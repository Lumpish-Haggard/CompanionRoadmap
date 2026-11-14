-- =============================================================================
-- Tracker/FlagEvaluator.lua
-- Shared: status codes, approval tiers.
-- Server: reads the live save through Osiris (flags, journal, databases,
-- approval) and turns the guide data into a per-player snapshot.
--
-- Every Osiris access goes through a protected call and is cached for the
-- duration of one snapshot, so a missing flag or a game patch can never throw.
-- =============================================================================

CR.Eval = CR.Eval or {}
local E = CR.Eval
local Guides = CR.Guides

-- -----------------------------------------------------------------------------
-- Status codes (shared with the client)
-- -----------------------------------------------------------------------------
CR.Status = {
    DONE = "D",        -- detected in the save
    OVERRIDE = "O",    -- checked off manually
    NEXT = "N",        -- the next thing to do for this companion
    AVAILABLE = "A",   -- can be done now
    PENDING = "P",     -- waiting on an earlier step
    UPCOMING = "U",    -- belongs to a later act
    MISSED = "M",      -- failed, or its window closed
    NA = "X",          -- not applicable (other path taken, optional and skipped)
    INCOMPLETE = "I",  -- earlier act, not detected, may still be possible
}

-- -----------------------------------------------------------------------------
-- Approval tiers (bg3.wiki "Approval": -50 and below = leaves the party)
-- -----------------------------------------------------------------------------
CR.ApprovalTiers = {
    { min = 81, name = "Exceptional", color = { 0.35, 0.90, 0.45, 1 } },
    { min = 61, name = "Very High", color = { 0.45, 0.88, 0.50, 1 } },
    { min = 41, name = "High", color = { 0.60, 0.85, 0.55, 1 } },
    { min = 21, name = "Medium", color = { 0.85, 0.85, 0.50, 1 } },
    { min = -19, name = "Neutral", color = { 0.80, 0.80, 0.80, 1 } },
    { min = -39, name = "Low", color = { 0.95, 0.65, 0.35, 1 } },
    { min = -49, name = "Very Low", color = { 0.95, 0.40, 0.30, 1 } },
    { min = -100, name = "Leaving", color = { 1.00, 0.25, 0.25, 1 } },
}

function CR.ApprovalTier(value)
    if type(value) ~= "number" then return "Unknown", { 0.6, 0.6, 0.6, 1 } end
    for _, t in ipairs(CR.ApprovalTiers) do
        if value >= t.min then return t.name, t.color end
    end
    local last = CR.ApprovalTiers[#CR.ApprovalTiers]
    return last.name, last.color
end

-- Everything below talks to Osiris and only runs on the server.
if not Ext.IsServer() then return end

-- -----------------------------------------------------------------------------
-- Low level Osiris probes (protected)
-- -----------------------------------------------------------------------------
local USAGE_GLOBAL, USAGE_OBJECT = 1, 4

local function osiInt(fn, ...)
    if fn == nil then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

--- Rows of an Osiris database. Pass one argument per column; nil means "any value"
--- (table.pack keeps trailing nils, which a plain { ... } would drop).
local function dbRows(dbName, ...)
    local db = Osi[dbName]
    if db == nil then return nil end
    local args = table.pack(...)
    local ok, rows = pcall(function() return db:Get(table.unpack(args, 1, args.n)) end)
    if ok and type(rows) == "table" then return rows end
    return nil
end

local function dbHasRows(dbName, ...)
    local rows = dbRows(dbName, ...)
    return rows ~= nil and #rows > 0
end

local function dbFirstValue(dbName, ...)
    local rows = dbRows(dbName, ...)
    if rows and rows[1] then return rows[1][1] end
    return nil
end
E.DbRows = dbRows
E.DbHasRows = dbHasRows
E.DbFirstValue = dbFirstValue

-- -----------------------------------------------------------------------------
-- Context: one snapshot for one avatar (results are cached per context)
-- -----------------------------------------------------------------------------
local Context = {}
Context.__index = Context

function E.NewContext(avatar)
    return setmetatable({ avatar = avatar, cache = {}, comp = nil }, Context)
end

function Context:Flag(guid, target)
    if not guid or not target then return false end
    local key = guid .. "@" .. target
    local v = self.cache[key]
    if v == nil then
        v = osiInt(Osi.GetFlag, guid, target) == 1
        self.cache[key] = v
    end
    return v
end

function Context:Quest(quest, step)
    local key = "q:" .. quest .. "/" .. step
    local v = self.cache[key]
    if v == nil then
        v = osiInt(Osi.QuestUpdateIsUnlocked, CR.NULL, quest, step) == 1
        if not v and string.sub(quest, 1, 8) == "ORI_COM_" then
            v = osiInt(Osi.QuestUpdateIsUnlocked, CR.NULL, "ORI_Avatar_" .. string.sub(quest, 9), step) == 1
        end
        self.cache[key] = v
    end
    return v
end

function Context:Marker(marker)
    local name = Guides.Markers[marker]
    local entry = name and CR.Flags[name]
    if not entry then return false end
    return self:Flag(entry[1], CR.NULL)
end

function Context:FlagCond(cond)
    local entry = CR.Flags[cond.name]
    if not entry then return false end
    local guid, usage = entry[1], entry[2] or 0
    local on = cond.on
    if on == "global" then return self:Flag(guid, CR.NULL) end
    if on == "player" then return self.avatar ~= nil and self:Flag(guid, self.avatar) end
    if on == "companion" then return self.comp ~= nil and self:Flag(guid, self.comp.uuid) end
    -- "any": try every target the flag's usage allows
    if usage & USAGE_GLOBAL ~= 0 and self:Flag(guid, CR.NULL) then return true end
    if usage & USAGE_OBJECT ~= 0 then
        if self.avatar and self:Flag(guid, self.avatar) then return true end
        if self.comp and self:Flag(guid, self.comp.uuid) then return true end
    end
    return false
end

function Context:IsDead(comp)
    local key = "dead:" .. comp.uuid
    local v = self.cache[key]
    if v == nil then
        v = osiInt(Osi.IsDead, comp.uuid) == 1
        self.cache[key] = v
    end
    return v
end

function Context:IsPermaDefeated(comp)
    local key = "perma:" .. comp.uuid
    local v = self.cache[key]
    if v == nil then
        v = dbHasRows("DB_PermaDefeated", comp.uuid)
        self.cache[key] = v
    end
    return v
end

function Context:Recruited(comp)
    local key = "rec:" .. comp.uuid
    local v = self.cache[key]
    if v == nil then
        v = (comp.recruited ~= nil and self:Check(comp.recruited)) or dbHasRows("DB_PartOfTheTeam", comp.uuid)
        self.cache[key] = v
    end
    return v
end

function Context:KnockedOut(comp)
    if dbHasRows("DB_KnockedOut", comp.uuid) then return true end
    if comp.id == "Minthara" and dbHasRows("DB_ORI_Minthara_RemoveKnockedOutLater", 1) then return true end
    for _, status in ipairs({ "KNOCKED_OUT", "KNOCKED_OUT_PERMANENTLY", "KNOCKED_OUT_TEMPORARILY" }) do
        if osiInt(Osi.HasActiveStatus, comp.uuid, status) == 1 then return true end
    end
    return false
end

function Context:Relationship(comp, state)
    local r = comp.romance
    if not r or not self.avatar then return false end
    if state == "partnered" then
        return (r.partnered ~= nil and self:Check(r.partnered)) or dbHasRows("DB_ORI_Partnered", self.avatar, comp.uuid)
    elseif state == "dating" then
        return (r.dating ~= nil and self:Check(r.dating)) or dbHasRows("DB_ORI_Dating", self.avatar, comp.uuid)
    elseif state == "ex" then
        return r.ex ~= nil and self:Check(r.ex)
    end
    return false
end

--- Evaluates one condition from the data mini-language.
function Context:Check(cond)
    if type(cond) ~= "table" then return false end
    local k = cond.k
    if k == "q" then return self:Quest(cond.quest, cond.step) end
    if k == "f" then return self:FlagCond(cond) end
    if k == "any" then
        for _, c in ipairs(cond.list) do if self:Check(c) then return true end end
        return false
    end
    if k == "all" then
        for _, c in ipairs(cond.list) do if not self:Check(c) then return false end end
        return #cond.list > 0
    end
    if k == "not" then return not self:Check(cond.c) end
    local comp = self.comp
    if k == "rel" then return comp ~= nil and self:Relationship(comp, cond.state) end
    if k == "rec" then return comp ~= nil and self:Recruited(comp) end
    if k == "dead" then return comp ~= nil and (self:IsDead(comp) or self:IsPermaDefeated(comp)) end
    if k == "ko" then return comp ~= nil and self:KnockedOut(comp) end
    if k == "prog" then return self:Marker(cond.marker) end
    return false
end

--- Returns the 1-based index of the first true condition in a list, or nil.
function Context:FirstTrue(list)
    for i, c in ipairs(list or {}) do
        if self:Check(c) then return i end
    end
    return nil
end

-- -----------------------------------------------------------------------------
-- Campaign progress
-- -----------------------------------------------------------------------------
function E.CurrentLevel(avatar)
    local level = dbFirstValue("DB_CurrentLevel", nil)
    if type(level) == "string" and level ~= "" then return level end
    if avatar then
        local region = osiInt(Osi.GetRegion, avatar)
        if type(region) == "string" and region ~= "" then return region end
    end
    return nil
end

local function progress(ctx, avatar)
    local level = E.CurrentLevel(avatar)
    local levelAct, region = Guides.LevelInfo(level)
    local act = levelAct or 0
    for _, r in ipairs(Guides.VisitedRegions) do
        local entry = CR.Flags[r.flag]
        if entry and r.act > act and ctx:Flag(entry[1], CR.NULL) then act = r.act end
    end
    local markers = {}
    for id in pairs(Guides.Markers) do markers[id] = ctx:Marker(id) end
    if markers.act3 and act < 3 then act = 3 end
    if markers.act1Locked and act < 2 then act = 2 end
    if act > 3 then act = 3 end
    return { level = level, region = region, act = act, levelAct = levelAct, markers = markers }
end
E.Progress = progress

-- -----------------------------------------------------------------------------
-- Step evaluation
-- -----------------------------------------------------------------------------
local S = CR.Status
local SATISFIED = { [S.DONE] = true, [S.OVERRIDE] = true, [S.NA] = true }

local function evaluateCompanion(ctx, comp, prog, overrides)
    ctx.comp = comp
    local result = {}       -- stepId -> { status, evidence }
    local lost = false
    for _, c in ipairs(comp.left) do
        if ctx:Check(c) then lost = true break end
    end
    if not lost and ctx:IsPermaDefeated(comp) then lost = true end
    local isYou = ctx.avatar ~= nil and CR.Guid(ctx.avatar) == comp.uuid

    -- Died before ever joining: in most cases such a companion can no longer be
    -- revived or recruited (bg3.wiki "Dead"). The data marks the exceptions with
    -- `revivable`. A knocked-out Minthara or Minsc is not dead.
    local dead = ctx:IsDead(comp)
    local why = nil
    if not lost and not isYou and dead and not comp.revivable
        and not ctx:Recruited(comp) and not ctx:KnockedOut(comp) then
        lost, why = true, "died"
    end

    local visiting = {}
    local function eval(step)
        local cached = result[step.id]
        if cached then return cached[1] end
        if visiting[step.id] then return S.PENDING end
        visiting[step.id] = true

        local status, evidence = nil, 0
        local doneIdx = ctx:FirstTrue(step.done)
        if doneIdx then
            status, evidence = S.DONE, doneIdx
        elseif overrides[step.id] then
            status = S.OVERRIDE
        elseif isYou and (step.kind == "recruit" or step.romance) then
            status = S.NA
        else
            local skipIdx = ctx:FirstTrue(step.skip)
            local failIdx = (not skipIdx) and ctx:FirstTrue(step.fail) or nil
            if skipIdx then
                status, evidence = S.NA, skipIdx
            elseif failIdx then
                status, evidence = S.MISSED, -failIdx
            elseif lost then
                status = S.MISSED
            elseif step.closes and prog.markers[Guides.DeadlineById[step.closes].marker] then
                status = S.MISSED
            else
                local blocked, waiting = false, false
                for _, dep in ipairs(step.after or {}) do
                    local depStep = Guides.StepById[dep]
                    if depStep then
                        local ds = eval(depStep)
                        if ds == S.MISSED then blocked = true
                        elseif not SATISFIED[ds] then waiting = true end
                    end
                end
                if blocked then
                    status = S.MISSED
                elseif step.act > prog.act then
                    status = S.UPCOMING
                elseif waiting then
                    status = S.PENDING
                elseif step.act < prog.act and not step.closes then
                    status = step.optional and S.NA or S.INCOMPLETE
                else
                    status = S.AVAILABLE
                end
            end
        end
        visiting[step.id] = nil
        result[step.id] = { status, evidence }
        return status
    end

    for _, step in ipairs(comp.steps) do eval(step) end

    -- Alternatives: once one route of an 'alt' group is done, the others no longer apply.
    local doneAlt = {}
    for _, step in ipairs(comp.steps) do
        local r = result[step.id]
        if step.alt and (r[1] == S.DONE or r[1] == S.OVERRIDE) then doneAlt[step.alt] = true end
    end
    for _, step in ipairs(comp.steps) do
        local r = result[step.id]
        if step.alt and doneAlt[step.alt] and r[1] ~= S.DONE and r[1] ~= S.OVERRIDE then
            r[1], r[2] = S.NA, 0
        end
    end

    -- The first available step becomes "next" (required steps win over optional ones).
    local nextStep = nil
    for _, step in ipairs(comp.steps) do
        if result[step.id][1] == S.AVAILABLE then
            if not step.optional then nextStep = step break end
            nextStep = nextStep or step
        end
    end
    if nextStep then result[nextStep.id][1] = S.NEXT end

    -- Companion summary
    local info = {
        lost = lost,
        you = isYou,
        rec = ctx:Recruited(comp),
        dead = dead,
        why = why,          -- "died": lost because they died before joining
    }
    if not isYou and ctx.avatar then
        local a = osiInt(Osi.GetApprovalRating, comp.uuid, ctx.avatar)
        if type(a) == "number" then info.a = math.floor(a) end
    end
    if comp.romanceable and not isYou then
        if ctx:Relationship(comp, "partnered") then info.rel = "partnered"
        elseif ctx:Relationship(comp, "dating") then info.rel = "dating"
        elseif ctx:Relationship(comp, "ex") then info.rel = "ex"
        elseif comp.romance and comp.romance.closed and ctx:FirstTrue(comp.romance.closed) then info.rel = "closed" end
    end
    if #comp.counters > 0 then
        info.cnt = {}
        for _, counter in ipairs(comp.counters) do
            local bits = {}
            for i, item in ipairs(counter.items) do bits[i] = ctx:Check(item.cond) and 1 or 0 end
            local reached = counter.reached and ctx:Check(counter.reached) or false
            info.cnt[counter.id] = { bits = bits, reached = reached }
        end
    end
    ctx.comp = nil
    return result, info
end

--- Builds the complete snapshot for one avatar.
--- @param avatar string|nil  avatar GUID
--- @param overrides table    stepId -> true
function E.BuildSnapshot(avatar, overrides)
    overrides = overrides or {}
    local ctx = E.NewContext(avatar)
    local prog = progress(ctx, avatar)
    local snap = {
        p = CR.Protocol,
        v = CR.Version,
        ready = true,
        avatar = avatar and CR.Guid(avatar) or nil,
        level = prog.level,
        region = prog.region,
        act = prog.act,
        markers = prog.markers,
        steps = {},
        comps = {},
        ov = {},
    }
    for id, v in pairs(overrides) do if v then snap.ov[id] = true end end
    for _, comp in ipairs(Guides.Companions) do
        local ok, err = pcall(function()
            local steps, info = evaluateCompanion(ctx, comp, prog, overrides)
            for id, r in pairs(steps) do snap.steps[id] = r end
            snap.comps[comp.id] = info
        end)
        if not ok then
            CR.Error("Evaluating %s failed: %s", comp.id, tostring(err))
            snap.comps[comp.id] = { error = true }
        end
    end
    return snap, ctx
end
