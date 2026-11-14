-- =============================================================================
-- Shared/Core.lua
-- Namespace, logging, safe-call helpers, timers and network channels.
-- Loaded first by both BootstrapServer.lua and BootstrapClient.lua.
--
-- Every file of this mod shares the mod environment (Mods.CompanionRoadmap),
-- so the global table `CR` declared here is visible to all other modules.
-- =============================================================================

CR = CR or {}

CR.ModName = "Companion & Romance Roadmap"
CR.Version = "1.0.1"
CR.Protocol = 1                                       -- bump when the net payload changes
CR.NULL = "NULL_00000000-0000-0000-0000-000000000000" -- Osiris NULL GUID (global flags, "any player")
CR.Verbose = false                                    -- toggled with the console command "!roadmap debug"

-- -----------------------------------------------------------------------------
-- Logging
-- -----------------------------------------------------------------------------
local LOG_PREFIX = "[CompanionRoadmap] "

local function format(fmt, ...)
    if select("#", ...) == 0 then return tostring(fmt) end
    local ok, s = pcall(string.format, fmt, ...)
    if ok then return s end
    return tostring(fmt)
end

local function emit(kind, msg)
    local log = Ext.Log or Ext.Utils
    local fn = nil
    if log then
        if kind == "warn" then fn = log.PrintWarning
        elseif kind == "error" then fn = log.PrintError
        else fn = log.Print end
    end
    if fn then fn(LOG_PREFIX .. msg) else print(LOG_PREFIX .. msg) end
end

function CR.Info(fmt, ...) emit("info", format(fmt, ...)) end
function CR.Warn(fmt, ...) emit("warn", format(fmt, ...)) end
function CR.Error(fmt, ...) emit("error", format(fmt, ...)) end
function CR.Debug(fmt, ...)
    if CR.Verbose then emit("info", "[debug] " .. format(fmt, ...)) end
end

-- -----------------------------------------------------------------------------
-- Safe calls
-- -----------------------------------------------------------------------------

--- Calls fn(...) in protected mode. Returns the first result, or nil on error.
function CR.Try(fn, ...)
    if fn == nil then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
    CR.Debug("protected call failed: %s", tostring(res))
    return nil
end

--- Runs fn(...) and logs (instead of propagating) any error. Used for event handlers.
function CR.Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then CR.Error("%s failed: %s", label, tostring(err)) end
    return ok
end

-- -----------------------------------------------------------------------------
-- GUID helpers
-- -----------------------------------------------------------------------------
local GUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

--- Extracts the bare, lower-case GUID from "Name_GUID" or "GUID" strings.
function CR.Guid(s)
    if type(s) ~= "string" or #s < 36 then return nil end
    local g = string.lower(string.sub(s, -36))
    if string.match(g, GUID_PATTERN) then return g end
    return nil
end

-- -----------------------------------------------------------------------------
-- Time and timers
-- -----------------------------------------------------------------------------
function CR.Now()
    local fn = (Ext.Timer and Ext.Timer.MonotonicTime) or (Ext.Utils and Ext.Utils.MonotonicTime)
    if fn then
        local ok, v = pcall(fn)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

--- Runs fn after `ms` milliseconds of real time (falls back to game time, then to immediate).
function CR.After(ms, fn)
    local T = Ext.Timer
    if T and T.WaitForRealtime then return T.WaitForRealtime(ms, fn) end
    if T and T.WaitFor then return T.WaitFor(ms, fn) end
    fn()
    return nil
end

function CR.CancelTimer(handle)
    if handle ~= nil and Ext.Timer and Ext.Timer.Cancel then
        pcall(Ext.Timer.Cancel, handle)
    end
end

-- -----------------------------------------------------------------------------
-- Small table helpers
-- -----------------------------------------------------------------------------
function CR.Count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

function CR.Contains(list, value)
    if type(list) ~= "table" then return false end
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

function CR.ShallowCopy(t)
    local r = {}
    if type(t) == "table" then for k, v in pairs(t) do r[k] = v end end
    return r
end

-- -----------------------------------------------------------------------------
-- Network channels (Ext.Net NetChannel API, SE v22+)
--   State    server -> client   full roadmap snapshot for that client's avatar
--   Toast    server -> client   "step completed / missed" notifications
--   Hello    client -> server   subscribe + request a snapshot ({open=bool})
--   Override client -> server   manual check-off toggle ({id=stepId, value=bool})
--   Report   client -> server   write the report file; server -> client: the result
-- Channels must be created with identical names on both sides.
-- -----------------------------------------------------------------------------
CR.Net = { Ready = false }

function CR.Net.Init()
    if CR.Net.Ready then return true end
    if not (Ext.Net and Ext.Net.CreateChannel) then
        CR.Error("Ext.Net.CreateChannel is missing - please update the Script Extender (v25 or newer is required).")
        return false
    end
    local ok, err = pcall(function()
        CR.Net.State = Ext.Net.CreateChannel(ModuleUUID, "State")
        CR.Net.Toast = Ext.Net.CreateChannel(ModuleUUID, "Toast")
        CR.Net.Hello = Ext.Net.CreateChannel(ModuleUUID, "Hello")
        CR.Net.Override = Ext.Net.CreateChannel(ModuleUUID, "Override")
        CR.Net.Report = Ext.Net.CreateChannel(ModuleUUID, "Report")
    end)
    if not ok then
        CR.Error("Could not create network channels: %s", tostring(err))
        return false
    end
    CR.Net.Ready = true
    return true
end

-- -----------------------------------------------------------------------------
-- Savegame storage: manual check-offs live in a mod variable so they travel with
-- the save. Must be registered at bootstrap, with identical settings on both sides.
-- -----------------------------------------------------------------------------
function CR.RegisterVars()
    if not (Ext.Vars and Ext.Vars.RegisterModVariable) then
        CR.Warn("Ext.Vars is unavailable - manual check-offs will not be saved with the game.")
        return
    end
    local ok, err = pcall(Ext.Vars.RegisterModVariable, ModuleUUID, "Overrides", {
        Server = true,
        Client = false,
        WriteableOnServer = true,
        WriteableOnClient = false,
        Persistent = true,
        SyncToClient = false,
    })
    if not ok then CR.Warn("Could not register the save variable: %s", tostring(err)) end
end

--- Converts the peer id passed to net handlers into the user id Osiris expects.
function CR.PeerToUserId(peerId)
    if type(peerId) ~= "number" then return nil end
    return (math.floor(peerId) & 0xffff0000) | 0x0001
end
