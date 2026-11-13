-- =============================================================================
-- mock_se.lua - a strict stand-in for the BG3 Script Extender, used by
-- tools/test_harness.py to run the mod's real Lua code outside the game.
--
-- The IMGUI mock is generated from BG3SE's property map (GameDefinitions/
-- PropertyMaps/IMGUI.inl, v33): unknown element types, properties, colour slots,
-- style vars, conditions or non Latin-1 text raise errors, exactly like the real
-- extender would refuse them (or render '?').
--
-- `Host` (a Python object) is injected before this file runs.
-- =============================================================================

local Mock = {}

-- ----------------------------------------------------------------------------- JSON
local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    for i = 1, n do if t[i] == nil then return false end end
    return true
end

local function encode(v)
    local tv = type(v)
    if tv == "nil" then return "null" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("cannot encode non-finite number") end
        if math.type(v) == "integer" then return tostring(v) end
        return string.format("%.14g", v)
    end
    if tv == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
            return map[c] or string.format("\\u%04x", c:byte())
        end) .. '"'
    end
    if tv == "table" then
        if next(v) == nil then return "{}" end
        local parts = {}
        if isArray(v) then
            for i = 1, #v do parts[#parts + 1] = encode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, val in pairs(v) do
            if type(k) ~= "string" and type(k) ~= "number" then error("cannot encode key of type " .. type(k)) end
            parts[#parts + 1] = encode(tostring(k)) .. ":" .. encode(val)
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("cannot encode value of type " .. tv)
end

-- ----------------------------------------------------------------------------- IMGUI
-- Every IMGUI misuse is recorded as well as raised: the mod wraps styling calls in
-- pcall, so a raised error alone could go unnoticed. Tests assert the list is empty.
Mock.Violations = {}
local function fail(msg, level)
    table.insert(Mock.Violations, msg)
    error(msg, (level or 1) + 1)
end
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

local GUI_COLOR = set { "Text", "TextDisabled", "WindowBg", "ChildBg", "PopupBg", "Border", "BorderShadow",
    "FrameBg", "FrameBgHovered", "FrameBgActive", "TitleBg", "TitleBgActive", "TitleBgCollapsed", "MenuBarBg",
    "ScrollbarBg", "ScrollbarGrab", "ScrollbarGrabHovered", "ScrollbarGrabActive", "CheckMark", "SliderGrab",
    "SliderGrabActive", "Button", "ButtonHovered", "ButtonActive", "Header", "HeaderHovered", "HeaderActive",
    "Separator", "SeparatorHovered", "SeparatorActive", "ResizeGrip", "ResizeGripHovered", "ResizeGripActive",
    "Tab", "TabHovered", "TabActive", "TabUnfocused", "TabUnfocusedActive", "TabDimmedSelectedOverline",
    "PlotLines", "PlotLinesHovered", "PlotHistogram", "PlotHistogramHovered", "TableHeaderBg", "TableBorderStrong",
    "TableBorderLight", "TableRowBg", "TableRowBgAlt", "TextLink", "TextSelectedBg", "DragDropTarget",
    "NavHighlight", "NavWindowingHighlight", "NavWindowingDimBg", "ModalWindowDimBg" }
local GUI_STYLE = set { "Alpha", "DisabledAlpha", "WindowPadding", "WindowRounding", "WindowBorderSize",
    "WindowMinSize", "WindowTitleAlign", "ChildRounding", "ChildBorderSize", "PopupRounding", "PopupBorderSize",
    "FramePadding", "FrameRounding", "FrameBorderSize", "ItemSpacing", "ItemInnerSpacing", "IndentSpacing",
    "CellPadding", "ScrollbarSize", "ScrollbarRounding", "GrabMinSize", "GrabRounding", "ImageBorderSize",
    "TabRounding", "TabBorderSize", "TabBarBorderSize", "TabBarOverlineSize", "TableAngledHeadersAngle",
    "TableAngledHeadersTextAlign", "ButtonTextAlign", "SelectableTextAlign", "SeparatorTextBorderSize",
    "SeparatorTextAlign", "SeparatorTextPadding" }
local GUI_COND = set { "Always", "Once", "FirstUseEver", "Appearing" }

local FLAGS = {
    Window = { "NoTitleBar", "NoResize", "NoMove", "NoScrollbar", "NoScrollWithMouse", "NoCollapse",
        "AlwaysAutoResize", "NoBackground", "NoSavedSettings", "NoMouseInputs", "MenuBar", "HorizontalScrollbar",
        "NoFocusOnAppearing", "NoBringToFrontOnFocus", "AlwaysVerticalScrollbar", "AlwaysHorizontalScrollbar",
        "NoNavInputs", "NoNavFocus", "UnsavedDocument", "NoNav", "NoDecoration", "NoInputs" },
    Child = { "Border", "AlwaysUseWindowPadding", "ResizeX", "ResizeY", "AutoResizeX", "AutoResizeY",
        "ChildAlwaysAutoResize", "FrameStyle", "NavFlattened" },
    Tree = { "Selected", "Framed", "AllowOverlap", "NoTreePushOnOpen", "NoAutoOpenOnLog", "DefaultOpen",
        "OpenOnDoubleClick", "OpenOnArrow", "Leaf", "Bullet", "FramePadding", "SpanAvailWidth", "SpanFullWidth",
        "SpanTextWidth", "SpanAllColumns", "NavLeftJumpsBackHere", "CollapsingHeader" },
    TabBar = { "Reorderable", "AutoSelectNewTabs", "TabListPopupButton", "NoCloseWithMiddleMouseButton",
        "NoTabListScrollingButtons", "NoTooltip", "DrawSelectedOverline", "FittingPolicyResizeDown", "FittingPolicyScroll" },
    TabItem = { "UnsavedDocument", "SetSelected", "NoCloseWithMiddleMouseButton", "NoPushId", "NoTooltip",
        "NoReorder", "Leading", "Trailing", "NoAssumedClosure" },
    Item = { "NoTabStop", "NoItemNav", "NoNavDefaultFocus", "ButtonRepeat", "AutoClosePopups", "AllowDuplicateId",
        "Disabled", "ItemReadOnly", "NoWindowHoverableCheck", "AllowItemOverlap", "NoNavDisableMouseHover", "NoMarkEdited" },
    Selectable = { "DontClosePopups", "SpanAllColumns", "AllowDoubleClick", "SelectableDisabled", "AllowOverlap", "Highlight" },
    Combo = { "PopupAlignLeft", "HeightSmall", "HeightRegular", "HeightLarge", "HeightLargest", "NoArrowButton",
        "NoPreview", "WidthFitPreview" },
    Button = { "MouseButtonLeft", "MouseButtonRight", "MouseButtonMiddle" },
    Table = { "Resizable", "Reorderable", "Hideable", "Sortable", "NoSavedSettings", "ContextMenuInBody", "RowBg",
        "BordersInnerH", "BordersOuterH", "BordersInnerV", "BordersOuterV", "BordersH", "BordersV", "BordersInner",
        "BordersOuter", "Borders", "NoBordersInBody", "NoBordersInBodyUntilResize", "SizingFixedFit",
        "SizingFixedSame", "SizingStretchProp", "SizingStretchSame", "NoHostExtendX", "NoHostExtendY",
        "NoKeepColumnsVisible", "PreciseWidths", "NoClip", "PadOuterX", "NoPadOuterX", "NoPadInnerX", "ScrollX",
        "ScrollY", "SortMulti", "SortTristate", "HighlightHoveredColumn" },
    TableRow = { "Headers" },
    TableColumn = { "Disabled", "DefaultHide", "DefaultSort", "WidthStretch", "WidthFixed", "NoResize", "NoReorder",
        "NoHide", "NoClip", "NoSort", "NoSortAscending", "NoSortDescending", "NoHeaderLabel", "NoHeaderWidth",
        "PreferSortAscending", "PreferSortDescending", "IndentEnable", "IndentDisable", "AngledHeader" },
}

-- Fonts the extender registers itself (IMGUIManager::InitializeUI); others come from Ext.IMGUI.LoadFont.
local BUILTIN_FONTS = { Tiny = true, Small = true, Medium = true, Default = true, Large = true, Big = true }
Mock.Fonts = {}

local CLASSES = {
    Renderable = { props = { "Handle", "Parent", "ParentElement", "UserData" }, funcs = { "Destroy" } },
    StyledRenderable = { base = "Renderable",
        props = { "Label", "IDContext", "SameLine", "SamePosition", "Visible", "RequestActivate", "WasHovered",
            "CanDrag", "DragPreview", "DragDropType", "Font", "PositionOffset", "AbsolutePosition", "ItemWidth",
            "TextWrapPos", "ItemFlags", "StatusFlags", "DragFlags", "DropFlags", "OnClick", "OnRightClick",
            "OnActivate", "OnDeactivate", "OnHoverEnter", "OnHoverLeave", "OnDragStart", "OnDragEnd", "OnDragDrop" },
        funcs = { "GetStyle", "SetStyle", "GetColor", "SetColor", "Activate", "Tooltip" },
        flags = { FLAGS.Item } },
    TreeParent = { base = "StyledRenderable", props = { "Children" },
        funcs = { "AddGroup", "AddCollapsingHeader", "AddTabBar", "AddTree", "AddTable", "AddPopup", "AddChildWindow",
            "AddMenu", "AddImage", "AddIcon", "AddSelectable", "AddButton", "AddImageButton", "AddText", "AddTextLink",
            "AddBulletText", "AddSeparatorText", "AddSpacing", "AddDummy", "AddNewLine", "AddSeparator", "AddCheckbox",
            "AddRadioButton", "AddInputText", "AddCombo", "AddDrag", "AddDragInt", "AddSlider", "AddSliderInt",
            "AddInputScalar", "AddInputInt", "AddColorEdit", "AddColorPicker", "AddProgressBar", "RemoveChild",
            "RemoveAllChildren", "DetachChild", "AttachChild" } },
    WindowBase = { base = "TreeParent", props = { "Flags", "LastSize", "LastPosition" },
        funcs = { "SetPos", "SetSize", "SetSizeConstraints", "SetContentSize", "SetCollapsed", "SetFocus", "SetScroll", "SetBgAlpha" },
        flags = { FLAGS.Window } },
    Window = { base = "WindowBase", props = { "Open", "Closeable", "Scaling", "OnClose", "MainMenu" }, funcs = { "AddMainMenu" } },
    ChildWindow = { base = "WindowBase", props = { "ChildFlags", "Size" }, flags = { FLAGS.Child } },
    Group = { base = "TreeParent" },
    CollapsingHeader = { base = "TreeParent", props = { "Flags" }, flags = { FLAGS.Tree } },
    TabBar = { base = "TreeParent", props = { "Flags" }, funcs = { "AddTabItem" }, flags = { FLAGS.TabBar } },
    TabItem = { base = "TreeParent", props = { "Flags" }, flags = { FLAGS.TabItem } },
    Tree = { base = "TreeParent", props = { "Flags", "OnExpand", "OnCollapse" }, funcs = { "SetOpen" }, flags = { FLAGS.Tree } },
    Text = { base = "StyledRenderable" },
    BulletText = { base = "StyledRenderable" },
    SeparatorText = { base = "StyledRenderable" },
    Spacing = { base = "StyledRenderable" },
    NewLine = { base = "StyledRenderable" },
    Separator = { base = "StyledRenderable" },
    Selectable = { base = "StyledRenderable", props = { "Size", "Flags", "Selected" }, flags = { FLAGS.Selectable } },
    Button = { base = "StyledRenderable", props = { "Size", "Flags" }, flags = { FLAGS.Button } },
    Checkbox = { base = "StyledRenderable", props = { "Checked", "OnChange" } },
    Combo = { base = "StyledRenderable", props = { "Options", "SelectedIndex", "Flags", "OnChange" }, flags = { FLAGS.Combo } },
    ProgressBar = { base = "StyledRenderable", props = { "Value", "Size", "Overlay" } },
    Table = { base = "TreeParent",
        props = { "Columns", "Flags", "FreezeRows", "FreezeCols", "ShowHeader", "AngledHeader", "OptimizedDraw",
            "ColumnDefs", "Sorting", "Size", "OnSortChanged" },
        funcs = { "AddRow", "AddColumn" }, flags = { FLAGS.Table } },
    TableRow = { base = "TreeParent", props = { "Flags", "MinHeight" }, funcs = { "AddCell" }, flags = { FLAGS.TableRow } },
    TableCell = { base = "TreeParent" },
    Tooltip = { base = "WindowBase" },
    Popup = { base = "WindowBase", funcs = { "Open" } },
}

local ADD_TYPES = {
    AddGroup = "Group", AddCollapsingHeader = "CollapsingHeader", AddTabBar = "TabBar", AddTree = "Tree",
    AddChildWindow = "ChildWindow", AddSelectable = "Selectable", AddButton = "Button", AddText = "Text",
    AddBulletText = "BulletText", AddSeparatorText = "SeparatorText", AddSpacing = "Spacing",
    AddNewLine = "NewLine", AddSeparator = "Separator", AddCheckbox = "Checkbox", AddCombo = "Combo",
    AddProgressBar = "ProgressBar", AddTabItem = "TabItem", AddTable = "Table", AddRow = "TableRow",
    AddCell = "TableCell", AddPopup = "Popup",
}
-- element types created without a label argument
local NO_LABEL = set { "Spacing", "NewLine", "Separator", "ProgressBar", "TableRow", "TableCell" }
local INTERACTIVE = set { "Button", "Checkbox", "Selectable", "Tree", "CollapsingHeader", "TabItem", "Combo",
    "ChildWindow", "TabBar", "Table", "Popup" }

-- resolve inherited members once
local RESOLVED = {}
local function resolve(name)
    if RESOLVED[name] then return RESOLVED[name] end
    local cls = CLASSES[name] or fail("unknown IMGUI class " .. name)
    local r = { props = {}, funcs = {}, flags = {} }
    if cls.base then
        local b = resolve(cls.base)
        for k in pairs(b.props) do r.props[k] = true end
        for k in pairs(b.funcs) do r.funcs[k] = true end
        for k in pairs(b.flags) do r.flags[k] = true end
    end
    for _, p in ipairs(cls.props or {}) do r.props[p] = true end
    for _, f in ipairs(cls.funcs or {}) do r.funcs[f] = true end
    for _, list in ipairs(cls.flags or {}) do for _, f in ipairs(list) do r.flags[f] = true end end
    RESOLVED[name] = r
    return r
end

local function checkLatin1(s, where)
    if type(s) ~= "string" then fail(where .. ": expected a string, got " .. type(s), 3) end
    for _, cp in utf8.codes(s) do
        if cp > 0xFF then
            fail(string.format("%s: character U+%04X cannot be drawn by the SE IMGUI font in %q", where, cp, s), 3)
        end
    end
end

local function idOf(label)
    local pos = string.find(label, "###", 1, true)
    if pos then return string.sub(label, pos) end
    return label
end

Mock.Elements = {}      -- all created elements (for tests)
Mock.Windows = {}
local nextHandle = 1

local Element = {}

local function newElement(typ, label, parent)
    local cls = resolve(typ)
    local raw = {
        __type = typ, __cls = cls, __children = {}, __destroyed = false, __parent = parent,
        __values = { Label = label or "", Visible = true, SameLine = false, Handle = nextHandle },
        __colors = {}, __styles = {},
    }
    nextHandle = nextHandle + 1
    local e = setmetatable(raw, Element)
    if label ~= nil then checkLatin1(label, typ .. " label") end
    if parent then
        -- duplicate interactive IDs among siblings break ImGui state
        if INTERACTIVE[typ] and label and label ~= "" then
            for _, sib in ipairs(parent.__children) do
                if not sib.__destroyed and INTERACTIVE[sib.__type] and idOf(sib.__values.Label) == idOf(label) then
                    fail(string.format("duplicate IMGUI id %q under %s", idOf(label), parent.__type), 3)
                end
            end
        end
        table.insert(parent.__children, e)
    end
    table.insert(Mock.Elements, e)
    return e
end

local function destroy(e)
    e.__destroyed = true
    for _, c in ipairs(e.__children) do destroy(c) end
    local tip = rawget(e, "__tooltip")
    if tip then destroy(tip) end
end

local function method(e, name)
    if name == "Destroy" then return function(self) destroy(self) end end
    if name == "SetColor" then
        return function(self, slot, rgba)
            if not GUI_COLOR[slot] then fail("SetColor: unknown GuiColor " .. tostring(slot), 2) end
            if type(rgba) ~= "table" or #rgba ~= 4 then fail("SetColor: expected {r,g,b,a}", 2) end
            self.__colors[slot] = rgba
        end
    end
    if name == "GetColor" then return function(self, slot) return self.__colors[slot] end end
    if name == "SetStyle" then
        return function(self, var, a, b)
            if not GUI_STYLE[var] then fail("SetStyle: unknown GuiStyleVar " .. tostring(var), 2) end
            if type(a) ~= "number" then fail("SetStyle: value must be a number", 2) end
            self.__styles[var] = { a, b }
        end
    end
    if name == "GetStyle" then return function(self, var) local s = self.__styles[var] return s and s[1] end end
    if name == "Tooltip" then
        -- one lazily created tooltip per element, drawn when the element is hovered
        return function(self)
            local tip = rawget(self, "__tooltip")
            if not tip then
                tip = newElement("Tooltip", "", nil)
                rawset(self, "__tooltip", tip)
            end
            return tip
        end
    end
    if name == "AddColumn" then
        return function(self, colName, flags, width)
            if type(colName) ~= "string" then fail("AddColumn: name must be a string", 2) end
            checkLatin1(colName, "AddColumn name")
            local list = flags
            if type(flags) == "string" then list = { flags } end
            if list ~= nil then
                if type(list) ~= "table" then fail("AddColumn: flags must be a string or a list", 2) end
                local valid = set(FLAGS.TableColumn)
                for _, f in ipairs(list) do
                    if not valid[f] then fail("AddColumn: unknown GuiTableColumnFlags " .. tostring(f), 2) end
                end
            end
            if width ~= nil and type(width) ~= "number" then fail("AddColumn: width must be a number", 2) end
            local defs = self.__values.ColumnDefs
            table.insert(defs, { Name = colName, Flags = list or {}, Width = width or 0 })
        end
    end
    if name == "Open" then return function(self) self.__values.Open = true end end
    if name == "SetPos" then
        return function(self, pos, cond, pivot)
            if type(pos) ~= "table" or #pos ~= 2 then fail("SetPos: expected {x,y}", 2) end
            if cond ~= nil and not GUI_COND[cond] then fail("SetPos: bad GuiCond " .. tostring(cond), 2) end
            if pivot ~= nil and (type(pivot) ~= "table" or #pivot ~= 2) then fail("SetPos: bad pivot", 2) end
        end
    end
    if name == "SetSize" then
        return function(self, size, cond)
            if type(size) ~= "table" or #size ~= 2 then fail("SetSize: expected {w,h}", 2) end
            if cond ~= nil and not GUI_COND[cond] then fail("SetSize: bad GuiCond " .. tostring(cond), 2) end
        end
    end
    if name == "SetSizeConstraints" then
        return function(self, a, b)
            if a ~= nil and #a ~= 2 then fail("SetSizeConstraints: bad min", 2) end
            if b ~= nil and #b ~= 2 then fail("SetSizeConstraints: bad max", 2) end
        end
    end
    if name == "SetOpen" then
        return function(self, open, cond)
            if type(open) ~= "boolean" then fail("SetOpen: expected boolean", 2) end
            if cond ~= nil and not GUI_COND[cond] then fail("SetOpen: bad GuiCond " .. tostring(cond), 2) end
            rawset(self, "__open", open)
        end
    end
    if name == "RemoveAllChildren" then
        return function(self)
            for _, c in ipairs(self.__children) do destroy(c) end
            self.__children = {}
        end
    end
    if name == "RemoveChild" then
        return function(self, child)
            for i, c in ipairs(self.__children) do
                if c == child then destroy(c) table.remove(self.__children, i) return true end
            end
            return false
        end
    end
    local addType = ADD_TYPES[name]
    if addType then
        return function(self, label, a)
            local needsLabel = not NO_LABEL[addType]
            if needsLabel and type(label) ~= "string" then fail(name .. ": label must be a string", 2) end
            if addType == "Table" and (math.type(a) ~= "integer" or a < 1) then
                fail("AddTable: column count must be a positive integer (ImGui crashes on 0 columns)", 2)
            end
            if addType == "TableCell" then
                local tbl = self.__parent
                local cols = math.max(tbl.__values.Columns or 0, #tbl.__values.ColumnDefs)
                if #self.__children >= cols then
                    fail(string.format("AddCell: row already has %d cells for a %d-column table", #self.__children, cols), 2)
                end
            end
            local child = newElement(addType, needsLabel and label or "", self)
            if addType == "Checkbox" then child.__values.Checked = a and true or false end
            if addType == "ProgressBar" then child.__values.Value = 0 end
            if addType == "Combo" then child.__values.Options = {} child.__values.SelectedIndex = 0 end
            if addType == "Table" then child.__values.Columns = a child.__values.ColumnDefs = {} end
            return child
        end
    end
    return function() fail("IMGUI method " .. name .. " is not implemented by the mock", 2) end
end

Element.__index = function(e, key)
    if rawget(e, "__destroyed") then fail("access to destroyed IMGUI element (" .. e.__type .. "." .. key .. ")", 2) end
    local cls = e.__cls
    if cls.funcs[key] then return method(e, key) end
    if cls.props[key] or cls.flags[key] then return e.__values[key] end
    fail("IMGUI " .. e.__type .. " has no property or method '" .. tostring(key) .. "'", 2)
end

Element.__newindex = function(e, key, value)
    if rawget(e, "__destroyed") then fail("write to destroyed IMGUI element", 2) end
    local cls = e.__cls
    if cls.flags[key] then
        if type(value) ~= "boolean" then fail(e.__type .. "." .. key .. " expects a boolean", 2) end
    elseif not cls.props[key] then
        fail("IMGUI " .. e.__type .. " has no property '" .. tostring(key) .. "'", 2)
    end
    if key == "Label" or key == "Overlay" then checkLatin1(value, e.__type .. "." .. key) end
    if key == "Font" and not (BUILTIN_FONTS[value] or Mock.Fonts[value]) then
        fail("IMGUI font '" .. tostring(value) .. "' is neither built in nor loaded with Ext.IMGUI.LoadFont", 2)
    end
    if key == "Scaling" and value ~= "Absolute" and value ~= "Scaled" then fail("bad Scaling value", 2) end
    if key == "Options" then
        for _, o in ipairs(value) do checkLatin1(o, "Combo option") end
    end
    if (key == "Size" or key == "PositionOffset") and (type(value) ~= "table" or #value ~= 2) then
        fail(key .. " expects {x,y}", 2)
    end
    if (key == "Value" or key == "TextWrapPos" or key == "ItemWidth") and type(value) ~= "number" then
        fail(key .. " expects a number", 2)
    end
    e.__values[key] = value
end

-- ----------------------------------------------------------------------------- Osi
local NULL = "NULL_00000000-0000-0000-0000-000000000000"

local function osiProxy(name)
    local p = {}
    p.Get = function(self, ...)
        local args = { ... }
        local n = select("#", ...)
        return Host:db_get(name, args, n)
    end
    return setmetatable(p, {
        __call = function(_, ...)
            local args = { ... }
            return Host:osi_call(name, args, select("#", ...))
        end,
    })
end

Osi = setmetatable({}, { __index = function(t, k) local p = osiProxy(k) rawset(t, k, p) return p end })

-- ----------------------------------------------------------------------------- Ext
local function newEvent(name)
    local ev = { handlers = {}, name = name }
    function ev:Subscribe(fn) table.insert(self.handlers, fn) return #self.handlers end
    function ev:Unsubscribe(id) self.handlers[id] = nil end
    function ev:Throw(e) for _, fn in pairs(self.handlers) do fn(e) end end
    return ev
end

local OSIRIS_EVENTS = {
    FlagSet = 3, FlagCleared = 3, QuestUpdateUnlocked = 3, ApprovalRatingChanged = 3,
    Died = 1, CharacterJoinedParty = 1, CharacterLeftParty = 1, LevelGameplayStarted = 2,
}
Mock.OsirisListeners = {}
Mock.ConsoleCommands = {}
Mock.Files = {}

local loaded = {}
local modEnv = setmetatable({}, { __index = _G })

Ext = {}
Ext.IsServer = function() return Host.is_server end
Ext.IsClient = function() return not Host.is_server end
Ext.Log = {
    Print = function(...) Host:log("info", table.concat({ ... }, " ")) end,
    PrintWarning = function(...) Host:log("warn", table.concat({ ... }, " ")) end,
    PrintError = function(...) Host:log("error", table.concat({ ... }, " ")) end,
}
Ext.Utils = { Print = Ext.Log.Print, PrintWarning = Ext.Log.PrintWarning, PrintError = Ext.Log.PrintError,
    MonotonicTime = function() return Host:now() end }
Ext.Json = {
    Stringify = function(v) return encode(v) end,
    Parse = function(s) return Host:json_parse(s) end,
}
Ext.Require = function(path)
    if loaded[path] ~= nil then return table.unpack(loaded[path]) end
    local src = Host:read_lua(path)
    local chunk, err = load(src, "@" .. path, "t", modEnv)
    if not chunk then error(err, 2) end
    local res = { chunk() }
    loaded[path] = res
    return table.unpack(res)
end
Ext.Timer = {
    WaitForRealtime = function(ms, fn) return Host:add_timer(ms, fn) end,
    WaitFor = function(ms, fn) return Host:add_timer(ms, fn) end,
    Cancel = function(h) return Host:cancel_timer(h) end,
    MonotonicTime = function() return Host:now() end,
}
Ext.IO = {
    LoadFile = function(p) return Mock.Files[p] end,
    SaveFile = function(p, c) assert(type(c) == "string") Mock.Files[p] = c return true end,
}
Ext.Vars = {
    vars = {},
    RegisterModVariable = function(uuid, name, opts) assert(uuid == ModuleUUID) assert(type(opts) == "table") end,
    GetModVariables = function(uuid) assert(uuid == ModuleUUID) return Ext.Vars.vars end,
}
Ext.Net = {
    CreateChannel = function(module, name)
        assert(module == ModuleUUID, "channel for wrong module")
        local ch = { name = name }
        function ch:SetHandler(fn) Host:set_handler(name, fn) end
        function ch:SendToServer(msg) assert(not Host.is_server, "SendToServer on server") Host:send(name, encode(msg), "server", nil) end
        function ch:SendToClient(msg, user) assert(Host.is_server, "SendToClient on client") Host:send(name, encode(msg), "client", user) end
        function ch:Broadcast(msg) assert(Host.is_server) Host:send(name, encode(msg), "client", nil) end
        return ch
    end,
}
Ext.Events = {}
for _, n in ipairs({ "SessionLoaded", "GameStateChanged", "KeyInput", "ResetCompleted", "Tick" }) do Ext.Events[n] = newEvent(n) end
Ext.ModEvents = {}
Ext.Osiris = {
    RegisterListener = function(name, arity, phase, fn)
        if OSIRIS_EVENTS[name] ~= arity then error("no Osiris event " .. name .. "/" .. tostring(arity), 2) end
        assert(phase == "after" or phase == "before")
        Mock.OsirisListeners[name] = Mock.OsirisListeners[name] or {}
        table.insert(Mock.OsirisListeners[name], fn)
    end,
}
Ext.RegisterConsoleCommand = function(name, fn) Mock.ConsoleCommands[name] = fn end
Ext.IMGUI = {
    NewWindow = function(label)
        local w = newElement("Window", label, nil)
        w.__values.Open = true
        table.insert(Mock.Windows, w)
        return w
    end,
    GetViewportSize = function() return Host.viewport or { 2560, 1440 } end,
    LoadFont = function(name, path, size)
        if type(name) ~= "string" or name == "" then error("LoadFont: name must be a non-empty string", 2) end
        if BUILTIN_FONTS[name] then error("LoadFont: refusing to replace the built-in font " .. name, 2) end
        if type(path) ~= "string" or type(size) ~= "number" or size <= 0 then error("LoadFont: bad path or size", 2) end
        Mock.Fonts[name] = { path = path, size = size }
        return true
    end,
}

ModuleUUID = "9f8b2c41-7a63-4d8e-9b5a-1c8e5f2a3d4e"
Mods = { CompanionRoadmap = modEnv }

function Mock.FireOsiris(name, ...)
    for _, fn in ipairs(Mock.OsirisListeners[name] or {}) do fn(...) end
end
function Mock.Env() return modEnv end
function Mock.FindByLabel(sub)
    for _, e in ipairs(Mock.Elements) do
        if not e.__destroyed and string.find(e.__values.Label or "", sub, 1, true) then return e end
    end
    return nil
end
function Mock.Encode(v) return encode(v) end

return Mock
