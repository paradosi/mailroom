-- Mailroom / Modules / TradeBlock.lua
-- Blocks trade and guild charter requests while the mailbox is open.
-- Automatically declines incoming trade requests and charter signature
-- requests while MAIL_SHOW is active, with separate toggles for each.
-- All blocks clear the moment MAIL_CLOSED fires.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- TradeBlock Module
-------------------------------------------------------------------------------

MR.TradeBlock = {}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local blocking = false        -- true while the mailbox is open and blocking
local eventsRegistered = false

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

-- Called when a trade request arrives while blocking is active.
-- Declines the trade and notifies the player.
local function OnTradeShow()
    if not blocking then return end
    if not MR.Addon.db.profile.blockTrades then return end

    -- CloseTrade() or CancelTrade() declines the incoming trade.
    CloseTrade()

    -- UnitName("NPC") returns the name of the player who initiated
    -- the trade during the TRADE_SHOW event.
    local traderName = UnitName("NPC") or "someone"
    MR.Addon:Print("Blocked trade request from " .. traderName .. ".")
end

-- Called when a guild charter petition is offered while blocking.
-- Closes the petition frame to decline it.
local function OnPetitionShow()
    if not blocking then return end
    if not MR.Addon.db.profile.blockCharters then return end

    -- ClosePetition() declines the charter request.
    if ClosePetition then
        ClosePetition()
    end

    MR.Addon:Print("Blocked guild charter request.")
end

-------------------------------------------------------------------------------
-- Module Lifecycle (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Enables trade blocking when the mailbox opens.
function MR.TradeBlock:OnMailShow()
    if not MR.Addon.db.profile.tradeBlockEnabled then return end

    blocking = true

    -- Register blocking events if not already registered.
    if not eventsRegistered then
        eventsRegistered = true
        MR.Addon:RegisterEvent("TRADE_SHOW", OnTradeShow)
        -- PETITION_SHOW fires when someone offers a guild charter to sign.
        if ClosePetition then
            MR.Addon:RegisterEvent("PETITION_SHOW", OnPetitionShow)
        end
    end
end

-- Disables trade blocking when the mailbox closes.
function MR.TradeBlock:OnMailClosed()
    blocking = false
end
