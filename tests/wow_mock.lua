-- A small, strict stand-in for the World of Warcraft UI API: just enough to run
-- Manabar outside the game with plain Lua 5.1 (the Lua version WoW uses).
--
-- It also simulates Midnight's "secret values": arithmetic, comparison,
-- indexing, calling and concatenation on a secret raise an error, and only the
-- widget methods that accept secrets in the real client accept them here.
-- Unknown widget methods, bad anchors, unknown events and setting text before
-- a font is set are errors too, like in the game.

local M = {}
M.realPrint = print

-------------------------------------------------------------------------------
-- Secret values
-------------------------------------------------------------------------------

local secretValues = setmetatable({}, { __mode = "k" })

local function blocked(what)
    return function() error("attempt to " .. what .. " a secret value", 2) end
end

function M.secret(v)
    local p = newproxy(true)
    local mt = getmetatable(p)
    mt.__index = blocked("index")
    mt.__newindex = blocked("index")
    mt.__call = blocked("call")
    mt.__add = blocked("perform arithmetic on")
    mt.__sub = blocked("perform arithmetic on")
    mt.__mul = blocked("perform arithmetic on")
    mt.__div = blocked("perform arithmetic on")
    mt.__mod = blocked("perform arithmetic on")
    mt.__pow = blocked("perform arithmetic on")
    mt.__unm = blocked("perform arithmetic on")
    mt.__lt = blocked("compare")
    mt.__le = blocked("compare")
    mt.__eq = blocked("compare")
    mt.__len = blocked("get the length of")
    mt.__concat = blocked("concatenate")
    mt.__tostring = function() return "<secret>" end
    secretValues[p] = { v = v }
    return p
end

function M.issecret(v)
    if type(v) ~= "userdata" then return false end
    return secretValues[v] ~= nil
end

function M.reveal(v)
    if M.issecret(v) then return secretValues[v].v end
    return v
end

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------

local VALID_POINTS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local SCRIPTS = {
    OnEvent = true, OnUpdate = true, OnDragStart = true, OnDragStop = true, OnShow = true,
    OnHide = true, OnMouseUp = true, OnMouseDown = true, OnEnter = true, OnLeave = true,
    OnClick = true,
}
local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true, TOOLTIP = true }
-- Methods that accept secret arguments in the real client.
local SECRET_OK = {
    SetValue = true, SetMinMaxValues = true, SetStatusBarColor = true, SetText = true,
    SetFormattedText = true, SetVertexColor = true, SetAlpha = true, SetShown = true,
}

local classes = {}
local allObjects = {}

local function defineClass(name, parent)
    local methods = {}
    if parent then
        for k, v in pairs(classes[parent]) do methods[k] = v end
    end
    classes[name] = methods
    return methods
end

local function method(cls, name, fn)
    if SECRET_OK[name] then
        cls[name] = fn
        return
    end
    cls[name] = function(self, ...)
        for i = 1, select("#", ...) do
            if M.issecret((select(i, ...))) then
                error(name .. "(): secret values are not allowed here", 2)
            end
        end
        return fn(self, ...)
    end
end

local function checknum(v, what)
    if type(v) ~= "number" or v ~= v then error((what or "value") .. ": number expected, got " .. type(v), 3) end
end

local function snapshot(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

local function isVisible(o)
    if not o.__shown then return false end
    if o.__parent then return isVisible(o.__parent) end
    return true
end

local function setShown(o, shown)
    if o.__shown == shown then return end
    o.__shown = shown
    local script = o.__scripts and o.__scripts[shown and "OnShow" or "OnHide"]
    if script then script(o) end
end

-- Does region a (transitively) anchor to region b?
local function dependsOn(a, b, seen)
    seen = seen or {}
    if seen[a] then return false end
    seen[a] = true
    for _, p in ipairs(a.__points or {}) do
        if p.rel == b or dependsOn(p.rel, b, seen) then return true end
    end
    return false
end

-- Left/top of a frame anchored to UIParent, in the frame's own scale.
local function rect(o)
    local p = o.__points[1]
    if not p or p.rel ~= M.UIParent then return nil end
    local s = o.__scale or 1
    local rp, pp = VALID_POINTS[p.relPoint], VALID_POINTS[p.point]
    local ax, ay = M.UIParent.__w * rp[1] / s, M.UIParent.__h * rp[2] / s
    local w, h = o.__w or 0, o.__h or 0
    return ax + p.x - pp[1] * w, ay + p.y + (1 - pp[2]) * h
end

local Region = defineClass("Region")
method(Region, "GetObjectType", function(self) return self.__type end)
method(Region, "GetName", function(self) return self.__name end)
method(Region, "GetParent", function(self) return self.__parent end)
method(Region, "SetPoint", function(self, point, a, b, c, d)
    if not VALID_POINTS[point] then error("SetPoint(): invalid point " .. tostring(point), 2) end
    local rel, relPoint, x, y
    if a == nil or type(a) == "number" then
        rel, relPoint, x, y = nil, point, a or 0, b or 0
    else
        rel = a
        if type(b) == "string" then
            relPoint, x, y = b, c or 0, d or 0
        else
            relPoint, x, y = point, b or 0, c or 0
        end
    end
    if rel == nil then rel = self.__parent or M.UIParent end
    if type(rel) == "string" then rel = _G[rel] end
    if type(rel) ~= "table" or not rel.__type then error("SetPoint(): invalid relative region", 2) end
    if not VALID_POINTS[relPoint] then error("SetPoint(): invalid relative point " .. tostring(relPoint), 2) end
    if type(x) ~= "number" or type(y) ~= "number" then error("SetPoint(): offsets must be numbers", 2) end
    if rel == self or dependsOn(rel, self) then error("SetPoint(): anchor family connection loop", 2) end
    for i, p in ipairs(self.__points) do
        if p.point == point then
            table.remove(self.__points, i)
            break
        end
    end
    table.insert(self.__points, { point = point, rel = rel, relPoint = relPoint, x = x, y = y })
end)
method(Region, "SetAllPoints", function(self, rel)
    self.__points = {}
    rel = rel or self.__parent
    self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end)
method(Region, "ClearAllPoints", function(self) self.__points = {} end)
method(Region, "GetNumPoints", function(self) return #self.__points end)
method(Region, "GetPoint", function(self, i)
    local p = self.__points[i or 1]
    if p then return p.point, p.rel, p.relPoint, p.x, p.y end
end)
method(Region, "SetSize", function(self, w, h)
    checknum(w, "width")
    checknum(h, "height")
    self.__w, self.__h = w, h
end)
method(Region, "SetWidth", function(self, w) checknum(w, "width"); self.__w = w end)
method(Region, "SetHeight", function(self, h) checknum(h, "height"); self.__h = h end)
method(Region, "GetWidth", function(self) return self.__w or 0 end)
method(Region, "GetHeight", function(self) return self.__h or 0 end)
method(Region, "Show", function(self) setShown(self, true) end)
method(Region, "Hide", function(self) setShown(self, false) end)
method(Region, "SetShown", function(self, shown) setShown(self, M.reveal(shown) and true or false) end)
method(Region, "IsShown", function(self) return self.__shown end)
method(Region, "IsVisible", function(self) return isVisible(self) end)
method(Region, "SetAlpha", function(self, a) self.__alpha = M.reveal(a) end)
method(Region, "GetAlpha", function(self) return self.__alpha end)
method(Region, "GetLeft", function(self) return (rect(self)) end)
method(Region, "GetTop", function(self)
    local _, top = rect(self)
    return top
end)

local Frame = defineClass("Frame", "Region")
method(Frame, "SetScale", function(self, s)
    checknum(s, "scale")
    if s <= 0 then error("SetScale(): scale must be > 0", 2) end
    self.__scale = s
end)
method(Frame, "GetScale", function(self) return self.__scale end)
method(Frame, "GetEffectiveScale", function(self)
    local s = self.__scale
    if self.__parent then s = s * self.__parent:GetEffectiveScale() end
    return s
end)
method(Frame, "EnableMouse", function(self, v) self.__mouse = v and true or false end)
method(Frame, "IsMouseEnabled", function(self) return self.__mouse == true end)
method(Frame, "SetMovable", function(self, v) self.__movable = v and true or false end)
method(Frame, "IsMovable", function(self) return self.__movable == true end)
method(Frame, "SetClampedToScreen", function(self, v) self.__clamped = v and true or false end)
method(Frame, "RegisterForDrag", function(self, ...) self.__drag = { ... } end)
method(Frame, "SetScript", function(self, name, fn)
    if not SCRIPTS[name] then error("SetScript(): unknown script " .. tostring(name), 2) end
    if fn ~= nil and type(fn) ~= "function" then error("SetScript(): function expected", 2) end
    self.__scripts[name] = fn
end)
method(Frame, "GetScript", function(self, name) return self.__scripts[name] end)
method(Frame, "RegisterEvent", function(self, event)
    if not M.knownEvents[event] then
        error('Frame:RegisterEvent(): Attempt to register unknown event "' .. tostring(event) .. '"', 2)
    end
    self.__events[event] = true
    return true
end)
method(Frame, "UnregisterEvent", function(self, event) self.__events[event] = nil end)
method(Frame, "IsEventRegistered", function(self, event) return self.__events[event] == true end)
method(Frame, "SetFrameStrata", function(self, strata)
    if not STRATA[strata] then error("SetFrameStrata(): invalid strata " .. tostring(strata), 2) end
    self.__strata = strata
end)
method(Frame, "SetFrameLevel", function(self, level) checknum(level, "level"); self.__level = level end)
method(Frame, "StartMoving", function(self)
    if not self.__movable then error("StartMoving(): frame is not movable", 2) end
    self.__moving = true
    self.__userPlaced = true
end)
method(Frame, "StopMovingOrSizing", function(self)
    if not self.__moving then return end
    self.__moving = false
    local dest = M.dragTo
    if dest then
        -- The client re-anchors a moved frame on its own; use BOTTOMLEFT here so
        -- the addon has to convert it (dest = { left, top } in frame units).
        self.__points = {
            { point = "BOTTOMLEFT", rel = M.UIParent, relPoint = "BOTTOMLEFT", x = dest[1], y = dest[2] - (self.__h or 0) },
        }
    end
end)
method(Frame, "SetUserPlaced", function(self, v)
    if not self.__movable then error("SetUserPlaced(): frame is not movable", 2) end
    self.__userPlaced = v and true or false
end)
method(Frame, "IsUserPlaced", function(self) return self.__userPlaced == true end)

local newObject

method(Frame, "CreateFontString", function(self, name)
    return newObject("FontString", name, self)
end)
method(Frame, "CreateTexture", function(self, name)
    return newObject("Texture", name, self)
end)

local StatusBar = defineClass("StatusBar", "Frame")
method(StatusBar, "SetStatusBarTexture", function(self, tex)
    if type(tex) == "table" then
        self.__barTexture = tex
        return
    end
    if type(tex) ~= "string" and type(tex) ~= "number" then error("SetStatusBarTexture(): texture expected", 2) end
    local t = self.__barTexture or newObject("Texture", nil, self)
    t.__texture = tex
    t.__color = t.__color or { 1, 1, 1, 1 }
    self.__barTexture = t
end)
method(StatusBar, "GetStatusBarTexture", function(self) return self.__barTexture end)
method(StatusBar, "SetMinMaxValues", function(self, lo, hi)
    self.__minMaxSecret = M.issecret(lo) or M.issecret(hi)
    lo, hi = M.reveal(lo), M.reveal(hi)
    checknum(lo, "min")
    checknum(hi, "max")
    self.__min, self.__max = lo, hi
end)
method(StatusBar, "GetMinMaxValues", function(self) return self.__min, self.__max end)
method(StatusBar, "SetValue", function(self, v)
    self.__valueSecret = M.issecret(v)
    v = M.reveal(v)
    checknum(v, "SetValue()")
    self.__value = v
end)
method(StatusBar, "GetValue", function(self) return self.__value end)
method(StatusBar, "SetStatusBarColor", function(self, r, g, b, a)
    self.__barTexture:SetVertexColor(r, g, b, a)
end)

local Button = defineClass("Button", "Frame")
local function textureSetter(field)
    return function(self, tex, blend)
        if tex ~= nil and type(tex) ~= "string" and type(tex) ~= "number" and type(tex) ~= "table" then
            error("texture path expected", 2)
        end
        self[field] = tex
        self[field .. "Blend"] = blend
    end
end
method(Button, "SetNormalTexture", textureSetter("__normalTexture"))
method(Button, "SetPushedTexture", textureSetter("__pushedTexture"))
method(Button, "SetHighlightTexture", textureSetter("__highlightTexture"))
method(Button, "SetDisabledTexture", textureSetter("__disabledTexture"))
method(Button, "SetHitRectInsets", function(self, l, r, t, b)
    checknum(l, "left")
    checknum(r, "right")
    checknum(t, "top")
    checknum(b, "bottom")
    self.__hitRect = { l, r, t, b }
end)
method(Button, "RegisterForClicks", function(self, ...) self.__clicks = { ... } end)
method(Button, "Enable", function(self) self.__disabled = false end)
method(Button, "Disable", function(self) self.__disabled = true end)
method(Button, "IsEnabled", function(self) return not self.__disabled end)

local CheckButton = defineClass("CheckButton", "Button")
method(CheckButton, "SetCheckedTexture", textureSetter("__checkedTexture"))
method(CheckButton, "SetDisabledCheckedTexture", textureSetter("__disabledCheckedTexture"))
method(CheckButton, "SetChecked", function(self, v) self.__checked = v and true or false end)
method(CheckButton, "GetChecked", function(self) return self.__checked == true end)

local FontString = defineClass("FontString", "Region")
method(FontString, "SetFont", function(self, path, size, flags)
    if type(path) ~= "string" or type(size) ~= "number" or size <= 0 then
        error("SetFont(): bad arguments", 2)
    end
    self.__font = { path, size, flags }
    return true
end)
method(FontString, "GetFont", function(self)
    if self.__font then return self.__font[1], self.__font[2], self.__font[3] end
end)
method(FontString, "SetText", function(self, text)
    if not self.__font then error("FontString:SetText(): Font not set", 2) end
    self.__textSecret = M.issecret(text)
    text = M.reveal(text)
    if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then
        error("SetText(): string expected", 2)
    end
    self.__text = text ~= nil and tostring(text) or nil
end)
method(FontString, "SetFormattedText", function(self, fmt, ...)
    if not self.__font then error("FontString:SetFormattedText(): Font not set", 2) end
    local n = select("#", ...)
    local args = { ... }
    local secret = false
    for i = 1, n do
        if M.issecret(args[i]) then
            secret = true
            args[i] = M.reveal(args[i])
        end
    end
    self.__textSecret = secret
    self.__text = string.format(fmt, unpack(args, 1, n))
end)
method(FontString, "GetText", function(self) return self.__text end)
method(FontString, "SetTextColor", function(self, r, g, b, a) self.__textColor = { r, g, b, a } end)
method(FontString, "SetJustifyH", function(self, j)
    if j ~= "LEFT" and j ~= "CENTER" and j ~= "RIGHT" then error("SetJustifyH(): bad value", 2) end
    self.__justifyH = j
end)
method(FontString, "SetJustifyV", function(self, j) self.__justifyV = j end)
method(FontString, "SetWordWrap", function(self, v) self.__wordWrap = v and true or false end)
method(FontString, "SetNonSpaceWrap", function(self, v) self.__nonSpaceWrap = v and true or false end)

local Texture = defineClass("Texture", "Region")
method(Texture, "SetTexture", function(self, tex) self.__texture = tex end)
method(Texture, "GetTexture", function(self) return self.__texture end)
method(Texture, "SetTexCoord", function(self, ...)
    local n = select("#", ...)
    if n ~= 4 and n ~= 8 then error("SetTexCoord(): 4 or 8 numbers expected", 2) end
    for i = 1, n do checknum((select(i, ...)), "texcoord") end
end)
method(Texture, "SetVertexColor", function(self, r, g, b, a)
    self.__colorSecret = M.issecret(r) or M.issecret(g) or M.issecret(b) or M.issecret(a)
    r, g, b, a = M.reveal(r), M.reveal(g), M.reveal(b), M.reveal(a)
    checknum(r, "r")
    checknum(g, "g")
    checknum(b, "b")
    self.__color = { r, g, b, a or 1 }
end)
method(Texture, "GetVertexColor", function(self)
    local c = self.__color or { 1, 1, 1, 1 }
    return c[1], c[2], c[3], c[4]
end)

local Tooltip = defineClass("GameTooltip", "Frame")
method(Tooltip, "SetOwner", function(self, owner)
    self.__owner = owner
    self.__lines = {}
end)
method(Tooltip, "GetOwner", function(self) return self.__owner end)
method(Tooltip, "IsOwned", function(self, f) return self.__owner ~= nil and self.__owner == f end)
method(Tooltip, "SetText", function(self, text) self.__lines = { text } end)
method(Tooltip, "AddLine", function(self, text) table.insert(self.__lines, text) end)
method(Tooltip, "Hide", function(self)
    setShown(self, false)
    self.__owner = nil
end)

local Backdrop = {}
method(Backdrop, "SetBackdrop", function(self, bd)
    if bd ~= nil and type(bd) ~= "table" then error("SetBackdrop(): table expected", 2) end
    self.__backdrop = bd
end)
method(Backdrop, "SetBackdropColor", function(self, r, g, b, a)
    if not self.__backdrop then error("SetBackdropColor(): no backdrop set", 2) end
    self.__backdropColor = { r, g, b, a }
end)
method(Backdrop, "SetBackdropBorderColor", function(self, r, g, b, a)
    if not self.__backdrop then error("SetBackdropBorderColor(): no backdrop set", 2) end
    self.__backdropBorderColor = { r, g, b, a }
end)

newObject = function(otype, name, parent, template)
    local cls = classes[otype]
    if not cls then error("CreateFrame(): unknown frame type " .. tostring(otype), 3) end
    local o = {
        __type = otype, __name = name, __parent = parent, __shown = true, __points = {},
        __scripts = {}, __events = {}, __scale = 1, __alpha = 1, __children = {},
    }
    if template ~= nil then
        if template ~= "BackdropTemplate" then error("CreateFrame(): unknown template " .. tostring(template), 3) end
        for k, v in pairs(Backdrop) do o[k] = v end
    end
    setmetatable(o, { __index = cls })
    if parent then table.insert(parent.__children, o) end
    if name then _G[name] = o end
    allObjects[#allObjects + 1] = o
    return o
end

function M.CreateFrame(otype, name, parent, template)
    if otype ~= "Frame" and otype ~= "StatusBar" and otype ~= "Button" and otype ~= "CheckButton" then
        error("CreateFrame(): frame type not supported by the mock: " .. tostring(otype), 2)
    end
    if parent ~= nil and (type(parent) ~= "table" or not parent.__type) then
        error("CreateFrame(): invalid parent", 2)
    end
    return newObject(otype, name, parent, template)
end

-------------------------------------------------------------------------------
-- Events and time
-------------------------------------------------------------------------------

M.knownEvents = {
    ADDON_LOADED = true, PLAYER_ENTERING_WORLD = true, GROUP_ROSTER_UPDATE = true,
    PLAYER_ROLES_ASSIGNED = true, PLAYER_SPECIALIZATION_CHANGED = true,
    ACTIVE_PLAYER_SPECIALIZATION_CHANGED = true, INSPECT_READY = true, PLAYER_REGEN_ENABLED = true,
    UNIT_NAME_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true,
    UNIT_DISPLAYPOWER = true, UNIT_CONNECTION = true, UNIT_AURA = true, PLAYER_REGEN_DISABLED = true,
    -- ROLE_CHANGED_INFORM and PLAYER_TALENT_UPDATE are left out on purpose:
    -- registering them must not break the addon.
}

local timers = {}

function M.fire(event, ...)
    for _, o in ipairs(snapshot(allObjects)) do
        if o.__events[event] then
            local fn = o.__scripts.OnEvent
            if fn then fn(o, event, ...) end
        end
    end
end

function M.tick(dt)
    M.now = M.now + dt
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= M.now + 1e-9 then table.insert(due, 1, table.remove(timers, i)) end
    end
    for _, t in ipairs(due) do t.fn() end
    for _, o in ipairs(snapshot(allObjects)) do
        local fn = o.__scripts.OnUpdate
        if fn and isVisible(o) then fn(o, dt) end
    end
end

function M.run(seconds, step)
    step = step or 0.05
    local n = math.floor(seconds / step + 0.5)
    for _ = 1, n do M.tick(step) end
end

-- Simulates a left click like the client: a CheckButton toggles first.
function M.click(button, mouseButton)
    if not isVisible(button) then error("click on a hidden button", 2) end
    if button.__disabled then return end
    if button.__type == "CheckButton" then button.__checked = not button.__checked end
    local fn = button.__scripts.OnClick
    if fn then fn(button, mouseButton or "LeftButton", false) end
end

function M.isRegistered(event)
    for _, o in ipairs(allObjects) do
        if o.__events[event] then return true end
    end
    return false
end

function M.setCombat(on)
    M.state.inCombat = on and true or false
    M.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

-------------------------------------------------------------------------------
-- Units, group, auras, specs
-------------------------------------------------------------------------------

local function member(token)
    if M.issecret(token) then error("unit token must not be secret", 3) end
    if type(token) ~= "string" then return nil end
    local st = M.state
    if token == "player" then return st.player end
    if token == "target" then return st.target end
    local n = token:match("^party(%d+)$")
    if n then return st.kind == "party" and st.party[tonumber(n)] or nil end
    n = token:match("^raid(%d+)$")
    if n then return st.kind == "raid" and st.raid[tonumber(n)] or nil end
    return nil
end
M.member = member

local function newMember(t)
    t.class = t.class or "WARRIOR"
    t.className = t.className or (t.class:sub(1, 1) .. t.class:sub(2):lower())
    t.mana = t.mana or 0
    t.maxMana = t.maxMana or 0
    if t.connected == nil then t.connected = true end
    t.dead = t.dead or false
    t.auras = t.auras or {}
    t.guid = t.guid or ("Player-1-" .. t.name)
    return t
end

-- kind: "solo" | "party" | "raid". members: list of unit specs; the one with
-- isPlayer = true (default: the first) is you.
function M.setGroup(kind, members)
    local st = M.state
    st.kind, st.party, st.raid = kind, {}, {}
    local list, flagged = {}, false
    for _, spec in ipairs(members) do
        if spec.isPlayer then flagged = true end
    end
    for i, spec in ipairs(members) do
        local m = newMember(spec)
        if not flagged and i == 1 then m.isPlayer = true end
        if m.isPlayer then st.player = m end
        list[#list + 1] = m
    end
    if kind == "party" then
        for _, m in ipairs(list) do
            if not m.isPlayer then st.party[#st.party + 1] = m end
        end
    elseif kind == "raid" then
        st.raid = list
    end
end

local function hideIf(flag, m, v)
    if flag and not m.isPlayer then return M.secret(v) end
    return v
end

local function auraRestricted(m)
    local flag = M.flags.auraRestricted
    if flag == nil then flag = M.flags.restricted end
    return flag and not m.isPlayer
end

local ColorMixin = {}
function ColorMixin:GetRGB() return self.r, self.g, self.b end
function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a end

function M.CreateColor(r, g, b, a)
    local c = { r = r, g = g, b = b, a = a or 1 }
    for k, v in pairs(ColorMixin) do c[k] = v end
    return c
end

local function lerp(points, x, isColor)
    if #points == 0 then return isColor and M.CreateColor(0, 0, 0, 0) or 0 end
    if x <= points[1].x then return points[1].y end
    for i = 2, #points do
        local b = points[i]
        if x <= b.x then
            local a = points[i - 1]
            local t = (x - a.x) / (b.x - a.x)
            if isColor then
                return M.CreateColor(a.y.r + (b.y.r - a.y.r) * t, a.y.g + (b.y.g - a.y.g) * t,
                    a.y.b + (b.y.b - a.y.b) * t, a.y.a + (b.y.a - a.y.a) * t)
            end
            return a.y + (b.y - a.y) * t
        end
    end
    return points[#points].y
end

-- How a color evaluated from secret input comes back: "fields" = a color table
-- whose components are secret; "opaque" = the whole color is a secret.
local function secretColor(c)
    if M.flags.colorMode == "opaque" then return M.secret(c) end
    return M.CreateColor(M.secret(c.r), M.secret(c.g), M.secret(c.b), M.secret(c.a))
end

local function newCurve(isColor)
    local c = { __isCurve = true, __isColor = isColor, __points = {} }
    function c:SetType(t)
        if t == nil then error("SetType(): curve type expected", 2) end
        self.__curveType = t
    end
    function c:AddPoint(x, y)
        checknum(x, "x")
        if isColor then
            if type(y) ~= "table" or type(y.r) ~= "number" then error("AddPoint(): color expected", 2) end
        else
            checknum(y, "y")
        end
        table.insert(self.__points, { x = x, y = y })
        table.sort(self.__points, function(p, q) return p.x < q.x end)
    end
    function c:__eval(x) return lerp(self.__points, x, isColor) end
    function c:Evaluate(x)
        local v = lerp(self.__points, M.reveal(x), isColor)
        if M.issecret(x) then
            if isColor then return secretColor(v) end
            return M.secret(v)
        end
        return v
    end
    if isColor then
        function c:EvaluateUnpacked(x)
            local col = lerp(self.__points, M.reveal(x), true)
            if M.issecret(x) then
                return M.secret(col.r), M.secret(col.g), M.secret(col.b), M.secret(col.a)
            end
            return col.r, col.g, col.b, col.a
        end
    end
    return c
end

local API = {}

function API.UnitExists(unit) return member(unit) ~= nil end
function API.UnitName(unit)
    local m = member(unit)
    if not m then return nil end
    return hideIf(M.flags.secretNames, m, m.name), nil
end
function API.UnitClass(unit)
    local m = member(unit)
    if not m then return nil end
    return hideIf(M.flags.secretNames, m, m.className), m.class, 1
end
function API.UnitGUID(unit)
    local m = member(unit)
    return m and m.guid or nil
end
function API.UnitIsUnit(a, b)
    local ma, mb = member(a), member(b)
    local same = ma ~= nil and ma == mb
    if M.flags.secretCompare then return M.secret(same) end
    return same
end
function API.UnitGroupRolesAssigned(unit)
    local m = member(unit)
    return m and m.role or "NONE"
end
function API.UnitIsConnected(unit)
    local m = member(unit)
    if not m then return false end
    return hideIf(M.flags.secretFlags, m, m.connected)
end
function API.UnitIsDeadOrGhost(unit)
    local m = member(unit)
    if not m then return false end
    return hideIf(M.flags.secretFlags, m, m.dead)
end
function API.UnitPower(unit, powerType)
    local m = member(unit)
    if not m or (powerType or 0) ~= 0 then return 0 end
    return hideIf(M.flags.restricted, m, m.mana)
end
function API.UnitPowerMax(unit, powerType)
    local m = member(unit)
    if not m or (powerType or 0) ~= 0 then return 0 end
    return hideIf(M.flags.secretMax, m, m.maxMana)
end
function API.UnitPowerPercent(unit, powerType, unmodified, curve)
    if M.issecret(unit) or M.issecret(curve) then error("UnitPowerPercent(): secret arguments are not allowed", 2) end
    if curve ~= nil and (type(curve) ~= "table" or not curve.__isCurve) then
        error("UnitPowerPercent(): curve object expected", 2)
    end
    local m = member(unit)
    if not m then return nil end
    local frac = 0
    if (powerType or 0) == 0 and m.maxMana > 0 then frac = m.mana / m.maxMana end
    local result = frac
    if curve then result = curve:__eval(frac) end
    if M.flags.restricted and not m.isPlayer then
        if type(result) == "table" then return secretColor(result) end
        return M.secret(result)
    end
    return result
end
function API.IsInRaid() return M.state.kind == "raid" end
function API.IsInGroup() return M.state.kind ~= "solo" end
function API.GetNumGroupMembers()
    local st = M.state
    if st.kind == "raid" then return #st.raid end
    if st.kind == "party" then return #st.party + 1 end
    return 0
end
function API.GetNumSubgroupMembers()
    local st = M.state
    if st.kind == "party" then return #st.party end
    return 0
end
local CLASS_NAMES = { [2] = "Paladin", [3] = "Hunter", [5] = "Priest", [7] = "Shaman", [8] = "Mage",
    [9] = "Warlock", [11] = "Druid" }
local CLASS_FILES = { [2] = "PALADIN", [3] = "HUNTER", [5] = "PRIEST", [7] = "SHAMAN", [8] = "MAGE",
    [9] = "WARLOCK", [11] = "DRUID" }

local function findSpec(specID)
    for _, specs in pairs(M.classSpecData) do
        for _, s in ipairs(specs) do
            if s[1] == specID then return s end
        end
    end
end

function API.GetSpecialization()
    local id = M.state.player and M.state.player.spec
    if not id then return nil end
    return 1
end
function API.GetSpecializationInfo(index)
    local id = M.state.player and M.state.player.spec
    local s = id and findSpec(id)
    if index ~= 1 or not s then return nil end
    return s[1], s[2], "", 0, s[3], 1
end
function API.GetClassInfo(classID)
    if not CLASS_NAMES[classID] then return nil end
    return CLASS_NAMES[classID], CLASS_FILES[classID], classID
end
function API.GetNumSpecializationsForClassID(classID)
    local specs = M.classSpecData[classID]
    return specs and #specs or 0
end
function API.GetSpecializationInfoForClassID(classID, index)
    local s = M.classSpecData[classID] and M.classSpecData[classID][index]
    if not s then return nil end
    return s[1], s[2], "", 0, s[3], false, true
end
function API.GetInspectSpecialization(unit)
    local m = member(unit)
    if m and M.inspectData[m.guid] and m.spec then return m.spec end
    return 0
end
function API.GetTime() return M.now end
function API.InCombatLockdown() return M.state.inCombat == true end
function API.UnitAffectingCombat(unit)
    local m = member(unit)
    return m ~= nil and m.isPlayer and M.state.inCombat == true
end
function API.CanInspect(unit)
    local m = member(unit)
    return m ~= nil and not m.isPlayer and m.connected ~= false
end
-- Protected in combat in the real client: an addon calling it there is blocked
-- (no Lua error, the client shows "Interface action failed"), so record it.
function API.CheckInteractDistance(unit, index)
    if M.state.inCombat then
        table.insert(M.blocked, "CheckInteractDistance")
        return nil
    end
    local m = member(unit)
    return m ~= nil and m.inRange ~= false
end
function API.NotifyInspect(unit)
    if M.issecret(unit) then error("NotifyInspect(): secret unit", 2) end
    local m = member(unit)
    if not m then return end
    table.insert(M.inspectRequests, m.name)
    if M.flags.inspectNeverAnswers then return end
    table.insert(timers, { at = M.now + 0.3, fn = function()
        M.inspectData[m.guid] = true
        M.fire("INSPECT_READY", m.guid)
    end })
end
function API.ClearInspectPlayer()
    M.clearInspectCount = M.clearInspectCount + 1
end

local function newAuraApi()
    return {
        GetAuraDataBySpellName = function(unit, name)
            if M.issecret(name) then error("GetAuraDataBySpellName(): secret name", 2) end
            local m = member(unit)
            if not m or auraRestricted(m) then return nil end
            for i, a in ipairs(m.auras) do
                if a == name then return { name = a, auraInstanceID = i, spellId = 430 } end
            end
            return nil
        end,
        GetAuraDataByIndex = function(unit, index)
            checknum(index, "index")
            local m = member(unit)
            if not m then return nil end
            local a = m.auras[index]
            if not a then return nil end
            if auraRestricted(m) then return { name = M.secret(a), auraInstanceID = index } end
            return { name = a, auraInstanceID = index }
        end,
    }
end

-------------------------------------------------------------------------------
-- Install / load
-------------------------------------------------------------------------------

M.chat = {}

function M.chatText()
    return table.concat(M.chat, "\n")
end

function M.clearChat()
    M.chat = {}
end

-- opts.noCurves: client without UnitPowerPercent / curve objects
-- opts.noAuraByName: client without C_UnitAuras.GetAuraDataBySpellName
function M.install(opts)
    opts = opts or {}
    for i = #allObjects, 1, -1 do allObjects[i] = nil end
    for i = #timers, 1, -1 do timers[i] = nil end
    M.now = 0
    M.dragTo = nil
    M.flags = { restricted = false, secretMax = false, secretFlags = false, secretNames = false,
        secretCompare = false, auraRestricted = nil, colorMode = "fields", inspectNeverAnswers = false }
    M.state = { kind = "solo", party = {}, raid = {}, player = nil, target = nil, inCombat = false }
    -- classID -> { { specID, name, role }, ... } (WoW Forever: 3 specs per class)
    M.classSpecData = {
        [2] = { { 65, "Holy", "HEALER" }, { 66, "Protection", "TANK" }, { 70, "Retribution", "DAMAGER" } },
        [3] = { { 253, "Beast Mastery", "DAMAGER" }, { 254, "Marksmanship", "DAMAGER" }, { 255, "Survival", "DAMAGER" } },
        [5] = { { 256, "Discipline", "HEALER" }, { 257, "Holy", "HEALER" }, { 258, "Shadow", "DAMAGER" } },
        [7] = { { 262, "Elemental", "DAMAGER" }, { 263, "Enhancement", "DAMAGER" }, { 264, "Restoration", "HEALER" } },
        [8] = { { 62, "Arcane", "DAMAGER" }, { 63, "Fire", "DAMAGER" }, { 64, "Frost", "DAMAGER" } },
        [9] = { { 265, "Affliction", "DAMAGER" }, { 266, "Demonology", "DAMAGER" }, { 267, "Destruction", "DAMAGER" } },
        [11] = { { 102, "Balance", "DAMAGER" }, { 103, "Feral", "DAMAGER" }, { 105, "Restoration", "HEALER" } },
    }
    M.inspectData = {}
    M.blocked = {}
    M.inspectRequests = {}
    M.clearInspectCount = 0
    M.spellNames = { [430] = "Drink", [431] = "Drink", [432] = "Drink", [1133] = "Drink",
        [1135] = "Drink", [1137] = "Drink", [22734] = "Drink" }
    M.chat = {}

    _G.ManabarDB, _G.SLASH_MANABAR1, _G.ManabarFrame = nil, nil, nil
    _G.SlashCmdList = {}
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.UISpecialFrames = {}
    _G.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    _G.InspectFrame = nil
    _G.BackdropTemplateMixin = {}
    _G.Enum = { PowerType = { Mana = 0 }, LuaCurveType = { Linear = 0, Step = 1 } }
    _G.issecretvalue = M.issecret
    _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        table.insert(M.chat, table.concat(parts, " "))
    end
    _G.CreateFrame = M.CreateFrame
    _G.CreateColor = M.CreateColor
    _G.C_Timer = { After = function(delay, fn)
        checknum(delay, "delay")
        table.insert(timers, { at = M.now + delay, fn = fn })
    end }
    _G.C_Spell = { GetSpellName = function(id) return M.spellNames[id] end }
    _G.GetSpellInfo = nil
    _G.C_SpecializationInfo = nil
    _G.C_UnitAuras = newAuraApi()
    if opts.noAuraByName then _G.C_UnitAuras.GetAuraDataBySpellName = nil end
    _G.C_CurveUtil = {
        CreateCurve = function() return newCurve(false) end,
        CreateColorCurve = function() return newCurve(true) end,
    }
    for k, v in pairs(API) do _G[k] = v end
    if opts.noCurves then
        _G.UnitPowerPercent = nil
        _G.C_CurveUtil = nil
    end

    M.UIParent = newObject("Frame", "UIParent", nil)
    M.UIParent.__w, M.UIParent.__h = 1600, 900
    _G.GameTooltip = newObject("GameTooltip", "GameTooltip", M.UIParent)
    _G.GameTooltip.__shown = false
end

-- Loads the addon files listed in the TOC, in order, with one shared namespace.
function M.loadAddon(dir, name)
    name = name or "Manabar"
    local ns = {}
    local toc = assert(io.open(dir .. "/" .. name .. ".toc", "r"))
    for line in toc:lines() do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:find("^#") then
            local chunk = assert(loadfile(dir .. "/" .. line))
            chunk(name, ns)
        end
    end
    toc:close()
    return ns
end

return M
