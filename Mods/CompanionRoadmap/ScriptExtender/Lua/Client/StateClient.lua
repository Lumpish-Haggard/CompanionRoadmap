-- =============================================================================
-- Client/StateClient.lua
-- Receives roadmap snapshots and notifications from the server, and sends the
-- player's requests (subscribe, refresh, manual check-offs, report file).
-- =============================================================================

CR.Client = CR.Client or {}
local Client = CR.Client

Client.Snapshot = nil        -- last snapshot received from the server
Client.ReceivedAt = 0
Client.listeners = {}

function Client.OnSnapshot(fn) table.insert(Client.listeners, fn) end

local function send(channel, msg)
    if not CR.Net.Ready or not channel then return false end
    local ok, err = pcall(function() channel:SendToServer(msg) end)
    if not ok then CR.Debug("send failed: %s", tostring(err)) end
    return ok
end

--- Tells the server we exist (and whether the overlay is open). `want` asks for a snapshot now.
function Client.Hello(open, want)
    return send(CR.Net.Hello, { open = open and true or false, want = want and true or nil })
end

function Client.RequestRefresh(open)
    return Client.Hello(open, true)
end

function Client.SetOverride(stepId, value)
    return send(CR.Net.Override, { id = stepId, value = value and true or false })
end

--- Asks the server to write the report file; `onDone(ok, text)` gets the outcome.
function Client.RequestReport(onDone)
    Client.reportDone = onDone
    if not send(CR.Net.Report, {}) and onDone then
        onDone(false, "The game is not ready yet - load a save first.")
    end
end

local function onReport(msg)
    local done = Client.reportDone
    Client.reportDone = nil
    if not done or type(msg) ~= "table" then return end
    if msg.ok then
        -- the file is written by the server, i.e. on the host's PC in multiplayer
        local file = string.gsub(tostring(msg.file), "/", "\\")
        done(true, "Saved (" .. tostring(msg.info) .. "): %LOCALAPPDATA%\\Larian Studios\\Baldur's Gate 3\\Script Extender\\" .. file)
    else
        done(false, tostring(msg.info or "The report could not be written."))
    end
end

local function onState(msg)
    if type(msg) ~= "table" then return end
    if msg.p ~= nil and msg.p ~= CR.Protocol then
        CR.Warn("Server sent protocol %s, client expects %s - is the mod installed on all machines?", tostring(msg.p), tostring(CR.Protocol))
        return
    end
    Client.Snapshot = msg
    Client.ReceivedAt = CR.Now()
    for _, fn in ipairs(Client.listeners) do CR.Guard("snapshot listener", fn, msg) end
end

local function onToast(msg)
    if type(msg) ~= "table" or type(msg.items) ~= "table" then return end
    if CR.Toasts then CR.Toasts.Push(msg.items) end
end

function Client.Init()
    if not CR.Net.Ready then return end
    CR.Net.State:SetHandler(function(msg) CR.Guard("State", onState, msg) end)
    CR.Net.Toast:SetHandler(function(msg) CR.Guard("Toast", onToast, msg) end)
    CR.Net.Report:SetHandler(function(msg) CR.Guard("Report", onReport, msg) end)

    -- Announce ourselves once the game is running so the server can send toasts
    -- even before the overlay has been opened.
    Ext.Events.GameStateChanged:Subscribe(function(e)
        if tostring(e.ToState) == "Running" then
            local open = CR.UI and CR.UI.IsOpen and CR.UI.IsOpen() or false
            Client.Hello(open, open)
        end
    end)
end
