-- Mailroom / Alerts.lua
-- Expiry warnings and COD prompts.
-- Handles user-facing alerts that require attention: mail about to
-- expire, COD payment confirmations, and large gold send warnings.
-- Uses AceConsole :Print for chat messages and standard Blizzard
-- StaticPopup dialogs for confirmations that need a yes/no response.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Alerts Module
-------------------------------------------------------------------------------

MR.Alerts = {}

-------------------------------------------------------------------------------
-- Static Popup Definitions
-- Blizzard's StaticPopup system is used for modal confirmations.
-- These are registered once at load time and shown on demand.
-------------------------------------------------------------------------------

-- COD acceptance confirmation dialog.
-- Shown when the player attempts to collect a COD mail via collect-all.
-- Displays the COD cost and lets the player accept or decline.
-- Both outcomes resume the mail queue so collection continues.
StaticPopupDialogs["MAILROOM_COD_CONFIRM"] = {
    text = "This mail requires a COD payment of %s. Accept and pay?",
    button1 = "Accept",
    button2 = "Skip",
    OnAccept = function(self, data)
        if data and data.index then
            -- Queue the COD acceptance as a priority operation.
            -- TakeInboxItem on a COD mail triggers the payment automatically.
            MR.Queue.Add(function()
                MR.TakeInboxItem(data.index, 1)
            end, true)
        end
        -- Resume the queue regardless of whether we accepted.
        MR.Queue.Resume()
    end,
    OnCancel = function()
        -- Player declined the COD — just resume the queue and skip it.
        MR.Queue.Resume()
    end,
    timeout = 0,       -- no auto-dismiss: player must choose
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3, -- avoid UI taint from shared popup slots
}

-------------------------------------------------------------------------------
-- Alert Functions
-------------------------------------------------------------------------------

-- Shows the COD confirmation dialog for a specific mail.
-- The queue should be paused before calling this; the dialog's
-- OnAccept and OnCancel callbacks will resume it.
-- @param index (number) The inbox index of the COD mail.
-- @param codAmount (number) The COD cost in copper.
function MR.Alerts:ShowCODConfirm(index, codAmount)
    local moneyText = MR.FormatMoney(codAmount)
    local dialog = StaticPopup_Show("MAILROOM_COD_CONFIRM", moneyText)
    if dialog then
        dialog.data = { index = index }
    end
end

-- Prints expiry warnings to chat for all mail expiring within the
-- configured threshold. Called when the mailbox is opened.
-- Each mail is listed with its subject, sender, and time remaining.
-- @param expiringMail (table) Array of mail info tables from
--                     MR.Inbox:GetExpiringMail().
function MR.Alerts:ShowExpiryWarnings(expiringMail)
    if #expiringMail == 0 then return end

    MR.Addon:Print("--- Expiring Mail (" .. #expiringMail .. ") ---")
    for _, info in ipairs(expiringMail) do
        -- daysLeft is a float (e.g., 1.5 = 1 day 12 hours).
        -- Show "< 1 day" for anything under 1, whole days otherwise.
        local dayText
        if info.daysLeft < 1 then
            dayText = "< 1 day"
        elseif info.daysLeft < 2 then
            dayText = "1 day"
        else
            dayText = math.floor(info.daysLeft) .. " days"
        end

        local subject = info.subject ~= "" and info.subject or "(no subject)"
        MR.Addon:Print(string.format("  %s from %s — %s left",
            subject, info.sender, dayText))
    end
end

-- Prints a summary of gold and items collected after a bulk collect
-- operation finishes. Called by the queue's onStop callback.
-- @param totalGold (number) Total copper collected (delta from before/after).
-- @param totalItems (number) Total number of item attachments collected.
function MR.Alerts:ShowCollectSummary(totalGold, totalItems)
    local parts = {}
    if totalGold > 0 then
        table.insert(parts, MR.FormatMoney(totalGold))
    end
    if totalItems > 0 then
        local itemText = totalItems == 1 and "1 item" or
            (totalItems .. " items")
        table.insert(parts, itemText)
    end

    if #parts > 0 then
        MR.Addon:Print("Collected: " .. table.concat(parts, ", "))
    else
        MR.Addon:Print("Collection complete.")
    end
end
