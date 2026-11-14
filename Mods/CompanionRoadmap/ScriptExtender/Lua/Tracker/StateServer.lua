-- =============================================================================
-- Tracker/StateServer.lua  (server only)
-- Keeps every connected player's roadmap up to date:
--   * clients say Hello (and whether their window is open)
--   * Osiris events for watched flags / journal steps / approval mark the state dirty
--   * a short debounce later, each player gets a fresh snapshot (if their window is
--     open) and "completed / missed" toasts for steps that changed; toasts wait
--     until that player is out of a conversation
--   * manual check-offs are stored per savegame in a mod variable
--   * "!roadmap report" (or the button in Options) writes what the tracker sees to
--     a file for bug reports
-- =============================================================================

CR.Server = CR.Server or {}
local Srv = CR.Server
local Guides = CR.Guides
local S = CR.Status

local DEBOUNCE_MS = 400
local TOAST_RETRY_MS = 3000       -- re-check while a player is still in a conversation
local TOAST_MAX_WAIT_MS = 120000  -- never hold a notice longer than this
local REPORT_FILE = "CompanionRoadmap/report.json"

Srv.Peers = {}            -- peerId -> { open = bool, last = { stepId -> status }, baseline = bool }
Srv.Ready = false
Srv.DirtyPending = false
Srv.Overrides = {}        -- fallback when mod variables are unavailable

-- -----------------------------------------------------------------------------
-- Manual overrides (persisted in the savegame through a mod variable)
-- -----------------------------------------------------------------------------
local function modVars()
    if not (Ext.Vars and Ext.Vars.GetModVariables) then return nil end
    local ok, vars = pcall(Ext.Vars.GetModVariables, ModuleUUID)
    if ok then return vars end
    return nil
end

function Srv.GetOverrides()
    local vars = modVars()
    local t = vars and vars.Overrides
    if type(t) == "table" then return t end
    return Srv.Overrides
end

function Srv.SetOverride(stepId, value)
    if type(stepId) ~= "string" or not Guides.StepById[stepId] then return false end
    local current = CR.ShallowCopy(Srv.GetOverrides())
    current[stepId] = value and true or nil
    local vars = modVars()
    if vars then
        -- reassign the whole table so the variable manager notices the change
        local ok = pcall(function() vars.Overrides = current end)
        if ok then return true end
    end
    Srv.Overrides = current
    return true
end

function Srv.ClearOverrides()
    local vars = modVars()
    if vars then pcall(function() vars.Overrides = {} end) end
    Srv.Overrides = {}
end

-- -----------------------------------------------------------------------------
-- Which avatar belongs to a client?
-- -----------------------------------------------------------------------------
local function osi(fn, ...)
    if fn == nil then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

function Srv.AvatarForPeer(peer)
    local userId = CR.PeerToUserId(peer)
    if userId then
        local ok, rows = pcall(function() return Osi.DB_Avatars:Get(nil) end)
        if ok and type(rows) == "table" then
            for _, row in ipairs(rows) do
                local avatar = row[1]
                if osi(Osi.GetReservedUserID, avatar) == userId then return avatar end
            end
        end
        local current = osi(Osi.GetCurrentCharacter, userId)
        if type(current) == "string" and current ~= "" then return current end
    end
    local host = osi(Osi.GetHostCharacter)
    if type(host) == "string" and host ~= "" then return host end
    return nil
end

-- -----------------------------------------------------------------------------
-- Readiness: Osiris must be running before we can read the save
-- -----------------------------------------------------------------------------
function Srv.CheckReady()
    if Srv.Ready then return true end
    local host = osi(Osi.GetHostCharacter)
    if type(host) == "string" and host ~= "" and CR.Eval.CurrentLevel(host) then
        Srv.Ready = true
    end
    return Srv.Ready
end

-- -----------------------------------------------------------------------------
-- Snapshots, diffs and toasts
-- -----------------------------------------------------------------------------
-- Completed steps are always worth a notice; missed ones only when they were
-- important and not optional (a romance you never started is not news).
local function toastWorthy(step, now)
    if now == S.DONE then return true end
    if now == S.MISSED then
        return step.critical and not step.optional and not step.romanceStart
    end
    return false
end

local function diff(last, snap)
    local items = {}
    if not last then return items end
    for id, r in pairs(snap.steps) do
        local now, before = r[1], last[id]
        local step = Guides.StepById[id]
        if step and before ~= nil and before ~= now and before ~= S.OVERRIDE and toastWorthy(step, now) then
            local owner = Guides.StepOwner[id]
            table.insert(items, { c = owner and owner.id or "?", id = id, s = now })
        end
    end
    table.sort(items, function(a, b)
        return (Guides.StepIndex[a.id] or 0) < (Guides.StepIndex[b.id] or 0)
    end)
    return items
end

local function statusMap(snap)
    local m = {}
    for id, r in pairs(snap.steps) do m[id] = r[1] end
    return m
end

-- -----------------------------------------------------------------------------
-- Toast delivery: never interrupt a conversation or a camp scene
-- -----------------------------------------------------------------------------
local function inDialog(avatar)
    return avatar ~= nil and CR.Eval.DbHasRows("DB_DialogPlayers", nil, avatar, nil)
end

local function queueToasts(p, items)
    p.pending = p.pending or {}
    p.pendingSince = p.pendingSince or CR.Now()
    for _, item in ipairs(items) do
        -- one notice per step: the latest status wins
        for i = #p.pending, 1, -1 do
            if p.pending[i].id == item.id then table.remove(p.pending, i) end
        end
        table.insert(p.pending, item)
    end
end

--- Sends queued notices to every player who is not in a conversation right now.
function Srv.DeliverToasts()
    if Srv.ToastTimer then CR.CancelTimer(Srv.ToastTimer) end
    Srv.ToastTimer = nil
    local waiting = false
    for peer, p in pairs(Srv.Peers) do
        if p.pending and #p.pending > 0 then
            local held = CR.Now() - (p.pendingSince or 0)
            if held < TOAST_MAX_WAIT_MS and inDialog(Srv.AvatarForPeer(peer)) then
                waiting = true
            else
                local items = p.pending
                p.pending, p.pendingSince = nil, nil
                pcall(function() CR.Net.Toast:SendToClient({ items = items }, peer) end)
            end
        end
    end
    if waiting then
        Srv.ToastTimer = CR.After(TOAST_RETRY_MS, function()
            Srv.ToastTimer = nil
            CR.Guard("toasts", Srv.DeliverToasts)
        end)
    end
end

function Srv.RefreshPeer(peer, forceSend)
    local p = Srv.Peers[peer]
    if not p then return end
    if not Srv.CheckReady() then
        if forceSend and CR.Net.Ready then
            pcall(function() CR.Net.State:SendToClient({ p = CR.Protocol, ready = false }, peer) end)
        end
        return
    end
    local avatar = Srv.AvatarForPeer(peer)
    local snap = CR.Eval.BuildSnapshot(avatar, Srv.GetOverrides())
    if p.open or forceSend then
        local ok, err = pcall(function() CR.Net.State:SendToClient(snap, peer) end)
        if not ok then CR.Debug("send to %s failed: %s", tostring(peer), tostring(err)) end
    end
    if not p.baseline then
        local items = diff(p.last, snap)
        if #items > 0 then
            queueToasts(p, items)
            Srv.DeliverToasts()
        end
    end
    p.last = statusMap(snap)
    p.baseline = false
end

function Srv.Flush()
    Srv.DirtyPending = false
    for peer in pairs(Srv.Peers) do
        CR.Guard("refresh", Srv.RefreshPeer, peer, false)
    end
end

function Srv.MarkDirty()
    if Srv.DirtyPending then return end
    if next(Srv.Peers) == nil then return end
    Srv.DirtyPending = true
    CR.After(DEBOUNCE_MS, function() CR.Guard("flush", Srv.Flush) end)
end

-- -----------------------------------------------------------------------------
-- Network handlers
-- -----------------------------------------------------------------------------
local function onHello(msg, peer)
    msg = type(msg) == "table" and msg or {}
    local p = Srv.Peers[peer]
    if not p then
        p = { open = false, last = nil, baseline = true }
        Srv.Peers[peer] = p
    end
    if msg.open ~= nil then p.open = msg.open and true or false end
    if msg.want or msg.open then
        Srv.RefreshPeer(peer, true)
    elseif p.last == nil and Srv.CheckReady() then
        -- establish the toast baseline quietly
        Srv.RefreshPeer(peer, false)
    end
end

local function onOverride(msg, peer)
    if type(msg) ~= "table" or type(msg.id) ~= "string" then return end
    local changed
    if msg.id == "*" then
        Srv.ClearOverrides()
        changed = true
    else
        changed = Srv.SetOverride(msg.id, msg.value)
    end
    if changed then
        -- a manual change should not produce a toast for anyone
        for _, p in pairs(Srv.Peers) do p.baseline = true end
        Srv.Flush()
    end
end

-- -----------------------------------------------------------------------------
-- Osiris listeners: only react to things the guides actually watch
-- -----------------------------------------------------------------------------
local tracked = {}
for _, comp in ipairs(Guides.Companions) do tracked[comp.uuid] = true end

local function isTrackedCharacter(ch)
    local g = CR.Guid(ch)
    return g ~= nil and tracked[g] == true
end

local function onFlag(flag)
    local g = CR.Guid(flag)
    if g and Guides.WatchedFlags[g] then Srv.MarkDirty() end
end

local function listen(event, arity, fn)
    local ok, err = pcall(Ext.Osiris.RegisterListener, event, arity, "after", function(...)
        CR.Guard(event, fn, ...)
    end)
    if not ok then CR.Warn("Could not listen to %s/%d: %s", event, arity, tostring(err)) end
end

function Srv.Init()
    if not CR.Net.Ready then return end
    CR.Net.Hello:SetHandler(function(msg, peer) CR.Guard("Hello", onHello, msg, peer) end)
    CR.Net.Override:SetHandler(function(msg, peer) CR.Guard("Override", onOverride, msg, peer) end)
    CR.Net.Report:SetHandler(function(_, peer)
        CR.Guard("Report", function()
            local ok, info = Srv.WriteReport(Srv.AvatarForPeer(peer))
            pcall(function() CR.Net.Report:SendToClient({ ok = ok, info = info, file = REPORT_FILE }, peer) end)
        end)
    end)

    listen("FlagSet", 3, function(flag) onFlag(flag) end)
    listen("FlagCleared", 3, function(flag) onFlag(flag) end)
    listen("QuestUpdateUnlocked", 3, function(_, quest)
        if Guides.WatchedQuests[quest] then Srv.MarkDirty() end
    end)
    listen("ApprovalRatingChanged", 3, function(npc)
        if isTrackedCharacter(npc) then Srv.MarkDirty() end
    end)
    for _, ev in ipairs({ "Died", "Resurrected", "CharacterJoinedParty", "CharacterLeftParty" }) do
        listen(ev, 1, function(ch) if isTrackedCharacter(ch) then Srv.MarkDirty() end end)
    end
    -- a conversation just ended: deliver the notices that were waiting for it
    listen("DialogEnded", 2, function()
        for _, p in pairs(Srv.Peers) do
            if p.pending and #p.pending > 0 then
                CR.After(800, function() CR.Guard("toasts", Srv.DeliverToasts) end)
                return
            end
        end
    end)
    listen("LevelGameplayStarted", 2, function()
        Srv.Ready = false
        Srv.CheckReady()
        -- the save just (re)loaded: rebuild baselines without toasting
        for _, p in pairs(Srv.Peers) do p.baseline = true end
        Srv.Flush()
    end)

    Ext.Events.ResetCompleted:Subscribe(function() Srv.CheckReady() end)

    Srv.RegisterConsole()
end

-- -----------------------------------------------------------------------------
-- Report: everything the tracker sees, as one JSON file.
-- Attach it to a bug report; tools/test_harness.py can replay it as a test.
-- It holds game identifiers only: no names, no account or system details.
-- -----------------------------------------------------------------------------

--- Reads every flag and journal step the guides watch, on every target the flag
--- allows, so the report also shows what was NOT set.
local function probeEverything(ctx)
    local function probe(cond, comp)
        if type(cond) ~= "table" then return end
        if cond.k == "f" then
            local entry = CR.Flags[cond.name]
            if entry then
                local guid, usage = entry[1], entry[2] or 0
                if usage & 1 ~= 0 then ctx:Flag(guid, CR.NULL) end
                if usage & 4 ~= 0 then
                    if ctx.avatar then ctx:Flag(guid, ctx.avatar) end
                    if comp then ctx:Flag(guid, comp.uuid) end
                end
            end
        elseif cond.k == "q" then
            ctx:Quest(cond.quest, cond.step)
        elseif cond.k == "any" or cond.k == "all" then
            for _, c in ipairs(cond.list or {}) do probe(c, comp) end
        elseif cond.k == "not" then
            probe(cond.c, comp)
        end
    end
    for _, comp in ipairs(Guides.Companions) do
        probe(comp.recruited, comp)
        for _, c in ipairs(comp.left) do probe(c, comp) end
        if comp.romance then
            for _, key in ipairs({ "dating", "partnered", "ex" }) do probe(comp.romance[key], comp) end
            local closed = comp.romance.closed
            if type(closed) == "table" then
                if closed.k then probe(closed, comp) else for _, c in ipairs(closed) do probe(c, comp) end end
            end
        end
        for _, counter in ipairs(comp.counters) do
            for _, item in ipairs(counter.items or {}) do probe(item.cond, comp) end
            probe(counter.reached, comp)
        end
        for _, step in ipairs(comp.steps) do
            for _, list in ipairs({ step.done, step.fail, step.skip }) do
                for _, c in ipairs(list) do probe(c, comp) end
            end
        end
    end
end

--- Up to `limit` rows of a database with `columns` columns, mapped through `pick`.
local function dbDump(name, columns, pick, limit)
    local rows = CR.Eval.DbRows(name, table.unpack({}, 1, columns))
    local out = {}
    for i, row in ipairs(rows or {}) do
        if i > (limit or 400) then break end
        out[#out + 1] = pick(row)
    end
    return out
end

function Srv.BuildReport(avatar)
    local E = CR.Eval
    local snap, ctx = E.BuildSnapshot(avatar, Srv.GetOverrides())
    probeEverything(ctx)

    local flags, quests = {}, {}
    for key, value in pairs(ctx.cache) do
        if value == true then
            if string.sub(key, 1, 2) == "q:" then
                quests[#quests + 1] = string.sub(key, 3)
            elseif string.find(key, "@", 1, true) then
                local guid, target = string.match(key, "^(.-)@(.*)$")
                flags[#flags + 1] = guid .. "@" .. (CR.Guid(target) or target)
            end
        end
    end
    table.sort(flags)
    table.sort(quests)

    local companions = {}
    for _, comp in ipairs(Guides.Companions) do
        ctx.comp = comp
        local approval = avatar and osi(Osi.GetApprovalRating, comp.uuid, avatar) or nil
        companions[comp.id] = {
            uuid = comp.uuid,
            dead = ctx:IsDead(comp),
            perma = ctx:IsPermaDefeated(comp),
            team = E.DbHasRows("DB_PartOfTheTeam", comp.uuid),
            ko = ctx:KnockedOut(comp),
            approval = type(approval) == "number" and math.floor(approval) or nil,
            dating = avatar ~= nil and E.DbHasRows("DB_ORI_Dating", avatar, comp.uuid),
            partnered = avatar ~= nil and E.DbHasRows("DB_ORI_Partnered", avatar, comp.uuid),
            info = snap.comps[comp.id],
        }
    end
    ctx.comp = nil

    local overrides = {}
    for id, v in pairs(Srv.GetOverrides()) do if v then overrides[#overrides + 1] = id end end
    table.sort(overrides)

    local function version(fn)
        if not fn then return nil end
        local ok, v = pcall(fn)
        if ok and v ~= nil then return tostring(v) end
        return nil
    end

    local report = {
        format = 1,
        mod = CR.Version,
        se = version(Ext.Utils and Ext.Utils.Version),
        game = version(Ext.Utils and Ext.Utils.GameVersion),
        level = snap.level,
        act = snap.act,
        markers = snap.markers,
        avatar = avatar and CR.Guid(avatar) or nil,
        overrides = overrides,
        steps = snap.steps,
        raw = { flags = flags, quests = quests, companions = companions },
    }

    -- the camp scheduler, for the "tonight at camp" work (best effort)
    local okCamp, camp = pcall(function()
        return {
            nights = dbDump("DB_CampNight", 2, function(r) return { tostring(r[1]), r[2] } end),
            completed = dbDump("DB_CampNight_Completed", 1, function(r) return tostring(r[1]) end),
            expiring = dbDump("DB_CampNight_StartedExpiring", 2, function(r) return { tostring(r[1]), r[2] } end),
        }
    end)
    if okCamp then report.camp = camp end
    return report
end

--- Writes the report next to the mod's settings. Returns ok, short description.
function Srv.WriteReport(avatar)
    if not Srv.CheckReady() then return false, "The game is not ready yet - load a save first." end
    local ok, report = pcall(Srv.BuildReport, avatar)
    if not ok then return false, "Could not build the report: " .. tostring(report) end
    local okJson, json = pcall(Ext.Json.Stringify, report)
    if not okJson or type(json) ~= "string" then return false, "Could not encode the report." end
    if not (Ext.IO and Ext.IO.SaveFile) then return false, "This Script Extender version cannot write files." end
    local okSave = pcall(Ext.IO.SaveFile, REPORT_FILE, json)
    if not okSave then return false, "Could not write the report file." end
    return true, string.format("%d steps, %d flags, %d journal entries", CR.Count(report.steps),
        #report.raw.flags, #report.raw.quests)
end

-- -----------------------------------------------------------------------------
-- Console: !roadmap [diag|steps <Companion>|report|resetoverrides|debug]
-- -----------------------------------------------------------------------------
local STATUS_NAMES = {
    D = "done", O = "checked", N = "NEXT", A = "available", P = "pending",
    U = "upcoming", M = "MISSED", X = "n/a", I = "incomplete",
}

function Srv.RegisterConsole()
    if not Ext.RegisterConsoleCommand then return end
    Ext.RegisterConsoleCommand("roadmap", function(_, sub, arg)
        sub = string.lower(sub or "diag")
        if sub == "debug" then
            CR.Verbose = not CR.Verbose
            CR.Info("Verbose logging %s (server).", CR.Verbose and "ON" or "OFF")
        elseif sub == "resetoverrides" then
            Srv.ClearOverrides()
            for _, p in pairs(Srv.Peers) do p.baseline = true end
            Srv.Flush()
            CR.Info("All manual check-offs cleared for this save.")
        elseif sub == "report" then
            local ok, info = Srv.WriteReport(Srv.AvatarForPeer(nil))
            if ok then
                CR.Info("Report written (%s) to the Script Extender folder:", info)
                CR.Info("  Script Extender/%s", REPORT_FILE)
            else
                CR.Warn("%s", info)
            end
        elseif sub == "steps" then
            local comp = Guides.Get(arg or "")
            if not comp then CR.Info("Usage: !roadmap steps <Shadowheart|Minthara|...>") return end
            local snap = CR.Eval.BuildSnapshot(Srv.AvatarForPeer(nil), Srv.GetOverrides())
            for _, step in ipairs(comp.steps) do
                local r = snap.steps[step.id] or { "?" }
                CR.Info("  [%-10s] A%d %s - %s", STATUS_NAMES[r[1]] or r[1], step.act, step.id, step.title)
            end
        else
            Srv.CheckReady()
            local avatar = Srv.AvatarForPeer(nil)
            CR.Info("%s v%s - server diagnostics", CR.ModName, CR.Version)
            CR.Info("  data: %d companions, %d watched flags, %d watched quests, %d data errors",
                #Guides.Companions, CR.Count(Guides.WatchedFlags), CR.Count(Guides.WatchedQuests), #Guides.Errors)
            CR.Info("  ready=%s avatar=%s clients=%d overrides=%d", tostring(Srv.Ready), tostring(avatar),
                CR.Count(Srv.Peers), CR.Count(Srv.GetOverrides()))
            if Srv.Ready then
                local snap = CR.Eval.BuildSnapshot(avatar, Srv.GetOverrides())
                CR.Info("  level=%s act=%s", tostring(snap.level), tostring(snap.act))
                for _, comp in ipairs(Guides.Companions) do
                    local info = snap.comps[comp.id] or {}
                    local counts = {}
                    for _, step in ipairs(comp.steps) do
                        local s = (snap.steps[step.id] or {})[1] or "?"
                        counts[s] = (counts[s] or 0) + 1
                    end
                    CR.Info("  %-12s approval=%-4s rel=%-9s recruited=%-5s done=%d next=%d missed=%d",
                        comp.name, tostring(info.a or "-"), tostring(info.rel or "-"), tostring(info.rec),
                        (counts.D or 0) + (counts.O or 0), counts.N or 0, counts.M or 0)
                end
            end
            for _, e in ipairs(Guides.Errors) do CR.Warn("  data error: %s", e) end
        end
    end)
end
