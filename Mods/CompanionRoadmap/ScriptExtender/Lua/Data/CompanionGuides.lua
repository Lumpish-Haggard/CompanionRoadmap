-- =============================================================================
-- Data/CompanionGuides.lua
-- Guide registry, the condition mini-language used by the companion data files,
-- point-of-no-return definitions and lookup helpers. Loaded on client and server.
--
-- Every flag and journal step referenced by the data files is verified against
-- the game's own data by tools/build_data.py, which also generates Data/Flags.lua.
-- =============================================================================

CR.Guides = CR.Guides or {}
local Guides = CR.Guides

-- -----------------------------------------------------------------------------
-- Condition constructors (used by Data/Companions/*.lua)
--
--   Q(quest, step)   journal step unlocked. "ORI_COM_X" quests are also checked
--                    under "ORI_Avatar_X" so origin playthroughs are covered.
--   P(flag)          flag set on the player's avatar (romance/relationship flags)
--   G(flag)          global flag (camp nights, progress markers, quest states)
--   F(flag, on)      flag on "player" | "global" | "companion" | "any"
--   Rel(state)       relationship with this companion: "dating" | "partnered" | "ex"
--   Recruited()      this companion is currently part of the team (camp or party)
--   Dead()           this companion is dead
--   Prog(marker)     a progress marker was reached (see Guides.Markers)
--   KO()             Minthara-style "knocked out instead of killed" detection
--   Any{...} All{...} Not(c)
-- -----------------------------------------------------------------------------
CR.Cond = CR.Cond or {}
local C = CR.Cond

function C.Q(quest, step) return { k = "q", quest = quest, step = step } end
function C.F(name, on) return { k = "f", name = name, on = on or "any" } end
function C.P(name) return { k = "f", name = name, on = "player" } end
function C.G(name) return { k = "f", name = name, on = "global" } end
function C.Rel(state) return { k = "rel", state = state } end
function C.Recruited() return { k = "rec" } end
function C.Dead() return { k = "dead" } end
function C.Prog(marker) return { k = "prog", marker = marker } end
function C.KO() return { k = "ko" } end
function C.Any(list) return { k = "any", list = list } end
function C.All(list) return { k = "all", list = list } end
function C.Not(c) return { k = "not", c = c } end

-- -----------------------------------------------------------------------------
-- Progress markers and points of no return
-- -----------------------------------------------------------------------------

-- Global flags the server reads to know how far the campaign has progressed.
Guides.Markers = {
    act1Locked = "Act2_PointOfNoReturnReached",     -- entered Nightsong's prison in the Shadowfell
    lastLight  = "HAV_PartyProgress_EnteredHaven",  -- reached Last Light Inn
    moonrise   = "MOO_PartyProgress_EnteredMoonrise",
    sharTemple = "SHA_PartyProgress_EnteredSharTemple",
    colony     = "COL_PartyProgress_EnteredColony", -- went down into the Mind Flayer Colony
    act3       = "VISITEDREGION_BGO_Main_A",        -- reached Rivington / Wyrm's Crossing
    lowerCity  = "VISITEDREGION_CTY_Main_A",
    endgame    = "END_General_State_Started",       -- final assault on the Netherbrain began
}

-- Regions the game marks as visited, mapped to the act they belong to.
Guides.VisitedRegions = {
    { flag = "VISITEDREGION_WLD_Main_A", act = 1 },
    { flag = "VISITEDREGION_CRE_Main_A", act = 1 },
    { flag = "VISITEDREGION_SCL_Main_A", act = 2 },
    { flag = "VISITEDREGION_INT_Main_A", act = 2 },
    { flag = "VISITEDREGION_BGO_Main_A", act = 3 },
    { flag = "VISITEDREGION_CTY_Main_A", act = 3 },
    { flag = "VISITEDREGION_IRN_Main_A", act = 3 },
}

-- Level name prefix -> act and a readable region name.
Guides.Levels = {
    { prefix = "SYS_", act = 0, name = "Character Creation" },
    { prefix = "TUT_", act = 0, name = "Nautiloid (Prologue)" },
    { prefix = "WLD_", act = 1, name = "Wilderness / Underdark" },
    { prefix = "CRE_", act = 1, name = "Mountain Pass / Rosymorn Monastery" },
    { prefix = "SCL_", act = 2, name = "Shadow-Cursed Lands" },
    { prefix = "INT_", act = 2, name = "Act 2 Finale" },
    { prefix = "BGO_", act = 3, name = "Rivington / Wyrm's Crossing" },
    { prefix = "CTY_", act = 3, name = "Lower City" },
    { prefix = "IRN_", act = 3, name = "Iron Throne" },
    { prefix = "END_", act = 3, name = "Upper City / Netherbrain" },
    { prefix = "EPI_", act = 4, name = "Epilogue" },
}

function Guides.LevelInfo(level)
    if type(level) == "string" then
        local up = string.upper(level)
        for _, l in ipairs(Guides.Levels) do
            if string.sub(up, 1, #l.prefix) == l.prefix then return l.act, l.name end
        end
    end
    return nil, level or "Unknown"
end

-- Points of no return. `closes` on a step refers to one of these ids.
-- The UI lists unfinished important steps that close at the next deadline.
Guides.Deadlines = {
    {
        id = "act1", marker = "act1Locked", act = 1,
        title = "Act 1 locks for good when you enter the Shadowfell",
        text = "Travelling to the Shadow-Cursed Lands is not final yet, but stepping into Nightsong's prison "
            .. "in the Shadowfell (Gauntlet of Shar, Act 2) permanently locks you out of every Act 1 area: "
            .. "the Grove, Goblin Camp, Underdark, Grymforge, Mountain Pass and the Creche.",
    },
    {
        id = "colony", marker = "colony", act = 2,
        title = "Act 2 ends when you go down into the Mind Flayer Colony",
        text = "Taking the lift below Moonrise Towers into the Mind Flayer Colony starts the end of Act 2. "
            .. "You cannot long rest there, so any queued Act 2 romance night is lost, and prisoners still "
            .. "inside Moonrise (including Minthara) are left behind.",
    },
    {
        id = "act3", marker = "act3", act = 2,
        title = "Leaving Act 2 for Baldur's Gate",
        text = "Once you reach Rivington, the Shadow-Cursed Lands are gone. Halsin stays behind if the shadow "
            .. "curse was not lifted, and Act 2 companion beats that did not happen are skipped.",
    },
    {
        id = "lowercity", marker = "lowerCity", act = 3,
        title = "Entering the Lower City",
        text = "Some Rivington and Wyrm's Crossing events move on or close once the story continues in the Lower City.",
    },
    {
        id = "endgame", marker = "endgame", act = 3,
        title = "The final assault on the Netherbrain",
        text = "When the final battle begins, unfinished companion quests and Act 3 romance scenes stay unfinished.",
    },
}

Guides.DeadlineById = {}
for _, d in ipairs(Guides.Deadlines) do Guides.DeadlineById[d.id] = d end

-- -----------------------------------------------------------------------------
-- Companion registry
-- -----------------------------------------------------------------------------
Guides.Companions = {}       -- ordered list
Guides.ById = {}
Guides.ByUuid = {}
Guides.StepById = {}         -- stepId -> step
Guides.StepOwner = {}        -- stepId -> companion
Guides.StepIndex = {}        -- stepId -> position inside its companion
Guides.Errors = {}

local function addError(fmt, ...)
    local msg = string.format(fmt, ...)
    table.insert(Guides.Errors, msg)
    CR.Warn("Data: %s", msg)
end

local function normalizeList(v)
    if v == nil then return {} end
    if type(v) == "table" and v.k ~= nil then return { v } end
    return v
end

local VALID_ACTS = { [0] = true, [1] = true, [2] = true, [3] = true }

--- Called by each Data/Companions/*.lua file.
function Guides.Register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" then
        addError("Register() called without an id")
        return
    end
    if Guides.ById[def.id] then
        addError("companion '%s' registered twice", def.id)
        return
    end
    def.uuid = CR.Guid(def.uuid) or def.uuid
    def.steps = def.steps or {}
    def.left = normalizeList(def.left)
    def.counters = def.counters or {}
    def.rules = def.rules or {}
    def.romanceNotes = def.romanceNotes or {}

    for i, step in ipairs(def.steps) do
        if type(step.id) ~= "string" then
            addError("%s step #%d has no id", def.id, i)
        elseif Guides.StepById[step.id] then
            addError("duplicate step id '%s'", step.id)
        else
            if not VALID_ACTS[step.act] then addError("step '%s' has an invalid act", step.id) end
            if step.closes and not Guides.DeadlineById[step.closes] then
                addError("step '%s' closes at unknown deadline '%s'", step.id, tostring(step.closes))
            end
            step.done = normalizeList(step.done)
            step.fail = normalizeList(step.fail)
            step.skip = normalizeList(step.skip)
            step.todo = step.todo or {}
            step.avoid = step.avoid or {}
            Guides.StepById[step.id] = step
            Guides.StepOwner[step.id] = def
            Guides.StepIndex[step.id] = i
        end
    end

    table.insert(Guides.Companions, def)
    Guides.ById[def.id] = def
    if def.uuid then Guides.ByUuid[def.uuid] = def end
end

function Guides.Get(id)
    return Guides.ById[id] or Guides.ByUuid[CR.Guid(id) or ""]
end

-- -----------------------------------------------------------------------------
-- Static analysis: which flags and quests do the guides watch?
-- Used by the server to ignore the thousands of irrelevant FlagSet events.
-- -----------------------------------------------------------------------------
Guides.WatchedFlags = {}     -- guid -> true
Guides.WatchedQuests = {}    -- quest id -> true

local function flagGuid(name)
    local entry = CR.Flags and CR.Flags[name]
    return entry and entry[1] or nil
end
Guides.FlagGuid = flagGuid

local function visit(cond, owner)
    if type(cond) ~= "table" then return end
    local k = cond.k
    if k == "f" then
        local g = flagGuid(cond.name)
        if g then
            Guides.WatchedFlags[g] = true
        else
            addError("%s references unknown flag '%s'", owner, tostring(cond.name))
        end
    elseif k == "q" then
        Guides.WatchedQuests[cond.quest] = true
        if string.sub(cond.quest, 1, 8) == "ORI_COM_" then
            Guides.WatchedQuests["ORI_Avatar_" .. string.sub(cond.quest, 9)] = true
        end
    elseif k == "any" or k == "all" then
        for _, c in ipairs(cond.list or {}) do visit(c, owner) end
    elseif k == "not" then
        visit(cond.c, owner)
    end
end

function Guides.BuildIndex()
    Guides.WatchedFlags = {}
    Guides.WatchedQuests = {}
    for _, name in pairs(Guides.Markers) do visit(C.G(name), "markers") end
    for _, r in ipairs(Guides.VisitedRegions) do visit(C.G(r.flag), "regions") end
    for _, comp in ipairs(Guides.Companions) do
        local owner = comp.id
        visit(comp.recruited, owner)
        for _, c in ipairs(comp.left) do visit(c, owner) end
        if comp.romance then
            visit(comp.romance.dating, owner)
            visit(comp.romance.partnered, owner)
            visit(comp.romance.ex, owner)
            for _, c in ipairs(normalizeList(comp.romance.closed)) do visit(c, owner) end
        end
        for _, counter in ipairs(comp.counters) do
            for _, item in ipairs(counter.items or {}) do visit(item.cond, owner) end
        end
        for _, step in ipairs(comp.steps) do
            local who = owner .. "/" .. step.id
            for _, c in ipairs(step.done) do visit(c, who) end
            for _, c in ipairs(step.fail) do visit(c, who) end
            for _, c in ipairs(step.skip) do visit(c, who) end
            if step.after then
                for _, dep in ipairs(step.after) do
                    if not Guides.StepById[dep] then addError("step '%s' depends on unknown step '%s'", step.id, dep) end
                end
            end
        end
    end
end

-- -----------------------------------------------------------------------------
-- Human readable descriptions of conditions (shown in "How this is tracked")
-- -----------------------------------------------------------------------------
local REL_NAMES = { dating = "Dating", partnered = "Partnered", ex = "Ex-partner" }

function Guides.Describe(cond, comp)
    if type(cond) ~= "table" then return "?" end
    local k = cond.k
    if k == "q" then
        local title = CR.QuestTitles and CR.QuestTitles[cond.quest]
        return string.format("Journal: %s > %s", title or cond.quest, cond.step)
    elseif k == "f" then
        local where = (cond.on == "player" and " (on you)") or (cond.on == "global" and "") or ""
        return "Game flag " .. tostring(cond.name) .. where
    elseif k == "rel" then
        return "Relationship: " .. (REL_NAMES[cond.state] or tostring(cond.state))
    elseif k == "rec" then
        return (comp and comp.name or "Companion") .. " is in your camp/party"
    elseif k == "dead" then
        return (comp and comp.name or "Companion") .. " is dead"
    elseif k == "ko" then
        return "Knocked out instead of killed"
    elseif k == "prog" then
        return "Progress: " .. tostring(cond.marker)
    elseif k == "not" then
        return "NOT " .. Guides.Describe(cond.c, comp)
    elseif k == "any" or k == "all" then
        local parts = {}
        for _, c in ipairs(cond.list or {}) do table.insert(parts, Guides.Describe(c, comp)) end
        return table.concat(parts, (k == "any") and " OR " or " AND ")
    end
    return "?"
end

-- -----------------------------------------------------------------------------
-- Load companion data (display order = sidebar order)
-- -----------------------------------------------------------------------------
Guides.Order = {
    "Shadowheart", "Minthara", "Karlach", "Laezel", "Astarion",
    "Gale", "Wyll", "Halsin", "Jaheira", "Minsc",
}

for _, name in ipairs(Guides.Order) do
    local ok, err = pcall(Ext.Require, "Data/Companions/" .. name .. ".lua")
    if not ok then addError("failed to load Data/Companions/%s.lua: %s", name, tostring(err)) end
end

Guides.BuildIndex()

if #Guides.Errors == 0 then
    local steps = 0
    for _ in pairs(Guides.StepById) do steps = steps + 1 end
    CR.Debug("Loaded %d companions, %d steps, %d watched flags.", #Guides.Companions, steps, CR.Count(Guides.WatchedFlags))
end
