-- Manabar settings window: opened by the gear icon on the bars or /manabar.
-- Display options, the class/spec combinations whose mana is shown, presets.

local _, ns = ...

local PAD        = 14
local CLASS_COL  = 86   -- width of the class name column
local SPEC_COL   = 140  -- width of one spec checkbox column
local ROW_H      = 22
local CHECK_SIZE = 20
local ICON_SIZE  = 14

local CHECK_TEXTURES = {
    normal    = "Interface\\Buttons\\UI-CheckBox-Up",
    pushed    = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checked   = "Interface\\Buttons\\UI-CheckBox-Check",
}

-- Used when RAID_CLASS_COLORS is not available.
local CLASS_COLORS = {
    PRIEST = { 1, 1, 1 }, PALADIN = { 0.96, 0.55, 0.73 }, SHAMAN = { 0, 0.44, 0.87 },
    DRUID = { 1, 0.49, 0.04 }, MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 },
    HUNTER = { 0.67, 0.83, 0.45 },
}

-- Display options: SavedVariables key + text key.
local OPTIONS = {
    { key = "healersInCombat", text = "optHealersInCombat" },
    { key = "hideInCombat",    text = "optHideInCombat" },
    { key = "summary",         text = "optSummary" },
    { key = "showSelf",        text = "optShowSelf" },
    { key = "showUnknown",     text = "optShowUnknown" },
    { key = "specIcons",       text = "optSpecIcons" },
    { key = "locked",          text = "optLocked" },
}

local PRESETS = {
    { text = "optAll",     mode = "all" },
    { text = "optHealers", mode = "healers" },
    { text = "optNone",    mode = "none" },
}

local win
local labels = {}       -- { fontString, text key } for re-translation
local optionChecks = {} -- { checkButton, SavedVariables key }
local specChecks = {}   -- { checkButton, specID }
local classButtons = {} -- { button, classFile }

local function T(key)
    local texts = ns.GetL()
    return texts and texts[key] or key
end

local function ClassColor(classFile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
    c = CLASS_COLORS[classFile]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
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
    local classSpecs = ns.GetClassSpecs()
    local maxSpecs = 3
    for _, class in ipairs(classSpecs) do
        if #class.specs > maxSpecs then maxSpecs = #class.specs end
    end
    local width = PAD * 2 + CLASS_COL + maxSpecs * SPEC_COL

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

    -- Display options
    local y = -40
    local display = NewText(win, 12, 1, 0.82, 0)
    display:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
    Localize(display, "optDisplay")
    y = y - 18
    for _, opt in ipairs(OPTIONS) do
        local key = opt.key
        local cb = NewCheck(win, width - PAD * 2 - CHECK_SIZE - 4, function(self)
            ns.SetOption(key, self:GetChecked() and true or false)
        end)
        cb:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
        Localize(cb.label, opt.text)
        optionChecks[#optionChecks + 1] = { cb, key }
        y = y - ROW_H
    end

    -- Class / spec grid
    y = y - 10
    local specsTitle = NewText(win, 12, 1, 0.82, 0)
    specsTitle:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
    Localize(specsTitle, "optSpecs")
    y = y - 18
    for _, class in ipairs(classSpecs) do
        -- The class name toggles the whole row.
        local classFile = class.classFile
        local classButton = CreateFrame("Button", nil, win)
        classButton:SetSize(CLASS_COL - 6, CHECK_SIZE)
        classButton:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
        local className = NewText(classButton, 12, ClassColor(classFile))
        className:SetPoint("LEFT", classButton, "LEFT", 0, 0)
        className:SetWidth(CLASS_COL - 6)
        className:SetWordWrap(false)
        className:SetText(class.name)
        classButton.label = className
        classButton:SetScript("OnClick", function()
            ns.ToggleClass(classFile)
            ns.RefreshOptions()
        end)
        classButton:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(class.name)
            GameTooltip:AddLine(T("classTip"), 1, 1, 1)
            GameTooltip:Show()
        end)
        classButton:SetScript("OnLeave", function(self)
            if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        classButtons[#classButtons + 1] = { classButton, classFile }

        local labelWidth = SPEC_COL - CHECK_SIZE - 6
        for i, spec in ipairs(class.specs) do
            local specID = spec.id
            local cb = NewCheck(win, labelWidth, function(self)
                ns.SetSpecEnabled(specID, self:GetChecked() and true or false)
            end)
            cb:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + CLASS_COL + (i - 1) * SPEC_COL, y)
            if spec.icon then
                local icon = cb:CreateTexture(nil, "ARTWORK")
                icon:SetSize(ICON_SIZE, ICON_SIZE)
                icon:SetPoint("LEFT", cb, "RIGHT", 1, 0)
                icon:SetTexture(spec.icon)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                cb.icon = icon
                cb.label:ClearAllPoints()
                cb.label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
                cb.label:SetWidth(labelWidth - ICON_SIZE - 6)
            end
            cb.label:SetText(spec.name)
            specChecks[#specChecks + 1] = { cb, specID }
        end
        y = y - ROW_H
    end

    -- Presets
    y = y - 8
    local x = PAD
    for _, preset in ipairs(PRESETS) do
        local mode = preset.mode
        local b = NewButton(win, 120, 22, function()
            ns.SetAllSpecs(mode)
            ns.RefreshOptions()
        end)
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
        Localize(b.label, preset.text)
        x = x + 128
    end
    y = y - 32

    local hint = NewText(win, 10, 0.65, 0.65, 0.65)
    hint:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, y)
    hint:SetWidth(width - PAD * 2)
    hint:SetWordWrap(true)
    Localize(hint, "optHint")
    y = y - 48

    win:SetSize(width, -y)

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
    for _, entry in ipairs(specChecks) do
        entry[1]:SetChecked(ns.IsSpecEnabled(entry[2]) and true or false)
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
    return win, optionChecks, specChecks, classButtons
end
