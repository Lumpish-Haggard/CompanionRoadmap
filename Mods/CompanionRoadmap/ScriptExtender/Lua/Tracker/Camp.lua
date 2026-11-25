-- =============================================================================
-- Tracker/Camp.lua  (server only)
-- "Tonight at camp": which camp scenes the game would play at your next long
-- rest, and what holds back the ones the guide is waiting for.
--
-- The game schedules camp scenes in the story goal GLO_CampNights. Each scene is a
-- global NIGHT_* flag registered in DB_CampNight(flag, priority) together with the
-- camps it can play in and its requirements. A scene that has played or was
-- cancelled is removed from all of these tables, so what is left is exactly what
-- the scheduler still considers. At a long rest, PROC_CampNight_DecideCampNight
-- first drops scenes whose time ran out, then repeatedly picks the most important
-- scene that meets its requirements and does not clash with the scenes already
-- picked. This file reads the same tables and repeats that selection, so it never
-- has to know the scenes in advance.
--
-- Read-only: the story's own queries are never called (some need you to be in
-- camp already). What cannot be known before the rest (a few scenes adjust their
-- requirements at the last moment, characters who cannot talk right then) makes
-- this a prediction, and the window says so.
-- =============================================================================

CR.Camp = CR.Camp or {}
local Camp = CR.Camp
local Guides = CR.Guides

local NULL_GUID = "00000000-0000-0000-0000-000000000000"

-- -----------------------------------------------------------------------------
-- Guide steps that a camp scene completes: night flag GUID -> { step ids }.
-- A step whose camp scene only proves that something else happened says so with
-- `campScene = false` (the Grove's celebration on "Save the Grove").
-- -----------------------------------------------------------------------------
Camp.StepsByNight = {}

local function collectNights(cond, out)
    if type(cond) ~= "table" then return end
    if cond.k == "f" and type(cond.name) == "string" and string.sub(cond.name, 1, 6) == "NIGHT_" then
        local g = Guides.FlagGuid(cond.name)
        if g then out[#out + 1] = g end
    elseif cond.k == "any" or cond.k == "all" then
        for _, c in ipairs(cond.list or {}) do collectNights(c, out) end
    end
end

for _, comp in ipairs(Guides.Companions) do
    for _, step in ipairs(comp.steps) do
        local nights = {}
        if step.campScene ~= false then
            for _, c in ipairs(step.done) do collectNights(c, nights) end
        end
        local seen = {}
        for _, g in ipairs(nights) do
            if not seen[g] then
                seen[g] = true
                Camp.StepsByNight[g] = Camp.StepsByNight[g] or {}
                table.insert(Camp.StepsByNight[g], step.id)
            end
        end
    end
end

-- Requirement flags that a guide step completes: flag GUID -> step id. Lets the
-- window say "needs: <step>" instead of "a story moment".
Camp.StepByFlag = {}
local function collectFlags(cond, stepId)
    if type(cond) ~= "table" then return end
    if cond.k == "f" then
        local g = Guides.FlagGuid(cond.name)
        if g and not Camp.StepByFlag[g] then Camp.StepByFlag[g] = stepId end
    elseif cond.k == "any" or cond.k == "all" then
        for _, c in ipairs(cond.list or {}) do collectFlags(c, stepId) end
    end
end
for _, comp in ipairs(Guides.Companions) do
    for _, step in ipairs(comp.steps) do
        for _, c in ipairs(step.done) do collectFlags(c, step.id) end
    end
end

-- -----------------------------------------------------------------------------
-- Reading the scheduler's tables
-- -----------------------------------------------------------------------------
local function osi(fn, ...)
    if fn == nil then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function rows(db, columns)
    return CR.Eval.DbRows(db, table.unpack({}, 1, columns)) or {}
end

local function key(v)
    local g = CR.Guid(v)
    if g == nil or g == NULL_GUID then return nil end
    return g
end

local function push(t, k, v)
    if k == nil then return end
    t[k] = t[k] or {}
    table.insert(t[k], v)
end

--- Everything the scheduler knows right now, keyed by night GUID.
function Camp.Read()
    local W = {
        nights = {}, byGuid = {}, camps = {}, req = {}, approval = {}, partner = {}, dating = {},
        startDating = {}, sameUser = {}, cancelledBy = {}, expires = {}, expiring = {}, exclusive = {}, crd = {},
        evening = {}, morning = {}, sleepExclusive = {}, sco = {}, solo = {}, romance = {}, avatarDream = {},
    }
    for i, r in ipairs(rows("DB_CampNight", 2)) do
        local g = key(r[1])
        if g and type(r[2]) == "number" then
            local n = { g = g, raw = r[1], p = r[2], i = i }
            table.insert(W.nights, n)
            W.byGuid[g] = n
        end
    end
    for _, r in ipairs(rows("DB_CampNight_Camp", 2)) do
        local g = key(r[1])
        if g then
            W.camps[g] = W.camps[g] or {}
            W.camps[g][tostring(r[2])] = true
        end
    end
    -- DB_CampNight_Requirement(night, flag1 .. flag7): each row is one set of flags
    -- that must all be set; any one row is enough
    for arity = 1, 7 do
        for _, r in ipairs(rows("DB_CampNight_Requirement", arity + 1)) do
            local flags = {}
            for i = 2, arity + 1 do flags[#flags + 1] = r[i] end
            push(W.req, key(r[1]), flags)
        end
    end
    for _, r in ipairs(rows("DB_CampNight_Requirement_Approval", 3)) do
        push(W.approval, key(r[1]), { c = r[2], min = tonumber(r[3]) or 0 })
    end
    for _, r in ipairs(rows("DB_CampNight_Requirement_Partner", 2)) do push(W.partner, key(r[1]), r[2]) end
    for _, r in ipairs(rows("DB_CampNight_Requirement_Dating", 2)) do push(W.dating, key(r[1]), r[2]) end
    for _, r in ipairs(rows("DB_CampNight_Requirement_CanStartDating", 2)) do push(W.startDating, key(r[1]), r[2]) end
    for _, r in ipairs(rows("DB_CampNight_Requirement_SameUser", 3)) do push(W.sameUser, key(r[1]), { r[2], r[3] }) end
    -- setting one of these flags removes the scene (only watched, to refresh in time)
    for _, r in ipairs(rows("DB_CampNight_CancelledBy", 2)) do push(W.cancelledBy, key(r[1]), r[2]) end
    for _, r in ipairs(rows("DB_CampNight_ExpiresAfter", 2)) do
        local g = key(r[1])
        if g then W.expires[g] = tonumber(r[2]) end
    end
    for _, r in ipairs(rows("DB_CampNight_StartedExpiring", 2)) do
        local g = key(r[1])
        if g then W.expiring[g] = tonumber(r[2]) end
    end
    for _, r in ipairs(rows("DB_CampNight_ExclusiveMoment", 1)) do
        local g = key(r[1])
        if g then W.exclusive[g] = true end
    end
    -- what each scene consists of: which speakers it needs, and whether it takes the
    -- whole evening, night or morning for itself
    for _, r in ipairs(rows("DB_CampNight_CRD", 4)) do push(W.crd, key(r[1]), { s = r[2], f = r[4] }) end
    for _, db in ipairs({ { "DB_CampNight_CFM", 2 }, { "DB_CampNight_IVB", 3 } }) do
        for _, r in ipairs(rows(db[1], db[2])) do
            local g = key(r[1])
            if g then W.evening[g] = true end
        end
    end
    for _, db in ipairs({ { "DB_CampNight_MorningIVB", 3 }, { "DB_CampNight_MorningCFM", 2 } }) do
        for _, r in ipairs(rows(db[1], db[2])) do
            local g = key(r[1])
            if g then W.morning[g] = true end
        end
    end
    for _, r in ipairs(rows("DB_CampNight_SCO", 2)) do
        local g = key(r[1])
        if g then
            W.sleepExclusive[g] = true
            W.sco[g] = true
        end
    end
    for _, r in ipairs(rows("DB_CampNight_AvatarDream", 2)) do
        local g = key(r[1])
        if g then
            W.sleepExclusive[g] = true
            W.avatarDream[g] = true
        end
    end
    for _, r in ipairs(rows("DB_CampNight_SoloDream", 3)) do push(W.solo, key(r[1]), r[2]) end
    for _, r in ipairs(rows("DB_CampNight_RomanceNight", 4)) do push(W.romance, key(r[1]), { c = r[2], f = r[4] }) end

    local active = CR.Eval.DbFirstValue("DB_ActiveCamp", nil)
    W.active = type(active) == "string" and active ~= "" and active or nil
    W.unlocked = CR.Eval.DbHasRows("DB_Camp_Unlocked", 1)
    W.fallback = CR.Eval.DbHasRows("DB_FallbackCamp_InCamp", nil)
    W.disabled = CR.Eval.DbHasRows("DB_CampNight_DEBUG_Disabled", 1)
    return W
end

-- -----------------------------------------------------------------------------
-- Facts about the party (cached for one prediction)
-- -----------------------------------------------------------------------------
local function newFacts(avatar)
    local F = { cache = {} }
    local avatars = {}
    for _, r in ipairs(rows("DB_Avatars", 1)) do avatars[#avatars + 1] = r[1] end
    if #avatars == 0 and avatar then avatars[1] = avatar end
    F.avatars = avatars
    local isAvatar = {}
    for _, a in ipairs(avatars) do
        local g = CR.Guid(a)
        if g then isAvatar[g] = true end
    end

    local function cached(k, fn)
        local v = F.cache[k]
        if v == nil then
            v = fn() and true or false
            F.cache[k] = v
        end
        return v
    end

    function F.isAvatar(c) return isAvatar[CR.Guid(c) or ""] == true end
    function F.global(flag)
        return cached("g:" .. tostring(flag), function() return osi(Osi.GetFlag, flag, CR.NULL) == 1 end)
    end
    function F.flagOn(flag, target)
        return cached("f:" .. tostring(flag) .. "@" .. tostring(target), function() return osi(Osi.GetFlag, flag, target) == 1 end)
    end
    function F.alive(c)
        return cached("alive:" .. tostring(c), function() return osi(Osi.IsDead, c) ~= 1 end)
    end
    --- Will this character be at camp when you rest? Everyone in your team goes there;
    --- others (camp followers) only if they are there already.
    function F.inCamp(c)
        return cached("camp:" .. tostring(c), function()
            if F.isAvatar(c) then return true end
            local there = CR.Eval.DbHasRows("DB_PartOfTheTeam", c) or CR.Eval.DbHasRows("DB_InCamp", c)
            return there and F.alive(c)
        end)
    end
    function F.approval(c, av)
        local k = "a:" .. tostring(c) .. "@" .. tostring(av)
        local v = F.cache[k]
        if v == nil then
            v = osi(Osi.GetApprovalRating, c, av)
            v = type(v) == "number" and math.floor(v) or false
            F.cache[k] = v
        end
        return v or nil
    end
    function F.partnered(av, c)
        return cached("p:" .. tostring(av) .. "@" .. tostring(c), function() return CR.Eval.DbHasRows("DB_ORI_Partnered", av, c) end)
    end
    function F.partneredAny(av)
        return cached("p:" .. tostring(av), function() return CR.Eval.DbHasRows("DB_ORI_Partnered", av, nil) end)
    end
    function F.partneredOther(av, c)
        local g = CR.Guid(c)
        for _, r in ipairs(CR.Eval.DbRows("DB_ORI_Partnered", av, nil) or {}) do
            if CR.Guid(r[2]) ~= g then return true end
        end
        return false
    end
    function F.dating(av, c)
        return cached("d:" .. tostring(av) .. "@" .. tostring(c), function() return CR.Eval.DbHasRows("DB_ORI_Dating", av, c) end)
    end
    function F.anyoneDating(c)
        return cached("d:*@" .. tostring(c), function() return CR.Eval.DbHasRows("DB_ORI_Dating", nil, c) end)
    end
    function F.wasDating(av, c)
        return cached("w:" .. tostring(av) .. "@" .. tostring(c), function() return CR.Eval.DbHasRows("DB_ORI_WasDating", av, c) end)
    end
    return F
end

-- -----------------------------------------------------------------------------
-- QRY_CampNight_MeetsRequirements, rule by rule. Each check returns ok, and when
-- not ok, why (a blocker the window can put in words).
-- -----------------------------------------------------------------------------
local function compId(c)
    local comp = Guides.ByUuid[CR.Guid(c) or ""]
    return comp and comp.id or nil
end

local function flagsOk(W, F, g)
    local alts = W.req[g]
    if not alts or #alts == 0 then return true end
    local best = nil
    for _, flags in ipairs(alts) do
        local missing = {}
        for _, f in ipairs(flags) do
            if not F.global(f) then missing[#missing + 1] = f end
        end
        if #missing == 0 then return true end
        if not best or #missing < #best then best = missing end
    end
    -- the set closest to complete says what is still missing
    local step = nil
    for _, f in ipairs(best or {}) do
        step = step or Camp.StepByFlag[CR.Guid(f) or ""]
    end
    return false, { "f", #(best or {}), step }
end

--- Any one row is enough: that companion is at camp and approves of some player
--- at least this much.
local function approvalOk(W, F, g, me)
    local reqs = W.approval[g]
    if not reqs or #reqs == 0 then return true end
    local low, away = nil, nil
    for _, r in ipairs(reqs) do
        if F.inCamp(r.c) and not F.isAvatar(r.c) then
            for _, av in ipairs(F.avatars) do
                local a = F.approval(r.c, av)
                if a and a >= r.min then return true end
            end
            -- `false`, not nil, for a character the guide does not know: no hole in the list
            low = low or { "a", compId(r.c) or false, r.min, me and F.approval(r.c, me) or nil }
        else
            away = away or { "t", compId(r.c) }
        end
    end
    return false, low or away
end

local function partnerOk(W, F, g)
    local reqs = W.partner[g]
    if not reqs or #reqs == 0 then return true end
    for _, c in ipairs(reqs) do
        for _, av in ipairs(F.avatars) do
            if F.partnered(av, c) then return true end
        end
    end
    return false, { "p", compId(reqs[1]) }
end

local function datingOk(W, F, g)
    local reqs = W.dating[g]
    if not reqs or #reqs == 0 then return true end
    for _, c in ipairs(reqs) do
        if not F.isAvatar(c) then
            for _, av in ipairs(F.avatars) do
                if F.dating(av, c) and not F.partneredOther(av, c) then return true end
            end
        end
    end
    return false, { "d", compId(reqs[1]) }
end

local DOUBLE_DATING = nil   -- the GUID of ORI_State_DoubleDating (Data/Flags.lua)

--- A romance can still begin: nobody is dating them yet, you are not partnered and
--- not already dating two, you never dated them before, and approval is strictly
--- above the scene's value.
local function startDatingOk(W, F, g, me)
    local reqs = W.startDating[g]
    if not reqs or #reqs == 0 then return true end
    DOUBLE_DATING = DOUBLE_DATING or Guides.FlagGuid("ORI_State_DoubleDating")
    local blocker = nil
    for _, c in ipairs(reqs) do
        if not F.anyoneDating(c) and not F.isAvatar(c) then
            for _, av in ipairs(F.avatars) do
                local free = not F.partneredAny(av)
                    and not (DOUBLE_DATING and F.flagOn(DOUBLE_DATING, av))
                    and not F.wasDating(av, c)
                local nightOk = true
                local rn = W.romance[g]
                if rn and #rn > 0 then
                    nightOk = false
                    for _, r in ipairs(rn) do
                        if key(r.f) == nil or F.flagOn(r.f, av) then nightOk = true break end
                    end
                end
                -- QRY_CampNight_MeetsRequirements_StartDating_Approval: no approval row
                -- for them, or one they are strictly above
                local approvalAbove, need = true, nil
                for _, r in ipairs(W.approval[g] or {}) do
                    if CR.Guid(r.c) == CR.Guid(c) then
                        if need == nil then approvalAbove = false end
                        need = need and math.min(need, r.min) or r.min
                        local a = F.approval(c, av)
                        if a and a > r.min then approvalAbove = true end
                    end
                end
                if free and nightOk and approvalAbove then return true end
                if not blocker or av == me then
                    if not free or not nightOk then
                        blocker = { "s", compId(c) }
                    else
                        blocker = { "a", compId(c) or false, (need or 0) + 1, me and F.approval(c, me) or nil }
                    end
                end
            end
        elseif not blocker then
            blocker = { "s", compId(c) }
        end
    end
    return false, blocker or { "s", compId(reqs[1]) }
end

--- Every requirement, in the order the game checks them. Returns ok, blockers.
local function meets(W, F, g, me)
    local blockers = {}
    local ok = true
    for _, check in ipairs({ flagsOk, approvalOk, partnerOk, datingOk, startDatingOk }) do
        local fine, why = check(W, F, g, me)
        if not fine then
            ok = false
            if why then blockers[#blockers + 1] = why end
        end
    end
    -- DB_CampNight_Requirement_SameUser only matters in multiplayer (two companions
    -- controlled by the same player); it is not predicted.
    return ok, blockers
end

--- QRY_CampNight_AllSpeakersMissing: a scene made only of conversations that need
--- someone who will not be at camp does not play.
local function allSpeakersMissing(W, F, g)
    -- campfire moments, barks, sleep cutscenes and morning moments always play
    if W.evening[g] or W.morning[g] or W.sco[g] then return false end
    for _, crd in ipairs(W.crd[g] or {}) do
        if key(crd.s) == nil then return false end
        if not F.isAvatar(crd.s) and F.inCamp(crd.s) then return false end
    end
    for _, c in ipairs(W.solo[g] or {}) do
        if F.isAvatar(c) then return false end
    end
    if W.avatarDream[g] then return false end
    for _, r in ipairs(W.romance[g] or {}) do
        if not F.isAvatar(r.c) and F.inCamp(r.c) then return false end
    end
    return true
end

-- -----------------------------------------------------------------------------
-- Selection: PROC_CampNight_DecideCampNight_Recursive
-- -----------------------------------------------------------------------------

--- PROC_CampNight_CacheSleepSpeakers: who a scene's sleep moment needs, or whether
--- it takes the whole night for itself.
local function sleepSpeakers(W, F, g)
    local individuals = {}
    local exclusive = W.sleepExclusive[g] == true
    for _, c in ipairs(W.solo[g] or {}) do individuals[CR.Guid(c) or tostring(c)] = true end
    for _, r in ipairs(W.romance[g] or {}) do
        local known = false
        for _, av in ipairs(F.avatars) do
            local together = (key(r.f) == nil and (F.partnered(av, r.c) or F.dating(av, r.c)))
                or (key(r.f) ~= nil and F.flagOn(r.f, av))
            if together then
                individuals[CR.Guid(r.c) or tostring(r.c)] = true
                individuals[CR.Guid(av) or tostring(av)] = true
                known = true
            end
        end
        if not known then exclusive = true end
    end
    return exclusive, individuals
end

local function clashes(W, F, g, queued, sleep)
    if #queued == 0 then return false end
    if W.exclusive[g] then return true end
    local myEx, mine = sleep(g)
    for _, q in ipairs(queued) do
        if W.exclusive[q] then return true end
        -- evening: one campfire moment or interactive bark at a time, no speaker twice
        if W.evening[q] and W.evening[g] then return true end
        for _, a in ipairs(W.crd[q] or {}) do
            for _, b in ipairs(W.crd[g] or {}) do
                if (CR.Guid(a.s) or "") == (CR.Guid(b.s) or "") then return true end
            end
        end
        -- night: exclusive dreams and romance nights, or the same sleeper twice
        local theirEx, theirs = sleep(q)
        if theirEx and myEx then return true end
        if theirEx and next(mine) ~= nil then return true end
        if myEx and next(theirs) ~= nil then return true end
        for who in pairs(mine) do
            if theirs[who] then return true end
        end
        -- morning: one moment only
        if W.morning[q] and W.morning[g] then return true end
    end
    return false
end

--- The scenes the game would queue at your next long rest, most important first.
local function select(W, F, eligible)
    local queued = {}
    local sleepCache = {}
    local function sleep(g)
        local c = sleepCache[g]
        if not c then
            local ex, ind = sleepSpeakers(W, F, g)
            c = { ex, ind }
            sleepCache[g] = c
        end
        return c[1], c[2]
    end
    local picked = {}
    while true do
        local best, bestPrio = nil, -1
        for _, n in ipairs(W.nights) do
            if eligible[n.g] and not picked[n.g] and n.p > bestPrio and not clashes(W, F, n.g, queued, sleep) then
                best, bestPrio = n, n.p
            end
        end
        if not best then break end
        picked[best.g] = true
        table.insert(queued, best.g)
    end
    return queued
end

-- -----------------------------------------------------------------------------
-- Describing a scene the guide does not cover
-- -----------------------------------------------------------------------------
local function describe(W, g)
    local romance = W.romance[g] and W.romance[g][1] and compId(W.romance[g][1].c)
    if romance then return { c = romance, r = 1 } end
    local names, seen = {}, {}
    for _, crd in ipairs(W.crd[g] or {}) do
        local id = compId(crd.s)
        if id and not seen[id] then seen[id] = true names[#names + 1] = id end
    end
    for _, c in ipairs(W.solo[g] or {}) do
        local id = compId(c)
        if id and not seen[id] then seen[id] = true names[#names + 1] = id end
    end
    if #names == 1 then return { c = names[1] } end
    if W.evening[g] then return { e = 1 } end           -- a moment around the campfire
    if W.avatarDream[g] then return { d = 1 } end       -- a dream
    if #names > 1 then return { e = 1 } end
    return {}
end

-- -----------------------------------------------------------------------------
-- The snapshot part
-- -----------------------------------------------------------------------------

--- What the window shows under "Tonight at camp" for one avatar.
--- {
---   ok = true | false, why = "locked" | "fallback" | "nocamp" | nil,
---   at = "<camp>",
---   tonight = { { s = "<step id>" } | { c = "<companion>", r = 1 } | { e = 1 } | { d = 1 } | {} , ... },
---   steps = { ["<step id>"] = { t = 1 (plays tonight), b = { blockers }, x = rests left } },
---   n = number of scenes the scheduler still holds
--- }
--- Blockers: { "a", companion, need, have } approval; { "p", companion } partner;
--- { "d", companion } dating; { "s", companion } a romance can no longer begin;
--- { "f", count, step } story moments still missing; { "t", companion } not at camp;
--- { "c" } another camp; { "q" } ready, another scene comes first; { "x" } dropped at the next rest.
function Camp.Build(avatar)
    local W = Camp.Read()
    local out = { ok = false, n = #W.nights, tonight = {}, steps = {} }
    if not W.unlocked then
        out.why = "locked"
        return out, W
    end
    if W.fallback or W.disabled then
        out.why = "fallback"
        return out, W
    end
    if not W.active then
        out.why = "nocamp"
        return out, W
    end
    out.ok = true
    out.at = W.active
    local F = newFacts(avatar)

    -- PROC_CampNight_CheckExpirationDates runs first: a scene whose time is up is
    -- dropped before anything is picked
    local dropped = {}
    for g, left in pairs(W.expiring) do
        if left <= 1 then dropped[g] = true end
    end

    local eligible, why, fulfilled = {}, {}, {}
    for _, n in ipairs(W.nights) do
        local g = n.g
        local blockers = {}
        local ok, b = meets(W, F, g, avatar)
        fulfilled[g] = ok           -- its time starts running once this holds, wherever you camp
        if dropped[g] then
            blockers[#blockers + 1] = { "x" }
        elseif not (W.camps[g] and W.camps[g][W.active]) then
            blockers[#blockers + 1] = { "c" }
        else
            if ok and allSpeakersMissing(W, F, g) then
                ok = false
                -- nobody it needs will be at camp: name the companion if it is one
                local who = nil
                for _, crd in ipairs(W.crd[g] or {}) do who = who or compId(crd.s) end
                for _, r in ipairs(W.romance[g] or {}) do who = who or compId(r.c) end
                b = { { "t", who } }
            end
            if ok then eligible[g] = true else blockers = b end
        end
        why[g] = blockers
    end

    local queued = select(W, F, eligible)
    local tonight = {}
    for _, g in ipairs(queued) do
        tonight[g] = true
        local steps = Camp.StepsByNight[g]
        local entry = steps and { s = steps[1] } or describe(W, g)
        entry.g = g          -- the scene's flag, for "!roadmap camp" and the report
        out.tonight[#out.tonight + 1] = entry
    end

    -- the guide's own scenes: tonight, or what holds them back
    for g, steps in pairs(Camp.StepsByNight) do
        local n = W.byGuid[g]
        if n then
            local entry = {}
            if tonight[g] then
                entry.t = 1
            elseif eligible[g] then
                entry.b = { { "q" } }
            else
                entry.b = why[g]
            end
            -- long rests at which it can still play: the count is lowered before each
            -- pick, and a scene at 1 is dropped
            local left = W.expiring[g]
            if left then
                entry.x = math.max(0, left - 1)
            elseif W.expires[g] and fulfilled[g] then
                entry.x = W.expires[g]          -- its time starts running at the next rest
            end
            for _, id in ipairs(steps) do out.steps[id] = entry end
        end
    end
    return out, W
end

--- Every flag a pending scene depends on: when one of them changes, "Tonight at
--- camp" may change too (StateServer listens for these as well as the guide's own).
function Camp.WatchedFlags(W)
    local set = {}
    if not W then return set end
    for _, n in ipairs(W.nights) do set[n.g] = true end
    for _, alts in pairs(W.req) do
        for _, flags in ipairs(alts) do
            for _, f in ipairs(flags) do
                local g = CR.Guid(f)
                if g then set[g] = true end
            end
        end
    end
    for _, list in pairs(W.romance) do
        for _, r in ipairs(list) do
            local g = key(r.f)
            if g then set[g] = true end
        end
    end
    for _, list in pairs(W.cancelledBy) do
        for _, f in ipairs(list) do
            local g = key(f)
            if g then set[g] = true end
        end
    end
    return set
end

--- The scheduler's tables as plain data (for the report file), so a report replays
--- to the same prediction.
function Camp.Export()
    local function dump(db, columns, limit)
        local out = {}
        for i, r in ipairs(rows(db, columns)) do
            if i > (limit or 600) then break end
            local row = {}
            for c = 1, columns do
                local v = r[c]
                row[c] = (type(v) == "number" or type(v) == "string") and v or tostring(v)
            end
            out[#out + 1] = row
        end
        return out
    end
    local t = {
        DB_CampNight = dump("DB_CampNight", 2),
        DB_CampNight_Camp = dump("DB_CampNight_Camp", 2),
        DB_CampNight_Requirement_Approval = dump("DB_CampNight_Requirement_Approval", 3),
        DB_CampNight_Requirement_Partner = dump("DB_CampNight_Requirement_Partner", 2),
        DB_CampNight_Requirement_Dating = dump("DB_CampNight_Requirement_Dating", 2),
        DB_CampNight_Requirement_CanStartDating = dump("DB_CampNight_Requirement_CanStartDating", 2),
        DB_CampNight_CancelledBy = dump("DB_CampNight_CancelledBy", 2),
        DB_CampNight_ExpiresAfter = dump("DB_CampNight_ExpiresAfter", 2),
        DB_CampNight_StartedExpiring = dump("DB_CampNight_StartedExpiring", 2),
        DB_CampNight_ExclusiveMoment = dump("DB_CampNight_ExclusiveMoment", 1),
        DB_CampNight_CRD = dump("DB_CampNight_CRD", 4),
        DB_CampNight_CFM = dump("DB_CampNight_CFM", 2),
        DB_CampNight_IVB = dump("DB_CampNight_IVB", 3),
        DB_CampNight_MorningIVB = dump("DB_CampNight_MorningIVB", 3),
        DB_CampNight_MorningCFM = dump("DB_CampNight_MorningCFM", 2),
        DB_CampNight_SCO = dump("DB_CampNight_SCO", 2),
        DB_CampNight_AvatarDream = dump("DB_CampNight_AvatarDream", 2),
        DB_CampNight_SoloDream = dump("DB_CampNight_SoloDream", 3),
        DB_CampNight_RomanceNight = dump("DB_CampNight_RomanceNight", 4),
        DB_CampNight_Completed = dump("DB_CampNight_Completed", 1),
        DB_ActiveCamp = dump("DB_ActiveCamp", 1),
        DB_Camp_Unlocked = dump("DB_Camp_Unlocked", 1),
        DB_InCamp = dump("DB_InCamp", 1),
        DB_ORI_WasDating = dump("DB_ORI_WasDating", 2),
    }
    for arity = 1, 7 do
        t["DB_CampNight_Requirement/" .. (arity + 1)] = dump("DB_CampNight_Requirement", arity + 1)
    end
    -- the requirement flags that are set (global), so the report can rebuild them
    local set = {}
    local W = Camp.Read()
    for _, alts in pairs(W.req) do
        for _, flags in ipairs(alts) do
            for _, f in ipairs(flags) do
                local g = CR.Guid(f)
                if g and not set[g] and osi(Osi.GetFlag, f, CR.NULL) == 1 then set[g] = true end
            end
        end
    end
    local flags = {}
    for g in pairs(set) do flags[#flags + 1] = g end
    table.sort(flags)
    t.flags = flags
    -- flags set on a player that the prediction reads: dating two already, and the
    -- flags romance nights wait for ("<flag guid>@<player guid>")
    local onPlayer = {}
    local checks = {}
    local dd = Guides.FlagGuid("ORI_State_DoubleDating")
    if dd then checks[#checks + 1] = dd end
    for _, list in pairs(W.romance) do
        for _, r in ipairs(list) do
            if key(r.f) then checks[#checks + 1] = r.f end
        end
    end
    for _, r in ipairs(rows("DB_Avatars", 1)) do
        for _, f in ipairs(checks) do
            if osi(Osi.GetFlag, f, r[1]) == 1 then
                onPlayer[#onPlayer + 1] = (CR.Guid(f) or tostring(f)) .. "@" .. (CR.Guid(r[1]) or tostring(r[1]))
            end
        end
    end
    table.sort(onPlayer)
    t.playerFlags = onPlayer
    return t
end
