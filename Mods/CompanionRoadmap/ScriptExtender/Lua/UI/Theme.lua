-- =============================================================================
-- UI/Theme.lua
-- Visual language of the roadmap, modelled on Baldur's Gate 3's own panels:
-- near-black translucent surfaces, a hairline bronze border, parchment text,
-- muted gold for headings, and colour used sparingly and only for meaning.
--
-- Text uses the game's own typeface (Quadraat). The Script Extender font atlas
-- only holds ASCII + Latin-1 glyphs, so every symbol used here is Latin-1:
-- middle dot (U+00B7), right guillemet (U+00BB) and multiplication sign (U+00D7).
-- =============================================================================

CR.Theme = CR.Theme or {}
local T = CR.Theme

local function rgb(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1.0 } end

T.C = {
    gold    = rgb(214, 182, 122),   -- headings, selection, the next step
    goldDim = rgb(158, 134, 94),    -- small labels
    text    = rgb(228, 219, 200),   -- parchment body text
    dim     = rgb(163, 153, 136),   -- secondary text
    faint   = rgb(112, 105, 94),    -- hints, inactive entries
    good    = rgb(146, 184, 124),   -- done
    warn    = rgb(224, 164, 92),    -- deadlines, needs attention
    bad     = rgb(208, 108, 94),    -- missed, dangerous
    romance = rgb(216, 146, 164),   -- romance
    info    = rgb(146, 174, 206),
}
T.C.avoid = T.C.bad
T.Clear = { 0, 0, 0, 0 }
T.NextRowBg = { 0.84, 0.71, 0.48, 0.07 }   -- faint gold band behind the NEXT step

-- Latin-1 punctuation used as ornaments
T.DOT = "\u{B7}"
T.SEP = "   \u{B7}   "       -- between facts on one line
T.SEP_SHORT = "  \u{B7}  "   -- the same in narrow places and headings
T.BULLET = "\u{BB}"
T.CROSS = "\u{D7}"

-- Status code -> short label for the status column, its colour, and the colour
-- of the step title (finished or unreachable steps recede).
T.Status = {
    N = { label = "NEXT",     color = T.C.gold,  title = T.C.text },
    A = { label = "TO DO",    color = T.C.text,  title = T.C.text },
    I = { label = "NOT SEEN", color = T.C.warn,  title = T.C.text },
    P = { label = "WAITING",  color = T.C.dim,   title = T.C.dim },
    U = { label = "LATER",    color = T.C.faint, title = T.C.dim },
    D = { label = "DONE",     color = T.C.good,  title = T.C.dim },
    O = { label = "CHECKED",  color = T.C.good,  title = T.C.dim },
    M = { label = "MISSED",   color = T.C.bad,   title = T.C.dim },
    X = { label = "N/A",      color = T.C.faint, title = T.C.faint },
    ["?"] = { label = "...",  color = T.C.faint, title = T.C.dim },
}

-- Order used by the status legend
T.StatusOrder = { "N", "A", "I", "P", "U", "D", "O", "M", "X" }

T.StatusHelp = {
    N = "The next thing to do for this companion.",
    A = "Can be done now.",
    I = "A step from an earlier act that the game never recorded. It may still be possible, or you did it in a way "
        .. "the game does not track. If you did it, check it off.",
    P = "Waits for an earlier step.",
    U = "Belongs to a later act.",
    D = "Detected in your save.",
    O = "You checked this off yourself.",
    M = "Missed: it failed, or its window has closed.",
    X = "Does not apply to the path you are on.",
}

T.Relationship = {
    partnered = { label = "Partnered", color = T.C.romance },
    dating    = { label = "Dating", color = T.C.romance },
    ex        = { label = "Ex-partner", color = T.C.dim },
    closed    = { label = "Romance ended", color = T.C.dim },
}

--- Muted colour for an approval value (the tracker's own tier colours are too loud for this UI).
function T.ApprovalColor(value)
    if type(value) ~= "number" then return T.C.dim end
    if value >= 41 then return T.C.good end
    if value >= 21 then return T.C.text end
    if value >= -19 then return T.C.dim end
    if value >= -39 then return T.C.warn end
    return T.C.bad
end

-- -----------------------------------------------------------------------------
-- Scale and fonts
-- -----------------------------------------------------------------------------
function T.Viewport()
    local ok, v = pcall(Ext.IMGUI.GetViewportSize)
    if ok and type(v) == "table" and (v[1] or 0) > 0 and (v[2] or 0) > 0 then return v[1], v[2] end
    return 1920, 1080
end

--- The Script Extender scales its own UI by viewport height / 1610 but leaves
--- per-element style values alone, so ours are scaled the same way by hand.
function T.Scale()
    local _, vh = T.Viewport()
    return math.max(0.5, math.min(3.0, vh / 1610))
end

-- Logical font -> font name. The defaults are the extender's built-in sizes of
-- Quadraat Regular (Tiny 24, Small 28, Medium 32, Default 36, Large 40, Big 44);
-- LoadFonts() swaps in heavier and italic cuts of the same typeface.
T.Fonts = {
    body = "Medium",
    small = "Small",
    tiny = "Tiny",
    italic = "Small",
    strong = "Medium",
    heading = "Default",
    title = "Big",
}

local FONT_DIR = "Public/Game/GUI/Assets/Fonts/QuadraatOffcPro/"
local CUSTOM_FONTS = {
    { key = "title",   name = "CompanionRoadmap_Title",   file = "QuadraatOffcPro-Demibold.ttf", size = 46 },
    { key = "heading", name = "CompanionRoadmap_Heading", file = "QuadraatOffcPro-Demibold.ttf", size = 34 },
    { key = "strong",  name = "CompanionRoadmap_Strong",  file = "QuadraatOffcPro-Demibold.ttf", size = 30 },
    { key = "italic",  name = "CompanionRoadmap_Italic",  file = "QuadraatOffcPro-Italic.ttf",   size = 29 },
}
local fontAttempts = 0

--- Loads the extra Quadraat cuts once IMGUI is up. Failure only means the
--- built-in regular cut is used instead.
function T.LoadFonts()
    if T.fontsLoaded or fontAttempts >= 3 then return end
    if not (Ext.IMGUI and Ext.IMGUI.LoadFont) then T.fontsLoaded = true return end
    fontAttempts = fontAttempts + 1
    local loaded = 0
    for _, f in ipairs(CUSTOM_FONTS) do
        local ok, res = pcall(Ext.IMGUI.LoadFont, f.name, FONT_DIR .. f.file, f.size)
        if ok and res then
            T.Fonts[f.key] = f.name
            loaded = loaded + 1
        end
    end
    if loaded == #CUSTOM_FONTS then
        T.fontsLoaded = true
    elseif loaded == 0 then
        CR.Debug("Custom fonts not loaded yet (attempt %d); using built-in sizes", fontAttempts)
    else
        T.fontsLoaded = true
    end
end

-- -----------------------------------------------------------------------------
-- Helpers (all protected: a styling failure must never break the UI)
-- -----------------------------------------------------------------------------
function T.SetColor(elem, rgba, slot)
    if elem and rgba then pcall(function() elem:SetColor(slot or "Text", rgba) end) end
end

function T.SetProp(elem, prop, value)
    if elem then pcall(function() elem[prop] = value end) end
end

function T.SetFont(elem, key)
    local name = T.Fonts[key] or key
    if elem and name then pcall(function() elem.Font = name end) end
end

function T.SetStyle(elem, var, a, b)
    if elem then pcall(function() elem:SetStyle(var, a, b) end) end
end

--- Adds a wrapped text line in a colour and (logical) font.
function T.Text(parent, text, color, font)
    local t = parent:AddText(text or "")
    T.SetProp(t, "TextWrapPos", 0)
    if color then T.SetColor(t, color) end
    if font then T.SetFont(t, font) end
    return t
end

--- Small upper-case label, used above lists ("WHAT TO DO", "AVOID").
function T.Label(parent, text, color)
    return T.Text(parent, string.upper(text), color or T.C.goldDim, "small")
end

--- A bullet line with a hanging indent: ornament + wrapped text.
--- Returns the text element and the ornament element.
function T.Bullet(parent, text, color, ornament, ornamentColor)
    local mark = parent:AddText(ornament or T.BULLET)
    T.SetColor(mark, ornamentColor or T.C.goldDim)
    T.SetProp(mark, "PositionOffset", { 6, 0 })
    local line = parent:AddText(text or "")
    line.SameLine = true
    T.SetProp(line, "TextWrapPos", 0)
    T.SetColor(line, color or T.C.text)
    return line, mark
end

--- Updates a text element only when the content actually changed.
function T.Update(elem, text, color)
    if not elem then return end
    pcall(function()
        if elem.Label ~= text then elem.Label = text end
    end)
    if color then T.SetColor(elem, color) end
end

function T.Show(elem, visible)
    if elem then pcall(function() if elem.Visible ~= visible then elem.Visible = visible end end) end
end

--- Adds a hover tooltip with one wrapped text line; returns that text.
function T.Tooltip(elem, text)
    local ok, line = pcall(function()
        local tip = elem:Tooltip()
        local t = tip:AddText(text or "")
        t.TextWrapPos = 460
        return t
    end)
    return ok and line or nil
end

-- -----------------------------------------------------------------------------
-- Window style
-- -----------------------------------------------------------------------------
local function goldA(a) return { 0.84, 0.71, 0.48, a } end

--- Colours and metrics for a window; children inherit them.
function T.ApplyWindow(win, opacity)
    local a = math.max(0.3, math.min(1.0, opacity or 0.95))
    local bg = { 0.047, 0.043, 0.039, a }
    local colors = {
        WindowBg             = bg,
        ChildBg              = { 0, 0, 0, 0 },
        PopupBg              = { 0.055, 0.050, 0.045, 0.98 },
        Border               = { 0.55, 0.45, 0.29, 0.50 },
        BorderShadow         = { 0, 0, 0, 0 },
        TitleBg              = bg,
        TitleBgActive        = { 0.066, 0.060, 0.053, a },
        TitleBgCollapsed     = bg,
        Text                 = T.C.text,
        TextDisabled         = T.C.faint,
        Header               = goldA(0.08),
        HeaderHovered        = goldA(0.12),
        HeaderActive         = goldA(0.18),
        Button               = goldA(0.07),
        ButtonHovered        = goldA(0.16),
        ButtonActive         = goldA(0.24),
        FrameBg              = goldA(0.07),
        FrameBgHovered       = goldA(0.12),
        FrameBgActive        = goldA(0.17),
        CheckMark            = T.C.gold,
        Tab                  = { 0, 0, 0, 0 },
        TabHovered           = goldA(0.10),
        TabActive            = goldA(0.15),
        TabUnfocused         = { 0, 0, 0, 0 },
        TabUnfocusedActive   = goldA(0.10),
        Separator            = { 0.55, 0.45, 0.29, 0.30 },
        SeparatorHovered     = { 0.55, 0.45, 0.29, 0.45 },
        SeparatorActive      = { 0.55, 0.45, 0.29, 0.60 },
        PlotHistogram        = { 0.80, 0.66, 0.42, 0.90 },
        PlotHistogramHovered = { 0.86, 0.72, 0.48, 1.00 },
        ScrollbarBg          = { 0, 0, 0, 0 },
        ScrollbarGrab        = goldA(0.16),
        ScrollbarGrabHovered = goldA(0.28),
        ScrollbarGrabActive  = goldA(0.40),
        ResizeGrip           = goldA(0.08),
        ResizeGripHovered    = goldA(0.22),
        ResizeGripActive     = goldA(0.36),
        TableBorderLight     = { 0.55, 0.45, 0.29, 0.16 },
        TableBorderStrong    = { 0.55, 0.45, 0.29, 0.30 },
        TableRowBg           = { 0, 0, 0, 0 },
        TableRowBgAlt        = { 0, 0, 0, 0 },
        TableHeaderBg        = goldA(0.06),
        TextSelectedBg       = goldA(0.25),
        NavHighlight         = goldA(0.50),
        ModalWindowDimBg     = { 0, 0, 0, 0.45 },
    }
    for slot, rgba in pairs(colors) do T.SetColor(win, rgba, slot) end

    local s = T.Scale()
    local styles = {
        { "WindowPadding", 20 * s, 16 * s },
        { "FramePadding", 10 * s, 5 * s },
        { "ItemSpacing", 10 * s, 7 * s },
        { "ItemInnerSpacing", 8 * s, 6 * s },
        { "CellPadding", 6 * s, 5 * s },
        { "IndentSpacing", (32 + 2 * 10) * s },
        { "ScrollbarSize", 9 * s },
        { "GrabMinSize", 12 * s },
        { "WindowRounding", 3 },
        { "ChildRounding", 2 },
        { "FrameRounding", 2 },
        { "PopupRounding", 2 },
        { "GrabRounding", 2 },
        { "TabRounding", 2 },
        { "ScrollbarRounding", 0 },
        { "WindowBorderSize", 1 },
        { "ChildBorderSize", 1 },
        { "PopupBorderSize", 1 },
        { "FrameBorderSize", 0 },
        { "TabBorderSize", 0 },
        { "TabBarBorderSize", 1 },
        { "SeparatorTextBorderSize", 1 },
        { "SeparatorTextPadding", 0, 6 * s },
        { "SeparatorTextAlign", 0, 0.5 },
        { "WindowTitleAlign", 0.5, 0.5 },
        { "ButtonTextAlign", 0.5, 0.5 },
        { "SelectableTextAlign", 0, 0.5 },
    }
    for _, st in ipairs(styles) do T.SetStyle(win, st[1], st[2], st[3]) end
end
