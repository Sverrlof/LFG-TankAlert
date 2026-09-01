-- TankAlertOptions
-- A standalone settings window (open with /ta options) with two tabs:
-- Alerts, Ignore Rules. Reads/writes ns.db directly, so changes take effect
-- immediately.
--
-- Built entirely from flat custom widgets (ns.CreateFlatButton/CreateFlatPanel
-- from TankAlert.lua) rather than Blizzard's Button/DialogBox templates --
-- those get repainted by UI-skinning addons in ways that clash with each
-- other, which is what made earlier versions of this window look messy.

local ADDON_NAME, ns = ...

local PANEL_WIDTH = 392 -- full width of the content area
local INSET = 16        -- left padding every row is laid out from
-- Width available for anything that starts at x=INSET and should end with a
-- matching right-hand margin (divider lines, wrapped text) -- NOT PANEL_WIDTH
-- itself, which would run the full width starting from x=0 and overshoot
-- the right edge by INSET pixels once drawn starting at x=INSET.
local CONTENT_WIDTH = PANEL_WIDTH - (INSET * 2)

--------------------------------------------------------------------------
-- Small widget factories
--------------------------------------------------------------------------

local function CreateLabel(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

-- A thin gold rule with a small caps-style heading above it. Used to break
-- each tab up into clearly separated groups instead of one long flat list.
local function CreateSectionHeader(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(("|cffffd100%s|r"):format(text:upper()))

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 18)
    line:SetSize(width, 1)
    line:SetColorTexture(1, 0.82, 0, 0.3)

    return 30 -- vertical space consumed
end

local function CreateCheckbox(parent, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetSize(22, 22)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 6, 1)
    text:SetText(label)
    cb.text = text
    cb:SetChecked(get())
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    return cb
end

-- allowDecimal=true skips SetNumeric so values like "1.5" can be typed.
local function CreateNumberBox(parent, label, x, y, get, set, allowDecimal)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(64, 22)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 1, y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(7)
    if not allowDecimal then
        box:SetNumeric(true)
    end
    box:SetText(tostring(get() or 0))

    if label then
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 6)
        fs:SetText(label)
    end

    local function Commit()
        local n = tonumber(box:GetText())
        if not n or n < 0 then n = 0 end
        set(n)
        box:SetText(tostring(n))
        box:ClearFocus()
    end
    box:SetScript("OnEnterPressed", Commit)
    box:SetScript("OnEditFocusLost", Commit)
    return box
end

-- Modern (10.2.5+) ColorPickerFrame API, with a legacy fallback for older
-- clients still running this addon.
local function OpenColorPicker(r, g, b, onColorChanged)
    -- Captured directly instead of trusting ColorPickerFrame:GetPreviousValues()
    -- to hand back a particular shape -- it turned out to return several
    -- separate values, not the table our first attempt assumed.
    local startR, startG, startB = r, g, b

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                onColorChanged(nr, ng, nb)
            end,
            cancelFunc = function()
                onColorChanged(startR, startG, startB)
            end,
        })
    else
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame.func = function()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            onColorChanged(nr, ng, nb)
        end
        ColorPickerFrame.cancelFunc = function()
            onColorChanged(startR, startG, startB)
        end
        ShowUIPanel(ColorPickerFrame)
    end
end

local function CreateColorSwatch(parent, x, y, getRGB, setRGB)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(26, 26)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    ns.ApplyFlatBackdrop(btn, 1)
    btn:SetBackdropBorderColor(unpack(ns.PALETTE.buttonBorder))

    local function Refresh()
        local r, g, b = getRGB()
        btn:SetBackdropColor(r, g, b, 1)
    end
    Refresh()

    btn:SetScript("OnClick", function()
        local r, g, b = getRGB()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            setRGB(nr, ng, nb)
            Refresh()
        end)
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(ns.PALETTE.accent))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click to change color")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(ns.PALETTE.buttonBorder))
        GameTooltip_Hide()
    end)

    return btn
end

--------------------------------------------------------------------------
-- Panels
--------------------------------------------------------------------------

local function BuildAlertsPanel(panel)
    local db = ns.db
    local x, y = 16, -16

    y = y - CreateSectionHeader(panel, "Screen Flash", x, y, CONTENT_WIDTH)

    CreateCheckbox(panel, "Enable screen flash", x, y,
        function() return db.flashEnabled end,
        function(v) db.flashEnabled = v end)
    y = y - 42 -- extra clearance: the Duration number box's caption sits above its box

    CreateLabel(panel, "Flash color", x, y + 4)
    CreateColorSwatch(panel, x + 96, y - 2,
        function() return db.flashColor.r, db.flashColor.g, db.flashColor.b end,
        function(r, g, b) db.flashColor.r, db.flashColor.g, db.flashColor.b = r, g, b end)
    CreateNumberBox(panel, "Duration (sec)", x + 156, y,
        function() return db.flashDuration end,
        function(v) db.flashDuration = v end)
    y = y - 54

    y = y - CreateSectionHeader(panel, "Sound", x, y, CONTENT_WIDTH)

    local soundDropdown = ns.CreateFlatDropdown(panel, 220, 26, ns.SOUND_CHOICES,
        function() return db.sound end,
        function(key) db.sound = key end)
    soundDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)

    local previewBtn = ns.CreateFlatButton(panel, "Preview", 100, 26)
    previewBtn:SetPoint("LEFT", soundDropdown, "RIGHT", 8, 0)
    previewBtn:SetScript("OnClick", function()
        if ns.PlayAlertSoundOnce then ns.PlayAlertSoundOnce(db.sound) end
    end)

    y = y - 54 -- extra clearance below the 26px-tall dropdown for the
               -- Repeat/Interval captions above their boxes

    CreateNumberBox(panel, "Repeat count", x, y,
        function() return db.soundRepeat end,
        function(v) db.soundRepeat = math.max(1, v) end)
    CreateNumberBox(panel, "Interval (sec)", x + 120, y,
        function() return db.soundInterval end,
        function(v) db.soundInterval = v end, true)
    y = y - 56

    y = y - CreateSectionHeader(panel, "Notifications", x, y, CONTENT_WIDTH)

    CreateCheckbox(panel, "Chat announcements", x, y,
        function() return db.chatAnnounce end,
        function(v) db.chatAnnounce = v end)
    y = y - 30

    CreateCheckbox(panel, "Invite/Decline popup", x, y,
        function() return db.popupEnabled end,
        function(v)
            db.popupEnabled = v
            if ns.UpdatePopup then ns.UpdatePopup() end
        end)
    y = y - 30

    CreateCheckbox(panel, "Show Raider.IO score in popup (if installed)", x, y,
        function() return db.showRaiderIO end,
        function(v)
            db.showRaiderIO = v
            if ns.UpdatePopup then ns.UpdatePopup() end
        end)
    y = y - 30

    CreateCheckbox(panel, "Only alert when I can invite (raid leader/assist)", x, y,
        function() return db.requireInvitePermission end,
        function(v) db.requireInvitePermission = v end)
    y = y - 46

    local testBtn = ns.CreateFlatButton(panel, "Test Alert", 140, 26)
    testBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    testBtn.label:SetTextColor(unpack(ns.PALETTE.accent))
    testBtn:SetBackdropBorderColor(unpack(ns.PALETTE.accent))
    testBtn:SetScript("OnClick", function()
        if ns.RunTestAlert then ns.RunTestAlert() end
    end)
    y = y - 36

    return -y + 14
end

local function BuildIgnorePanel(panel)
    local db = ns.db
    local x, y = 16, -16
    local rule = db.ignoreRule

    y = y - CreateSectionHeader(panel, "Ignore Low Tanks", x, y, CONTENT_WIDTH)

    CreateCheckbox(panel, "Enable ignore rule", x, y,
        function() return rule.enabled end,
        function(v) rule.enabled = v end)
    y = y - 22

    local note = CreateLabel(panel,
        "|cff9d9d9dA tank is ignored (no flash, sound, chat, or popup) if their ilvl is below the minimum OR their M+ score is below the minimum. Leave a value at 0 to skip that check.|r",
        x, y, "GameFontDisableSmall")
    note:SetWidth(CONTENT_WIDTH)
    y = y - 62 -- this note reliably wraps to 3 lines at this width

    CreateNumberBox(panel, "Min ilvl", x, y,
        function() return rule.minIlvl end,
        function(v) rule.minIlvl = v end)
    CreateNumberBox(panel, "Min M+ score", x + 120, y,
        function() return rule.minRating end,
        function(v) rule.minRating = v end)
    y = y - 50

    local warn = CreateLabel(panel,
        "|cffff8800Careful: setting these too high can hide legitimate tanks who just haven't pushed keys yet this season.|r",
        x, y, "GameFontDisableSmall")
    warn:SetWidth(CONTENT_WIDTH)
    y = y - 44 -- this warning also usually wraps to two lines

    return -y + 14
end

--------------------------------------------------------------------------
-- Frame shell with tabs
--------------------------------------------------------------------------

local optionsFrame

local CHROME_TOP = 92     -- title + tab row + top content padding
local CHROME_BOTTOM = 22
local MIN_HEIGHT = 260
local MAX_HEIGHT = 620

local function CreateOptionsFrame()
    local f = ns.CreateFlatPanel(UIParent, { edgeSize = 1 })
    f:SetSize(430, 470)
    f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    -- CreateFlatPanel makes an unnamed frame, but UISpecialFrames (which
    -- makes Escape close this window) looks the frame up by a global name,
    -- so register one manually.
    _G.TankAlertOptionsFrame = f
    tinsert(UISpecialFrames, "TankAlertOptionsFrame")

    -- thin gold top accent strip
    local accentBar = f:CreateTexture(nil, "ARTWORK")
    accentBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    accentBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    accentBar:SetHeight(2)
    accentBar:SetColorTexture(unpack(ns.PALETTE.accent))

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    icon:SetTexture("Interface\\Icons\\Ability_Warrior_DefensiveStance")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("|cffffd100LFG TankAlert Settings|r")

    local closeBtn = ns.CreateFlatButton(f, "X", 24, 24)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local tabNames = { "Alerts", "Ignore Rules" }
    local panelBuilders = { BuildAlertsPanel, BuildIgnorePanel }
    local tabButtons, panelFrames, panelHeights = {}, {}, {}

    local tabGap = 6
    local tabWidth = (PANEL_WIDTH - (tabGap * (#tabNames - 1))) / #tabNames
    for i, name in ipairs(tabNames) do
        local btn = ns.CreateFlatButton(f, name, tabWidth, 26)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 19 + (i - 1) * (tabWidth + tabGap), -50)
        tabButtons[i] = btn
    end

    local content = ns.CreateFlatPanel(f, {
        bg = { 0.02, 0.02, 0.025, 0.6 },
        border = { 1, 0.82, 0, 0.18 },
        edgeSize = 1,
    })
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 19, -84)
    content:SetPoint("TOPRIGHT", f, "TOPRIGHT", -19, -84)

    for i = 1, #tabNames do
        local panel = CreateFrame("Frame", nil, content)
        panel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        panel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
        panelHeights[i] = panelBuilders[i](panel)
        panel:SetHeight(panelHeights[i])
        panelFrames[i] = panel
        panel:Hide()
    end

    local function SelectTab(i)
        for j, btn in ipairs(tabButtons) do
            ns.SetFlatButtonActive(btn, j == i)
            panelFrames[j]:SetShown(j == i)
        end

        local h = panelHeights[i] or MIN_HEIGHT
        content:SetHeight(h)

        local frameHeight = h + CHROME_TOP + CHROME_BOTTOM
        if frameHeight < MIN_HEIGHT then frameHeight = MIN_HEIGHT end
        if frameHeight > MAX_HEIGHT then frameHeight = MAX_HEIGHT end
        f:SetHeight(frameHeight)
    end

    for i, btn in ipairs(tabButtons) do
        btn:SetScript("OnClick", function() SelectTab(i) end)
    end

    SelectTab(1)

    optionsFrame = f
    return f
end

function ns.ToggleOptions()
    if not ns.db then
        print("|cffffd100LFG TankAlert|r is still loading, try again in a moment.")
        return
    end
    local f = optionsFrame or CreateOptionsFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end
