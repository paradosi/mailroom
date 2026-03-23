-- Mailroom / Modules / PendingIncome.lua
-- AH listing tracker and income estimator.
-- Hooks AH posting events to record active listings, then matches them
-- against incoming AH mail to track which listings sold, expired, or
-- were cancelled. Provides a summary of tracked pending income that
-- other modules can query. Only listings posted while Mailroom was
-- active are tracked — this is clearly communicated to the player.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- PendingIncome Module
-------------------------------------------------------------------------------

MR.PendingIncome = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- AH duration options in seconds. WoW offers 12h, 24h, and 48h durations.
-- These are used to calculate when a listing should be considered expired.
local DURATION_SECONDS = {
    [1] = 43200,   -- 12 hours
    [2] = 86400,   -- 24 hours
    [3] = 172800,  -- 48 hours
}

-- Default expiry if duration is unknown. 48 hours is the safest fallback
-- because it is the longest standard AH listing duration.
local DEFAULT_DURATION = 172800

-- Disclaimer text shown in all displays. Critical because we can only
-- track listings created while the addon was loaded and the AH was open.
local DISCLAIMER = "Only listings posted while Mailroom was active are tracked."

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local ahHooksInstalled = false

-------------------------------------------------------------------------------
-- Listing Management
-- Listings are stored in db.factionrealm.pendingListings as an array
-- of tables. We use factionrealm scope because AH listings are shared
-- across characters on the same faction and realm.
-------------------------------------------------------------------------------

-- Returns the pending listings table from the database.
-- Creates it if it does not exist (first run).
-- @return (table) Array of listing entries.
local function GetListings()
    local db = MR.Addon.db.factionrealm
    if not db.pendingListings then
        db.pendingListings = {}
    end
    return db.pendingListings
end

-- Records a new AH listing.
-- @param itemName (string) Name of the listed item.
-- @param quantity (number) Stack size of the listing.
-- @param askingPrice (number) Buyout or bid price in copper.
-- @param duration (number) Duration index (1=12h, 2=24h, 3=48h).
local function RecordListing(itemName, quantity, askingPrice, duration)
    local listings = GetListings()
    local durationSec = DURATION_SECONDS[duration] or DEFAULT_DURATION

    table.insert(listings, {
        itemName     = itemName,
        quantity     = quantity or 1,
        askingPrice  = askingPrice or 0,
        postedAt     = time(),
        duration     = durationSec,
        resolved     = false,
    })
end

-- Attempts to match a collected AH mail against pending listings.
-- When AH mail is collected, we search for an unresolved listing with
-- a matching item name and mark the first match as resolved. We match
-- on item name only because the AH mail subject does not reliably
-- contain quantity or price information across all clients.
-- @param info (table) A mail cache entry from MR.mailCache.
local function TryResolveListing(info)
    if not info or not info.subject then return end

    local listings = GetListings()

    -- AH sale mail subjects typically contain the item name. We extract
    -- it by searching listing names against the subject text.
    for _, listing in ipairs(listings) do
        if not listing.resolved and listing.itemName then
            if info.subject:find(listing.itemName, 1, true) then
                listing.resolved = true
                return
            end
        end
    end
end

-- Checks all unresolved listings and flags those that have exceeded
-- their posting duration as expired. Called periodically to keep the
-- summary accurate.
local function FlagExpiredListings()
    local listings = GetListings()
    local now = time()

    for _, listing in ipairs(listings) do
        if not listing.resolved then
            local expiresAt = listing.postedAt + listing.duration
            if now > expiresAt then
                listing.resolved = true
                listing.expired = true
            end
        end
    end
end

-- Removes resolved listings older than 7 days to prevent indefinite
-- growth of the saved variables table. Called on MAIL_SHOW.
local function CleanupOldListings()
    local listings = GetListings()
    local now = time()
    local sevenDays = 604800

    local i = 1
    while i <= #listings do
        local listing = listings[i]
        if listing.resolved and (now - listing.postedAt) > sevenDays then
            table.remove(listings, i)
        else
            i = i + 1
        end
    end
end

-------------------------------------------------------------------------------
-- AH Event Hooks
-- We hook into AH posting events to record new listings. The events
-- differ between Retail and Classic clients. On Retail, we hook
-- PostAuction; on Classic, we hook the legacy PlaceAuctionBid flow.
-- The hooks are installed once and persist for the addon's lifetime.
-------------------------------------------------------------------------------

-- Installs hooks on AH posting functions to capture new listings.
-- Uses hooksecurefunc to avoid tainting the original functions.
local function InstallAHHooks()
    if ahHooksInstalled then return end
    ahHooksInstalled = true

    -- Retail uses C_AuctionHouse.PostItem or C_AuctionHouse.PostCommodity.
    -- Classic uses the global PostAuction(). We hook whichever is available.
    if C_AuctionHouse then
        -- Retail: hook PostItem for items and PostCommodity for commodities.
        if C_AuctionHouse.PostItem then
            hooksecurefunc(C_AuctionHouse, "PostItem", function(itemLocation, duration, quantity, unitPrice, buyoutPrice)
                if not MR.Addon.db.profile.pendingIncomeEnabled then return end

                -- Get item name from the item location.
                local itemName = ""
                if C_Item and C_Item.GetItemName then
                    itemName = C_Item.GetItemName(itemLocation) or ""
                end

                local price = buyoutPrice or unitPrice or 0
                RecordListing(itemName, quantity or 1, price, duration)
            end)
        end

        if C_AuctionHouse.PostCommodity then
            hooksecurefunc(C_AuctionHouse, "PostCommodity", function(itemLocation, duration, quantity, unitPrice)
                if not MR.Addon.db.profile.pendingIncomeEnabled then return end

                local itemName = ""
                if C_Item and C_Item.GetItemName then
                    itemName = C_Item.GetItemName(itemLocation) or ""
                end

                local totalPrice = (unitPrice or 0) * (quantity or 1)
                RecordListing(itemName, quantity or 1, totalPrice, duration)
            end)
        end
    end

    -- Classic / MoP: hook the global PostAuction if it exists.
    -- PostAuction(startPrice, buyoutPrice, runTime) is called after the
    -- player clicks the Create Auction button on the classic AH UI.
    if PostAuction then
        hooksecurefunc("PostAuction", function(startPrice, buyoutPrice, runTime)
            if not MR.Addon.db.profile.pendingIncomeEnabled then return end

            -- On Classic, the item in the auction slot can be queried via
            -- GetAuctionSellItemInfo(). This returns name, texture, count, etc.
            local name, _, count = GetAuctionSellItemInfo()
            if name then
                RecordListing(name, count or 1, buyoutPrice or startPrice or 0, runTime)
            end
        end)
    end
end

-------------------------------------------------------------------------------
-- Mail Collection Hook
-- We install a wrapper on MR.TakeInboxMoney to detect when AH gold
-- arrives. When the collected mail is classified as "ah", we try to
-- resolve a matching pending listing. This piggybacks on the same
-- wrapping pattern used by Rake and Analytics.
-------------------------------------------------------------------------------

local takeMoneyWrapInstalled = false

-- Installs a wrapper around MR.TakeInboxMoney to detect AH mail collection.
local function InstallTakeMoneyWrap()
    if takeMoneyWrapInstalled then return end
    takeMoneyWrapInstalled = true

    local originalTakeMoney = MR.TakeInboxMoney
    MR.TakeInboxMoney = function(index, ...)
        if MR.Addon.db.profile.pendingIncomeEnabled then
            local info = MR.mailCache[index]
            if info and MR.ClassifyMail(info) == "ah" then
                TryResolveListing(info)
            end
        end
        return originalTakeMoney(index, ...)
    end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Returns a summary of pending income state.
-- @return (table) Summary with trackedCount, estimatedGold, and expiredCount.
function MR.PendingIncome:GetSummary()
    FlagExpiredListings()

    local listings = GetListings()
    local trackedCount = 0
    local estimatedGold = 0
    local expiredCount = 0

    for _, listing in ipairs(listings) do
        if not listing.resolved then
            trackedCount = trackedCount + 1
            estimatedGold = estimatedGold + (listing.askingPrice or 0)
        elseif listing.expired then
            expiredCount = expiredCount + 1
        end
    end

    return {
        trackedCount  = trackedCount,
        estimatedGold = estimatedGold,
        expiredCount  = expiredCount,
    }
end

-- Prints the pending income summary to chat.
-- Includes the disclaimer about tracking limitations.
function MR.PendingIncome:PrintSummary()
    local summary = self:GetSummary()

    MR.Addon:Print("--- Pending Income ---")

    if summary.trackedCount == 0 and summary.expiredCount == 0 then
        MR.Addon:Print("  No tracked listings.")
    else
        if summary.trackedCount > 0 then
            MR.Addon:Print("  Active listings: " .. summary.trackedCount)
            MR.Addon:Print("  Estimated income: " ..
                MR.FormatMoney(summary.estimatedGold))
        end
        if summary.expiredCount > 0 then
            MR.Addon:Print("  Expired/unsold: " .. summary.expiredCount)
        end
    end

    MR.Addon:Print("  " .. DISCLAIMER)
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Registers AH hooks and cleans up old data when the mailbox opens.
function MR.PendingIncome:OnMailShow()
    if not MR.Addon.db.profile.pendingIncomeEnabled then return end
    InstallAHHooks()
    InstallTakeMoneyWrap()
    CleanupOldListings()
    FlagExpiredListings()
end

-------------------------------------------------------------------------------
-- Slash Command Integration
-- Registers "pending" as a subcommand of /mr. This is handled by
-- Mailroom.lua's OnSlashCommand, which should call this method.
-------------------------------------------------------------------------------

-- Handles the /mr pending slash command.
function MR.PendingIncome:OnSlashCommand()
    self:PrintSummary()
end
