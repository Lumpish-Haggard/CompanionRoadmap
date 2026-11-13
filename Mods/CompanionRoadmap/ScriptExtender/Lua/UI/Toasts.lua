-- =============================================================================
-- UI/Toasts.lua
-- Small notices on the right edge, below the minimap:
--     COMPANION ROADMAP
--     DONE    Shadowheart  .  Romance: wine by the waterfall
-- Shown when the server reports a step that just became done or missed.
-- =============================================================================

CR.Toasts = CR.Toasts or {}
local Toasts = CR.Toasts
local T = CR.Theme

local MAX_LINES = 4
local DURATION_MS = 8000
local WRAP = 600            -- scaled by the extender

Toasts.win = nil
Toasts.lines = {}
Toasts.queue = {}
Toasts.hideTimer = nil

local function build()
    if Toasts.win then return true end
    local ok, err = pcall(function()
        local win = Ext.IMGUI.NewWindow("Companion Roadmap - Alerts")
        for _, flag in ipairs({ "NoTitleBar", "NoResize", "NoMove", "NoScrollbar", "AlwaysAutoResize",
                                 "NoFocusOnAppearing", "NoNav", "NoSavedSettings", "NoInputs" }) do
            T.SetProp(win, flag, true)
        end
        T.SetProp(win, "Scaling", "Scaled")
        T.ApplyWindow(win, 0.92)
        local s = T.Scale()
        T.SetStyle(win, "WindowPadding", 16 * s, 12 * s)
        T.SetStyle(win, "ItemSpacing", 12 * s, 5 * s)
        T.SetFont(win, "small")

        local header = win:AddText("COMPANION ROADMAP")
        T.SetColor(header, T.C.goldDim)
        for i = 1, MAX_LINES do
            local status = win:AddText("")
            local text = win:AddText("")
            text.SameLine = true
            T.SetProp(text, "TextWrapPos", WRAP)
            T.SetColor(text, T.C.text)
            Toasts.lines[i] = { status = status, text = text }
        end
        win.Open = false
        Toasts.win = win
    end)
    if not ok then CR.Warn("Could not create the notification window: %s", tostring(err)) end
    return ok
end

local function render()
    local win = Toasts.win
    if not win then return end
    local n = #Toasts.queue
    for i = 1, MAX_LINES do
        local item = Toasts.queue[n - MAX_LINES + i]
        local line = Toasts.lines[i]
        if item then
            T.Update(line.status, item.label, item.color)
            T.Update(line.text, item.text)
        end
        T.Show(line.status, item ~= nil)
        T.Show(line.text, item ~= nil)
    end
    local vw, vh = T.Viewport()
    -- right edge, below the minimap
    pcall(function() win:SetPos({ vw - 24, math.floor(vh * 0.30) }, "Always", { 1.0, 0.0 }) end)
    win.Open = n > 0
end

local function scheduleHide()
    if Toasts.hideTimer then CR.CancelTimer(Toasts.hideTimer) end
    Toasts.hideTimer = CR.After(DURATION_MS, function()
        Toasts.hideTimer = nil
        Toasts.queue = {}
        render()
    end)
end

--- items: list of { c = companionId, id = stepId, s = status }
function Toasts.Push(items)
    local Set = CR.Settings
    if not Set.Get("notifications") then return end
    local all = Set.Get("notifyAll")
    local added = false
    for _, item in ipairs(items or {}) do
        local step = CR.Guides.StepById[item.id]
        local comp = CR.Guides.Get(item.c)
        if step and comp and (all or step.critical or step.romance) then
            local st = T.Status[item.s] or T.Status["?"]
            table.insert(Toasts.queue, {
                label = st.label,
                color = st.color,
                text = comp.name .. T.SEP_SHORT .. step.title,
            })
            added = true
        end
    end
    if not added then return end
    while #Toasts.queue > MAX_LINES do table.remove(Toasts.queue, 1) end
    if build() then
        render()
        scheduleHide()
    end
end
