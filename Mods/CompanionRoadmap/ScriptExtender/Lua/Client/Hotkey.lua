-- =============================================================================
-- Client/Hotkey.lua
-- Opening the overlay:
--   * with MCM installed: the "Toggle roadmap" keybinding (default F7) and an
--     "Open roadmap" button on the mod's MCM page
--   * without MCM: a built-in key handler (default F7), rebindable from the
--     overlay's Options panel
--   * always: the SE console command  !roadmap
-- Esc closes the window while it is open (can be turned off in the options).
--
-- F8 is NOT used: it is Baldur's Gate 3's default Quickload key.
-- Default BG3 binds F1-F5, F8 and F10; F6, F7, F9 and F11 are free.
-- =============================================================================

CR.Hotkey = CR.Hotkey or {}
local H = CR.Hotkey
local Set = CR.Settings

H.useMCM = false
H.capture = nil

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LGUI = true, RGUI = true,
}
local MOD_NAMES = {
    LSHIFT = "SHIFT", RSHIFT = "SHIFT", LCTRL = "CTRL", RCTRL = "CTRL", LALT = "ALT", RALT = "ALT",
}

--- Normalised set of held modifiers: { CTRL = true, SHIFT = true, ALT = true }
local function heldModifiers(e)
    local held = {}
    pcall(function()
        for _, m in ipairs(e.Modifiers) do
            local name = MOD_NAMES[string.upper(tostring(m))]
            if name then held[name] = true end
        end
    end)
    return held
end

local function sameMods(held, wanted)
    local n = 0
    for _, m in ipairs(wanted or {}) do
        if not held[string.upper(m)] then return false end
        n = n + 1
    end
    local m = 0
    for _ in pairs(held) do m = m + 1 end
    return n == m
end

function H.Describe()
    local hk = Set.Get("hotkey") or Set.Defaults.hotkey
    local parts = {}
    for _, m in ipairs(hk.mods or {}) do table.insert(parts, string.upper(m)) end
    table.insert(parts, hk.key or "F7")
    return table.concat(parts, " + ")
end

--- Records the next key press as the new toggle key (used by the Options panel).
function H.BeginCapture(onDone)
    H.capture = { onDone = onDone }
end

local function onKey(e)
    if tostring(e.Event) ~= "KeyDown" or e.Repeat then return end
    local key = string.upper(tostring(e.Key))

    if H.capture then
        if MODIFIER_KEYS[key] then return end
        local cap = H.capture
        H.capture = nil
        if key ~= "ESCAPE" then
            local mods = {}
            for m in pairs(heldModifiers(e)) do table.insert(mods, m) end
            table.sort(mods)
            Set.Set("hotkey", { key = key, mods = mods })
            CR.Info("Roadmap hotkey set to %s.", H.Describe())
        end
        pcall(function() e:PreventAction() end)
        if cap.onDone then CR.Guard("hotkey capture", cap.onDone) end
        return
    end

    -- Esc closes the roadmap like any other panel, and is not passed on to the game
    if key == "ESCAPE" and CR.UI.IsOpen() and Set.Get("escCloses") then
        CR.UI.SetOpen(false)
        pcall(function() e:PreventAction() end)
        return
    end

    if H.useMCM then return end
    local hk = Set.Get("hotkey") or Set.Defaults.hotkey
    if key == string.upper(hk.key or "") and sameMods(heldModifiers(e), hk.mods) then
        CR.UI.Toggle()
    end
end

--- Registers MCM callbacks once MCM has injected its API (called at SessionLoaded).
function H.AttachMCM()
    local api = Set.mcm
    if not api or H.useMCM then return end
    local toggle = function() CR.Guard("toggle", CR.UI.Toggle) end
    local ok = false
    if api.Keybinding and api.Keybinding.SetKeyDownCallback then
        ok = pcall(api.Keybinding.SetKeyDownCallback, "toggle_roadmap", toggle)
    elseif api.Keybinding and api.Keybinding.SetCallback then
        ok = pcall(api.Keybinding.SetCallback, "toggle_roadmap", toggle)
    elseif api.SetKeybindingCallback then
        ok = pcall(api.SetKeybindingCallback, "toggle_roadmap", toggle)
    end
    H.useMCM = ok
    if api.EventButton and api.EventButton.RegisterCallback then
        pcall(api.EventButton.RegisterCallback, "open_roadmap", function()
            CR.Guard("open", CR.UI.SetOpen, true)
            if api.CloseMCMWindow then pcall(api.CloseMCMWindow) end
        end)
    end
    if not ok then CR.Warn("Could not register the MCM keybinding - falling back to %s.", H.Describe()) end
    if CR.UI.RefreshHotkeyText then CR.UI.RefreshHotkeyText() end
end

function H.Init()
    Ext.Events.KeyInput:Subscribe(function(e) CR.Guard("key input", onKey, e) end)

    if Ext.RegisterConsoleCommand then
        Ext.RegisterConsoleCommand("roadmap", function(_, sub)
            sub = string.lower(sub or "toggle")
            if sub == "open" then CR.UI.SetOpen(true)
            elseif sub == "close" then CR.UI.SetOpen(false)
            elseif sub == "debug" then
                CR.Verbose = not CR.Verbose
                CR.Info("Verbose logging %s (client).", CR.Verbose and "ON" or "OFF")
            elseif sub == "hotkey" then
                CR.Info("Current toggle key: %s%s", H.Describe(), H.useMCM and " (managed by MCM)" or "")
            else
                CR.UI.Toggle()
            end
        end)
    end
end
