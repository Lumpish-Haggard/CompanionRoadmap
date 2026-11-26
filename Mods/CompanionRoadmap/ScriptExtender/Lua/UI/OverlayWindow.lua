-- =============================================================================
-- UI/OverlayWindow.lua
-- The in-game roadmap window (Ext.IMGUI), styled after BG3's own panels.
--
--   +----------------------------------------------------------------------+
--   |                     Companion & Romance Roadmap                  [x] |
--   |  Act 2  .  Shadow-Cursed Lands                                       |
--   |  Partner: Shadowheart   .   41 of 112 steps done                     |
--   |  2 things to settle before you move on - click to review             |
--   |  Companions | Before you move on (2) | Options                       |
--   |  +-------------+---------------------------------------------------+ |
--   |  | COMPANIONS  | (o) Shadowheart                                   | |
--   |  | (o) Shadow..|     Half-elf cleric of Shar                       | |
--   |  |     Dating  |     In your camp . Dating . Approval 47 (High)    | |
--   |  | (o) Minthara| ==========----------------                        | |
--   |  |     ...     | v Act 2  .  3 of 5 done                           | |
--   |  |             |   NEXT      Romance: the night swim               | |
--   |  |             |   DONE      ...                                   | |
--   +----------------------------------------------------------------------+
--
-- The window is built once; live updates only change labels, colours and
-- visibility, so scroll position and open steps survive.
-- =============================================================================

CR.UI = CR.UI or {}
local UI = CR.UI
local T = CR.Theme
local Guides = CR.Guides
local Set = CR.Settings
local S = CR.Status

UI.win = nil
UI.open = false
UI.selected = nil
UI.page = nil          -- element references for the selected companion
UI.sidebar = {}        -- companionId -> { sel, info, img }
UI.h = {}              -- header / tabs / warnings / options references
UI.forcedAct = nil

local ACTS = {
    { key = 1, title = "Act 1", acts = { [0] = true, [1] = true } },
    { key = 2, title = "Act 2", acts = { [2] = true } },
    { key = 3, title = "Act 3", acts = { [3] = true } },
}

local DONE_LIKE = { D = true, O = true }
local OPEN_LIKE = { N = true, C = true, A = true, P = true, I = true }
-- statuses that mean "do this now": highlighted, opened once, and they make an act open
local ACT_NOW = { N = true, C = true }

-- Sizes are scaled by the extender (window Scaling = "Scaled").
local SIDEBAR_WIDTH = 300
local SIDEBAR_WIDTH_PORTRAITS = 350
local STATUS_WIDTH = 140
local PORTRAIT_SIDE = 46
local PORTRAIT_PAGE = 84
-- Nudges small text down so it shares a baseline with body text next to it.
local BASELINE_NUDGE = { 0, 3 }

-- -----------------------------------------------------------------------------
-- Keyboard and controller navigation
-- The Script Extender switches on ImGui's keyboard and gamepad navigation for all
-- its windows, and the game keeps receiving the same keys and buttons. The window
-- that has the focus then also takes Space, the arrow keys, Tab, Page Up/Down and
-- every controller button and stick: with the roadmap focused, playing the game
-- (or a drifting stick) switched tabs, ticked check-offs, scrolled and moved the
-- window. So the main window takes no focus when it opens and ignores navigation
-- (buildWindow), none of its items can be reached by navigation, and because a
-- click inside a scrolling area hands the focus to that child window, which cannot
-- be told to ignore navigation (the extender passes a child window's flags to
-- ImGui in swapped order), every click gives the focus back to the main window.
-- -----------------------------------------------------------------------------

--- Gives the focus back to the main window, which ignores keyboard and controller
--- navigation.
function UI.KeepFocus()
    if UI.win and UI.open then pcall(function() UI.win:SetFocus() end) end
end

--- Sets an event handler (OnClick, OnChange) that also gives the focus back.
local function on(elem, event, fn)
    elem[event] = function(...)
        fn(...)
        UI.KeepFocus()
    end
end

--- Opening or closing a tree gives the focus back.
local function keepFocusOnToggle(tree)
    tree.OnExpand = function() UI.KeepFocus() end
    tree.OnCollapse = function() UI.KeepFocus() end
    return tree
end

--- A scrolling area (child window): a click on its empty space gives the focus back.
local function addChildWindow(parent, id)
    local area = parent:AddChildWindow(id)
    area.OnClick = function() UI.KeepFocus() end
    return area
end

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
local refreshApprovalLog     -- defined with the page refresh below
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--- Status, evidence index, and (for a step that is DONE from the choice memory)
--- the act it was remembered from.
local function stepResult(snap, id)
    local r = snap and snap.steps and snap.steps[id]
    if r then return r[1] or "?", r[2] or 0, r[3] end
    return "?", 0, nil
end

local function compSnapshot(snap, comp)
    return snap and snap.comps and snap.comps[comp.id] or nil
end

--- Act number -> act section key (the prologue lives in the Act 1 section).
local function actKey(act)
    if type(act) ~= "number" or act <= 1 then return 1 end
    return math.min(act, 3)
end

--- The act used for spoiler decisions: what the player has reached (at least 1).
local function reachedAct(snap)
    if snap and snap.ready then return math.max(1, math.min(snap.act or 1, 3)) end
    return 1
end

local function indexOf(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
    return 1
end

local function portraitsOn()
    return Set.Get("portraits") and true or false
end

-- Statuses whose meaning is obvious from the label alone get no explanation line.
local SELF_EXPLAINING = { N = true, A = true, U = true, ["?"] = true }

--- One plain sentence under a step: what the game recorded, or why it is closed.
--- `remembered` is the act a DONE step is remembered from, when the save itself no
--- longer shows it (0 = act unknown).
local function describeEvidence(comp, c, step, status, evidence, remembered, declined)
    if declined and Guides.IsRomanceStep(step) and (status == S.NA or status == S.AVAILABLE) then
        if status == S.AVAILABLE then
            return "You marked this romance as not wanted. This is where it can begin: turn " .. comp.name
                .. " down when asked."
        end
        return "Not wanted: you marked " .. comp.name .. "'s romance as not for this playthrough."
    end
    if status == S.DONE and remembered ~= nil and step.done[evidence] then
        local when = (type(remembered) == "number" and remembered >= 1) and (" in Act " .. remembered) or " earlier"
        return "Remembered: " .. Guides.Explain(step.done[evidence], comp, "done")
            .. ". The roadmap saw this" .. when .. "; your save no longer shows it."
    elseif status == S.DONE and evidence > 0 and step.done[evidence] then
        return "Detected: " .. Guides.Explain(step.done[evidence], comp, "done")
    elseif status == S.MISSED and evidence < 0 and step.fail[-evidence] then
        return "Missed: " .. Guides.Explain(step.fail[-evidence], comp, "fail")
    elseif status == S.NA and evidence > 0 and step.skip[evidence] then
        return "Not needed: " .. Guides.Explain(step.skip[evidence], comp, "skip")
    elseif status == S.MISSED and c and c.lost then
        if c.why == "died" then return "Missed: " .. comp.name .. " died before joining you" end
        return "Missed: " .. comp.name .. " is gone for this playthrough"
    elseif status == S.MISSED and step.closes then
        local d = Guides.DeadlineById[step.closes]
        return "Its window closed: " .. (d and d.title or step.closes)
    elseif status == S.CHOICE and step.alt then
        local others = {}
        for _, other in ipairs(Guides.AltGroups[step.alt] or {}) do
            if other ~= step then table.insert(others, other.title) end
        end
        if #others > 0 then return "Or instead: " .. table.concat(others, "  /  ") end
    end
    if SELF_EXPLAINING[status] then return "" end
    return T.StatusHelp[status] or ""
end

--- Whether this player marked the companion's romance as not wanted ("Not interested").
local function declinedRomance(snap, comp)
    return snap ~= nil and snap.nr ~= nil and comp ~= nil and snap.nr[comp.id] == true
end

-- -----------------------------------------------------------------------------
-- Tonight at camp, in words
-- -----------------------------------------------------------------------------

-- What a camp scene still needs, most useful first (see Tracker/Camp.lua for the codes).
local NEED_ORDER = { a = 1, p = 2, d = 2, s = 3, t = 4, f = 5 }

--- One thing a camp scene still needs, as words that follow "Needs" (or nil).
local function campNeed(b, comp, snap)
    local kind = b[1]
    local who = Guides.ById[b[2] or ""] or comp
    local name = who and who.name or "them"
    if kind == "a" then
        if b[4] ~= nil then return string.format("%d approval with %s (you have %d)", b[3], name, b[4]) end
        return string.format("%d approval with %s", b[3], name)
    elseif kind == "p" then
        return "you to be " .. name .. "'s partner"
    elseif kind == "d" then
        return "you to be dating " .. name
    elseif kind == "s" then
        return "a romance with " .. name .. " to be still possible"
    elseif kind == "t" then
        return name .. " at your camp"
    elseif kind == "f" then
        local step = b[3] and Guides.StepById[b[3]]
        if step and not (Set.Spoilers() == "hide" and step.act > reachedAct(snap)) then
            return '"' .. step.title .. '" first'
        end
        return "something else to happen in the story first"
    end
    return nil
end

local CAMP_STATE = {
    c = "It only plays at another camp.",
    q = "Ready, but a more important scene comes first: it waits for a later night.",
    x = "Its time ran out: the game drops it at your next long rest.",
}

--- Why a camp scene is not playing tonight, as one or two sentences. `skipApproval`
--- leaves out what the step's own approval line already says.
local function campWaiting(e, comp, snap, skipApproval)
    local needs, other = {}, {}
    for _, b in ipairs(e.b or {}) do
        if b[1] == "a" and skipApproval then
            -- shown above it: "Needs 40+ approval with ... - you have ..."
        elseif NEED_ORDER[b[1]] then
            local words = campNeed(b, comp, snap)
            if words then needs[#needs + 1] = { NEED_ORDER[b[1]], words } end
        elseif CAMP_STATE[b[1]] then
            other[#other + 1] = CAMP_STATE[b[1]]
        end
    end
    table.sort(needs, function(x, y) return x[1] < y[1] end)
    local parts = {}
    if #needs > 0 then
        local words = {}
        for _, n in ipairs(needs) do words[#words + 1] = n[2] end
        parts[1] = "Needs " .. table.concat(words, "; ") .. "."
    end
    for _, o in ipairs(other) do parts[#parts + 1] = o end
    return table.concat(parts, " ")
end

--- How many long rests a scene can still play at, in words (or nil).
local function campExpiry(e)
    if not e or e.x == nil or e.x <= 0 then return nil end
    if e.x == 1 then return "Last chance: only at your next long rest." end
    return string.format("It can only play at the next %d long rests.", e.x)
end

--- The line under a step that a camp scene completes, or "" (and its colour).
--- `inTab`: for the "Tonight at camp" tab, which needs no "Camp scene:" in front.
local function campLine(snap, comp, step, status, inTab)
    local camp = snap and snap.camp
    local e = camp and camp.ok and camp.steps and camp.steps[step.id]
    -- only for steps that are open now: some later-act scenes are registered early
    if not e or not OPEN_LIKE[status] then return "", T.C.dim end
    local expiry = campExpiry(e)
    if e.t then
        local text = "Tonight at camp: this scene plays at your next long rest."
        if declinedRomance(snap, comp) and Guides.IsRomanceStep(step) then
            text = "Tonight at camp: this romance can begin at your next long rest. Say no if you are asked."
        end
        return text .. (expiry and (" " .. expiry) or ""), T.C.good
    end
    local worrying = false
    for _, b in ipairs(e.b or {}) do
        if b[1] ~= "q" and b[1] ~= "c" then worrying = true end
    end
    local text = campWaiting(e, comp, snap, not inTab and step.approval ~= nil)
    if text == "" then text = "Waiting for a night at camp." end
    if not inTab then text = "Camp scene: " .. text end
    if expiry then text = text .. " " .. expiry end
    return text, (worrying or expiry) and T.C.warn or T.C.dim
end

local function evidenceColor(status)
    if status == S.MISSED then return T.C.bad end
    if status == S.INCOMPLETE then return T.C.warn end
    if status == S.CHOICE then return T.C.dim end
    return T.C.faint
end

local function trackingText(comp, step)
    local parts = {}
    for i, c in ipairs(step.done) do
        if i > 4 then table.insert(parts, "...") break end
        table.insert(parts, Guides.Describe(c, comp))
    end
    local text = "Detected by: " .. (#parts > 0 and table.concat(parts, " | ") or "manual check-off only")
    if #step.fail > 0 then
        local f = {}
        for i, c in ipairs(step.fail) do
            if i > 3 then table.insert(f, "...") break end
            table.insert(f, Guides.Describe(c, comp))
        end
        text = text .. "    Missed if: " .. table.concat(f, " | ")
    end
    return text
end

local function stepMeta(step)
    local parts = {}
    if step.where and step.where ~= "" then table.insert(parts, step.where) end
    if step.romance then table.insert(parts, "Romance") end
    if step.critical then table.insert(parts, "Important") end
    if step.optional then table.insert(parts, "Optional") end
    return table.concat(parts, T.SEP)
end

--- Programmatic tab switch: the flag must be cleared again or the tab sticks.
local function selectTab(tab)
    if not tab then return end
    T.SetProp(tab, "SetSelected", true)
    CR.After(300, function() T.SetProp(tab, "SetSelected", false) end)
end

local function addSmallButton(parent, label, onClick, sameLine)
    local b = parent:AddButton(label)
    T.SetFont(b, "small")
    if sameLine then b.SameLine = true end
    on(b, "OnClick", onClick)
    return b
end

local function addBar(parent)
    local bar = parent:AddProgressBar()
    bar.Size = { -1, 6 }
    T.SetProp(bar, "Overlay", " ")
    T.SetColor(bar, T.BarTrack, "FrameBg")
    return bar
end

-- -----------------------------------------------------------------------------
-- Options tab
-- -----------------------------------------------------------------------------
local function section(parent, title)
    local sep = parent:AddSeparatorText(title)
    T.SetColor(sep, T.C.gold)
    T.SetFont(sep, "strong")
    return sep
end

local function addCheckbox(parent, label, key)
    local cb = parent:AddCheckbox(label, Set.Get(key) and true or false)
    on(cb, "OnChange", function(_, value) Set.Set(key, value and true or false) end)
    UI.h.checks[key] = cb
    return cb
end

local function addCombo(parent, label, choices, current, onPick)
    local combo = parent:AddCombo(label)
    combo.Options = choices
    combo.SelectedIndex = math.max(0, (current or 1) - 1)
    T.SetProp(combo, "ItemWidth", 320)
    on(combo, "OnChange", function(_, index) onPick((tonumber(index) or 0) + 1) end)
    return combo
end

--- A 0-100 slider for a percentage setting. The extender passes the value as a
--- four-component vector ({ n, 0, 0, 0 }).
local function addPercentSlider(parent, label, key)
    -- guarded: if the extender ever refuses the slider, the rest of the Options tab must still build
    local ok, slider = pcall(function()
        return parent:AddSliderInt(label, math.floor(tonumber(Set.Get(key)) or 0), 0, 100)
    end)
    if not ok or not slider then
        CR.Warn("Could not create the '%s' slider: %s", key, tostring(slider))
        return nil
    end
    T.SetProp(slider, "ItemWidth", 320)
    on(slider, "OnChange", function(_, value)
        local v = type(value) == "table" and value[1] or value
        v = math.floor(tonumber(v) or 0)
        if v ~= Set.Get(key) then Set.Set(key, v) end
    end)
    return slider
end

--- The custom position sliders are only useful with the "Custom" choice.
local function refreshToastControls()
    local h = UI.h
    if not h.toastPos then return end
    local custom = Set.Get("toastPosition") == "custom"
    pcall(function() h.toastPos.SelectedIndex = (indexOf(Set.ToastKeys, Set.Get("toastPosition")) or 1) - 1 end)
    for key, slider in pairs({ toastX = h.toastX, toastY = h.toastY }) do
        T.Show(slider, custom)
        local v = math.floor(tonumber(Set.Get(key)) or 0)
        pcall(function()
            if slider.Value[1] ~= v then slider.Value = { v, 0, 0, 0 } end
        end)
    end
end

--- Any choice (here, in the Options tab or in MCM) answers the first-run question.
local function chooseSpoilers(key)
    Set.Set("spoilers", key)
end

local function buildLegend(parent)
    local tbl = parent:AddTable("##crLegend", 2)
    tbl:AddColumn("Status", "WidthFixed", STATUS_WIDTH)
    tbl:AddColumn("Meaning", "WidthStretch")
    for _, code in ipairs(T.StatusOrder) do
        local st = T.Status[code]
        local row = tbl:AddRow()
        local label = row:AddCell():AddText(st.label)
        T.SetFont(label, "small")
        T.SetColor(label, st.color)
        T.Text(row:AddCell(), T.StatusHelp[code], T.C.dim, "small")
    end
end

local function buildOptions(parent)
    UI.h.checks = {}
    -- hairline frames around checkboxes, combos and buttons on this page only
    T.SetStyle(parent, "FrameBorderSize", 1)

    section(parent, "Display")
    addCheckbox(parent, "Hide finished and not applicable steps", "hideCompleted")
    addCheckbox(parent, "Romance steps only", "romanceOnly")
    addCheckbox(parent, "Show how each step is detected (flags and journal entries)", "showTracking")
    addCheckbox(parent, "Show companion portraits", "portraits")
    UI.h.spoilers = addCombo(parent, "Spoilers for later acts", Set.SpoilerChoices,
        indexOf(Set.SpoilerKeys, Set.Get("spoilers")), function(i) chooseSpoilers(Set.SpoilerKeys[i]) end)
    UI.h.opacity = addCombo(parent, "Window opacity", Set.OpacityChoices,
        indexOf(Set.OpacityValues, Set.Get("opacity")), function(i) Set.Set("opacity", Set.OpacityValues[i]) end)
    parent:AddSpacing()

    section(parent, "Notifications")
    addCheckbox(parent, "Show a notice when a step is completed or missed", "notifications")
    addCheckbox(parent, "Notify for every step, not only romance and important ones", "notifyAll")
    addCheckbox(parent, "When the game asks if you are ready to pass a point of no return, show what is still open",
        "warnReadyChecks")
    addCheckbox(parent, "When a fight starts with a companion you can only recruit alive, remind you to knock them out",
        "koReminder")
    UI.h.toastPos = addCombo(parent, "Where notices appear", Set.ToastChoices,
        indexOf(Set.ToastKeys, Set.Get("toastPosition")), function(i) Set.Set("toastPosition", Set.ToastKeys[i]) end)
    UI.h.toastX = addPercentSlider(parent, "Across (0 = left edge, 100 = right edge)", "toastX")
    UI.h.toastY = addPercentSlider(parent, "Down (0 = top, 100 = bottom)", "toastY")
    local test = parent:AddButton("Show a test notice")
    T.SetFont(test, "small")
    on(test, "OnClick", function() if CR.Toasts then CR.Toasts.Preview() end end)
    refreshToastControls()
    parent:AddSpacing()

    section(parent, "Keys")
    UI.h.hotkeyText = T.Text(parent, "", T.C.text)
    UI.h.hotkeyBtn = parent:AddButton("Change hotkey")
    on(UI.h.hotkeyBtn, "OnClick", function()
        if not CR.Hotkey then return end
        T.Update(UI.h.hotkeyText, "Press the new key combination now (Esc cancels)...", T.C.warn)
        CR.Hotkey.BeginCapture(function() UI.RefreshHotkeyText() end)
    end)
    addCheckbox(parent, "Esc closes the roadmap", "escCloses")
    parent:AddSpacing()

    section(parent, "This save")
    local refresh = parent:AddButton("Refresh now")
    on(refresh, "OnClick", function() CR.Client.RequestRefresh(true) end)
    local reset = parent:AddButton("Clear all manual check-offs")
    reset.SameLine = true
    local armedAt = 0
    on(reset, "OnClick", function()
        local now = CR.Now()
        if now - armedAt < 4000 then
            armedAt = 0
            CR.Client.SetOverride("*", false)
            T.Update(reset, "Clear all manual check-offs")
        else
            armedAt = now
            T.Update(reset, "Click again to confirm")
        end
    end)
    T.Text(parent, "Check-offs are stored in your save file.", T.C.faint, "small")
    UI.h.memory = T.Text(parent, "", T.C.faint, "small")
    parent:AddSpacing()

    -- "Not interested": per save and per player, like check-offs (also on each companion's page)
    section(parent, "Romances you do not want")
    T.Text(parent, "Tick a companion whose romance you do not want in this playthrough. Their romance steps then "
        .. "only show where the romance can begin, so you know when to say no, and their romance notices stop. "
        .. "The roadmap cannot stop a romance in the game, only help you avoid it.", T.C.dim, "small")
    local grid = parent:AddTable("##crNoRomance", 2)
    grid:AddColumn("A", "WidthStretch")
    grid:AddColumn("B", "WidthStretch")
    UI.h.noRomance = {}
    local row, n = nil, 0
    for _, comp in ipairs(Guides.Companions) do
        if comp.romanceable then
            if n % 2 == 0 then row = grid:AddRow() end
            n = n + 1
            local cb = row:AddCell():AddCheckbox(comp.name .. "###nrOpt_" .. comp.id, false)
            T.SetFont(cb, "small")
            on(cb, "OnChange", function(_, checked) CR.Client.SetDeclined(comp.id, checked) end)
            UI.h.noRomance[comp.id] = cb
        end
    end
    parent:AddSpacing()

    section(parent, "Report a problem")
    T.Text(parent, "Found a wrong status or a missing step? Create a report file and attach it to your bug report. "
        .. "It lists what the tracker sees in this save: game identifiers only, nothing personal.", T.C.dim, "small")
    local report = parent:AddButton("Create a report file")
    UI.h.reportResult = T.Text(parent, "", T.C.faint, "small")
    T.Show(UI.h.reportResult, false)
    on(report, "OnClick", function()
        T.Update(UI.h.reportResult, "Writing the report...", T.C.faint)
        T.Show(UI.h.reportResult, true)
        CR.Client.RequestReport(function(ok, text)
            T.Update(UI.h.reportResult, text, ok and T.C.good or T.C.warn)
        end)
    end)
    parent:AddSpacing()

    section(parent, "Statuses")
    buildLegend(parent)
    parent:AddSpacing()

    section(parent, "About")
    T.Text(parent, "Companion & Romance Roadmap " .. tostring(CR.Version), T.C.text)
    T.Text(parent, "This mod is a work in progress. The guide and its detection will keep improving, and you may "
        .. "run into bugs or steps that are not detected. Please report them on the mod page.", T.C.dim, "small")
    T.Text(parent, "Diagnostics: open the Script Extender console and type  !roadmap", T.C.faint, "small")
end

function UI.RefreshHotkeyText()
    if not UI.h.hotkeyText then return end
    if Set.HasMCM() then
        T.Update(UI.h.hotkeyText, "The toggle key is set in the Mod Configuration Menu (Companion & Romance Roadmap).", T.C.dim)
        T.Show(UI.h.hotkeyBtn, false)
    else
        local desc = CR.Hotkey and CR.Hotkey.Describe() or "F7"
        T.Update(UI.h.hotkeyText, "Toggle key: " .. desc .. "   (with MCM installed it is set there)", T.C.text)
        T.Show(UI.h.hotkeyBtn, true)
    end
end

-- -----------------------------------------------------------------------------
-- Window
-- -----------------------------------------------------------------------------

--- Shows the picture that fits the companion's mood (T.Mood): dead, in love, pleased,
--- annoyed or neutral. The extender cannot re-point an existing image, so the
--- picture is rebuilt when it changes. `p.cell` holds nothing but the picture.
local function setPortrait(p, c)
    if not p then return end
    local mood = T.Mood(c)
    local picture = T.PortraitFor(p.comp.id, mood)
    if picture ~= p.shown then
        pcall(function() p.cell:RemoveAllChildren() end)
        p.img = T.Image(p.cell, picture, p.size)
        p.shown = picture
    end
    p.mood = mood
    -- a dead companion's picture says so by itself; one who left alive is faded
    local faded = c and c.lost and not c.dead
    T.SetProp(p.img, "Tint", faded and T.PortraitTint.lost or T.PortraitTint.normal)
end

--- A companion picture in `cell`, neutral until the first snapshot arrives.
local function addPortrait(cell, comp, size)
    local p = { cell = cell, comp = comp, size = size }
    setPortrait(p, nil)
    return p
end

--- (Re)builds the companion list. With portraits each entry is a table row, so a
--- picture that fails to load leaves an empty cell instead of breaking the layout.
local function buildSidebar()
    local side = UI.sideWin
    if not side then return end
    pcall(function() side:RemoveAllChildren() end)
    UI.sidebar = {}
    local pictures = portraitsOn()
    side.Size = { pictures and SIDEBAR_WIDTH_PORTRAITS or SIDEBAR_WIDTH, 0 }

    T.Label(side, "Companions")
    side:AddSpacing()
    local s = T.Scale()
    local tbl = nil
    if pictures then
        tbl = side:AddTable("##crSideTable", 2)
        tbl:AddColumn("Portrait", "WidthFixed", PORTRAIT_SIDE)
        tbl:AddColumn("Companion", "WidthStretch")
        T.SetStyle(tbl, "CellPadding", 4 * s, 6 * s)
    end
    for _, comp in ipairs(Guides.Companions) do
        local entry = {}
        local holder
        if tbl then
            local row = tbl:AddRow()
            entry.img = addPortrait(row:AddCell(), comp, PORTRAIT_SIDE)
            holder = row:AddCell()
        else
            holder = side:AddGroup("##grp_" .. comp.id)
        end
        T.SetStyle(holder, "ItemSpacing", 10 * s, 1 * s)
        entry.sel = holder:AddSelectable(comp.name .. "###sel_" .. comp.id)
        on(entry.sel, "OnClick", function() UI.Select(comp.id) end)
        entry.info = T.Text(holder, "", T.C.dim, "small")
        if not tbl then side:AddSpacing() end
        UI.sidebar[comp.id] = entry
    end
end

local function scrollArea(parent, id, padX, padY)
    local s = T.Scale()
    local area = addChildWindow(parent, id)
    area.Size = { 0, 0 }
    T.SetProp(area, "AlwaysUseWindowPadding", true)
    T.SetStyle(area, "WindowPadding", padX * s, padY * s)
    return area
end

local function buildWindow()
    local win = Ext.IMGUI.NewWindow("Companion & Romance Roadmap")
    UI.win = win
    win.Closeable = true
    win.OnClose = function() UI.SetOpen(false) end
    T.SetProp(win, "NoCollapse", true)
    -- no keyboard or controller navigation (see "Keyboard and controller navigation"):
    -- no focus when it opens, navigation input ignored, and NoItemNav/NoTabStop, which
    -- the extender pushes as item flags for everything drawn inside the window
    for _, flag in ipairs({ "NoFocusOnAppearing", "NoNavInputs", "NoNavFocus", "NoItemNav", "NoTabStop" }) do
        T.SetProp(win, flag, true)
    end
    T.SetProp(win, "Scaling", "Scaled")
    local vw, vh = T.Viewport()
    pcall(function()
        win:SetSize({ clamp(vw * 0.56, 860, 1640), clamp(vh * 0.80, 560, 1320) }, "FirstUseEver")
        win:SetPos({ vw * 0.5, vh * 0.5 }, "FirstUseEver", { 0.5, 0.5 })
        win:SetSizeConstraints({ 700, 460 }, { vw, vh })
    end)
    T.LoadFonts()
    T.ApplyWindow(win, Set.Get("opacity"))

    local h = UI.h
    h.act = T.Text(win, "Waiting for the game", T.C.gold, "heading")
    h.summary = T.Text(win, "", T.C.dim, "small")
    h.alert = win:AddSelectable("###crAlert")
    T.SetFont(h.alert, "small")
    T.SetColor(h.alert, T.C.warn)
    on(h.alert, "OnClick", function()
        T.SetProp(h.alert, "Selected", false)
        selectTab(h.tabWarn)
    end)
    T.Show(h.alert, false)
    -- patch-day check: only shown when the game no longer has something the guide watches
    h.gone = T.Text(win, "", T.C.warn, "small")
    T.Show(h.gone, false)

    -- asked once: how much may the roadmap reveal about acts not reached yet?
    h.firstRun = win:AddGroup("##crFirstRun")
    T.SetStyle(h.firstRun, "FrameBorderSize", 1)
    T.Text(h.firstRun, "How much may the roadmap reveal about acts you have not reached yet? Until you choose, "
        .. "later acts stay hidden. You can change this any time in Options.", T.C.gold, "small")
    addSmallButton(h.firstRun, "Everything", function() chooseSpoilers("full") end)
    addSmallButton(h.firstRun, "Step titles only", function() chooseSpoilers("titles") end, true)
    addSmallButton(h.firstRun, "Nothing from later acts", function() chooseSpoilers("hide") end, true)
    T.Show(h.firstRun, not Set.Get("spoilersChosen"))
    win:AddSpacing()

    h.tabs = win:AddTabBar("##crMain")
    h.tabRoadmap = h.tabs:AddTabItem("Companions###crTabRoadmap")
    h.tabCamp = h.tabs:AddTabItem("Tonight at camp###crTabCamp")
    h.tabWarn = h.tabs:AddTabItem("Before you move on###crTabWarn")
    h.tabOptions = h.tabs:AddTabItem("Options###crTabOptions")

    -- Companions: the list on the left, the selected companion on the right
    local s = T.Scale()
    local side = addChildWindow(h.tabRoadmap, "##crSidebar")
    T.SetProp(side, "AlwaysUseWindowPadding", true)
    T.SetColor(side, { 0, 0, 0, 0.22 }, "ChildBg")
    T.SetStyle(side, "WindowPadding", 14 * s, 12 * s)
    UI.sideWin = side
    buildSidebar()

    local content = addChildWindow(h.tabRoadmap, "##crContent")
    content.SameLine = true
    content.Size = { 0, 0 }
    T.SetProp(content, "AlwaysUseWindowPadding", true)
    T.SetStyle(content, "WindowPadding", 20 * s, 10 * s)
    UI.content = content

    -- Tonight at camp
    h.campBody = scrollArea(h.tabCamp, "##crCampScroll", 20, 12):AddGroup("##crCampBody")

    -- Before you move on
    h.warnBody = scrollArea(h.tabWarn, "##crWarnScroll", 20, 12):AddGroup("##crWarnBody")

    -- Options
    h.optionsGroup = scrollArea(h.tabOptions, "##crOptionsScroll", 20, 12):AddGroup("##crOptions")
    buildOptions(h.optionsGroup)
    UI.RefreshHotkeyText()
end

-- -----------------------------------------------------------------------------
-- Companion page
-- -----------------------------------------------------------------------------
local function buildStep(tbl, comp, step)
    local s = { step = step }
    s.row = tbl:AddRow()
    local statusCell = s.row:AddCell()
    local stepCell = s.row:AddCell()

    s.status = statusCell:AddText("...")
    T.SetFont(s.status, "small")
    T.SetColor(s.status, T.C.faint)
    T.SetProp(s.status, "PositionOffset", BASELINE_NUDGE)
    s.tip = T.Tooltip(s.status, "")

    s.tree = keepFocusOnToggle(stepCell:AddTree(step.title .. "###st_" .. step.id))
    T.SetProp(s.tree, "SpanAvailWidth", true)

    local meta = stepMeta(step)
    s.hasMeta = meta ~= ""
    s.meta = T.Text(s.tree, meta, T.C.dim, "small")
    T.Show(s.meta, s.hasMeta)
    s.req = T.Text(s.tree, "", T.C.text, "small")
    s.camp = T.Text(s.tree, "", T.C.dim, "small")      -- Tonight at camp, for steps a camp scene completes
    T.Show(s.camp, false)
    s.item = T.Text(s.tree, "", T.C.dim, "small")      -- "You have the Night Orchid", for steps that need an item
    T.Show(s.item, false)

    s.details = s.tree:AddGroup("##det_" .. step.id)
    if #step.todo > 0 then
        T.Label(s.details, "What to do")
        for _, line in ipairs(step.todo) do T.Bullet(s.details, line, T.C.text, T.BULLET, T.C.goldDim) end
    end
    if #step.avoid > 0 then
        T.Label(s.details, "Avoid", T.C.bad)
        for _, line in ipairs(step.avoid) do T.Bullet(s.details, line, T.C.text, T.CROSS, T.C.bad) end
    end
    if #step.changes > 0 then
        -- what a path costs or opens: information, not a warning
        T.Label(s.details, "What it changes")
        for _, line in ipairs(step.changes) do T.Bullet(s.details, line, T.C.text, T.BULLET, T.C.goldDim) end
    end
    if step.rewards then
        T.Label(s.details, "Rewards")
        T.Text(s.details, step.rewards, T.C.text)
    end
    if step.notes then T.Text(s.details, step.notes, T.C.dim, "italic") end
    if step.closes then
        local d = Guides.DeadlineById[step.closes]
        T.Text(s.details, "Last chance: " .. (d and d.title or step.closes), T.C.warn, "small")
    end
    s.tracking = T.Text(s.details, trackingText(comp, step), T.C.faint, "small")

    s.state = T.Text(s.tree, "", T.C.faint, "small")
    s.override = s.tree:AddCheckbox("I did this - mark it as done###ov_" .. step.id, false)
    T.SetFont(s.override, "small")
    T.SetColor(s.override, T.C.dim)
    on(s.override, "OnChange", function(_, checked) CR.Client.SetOverride(step.id, checked) end)
    s.tree:AddSpacing()
    return s
end

local function buildAct(parent, comp, def, page)
    local act = { def = def, steps = {} }
    act.header = keepFocusOnToggle(parent:AddTree(def.title .. "###act" .. def.key .. "_" .. comp.id))
    for _, flag in ipairs({ "Framed", "SpanAvailWidth", "NoTreePushOnOpen" }) do T.SetProp(act.header, flag, true) end
    T.SetFont(act.header, "heading")
    T.SetColor(act.header, T.C.gold)

    -- reset font and colour for everything inside the section
    act.body = act.header:AddGroup("##actbody" .. def.key)
    T.SetFont(act.body, "body")
    T.SetColor(act.body, T.C.text)
    act.table = act.body:AddTable("##steps" .. def.key, 2)
    act.table:AddColumn("Status", "WidthFixed", STATUS_WIDTH)
    act.table:AddColumn("Step", "WidthStretch")
    T.SetProp(act.table, "BordersInnerH", true)
    T.SetProp(act.table, "RowBg", true)
    for _, step in ipairs(comp.steps) do
        if def.acts[step.act] then
            local s = buildStep(act.table, comp, step)
            page.steps[step.id] = s
            table.insert(act.steps, s)
        end
    end
    act.empty = T.Text(act.body, "Nothing to show here with the current filters.", T.C.faint, "small")
    T.Show(act.empty, #act.steps == 0)
    act.body:AddSpacing()
    return act
end

local function buildCounters(parent, comp, page)
    for _, counter in ipairs(comp.counters) do
        local c = { def = counter, items = {} }
        c.label = T.Text(parent, counter.label, T.C.text, "small")
        c.bar = addBar(parent)
        local tree = keepFocusOnToggle(parent:AddTree("Details###cnt_" .. comp.id .. counter.id))
        T.SetFont(tree, "small")
        T.SetColor(tree, T.C.dim)
        c.help = T.Text(tree, counter.help or "", T.C.dim, "italic")
        for i, item in ipairs(counter.items) do
            local line, mark = T.Bullet(tree, item.label, T.C.dim, T.DOT, T.C.faint)
            c.items[i] = { line = line, mark = mark }
        end
        table.insert(page.counters, c)
    end
end

--- Golden rules / romance notes: one bullet per entry, plus a line that says how
--- many entries the spoiler setting is hiding.
local function buildNotes(tree, list, ornament, ornamentColor)
    local group = { items = {} }
    for _, note in ipairs(list) do
        local line, mark = T.Bullet(tree, note.text, T.C.text, ornament, ornamentColor)
        table.insert(group.items, { note = note, line = line, mark = mark })
    end
    group.hidden = T.Text(tree, "", T.C.faint, "small")
    T.Show(group.hidden, false)
    return group
end

--- Opens the current act, plus any earlier act that still has a NEXT or TO DO step
--- (some steps stay possible after their act ends), and folds the rest.
local function openActs(snap)
    local page = UI.page
    if not page then return end
    local ready = snap and snap.ready
    local current = ready and actKey(snap.act) or 1
    for key, a in pairs(page.acts) do
        local open = key == current
        if ready and key < current then
            for _, s in ipairs(a.steps) do
                local st = stepResult(snap, s.step.id)
                if ACT_NOW[st] or st == S.AVAILABLE then open = true break end
            end
        end
        pcall(function() a.header:SetOpen(open, "Always") end)
    end
end

local function buildPage(comp)
    local content = UI.content
    if not content then return end
    pcall(function() content:RemoveAllChildren() end)
    T.LoadFonts()
    local page = { comp = comp, steps = {}, acts = {}, counters = {}, openedNext = {} }
    UI.page = page

    -- name, subtitle and status sit next to the portrait when portraits are on
    local head = content
    local portrait = portraitsOn() and T.Portraits[comp.id] or nil
    if portrait then
        local tbl = content:AddTable("##crPageHead", 2)
        tbl:AddColumn("Portrait", "WidthFixed", PORTRAIT_PAGE + 6)
        tbl:AddColumn("Summary", "WidthStretch")
        local row = tbl:AddRow()
        page.portrait = addPortrait(row:AddCell(), comp, PORTRAIT_PAGE)
        head = row:AddCell()
    end
    T.Text(head, comp.name, T.C.gold, "title")
    if comp.subtitle and comp.subtitle ~= "" then T.Text(head, comp.subtitle, T.C.dim, "italic") end
    page.status = T.Text(head, "", T.C.text, "small")

    page.approval = addBar(content)
    -- the last approval changes (Tracker/ApprovalLog.lua); a shared id keeps it folded or open on every page
    page.alog = keepFocusOnToggle(content:AddTree("Recent approval changes###crApprovalLog"))
    T.SetFont(page.alog, "small")
    T.SetColor(page.alog, T.C.dim)
    page.alogBody = page.alog:AddGroup("##crApprovalLogBody")
    T.Show(page.alog, false)
    page.notice = T.Text(content, "", T.C.warn, "small")
    T.Show(page.notice, false)

    if #comp.counters > 0 then
        content:AddSpacing()
        buildCounters(content, comp, page)
    end

    -- Shared IDs: folding these on one companion folds them on every page.
    if #comp.rules > 0 then
        content:AddSpacing()
        local rules = keepFocusOnToggle(content:AddTree("Golden rules###crRules"))
        T.SetProp(rules, "DefaultOpen", true)
        T.SetColor(rules, T.C.bad)
        page.rules = buildNotes(rules, comp.rules, T.CROSS, T.C.bad)
    end

    -- The ways to lose any companion; the same on every page, so folded until asked for.
    if #Guides.CommonRules > 0 then
        local common = keepFocusOnToggle(content:AddTree("For every companion###crCommon"))
        T.SetColor(common, T.C.bad)
        page.common = buildNotes(common, Guides.CommonRules, T.CROSS, T.C.bad)
    end

    if #comp.romanceNotes > 0 then
        local romance = keepFocusOnToggle(content:AddTree((comp.romanceable and "Romance path" or "Romance")
            .. "###crRomance"))
        T.SetColor(romance, T.C.romance)
        page.notes = buildNotes(romance, comp.romanceNotes, T.BULLET, T.C.romance)
        if comp.romanceable then
            -- "Not interested" (requested on Nexus): stored in the save, for this player
            local cb = romance:AddCheckbox("Not interested in a romance with " .. comp.name
                .. " in this playthrough###nr_" .. comp.id, false)
            T.SetFont(cb, "small")
            T.SetColor(cb, T.C.dim)
            on(cb, "OnChange", function(_, checked) CR.Client.SetDeclined(comp.id, checked) end)
            page.noRomance = cb
        end
    end

    content:AddSpacing()
    addSmallButton(content, "Expand all", function() UI.SetAllOpen(true) end)
    addSmallButton(content, "Collapse all", function() UI.SetAllOpen(false) end, true)

    for _, def in ipairs(ACTS) do
        page.acts[def.key] = buildAct(content, comp, def, page)
    end
    openActs(CR.Client.Snapshot)
end

-- -----------------------------------------------------------------------------
-- Refresh (snapshot / settings changed)
-- -----------------------------------------------------------------------------
local function refreshHeader(snap)
    local h = UI.h
    local count = h.warnCount or 0
    T.Update(h.tabWarn, (count > 0 and string.format("Before you move on (%d)", count) or "Before you move on")
        .. "###crTabWarn")
    T.Show(h.firstRun, not Set.Get("spoilersChosen"))
    if not snap or not snap.ready then
        T.Update(h.act, "Waiting for the game", T.C.gold)
        T.Update(h.summary, "Load a save and the roadmap fills in by itself.", T.C.dim)
        T.Show(h.alert, false)
        T.Show(h.gone, false)
        return
    end
    local gone = tonumber(snap.gone) or 0
    if gone > 0 then
        T.Update(h.gone, string.format("Your game no longer has %d of the things this guide watches (a game update?). "
            .. "Some steps cannot be detected until the mod is updated; check them off by hand meanwhile.", gone), T.C.warn)
    end
    T.Show(h.gone, gone > 0)
    if h.memory then
        local n = tonumber(snap.mem) or 0
        T.Update(h.memory, string.format("The roadmap remembers %d %s from this save, so a step stays done even "
            .. "after the game forgets it. Console: !roadmap forget clears them.", n, n == 1 and "moment" or "moments"))
    end
    local actName = "Act " .. tostring(snap.act)
    if snap.act == 0 then actName = "Prologue" elseif (snap.act or 0) >= 4 then actName = "Epilogue" end
    local where = snap.region or snap.level or ""
    T.Update(h.act, where ~= "" and (actName .. T.SEP_SHORT .. where) or actName, T.C.gold)

    local partner, dating, done, total = {}, {}, 0, 0
    for _, comp in ipairs(Guides.Companions) do
        local c = compSnapshot(snap, comp)
        if c and c.rel == "partnered" then table.insert(partner, comp.name) end
        if c and c.rel == "dating" then table.insert(dating, comp.name) end
        for _, step in ipairs(comp.steps) do
            local st = stepResult(snap, step.id)
            if st ~= S.NA then
                total = total + 1
                if DONE_LIKE[st] then done = done + 1 end
            end
        end
    end
    local parts = {}
    table.insert(parts, "Partner: " .. (#partner > 0 and table.concat(partner, ", ") or "none"))
    if #dating > 0 then table.insert(parts, "Dating: " .. table.concat(dating, ", ")) end
    local m = snap.markers or {}
    if m.act1Locked and snap.act == 2 then table.insert(parts, "Act 1 is locked") end
    if m.colony and snap.act == 2 then table.insert(parts, "In the Colony") end
    if m.endgame then table.insert(parts, "Final battle started") end
    table.insert(parts, string.format("%d of %d steps done", done, total))
    T.Update(h.summary, table.concat(parts, T.SEP), T.C.dim)

    if count > 0 then
        T.Update(h.alert, string.format("%d %s to settle before you move on - click to review###crAlert", count,
            count == 1 and "thing" or "things"), T.C.warn)
    end
    T.Show(h.alert, count > 0)
end

--- One short line under a companion's name in the list.
local function companionLine(comp, c)
    if not c then return "", T.C.faint end
    if c.error then return "Error - see the console", T.C.bad end
    if c.you then return "Your character", T.C.gold end
    if c.lost then
        if c.why == "died" then return "Died before joining", T.C.bad end
        return "Lost for this playthrough", T.C.bad
    end
    if c.dead and not c.rec then return "Dead - can be revived", T.C.bad end
    local parts, color = {}, T.C.dim
    if c.dead then table.insert(parts, "Dead - revive") color = T.C.bad end
    local rel = c.rel and T.Relationship[c.rel]
    if rel then
        table.insert(parts, rel.label)
        if not c.dead then color = rel.color end
    end
    if c.rec then
        if c.a then
            table.insert(parts, string.format("%d %s", c.a, (CR.ApprovalTier(c.a))))
        else
            table.insert(parts, "In camp")
        end
    else
        table.insert(parts, "Not recruited")
        if not rel then color = T.C.faint end
    end
    return table.concat(parts, T.SEP_SHORT), color
end

local function refreshSidebar(snap)
    for _, comp in ipairs(Guides.Companions) do
        local entry = UI.sidebar[comp.id]
        if entry then
            local c = compSnapshot(snap, comp)
            local text, color = companionLine(comp, c)
            T.Update(entry.info, text, color)
            T.Show(entry.info, text ~= "")
            T.SetProp(entry.sel, "Selected", comp.id == UI.selected)
            local hasNext = false
            for _, step in ipairs(comp.steps) do
                if ACT_NOW[stepResult(snap, step.id)] then hasNext = true break end
            end
            local nameColor = hasNext and T.C.text or T.C.dim
            if comp.id == UI.selected then nameColor = T.C.gold end
            T.SetColor(entry.sel, nameColor)
            setPortrait(entry.img, c)
        end
    end
end

local function visibleByFilters(step, status)
    if Set.Get("hideCompleted") and (DONE_LIKE[status] or status == S.NA) then return false end
    if Set.Get("romanceOnly") and not step.romance then return false end
    if Set.Spoilers() == "hide" and status == S.UPCOMING then return false end
    return true
end

function UI.JumpTo(compId, stepId)
    UI.Select(compId)
    selectTab(UI.h.tabRoadmap)
    local page = UI.page
    local s = page and stepId and page.steps[stepId]
    if not s then return end
    local act = page.acts[actKey(s.step.act)]
    if act then pcall(function() act.header:SetOpen(true, "Always") end) end
    pcall(function() s.tree:SetOpen(true, "Always") end)
end

--- Collects what the "Before you move on" tab shows, as plain data. Also used by the
--- heads-up shown when the game asks about a point of no return (UI/Alerts.lua).
local function collectWarnings(snap)
    local groups, count = {}, 0
    local romanceOnly = Set.Get("romanceOnly")
    local declined = snap.nr or {}
    local hasPartner = false
    for _, comp in ipairs(Guides.Companions) do
        local c = compSnapshot(snap, comp)
        if c and c.rel == "partnered" then hasPartner = true end
    end
    local act = math.max(snap.act or 1, 1)
    for _, d in ipairs(Guides.Deadlines) do
        local reached = snap.markers and snap.markers[d.marker]
        if not reached and d.act <= act and d.act >= act - 1 then
            local g = { deadline = d, recruit = {}, important = {}, romance = {}, starts = {} }
            for _, comp in ipairs(Guides.Companions) do
                local c = compSnapshot(snap, comp)
                if c and not c.lost and not c.you then
                    local pursuing = c.rel == "dating" or c.rel == "partnered"
                    local altSeen = {}
                    for _, listed in ipairs(comp.steps) do
                        local st = stepResult(snap, listed.id)
                        local item = { comp = comp, step = listed, status = st }
                        if listed.alt and st == S.CHOICE then
                            -- open paths are one decision: list the group once, with every path in it,
                            -- and file it like its recruit path if it has one
                            if altSeen[listed.alt] then
                                item = nil
                            else
                                altSeen[listed.alt] = true
                                item.choices = {}
                                for _, other in ipairs(Guides.AltGroups[listed.alt] or {}) do
                                    if stepResult(snap, other.id) == S.CHOICE then table.insert(item.choices, other) end
                                end
                                for _, other in ipairs(item.choices) do
                                    if other.kind == "recruit" then item.step = other break end
                                end
                            end
                        end
                        local step = item and item.step or listed
                        if item and step.closes == d.id and OPEN_LIKE[st] then
                            if not c.rec then
                                -- never recruited: only the recruitment itself matters here
                                if step.kind == "recruit" and step.critical and not romanceOnly then
                                    table.insert(g.recruit, item)
                                end
                            elseif step.romanceStart then
                                -- not for a romance the player said they do not want
                                if not hasPartner and not pursuing and not declined[comp.id] then
                                    table.insert(g.starts, item)
                                end
                            elseif step.romance then
                                -- romance beats only matter for the companion you are pursuing
                                if pursuing and not (declined[comp.id] and Guides.IsRomanceStep(step)) then
                                    table.insert(g.romance, item)
                                end
                            elseif step.critical and not step.optional and not romanceOnly then
                                table.insert(g.important, item)
                            end
                        end
                    end
                end
            end
            count = count + #g.recruit + #g.important + #g.romance
            table.insert(groups, g)
        end
    end
    -- dead but not lost: in your camp (Withers can help), or one of the few who can
    -- still be revived before they ever joined
    local dead = {}
    for _, comp in ipairs(Guides.Companions) do
        local c = compSnapshot(snap, comp)
        if c and c.dead and not c.lost and not c.you and (c.rec or comp.revivable) then
            table.insert(dead, { comp = comp, rec = c.rec })
        end
    end
    count = count + #dead
    return groups, dead, count
end
UI.CollectWarnings = collectWarnings

local function warningsKey(groups, dead)
    local parts = {}
    for _, g in ipairs(groups) do
        table.insert(parts, g.deadline.id)
        for _, list in ipairs({ g.recruit, g.important, g.romance, g.starts }) do
            for _, item in ipairs(list) do table.insert(parts, item.step.id .. item.status) end
            table.insert(parts, "|")
        end
    end
    for _, d in ipairs(dead) do table.insert(parts, "dead:" .. d.comp.id .. (d.rec and "+" or "-")) end
    return table.concat(parts, ",")
end

local function warnLink(body, item, color)
    local st = T.Status[item.status] or T.Status["?"]
    local title = item.step.title
    if item.choices then
        local titles = {}
        for _, other in ipairs(item.choices) do table.insert(titles, other.title) end
        title = "choose a path: " .. table.concat(titles, "  /  ")
    end
    local sel = body:AddSelectable(string.format("%s   %s%s%s   (%s)###w_%s", T.BULLET, item.comp.name,
        T.SEP_SHORT, title, string.lower(st.label), item.step.id))
    T.SetColor(sel, color or T.C.text)
    on(sel, "OnClick", function()
        T.SetProp(sel, "Selected", false)
        UI.JumpTo(item.comp.id, item.step.id)
    end)
    return sel
end

local function names(list)
    local out = {}
    for _, item in ipairs(list) do table.insert(out, item.comp.name) end
    return table.concat(out, ", ")
end

local function refreshWarnings(snap)
    local h = UI.h
    if not h.warnBody then return end
    local groups, dead, count = {}, {}, 0
    local ready = snap and snap.ready
    if ready then groups, dead, count = collectWarnings(snap) end
    h.warnCount = count

    local key = ready and warningsKey(groups, dead) or "-"
    if key == h.warnKey then return end
    h.warnKey = key
    local body = h.warnBody
    pcall(function() body:RemoveAllChildren() end)

    if not ready then
        T.Text(body, "No game data yet. Load a save.", T.C.faint)
        return
    end
    T.Text(body, "Points of no return coming up, and what is still open before each one. "
        .. "Click an entry to open it.", T.C.dim, "small")
    body:AddSpacing()

    for _, g in ipairs(groups) do
        local d = g.deadline
        T.Text(body, d.title, T.C.gold, "heading")
        T.Text(body, d.text, T.C.dim, "small")
        local any = false
        if #g.recruit > 0 then
            T.Label(body, "Not recruited yet - last chance", T.C.warn)
            for _, item in ipairs(g.recruit) do warnLink(body, item) end
            any = true
        end
        if #g.important > 0 then
            T.Label(body, "Important steps still open", T.C.warn)
            for _, item in ipairs(g.important) do warnLink(body, item) end
            any = true
        end
        if #g.romance > 0 then
            T.Label(body, "Your romance", T.C.romance)
            for _, item in ipairs(g.romance) do warnLink(body, item) end
            any = true
        end
        if #g.starts > 0 then
            T.Label(body, "Romances that can only begin before this point", T.C.romance)
            T.Text(body, names(g.starts), T.C.text)
            any = true
        end
        if not any then
            T.Text(body, "Nothing important is left open here.", T.C.good, "small")
        end
        body:AddSpacing()
        body:AddSeparator()
        body:AddSpacing()
    end
    if #groups == 0 then
        T.Text(body, "No point of no return is close right now.", T.C.good)
    end
    if #dead > 0 then
        T.Label(body, "Dead companions", T.C.bad)
        for _, d in ipairs(dead) do
            local how = d.rec and "Revive them with Withers at camp or a Scroll of Revivify." or d.comp.revivable
            T.Bullet(body, d.comp.name .. " is dead. " .. how, T.C.text, T.CROSS, T.C.bad)
        end
    end
end

--- One scene the game would play tonight, in words: text, companion, guide step.
local function tonightLabel(entry)
    if entry.s then
        local step, owner = Guides.StepById[entry.s], Guides.StepOwner[entry.s]
        if step and owner then return owner.name .. T.SEP_SHORT .. step.title, owner, step end
    end
    local comp = entry.c and Guides.ById[entry.c] or nil
    if comp then return (entry.r and "A romance scene with " or "A scene with ") .. comp.name, comp, nil end
    if entry.d then return "A dream", nil, nil end
    if entry.e then return "A moment around the campfire", nil, nil end
    return "A camp scene", nil, nil
end

local CAMP_NOT_NOW = {
    locked = "You cannot rest at camp right now, so no camp scene can play.",
    fallback = "Your camp is not the usual one right now (you are on your way somewhere), so the roadmap cannot tell which scene plays.",
    nocamp = "There is no camp in this region yet.",
}

--- The "Tonight at camp" tab: what the game would play at your next long rest, and
--- what holds back the guide's other camp scenes. Rebuilt only when it changes.
local function refreshCamp(snap)
    local h = UI.h
    if not h.campBody then return end
    local camp = snap and snap.ready and snap.camp or nil
    local okKey, key = pcall(Ext.Json.Stringify, { camp or false, snap and snap.nr or false, Set.Spoilers(),
        snap and snap.steps and true or false })
    key = okKey and key or tostring(CR.Now())
    -- statuses decide which waiting scenes are listed
    if camp and camp.steps then
        local parts = { key }
        for id in pairs(camp.steps) do parts[#parts + 1] = id .. "=" .. stepResult(snap, id) end
        table.sort(parts)
        key = table.concat(parts, ";")
    end
    if key == h.campKey then return end
    h.campKey = key
    local body = h.campBody
    pcall(function() body:RemoveAllChildren() end)

    if not camp then
        T.Text(body, snap and snap.ready and "Open the roadmap again in a moment." or "No game data yet. Load a save.", T.C.faint)
        return
    end
    if not camp.ok then
        T.Text(body, CAMP_NOT_NOW[camp.why] or CAMP_NOT_NOW.nocamp, T.C.dim)
        return
    end

    T.Text(body, "If you rest now", T.C.gold, "heading")
    T.Text(body, "What the game would play at your next long rest. It picks the most important scene whose "
        .. "conditions are met, then others that do not clash with it. It decides when you rest, so anything "
        .. "that changes before then can change the pick.", T.C.dim, "small")
    if #camp.tonight == 0 then
        T.Text(body, "No camp scene is waiting for tonight: the night passes quietly.", T.C.text)
    end
    for i, entry in ipairs(camp.tonight) do
        local text, comp, step = tonightLabel(entry)
        if step then
            local sel = body:AddSelectable(string.format("%s   %s###tn_%d_%s", T.BULLET, text, i, step.id))
            T.SetColor(sel, T.C.text)
            on(sel, "OnClick", function()
                T.SetProp(sel, "Selected", false)
                UI.JumpTo(comp.id, step.id)
            end)
        else
            T.Bullet(body, text, T.C.dim, T.BULLET, T.C.goldDim)
        end
        local romance = (step and Guides.IsRomanceStep(step)) or (not step and entry.r)
        if romance and declinedRomance(snap, comp) then
            T.Text(body, "You do not want this romance: turn " .. comp.name .. " down if you are asked.", T.C.romance, "small")
        end
        local e = step and camp.steps[step.id]
        local expiry = campExpiry(e)
        if expiry then T.Text(body, expiry, T.C.warn, "small") end
    end
    body:AddSpacing()
    body:AddSeparator()
    body:AddSpacing()

    -- the guide's other scenes the game is holding, with what each one still needs
    local waiting = {}
    for _, comp in ipairs(Guides.Companions) do
        for _, step in ipairs(comp.steps) do
            local e = camp.steps[step.id]
            local st = stepResult(snap, step.id)
            local unwanted = declinedRomance(snap, comp) and Guides.IsRomanceStep(step)
            if e and not e.t and OPEN_LIKE[st] and not unwanted then
                waiting[#waiting + 1] = { comp = comp, step = step, e = e }
            end
        end
    end
    T.Text(body, "Waiting for a night at camp", T.C.gold, "heading")
    if #waiting == 0 then
        T.Text(body, "None of this guide's camp scenes is waiting right now.", T.C.dim, "small")
    end
    for _, w in ipairs(waiting) do
        local sel = body:AddSelectable(string.format("%s   %s%s%s###tw_%s", T.BULLET, w.comp.name, T.SEP_SHORT,
            w.step.title, w.step.id))
        T.SetColor(sel, T.C.text)
        on(sel, "OnClick", function()
            T.SetProp(sel, "Selected", false)
            UI.JumpTo(w.comp.id, w.step.id)
        end)
        local line, color = campLine(snap, w.comp, w.step, stepResult(snap, w.step.id), true)
        if line ~= "" then T.Text(body, line, color, "small") end
    end
    body:AddSpacing()
    T.Text(body, "Scenes that already played, can no longer happen or belong to a later act are not listed.",
        T.C.faint, "small")
end

--- Shows the rules / notes the spoiler setting allows and counts the hidden ones.
local function refreshNotes(group, act, spoilers)
    if not group then return end
    local hidden = 0
    for _, it in ipairs(group.items) do
        local show = spoilers == "full" or it.note.act <= act
        T.Show(it.line, show)
        T.Show(it.mark, show)
        if not show then hidden = hidden + 1 end
    end
    if hidden > 0 then
        T.Update(group.hidden, string.format("%d more for later acts %s hidden by your spoiler setting.", hidden,
            hidden == 1 and "is" or "are"))
    end
    T.Show(group.hidden, hidden > 0)
end

--- "Recent approval changes" under the approval bar, newest first. Rebuilt only when
--- the entries change.
function refreshApprovalLog(page, snap, c)
    if not page.alog then return end
    local comp = page.comp
    local log = snap and snap.ready and snap.alog or nil
    local list = log and log.c and log.c[comp.id] or nil
    local show = list ~= nil and #list > 0 and not (c and c.you)
    T.Show(page.alog, show)
    if not show then return end
    local okKey, key = pcall(Ext.Json.Stringify, { list, log.rests or 0 })
    key = okKey and key or tostring(CR.Now())
    if key == page.alogKey then return end
    page.alogKey = key
    local body = page.alogBody
    pcall(function() body:RemoveAllChildren() end)
    local tbl = body:AddTable("##crApprovalLogTable", 2)
    tbl:AddColumn("Change", "WidthFixed", 70)
    tbl:AddColumn("When", "WidthStretch")
    for i = #list, 1, -1 do
        local e = list[i]
        local row = tbl:AddRow()
        local d = tonumber(e.d)
        local color = (d and d > 0) and T.C.good or ((d and d < 0) and T.C.bad or T.C.dim)
        T.Text(row:AddCell(), d and string.format("%+d", d) or "-", color, "small")
        local who
        if e.c then
            local other = Guides.ById[e.c]
            who = "talking with " .. (other and other.name or tostring(e.c))
        elseif e.h then
            local name = e.h ~= "" and Guides.Loca(e.h) or nil
            who = name and ("talking with " .. name) or "in a conversation"
        else
            who = "outside a conversation"
        end
        local ago = (tonumber(log.rests) or 0) - (tonumber(e.r) or 0)
        local when = (ago <= 0 and "since your last long rest") or (ago == 1 and "1 long rest ago")
            or string.format("%d long rests ago", ago)
        T.Text(row:AddCell(), who .. T.SEP_SHORT .. when .. T.SEP_SHORT .. "now " .. tostring(e.v), T.C.dim, "small")
    end
end

local function refreshPage(snap)
    local page = UI.page
    if not page then return end
    local comp = page.comp
    local c = compSnapshot(snap, comp)
    local ready = snap and snap.ready
    local spoilers = Set.Spoilers()
    local act = reachedAct(snap)

    -- status line and approval
    local parts, color = {}, T.C.text
    if not ready then
        table.insert(parts, "Waiting for game data")
        color = T.C.dim
    elseif c then
        if c.you then table.insert(parts, "Your character")
        elseif c.lost then
            table.insert(parts, c.why == "died" and "Died before joining you" or "Lost for this playthrough")
            color = T.C.bad
        elseif c.rec then table.insert(parts, "In your camp")
        else table.insert(parts, "Not recruited yet") end
        if c.dead and not c.lost then
            table.insert(parts, c.rec and "Dead - revive them" or "Dead")
            color = T.C.bad
        end
        if c.rel and T.Relationship[c.rel] then table.insert(parts, T.Relationship[c.rel].label) end
        if c.a ~= nil and not c.you and (c.rec or c.a ~= 0) then
            table.insert(parts, string.format("Approval %d (%s)", c.a, (CR.ApprovalTier(c.a))))
        end
        if not comp.romanceable then table.insert(parts, "Not romanceable") end
    end
    T.Update(page.status, table.concat(parts, T.SEP), color)
    setPortrait(page.portrait, c)

    local showBar = c and c.a ~= nil and not c.you and (c.rec or c.a ~= 0)
    T.Show(page.approval, showBar and true or false)
    if showBar then T.SetProp(page.approval, "Value", clamp((c.a or 0) / 100, 0, 1)) end

    local notice = ""
    if c and c.you then
        notice = "You are playing this origin: recruitment and romance steps do not apply, the personal quest still does."
    elseif c and c.lost and c.why == "died" then
        notice = comp.name .. " died before joining you. In most cases a companion who dies before being recruited "
            .. "cannot be revived, so the remaining steps are marked as missed."
    elseif c and c.lost then
        -- say why when the tracker knows: the journal entry, or the game's own reason
        local why = Guides.ExplainLost(comp, c.lb)
        if why then
            notice = why .. " " .. comp.name .. " is gone for this playthrough; the remaining steps are marked as missed."
        else
            notice = comp.name .. " has died or left for good in this playthrough. The remaining steps are marked as missed."
        end
    elseif c and c.dead and not c.rec and comp.revivable then
        notice = comp.revivable
    elseif c and c.dead and c.rec then
        notice = "Revive " .. comp.name .. " with Withers at camp or with a Scroll of Revivify."
    end
    T.Update(page.notice, notice, T.C.warn)
    T.Show(page.notice, notice ~= "")

    -- counters (their names can be spoilers too)
    for _, counter in ipairs(page.counters) do
        local def = counter.def
        local data = c and c.cnt and c.cnt[def.id]
        local revealed = spoilers == "full" or (def.act or 0) <= act
        local value = 0
        for i, item in ipairs(counter.items) do
            local itemDef = def.items[i]
            local on = data and data.bits and data.bits[i] == 1
            if on then value = value + 1 end
            local known = on or spoilers == "full" or (itemDef.act or 0) <= act
            T.Update(item.mark, on and T.BULLET or T.DOT, on and T.C.good or T.C.faint)
            T.Update(item.line, known and itemDef.label or "A later moment", on and T.C.text or T.C.dim)
        end
        local n = #def.items
        local need = def.need or n
        local reached = (data and data.reached) or value >= need
        T.Update(counter.label, string.format("%s%s%d of %d%s%s", revealed and def.label or (def.alias or def.label),
            T.SEP, value, n, T.SEP, reached and "enough" or (need .. " needed")), reached and T.C.good or T.C.text)
        local help = revealed and (def.help or "") or (def.aliasHelp or "")
        T.Update(counter.help, help)
        T.Show(counter.help, help ~= "")
        T.SetProp(counter.bar, "Value", clamp(value / math.max(1, n), 0, 1))
    end

    refreshNotes(page.rules, act, spoilers)
    refreshNotes(page.common, act, spoilers)
    refreshNotes(page.notes, act, spoilers)

    -- Not interested in this romance (the checkbox follows changes made in Options)
    local declined = declinedRomance(snap, comp)
    if page.noRomance then
        pcall(function() if page.noRomance.Checked ~= declined then page.noRomance.Checked = declined end end)
    end

    refreshApprovalLog(page, snap, c)

    -- acts and steps
    local showTracking = Set.Get("showTracking")
    local currentKey = ready and actKey(snap.act) or 1
    for key, section in pairs(page.acts) do
        local done, total, visible = 0, 0, 0
        for _, s in ipairs(section.steps) do
            local step = s.step
            local st, ev, remembered = stepResult(snap, step.id)
            local info = T.Status[st] or T.Status["?"]
            local shown = (st == S.AVAILABLE and step.optional) and T.Status.OPT or info
            if st == S.AVAILABLE and declined and Guides.IsRomanceStep(step) then shown = T.Status.NO end
            T.Update(s.status, shown.label, shown.color)
            local band = ACT_NOW[st] and T.NextRowBg or T.Clear
            T.SetColor(s.row, band, "TableRowBg")
            T.SetColor(s.row, band, "TableRowBgAlt")
            T.Update(s.tip, (shown == T.Status.OPT and T.StatusHelp.OPT) or (shown == T.Status.NO and T.StatusHelp.NO)
                or T.StatusHelp[st] or "Waiting for game data.")
            T.SetColor(s.tree, info.title)

            if st ~= S.NA then
                total = total + 1
                if DONE_LIKE[st] then done = done + 1 end
            end
            local vis = visibleByFilters(step, st)
            T.Show(s.row, vis)
            if vis then visible = visible + 1 end

            -- approval requirement
            if step.approval then
                local a = c and c.a
                if a and not (c and c.you) then
                    local ok = a >= step.approval
                    T.Update(s.req, string.format("Needs %d+ approval with %s - you have %d%s", step.approval,
                        comp.name, a, ok and "" or " (too low)"), ok and T.C.good or T.C.warn)
                else
                    T.Update(s.req, string.format("Needs %d+ approval with %s", step.approval, comp.name), T.C.text)
                end
                T.Show(s.req, true)
            else
                T.Show(s.req, false)
            end

            -- Tonight at camp, for a step a camp scene completes
            local campText, campColor = "", T.C.dim
            if ready then campText, campColor = campLine(snap, comp, step, st) end
            T.Update(s.camp, campText, campColor)
            T.Show(s.camp, campText ~= "")

            -- the item the step needs: does the party have it (inventories and camp chest)?
            local has = step.item and c and c.items and c.items[step.id]
            if has ~= nil and has ~= false and OPEN_LIKE[st] then
                local text = has == 1 and ("You have " .. step.item.label .. ".")
                    or ("You do not have " .. step.item.label .. " yet.")
                T.Update(s.item, text, has == 1 and T.C.good or T.C.dim)
                T.Show(s.item, true)
            else
                T.Show(s.item, false)
            end

            local hideDetails = spoilers == "titles" and st == S.UPCOMING
            T.Show(s.details, not hideDetails)
            T.Show(s.meta, s.hasMeta and not hideDetails)
            T.Show(s.tracking, showTracking and true or false)
            local evidence = describeEvidence(comp, c, step, st, ev, remembered, declined)
            T.Update(s.state, evidence, evidenceColor(st))
            T.Show(s.state, evidence ~= "")

            local overridden = (snap and snap.ov and snap.ov[step.id]) and true or false
            pcall(function() if s.override.Checked ~= overridden then s.override.Checked = overridden end end)
            T.Show(s.override, st ~= S.DONE)

            if ACT_NOW[st] and not page.openedNext[step.id] then
                page.openedNext[step.id] = true
                pcall(function() s.tree:SetOpen(true, "Always") end)
            end
        end
        T.Show(section.empty, visible == 0)
        local label = section.def.title
        if total > 0 then label = string.format("%s%s%d of %d done", label, T.SEP_SHORT, done, total) end
        T.Update(section.header, label .. "###act" .. key .. "_" .. comp.id)
        T.Show(section.header, not (spoilers == "hide" and ready and key > currentKey))
    end
end

--- Options: the "Romances you do not want" checkboxes follow the save.
local function refreshOptions(snap)
    for id, cb in pairs(UI.h.noRomance or {}) do
        local on = declinedRomance(snap, Guides.ById[id])
        pcall(function() if cb.Checked ~= on then cb.Checked = on end end)
    end
end

function UI.Refresh(snap)
    if not UI.win then return end
    snap = snap or CR.Client.Snapshot
    CR.Guard("refresh warnings", refreshWarnings, snap)
    CR.Guard("refresh camp", refreshCamp, snap)
    CR.Guard("refresh options", refreshOptions, snap)
    CR.Guard("refresh header", refreshHeader, snap)
    CR.Guard("refresh sidebar", refreshSidebar, snap)
    CR.Guard("refresh page", refreshPage, snap)
    if snap and snap.ready and UI.forcedAct ~= snap.act then
        UI.forcedAct = snap.act
        openActs(snap)
    end
end

-- -----------------------------------------------------------------------------
-- Public API
-- -----------------------------------------------------------------------------
function UI.Select(compId)
    local comp = Guides.Get(compId) or Guides.Companions[1]
    if not comp then return end
    UI.selected = comp.id
    if Set.Get("lastCompanion") ~= comp.id then Set.Set("lastCompanion", comp.id) end
    CR.Guard("build page", buildPage, comp)
    UI.Refresh(CR.Client.Snapshot)
end

function UI.SetAllOpen(open)
    local page = UI.page
    if not page then return end
    for _, s in pairs(page.steps) do
        pcall(function() s.tree:SetOpen(open, "Always") end)
    end
    if open then
        for _, a in pairs(page.acts) do pcall(function() a.header:SetOpen(true, "Always") end) end
    else
        openActs(CR.Client.Snapshot)
    end
end

function UI.IsOpen() return UI.open end

function UI.SetOpen(open)
    if open then
        if not UI.win then
            local ok, err = pcall(buildWindow)
            if not ok then
                CR.Error("Could not create the roadmap window: %s", tostring(err))
                if UI.win then pcall(function() UI.win:Destroy() end) end
                UI.win = nil
                return
            end
            UI.Select(Set.Get("lastCompanion"))
        end
        UI.win.Open = true
        UI.open = true
        CR.Client.Hello(true, true)
        UI.Refresh(CR.Client.Snapshot)
    else
        if UI.win then pcall(function() UI.win.Open = false end) end
        UI.open = false
        CR.Client.Hello(false, false)
    end
end

function UI.Toggle()
    UI.SetOpen(not UI.open)
end

function UI.Init()
    CR.Client.OnSnapshot(function(snap)
        if UI.win and UI.open then UI.Refresh(snap) end
    end)
    Set.OnChange(function(key)
        if key == "toastPosition" or key == "toastX" or key == "toastY" then
            -- show where notices will go; nothing else in the window depends on it
            refreshToastControls()
            if CR.Toasts then CR.Toasts.Preview() end
            return
        end
        if not UI.win then return end
        if key == "opacity" then T.ApplyWindow(UI.win, Set.Get("opacity")) end
        local cb = UI.h.checks and UI.h.checks[key]
        if cb then pcall(function() cb.Checked = Set.Get(key) and true or false end) end
        if key == "spoilers" and UI.h.spoilers then
            pcall(function() UI.h.spoilers.SelectedIndex = indexOf(Set.SpoilerKeys, Set.Get("spoilers")) - 1 end)
        end
        if key == "opacity" and UI.h.opacity then
            pcall(function() UI.h.opacity.SelectedIndex = indexOf(Set.OpacityValues, Set.Get("opacity")) - 1 end)
        end
        if key == "romanceOnly" then UI.h.warnKey = nil end
        if key == "portraits" then
            -- pictures are part of the layout: rebuild the list and the open page
            CR.Guard("build sidebar", buildSidebar)
            if UI.selected then
                UI.Select(UI.selected)
                return
            end
        end
        UI.Refresh()
    end)
end
