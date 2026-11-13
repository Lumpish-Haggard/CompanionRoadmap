-- =============================================================================
-- Tracker/StateServer.lua  (server only)
-- Keeps every connected player's roadmap up to date:
--   * clients say Hello (and whether their window is open)
--   * Osiris events for watched flags / journal steps / approval mark the state dirty
--   * a short debounce later, each player gets a fresh snapshot (if their window is
--     open) and "completed / missed" toasts for steps that changed
--   * manual check-offs are stored per savegame in a mod variable
-- =============================================================================

CR.Server = CR.Server or {}
local Srv = CR.Server
local Guides = CR.Guides
local S = CR.Status

local DEBOUNCE_MS = 400

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
            pcall(function() CR.Net.Toast:SendToClient({ items = items }, peer) end)
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

    listen("FlagSet", 3, function(flag) onFlag(flag) end)
    listen("FlagCleared", 3, function(flag) onFlag(flag) end)
    listen("QuestUpdateUnlocked", 3, function(_, quest)
        if Guides.WatchedQuests[quest] then Srv.MarkDirty() end
    end)
    listen("ApprovalRatingChanged", 3, function(npc)
        if isTrackedCharacter(npc) then Srv.MarkDirty() end
    end)
    for _, ev in ipairs({ "Died", "CharacterJoinedParty", "CharacterLeftParty" }) do
        listen(ev, 1, function(ch) if isTrackedCharacter(ch) then Srv.MarkDirty() end end)
    end
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
-- Console: !roadmap [diag|steps <Companion>|resetoverrides|debug]
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
