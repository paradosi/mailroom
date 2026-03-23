-- Mailroom / Modules / Analytics.lua
-- Session report panel and history tracking.
-- Records per-session statistics (gold collected, AH sales, items received,
-- items returned, attachments looted, time spent) and stores them in the
-- profile database. Wraps MR.TakeInboxMoney and MR.TakeInboxItem to
-- increment counters as mail is processed. Shows a summary frame on
-- MAIL_CLOSED if there was activity, and provides a history browser.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Analytics Module
-------------------------------------------------------------------------------

MR.Analytics = {}

-------------------------------------------------------------------------------
-- Session State
-- A new session begins on MAIL_SHOW and ends on MAIL_CLOSED. All counters
-- reset at the start of each session. The session is pushed to persistent
-- history on close if any activity occurred.
-------------------------------------------------------------------------------

local session = {
    goldCollected   = 0, -- copper collected via TakeInboxMoney
    ahSalesCount    = 0, -- AH mail collected (detected via ClassifyMail)
    itemsReceived   = 0, -- items taken from non-AH, non-returned mail
    itemsReturned   = 0, -- items taken from returned mail
    attachmentsLooted = 0, -- total individual attachment takes
    startTime       = 0, -- time() when MAIL_SHOW fired
    endTime         = 0, -- time() when MAIL_CLOSED fired
    hadActivity     = false, -- true if any counter incremented
}

-- Resets all session counters to zero.
local function ResetSession()
    session.goldCollected     = 0
    session.ahSalesCount      = 0
    session.itemsReceived     = 0
    session.itemsReturned     = 0
    session.attachmentsLooted = 0
    session.startTime         = 0
    session.endTime           = 0
    session.hadActivity       = false
end

-------------------------------------------------------------------------------
-- Wraps
-- We wrap MR.TakeInboxMoney and MR.TakeInboxItem (similar to Rake's
-- TakeInboxMoney wrap) to count operations as they happen. The wraps
-- are installed once and persist for the addon's lifetime.
-------------------------------------------------------------------------------

local wrapsInstalled = false

-- Installs wrapper functions around MR.TakeInboxMoney and MR.TakeInboxItem.
-- Each wrapper records relevant counters before delegating to the original.
-- We check the mail cache to classify mail type at take time, because
-- the cache entry still exists when the queued operation executes (the
-- queue processes sequentially, and inbox refresh happens asynchronously).
local function InstallWraps()
    if wrapsInstalled then return end
    wrapsInstalled = true

    -- Wrap TakeInboxMoney to track gold collected and AH sales (gold).
    local originalTakeMoney = MR.TakeInboxMoney
    MR.TakeInboxMoney = function(index, ...)
        if MR.Addon.db.profile.analyticsEnabled then
            local _, _, _, _, money = MR.GetInboxHeaderInfo(index)
            if money and money > 0 then
                session.goldCollected = session.goldCollected + money
                session.hadActivity = true

                -- Count AH gold collections as AH sales.
                local info = MR.mailCache[index]
                if info and MR.ClassifyMail(info) == "ah" then
                    session.ahSalesCount = session.ahSalesCount + 1
                end
            end
        end
        return originalTakeMoney(index, ...)
    end

    -- Wrap TakeInboxItem to track attachments looted and item categories.
    local originalTakeItem = MR.TakeInboxItem
    MR.TakeInboxItem = function(index, ...)
        if MR.Addon.db.profile.analyticsEnabled then
            session.attachmentsLooted = session.attachmentsLooted + 1
            session.hadActivity = true

            local info = MR.mailCache[index]
            if info then
                if info.wasReturned then
                    session.itemsReturned = session.itemsReturned + 1
                else
                    session.itemsReceived = session.itemsReceived + 1
                end
            end
        end
        return originalTakeItem(index, ...)
    end
end

-------------------------------------------------------------------------------
-- History Management
-- Sessions are pushed to db.profile.analyticsHistory on MAIL_CLOSED.
-- The list is capped at analyticsMaxSessions, dropping the oldest entry
-- when the cap is exceeded.
-------------------------------------------------------------------------------

-- Pushes the current session data to persistent history.
-- Only stores if the session had any activity worth recording.
local function PushToHistory()
    local db = MR.Addon.db.profile
    local history = db.analyticsHistory

    local entry = {
        goldCollected     = session.goldCollected,
        ahSalesCount      = session.ahSalesCount,
        itemsReceived     = session.itemsReceived,
        itemsReturned     = session.itemsReturned,
        attachmentsLooted = session.attachmentsLooted,
        startTime         = session.startTime,
        endTime           = session.endTime,
        duration          = session.endTime - session.startTime,
    }

    table.insert(history, entry)

    -- Trim oldest entries to stay within the configured cap.
    local maxSessions = db.analyticsMaxSessions
    while #history > maxSessions do
        table.remove(history, 1)
    end
end

-------------------------------------------------------------------------------
-- Time Formatting
-- Converts a duration in seconds to a human-readable "Xm Ys" string.
-------------------------------------------------------------------------------

-- Formats a duration in seconds as a human-readable string.
-- @param seconds (number) Duration in seconds.
-- @return (string) Formatted string like "2m 15s" or "45s".
local function FormatDuration(seconds)
    if seconds < 0 then seconds = 0 end
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    if minutes > 0 then
        return minutes .. "m " .. secs .. "s"
    else
        return secs .. "s"
    end
end

-- Formats a timestamp as a date/time string for history display.
-- @param timestamp (number) A time() value.
-- @return (string) Formatted date string like "Mar 23 14:30".
local function FormatTimestamp(timestamp)
    if not timestamp or timestamp == 0 then return "Unknown" end
    return date("%b %d %H:%M", timestamp)
end

-------------------------------------------------------------------------------
-- Summary Frame
-- A simple Frame with FontStrings showing all session stats. Created once
-- and reused across sessions. Anchored to InboxFrame.
-------------------------------------------------------------------------------

local summaryFrame = nil
local summaryLabels = {}

-- Creates the summary frame if it does not already exist. The frame is
-- hidden by default and shown on MAIL_CLOSED when there was activity.
local function CreateSummaryFrame()
    if summaryFrame then return end

    summaryFrame = CreateFrame("Frame", "MailroomAnalyticsSummary",
        UIParent, "BasicFrameTemplateWithInset")
    summaryFrame:SetSize(280, 200)
    summaryFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    summaryFrame:SetFrameStrata("DIALOG")
    summaryFrame:SetMovable(true)
    summaryFrame:EnableMouse(true)
    summaryFrame:RegisterForDrag("LeftButton")
    summaryFrame:SetScript("OnDragStart", summaryFrame.StartMoving)
    summaryFrame:SetScript("OnDragStop", summaryFrame.StopMovingOrSizing)

    summaryFrame.TitleText = summaryFrame:CreateFontString(nil, "OVERLAY",
        "GameFontHighlight")
    summaryFrame.TitleText:SetPoint("TOP", summaryFrame, "TOP", 0, -5)
    summaryFrame.TitleText:SetText("Mailroom Session Report")

    -- Build label rows. Each row is a left-aligned name and a right-aligned value.
    local labelNames = {
        "Gold Collected:",
        "AH Sales:",
        "Items Received:",
        "Items Returned:",
        "Attachments Looted:",
        "Time Spent:",
    }

    for i, name in ipairs(labelNames) do
        local yOffset = -30 - ((i - 1) * 22)

        local label = summaryFrame:CreateFontString(nil, "OVERLAY",
            "GameFontNormal")
        label:SetPoint("LEFT", summaryFrame, "TOPLEFT", 16, yOffset)
        label:SetText(name)

        local value = summaryFrame:CreateFontString(nil, "OVERLAY",
            "GameFontHighlight")
        value:SetPoint("RIGHT", summaryFrame, "TOPRIGHT", -16, yOffset)

        summaryLabels[i] = value
    end

    -- Close button is provided by BasicFrameTemplateWithInset.

    -- "View History" button at the bottom of the summary frame.
    local histBtn = CreateFrame("Button", nil, summaryFrame,
        "UIPanelButtonTemplate")
    histBtn:SetSize(120, 22)
    histBtn:SetPoint("BOTTOM", summaryFrame, "BOTTOM", 0, 10)
    histBtn:SetText("View History")
    histBtn:SetScript("OnClick", function()
        MR.Analytics:ShowHistory()
    end)

    summaryFrame:Hide()
end

-- Updates the summary frame labels with current session data and shows it.
local function ShowSummary()
    CreateSummaryFrame()

    summaryLabels[1]:SetText(MR.FormatMoney(session.goldCollected))
    summaryLabels[2]:SetText(tostring(session.ahSalesCount))
    summaryLabels[3]:SetText(tostring(session.itemsReceived))
    summaryLabels[4]:SetText(tostring(session.itemsReturned))
    summaryLabels[5]:SetText(tostring(session.attachmentsLooted))
    summaryLabels[6]:SetText(FormatDuration(session.endTime - session.startTime))

    summaryFrame:Show()
end

-------------------------------------------------------------------------------
-- History Frame
-- A scrollable list of past sessions with date/time and totals.
-- Created once and reused.
-------------------------------------------------------------------------------

local historyFrame = nil
local historyScrollChild = nil

-- Creates the history frame if it does not already exist.
local function CreateHistoryFrame()
    if historyFrame then return end

    historyFrame = CreateFrame("Frame", "MailroomAnalyticsHistory",
        UIParent, "BasicFrameTemplateWithInset")
    historyFrame:SetSize(400, 350)
    historyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    historyFrame:SetFrameStrata("DIALOG")
    historyFrame:SetMovable(true)
    historyFrame:EnableMouse(true)
    historyFrame:RegisterForDrag("LeftButton")
    historyFrame:SetScript("OnDragStart", historyFrame.StartMoving)
    historyFrame:SetScript("OnDragStop", historyFrame.StopMovingOrSizing)

    historyFrame.TitleText = historyFrame:CreateFontString(nil, "OVERLAY",
        "GameFontHighlight")
    historyFrame.TitleText:SetPoint("TOP", historyFrame, "TOP", 0, -5)
    historyFrame.TitleText:SetText("Mailroom Session History")

    -- ScrollFrame for the history list.
    local scrollFrame = CreateFrame("ScrollFrame", nil, historyFrame,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", historyFrame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", historyFrame, "BOTTOMRIGHT", -30, 10)

    historyScrollChild = CreateFrame("Frame", nil, scrollFrame)
    historyScrollChild:SetSize(350, 1) -- height set dynamically
    scrollFrame:SetScrollChild(historyScrollChild)

    historyFrame:Hide()
end

-- Populates the history frame with entries from the database.
-- Clears any existing rows and rebuilds from the current history.
local function PopulateHistory()
    CreateHistoryFrame()

    -- Clear existing children (except the scroll child itself).
    local children = { historyScrollChild:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    local history = MR.Addon.db.profile.analyticsHistory
    if #history == 0 then
        local noData = historyScrollChild:CreateFontString(nil, "OVERLAY",
            "GameFontNormal")
        noData:SetPoint("TOP", historyScrollChild, "TOP", 0, -10)
        noData:SetText("No session history recorded yet.")
        historyScrollChild:SetHeight(30)
        return
    end

    local yOffset = -5
    local rowHeight = 70

    -- Show most recent sessions first.
    for i = #history, 1, -1 do
        local entry = history[i]

        local row = CreateFrame("Frame", nil, historyScrollChild,
            "BackdropTemplate")
        row:SetSize(340, rowHeight - 5)
        row:SetPoint("TOPLEFT", historyScrollChild, "TOPLEFT", 0, yOffset)
        row:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.6)

        -- Header line: date and duration.
        local header = row:CreateFontString(nil, "OVERLAY",
            "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
        header:SetText(FormatTimestamp(entry.startTime) ..
            "  (" .. FormatDuration(entry.duration) .. ")")
        header:SetTextColor(0.9, 0.8, 0.5)

        -- Stats line 1: gold and AH sales.
        local line1 = row:CreateFontString(nil, "OVERLAY",
            "GameFontNormalSmall")
        line1:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
        line1:SetText("Gold: " .. MR.FormatMoney(entry.goldCollected) ..
            "   AH Sales: " .. entry.ahSalesCount)

        -- Stats line 2: items.
        local line2 = row:CreateFontString(nil, "OVERLAY",
            "GameFontNormalSmall")
        line2:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -38)
        line2:SetText("Received: " .. entry.itemsReceived ..
            "   Returned: " .. entry.itemsReturned ..
            "   Looted: " .. entry.attachmentsLooted)

        yOffset = yOffset - rowHeight
    end

    historyScrollChild:SetHeight(math.abs(yOffset) + 10)
end

-------------------------------------------------------------------------------
-- Inbox Frame Button
-- A button on InboxFrame to manually open the session report.
-------------------------------------------------------------------------------

local reportButtonCreated = false

-- Creates a "Report" button on InboxFrame to view the last session report
-- or open the current one mid-session.
local function CreateReportButton()
    if reportButtonCreated then return end
    reportButtonCreated = true

    local btn = CreateFrame("Button", "MailroomAnalyticsButton",
        InboxFrame, "UIPanelButtonTemplate")
    btn:SetSize(70, 22)
    btn:SetPoint("TOPRIGHT", InboxFrame, "TOPRIGHT", -8, -38)
    btn:SetText("Report")
    btn:SetScript("OnClick", function()
        if session.hadActivity then
            ShowSummary()
        else
            MR.Analytics:ShowHistory()
        end
    end)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Opens the history frame, populating it with stored session data.
function MR.Analytics:ShowHistory()
    PopulateHistory()
    historyFrame:Show()
end

-- Returns the current session data table (read-only snapshot).
-- @return (table) Copy of session counters and timestamps.
function MR.Analytics:GetSession()
    return {
        goldCollected     = session.goldCollected,
        ahSalesCount      = session.ahSalesCount,
        itemsReceived     = session.itemsReceived,
        itemsReturned     = session.itemsReturned,
        attachmentsLooted = session.attachmentsLooted,
        startTime         = session.startTime,
        endTime           = session.endTime,
        hadActivity       = session.hadActivity,
    }
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Resets session counters and starts the session timer.
function MR.Analytics:OnMailShow()
    if not MR.Addon.db.profile.analyticsEnabled then return end
    ResetSession()
    session.startTime = time()
    InstallWraps()
    CreateReportButton()
end

-- Finalizes the session, pushes to history, and shows the summary if
-- there was any activity during this mailbox visit.
function MR.Analytics:OnMailClosed()
    if not MR.Addon.db.profile.analyticsEnabled then return end

    session.endTime = time()

    if session.hadActivity then
        PushToHistory()
        ShowSummary()
    end
end
