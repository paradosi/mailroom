-- Mailroom / Modules / ExpiryTicker.lua
-- Persistent expiry countdown on a minimap button.
-- Caches mail expiry times from MR.mailCache into persistent storage
-- (factionrealm scope) so expiry warnings are available even when the
-- mailbox is closed. A background ticker checks every 60 seconds for
-- the most urgent expiry and updates the minimap button tooltip. When
-- any mail expires within the configured threshold, the button turns red.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- ExpiryTicker Module
-------------------------------------------------------------------------------

MR.ExpiryTicker = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- How often the background ticker fires, in seconds. 60 seconds is
-- frequent enough for meaningful countdown updates without being
-- wasteful with CPU time.
local TICKER_INTERVAL = 60

-- Seconds per day, used to convert daysLeft from GetInboxHeaderInfo
-- into an absolute timestamp.
local SECONDS_PER_DAY = 86400

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local tickerHandle     = nil   -- C_Timer.NewTicker handle
local minimapButton    = nil   -- the minimap button frame
local buttonCreated    = false

-------------------------------------------------------------------------------
-- Mail Key Generation
-- Same composite key approach as Snooze.lua — sender + subject + money.
-- We use this to identify mail items across sessions since inbox indices
-- are volatile and change every time the inbox refreshes.
-------------------------------------------------------------------------------

-- Builds a stable key for a mail cache entry.
-- @param info (table) A mail info table from MR.mailCache.
-- @return (string) Composite key like "Thrall::Greetings::0".
local function BuildMailKey(info)
    local sender  = info.sender or "Unknown"
    local subject = info.subject or ""
    local money   = info.money or 0
    return sender .. "::" .. subject .. "::" .. tostring(money)
end

-------------------------------------------------------------------------------
-- Expiry Cache Management
-- On each MAIL_SHOW, we rebuild the expiry cache from the current
-- inbox contents. The cache is stored in factionrealm scope so it
-- persists across sessions and is shared among characters on the
-- same faction and realm (though each character's mail is separate,
-- the last-visited character's cache is what remains).
-------------------------------------------------------------------------------

-- Returns the expiry cache table from the database.
-- @return (table) Expiry cache keyed by mail key.
local function GetExpiryCache()
    local db = MR.Addon.db.factionrealm
    if not db.expiryCache then
        db.expiryCache = {}
    end
    return db.expiryCache
end

-- Rebuilds the expiry cache from the current MR.mailCache contents.
-- Called on MAIL_SHOW after the inbox has been scanned. Replaces the
-- entire cache because we cannot reliably detect which mail items
-- were removed between sessions (indices shift, items expire).
local function RebuildExpiryCache()
    local cache = GetExpiryCache()
    wipe(cache)

    local now = time()
    for _, info in ipairs(MR.mailCache) do
        if info.daysLeft and info.daysLeft > 0 then
            local key = BuildMailKey(info)
            cache[key] = {
                sender    = info.sender,
                subject   = info.subject,
                expiresAt = now + (info.daysLeft * SECONDS_PER_DAY),
            }
        end
    end
end

-- Removes expired entries from the cache.
-- Called by the background ticker to keep the cache clean.
local function CleanupExpiredEntries()
    local cache = GetExpiryCache()
    local now = time()

    for key, entry in pairs(cache) do
        if entry.expiresAt <= now then
            cache[key] = nil
        end
    end
end

-------------------------------------------------------------------------------
-- Urgency Check
-- Finds the mail item closest to expiry in the cache. Returns its
-- entry data and remaining time. Used by the ticker to determine
-- tooltip text and button tint.
-------------------------------------------------------------------------------

-- Finds the most urgent (soonest-expiring) entry in the cache.
-- @return (table or nil) The cache entry closest to expiry, or nil if empty.
-- @return (number) Seconds remaining until the most urgent mail expires.
local function FindMostUrgent()
    local cache = GetExpiryCache()
    local now = time()
    local urgentEntry = nil
    local urgentRemaining = math.huge

    for _, entry in pairs(cache) do
        local remaining = entry.expiresAt - now
        if remaining > 0 and remaining < urgentRemaining then
            urgentRemaining = remaining
            urgentEntry = entry
        end
    end

    if urgentEntry then
        return urgentEntry, urgentRemaining
    end

    return nil, 0
end

-------------------------------------------------------------------------------
-- Time Formatting
-- Converts remaining seconds into a human-readable countdown string.
-------------------------------------------------------------------------------

-- Formats a remaining time in seconds as a readable countdown.
-- @param seconds (number) Remaining seconds.
-- @return (string) Formatted string like "2d 5h", "3h 22m", or "45m".
local function FormatCountdown(seconds)
    if seconds <= 0 then return "Expired" end

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return days .. "d " .. hours .. "h"
    elseif hours > 0 then
        return hours .. "h " .. minutes .. "m"
    else
        return minutes .. "m"
    end
end

-------------------------------------------------------------------------------
-- Minimap Button
-- A simple square button near the minimap with an icon. The tooltip
-- shows the most urgent mail expiry. When any mail is within the
-- threshold, the button icon gets a red tint to draw attention.
-------------------------------------------------------------------------------

-- Creates the minimap button frame.
local function CreateMinimapButton()
    if buttonCreated then return end
    buttonCreated = true

    minimapButton = CreateFrame("Button", "MailroomExpiryButton",
        Minimap)
    minimapButton:SetSize(28, 28)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)

    -- Position the button at a fixed angle on the minimap border.
    -- We use a simple offset rather than calculating angle-based
    -- positioning to avoid complexity and OnUpdate polling.
    minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -5, 5)

    -- Button icon. Uses the standard mail icon as a fallback if the
    -- addon icon texture is not found.
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Minimap\\Tracking\\Mailbox")
    minimapButton.icon = icon

    -- Highlight texture for mouseover.
    local highlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    -- Border ring matching other minimap buttons.
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Tooltip on hover.
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Mailroom", 0.9, 0.8, 0.5)

        local entry, remaining = FindMostUrgent()
        if entry then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Next expiry:", 1, 1, 1)

            local subj = entry.subject or "(no subject)"
            if #subj > 30 then
                subj = subj:sub(1, 27) .. "..."
            end
            GameTooltip:AddLine(subj .. " from " .. (entry.sender or "Unknown"),
                0.8, 0.8, 0.8)
            GameTooltip:AddLine("Expires in " .. FormatCountdown(remaining),
                1, 0.8, 0.2)

            -- Show pending income summary if available.
            if MR.PendingIncome then
                local summary = MR.PendingIncome:GetSummary()
                if summary.trackedCount > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Pending AH Income:", 1, 1, 1)
                    GameTooltip:AddLine(summary.trackedCount .. " listing(s), ~" ..
                        MR.FormatMoney(summary.estimatedGold), 0.8, 0.8, 0.8)
                end
            end
        else
            GameTooltip:AddLine("No tracked mail expiries.", 0.6, 0.6, 0.6)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Left-click", "Open settings", 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Left-click opens settings.
    minimapButton:SetScript("OnClick", function()
        LibStub("AceConfigDialog-3.0"):Open("Mailroom")
    end)
end

-- Updates the minimap button tint based on urgency.
-- Red tint when any mail is within the threshold; normal tint otherwise.
local function UpdateButtonTint()
    if not minimapButton then return end

    local _, remaining = FindMostUrgent()
    local thresholdHours = MR.Addon.db.profile.expiryTickerThreshold
    local thresholdSeconds = thresholdHours * 3600

    if remaining > 0 and remaining <= thresholdSeconds then
        -- Red tint to indicate urgent expiry.
        minimapButton.icon:SetVertexColor(1.0, 0.3, 0.3)
    else
        -- Normal tint when nothing is urgent.
        minimapButton.icon:SetVertexColor(1.0, 1.0, 1.0)
    end
end

-------------------------------------------------------------------------------
-- Background Ticker
-- A C_Timer.NewTicker that fires every TICKER_INTERVAL seconds to
-- clean up expired entries and update the button tint. This runs even
-- when the mailbox is closed, using the persisted expiry cache.
-------------------------------------------------------------------------------

-- The function called by C_Timer.NewTicker on each tick.
-- Cleans expired entries and updates the button visual state.
local function OnTick()
    CleanupExpiredEntries()
    UpdateButtonTint()
end

-- Starts the background ticker if it is not already running.
local function StartTicker()
    if tickerHandle then return end
    tickerHandle = C_Timer.NewTicker(TICKER_INTERVAL, OnTick)
end

-- Stops the background ticker if it is running.
-- Called when the module is disabled.
local function StopTicker()
    if tickerHandle then
        tickerHandle:Cancel()
        tickerHandle = nil
    end
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Rebuilds the expiry cache from fresh inbox data, creates the minimap
-- button, and starts the background ticker.
function MR.ExpiryTicker:OnMailShow()
    if not MR.Addon.db.profile.expiryTickerEnabled then return end

    RebuildExpiryCache()
    CreateMinimapButton()
    StartTicker()
    UpdateButtonTint()
end

-- Updates the button tint when the mailbox closes. The ticker continues
-- running in the background using the cached data.
function MR.ExpiryTicker:OnMailClosed()
    if not MR.Addon.db.profile.expiryTickerEnabled then return end
    UpdateButtonTint()
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Returns the most urgent expiry entry and its remaining seconds.
-- @return (table or nil) The cache entry, or nil if no tracked mail.
-- @return (number) Seconds remaining, or 0 if no tracked mail.
function MR.ExpiryTicker:GetMostUrgent()
    return FindMostUrgent()
end

-- Returns the total count of tracked expiry entries.
-- @return (number) Count of entries in the expiry cache.
function MR.ExpiryTicker:GetTrackedCount()
    local cache = GetExpiryCache()
    local count = 0
    for _ in pairs(cache) do
        count = count + 1
    end
    return count
end
