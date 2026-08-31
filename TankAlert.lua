-- TankAlert
-- Watches your active Premade Groups (LFG list) listing and alerts you the
-- moment an applicant who can tank shows up, so you don't need to keep the
-- Group Finder window open. An optional ignore rule can suppress the alert
-- entirely for tanks below a minimum item level or Mythic+ score, so you're
-- not interrupted for undergeared applicants.

local ADDON_NAME, ns = ...

--------------------------------------------------------------------------
-- Saved settings
--------------------------------------------------------------------------

local DEFAULTS = {
    -- alerts
    sound = "RAID_WARNING",   -- "RAID_WARNING", "READY_CHECK" or "NONE"
    soundRepeat = 3,
    soundInterval = 1.6,
    flashEnabled = true,
    flashDuration = 8,
    flashColor = { r = 1, g = 0.82, b = 0 },
    flashAlpha = 0.35,
    chatAnnounce = true,
    popupEnabled = true,
    showRaiderIO = true, -- shows Raider.IO score/best-run info in the popup when that addon is installed

    -- A tank applicant is ignored (no flash/sound/popup/chat) if EITHER
    -- threshold is set (> 0) and they fail it. Leaving both at 0 disables
    -- the rule entirely regardless of `enabled`.
    ignoreRule = {
        enabled = false,
        minIlvl = 0,
        minRating = 0,
    },
}

-- Recursively fills in any keys missing from a saved table (including nested
-- tables), so upgrading from an older TankAlertDB doesn't crash on nil fields.
local function ApplyDefaults(dst, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local db -- set on ADDON_LOADED; also published as ns.db

--------------------------------------------------------------------------
-- Shared flat-panel UI helpers (used by this file's popup and by
-- TankAlertOptions.lua). Deliberately NOT built from Blizzard's Button/
-- DialogBox templates: those get repainted by UI-skinning addons (ElvUI and
-- similar) in ways that clash with each other, which is what made the
-- window look inconsistent. Plain custom textures render exactly as drawn.
--------------------------------------------------------------------------

local PALETTE = {
    panelBg = { 0.045, 0.045, 0.05, 0.97 },
    panelBorder = { 0.22, 0.22, 0.25, 1 },
    fieldBorder = { 0.24, 0.24, 0.27, 1 },
    buttonBg = { 0.11, 0.11, 0.13, 1 },
    buttonBgHover = { 0.16, 0.16, 0.19, 1 },
    buttonBorder = { 0.27, 0.27, 0.30, 1 },
    accent = { 1, 0.82, 0 },
    accentBg = { 0.20, 0.16, 0.03, 1 },
    text = { 0.90, 0.90, 0.90 },
    textDim = { 0.6, 0.6, 0.63 },
}
ns.PALETTE = PALETTE

local function ApplyFlatBackdrop(frame, edgeSize)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edgeSize or 1,
    })
end
ns.ApplyFlatBackdrop = ApplyFlatBackdrop

local function CreateFlatPanel(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ApplyFlatBackdrop(f, opts.edgeSize or 1)
    f:SetBackdropColor(unpack(opts.bg or PALETTE.panelBg))
    f:SetBackdropBorderColor(unpack(opts.border or PALETTE.panelBorder))
    return f
end
ns.CreateFlatPanel = CreateFlatPanel

-- A plain flat button: dark fill, thin border, centered label. Hover
-- lightens the fill slightly unless the button is marked .active.
local function CreateFlatButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    ApplyFlatBackdrop(btn, 1)
    btn:SetBackdropColor(unpack(PALETTE.buttonBg))
    btn:SetBackdropBorderColor(unpack(PALETTE.buttonBorder))

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(unpack(PALETTE.text))
    btn.label = label
    btn.active = false

    btn:SetScript("OnEnter", function(self)
        if not self.active then
            self:SetBackdropColor(unpack(PALETTE.buttonBgHover))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.active then
            self:SetBackdropColor(unpack(PALETTE.buttonBg))
        end
    end)

    return btn
end
ns.CreateFlatButton = CreateFlatButton

-- Toggles the gold "selected" look used for tabs and choice chips.
local function SetFlatButtonActive(btn, active)
    btn.active = active
    if active then
        btn:SetBackdropColor(unpack(PALETTE.accentBg))
        btn:SetBackdropBorderColor(unpack(PALETTE.accent))
        btn.label:SetTextColor(unpack(PALETTE.accent))
    else
        btn:SetBackdropColor(unpack(PALETTE.buttonBg))
        btn:SetBackdropBorderColor(unpack(PALETTE.buttonBorder))
        btn.label:SetTextColor(unpack(PALETTE.text))
    end
end
ns.SetFlatButtonActive = SetFlatButtonActive

-- Permanently recolors a flat button (used for the popup's green Invite /
-- red Decline buttons) instead of the default hover behavior.
local function TintFlatButton(btn, bg, hoverBg, border, textColor)
    btn.active = true -- stop the default OnEnter/OnLeave from overwriting this
    btn:SetBackdropColor(unpack(bg))
    btn:SetBackdropBorderColor(unpack(border))
    btn.label:SetTextColor(unpack(textColor))
    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(hoverBg)) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(bg)) end)
end
ns.TintFlatButton = TintFlatButton

-- A minimal dropdown: a flat button showing the current choice, opening a
-- floating list of flat rows on click. `choices` is { {key, label}, ... };
-- getKey/setKey read and write the selection. Built from scratch (rather
-- than Blizzard's UIDropDownMenu) for the same reason as the other flat
-- widgets -- consistent look regardless of any UI-skinning addon, and no
-- dependency on a semi-documented Blizzard API surface.
local function CreateFlatDropdown(parent, width, height, choices, getKey, setKey, onChange)
    local dropdown = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dropdown:SetSize(width, height)
    ApplyFlatBackdrop(dropdown, 1)
    dropdown:SetBackdropColor(unpack(PALETTE.buttonBg))
    dropdown:SetBackdropBorderColor(unpack(PALETTE.buttonBorder))

    local label = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", dropdown, "LEFT", 10, 0)
    label:SetPoint("RIGHT", dropdown, "RIGHT", -22, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(unpack(PALETTE.text))
    dropdown.label = label

    local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    arrow:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
    arrow:SetText("v")
    arrow:SetTextColor(unpack(PALETTE.textDim))

    local function RefreshLabel()
        local key = getKey()
        for _, choice in ipairs(choices) do
            if choice.key == key then
                label:SetText(choice.label)
                return
            end
        end
        label:SetText(key or "")
    end
    RefreshLabel()
    dropdown.RefreshLabel = RefreshLabel

    local listFrame, catcher

    local function CloseList()
        if listFrame then listFrame:Hide() end
        if catcher then catcher:Hide() end
        arrow:SetText("v")
    end

    local function OpenList()
        if not listFrame then
            -- Full-screen invisible button behind the list so clicking
            -- anywhere outside it closes the dropdown.
            catcher = CreateFrame("Button", nil, UIParent)
            catcher:SetAllPoints(UIParent)
            catcher:SetFrameStrata("TOOLTIP")
            catcher:SetFrameLevel(1)
            catcher:Hide()
            catcher:SetScript("OnClick", CloseList)

            listFrame = CreateFlatPanel(UIParent, { edgeSize = 1, border = PALETTE.accent })
            listFrame:SetFrameStrata("TOOLTIP")
            listFrame:SetFrameLevel(2)
            listFrame:SetWidth(width)

            local rowHeight = 22
            local y = -4
            for _, choice in ipairs(choices) do
                local row = CreateFrame("Button", nil, listFrame)
                row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, y)
                row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, y)
                row:SetHeight(rowHeight)

                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(row)
                hl:SetColorTexture(1, 0.82, 0, 0.15)

                local rowLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                rowLabel:SetPoint("LEFT", row, "LEFT", 8, 0)
                rowLabel:SetText(choice.label)
                rowLabel:SetTextColor(unpack(PALETTE.text))

                row:SetScript("OnClick", function()
                    setKey(choice.key)
                    RefreshLabel()
                    CloseList()
                    if onChange then onChange(choice.key) end
                end)

                y = y - rowHeight
            end
            listFrame:SetHeight(-y + 4)
        end

        listFrame:ClearAllPoints()
        listFrame:SetPoint("TOP", dropdown, "BOTTOM", 0, -2)
        catcher:Show()
        listFrame:Show()
        arrow:SetText("^")
    end

    dropdown:SetScript("OnClick", function()
        if listFrame and listFrame:IsShown() then
            CloseList()
        else
            OpenList()
        end
    end)
    dropdown:SetScript("OnHide", CloseList)

    dropdown:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(PALETTE.accent)) end)
    dropdown:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(PALETTE.buttonBorder)) end)

    return dropdown
end
ns.CreateFlatDropdown = CreateFlatDropdown

--------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------

-- All keys verified against BlizzardInterfaceResources/SoundKit.lua and
-- cross-checked by numeric ID on Wowhead (RAID_WARNING=8959, READY_CHECK=8960)
-- before shipping, since a mistyped SOUNDKIT field just silently fails to
-- play rather than erroring.
local SOUND_CHOICES = {
    { key = "RAID_WARNING", label = "Raid Warning", kit = SOUNDKIT and SOUNDKIT.RAID_WARNING },
    { key = "READY_CHECK", label = "Ready Check", kit = SOUNDKIT and SOUNDKIT.READY_CHECK },
    { key = "ALARM_1", label = "Alarm Clock 1", kit = SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_1 },
    { key = "ALARM_2", label = "Alarm Clock 2", kit = SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_2 },
    { key = "ALARM_3", label = "Alarm Clock 3", kit = SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 },
    { key = "NONE", label = "None", kit = false },
}
ns.SOUND_CHOICES = SOUND_CHOICES

local SOUND_PRESETS = {}
for _, choice in ipairs(SOUND_CHOICES) do
    SOUND_PRESETS[choice.key] = choice.kit
end

-- soundKey defaults to db.sound; passing one explicitly lets the options
-- window preview any choice without changing the saved setting.
local function PlayAlertSoundOnce(soundKey)
    soundKey = soundKey or db.sound
    if soundKey == "NONE" then return end
    local kit = SOUND_PRESETS[soundKey]
    if kit then
        pcall(PlaySound, kit, "Master")
    end
end
ns.PlayAlertSoundOnce = PlayAlertSoundOnce

-- Plays the alert sound db.soundRepeat times, db.soundInterval apart. If a
-- newer alert starts in the meantime, the older loop's remaining plays are
-- skipped so sounds from back-to-back applicants don't pile up.
local soundGeneration = 0
local function PlayAlertSoundLoop()
    soundGeneration = soundGeneration + 1
    local myGen = soundGeneration
    local count = db.soundRepeat or 1
    for i = 1, count do
        C_Timer.After((i - 1) * (db.soundInterval or 1.5), function()
            if myGen == soundGeneration then
                PlayAlertSoundOnce()
            end
        end)
    end
end

--------------------------------------------------------------------------
-- Screen flash
--------------------------------------------------------------------------

local flashFrame
local function CreateFlashFrame()
    if flashFrame then return flashFrame end

    local f = CreateFrame("Frame", "TankAlertFlashFrame", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:Hide()
    f:EnableMouse(true)

    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(f)
    tex:SetColorTexture(1, 0.82, 0, 1)
    tex:SetAlpha(0)
    f.tex = tex

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 120)
    hint:SetText("|cffffd100Tank applied!|r  (click to dismiss)")
    f.hint = hint

    local ag = tex:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0)
    a1:SetToAlpha(0.35)
    a1:SetDuration(0.5)
    a1:SetSmoothing("IN_OUT")
    f.anim = ag
    f.animAlpha = a1

    f:SetScript("OnMouseDown", function(self)
        self:Hide()
    end)

    flashFrame = f
    return f
end

local flashHideTimer
local function ShowFlash()
    if not db.flashEnabled then return end
    local f = CreateFlashFrame()

    local c = db.flashColor
    f.tex:SetColorTexture(c.r, c.g, c.b, 1)
    f.animAlpha:SetToAlpha(db.flashAlpha or 0.35)

    f:Show()
    f.anim:Play()
    if flashHideTimer then
        flashHideTimer:Cancel()
    end
    flashHideTimer = C_Timer.NewTimer(db.flashDuration or 8, function()
        if f.anim:IsPlaying() then f.anim:Stop() end
        f.tex:SetAlpha(0)
        f:Hide()
    end)
end

local function HideFlash()
    if not flashFrame then return end
    if flashHideTimer then
        flashHideTimer:Cancel()
        flashHideTimer = nil
    end
    if flashFrame.anim:IsPlaying() then flashFrame.anim:Stop() end
    flashFrame.tex:SetAlpha(0)
    flashFrame:Hide()
end

--------------------------------------------------------------------------
-- Applicant inspection helpers
--
-- NOTE on field order: C_LFGList.GetApplicantMemberInfo returns
--   name, class, localizedClass, level, itemLevel, honorLevel,
--   tank, healer, damage, assignedRole, relationship, dungeonScore, ...
-- `class` (2nd) is the English token used by RAID_CLASS_COLORS (e.g.
-- "WARRIOR"); `localizedClass` (3rd) is the translated display name.
-- C_LFGList.GetApplicantInfo returns
--   applicantID, applicationStatus, pendingApplicationStatus, numMembers,
--   isNew, comment, displayOrderID
--------------------------------------------------------------------------

local function ClassColoredName(name, classFileName)
    local color = classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName]
    if color then
        return color:WrapTextInColorCode(name or UNKNOWN)
    end
    return name or UNKNOWN
end

-- Returns nil if no member of this applicant offers to tank; otherwise the
-- display/ignore-rule info for whichever tanking member has the higher
-- item level (matters for premade duo/trio applications).
local function GetTankInfo(applicantID, numMembers)
    local best
    for i = 1, (numMembers or 1) do
        local name, classFileName, _localizedClass, level, itemLevel, _honorLevel,
              tank, _healer, _damage, _assignedRole, _relationship, dungeonScore =
            C_LFGList.GetApplicantMemberInfo(applicantID, i)
        if tank then
            itemLevel = itemLevel or 0
            dungeonScore = dungeonScore or 0
            if not best or itemLevel > best.itemLevel then
                best = {
                    name = name or UNKNOWN,
                    classFileName = classFileName,
                    itemLevel = itemLevel,
                    level = level,
                    rating = dungeonScore,
                }
            end
        end
    end
    return best
end

-- As of the current API, C_LFGList.GetApplicantInfo(applicantID) returns a
-- single struct/table (named fields like .applicationStatus, .numMembers)
-- rather than several separate values. This reads it either way, so it
-- keeps working if that ever reverts or differs on some client.
local function GetApplicantStatusInfo(applicantID)
    local first = C_LFGList.GetApplicantInfo(applicantID)
    if type(first) == "table" then
        return first.applicationStatus, first.numMembers, first.isNew
    end
    local _appID, applicationStatus, _pendingStatus, numMembers, isNew = C_LFGList.GetApplicantInfo(applicantID)
    return applicationStatus, numMembers, isNew
end

-- Doesn't trust numMembers at all (in case it's ever missing/renamed too) --
-- counts by probing GetApplicantMemberInfo directly, which we've confirmed
-- still returns real data. Groups top out at 5 members.
local function CountApplicantMembers(applicantID, hint)
    local n = tonumber(hint)
    if n and n >= 1 then return n end
    for i = 1, 5 do
        local name = C_LFGList.GetApplicantMemberInfo(applicantID, i)
        if not name then
            return math.max(i - 1, 1)
        end
    end
    return 5
end

--------------------------------------------------------------------------
-- Raider.IO integration (optional -- only produces anything if the player
-- also has the Raider.IO addon installed, and only for applicants Raider.IO
-- actually has cached, which is a periodically-refreshed snapshot, not
-- live data). Blizzard's own API never exposes another player's best runs
-- or previous-season score at all, so this is the only way to surface it.
--------------------------------------------------------------------------

-- C_LFGList.GetActiveEntryInfo() may return either a single struct/table or
-- several positional values, same situation as GetApplicantInfo -- handled
-- both ways here rather than guessed at.
local function GetCurrentActivityIDSet()
    if not C_LFGList.HasActiveEntryInfo() then return nil end
    local ok, first = pcall(C_LFGList.GetActiveEntryInfo)
    if not ok or not first then return nil end

    local activityIDs
    if type(first) == "table" then
        activityIDs = first.activityIDs
    else
        local _name, _comment, _voiceChat, _ilvl, _honorLevel, ids = C_LFGList.GetActiveEntryInfo()
        activityIDs = ids
    end
    if not activityIDs then return nil end

    local set = {}
    for _, id in ipairs(activityIDs) do
        set[id] = true
    end
    return set
end

-- Returns nil if Raider.IO isn't installed or has no data for this
-- applicant, otherwise a table:
--   { currentScore, previousScore, previousScoreSeason, bestRun, thisDungeonBestRun }
-- bestRun / thisDungeonBestRun (when present) are each
--   { level, chests, dungeonName, dungeonShortName }
-- chests is 0-3, i.e. the number of "+"s the key was upgraded by (0 means
-- completed over time / untimed). thisDungeonBestRun is only filled in when
-- activityIDSet is given and a matching entry is found via the dungeon's
-- lfd_activity_ids.
local function GetRaiderIOSummary(applicantName, activityIDSet)
    if not db.showRaiderIO then return nil end
    if type(RaiderIO) ~= "table" or type(RaiderIO.GetProfile) ~= "function" then
        return nil -- addon not installed
    end
    if not applicantName or applicantName == "" then return nil end

    local shortName, realm = applicantName:match("^(.-)%-(.+)$")
    if not shortName then
        shortName = applicantName
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    end

    local ok, profile = pcall(RaiderIO.GetProfile, shortName, realm)
    if not ok or not profile then return nil end

    local mkp = profile.mythicKeystoneProfile
    if not mkp then return nil end

    local summary = {
        currentScore = mkp.currentScore,
        previousScore = mkp.previousScore,
        previousScoreSeason = mkp.previousScoreSeason,
    }

    if type(mkp.sortedDungeons) == "table" then
        for _, entry in ipairs(mkp.sortedDungeons) do
            local level = entry.level
            if level then
                local dungeon = entry.dungeon
                if not summary.bestRun or level > summary.bestRun.level then
                    summary.bestRun = {
                        level = level,
                        chests = entry.chests,
                        dungeonName = dungeon and dungeon.name,
                        dungeonShortName = dungeon and dungeon.shortName,
                    }
                end
                if activityIDSet and dungeon and type(dungeon.lfd_activity_ids) == "table" then
                    for _, id in ipairs(dungeon.lfd_activity_ids) do
                        if activityIDSet[id] then
                            if not summary.thisDungeonBestRun or level > summary.thisDungeonBestRun.level then
                                summary.thisDungeonBestRun = { level = level, chests = entry.chests }
                            end
                        end
                    end
                end
            end
        end
    end

    if not (summary.currentScore or summary.bestRun) then
        return nil -- Raider.IO returned a profile shell with nothing usable
    end
    return summary
end

--------------------------------------------------------------------------
-- Ignore rule
--------------------------------------------------------------------------

-- true if this tank should be skipped entirely (no flash/sound/popup/chat):
-- the rule is enabled AND either threshold is set (> 0) and they fail it.
local function IsTankIgnored(ilvl, rating)
    local rule = db.ignoreRule
    if not rule.enabled then return false end
    local minIlvl = rule.minIlvl or 0
    local minRating = rule.minRating or 0
    if minIlvl <= 0 and minRating <= 0 then return false end
    local failsIlvl = minIlvl > 0 and (ilvl or 0) < minIlvl
    local failsRating = minRating > 0 and (rating or 0) < minRating
    return failsIlvl or failsRating
end

--------------------------------------------------------------------------
-- Popup (Invite / Decline / Dismiss)
--------------------------------------------------------------------------

local pendingTanks = {}     -- applicantID -> { name, classFileName, itemLevel, level, rating }
local notifiedIDs = {}      -- applicantID -> true (already alerted once)
local popupManuallyHidden = false

local alertPopup -- forward decl
local CreatePopup

local function UpdatePopup()
    if not db.popupEnabled then
        if alertPopup then alertPopup:Hide() end
        return
    end

    local count = 0
    local firstID, firstInfo
    for id, info in pairs(pendingTanks) do
        count = count + 1
        if not firstID then
            firstID, firstInfo = id, info
        end
    end

    if count == 0 or popupManuallyHidden then
        if alertPopup then alertPopup:Hide() end
        return
    end

    local popup = alertPopup or CreatePopup()
    popup.applicantID = firstID

    local nameText = ClassColoredName(firstInfo.name, firstInfo.classFileName)
    local ilvlText = firstInfo.itemLevel and (" |cff9d9d9d(ilvl %d)|r"):format(firstInfo.itemLevel) or ""
    popup.body:SetText(nameText .. ilvlText)

    -- Stacks each optional line directly under the last one actually shown,
    -- instead of anchoring every line to a fixed slot -- otherwise a hidden
    -- line (no Raider.IO data, etc.) would leave a dead gap where it used
    -- to be.
    local anchor = popup.body
    local function PlaceIfShown(fs, shouldShow, text)
        if shouldShow then
            fs:SetText(text)
            fs:ClearAllPoints()
            fs:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
            fs:Show()
            anchor = fs
        else
            fs:Hide()
        end
    end

    local rio = GetRaiderIOSummary(firstInfo.name, GetCurrentActivityIDSet())
    if rio then
        local scoreText = rio.currentScore and ("Score: |cffffd100%d|r"):format(rio.currentScore) or nil
        if rio.previousScore then
            local seasonTag = rio.previousScoreSeason and (" (S%d)"):format(rio.previousScoreSeason) or " (prev)"
            scoreText = (scoreText or "Score: |cff9d9d9d?|r")
                .. ("  |cff9d9d9dwas %d%s|r"):format(rio.previousScore, seasonTag)
        end
        PlaceIfShown(popup.rio1, scoreText ~= nil, scoreText or "")

        -- chests (0-3) is how many "+"s the key was upgraded by (0 = timed
        -- over / untimed) -- all shown left of the level, e.g. "++18".
        local function FormatKeyLevel(run)
            return ("%s%d"):format(("+"):rep(run.chests or 0), run.level)
        end

        local runText
        if rio.bestRun then
            local dungeonLabel = rio.bestRun.dungeonShortName or rio.bestRun.dungeonName
            runText = ("Best key: |cffffd100%s|r"):format(FormatKeyLevel(rio.bestRun))
            if dungeonLabel then
                runText = runText .. (" |cff9d9d9d%s|r"):format(dungeonLabel)
            end
            if rio.thisDungeonBestRun then
                runText = runText .. ("   This: |cffffd100%s|r"):format(FormatKeyLevel(rio.thisDungeonBestRun))
            end
        end
        PlaceIfShown(popup.rio2, runText ~= nil, runText or "")
    else
        PlaceIfShown(popup.rio1, false)
        PlaceIfShown(popup.rio2, false)
    end

    PlaceIfShown(popup.extra, count > 1, ("+%d more tank(s) waiting"):format(count - 1))

    popup:Show()
end

CreatePopup = function()
    local f = CreateFlatPanel(UIParent, { edgeSize = 1 })
    f:SetSize(320, 192)
    f:SetPoint("TOP", UIParent, "TOP", 0, -200)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- thin gold top accent strip, consistent with the settings window
    local accentBar = f:CreateTexture(nil, "ARTWORK")
    accentBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    accentBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    accentBar:SetHeight(2)
    accentBar:SetColorTexture(unpack(PALETTE.accent))

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -18)
    title:SetText("|cffffd100Tank Available|r")

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOP", title, "BOTTOM", 0, -10)
    f.body = body

    -- rio1/rio2 (Raider.IO score/best-run) and extra ("+N more") all get
    -- repositioned dynamically in UpdatePopup via PlaceIfShown -- these
    -- initial anchors are just a safe default before the first update.
    local rio1 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rio1:SetPoint("TOP", body, "BOTTOM", 0, -6)
    rio1:Hide()
    f.rio1 = rio1

    local rio2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rio2:SetPoint("TOP", body, "BOTTOM", 0, -6)
    rio2:Hide()
    f.rio2 = rio2

    local extra = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    extra:SetPoint("TOP", body, "BOTTOM", 0, -6)
    f.extra = extra

    local inviteBtn = CreateFlatButton(f, "Invite", 90, 24)
    inviteBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
    TintFlatButton(inviteBtn,
        { 0.06, 0.20, 0.09, 1 }, { 0.09, 0.27, 0.13, 1 },
        { 0.30, 0.75, 0.38, 1 }, { 0.62, 1, 0.68 })
    inviteBtn:SetScript("OnClick", function()
        if f.applicantID then
            C_LFGList.InviteApplicant(f.applicantID)
        end
    end)

    local declineBtn = CreateFlatButton(f, "Decline", 90, 24)
    declineBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    TintFlatButton(declineBtn,
        { 0.22, 0.06, 0.06, 1 }, { 0.30, 0.09, 0.09, 1 },
        { 0.78, 0.32, 0.32, 1 }, { 1, 0.6, 0.6 })
    declineBtn:SetScript("OnClick", function()
        if f.applicantID then
            C_LFGList.DeclineApplicant(f.applicantID)
        end
    end)

    local dismissBtn = CreateFlatButton(f, "Dismiss", 90, 24)
    dismissBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    dismissBtn:SetScript("OnClick", function()
        popupManuallyHidden = true
        f:Hide()
    end)

    alertPopup = f
    return f
end

--------------------------------------------------------------------------
-- Core refresh logic
--------------------------------------------------------------------------

local function Announce(info)
    if db.chatAnnounce then
        local msg = ("|cff33ff99[LFG TankAlert]|r %s just applied to your group%s."):format(
            ClassColoredName(info.name, info.classFileName),
            info.itemLevel and (" (ilvl " .. info.itemLevel .. ")") or ""
        )
        print(msg)
    end
    ShowFlash()
    PlayAlertSoundLoop()
end

local function RefreshApplicants()
    if not C_LFGList.HasActiveEntryInfo() then
        wipe(pendingTanks)
        wipe(notifiedIDs)
        popupManuallyHidden = false
        UpdatePopup()
        HideFlash()
        return
    end

    local ids = C_LFGList.GetApplicants()
    local currentSet = {}

    if ids then
        for _, id in ipairs(ids) do
            currentSet[id] = true
            local applicationStatus, rawNumMembers = GetApplicantStatusInfo(id)
            local numMembers = CountApplicantMembers(id, rawNumMembers)

            -- If the status field is ever unreadable (nil) treat the
            -- applicant as still pending rather than silently ignoring them --
            -- our notifiedIDs bookkeeping already prevents re-announcing, so
            -- it's safer to err toward alerting.
            if applicationStatus == "applied" or applicationStatus == nil then
                local tankInfo = GetTankInfo(id, numMembers)

                if tankInfo and not IsTankIgnored(tankInfo.itemLevel, tankInfo.rating) then
                    local isNewApplicant = not pendingTanks[id]
                    pendingTanks[id] = tankInfo
                    if not notifiedIDs[id] then
                        notifiedIDs[id] = true
                        popupManuallyHidden = false
                        Announce(tankInfo)
                    elseif isNewApplicant then
                        popupManuallyHidden = false
                    end
                else
                    pendingTanks[id] = nil
                end
            else
                -- invited / declined / failed / cancelled -> no longer pending
                pendingTanks[id] = nil
            end
        end
    end

    -- drop anything that disappeared from the applicant list entirely
    for id in pairs(pendingTanks) do
        if not currentSet[id] then pendingTanks[id] = nil end
    end
    for id in pairs(notifiedIDs) do
        if not currentSet[id] then notifiedIDs[id] = nil end
    end

    UpdatePopup()
end

--------------------------------------------------------------------------
-- Shared namespace exports (used by TankAlertOptions.lua)
--------------------------------------------------------------------------

ns.UpdatePopup = UpdatePopup
ns.HideFlash = HideFlash
ns.RunTestAlert = function()
    popupManuallyHidden = false
    local fakeID = -1
    pendingTanks[fakeID] = { name = "Testerino", classFileName = "WARRIOR", itemLevel = 665, rating = 2000 }
    Announce(pendingTanks[fakeID])
    UpdatePopup()
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED")
eventFrame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED")
eventFrame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")

-- Wrapping every event-driven scan in pcall means a bug can never again fail
-- completely silently: if something breaks, you'll see a red chat line
-- instead of just... nothing. Paste that line back to get it fixed.
local function SafeRefreshApplicants()
    local ok, err = pcall(RefreshApplicants)
    if not ok then
        print("|cffff0000[LFG TankAlert] ERROR:|r " .. tostring(err) .. " (run /ta debug and share the output)")
    end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            TankAlertDB = ApplyDefaults(TankAlertDB or {}, DEFAULTS)
            db = TankAlertDB
            ns.db = db

            -- Falls back to the default if a saved sound choice was since
            -- removed from SOUND_CHOICES (e.g. a pruned option), so the
            -- dropdown never shows a stale, unlabeled selection.
            local soundStillValid = false
            for _, choice in ipairs(SOUND_CHOICES) do
                if choice.key == db.sound then
                    soundStillValid = true
                    break
                end
            end
            if not soundStillValid then
                db.sound = DEFAULTS.sound
            end
            print("|cff33ff99LFG TankAlert|r loaded. Type |cffffd100/ta options|r to configure, |cffffd100/ta test|r to preview.")
        end
        return
    end

    if not db then return end

    if event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        popupManuallyHidden = false
        SafeRefreshApplicants()
    elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED"
        or event == "LFG_LIST_APPLICANT_UPDATED" then
        SafeRefreshApplicants()
    end
end)

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

local function PrintHelp()
    print("|cffffd100LFG TankAlert|r commands:")
    print("  /ta options     - open the settings window (alerts, ignore rule)")
    print("  /ta test        - fire a test alert (flash/sound/popup)")
    print("  /ta status      - show whether you have an active listing & pending tanks")
    print("  /ta debug       - dump raw applicant data to chat (for troubleshooting)")
    print("  /ta sound raidwarning|readycheck|none - quick sound switch (full list + preview in /ta options)")
    print("  /ta flash on|off   - toggle the screen flash")
    print("  /ta popup on|off   - toggle the invite/decline popup")
    print("  /ta chat on|off    - toggle chat announcements")
end

local function OnSlash(msg)
    msg = strtrim((msg or ""):lower())
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")

    if cmd == "" or cmd == "help" then
        PrintHelp()
    elseif cmd == "options" or cmd == "config" then
        if ns.ToggleOptions then
            ns.ToggleOptions()
        else
            print("|cffffd100LFG TankAlert|r options window isn't loaded.")
        end
    elseif cmd == "test" then
        ns.RunTestAlert()
    elseif cmd == "status" then
        local hasEntry = C_LFGList.HasActiveEntryInfo()
        local count = 0
        for _ in pairs(pendingTanks) do count = count + 1 end
        print(("|cffffd100LFG TankAlert|r active listing: %s | pending tank applicants: %d"):format(
            hasEntry and "|cff33ff99yes|r" or "|cffff3333no|r", count))
    elseif cmd == "debug" then
        local ok, err = pcall(function()
            print(("|cffffd100LFG TankAlert debug|r active listing: %s"):format(tostring(C_LFGList.HasActiveEntryInfo())))
            local ids = C_LFGList.GetApplicants()
            if not ids or #ids == 0 then
                print("  no applicants right now.")
            end
            for _, id in ipairs(ids or {}) do
                print(("  applicantID=%s"):format(tostring(id)))

                local first = C_LFGList.GetApplicantInfo(id)
                if type(first) == "table" then
                    print("  GetApplicantInfo returned a table; raw fields:")
                    for k, v in pairs(first) do
                        print(("    ." .. tostring(k) .. " = " .. tostring(v)))
                    end
                else
                    local _appID, status, pending, rawNumMembers, isNew = C_LFGList.GetApplicantInfo(id)
                    print(("  status=%s pending=%s numMembers=%s isNew=%s"):format(
                        tostring(status), tostring(pending), tostring(rawNumMembers), tostring(isNew)))
                end

                local applicationStatus, rawNumMembers = GetApplicantStatusInfo(id)
                local numMembers = CountApplicantMembers(id, rawNumMembers)
                print(("  resolved: applicationStatus=%s numMembers=%d"):format(tostring(applicationStatus), numMembers))

                local firstMemberName
                for i = 1, numMembers do
                    local name, class, localizedClass, level, itemLevel, honorLevel,
                          tank, healer, damage, assignedRole, relationship, dungeonScore =
                        C_LFGList.GetApplicantMemberInfo(id, i)
                    firstMemberName = firstMemberName or name
                    print(("    member %d: name=%s class=%s localizedClass=%s ilvl=%s tank=%s healer=%s damage=%s score=%s"):format(
                        i, tostring(name), tostring(class), tostring(localizedClass), tostring(itemLevel),
                        tostring(tank), tostring(healer), tostring(damage), tostring(dungeonScore)))
                end

                if type(RaiderIO) ~= "table" then
                    print("    Raider.IO: addon not installed")
                elseif firstMemberName then
                    local rio = GetRaiderIOSummary(firstMemberName, GetCurrentActivityIDSet())
                    if rio then
                        print(("    Raider.IO: currentScore=%s previousScore=%s previousScoreSeason=%s"):format(
                            tostring(rio.currentScore), tostring(rio.previousScore), tostring(rio.previousScoreSeason)))
                        if rio.bestRun then
                            print(("    Raider.IO bestRun: level=%s chests=%s dungeonName=%s dungeonShortName=%s"):format(
                                tostring(rio.bestRun.level), tostring(rio.bestRun.chests),
                                tostring(rio.bestRun.dungeonName), tostring(rio.bestRun.dungeonShortName)))
                        end
                        if rio.thisDungeonBestRun then
                            print(("    Raider.IO thisDungeonBestRun: level=%s chests=%s"):format(
                                tostring(rio.thisDungeonBestRun.level), tostring(rio.thisDungeonBestRun.chests)))
                        end
                    else
                        print("    Raider.IO: no cached profile for this applicant")
                    end
                end
            end
        end)
        if not ok then
            print("|cffff0000[LFG TankAlert] debug itself errored:|r " .. tostring(err))
        end
    elseif cmd == "sound" then
        if rest == "raidwarning" then
            db.sound = "RAID_WARNING"; print("LFG TankAlert: sound set to Raid Warning.")
        elseif rest == "readycheck" then
            db.sound = "READY_CHECK"; print("LFG TankAlert: sound set to Ready Check.")
        elseif rest == "none" then
            db.sound = "NONE"; print("LFG TankAlert: sound disabled.")
        else
            print("Usage: /ta sound raidwarning|readycheck|none")
        end
    elseif cmd == "flash" then
        if rest == "on" then db.flashEnabled = true; print("LFG TankAlert: flash ON.")
        elseif rest == "off" then db.flashEnabled = false; HideFlash(); print("LFG TankAlert: flash OFF.")
        else print("Usage: /ta flash on|off") end
    elseif cmd == "popup" then
        if rest == "on" then db.popupEnabled = true; UpdatePopup(); print("LFG TankAlert: popup ON.")
        elseif rest == "off" then db.popupEnabled = false; UpdatePopup(); print("LFG TankAlert: popup OFF.")
        else print("Usage: /ta popup on|off") end
    elseif cmd == "chat" then
        if rest == "on" then db.chatAnnounce = true; print("LFG TankAlert: chat announcements ON.")
        elseif rest == "off" then db.chatAnnounce = false; print("LFG TankAlert: chat announcements OFF.")
        else print("Usage: /ta chat on|off") end
    else
        PrintHelp()
    end
end

SLASH_TANKALERT1 = "/tankalert"
SLASH_TANKALERT2 = "/ta"
SlashCmdList.TANKALERT = OnSlash
