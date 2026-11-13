-- =============================================================================
-- BootstrapClient.lua - Companion & Romance Roadmap (client context)
-- The in-game overlay, notifications, settings and hotkey.
-- =============================================================================

Ext.Require("Shared/Core.lua")
Ext.Require("Data/Flags.lua")
Ext.Require("Data/CompanionGuides.lua")
Ext.Require("Tracker/FlagEvaluator.lua")   -- shared status/approval definitions
Ext.Require("Client/Settings.lua")
Ext.Require("Client/StateClient.lua")
Ext.Require("UI/Theme.lua")
Ext.Require("UI/Toasts.lua")
Ext.Require("UI/OverlayWindow.lua")
Ext.Require("Client/Hotkey.lua")

CR.RegisterVars()
CR.Settings.Load()
if CR.Net.Init() then
    CR.Client.Init()
end
CR.UI.Init()
CR.Hotkey.Init()

-- MCM injects its API into this mod's table during loading; attach once the
-- session is up, retrying a little later in case MCM initialises after us.
local function tryAttachMCM()
    if CR.Settings.AttachMCM() then
        CR.Hotkey.AttachMCM()
        return true
    end
    return false
end

Ext.Events.SessionLoaded:Subscribe(function()
    if not tryAttachMCM() then
        CR.After(2000, function()
            if not tryAttachMCM() then CR.After(6000, tryAttachMCM) end
        end)
    end
end)

CR.Info("v%s loaded. Press %s in game (or use the MCM page) to open the roadmap.", CR.Version, CR.Hotkey.Describe())
