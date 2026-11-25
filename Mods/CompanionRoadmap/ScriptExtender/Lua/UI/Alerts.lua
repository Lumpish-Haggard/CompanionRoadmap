-- =============================================================================
-- UI/Alerts.lua
-- Heads-ups that need the player right now, shown where notices appear:
--
--   * Before a point of no return: while the game asks "are you sure?" (entering
--     the Shadowfell, the Colony, leaving for Baldur's Gate, the Lower City, the
--     Morphic Pool), what is still open before it - the same list as the window's
--     "Before you move on" tab, for that one point.
--
--         COMPANION ROADMAP
--         Before you go on: Act 1 locks for good when you enter the Shadowfell
--         NEXT        Shadowheart  .  Retrieve the Spear of Night
--         ROMANCE     Karlach  .  Romance: ...
--         Press F7 to review everything before you answer.
--
--   * A fight starts with a companion you can only recruit by knocking them out.
--
-- The server says when (the Alert channel); the content comes from the latest
-- snapshot, which the server sends right before a point-of-no-return alert.
-- =============================================================================

CR.Alerts = CR.Alerts or {}
local Alerts = CR.Alerts
local T = CR.Theme
local Guides = CR.Guides

local MAX_ROWS = 6
local WRAP = 640              -- scaled by the extender
local PONR_MAX_MS = 180000    -- never outlive a prompt whose answer was missed
local KO_MS = 30000

Alerts.win = nil
Alerts.current = nil          -- { k = "ponr" | "ko", id = ready check id, ... }
Alerts.timer = nil
Alerts.rows = {}

function Alerts.IsShowing() return Alerts.current ~= nil end

local function build()
    if Alerts.win then return true end
    local ok, err = pcall(function()
        local win = Ext.IMGUI.NewWindow("Companion Roadmap - Heads-up")
        for _, flag in ipairs({ "NoTitleBar", "NoResize", "NoMove", "NoScrollbar", "AlwaysAutoResize",
                                 "NoFocusOnAppearing", "NoNav", "NoSavedSettings", "NoInputs" }) do
            T.SetProp(win, flag, true)
        end
        T.SetProp(win, "Scaling", "Scaled")
        T.ApplyWindow(win, 0.94)
        local s = T.Scale()
        T.SetStyle(win, "WindowPadding", 18 * s, 14 * s)
        T.SetStyle(win, "ItemSpacing", 12 * s, 5 * s)
        T.SetFont(win, "small")

        local header = win:AddText("COMPANION ROADMAP")
        T.SetColor(header, T.C.goldDim)
        Alerts.title = win:AddText("")
        T.SetProp(Alerts.title, "TextWrapPos", WRAP)
        T.SetFont(Alerts.title, "strong")
        T.SetColor(Alerts.title, T.C.gold)
        Alerts.text = win:AddText("")
        T.SetProp(Alerts.text, "TextWrapPos", WRAP)
        T.SetColor(Alerts.text, T.C.text)
        for i = 1, MAX_ROWS do
            local status = win:AddText("")
            local text = win:AddText("")
            text.SameLine = true
            T.SetProp(text, "TextWrapPos", WRAP)
            T.SetColor(text, T.C.text)
            Alerts.rows[i] = { status = status, text = text }
        end
        Alerts.extra = win:AddText("")
        T.SetProp(Alerts.extra, "TextWrapPos", WRAP)
        T.SetColor(Alerts.extra, T.C.romance)
        Alerts.footer = win:AddText("")
        T.SetProp(Alerts.footer, "TextWrapPos", WRAP)
        T.SetColor(Alerts.footer, T.C.faint)
        win.Open = false
        Alerts.win = win
    end)
    if not ok then CR.Warn("Could not create the heads-up window: %s", tostring(err)) end
    return ok
end

local function place()
    local vw, vh = T.Viewport()
    local pos, pivot = CR.Toasts.Placement(vw, vh)
    pcall(function() Alerts.win:SetPos(pos, "Always", pivot) end)
end

--- Fills the panel: a title, a line of text, rows of { label, colour, text }, an
--- extra line and a footer. Empty parts are hidden.
local function show(content, ms)
    if not build() then return end
    T.Update(Alerts.title, content.title or "")
    T.Show(Alerts.title, (content.title or "") ~= "")
    T.Update(Alerts.text, content.text or "", content.textColor or T.C.text)
    T.Show(Alerts.text, (content.text or "") ~= "")
    for i = 1, MAX_ROWS do
        local row, line = content.rows and content.rows[i], Alerts.rows[i]
        if row then
            T.Update(line.status, row.label or "", row.color or T.C.dim)
            T.Update(line.text, row.text or "", row.textColor or T.C.text)
        end
        T.Show(line.status, row ~= nil)
        T.Show(line.text, row ~= nil)
    end
    T.Update(Alerts.extra, content.extra or "")
    T.Show(Alerts.extra, (content.extra or "") ~= "")
    T.Update(Alerts.footer, content.footer or "")
    T.Show(Alerts.footer, (content.footer or "") ~= "")
    place()
    Alerts.win.Open = true
    if CR.Toasts then CR.Toasts.Reposition() end      -- notices wait while this is up
    if Alerts.timer then CR.CancelTimer(Alerts.timer) end
    Alerts.timer = CR.After(ms, function()
        Alerts.timer = nil
        Alerts.Hide()
    end)
end

function Alerts.Hide()
    if Alerts.timer then CR.CancelTimer(Alerts.timer) end
    Alerts.timer = nil
    Alerts.current = nil
    if Alerts.win then pcall(function() Alerts.win.Open = false end) end
    if CR.Toasts then CR.Toasts.Reposition() end
end

local function hotkey()
    return CR.Hotkey and CR.Hotkey.Describe() or "F7"
end

--- What is still open before one point of no return, as panel rows.
function Alerts.PointOfNoReturn(snap, deadlineId)
    local d = Guides.DeadlineById[deadlineId]
    -- without game data it could only say "nothing is open", which would be wrong
    if not d or not (snap and snap.ready) or not (CR.UI and CR.UI.CollectWarnings) then return nil end
    -- already passed (the Lower City entered once before): nothing left to warn about
    if snap.markers and snap.markers[d.marker] then return nil end
    local content = { title = "Before you go on: " .. d.title, rows = {} }
    local group = nil
    local groups, dead = CR.UI.CollectWarnings(snap)
    for _, g in ipairs(groups) do
        if g.deadline.id == deadlineId then group = g end
    end
    local items = {}
    if group then
        -- everyone you could still recruit on one line: the steps below matter as much
        if #group.recruit > 0 then
            local names = {}
            for _, item in ipairs(group.recruit) do names[#names + 1] = item.comp.name end
            items[#items + 1] = { label = "NOT RECRUITED", color = T.C.warn,
                text = table.concat(names, ", ") .. (#names == 1 and " - last chance to recruit" or " - last chance to recruit them") }
        end
        for _, item in ipairs(group.important) do
            local st = T.Status[item.status] or T.Status["?"]
            items[#items + 1] = { label = st.label, color = st.color, item = item }
        end
        for _, item in ipairs(group.romance) do
            items[#items + 1] = { label = "ROMANCE", color = T.C.romance, item = item }
        end
    end
    for _, x in ipairs(dead) do
        items[#items + 1] = { label = "DEAD", color = T.C.bad, text = x.comp.name .. " is dead - revive them first" }
    end
    local shown = math.min(#items, MAX_ROWS)
    if #items > MAX_ROWS then shown = MAX_ROWS - 1 end
    for i = 1, shown do
        local it = items[i]
        local text = it.text
        if not text then
            local title = it.item.step.title
            if it.item.choices then
                local titles = {}
                for _, other in ipairs(it.item.choices) do titles[#titles + 1] = other.title end
                title = "choose a path: " .. table.concat(titles, "  /  ")
            end
            text = it.item.comp.name .. T.SEP_SHORT .. title
        end
        content.rows[i] = { label = it.label, color = it.color, text = text }
    end
    if #items > shown then
        content.rows[#content.rows + 1] = { label = "", text = string.format("... and %d more", #items - shown),
            textColor = T.C.faint }
    end
    if #items == 0 then
        content.text = "Nothing important is left open here."
        content.textColor = T.C.good
    end
    if group and #group.starts > 0 then
        local names = {}
        for _, item in ipairs(group.starts) do names[#names + 1] = item.comp.name end
        content.extra = "Romances that can only begin before this point: " .. table.concat(names, ", ")
    end
    content.footer = string.format("Press %s to review everything before you answer.", hotkey())
    return content, #items
end

function Alerts.ShowPointOfNoReturn(deadlineId, checkId)
    if not CR.Settings.Get("warnReadyChecks") then return end
    local content = Alerts.PointOfNoReturn(CR.Client.Snapshot, deadlineId)
    if not content then return end
    Alerts.current = { k = "ponr", id = checkId, d = deadlineId }
    show(content, PONR_MAX_MS)
end

function Alerts.ShowKnockOut(compId)
    if not CR.Settings.Get("koReminder") then return end
    local comp = Guides.ById[compId or ""]
    local ko = comp and comp.knockOut
    if not ko then return end
    -- a point of no return being asked about wins
    if Alerts.current and Alerts.current.k == "ponr" then return end
    Alerts.current = { k = "ko", c = compId }
    show({
        title = comp.name .. ": knock out, do not kill",
        text = ko.text,
        footer = string.format("Press %s for the whole step in the roadmap.", hotkey()),
    }, KO_MS)
end

--- A message on the Alert channel.
function Alerts.Handle(msg)
    if msg.k == "ponr" then
        if msg.close then
            if Alerts.current and Alerts.current.k == "ponr" and Alerts.current.id == msg.id then Alerts.Hide() end
            return
        end
        Alerts.ShowPointOfNoReturn(msg.d, msg.id)
    elseif msg.k == "ko" then
        Alerts.ShowKnockOut(msg.c)
    end
end
