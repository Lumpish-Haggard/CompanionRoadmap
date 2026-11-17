-- =============================================================================
-- Tracker/Memory.lua  (server only)
-- Choice memory: what the mod saw happen, kept in the savegame.
--
-- The tracker normally only sees what is still in the save when it looks. Some
-- of that disappears later: the game purges a companion's romance flags when they
-- leave, drops the "knocked out" record once Minthara is moved to Moonrise, and
-- clears some flags as soon as a conversation ends. From the moment the mod is
-- installed, every watched fact that is seen true is written down here, and so is
-- the game's own reason when it removes a companion for good.
--
-- Memory can only turn an unknown step into DONE ("Remembered"). It never makes a
-- step missed, and something the save still shows always wins (see FlagEvaluator).
--
-- Stored in the mod variable "Memory":
--   { v = 1,
--     facts = { [key] = act },             key: "<flag guid>@<target guid>" or "ko@<companion guid>"
--     left  = { [companion guid] = { r = "<reason>", a = act } } }
-- `act` is the act the campaign was in when the fact was first seen (0 = unknown).
-- =============================================================================

CR.Memory = CR.Memory or {}
local Mem = CR.Memory

local VERSION = 1
local NULL_GUID = "00000000-0000-0000-0000-000000000000"

Mem.data = nil        -- working copy for this session
Mem.dirty = false
Mem.act = 0           -- the act of the last snapshot; stamped on new entries
Mem.unstamped = {}    -- keys noted while the act was being worked out

local function modVars()
    if not (Ext.Vars and Ext.Vars.GetModVariables) then return nil end
    local ok, vars = pcall(Ext.Vars.GetModVariables, ModuleUUID)
    if ok then return vars end
    return nil
end

local function fresh()
    return { v = VERSION, facts = {}, left = {} }
end

--- A plain copy of what is stored in the save (the stored value may be a proxy).
local function readStored()
    local vars = modVars()
    local stored = vars and vars.Memory
    local out = fresh()
    if type(stored) ~= "table" then return out end
    pcall(function()
        for key, act in pairs(stored.facts or {}) do
            if type(key) == "string" then out.facts[key] = tonumber(act) or 0 end
        end
        for guid, entry in pairs(stored.left or {}) do
            if type(guid) == "string" and type(entry) == "table" and type(entry.r) == "string" then
                out.left[guid] = { r = entry.r, a = tonumber(entry.a) or 0 }
            end
        end
    end)
    return out
end

--- (Re)reads the memory of the current save. Called when a save has loaded.
function Mem.Load()
    Mem.data = readStored()
    Mem.dirty = false
    Mem.unstamped = {}
    return Mem.data
end

local function data()
    return Mem.data or Mem.Load()
end

--- Writes pending changes into the save. The whole table is reassigned so the
--- variable manager notices the change.
function Mem.Commit()
    if not Mem.dirty then return end
    Mem.dirty = false
    local vars = modVars()
    if not vars then return end
    local d = data()
    local copy = { v = VERSION, facts = {}, left = {} }
    for key, act in pairs(d.facts) do copy.facts[key] = act end
    for guid, entry in pairs(d.left) do copy.left[guid] = { r = entry.r, a = entry.a } end
    local ok, err = pcall(function() vars.Memory = copy end)
    if not ok then CR.Debug("could not store the memory: %s", tostring(err)) end
end

--- Key of a flag fact. `target` is any GUID string (or the Osiris NULL).
function Mem.FlagKey(flagGuid, target)
    local f = CR.Guid(flagGuid)
    if not f then return nil end
    return f .. "@" .. (CR.Guid(target) or NULL_GUID)
end

function Mem.KoKey(companionGuid)
    return "ko@" .. tostring(CR.Guid(companionGuid) or companionGuid)
end

--- A snapshot starts by working out the act. Facts first seen during that (the
--- progress flags themselves) are stamped by Mem.Stamp once the act is known.
function Mem.BeginSnapshot()
    Mem.act = nil
end

function Mem.Stamp(act)
    Mem.act = tonumber(act) or 0
    if #Mem.unstamped > 0 then
        local facts = data().facts
        for _, key in ipairs(Mem.unstamped) do facts[key] = Mem.act end
        Mem.unstamped = {}
    end
end

--- Remembers a fact the first time it is seen.
function Mem.Note(key)
    if not key then return end
    local facts = data().facts
    if facts[key] == nil then
        facts[key] = Mem.act or 0
        if Mem.act == nil then table.insert(Mem.unstamped, key) end
        Mem.dirty = true
    end
end

--- The act in which a fact was first seen, or nil if it was never seen.
function Mem.Recall(key)
    if not key then return nil end
    return data().facts[key]
end

--- The game removed a companion for good, with this reason
--- (the second argument of PROC_Origins_CompanionLeavePermanently).
function Mem.NoteLeft(companionGuid, reason)
    local guid = CR.Guid(companionGuid)
    if not guid then return end
    data().left[guid] = { r = tostring(reason or ""), a = Mem.act or 0 }
    Mem.dirty = true
end

function Mem.Left(companionGuid)
    local guid = CR.Guid(companionGuid)
    return guid and data().left[guid] or nil
end

--- A companion who is back in the team did not leave for good after all.
function Mem.ClearLeft(companionGuid)
    local guid = CR.Guid(companionGuid)
    if guid and data().left[guid] then
        data().left[guid] = nil
        Mem.dirty = true
    end
end

function Mem.Count()
    return CR.Count(data().facts) + CR.Count(data().left)
end

--- Everything, as plain data (for the report file).
function Mem.Export()
    local d = data()
    local out = { v = VERSION, facts = {}, left = {} }
    for key, act in pairs(d.facts) do out.facts[key] = act end
    for guid, entry in pairs(d.left) do out.left[guid] = { r = entry.r, a = entry.a } end
    return out
end

--- Forgets everything remembered in this save.
function Mem.Forget()
    Mem.data = fresh()
    Mem.dirty = true
    Mem.Commit()
end
