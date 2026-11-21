-- Manabar settings window: opened by the gear icon on the bars or /manabar.
-- The group roles whose mana is shown (Healer / DPS / Tank) and the display
-- options.

local _, ns = ...

local WIDTH      = 380
local PAD        = 14
local ROW_H      = 22
local CHECK_SIZE = 20
local ROLE_COL   = 112  -- width of one role checkbox
local ICON_SIZE  = 16

local CHECK_TEXTURES = {
    normal    = "Interface\\Buttons\\UI-CheckBox-Up",
    pushed    = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checked   = "Interface\\Buttons\\UI-CheckBox-Check",
}

-- Blizzard's role icons (the same as in the group finder), from Manabar.lua.
local ROLES = {
    { role = "HEALER",  text = "roleHealer" },
    { role = "DAMAGER", text = "roleDamager" },
    { role = "TANK",    text = "roleTank" },
}

-- Display options: SavedVariables key + text key.
local OPTIONS = {
    { key = "hideInCombat", text = "optHideInCombat" },
    { key = "roleHeaders",  text = "optRoleHeaders" },
    { key = "summary",      text = "optSummary" },
    { key = "showSelf",     text = "optShowSelf" },
    { key = "showUnknown",  text = "optShowUnknown" },
    { key = "specIcons",    text = "optSpecIcons" },
    { key = "locked",       text = "optLocked" },
}

local win
local labels = {}       -- { fontString, text key } for re-translation
local optionChecks = {} -- { checkButton, SavedVariables key }
local roleChecks = {}   -- { checkButton, role }

local function T(key)
    local texts = ns.GetL()
    return texts and texts[key] or key
end

local function NewText(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.FONT, size, "")
    fs:SetTextColor(r, g, b)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Localize(fs, key)
    labels[#labels + 1] = { fs, key }
    fs:SetText(T(key))
end

local function NewCheck(parent, labelWidth, onClick)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(CHECK_SIZE, CHECK_SIZE)
    cb:SetNormalTexture(CHECK_TEXTURES.normal)
    cb:SetPushedTexture(CHECK_TEXTURES.pushed)
    cb:SetHighlightTexture(CHECK_TEXTURES.highlight, "ADD")
    cb:SetCheckedTexture(CHECK_TEXTURES.checked)
    cb:SetHitRectInsets(0, -labelWidth, 0, 0) -- the label is clickable too
    local label = NewText(cb, 11, 1, 1, 1)
    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    label:SetWidth(labelWidth - 2)
    label:SetWordWrap(false)
    cb.label = label
    cb:SetScript("OnClick", onClick)
    return cb
end

local function SetBorder(button, r, g, b)
    if button.SetBackdropBorderColor then button:SetBackdropBorderColor(r, g, b, 1) end
end

local function NewButton(parent, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, ns.BACKDROP_TEMPLATE)
    b:SetSize(width, height)
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = ns.WHITE_TEXTURE, edgeFile = ns.WHITE_TEXTURE, edgeSize = 1 })
        b:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
    end
    SetBorder(b, 0.45, 0.45, 0.45)
    local label = NewText(b, 11, 1, 0.82, 0)
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    b.label = label
    b:SetScript("OnEnter", function(self) SetBorder(self, 1, 0.82, 0) end)
    b:SetScript("OnLeave", function(self) SetBorder(self, 0.45, 0.45, 0.45) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function Create()
    win = CreateFrame("Frame", "ManabarOptionsFrame", UIParent, ns.BACKDROP_TEMPLATE)
    win:Hide()
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then self:SetUserPlaced(false) end
    end)
    win:SetScript("OnShow", function() ns.RefreshOptions() end)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    if win.SetBackdrop then
        win:SetBackdrop({ bgFile = ns.WHITE_TEXTURE, edgeFile = ns.WHITE_TEXTURE, edgeSize = 1 })
        win:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
        win:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    end

    local title = NewText(win, 14, 1, 0.82, 0)
    title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -12)
    Localize(title, "optTitle")

    local close = NewButton(win, 20, 20, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -8)
    close.label:SetText("X")

    -- Roles
    local y = -40
    local rolesTitle = NewText(win, 12, 1, 0.82, 0)
    rolesTitle:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
    Localize(rolesTitle, "optRoles")
    y = y - 20
    for i, entry in ipairs(ROLES) do
        local role = entry.role
        local cb = NewCheck(win, ROLE_COL - CHECK_SIZE - 4, function(self)
            ns.SetRoleEnabled(role, self:GetChecked() and true or false)
        end)
        cb:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + (i - 1) * ROLE_COL, y)
        local icon = cb:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("LEFT", cb, "RIGHT", 1, 0)
        local coords = ns.ROLE_COORDS[role]
        icon:SetTexture(ns.ROLE_ICONS)
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        cb.icon = icon
        cb.label:ClearAllPoints()
        cb.label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        cb.label:SetWidth(ROLE_COL - CHECK_SIZE - ICON_SIZE - 10)
        Localize(cb.label, entry.text)
        roleChecks[#roleChecks + 1] = { cb, role }
    end
    y = y - ROW_H - 10

    -- Display options
    local display = NewText(win, 12, 1, 0.82, 0)
    display:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
    Localize(display, "optDisplay")
    y = y - 18
    for _, opt in ipairs(OPTIONS) do
        local key = opt.key
        local cb = NewCheck(win, WIDTH - PAD * 2 - CHECK_SIZE - 4, function(self)
            ns.SetOption(key, self:GetChecked() and true or false)
        end)
        cb:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
        Localize(cb.label, opt.text)
        optionChecks[#optionChecks + 1] = { cb, key }
        y = y - ROW_H
    end

    y = y - 8
    local hint = NewText(win, 10, 0.65, 0.65, 0.65)
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
    hint:SetWidth(WIDTH - PAD * 2)
    hint:SetWordWrap(true)
    Localize(hint, "optHint")
    y = y - 60

    win:SetSize(WIDTH, -y)

    -- Escape closes the window.
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ManabarOptionsFrame") end
end

function ns.RefreshOptions()
    if not win or not win:IsShown() then return end
    local db = ns.GetDB()
    if not db then return end
    for _, entry in ipairs(optionChecks) do
        entry[1]:SetChecked(db[entry[2]] and true or false)
    end
    for _, entry in ipairs(roleChecks) do
        entry[1]:SetChecked(ns.IsRoleEnabled(entry[2]) and true or false)
    end
end

function ns.ApplyOptionsTexts()
    for _, entry in ipairs(labels) do
        entry[1]:SetText(T(entry[2]))
    end
end

function ns.ToggleOptions()
    if not ns.GetDB() then return end
    if not win then Create() end
    if win:IsShown() then
        win:Hide()
    else
        win:Show()
    end
end

-- For the offline tests.
function ns.GetOptionsFrame()
    return win, optionChecks, roleChecks
end
