-- =============================================================================
-- Tracker/ApprovalLog.lua  (server only)
-- The last approval changes per companion, kept in the savegame.
--
-- The game fires ApprovalRatingChanged(companion, player, new value) after every
-- change. The change itself is the difference with the value seen before, which
-- this file remembers per companion and player. When the player is in a
-- conversation at that moment, the conversation's main speaker is noted, so the
-- window can say "+2 talking with Zevlor". Long rests are counted, so it can also
-- say how long ago a change was.
--
-- Stored in the mod variable "Log":
--   { v = 1, rests = <long rests seen>,
--     approval = { ["<player guid>"] = { ["<companion guid>"] = {
--         { d = change or nil, v = new value, a = act, r = rests at the time,
--           c = "<companion id>" | h = "<localisation handle>" | nil (no conversation) }, ... } } } }
-- Newest entry last; at most MAX per companion and player.
-- =============================================================================

CR.ALog = CR.ALog or {}
local ALog = CR.ALog
local Guides = CR.Guides

local VERSION = 1
local MAX = 10

ALog.data = nil
ALog.last = {}          -- "<companion guid>@<player guid>" -> approval seen last (this session)

local function modVars()
    if not (Ext.Vars and Ext.Vars.GetModVariables) then return nil end
    local ok, vars = pcall(Ext.Vars.GetModVariables, ModuleUUID)
    if ok then return vars end
    return nil
end

local function fresh()
    return { v = VERSION, rests = 0, approval = {} }
end

--- A plain copy of what the save holds (the stored value may be a proxy).
local function readStored()
    local vars = modVars()
    local stored = vars and vars.Log
    local out = fresh()
    if type(stored) ~= "table" then return out end
    pcall(function()
        out.rests = tonumber(stored.rests) or 0
        for player, comps in pairs(stored.approval or {}) do
            if type(player) == "string" and type(comps) == "table" then
                out.approval[player] = {}
                for comp, list in pairs(comps) do
                    if type(comp) == "string" and type(list) == "table" then
                        local copy = {}
                        for _, e in ipairs(list) do
                            if type(e) == "table" and tonumber(e.v) then
                                copy[#copy + 1] = { d = tonumber(e.d), v = tonumber(e.v), a = tonumber(e.a) or 0,
                                    r = tonumber(e.r) or 0, c = type(e.c) == "string" and e.c or nil,
                                    h = type(e.h) == "string" and e.h or nil }
                            end
                        end
                        out.approval[player][comp] = copy
                    end
                end
            end
        end
    end)
    return out
end

--- (Re)reads the log of the current save. The values to measure changes against
--- come from the game itself (ALog.Baseline), never from the log: approval may
--- have changed while the mod was not looking.
function ALog.Load()
    ALog.data = readStored()
    ALog.last = {}
    return ALog.data
end

--- The log of the current save, read on first use. Unlike ALog.Load (a save was
--- loaded), this keeps the values the next change is measured against.
local function data()
    if not ALog.data then ALog.data = readStored() end
    return ALog.data
end

local function commit()
    local vars = modVars()
    if not vars then return end
    local d = data()
    local copy = { v = VERSION, rests = d.rests, approval = {} }
    for player, comps in pairs(d.approval) do
        copy.approval[player] = {}
        for comp, list in pairs(comps) do
            local l = {}
            for i, e in ipairs(list) do l[i] = { d = e.d, v = e.v, a = e.a, r = e.r, c = e.c, h = e.h } end
            copy.approval[player][comp] = l
        end
    end
    local ok, err = pcall(function() vars.Log = copy end)
    if not ok then CR.Debug("could not store the approval log: %s", tostring(err)) end
end

--- Reads the current approval of every companion towards every player, so the
--- next change can be measured. Called once the save can be read.
function ALog.Baseline(players)
    for _, player in ipairs(players or {}) do
        local pg = CR.Guid(player)
        if pg then
            for _, comp in ipairs(Guides.Companions) do
                local ok, a = pcall(Osi.GetApprovalRating, comp.uuid, player)
                if ok and type(a) == "number" then ALog.last[comp.uuid .. "@" .. pg] = math.floor(a) end
            end
        end
    end
end

local HANDLE = "(h%x+g%x+g%x+g%x+g%x+)"

--- The localisation handle of a character's name, or nil. The entity's DisplayName
--- (read the way the Script Extender's own tests do), else the story's GetDisplayName.
local function nameHandle(character)
    local g = CR.Guid(character)
    if g and Ext.Entity and Ext.Entity.Get then
        local ok, key = pcall(function()
            local e = Ext.Entity.Get(g)
            return e and e.DisplayName and e.DisplayName.NameKey
        end)
        local handle = ok and key ~= nil and string.match(tostring(key), HANDLE) or nil
        if handle then return handle end
    end
    local ok, name = pcall(Osi.GetDisplayName, character)
    if ok and name ~= nil then return string.match(tostring(name), HANDLE) end
    return nil
end

--- Who the player is talking to right now: a companion id, a localisation handle of
--- the main speaker's name, or nil when the player is not in a conversation.
local function speaker(player)
    local inst = nil
    for _, r in ipairs(CR.Eval.DbRows("DB_DialogPlayers", nil, player, nil) or {}) do
        inst = inst or r[1]
    end
    if inst == nil then return nil, nil end
    local best, bestIndex = nil, nil
    for _, r in ipairs(CR.Eval.DbRows("DB_DialogNPCs", inst, nil, nil) or {}) do
        local index = tonumber(r[3]) or 99
        if not bestIndex or index < bestIndex then best, bestIndex = r[2], index end
    end
    if best == nil then return nil, "" end      -- a conversation, speaker unknown
    local comp = Guides.ByUuid[CR.Guid(best) or ""]
    if comp then return comp.id, nil end
    return nil, nameHandle(best) or ""
end

--- ApprovalRatingChanged(companion, player, new value).
function ALog.OnChanged(companion, player, value, act)
    local comp = Guides.ByUuid[CR.Guid(companion) or ""]
    local pg = CR.Guid(player)
    if not comp or not pg or type(value) ~= "number" then return false end
    value = math.floor(value)
    local k = comp.uuid .. "@" .. pg
    local before = ALog.last[k]
    ALog.last[k] = value
    if before == value then return false end
    local who, handle = speaker(player)
    local d = data()
    d.approval[pg] = d.approval[pg] or {}
    local list = d.approval[pg][comp.uuid] or {}
    list[#list + 1] = { d = before and (value - before) or nil, v = value, a = tonumber(act) or 0, r = d.rests,
        c = who, h = handle }
    while #list > MAX do table.remove(list, 1) end
    d.approval[pg][comp.uuid] = list
    commit()
    return true
end

function ALog.OnRest()
    local d = data()
    d.rests = (d.rests or 0) + 1
    commit()
end

--- The entries for one player, by companion id (for the snapshot).
function ALog.For(player)
    local d = data()
    local pg = CR.Guid(player)
    local out = { rests = d.rests }
    local comps = pg and d.approval[pg] or nil
    if not comps then return out end
    out.c = {}
    for guid, list in pairs(comps) do
        local comp = Guides.ByUuid[guid]
        if comp and #list > 0 then
            local l = {}
            for i, e in ipairs(list) do l[i] = { d = e.d, v = e.v, a = e.a, r = e.r, c = e.c, h = e.h } end
            out.c[comp.id] = l
        end
    end
    return out
end

function ALog.Export()
    return data()
end

function ALog.Forget()
    ALog.data = fresh()
    ALog.last = {}
    commit()
end
