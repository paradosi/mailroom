-- Mailroom / Modules / Snooze.lua
-- Temporarily hide mail from Mailroom views.
-- Adds a "Snooze" button to OpenMailFrame that lets the player hide
-- individual mail items for a chosen duration. Other modules (OpenAll,
-- BulkSelect, MailBag) call MR.Snooze:IsSnoozed() to filter snoozed
-- mail from their views. Snooze entries are keyed by a composite of
-- sender, subject, and money amount since mail indices shift between
-- sessions and cannot be used as stable identifiers.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Snooze Module
-------------------------------------------------------------------------------

MR.Snooze = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Duration presets in seconds, mapped to display labels.
local DURATION_PRESETS = {
    { label = "1 Hour",  seconds = 3600 },
    { label = "4 Hours", seconds = 14400 },
    { label = "1 Day",   seconds = 86400 },
    { label = "3 Days",  seconds = 259200 },
}

-------------------------------------------------------------------------------
-- Mail Key Generation
-- We build a key from sender, subject, and money because mail indices
-- change every time the inbox refreshes (items shift as mail is taken
-- or deleted). This composite key uniquely identifies a mail item
-- across sessions without relying on volatile index values.
-------------------------------------------------------------------------------

-- Builds a stable key for a mail cache entry.
-- @param info (table) A mail info table from MR.mailCache with sender,
--             subject, and money fields.
-- @return (string) A composite key like "Thrall::Greetings::0".
local function BuildMailKey(info)
    local sender = info.sender or "Unknown"
    local subject = info.subject or ""
    local money = info.money or 0
    return sender .. "::" .. subject .. "::" .. tostring(money)
end

-------------------------------------------------------------------------------
-- Expired Snooze Cleanup
-- Called on each MAIL_SHOW to remove snooze entries whose expiry
-- timestamp has passed. This keeps the saved data table from growing
-- indefinitely with stale entries.
-------------------------------------------------------------------------------

-- Removes all snooze entries that have expired (expiry < current time).
local function CleanupExpired()
    local snoozed = MR.Addon.db.profile.snoozedMail
    local now = time()
    for key, expiryTimestamp in pairs(snoozed) do
        if expiryTimestamp <= now then
            snoozed[key] = nil
        end
    end
end

-------------------------------------------------------------------------------
-- Snoozed Count
-- Used by the badge on InboxFrame to show how many mail items are
-- currently hidden by active (non-expired) snooze entries.
-------------------------------------------------------------------------------

-- Counts the number of currently active (non-expired) snooze entries.
-- @return (number) Count of snoozed mail items.
local function CountSnoozed()
    local snoozed = MR.Addon.db.profile.snoozedMail
    local now = time()
    local count = 0
    for _, expiryTimestamp in pairs(snoozed) do
        if expiryTimestamp > now then
            count = count + 1
        end
    end
    return count
end

-------------------------------------------------------------------------------
-- Snooze Badge
-- A small text badge on InboxFrame showing the count of currently
-- snoozed mail. Hidden when count is zero.
-------------------------------------------------------------------------------

local badgeText = nil

-- Creates the badge FontString on InboxFrame if it does not exist.
local function CreateBadge()
    if badgeText then return end

    badgeText = InboxFrame:CreateFontString(nil, "OVERLAY",
        "GameFontNormalSmall")
    badgeText:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 70, -38)
    badgeText:SetTextColor(0.6, 0.6, 1.0)
end

-- Updates the badge text with the current snoozed count.
local function UpdateBadge()
    if not badgeText then return end

    local count = CountSnoozed()
    if count > 0 then
        badgeText:SetText(count .. " snoozed")
        badgeText:Show()
    else
        badgeText:Hide()
    end
end

-------------------------------------------------------------------------------
-- Snooze Popup
-- A small frame anchored to OpenMailFrame with duration buttons.
-- Clicking a preset snoozes the currently viewed mail for that duration.
-- The "Custom" option prompts for minutes via a StaticPopup EditBox.
-------------------------------------------------------------------------------

local popupFrame = nil

-- Snoozes the currently viewed mail for the given duration in seconds.
-- Reads the current mail info from the cache using the open mail index.
-- @param durationSeconds (number) How long to snooze, in seconds.
local function SnoozeCurrentMail(durationSeconds)
    -- InboxFrame.openMailID is set by Blizzard when a mail is opened.
    local openIndex = InboxFrame.openMailID
    if not openIndex then
        MR.Addon:Print("No mail is currently open.")
        return
    end

    local info = MR.mailCache[openIndex]
    if not info then
        MR.Addon:Print("Could not identify the open mail.")
        return
    end

    local key = BuildMailKey(info)
    local expiryTimestamp = time() + durationSeconds
    MR.Addon.db.profile.snoozedMail[key] = expiryTimestamp

    MR.Addon:Print("Snoozed mail from " .. info.sender .. " for " ..
        math.floor(durationSeconds / 3600) .. "h.")

    UpdateBadge()

    -- Hide the popup after snoozing.
    if popupFrame then
        popupFrame:Hide()
    end
end

-- Creates the snooze duration popup frame if it does not exist.
local function CreatePopup()
    if popupFrame then return end

    popupFrame = CreateFrame("Frame", "MailroomSnoozePopup",
        OpenMailFrame, "BackdropTemplate")
    popupFrame:SetSize(120, 30 + (#DURATION_PRESETS * 24) + 24)
    popupFrame:SetPoint("TOPLEFT", OpenMailFrame, "TOPRIGHT", 2, 0)
    popupFrame:SetFrameStrata("DIALOG")
    popupFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    popupFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    popupFrame:EnableMouse(true)

    -- Title
    local title = popupFrame:CreateFontString(nil, "OVERLAY",
        "GameFontNormalSmall")
    title:SetPoint("TOP", popupFrame, "TOP", 0, -8)
    title:SetText("Snooze for...")
    title:SetTextColor(0.9, 0.8, 0.5)

    -- Preset duration buttons.
    for i, preset in ipairs(DURATION_PRESETS) do
        local btn = CreateFrame("Button", nil, popupFrame,
            "UIPanelButtonTemplate")
        btn:SetSize(100, 20)
        btn:SetPoint("TOP", popupFrame, "TOP", 0, -22 - ((i - 1) * 24))
        btn:SetText(preset.label)
        btn:SetScript("OnClick", function()
            SnoozeCurrentMail(preset.seconds)
        end)
    end

    -- Custom duration button. Uses a StaticPopup with an EditBox to let
    -- the player type a duration in minutes.
    local customBtn = CreateFrame("Button", nil, popupFrame,
        "UIPanelButtonTemplate")
    customBtn:SetSize(100, 20)
    customBtn:SetPoint("TOP", popupFrame, "TOP", 0,
        -22 - (#DURATION_PRESETS * 24))
    customBtn:SetText("Custom...")
    customBtn:SetScript("OnClick", function()
        StaticPopup_Show("MAILROOM_SNOOZE_CUSTOM")
    end)

    popupFrame:Hide()
end

-- Register the StaticPopup dialog for custom snooze duration input.
-- We define this at file scope so it exists before the popup is shown.
-- The dialog asks for a number of minutes and converts to seconds.
StaticPopupDialogs["MAILROOM_SNOOZE_CUSTOM"] = {
    text = "Snooze duration (minutes):",
    button1 = "Snooze",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 6,
    OnAccept = function(self)
        local text = self.editBox:GetText()
        local minutes = tonumber(text)
        if minutes and minutes > 0 then
            SnoozeCurrentMail(minutes * 60)
        else
            MR.Addon:Print("Invalid duration. Enter a number of minutes.")
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local text = self:GetText()
        local minutes = tonumber(text)
        if minutes and minutes > 0 then
            SnoozeCurrentMail(minutes * 60)
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- Snooze Button on OpenMailFrame
-- Created once and persists. Toggles the duration popup on click.
-------------------------------------------------------------------------------

local snoozeButtonCreated = false

-- Creates the "Snooze" button on OpenMailFrame.
local function CreateSnoozeButton()
    if snoozeButtonCreated then return end
    snoozeButtonCreated = true

    CreatePopup()

    local btn = CreateFrame("Button", "MailroomSnoozeButton",
        OpenMailFrame, "UIPanelButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetPoint("BOTTOMRIGHT", OpenMailFrame, "BOTTOMRIGHT", -8, 4)
    btn:SetText("Snooze")
    btn:SetScript("OnClick", function()
        if popupFrame:IsShown() then
            popupFrame:Hide()
        else
            popupFrame:Show()
        end
    end)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Checks whether a mail cache entry is currently snoozed.
-- Returns true if the mail matches a snooze entry that has not yet expired.
-- Other modules should call this to filter snoozed mail from their views.
-- @param info (table) A mail info table from MR.mailCache.
-- @return (boolean) True if the mail is snoozed and the snooze is active.
function MR.Snooze:IsSnoozed(info)
    if not MR.Addon.db.profile.snoozeEnabled then return false end

    -- The showSnoozed setting temporarily reveals all snoozed mail,
    -- effectively disabling snooze filtering without clearing the data.
    if MR.Addon.db.profile.showSnoozed then return false end

    local key = BuildMailKey(info)
    local expiryTimestamp = MR.Addon.db.profile.snoozedMail[key]
    if not expiryTimestamp then return false end

    if expiryTimestamp <= time() then
        -- Snooze has expired; clean it up inline.
        MR.Addon.db.profile.snoozedMail[key] = nil
        return false
    end

    return true
end

-- Removes the snooze entry for a given mail info table.
-- @param info (table) A mail info table from MR.mailCache.
function MR.Snooze:Unsnooze(info)
    local key = BuildMailKey(info)
    MR.Addon.db.profile.snoozedMail[key] = nil
    UpdateBadge()
end

-- Returns the count of currently active snooze entries.
-- @return (number) Number of snoozed mail items.
function MR.Snooze:GetSnoozedCount()
    return CountSnoozed()
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Cleans up expired snoozes, creates UI elements, and updates the badge.
function MR.Snooze:OnMailShow()
    if not MR.Addon.db.profile.snoozeEnabled then return end
    CleanupExpired()
    CreateSnoozeButton()
    CreateBadge()
    UpdateBadge()
end

-- Hides the popup when the mailbox closes.
function MR.Snooze:OnMailClosed()
    if popupFrame then
        popupFrame:Hide()
    end
end
