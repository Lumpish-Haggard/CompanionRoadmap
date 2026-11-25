-- =============================================================================
-- Client/Settings.lua
-- Player preferences. Stored in
--   %LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Script Extender\CompanionRoadmap\settings.json
-- and mirrored to Mod Configuration Menu (MCM) when MCM is installed, so the same
-- options can be changed from either place.
-- =============================================================================

CR.Settings = CR.Settings or {}
local Set = CR.Settings

local FILE = "CompanionRoadmap/settings.json"

Set.SpoilerChoices = { "Show everything", "Titles only for future acts", "Hide future acts" }
Set.SpoilerKeys = { "full", "titles", "hide" }
Set.OpacityChoices = { "100%", "95%", "90%", "85%", "80%", "70%" }
Set.OpacityValues = { 1.0, 0.95, 0.90, 0.85, 0.80, 0.70 }
-- Where notices appear. "custom" uses toastX / toastY (0-100, percent of the screen).
Set.ToastChoices = { "Right, under the minimap", "Right, middle", "Right, bottom", "Top centre",
    "Left, middle", "Bottom centre, above the hotbar", "Custom (use the sliders)" }
Set.ToastKeys = { "right-top", "right-middle", "right-bottom", "top-centre", "left-middle", "bottom-centre", "custom" }

Set.Defaults = {
    hotkey = { key = "F7", mods = {} },   -- only used when MCM is not installed
    notifications = true,                 -- toasts when a step is completed or missed
    notifyAll = false,                    -- false: only romance / critical steps
    warnReadyChecks = true,               -- what is still open when the game asks "are you sure?" before a point of no return
    koReminder = true,                    -- when a fight starts with a companion you must knock out, not kill
    toastPosition = "right-top",          -- one of Set.ToastKeys
    toastX = 100,                         -- custom position: 0 = left edge, 100 = right edge
    toastY = 30,                          -- custom position: 0 = top, 100 = bottom
    spoilers = "full",                    -- "full" | "titles" | "hide"
    spoilersChosen = false,               -- the first-run question about spoilers was answered
    hideCompleted = false,
    romanceOnly = false,
    showTracking = false,                 -- show which flag/journal entry each step watches
    portraits = true,                     -- companion pictures (the game's Photo Mode stickers)
    escCloses = true,                     -- Esc closes the roadmap window
    opacity = 0.95,
    lastCompanion = "Shadowheart",
}

-- Setting key -> MCM blueprint id (see MCM_blueprint.json)
local MCM_IDS = {
    notifications = "notifications",
    notifyAll = "notify_all",
    warnReadyChecks = "warn_ready_checks",
    koReminder = "ko_reminder",
    toastPosition = "notify_position",
    toastX = "notify_x",
    toastY = "notify_y",
    spoilers = "spoilers",
    hideCompleted = "hide_completed",
    romanceOnly = "romance_only",
    showTracking = "show_tracking",
    portraits = "portraits",
    escCloses = "esc_closes",
    opacity = "window_opacity",
}
local MCM_KEY_BY_ID = {}
for k, id in pairs(MCM_IDS) do MCM_KEY_BY_ID[id] = k end

Set.values = {}
Set.listeners = {}
Set.mcm = nil
local saveTimer = nil

local function indexOf(list, value)
    for i, v in ipairs(list) do if v == value then return i end end
    return nil
end

--- A percentage setting as a whole number from 0 to 100 (anything else -> the default).
local function percent(key, value)
    local n = tonumber(value)
    if not n then return Set.Defaults[key] end
    return math.max(0, math.min(100, math.floor(n + 0.5)))
end

-- MCM stores the enum choice text; we store compact keys.
local function fromMcm(key, value)
    if key == "spoilers" then
        local i = indexOf(Set.SpoilerChoices, value)
        return i and Set.SpoilerKeys[i] or Set.Defaults.spoilers
    elseif key == "opacity" then
        local i = indexOf(Set.OpacityChoices, value)
        return i and Set.OpacityValues[i] or Set.Defaults.opacity
    elseif key == "toastPosition" then
        local i = indexOf(Set.ToastChoices, value)
        return i and Set.ToastKeys[i] or Set.Defaults.toastPosition
    elseif key == "toastX" or key == "toastY" then
        return percent(key, value)
    end
    return value
end

local function toMcm(key, value)
    if key == "toastPosition" then
        local i = indexOf(Set.ToastKeys, value)
        return Set.ToastChoices[i or 1]
    elseif key == "toastX" or key == "toastY" then
        return percent(key, value)
    end
    if key == "spoilers" then
        local i = indexOf(Set.SpoilerKeys, value)
        return Set.SpoilerChoices[i or 1]
    elseif key == "opacity" then
        local best, bestDiff = 1, math.huge
        for i, v in ipairs(Set.OpacityValues) do
            local d = math.abs(v - (tonumber(value) or 1))
            if d < bestDiff then best, bestDiff = i, d end
        end
        return Set.OpacityChoices[best]
    end
    return value
end

local function notify(key)
    for _, fn in ipairs(Set.listeners) do CR.Guard("settings listener", fn, key) end
end

function Set.OnChange(fn) table.insert(Set.listeners, fn) end

function Set.Load()
    local values = CR.ShallowCopy(Set.Defaults)
    local raw = Ext.IO and CR.Try(Ext.IO.LoadFile, FILE)
    if type(raw) == "string" and raw ~= "" then
        local data = CR.Try(Ext.Json.Parse, raw)
        if type(data) == "table" then
            for k, v in pairs(data) do
                if Set.Defaults[k] ~= nil and type(v) == type(Set.Defaults[k]) then values[k] = v end
            end
        end
    end
    if type(values.hotkey) ~= "table" or type(values.hotkey.key) ~= "string" then
        values.hotkey = CR.ShallowCopy(Set.Defaults.hotkey)
    end
    if type(values.hotkey.mods) ~= "table" then values.hotkey.mods = {} end
    if not indexOf(Set.SpoilerKeys, values.spoilers) then values.spoilers = Set.Defaults.spoilers end
    if not indexOf(Set.ToastKeys, values.toastPosition) then values.toastPosition = Set.Defaults.toastPosition end
    values.toastX = percent("toastX", values.toastX)
    values.toastY = percent("toastY", values.toastY)
    Set.values = values
end

function Set.Save()
    if saveTimer then CR.CancelTimer(saveTimer) end
    saveTimer = CR.After(500, function()
        saveTimer = nil
        if not (Ext.IO and Ext.IO.SaveFile) then return end
        local json = CR.Try(Ext.Json.Stringify, Set.values)
        if json then CR.Try(Ext.IO.SaveFile, FILE, json) end
    end)
end

function Set.Get(key)
    local id = MCM_IDS[key]
    if id and Set.mcm then
        local v = CR.Try(Set.mcm.Get, id)
        if v ~= nil then return fromMcm(key, v) end
    end
    local v = Set.values[key]
    if v == nil then v = Set.Defaults[key] end
    return v
end

--- The spoiler level actually applied. Until the player has answered the first-run
--- question (or changed the setting anywhere), nothing from later acts is revealed.
function Set.Spoilers()
    local level = Set.Get("spoilers")
    if level == "full" and not Set.Get("spoilersChosen") then return "titles" end
    return level
end

function Set.Set(key, value)
    Set.values[key] = value
    if key == "spoilers" then Set.values.spoilersChosen = true end  -- any choice answers the first-run question
    local id = MCM_IDS[key]
    if id and Set.mcm and Set.mcm.Set then
        CR.Try(Set.mcm.Set, id, toMcm(key, value))
    end
    Set.Save()
    notify(key)
end

-- -----------------------------------------------------------------------------
-- MCM integration (optional). Called once the session is loaded, when MCM has
-- injected its API into our mod table (load order independent).
-- -----------------------------------------------------------------------------
function Set.HasMCM() return Set.mcm ~= nil end

function Set.AttachMCM()
    if Set.mcm then return true end
    local api = MCM -- injected by MCM into this mod's environment
    if type(api) ~= "table" or type(api.Get) ~= "function" then return false end
    Set.mcm = api

    -- first run with MCM: push our local values into MCM so nothing is lost
    for key, id in pairs(MCM_IDS) do
        local current = CR.Try(api.Get, id)
        if current == nil then CR.Try(api.Set, id, toMcm(key, Set.values[key])) end
    end

    if Ext.ModEvents and Ext.ModEvents.BG3MCM and Ext.ModEvents.BG3MCM.MCM_Setting_Saved then
        CR.Try(function()
            Ext.ModEvents.BG3MCM.MCM_Setting_Saved:Subscribe(function(payload)
                if type(payload) ~= "table" or payload.modUUID ~= ModuleUUID then return end
                local key = MCM_KEY_BY_ID[payload.settingId]
                if key then
                    Set.values[key] = fromMcm(key, payload.value)
                    if key == "spoilers" then Set.values.spoilersChosen = true end
                    Set.Save()
                    notify(key)
                end
            end)
        end)
    end
    CR.Info("Mod Configuration Menu detected - settings and the hotkey are available in MCM.")
    return true
end
