--[[
Manabar - mana bars for WoW Forever
(Interface 16001, runs on the Midnight-based Mainline client)

One bar per player of the selected group roles (healer / dps / tank) in your
party or raid, grouped by role with the healers first. By default every mana
user is shown out of combat and only the healers in combat. Each bar shows the
player's name, the mana percentage and a "drinking" indicator.
The bar color follows the mana: 100% green -> 50% yellow -> 0% red. An optional
summary bar at the bottom shows the average. The frame can be dragged while
unlocked; the gear icon (or /manabar) opens the settings window (Options.lua).

Secret values: WoW Forever ships with Midnight's addon restrictions. In combat
the game may hand addons the mana of other players as "secret" values, which
addon code must not do math on or compare. Mana therefore only flows through
UnitPowerPercent() + curve objects straight into widget methods that accept
secrets (StatusBar:SetValue, FontString:SetFormattedText,
Texture:SetVertexColor). Plain Lua math (like the average) is only done on
values that are known not to be secret.
]]

local ADDON_NAME, ns = ...
ADDON_NAME = ADDON_NAME or "Manabar"
ns = ns or {}

-------------------------------------------------------------------------------
-- Settings and constants
-------------------------------------------------------------------------------

local DEFAULTS = {
    locked       = false,
    scale        = 1,
    width        = 180,
    height       = 18,
    showSelf     = true,  -- your own bar too (if your role is selected)
    healersInCombat = true, -- narrow the list to the healers while in combat
    hideInCombat = false, -- only show the frame out of combat
    roleHeaders  = true,  -- a header per role, with the role's average mana
    summary      = true,  -- overall average at the bottom (when it adds something)
    showUnknown  = false, -- show players whose spec is not known yet (when it matters)
    specIcons    = true,  -- spec icon at the start of each bar
    lang         = "hu",
    debug        = false,
}

-- Bar color by mana: { fraction, r, g, b }. 0% red -> 50% yellow -> 100% green.
local GRADIENT = {
    { 0.0, 1, 0, 0 },
    { 0.5, 1, 1, 0 },
    { 1.0, 0, 1, 0 },
}
local STATE_COLOR = { 0.4, 0.4, 0.4 } -- offline / dead / unknown
local MANA_COLOR  = { 0.3, 0.55, 1 }  -- when no color can be worked out

-- Added to the percentage so float rounding (0.29 * 100 = 28.9999...) never
-- makes "%d" show one percent too little.
local PCT_EPSILON = 0.0005

local PAD              = 4
local HEADER_HEIGHT    = 16
local BAR_GAP          = 2
local SUMMARY_GAP      = 4
local GROUP_GAP        = 4   -- between the role groups
local DIRTY_INTERVAL   = 0.1 -- seconds between event driven bar updates
local REFRESH_INTERVAL = 0.5 -- seconds between full refreshes (state, drinking)
local REBUILD_DELAY    = 0.2 -- debounce for roster rebuilds
local MAX_AURAS        = 40
local INSPECT_INTERVAL = 2   -- seconds between our inspect requests
local INSPECT_TIMEOUT  = 5
local INSPECT_RETRY    = 30  -- seconds before trying a unit again

local BAR_TEXTURE       = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE_TEXTURE     = "Interface\\Buttons\\WHITE8x8"
local DRINK_ICON        = "Interface\\Icons\\INV_Drink_07"
local GEAR_ICON         = "Interface\\Icons\\INV_Misc_Gear_01"
local UNKNOWN_SPEC_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local FONT              = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local PT_MANA           = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Classes offered in the settings window: the mana users of WoW Forever.
local SPEC_CLASSES = { "PRIEST", "PALADIN", "SHAMAN", "DRUID", "MAGE", "WARLOCK", "HUNTER" }
local CLASS_IDS = { PALADIN = 2, HUNTER = 3, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local CLASS_NAMES_EN = {
    PRIEST = "Priest", PALADIN = "Paladin", SHAMAN = "Shaman", DRUID = "Druid",
    MAGE = "Mage", WARLOCK = "Warlock", HUNTER = "Hunter",
}
-- Only used if the game does not report the specializations of a class.
local FALLBACK_SPECS = {
    PRIEST  = { { 256, "Discipline", "HEALER" }, { 257, "Holy", "HEALER" }, { 258, "Shadow", "DAMAGER" } },
    PALADIN = { { 65, "Holy", "HEALER" }, { 66, "Protection", "TANK" }, { 70, "Retribution", "DAMAGER" } },
    SHAMAN  = { { 262, "Elemental", "DAMAGER" }, { 263, "Enhancement", "DAMAGER" }, { 264, "Restoration", "HEALER" } },
    DRUID   = { { 102, "Balance", "DAMAGER" }, { 103, "Feral", "DAMAGER" }, { 105, "Restoration", "HEALER" } },
    MAGE    = { { 62, "Arcane", "DAMAGER" }, { 63, "Fire", "DAMAGER" }, { 64, "Frost", "DAMAGER" } },
    WARLOCK = { { 265, "Affliction", "DAMAGER" }, { 266, "Demonology", "DAMAGER" }, { 267, "Destruction", "DAMAGER" } },
    HUNTER  = { { 253, "Beast Mastery", "DAMAGER" }, { 254, "Marksmanship", "DAMAGER" }, { 255, "Survival", "DAMAGER" } },
}

-- The drinking buff is recognised by name. The localized name comes from these
-- spell IDs ("Drink"); the English names are a fallback.
local DRINK_SPELL_IDS = { 430, 431, 432, 1133, 1135, 1137, 22734 }
local DRINK_NAMES     = { "Drink", "Food & Drink", "Refreshment" }

-- Group roles in display order, with Blizzard's role icons (group finder).
local ROLE_RANK = { HEALER = 1, DAMAGER = 2, TANK = 3, UNKNOWN = 4 }
local ROLE_TEXT = { HEALER = "roleHealer", DAMAGER = "roleDamager", TANK = "roleTank", UNKNOWN = "roleUnknown" }
local ROLE_ICONS = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = {
    HEALER  = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
    TANK    = { 0, 19 / 64, 22 / 64, 41 / 64 },
}

-- Sample players for /manabar test, in display order (role groups).
local FAKE_PLAYERS = {
    { name = "Aelinor", role = "HEALER",  specID = 257, value = 0.97, rate = -0.03 },
    { name = "Borak",   role = "HEALER",  specID = 264, value = 0.40, rate = 0.08, drinking = true },
    { name = "Celeste", role = "HEALER",  specID = 65,  value = 0.63, rate = -0.05 },
    { name = "Elyra",   role = "HEALER",  specID = 256, state = "offline" },
    { name = "Dorn",    role = "DAMAGER", specID = 64,  value = 0.18, rate = -0.02 },
    { name = "Brom",    role = "TANK",    specID = 66,  value = 0.55, rate = -0.01 },
}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local STRINGS = ns.STRINGS or {}
local db                      -- ManabarDB (SavedVariables)
local L = STRINGS.hu or {}    -- active texts
local frame, titleText, emptyText, gearButton, summaryBar
local bars = {}               -- bar pool, bars[1..activeBars] are in use
local unitToBar = {}          -- unit token -> bar
local activeBars = 0
local testMode = false
local inCombat = false
local dirtyPending = false
local dirtyTimer, refreshTimer = 0, 0
local rebuildPending = false
local fracCurve, pctCurve, colorCurve, rgCurve
local okBars = {}             -- scratch: the bars that count for an average
local headers = {}            -- role -> header bar (role name + the role's average)
local groups = {}             -- { { role, first, last } } bar ranges per role
local useCurves = false
local drinkNames, drinkNameList = {}, {}
local drinkScanners = {}
local seenErrors = {}
local scratchUnits = {}
local identityByGuid, identityByToken = {}, {} -- class / name / "me", remembered
local rosterKey                                -- group type + size at the last rebuild
local constFrac, constPct                      -- Blizzard's CurveConstants, as fallback

local classSpecs = {}         -- { { classFile, classID, name, specs = { { id, name, role } } } }
local specsByClass = {}       -- classFile -> specs
local specInfoByID = {}       -- specID -> spec

local specCache = {}          -- guid -> specID of other players (from inspection)
local guidToUnit = {}         -- guid -> unit token in the current roster
local inspectQueue, inspectQueued, inspectFailedAt = {}, {}, {}
local inspectPending, inspectPendingAt
local inspectScheduled, retryScheduled = false, false

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local issecretvalue = issecretvalue or function() return false end
local wipe = wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- Returns v, or nil when v is a secret value. Only the result may be compared,
-- tested or used as a table key.
local function Plain(v)
    if issecretvalue(v) then return nil end
    return v
end

-- Calls fn when it exists; nil instead of an error when it fails.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

local function Now()
    return Plain(Call(GetTime)) or 0
end

local PREFIX = "|cff33ff99Manabar|r: "

local function Print(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then msg = string.format(fmt, ...) end
    print(PREFIX .. msg)
end

local function Debug(err)
    if not (db and db.debug) then return end
    err = tostring(err)
    if seenErrors[err] then return end
    seenErrors[err] = true
    Print("|cffff6060debug:|r %s", err)
end

local function GradientRGB(p)
    if p ~= p or p <= GRADIENT[1][1] then -- NaN or below the first point
        local g = GRADIENT[1]
        return g[2], g[3], g[4]
    end
    for i = 2, #GRADIENT do
        local b = GRADIENT[i]
        if p <= b[1] then
            local a = GRADIENT[i - 1]
            local t = (p - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    local g = GRADIENT[#GRADIENT]
    return g[2], g[3], g[4]
end

local function IsGroupToken(unit)
    return type(unit) == "string"
        and (unit == "player" or unit:find("^party%d") ~= nil or unit:find("^raid%d") ~= nil)
end

-------------------------------------------------------------------------------
-- Curves (secret-safe percentage and color)
-------------------------------------------------------------------------------

local function CreateCurves()
    local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
    fracCurve = C_CurveUtil.CreateCurve()
    pctCurve = C_CurveUtil.CreateCurve()
    colorCurve = C_CurveUtil.CreateColorCurve()
    if linear then
        fracCurve:SetType(linear)
        pctCurve:SetType(linear)
        colorCurve:SetType(linear)
    end
    fracCurve:AddPoint(0, 0)
    fracCurve:AddPoint(1, 1)
    pctCurve:AddPoint(0, PCT_EPSILON)
    pctCurve:AddPoint(1, 100 + PCT_EPSILON)
    for i = 1, #GRADIENT do
        local g = GRADIENT[i]
        colorCurve:AddPoint(g[1], CreateColor(g[2], g[3], g[4], 1))
    end
    -- Straight red -> green, for the summary bar: N of these, added up with
    -- alpha 2/N and clamped, give exactly the GRADIENT color of the average.
    rgCurve = C_CurveUtil.CreateColorCurve()
    if linear then rgCurve:SetType(linear) end
    rgCurve:AddPoint(0, CreateColor(1, 0, 0, 1))
    rgCurve:AddPoint(1, CreateColor(0, 1, 0, 1))
end

local function BuildCurves()
    useCurves = false
    if not (UnitPowerPercent and C_CurveUtil and C_CurveUtil.CreateCurve
            and C_CurveUtil.CreateColorCurve and CreateColor) then
        return
    end
    local ok, err = pcall(CreateCurves)
    if ok then
        useCurves = true
    else
        Debug(err)
    end
    if type(CurveConstants) == "table" then
        constFrac, constPct = CurveConstants.ZeroToOne, CurveConstants.ScaleTo100
    end
end

-------------------------------------------------------------------------------
-- Drinking detection
-------------------------------------------------------------------------------

local function AddDrinkName(name)
    if type(name) == "string" and name ~= "" and not drinkNames[name] then
        drinkNames[name] = true
        drinkNameList[#drinkNameList + 1] = name
    end
end

local function BuildDrinkNames()
    for i = 1, #DRINK_NAMES do AddDrinkName(DRINK_NAMES[i]) end
    local getName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    for i = 1, #DRINK_SPELL_IDS do
        AddDrinkName(Plain((Call(getName, DRINK_SPELL_IDS[i]))))
    end
end

local function DrinkByName(unit)
    local get = C_UnitAuras.GetAuraDataBySpellName
    for i = 1, #drinkNameList do
        if get(unit, drinkNameList[i], "HELPFUL") then return true end
    end
    return false
end

local function DrinkByIndex(unit)
    local get = C_UnitAuras.GetAuraDataByIndex
    for i = 1, MAX_AURAS do
        local aura = get(unit, i, "HELPFUL")
        if not aura then break end
        local name = Plain(aura.name)
        if name and drinkNames[name] then return true end
    end
    return false
end

local function BuildDrinkScanners()
    wipe(drinkScanners)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        drinkScanners[#drinkScanners + 1] = DrinkByName
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        drinkScanners[#drinkScanners + 1] = DrinkByIndex
    end
end

-- Aura data of other players can be restricted in combat; then the scan finds
-- nothing (or errors) and the unit counts as not drinking. Nobody can drink in
-- combat anyway.
local function IsUnitDrinking(unit)
    for i = 1, #drinkScanners do
        local ok, result = pcall(drinkScanners[i], unit)
        if ok then return result == true end
        Debug(result)
    end
    return false
end

-------------------------------------------------------------------------------
-- Classes and specializations
-------------------------------------------------------------------------------

local function BuildSpecData()
    wipe(classSpecs)
    wipe(specsByClass)
    wipe(specInfoByID)
    local getNum = (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID)
        or GetNumSpecializationsForClassID
    for _, classFile in ipairs(SPEC_CLASSES) do
        local classID = CLASS_IDS[classFile]
        local className = Plain((Call(GetClassInfo, classID)))
        if type(className) ~= "string" or className == "" then className = CLASS_NAMES_EN[classFile] end

        local specs = {}
        local count = Plain(Call(getNum, classID))
        if type(count) == "number" then
            for i = 1, count do
                local id, name, _, icon, role = Call(GetSpecializationInfoForClassID, classID, i)
                id, name, icon, role = Plain(id), Plain(name), Plain(icon), Plain(role)
                if type(id) == "number" and id > 0 and type(name) == "string" then
                    specs[#specs + 1] = {
                        id = id, name = name, icon = icon,
                        role = type(role) == "string" and role or "DAMAGER",
                    }
                end
            end
        end
        if #specs == 0 then
            for _, s in ipairs(FALLBACK_SPECS[classFile]) do
                specs[#specs + 1] = { id = s[1], name = s[2], role = s[3] }
            end
        end

        for _, spec in ipairs(specs) do
            spec.classFile = classFile
            specInfoByID[spec.id] = spec
        end
        specsByClass[classFile] = specs
        classSpecs[#classSpecs + 1] = { classFile = classFile, classID = classID, name = className, specs = specs }
    end
end

-- The group roles whose mana is shown (settings window: Healer / DPS / Tank).
-- By default every mana user out of combat; healersInCombat narrows it down.
local DEFAULT_ROLES = { HEALER = true, DAMAGER = true, TANK = true }

local function IsRoleEnabled(role)
    return db.roles[role] == true
end

-- Shown right now: ticked, and in combat a healer if "healers in combat" is on.
local function IsRoleShown(role)
    if not IsRoleEnabled(role) then return false end
    if inCombat and db.healersInCombat then return role == "HEALER" end
    return true
end

-- Maps a spec ID from any API to the spec entry of the class. An ID the class
-- list does not know is matched by its name (GetSpecializationInfoByID).
local function SpecEntry(specID, specs)
    if type(specID) ~= "number" or specID <= 0 or not specs or not specs[1] then return nil end
    local spec = specInfoByID[specID]
    if spec then
        if spec.classFile == specs[1].classFile then return spec end
        return nil
    end
    local _, name = Call(GetSpecializationInfoByID, specID)
    name = Plain(name)
    if type(name) == "string" then
        for i = 1, #specs do
            if specs[i].name == name then return specs[i] end
        end
    end
end

-- Your own spec; falls back to the spec index (same order as the class list).
local function PlayerSpec(specs)
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local index = Plain(Call(getSpec))
    if type(index) ~= "number" or index <= 0 then return nil end
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    return SpecEntry(Plain((Call(getInfo, index))), specs) or (specs and specs[index])
end

-- The spec of a group member if known: yours, or from (cached) inspection.
local function KnownSpec(unit, isSelf, guid, specs)
    if isSelf then return PlayerSpec(specs) end
    local id = Plain(Call(GetInspectSpecialization, unit))
    if type(id) == "number" and id > 0 then
        if guid then specCache[guid] = id end
    elseif guid then
        id = specCache[guid]
    end
    return SpecEntry(id, specs)
end

-------------------------------------------------------------------------------
-- Inspection (only for players whose spec matters and cannot be told from
-- their group role)
-------------------------------------------------------------------------------

local ScheduleRebuild -- defined with the frames
local ProcessInspectQueue

-- urgent: the spec decides whether / where the player is shown; otherwise it
-- is only wanted for the spec icon. Urgent requests go first.
local function QueueInspect(guid, urgent)
    if not guid or specCache[guid] or guid == inspectPending then return end
    if inspectQueued[guid] then
        if urgent then inspectQueued[guid] = "urgent" end
        return
    end
    local failedAt = inspectFailedAt[guid]
    if failedAt and Now() - failedAt < INSPECT_RETRY then return end
    inspectQueued[guid] = urgent and "urgent" or "icon"
    inspectQueue[#inspectQueue + 1] = guid
end

local function PopInspect()
    local pick = 1
    for i = 1, #inspectQueue do
        if inspectQueued[inspectQueue[i]] == "urgent" then
            pick = i
            break
        end
    end
    local guid = table.remove(inspectQueue, pick)
    inspectQueued[guid] = nil
    return guid
end

local function ScheduleInspect()
    if inspectScheduled or not NotifyInspect or not (C_Timer and C_Timer.After) then return end
    if #inspectQueue == 0 and not inspectPending then return end
    inspectScheduled = true
    C_Timer.After(INSPECT_INTERVAL, ProcessInspectQueue)
end

local function ScheduleRetry()
    if retryScheduled or not (C_Timer and C_Timer.After) then return end
    retryScheduled = true
    C_Timer.After(INSPECT_RETRY + 1, function()
        retryScheduled = false
        ScheduleRebuild()
    end)
end

local function InspectFrameOpen()
    return InspectFrame ~= nil and InspectFrame.IsShown ~= nil and InspectFrame:IsShown() == true
end

-- No range check on purpose (CheckInteractDistance is restricted on modern
-- clients): an unanswered request simply times out and is retried later.
local function CanInspectNow(unit)
    if Plain(Call(UnitIsConnected, unit)) == false then return false end
    return Plain(Call(CanInspect, unit)) ~= false
end

ProcessInspectQueue = function()
    inspectScheduled = false
    local now = Now()
    if inspectPending then
        if now - inspectPendingAt < INSPECT_TIMEOUT then
            ScheduleInspect()
            return
        end
        inspectFailedAt[inspectPending] = now -- no answer, try again later
        inspectPending = nil
        ScheduleRetry()
    end
    if not inCombat and not Plain(Call(InCombatLockdown)) and not InspectFrameOpen() then
        while #inspectQueue > 0 do
            local guid = PopInspect()
            local unit = guidToUnit[guid]
            if unit and not specCache[guid] then
                if CanInspectNow(unit) then
                    inspectPending, inspectPendingAt = guid, now
                    Call(NotifyInspect, unit)
                    break
                end
                inspectFailedAt[guid] = now -- out of range etc.
                ScheduleRetry()
            end
        end
    end
    ScheduleInspect()
end

local function OnInspectReady(guid)
    guid = Plain(guid)
    if type(guid) ~= "string" then return end
    local unit = guidToUnit[guid]
    if unit then
        local id = Plain(Call(GetInspectSpecialization, unit))
        if type(id) == "number" and id > 0 then
            specCache[guid] = id
            inspectFailedAt[guid] = nil
        end
    end
    if guid == inspectPending then
        inspectPending = nil
        if not InspectFrameOpen() then Call(ClearInspectPlayer) end
    end
    if unit then ScheduleRebuild() end
end

local function OnSpecChanged(unit)
    if unit ~= "player" and IsGroupToken(unit) then
        local guid = Plain(Call(UnitGUID, unit))
        if guid then
            specCache[guid] = nil
            inspectFailedAt[guid] = nil
            if identityByGuid[guid] then identityByGuid[guid].knownSpec = nil end
        end
        if identityByToken[unit] then identityByToken[unit].knownSpec = nil end
    end
    ScheduleRebuild()
end

-------------------------------------------------------------------------------
-- Who is shown
-------------------------------------------------------------------------------

-- true / false, or nil while the game hides the answer
local function IsSelfUnit(unit, guid)
    if unit == "player" then return true end
    local same = Plain(Call(UnitIsUnit, unit, "player"))
    if same ~= nil then return same and true or false end
    local playerGuid = Plain(Call(UnitGUID, "player"))
    if guid and playerGuid then return guid == playerGuid end
    return nil
end

-- Class, name and "is it me" of a group member. In combat the game may hide
-- them (secret values); then the last readable answer for that player is used
-- (found by GUID, or by unit token if the GUID is hidden too), so the bars do
-- not disappear in a fight.
local function UnitIdentity(unit, guid)
    local known = (guid and identityByGuid[guid]) or (not guid and identityByToken[unit]) or nil
    local _, classFile = Call(UnitClass, unit)
    classFile = Plain(classFile)
    if not classFile then return known end
    local isSelf = IsSelfUnit(unit, guid)
    if isSelf == nil then isSelf = (known and known.isSelf) or false end
    local same = known and known.classFile == classFile
    local identity = {
        classFile = classFile,
        name = Plain((Call(UnitName, unit))) or (same and known.name) or nil,
        isSelf = isSelf,
        knownSpec = same and known.knownSpec or nil,
    }
    if guid then identityByGuid[guid] = identity end
    identityByToken[unit] = identity
    return identity
end

-- The specs of a class that fit a group role (all of them without a role).
local function CandidateSpecs(specs, role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        local out = {}
        for i = 1, #specs do
            if specs[i].role == role then out[#out + 1] = specs[i] end
        end
        if #out > 0 then return out end
    end
    return specs
end

-- Decides by group role. Returns: show, spec (for the icon, or nil),
-- specUnknown, inspect ("urgent", "icon" or nil), role.
--   1. manual lists (/manabar add / ignore)
--   2. only classes that use mana (no bars for Warriors and Rogues)
--   3. the role set in the group (tank / healer / dps); without one, the role
--      of the spec (yours, or from a short inspection)
--   4. role still unknown: if every spec of the class gives the same answer,
--      that decides (a Mage is always dps). Otherwise the player is hidden
--      (unless "show unknown" is on) until the inspection tells the spec.
--   In combat only the healers stay when "healers in combat" is on.
local function Evaluate(unit, guid, identity)
    local isSelf, name = identity.isSelf, identity.name
    local key = name and name:lower()
    if key and db.exclude[key] then return false, nil, false, nil, nil end
    local forced = (key and db.include[key]) and true or false

    local specs = specsByClass[identity.classFile]
    if not specs then return forced, nil, false, nil, nil end

    local spec = KnownSpec(unit, isSelf, guid, specs)
    if spec then
        identity.knownSpec = spec -- kept for fights, when inspect data may be hidden
    else
        spec = identity.knownSpec
    end

    local role = Plain(Call(UnitGroupRolesAssigned, unit))
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
        role = spec and spec.role or nil
    end
    if not role then -- every spec of the class has the same role: a Mage is always dps
        role = specs[1] and specs[1].role
        for i = 2, #specs do
            if specs[i].role ~= role then
                role = nil
                break
            end
        end
    end
    if not spec then -- for the icon: the only spec of the class with that role
        local candidates = CandidateSpecs(specs, role)
        if #candidates == 1 then spec = candidates[1] end
    end
    local wantIcon = not isSelf and db.specIcons and spec == nil

    if role then
        local show = forced or IsRoleShown(role)
        return show, spec, spec == nil, (show and wantIcon) and "icon" or nil, role
    end

    local anyOn, anyOff = false, false
    for i = 1, #specs do
        if IsRoleShown(specs[i].role) then anyOn = true else anyOff = true end
    end
    local show = forced or (anyOn and (not anyOff or db.showUnknown))
    -- The role decides whether and in which group the player is shown: urgent.
    local inspect = (not isSelf and ((anyOn and anyOff) or show)) and "urgent" or nil
    return show, spec, spec == nil, inspect, nil
end

local function GetGroupUnits(out)
    local n = 0
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            n = n + 1
            out[n] = "raid" .. i
        end
    elseif IsInGroup and IsInGroup() then
        n = n + 1
        out[n] = "player"
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do
            n = n + 1
            out[n] = "party" .. i
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    return n
end

local function SortEntries(a, b)
    local ra, rb = ROLE_RANK[a.role or "UNKNOWN"], ROLE_RANK[b.role or "UNKNOWN"]
    if ra ~= rb then return ra < rb end
    if a.isSelf ~= b.isSelf then return a.isSelf end
    local an, bn = a.name, b.name
    if an and bn then
        if an ~= bn then return an < bn end
    elseif an or bn then
        return an ~= nil
    end
    return a.unit < b.unit
end

local function CollectUnits()
    local list = {}
    wipe(guidToUnit)
    local n = GetGroupUnits(scratchUnits)
    for i = 1, n do
        local unit = scratchUnits[i]
        if Plain(Call(UnitExists, unit)) ~= false then
            local guid = Plain(Call(UnitGUID, unit))
            if guid then guidToUnit[guid] = unit end
            local identity = UnitIdentity(unit, guid)
            if identity and (not identity.isSelf or db.showSelf) then
                local show, spec, specUnknown, inspect, role = Evaluate(unit, guid, identity)
                if show then
                    list[#list + 1] = {
                        unit = unit, name = identity.name, isSelf = identity.isSelf,
                        spec = spec, specUnknown = specUnknown, role = role,
                    }
                end
                if inspect then QueueInspect(guid, inspect == "urgent") end
            end
        end
    end
    table.sort(list, SortEntries)
    ScheduleInspect()
    return list
end

-------------------------------------------------------------------------------
-- Bar updates
-------------------------------------------------------------------------------

local function AnchorName(bar)
    local name = bar.name
    name:ClearAllPoints()
    if bar.iconShown then
        name:SetPoint("LEFT", bar.specIcon, "RIGHT", 3, 0)
    else
        name:SetPoint("LEFT", bar.status, "LEFT", 4, 0)
    end
    if bar.drinking then
        name:SetPoint("RIGHT", bar.drinkIcon, "LEFT", -3, 0)
    else
        name:SetPoint("RIGHT", bar.perc, "LEFT", -4, 0)
    end
end

local function SetDrinking(bar, drinking)
    drinking = drinking and true or false
    if bar.drinking == drinking then return end
    bar.drinking = drinking
    bar.drinkIcon:SetShown(drinking)
    bar.drinkText:SetShown(drinking)
    AnchorName(bar)
end

-- Spec icon at the start of the bar: the spec's icon, or a question mark while
-- the spec is not known yet.
local function SetSpecIcon(bar, spec, unknown)
    local texture
    if db.specIcons then
        if spec and spec.icon then
            texture = spec.icon
        elseif unknown then
            texture = UNKNOWN_SPEC_ICON
        end
    end
    if texture then bar.specIcon:SetTexture(texture) end
    local shown = texture ~= nil
    if bar.iconShown ~= shown then
        bar.iconShown = shown
        bar.specIcon:SetShown(shown)
        AnchorName(bar)
    end
end

local function SetGray(bar, text)
    local sb = bar.status
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(1)
    sb:GetStatusBarTexture():SetVertexColor(STATE_COLOR[1], STATE_COLOR[2], STATE_COLOR[3])
    bar.perc:SetText(text)
end

-- state: "offline", "dead" or "nomana" (no mana data, e.g. max mana is 0)
local function ShowState(bar, state)
    if state == "dead" then
        SetGray(bar, L.dead)
    elseif state == "offline" then
        SetGray(bar, L.offline)
    else
        SetGray(bar, "--")
    end
end

local function SetPlainValue(bar, frac)
    local sb = bar.status
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(frac)
    bar.perc:SetFormattedText("%d%%", math.floor(frac * 100 + PCT_EPSILON))
    sb:GetStatusBarTexture():SetVertexColor(GradientRGB(frac))
end

local function ApplyColorFromUnit(tex, unit, curve)
    local color = UnitPowerPercent(unit, PT_MANA, false, curve)
    tex:SetVertexColor(color:GetRGB())
end

local function ApplyColorFromFraction(tex, frac, curve)
    tex:SetVertexColor(curve:EvaluateUnpacked(frac))
end

-- Colors a texture by a unit's (possibly secret) mana through a color curve.
local function ApplyCurveColor(tex, unit, frac, curve)
    local ok, err = pcall(ApplyColorFromUnit, tex, unit, curve)
    if ok then return end
    Debug(err)
    ok, err = pcall(ApplyColorFromFraction, tex, frac, curve)
    if ok then return end
    Debug(err)
    tex:SetVertexColor(MANA_COLOR[1], MANA_COLOR[2], MANA_COLOR[3])
end

-- UnitPowerPercent through our curve, or through Blizzard's equivalent if the
-- game refuses ours. Returns the value (maybe secret) and whether it came from
-- the fallback.
local function PowerPercent(unit, curve, fallback)
    local ok, v = pcall(UnitPowerPercent, unit, PT_MANA, false, curve)
    if ok and v then return v, false end
    if not ok then Debug(v) end
    if fallback then
        ok, v = pcall(UnitPowerPercent, unit, PT_MANA, false, fallback)
        if ok and v then return v, true end
        if not ok then Debug(v) end
    end
    return nil
end

-- Secret-safe path: the values may be secret, they only go into widgets.
-- Returns handled, and the mana fraction when it is not secret.
local function UpdateManaCurve(bar, unit)
    local frac = PowerPercent(unit, fracCurve, constFrac)
    if not frac then return false end
    local sb = bar.status
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(frac)
    local pct, blizzard = PowerPercent(unit, pctCurve, constPct)
    if pct then
        -- Blizzard's ScaleTo100 has no rounding guard (0.29 -> 28.99...): round it
        bar.perc:SetFormattedText(blizzard and "%.0f%%" or "%d%%", pct)
    end
    ApplyCurveColor(sb:GetStatusBarTexture(), unit, frac, colorCurve)
    return true, Plain(frac)
end

-- Fallback without curves; does math only on non-secret values. With secret
-- values the bar is still filled by the game and the mana shown as a number.
local function UpdateManaPlain(bar, unit)
    local cur, max = UnitPower(unit, PT_MANA), UnitPowerMax(unit, PT_MANA)
    if issecretvalue(cur) or issecretvalue(max) then
        local sb = bar.status
        sb:SetMinMaxValues(0, max)
        sb:SetValue(cur)
        bar.perc:SetFormattedText("%d", cur)
        sb:GetStatusBarTexture():SetVertexColor(MANA_COLOR[1], MANA_COLOR[2], MANA_COLOR[3])
        return nil
    end
    cur, max = cur or 0, max or 0
    local frac = 0
    if max > 0 then frac = math.min(math.max(cur / max, 0), 1) end
    SetPlainValue(bar, frac)
    return frac
end

local function UpdateMana(bar, unit)
    if useCurves then
        local ok, handled, frac = pcall(UpdateManaCurve, bar, unit)
        if ok and handled then return frac end
        if not ok then Debug(handled) end
    end
    local ok, frac = pcall(UpdateManaPlain, bar, unit)
    if ok then return frac end
    Debug(frac)
end

local function GetUnitState(unit)
    if Plain(Call(UnitIsConnected, unit)) == false then return "offline" end
    if Plain(Call(UnitIsDeadOrGhost, unit)) then return "dead" end
    if Plain(Call(UnitPowerMax, unit, PT_MANA)) == 0 then return "nomana" end
    return "ok"
end

local function RefreshBar(bar, scanAura)
    local fake = bar.fake
    if fake then
        bar.state = fake.state or "ok"
        if fake.state then
            bar.frac = nil
            ShowState(bar, fake.state)
            SetDrinking(bar, false)
        else
            bar.frac = fake.value
            SetPlainValue(bar, fake.value)
            SetDrinking(bar, fake.drinking)
        end
        return
    end

    local unit = bar.unit
    if not unit then return end
    local state = GetUnitState(unit)
    bar.state = state
    if state ~= "ok" then
        bar.frac = nil
        ShowState(bar, state)
        SetDrinking(bar, false)
        return
    end
    bar.frac = UpdateMana(bar, unit)
    if scanAura then SetDrinking(bar, IsUnitDrinking(unit)) end
end

local function AnimateFakes(elapsed)
    for i = 1, #FAKE_PLAYERS do
        local f = FAKE_PLAYERS[i]
        if f.rate then
            local v = f.value + f.rate * elapsed
            if v < 0 then v = 1 elseif v > 1 then v = 0.1 end
            f.value = v
        end
    end
end

-- The overall average at the bottom: only when it adds something (with role
-- headers: when more than one role is shown).
local function SummaryVisible()
    if not db.summary or activeBars < 2 then return false end
    return not db.roleHeaders or #groups >= 2
end

-- Visual average for secret mana. Addon code may not add secret values up, but
-- the game can draw them: n segment bars, each 1/n of the width, are chained so
-- that every segment starts where the previous one's fill ends. The filled
-- length is then exactly the average. The segments' own fills are invisible;
-- the visible fill is painted by n additive layers (red -> green, alpha 2/n)
-- that add up, clamped, to the GRADIENT color of the average. The addon never
-- learns the average itself.
local function LayoutSegments(sb, n)
    local w, h = db.width - 2, db.height - 2
    if sb.segN == n and sb.segW == w and sb.segH == h then return end
    sb.segN, sb.segW, sb.segH = n, w, h
    local segments, paints = sb.segments, sb.paints
    for i = 1, n do
        local seg = segments[i]
        if not seg then
            seg = CreateFrame("StatusBar", nil, sb.stack)
            seg:SetStatusBarTexture(BAR_TEXTURE)
            seg:SetStatusBarColor(0, 0, 0, 0) -- only its geometry is used
            seg:SetMinMaxValues(0, 1)
            seg:SetValue(0)
            segments[i] = seg
        end
        seg:ClearAllPoints()
        if i == 1 then
            seg:SetPoint("TOPLEFT", sb.stack, "TOPLEFT", 0, 0)
        else
            seg:SetPoint("TOPLEFT", segments[i - 1]:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        end
        seg:SetSize(w / n, h)
        seg:Show()
    end
    for i = n + 1, #segments do segments[i]:Hide() end

    local fillEnd = segments[n]:GetStatusBarTexture()
    sb.paintBase:ClearAllPoints()
    sb.paintBase:SetPoint("TOPLEFT", sb.stack, "TOPLEFT", 0, 0)
    sb.paintBase:SetPoint("BOTTOMRIGHT", fillEnd, "BOTTOMRIGHT", 0, 0)
    for i = 1, n do
        local paint = paints[i]
        if not paint then
            paint = sb.stack:CreateTexture(nil, "ARTWORK")
            paint:SetTexture(BAR_TEXTURE)
            paint:SetBlendMode("ADD")
            paints[i] = paint
        end
        paint:ClearAllPoints()
        paint:SetPoint("TOPLEFT", sb.stack, "TOPLEFT", 0, 0)
        paint:SetPoint("BOTTOMRIGHT", fillEnd, "BOTTOMRIGHT", 0, 0)
        paint:SetAlpha(n == 1 and 1 or 2 / n)
        paint:Show()
    end
    for i = n + 1, #paints do paints[i]:Hide() end
end

local function ShowVisualAverage(sb, n)
    LayoutSegments(sb, n)
    for i = 1, n do
        local unit = okBars[i].unit
        local frac = PowerPercent(unit, fracCurve, constFrac)
        sb.segments[i]:SetValue(frac or 0)
        ApplyCurveColor(sb.paints[i], unit, frac, n == 1 and colorCurve or rgCurve)
    end
end

-- Average of bars[from..to] (offline / dead ones do not count) on an average
-- bar: an exact percentage while the mana values are readable, the visual
-- average while the game keeps them secret.
local function UpdateAverageBar(sb, from, to)
    local sum, secret = 0, false
    wipe(okBars)
    for i = from, to do
        local bar = bars[i]
        if bar.state == "ok" then
            okBars[#okBars + 1] = bar
            if bar.frac then
                sum = sum + bar.frac
            elseif bar.unit then
                secret = true
            end
        end
    end
    local n = #okBars
    local visual = false
    if n == 0 then
        SetGray(sb, "--")
    elseif not secret then
        SetPlainValue(sb, sum / n)
    elseif useCurves then
        local ok, err = pcall(ShowVisualAverage, sb, n)
        if ok then
            visual = true
            sb.status:SetMinMaxValues(0, 1)
            sb.status:SetValue(0)
            sb.perc:SetText("")
        else
            Debug(err)
            SetGray(sb, "?")
        end
    else
        SetGray(sb, "?")
    end
    sb.stack:SetShown(visual)
end

-------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------

local function CreateBar()
    local bar = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = WHITE_TEXTURE, edgeFile = WHITE_TEXTURE, edgeSize = 1 })
        bar:SetBackdropColor(0.05, 0.05, 0.05, 0.75)
        bar:SetBackdropBorderColor(0, 0, 0, 1)
    end

    local sb = CreateFrame("StatusBar", nil, bar)
    sb:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
    sb:SetStatusBarTexture(BAR_TEXTURE)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    bar.status = sb

    local perc = sb:CreateFontString(nil, "OVERLAY")
    perc:SetFont(FONT, 11, "OUTLINE")
    perc:SetPoint("RIGHT", sb, "RIGHT", -3, 0)
    perc:SetJustifyH("RIGHT")
    bar.perc = perc

    local drinkText = sb:CreateFontString(nil, "OVERLAY")
    drinkText:SetFont(FONT, 10, "OUTLINE")
    drinkText:SetTextColor(0.45, 0.8, 1)
    drinkText:SetPoint("RIGHT", perc, "LEFT", -4, 0)
    drinkText:SetText(L.drinking)
    drinkText:Hide()
    bar.drinkText = drinkText

    local drinkIcon = sb:CreateTexture(nil, "OVERLAY")
    drinkIcon:SetTexture(DRINK_ICON)
    drinkIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    drinkIcon:SetSize(14, 14)
    drinkIcon:SetPoint("RIGHT", drinkText, "LEFT", -2, 0)
    drinkIcon:Hide()
    bar.drinkIcon = drinkIcon

    local specIcon = sb:CreateTexture(nil, "OVERLAY")
    specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    specIcon:SetSize(14, 14)
    specIcon:SetPoint("LEFT", sb, "LEFT", 2, 0)
    specIcon:Hide()
    bar.specIcon = specIcon

    local name = sb:CreateFontString(nil, "OVERLAY")
    name:SetFont(FONT, 11, "OUTLINE")
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    bar.name = name

    bar.drinking, bar.iconShown = false, false
    AnchorName(bar)
    return bar
end

local function StyleBar(bar, w, h, fontSize)
    bar:SetSize(w, h)
    bar.name:SetFont(FONT, fontSize, "OUTLINE")
    bar.perc:SetFont(FONT, fontSize, "OUTLINE")
    bar.drinkText:SetFont(FONT, math.max(7, fontSize - 1), "OUTLINE")
    bar.drinkIcon:SetSize(h - 4, h - 4)
    bar.specIcon:SetSize(h - 4, h - 4)
end

-- A bar that shows the average mana of other bars: the role headers and the
-- overall summary at the bottom. The visual average (see LayoutSegments) is
-- drawn under its own bar, whose texts and marks stay on top.
local function CreateAverageBar()
    local ab = CreateBar()
    ab.name:SetTextColor(1, 0.82, 0)
    local stack = CreateFrame("Frame", nil, ab)
    stack:SetPoint("TOPLEFT", ab, "TOPLEFT", 1, -1)
    stack:SetPoint("BOTTOMRIGHT", ab, "BOTTOMRIGHT", -1, 1)
    stack:SetFrameLevel(ab:GetFrameLevel() + 1)
    ab.status:SetFrameLevel(ab:GetFrameLevel() + 2)
    stack:Hide()
    local paintBase = stack:CreateTexture(nil, "BACKGROUND")
    paintBase:SetColorTexture(0, 0, 0, 1) -- the additive paints start from black
    ab.stack, ab.paintBase = stack, paintBase
    ab.segments, ab.paints = {}, {}
    -- 25 / 50 / 75 % marks, to read the average without a number
    ab.ticks = {}
    for i, f in ipairs({ 0.25, 0.5, 0.75 }) do
        local tick = ab.status:CreateTexture(nil, "ARTWORK", nil, 7)
        tick:SetColorTexture(1, 1, 1, 0.3)
        tick.frac = f
        ab.ticks[i] = tick
    end
    ab:Hide()
    return ab
end

local function PlaceTicks(ab, w, h)
    for _, tick in ipairs(ab.ticks) do
        tick:ClearAllPoints()
        tick:SetSize(1, h - 4)
        tick:SetPoint("LEFT", ab.status, "LEFT", (w - 2) * tick.frac, 0)
    end
end

-- The header of a role group: role icon, role name with the number of
-- players, and the role's average mana.
local function GetHeader(role)
    local header = headers[role]
    if header then return header end
    header = CreateAverageBar()
    header.role = role
    local icon, coords = header.specIcon, ROLE_COORDS[role]
    if coords then
        icon:SetTexture(ROLE_ICONS)
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        icon:SetTexture(UNKNOWN_SPEC_ICON)
    end
    header.iconShown = true
    icon:Show()
    AnchorName(header)
    if header.SetBackdropBorderColor then header:SetBackdropBorderColor(1, 0.82, 0, 0.5) end
    headers[role] = header
    return header
end

local function UpdateHeaderTexts()
    for _, g in ipairs(groups) do
        GetHeader(g.role).name:SetFormattedText("%s (%d)", L[ROLE_TEXT[g.role]] or g.role, g.last - g.first + 1)
    end
end

local function UpdateAverages()
    if not summaryBar then return end
    if db.roleHeaders then
        for _, g in ipairs(groups) do
            UpdateAverageBar(GetHeader(g.role), g.first, g.last)
        end
    end
    if SummaryVisible() then
        UpdateAverageBar(summaryBar, 1, activeBars)
        summaryBar:Show()
    else
        summaryBar:Hide()
    end
end

local function Layout()
    local w, h = db.width, db.height
    local fontSize = math.max(8, math.floor(h * 0.6 + 0.5))
    local y = HEADER_HEIGHT
    for _, header in pairs(headers) do header.used = false end
    for gi, g in ipairs(groups) do
        if gi > 1 then y = y + GROUP_GAP end
        if db.roleHeaders then
            local header = GetHeader(g.role)
            header.used = true
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
            StyleBar(header, w, h, fontSize)
            PlaceTicks(header, w, h)
            header:Show()
            y = y + h + BAR_GAP
        end
        for i = g.first, g.last do
            local bar = bars[i]
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
            StyleBar(bar, w, h, fontSize)
            bar:Show()
            y = y + h + BAR_GAP
        end
    end
    for _, header in pairs(headers) do
        if not header.used then header:Hide() end
    end
    for i = activeBars + 1, #bars do bars[i]:Hide() end
    if activeBars == 0 then y = y + h + BAR_GAP end -- room for the placeholder text
    local height = y - BAR_GAP + PAD
    if SummaryVisible() then
        summaryBar:ClearAllPoints()
        summaryBar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(height - PAD + SUMMARY_GAP))
        StyleBar(summaryBar, w, h, fontSize)
        PlaceTicks(summaryBar, w, h)
        height = height + SUMMARY_GAP + h
    end
    frame:SetSize(w + PAD * 2, height)
end

local function UpdateVisibility()
    if not frame then return end
    local empty = activeBars == 0
    emptyText:SetShown(empty)
    if (db.hideInCombat and inCombat) or (empty and db.locked) then
        frame:Hide()
    else
        frame:Show()
    end
end

local function RosterKey()
    local kind = "solo"
    if IsInRaid and IsInRaid() then
        kind = "raid"
    elseif IsInGroup and IsInGroup() then
        kind = "party"
    end
    return kind .. (Plain(Call(GetNumGroupMembers)) or 0)
end

local function Rebuild()
    if not frame then return end
    rosterKey = RosterKey()
    wipe(unitToBar)
    local list = testMode and FAKE_PLAYERS or CollectUnits()
    activeBars = #list
    for i = 1, activeBars do
        local info = list[i]
        local bar = bars[i]
        if not bar then
            bar = CreateBar()
            bars[i] = bar
        end
        if testMode then
            bar.unit, bar.fake = nil, info
            bar.name:SetText(info.name)
            SetSpecIcon(bar, specInfoByID[info.specID], false)
        else
            bar.unit, bar.fake = info.unit, nil
            bar.name:SetText(info.name or Call(UnitName, info.unit) or "?")
            SetSpecIcon(bar, info.spec, info.specUnknown)
            unitToBar[info.unit] = bar
            if info.isSelf then unitToBar.player = bar end
        end
        bar.dirty, bar.dirtyAura = nil, nil
        RefreshBar(bar, true)
    end
    for i = activeBars + 1, #bars do
        bars[i].unit, bars[i].fake, bars[i].state, bars[i].frac = nil, nil, nil, nil
    end
    wipe(groups)
    for i = 1, activeBars do
        local role = list[i].role or "UNKNOWN"
        local g = groups[#groups]
        if not g or g.role ~= role then
            g = { role = role, first = i }
            groups[#groups + 1] = g
        end
        g.last = i
    end
    UpdateHeaderTexts()
    Layout()
    UpdateAverages()
    UpdateVisibility()
end

-- force: also in combat (the settings changed). Otherwise a fight only rebuilds
-- the list when the group itself changed; the rest waits until it ends.
ScheduleRebuild = function(force)
    if not force and inCombat and rosterKey == RosterKey() then return end
    if rebuildPending then return end
    if C_Timer and C_Timer.After then
        rebuildPending = true
        C_Timer.After(REBUILD_DELAY, function()
            rebuildPending = false
            Rebuild()
        end)
    else
        Rebuild()
    end
end

local function OnUpdate(self, elapsed)
    if testMode then
        AnimateFakes(elapsed)
        for i = 1, activeBars do RefreshBar(bars[i], true) end
        UpdateAverages()
        return
    end

    refreshTimer = refreshTimer + elapsed
    if refreshTimer >= REFRESH_INTERVAL then
        refreshTimer, dirtyTimer, dirtyPending = 0, 0, false
        for i = 1, activeBars do
            local bar = bars[i]
            bar.dirty, bar.dirtyAura = nil, nil
            RefreshBar(bar, true)
        end
        UpdateAverages()
        return
    end

    if not dirtyPending then return end
    dirtyTimer = dirtyTimer + elapsed
    if dirtyTimer < DIRTY_INTERVAL then return end
    dirtyTimer, dirtyPending = 0, false
    for i = 1, activeBars do
        local bar = bars[i]
        if bar.dirty then
            local scanAura = bar.dirtyAura
            bar.dirty, bar.dirtyAura = nil, nil
            RefreshBar(bar, scanAura)
        end
    end
    UpdateAverages()
end

-------------------------------------------------------------------------------
-- Position, scale, lock
-------------------------------------------------------------------------------

local function ApplyPosition()
    frame:ClearAllPoints()
    local pos = db.pos
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        frame:SetPoint("TOPLEFT", UIParent, "CENTER", -(db.width / 2 + PAD), 250)
    end
end

-- Saves the frame as TOPLEFT offsets (in the frame's own scale), so the frame
-- grows downwards when players join.
local function SavePosition()
    local left, top = Plain(frame:GetLeft()), Plain(frame:GetTop())
    if left and top then
        db.pos = { x = left, y = top }
    end
    ApplyPosition()
end

local function StopMoving()
    if frame.isMoving then
        frame:StopMovingOrSizing()
        frame.isMoving = nil
        if frame.SetUserPlaced then frame:SetUserPlaced(false) end
        SavePosition()
    end
end

local function SetScaleKeepPosition(scale)
    local oldScale = frame:GetScale()
    local left, top = Plain(frame:GetLeft()), Plain(frame:GetTop())
    db.scale = scale
    frame:SetScale(scale)
    if left and top then
        db.pos = { x = left * oldScale / scale, y = top * oldScale / scale }
    end
    ApplyPosition()
end

local function RefreshOptions()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

local function ApplyLock()
    local locked = db.locked
    if locked then StopMoving() end
    frame:EnableMouse(not locked)
    if frame.SetBackdropBorderColor then
        if locked then
            frame:SetBackdropBorderColor(0, 0, 0, 0.8)
        else
            frame:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
    end
    if locked and GameTooltip and GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
    UpdateVisibility()
end

local function SetLocked(locked)
    db.locked = locked and true or false
    ApplyLock()
    RefreshOptions()
    Print(db.locked and L.locked or L.unlocked)
end

local function ApplyTexts()
    titleText:SetText(L.title)
    emptyText:SetText(L.empty)
    summaryBar.name:SetText(L.average)
    summaryBar.drinkText:SetText(L.drinking)
    for i = 1, #bars do bars[i].drinkText:SetText(L.drinking) end
    UpdateHeaderTexts()
    if ns.ApplyOptionsTexts then ns.ApplyOptionsTexts() end
end

local function ShowTooltip(owner, title, line1, line2)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title)
    if line1 then GameTooltip:AddLine(line1, 1, 1, 1) end
    if line2 then GameTooltip:AddLine(line2, 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

local function HideTooltip(owner)
    if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function ToggleOptions()
    if ns.ToggleOptions then ns.ToggleOptions() end
end

local function CreateMainFrame()
    frame = CreateFrame("Frame", "ManabarFrame", UIParent, BACKDROP_TEMPLATE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = WHITE_TEXTURE, edgeFile = WHITE_TEXTURE, edgeSize = 1 })
        frame:SetBackdropColor(0, 0, 0, 0.35)
    end

    titleText = frame:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(FONT, 10, "OUTLINE")
    titleText:SetTextColor(1, 0.82, 0)
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 1, -3)

    emptyText = frame:CreateFontString(nil, "OVERLAY")
    emptyText:SetFont(FONT, 10, "OUTLINE")
    emptyText:SetTextColor(0.7, 0.7, 0.7)
    emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -(HEADER_HEIGHT + 3))

    -- Gear icon: opens the settings window. It stays clickable when the frame
    -- is locked (the frame itself is click-through then).
    gearButton = CreateFrame("Button", nil, frame)
    gearButton:SetSize(13, 13)
    gearButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -2)
    local gearIcon = gearButton:CreateTexture(nil, "ARTWORK")
    gearIcon:SetAllPoints(gearButton)
    gearIcon:SetTexture(GEAR_ICON)
    gearIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    gearButton:SetAlpha(0.75)
    gearButton:SetScript("OnClick", ToggleOptions)
    gearButton:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        ShowTooltip(self, L.gearTip, "/manabar")
    end)
    gearButton:SetScript("OnLeave", function(self)
        self:SetAlpha(0.75)
        HideTooltip(self)
    end)

    summaryBar = CreateAverageBar()

    frame:SetScript("OnDragStart", function(self)
        if db.locked then return end
        self:StartMoving()
        self.isMoving = true
    end)
    frame:SetScript("OnDragStop", StopMoving)
    frame:SetScript("OnHide", StopMoving)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and not db.locked then SetLocked(true) end
    end)
    frame:SetScript("OnEnter", function(self)
        if not db.locked then ShowTooltip(self, "Manabar", L.tipDrag, L.tipLock) end
    end)
    frame:SetScript("OnLeave", HideTooltip)
    frame:SetScript("OnUpdate", OnUpdate)
end

-------------------------------------------------------------------------------
-- Settings API for Options.lua
-------------------------------------------------------------------------------

local function SetOption(key, value)
    db[key] = value
    if key == "locked" then
        ApplyLock()
    elseif key == "hideInCombat" then
        UpdateVisibility()
    elseif key == "summary" or key == "roleHeaders" then
        Layout()
        UpdateAverages()
    elseif key == "showSelf" or key == "showUnknown" or key == "specIcons" or key == "healersInCombat" then
        ScheduleRebuild(true)
    end
end

local function SetRoleEnabled(role, enabled)
    db.roles[role] = enabled and true or false
    ScheduleRebuild(true)
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function ParseNumber(text)
    if type(text) ~= "string" then return nil end
    return tonumber((text:gsub(",", ".")))
end

local function SetNumber(key, text, minV, maxV, integer)
    local v = ParseNumber(text)
    if not v or v < minV or v > maxV then
        Print(L.invalid, (text and text ~= "") and text or "?", minV, maxV)
        return nil
    end
    if integer then v = math.floor(v + 0.5) end
    if key == "scale" then
        SetScaleKeepPosition(v)
    else
        db[key] = v
        Layout()
    end
    return v
end

local function ToggleOption(key, label)
    SetOption(key, not db[key])
    RefreshOptions()
    Print(L.toggle, label, db[key] and L.on or L.off)
end

local function SortedValues(t)
    local out = {}
    for _, v in pairs(t) do out[#out + 1] = tostring(v) end
    table.sort(out)
    return out
end

local function ManualList(cmd, rest)
    local name = rest
    if name == "" then name = Plain((Call(UnitName, "target"))) end
    if type(name) ~= "string" or name == "" then
        Print(L.noName)
        return
    end
    name = name:match("^([^%-]+)") or name -- "Name-Realm" -> "Name"
    local key = name:lower()
    if cmd == "add" then
        db.include[key], db.exclude[key] = name, nil
        Print(L.added, name)
    elseif cmd == "ignore" then
        db.exclude[key], db.include[key] = name, nil
        Print(L.ignored, name)
    else
        db.include[key], db.exclude[key] = nil, nil
        Print(L.removed, name)
    end
    ScheduleRebuild(true)
end

local function PrintLists()
    local inc, exc = SortedValues(db.include), SortedValues(db.exclude)
    Print(L.listAdd, #inc > 0 and table.concat(inc, ", ") or L.none)
    Print(L.listIgn, #exc > 0 and table.concat(exc, ", ") or L.none)
end

local function ShowHelp()
    for i = 1, #L.help do
        print(i == 1 and (PREFIX .. L.help[i]) or L.help[i])
    end
end

-- /manabar diag: which values the game lets the addon read right now.
local function DiagValue(fn, ...)
    if type(fn) ~= "function" then return "n/a" end
    local ok, v = pcall(fn, ...)
    if not ok then return "error" end
    if issecretvalue(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "number" then return string.format("%.4g", v) end
    return tostring(v)
end

local function DiagClass(unit)
    local _, classFile = UnitClass(unit)
    return classFile
end

local function DiagGuid(unit)
    local guid = UnitGUID(unit)
    if issecretvalue(guid) or guid == nil then return guid end
    return "ok"
end

local function DiagPercent(unit)
    return UnitPowerPercent(unit, PT_MANA, false, pctCurve)
end

local function Diagnose()
    Print("diag: %s, frame %s, bars %d, curves %s, only out of combat %s",
        inCombat and "IN COMBAT" or "out of combat", frame:IsShown() and "shown" or "hidden",
        activeBars, useCurves and "on" or "off", db.hideInCombat and "ON" or "off")
    local units = { "player" }
    for i = 1, math.min(activeBars, 8) do
        local unit = bars[i].unit
        if unit and unit ~= "player" then units[#units + 1] = unit end
    end
    for _, unit in ipairs(units) do
        print(string.format("  %s: name=%s class=%s guid=%s role=%s mana=%s max=%s pct=%s",
            unit, DiagValue(UnitName, unit), DiagValue(DiagClass, unit), DiagValue(DiagGuid, unit),
            DiagValue(UnitGroupRolesAssigned, unit), DiagValue(UnitPower, unit, PT_MANA),
            DiagValue(UnitPowerMax, unit, PT_MANA), DiagValue(DiagPercent, unit)))
    end
end

local function HandleSlash(msg)
    if not db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd, rest = (cmd or ""):lower(), rest or ""

    if cmd == "" or cmd == "config" or cmd == "options" then
        ToggleOptions()
    elseif cmd == "help" or cmd == "?" then
        ShowHelp()
    elseif cmd == "lock" or cmd == "unlock" then
        SetLocked(cmd == "lock")
    elseif cmd == "reset" then
        db.pos = nil
        db.scale, db.width, db.height = DEFAULTS.scale, DEFAULTS.width, DEFAULTS.height
        frame:SetScale(db.scale)
        ApplyPosition()
        Layout()
        Print(L.reset)
    elseif cmd == "scale" then
        local v = SetNumber("scale", rest, 0.5, 3, false)
        if v then Print(L.scale, v) end
    elseif cmd == "width" then
        local v = SetNumber("width", rest, 100, 400, true)
        if v then Print(L.width, v) end
    elseif cmd == "height" then
        local v = SetNumber("height", rest, 12, 40, true)
        if v then Print(L.height, v) end
    elseif cmd == "healers" then
        ToggleOption("healersInCombat", L.optHealersInCombat)
    elseif cmd == "combat" then
        ToggleOption("hideInCombat", L.optHideInCombat)
    elseif cmd == "summary" then
        ToggleOption("summary", L.optSummary)
    elseif cmd == "headers" then
        ToggleOption("roleHeaders", L.optRoleHeaders)
    elseif cmd == "self" then
        ToggleOption("showSelf", L.optShowSelf)
    elseif cmd == "add" or cmd == "ignore" or cmd == "remove" then
        ManualList(cmd, rest)
    elseif cmd == "list" then
        PrintLists()
    elseif cmd == "test" then
        testMode = not testMode
        Print(testMode and L.testOn or L.testOff)
        Rebuild()
    elseif cmd == "lang" then
        local code = rest:lower()
        if STRINGS[code] then
            db.lang, L = code, STRINGS[code]
            ApplyTexts()
            Rebuild()
            Print(L.lang)
        else
            Print(L.langHelp)
        end
    elseif cmd == "diag" then
        Diagnose()
    elseif cmd == "debug" then
        db.debug = not db.debug
        wipe(seenErrors)
        Print(db.debug and L.debugOn or L.debugOff)
    else
        Print(L.unknown, cmd)
    end
end

-------------------------------------------------------------------------------
-- Events and initialization
-------------------------------------------------------------------------------

local EVENT_KIND = {
    UNIT_POWER_FREQUENT = "unit",
    UNIT_POWER_UPDATE = "unit",
    UNIT_MAXPOWER = "unit",
    UNIT_DISPLAYPOWER = "unit",
    UNIT_CONNECTION = "unit",
    UNIT_AURA = "aura",
    GROUP_ROSTER_UPDATE = "roster",
    PLAYER_ENTERING_WORLD = "roster",
    PLAYER_ROLES_ASSIGNED = "roster",
    ROLE_CHANGED_INFORM = "roster",
    ACTIVE_PLAYER_SPECIALIZATION_CHANGED = "roster",
    PLAYER_TALENT_UPDATE = "roster",
    UNIT_NAME_UPDATE = "roster",
    PLAYER_SPECIALIZATION_CHANGED = "spec",
    INSPECT_READY = "inspect",
    PLAYER_REGEN_DISABLED = "combat",
    PLAYER_REGEN_ENABLED = "combat",
}

local eventFrame = CreateFrame("Frame")

local function Initialize()
    if type(ManabarDB) ~= "table" then ManabarDB = {} end
    db = ManabarDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    for _, key in ipairs({ "include", "exclude" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    if type(db.roles) ~= "table" then db.roles = {} end
    for role, on in pairs(DEFAULT_ROLES) do
        if db.roles[role] == nil then db.roles[role] = on end
    end
    db.specs = nil -- the class / spec filter of versions 1.1 - 1.4
    L = STRINGS[db.lang] or STRINGS.hu or L
    inCombat = (Plain(Call(UnitAffectingCombat, "player")) or Plain(Call(InCombatLockdown))) and true or false

    BuildCurves()
    BuildDrinkNames()
    BuildDrinkScanners()
    BuildSpecData()
    CreateMainFrame()
    frame:SetScale(db.scale)
    ApplyPosition()
    ApplyTexts()
    ApplyLock()

    for event in pairs(EVENT_KIND) do
        -- Unknown events raise an error on modern clients; skip those quietly.
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end

    Rebuild()

    if not db.welcomed then
        db.welcomed = true
        Print(L.welcome)
    end
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            self:UnregisterEvent("ADDON_LOADED")
            Initialize()
        end
        return
    end
    if not db then return end

    local kind = EVENT_KIND[event]
    if kind == "unit" or kind == "aura" then
        local bar = unitToBar[arg1]
        if bar then
            bar.dirty = true
            if kind == "aura" then bar.dirtyAura = true end
            dirtyPending = true
        end
    elseif kind == "roster" then
        if event == "UNIT_NAME_UPDATE" and not IsGroupToken(arg1) then return end
        if event == "PLAYER_ENTERING_WORLD" then BuildDrinkNames() end
        ScheduleRebuild()
    elseif kind == "spec" then
        OnSpecChanged(arg1)
    elseif kind == "inspect" then
        OnInspectReady(arg1)
    elseif kind == "combat" then
        -- Rebuild at once: "healers in combat" changes the list (remembered
        -- identities keep it working while the game hides names in a fight).
        inCombat = (event == "PLAYER_REGEN_DISABLED")
        Rebuild()
        if not inCombat then ScheduleInspect() end
    end
end)
eventFrame:RegisterEvent("ADDON_LOADED")

SLASH_MANABAR1 = "/manabar"
SlashCmdList.MANABAR = HandleSlash

-------------------------------------------------------------------------------
-- Shared with Options.lua (and the offline tests in tests/)
-------------------------------------------------------------------------------

ns.GetDB = function() return db end
ns.GetL = function() return L end
ns.IsRoleEnabled = IsRoleEnabled
ns.SetRoleEnabled = SetRoleEnabled
ns.SetOption = SetOption
ns.FONT = FONT
ns.WHITE_TEXTURE = WHITE_TEXTURE
ns.BACKDROP_TEMPLATE = BACKDROP_TEMPLATE

ns.bars = bars
ns.unitToBar = unitToBar
ns.specCache = specCache
ns.GetActiveBars = function() return activeBars end
ns.GetSummaryBar = function() return summaryBar end
ns.GetHeader = function(role) return headers[role] end
ns.GetGroups = function() return groups end
ns.ROLE_ICONS = ROLE_ICONS
ns.ROLE_COORDS = ROLE_COORDS
ns.GetGearButton = function() return gearButton end
ns.GradientRGB = GradientRGB
ns.IsTestMode = function() return testMode end
