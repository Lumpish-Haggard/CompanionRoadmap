-- =============================================================================
-- BootstrapServer.lua - Companion & Romance Roadmap (server context)
-- Reads the save through Osiris and sends each player their roadmap.
-- =============================================================================

Ext.Require("Shared/Core.lua")
Ext.Require("Data/Flags.lua")
Ext.Require("Data/CompanionGuides.lua")
Ext.Require("Tracker/FlagEvaluator.lua")
Ext.Require("Tracker/StateServer.lua")

CR.RegisterVars()
if CR.Net.Init() then
    CR.Server.Init()
end

CR.Info("v%s server ready (%d companions, %d tracked flags).", CR.Version, #CR.Guides.Companions, CR.Count(CR.Guides.WatchedFlags))
