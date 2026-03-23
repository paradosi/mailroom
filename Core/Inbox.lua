-- Mailroom / Inbox.lua
-- Inbox scanning, caching, and bulk mail operations.
-- Scans the inbox on MAIL_INBOX_UPDATE, caches header info locally,
-- and provides Open All / Collect All actions that feed operations
-- into MailQueue for throttled execution.
--
-- Index management: WoW mail indices are 1-based and shift downward
-- when a mail is deleted (removing index 3 makes old index 4 become 3).
-- However, indices do NOT shift when items/money are taken from a mail —
-- the mail stays in place but becomes "empty". We process in reverse
-- order (highest index first) so that deletes don't corrupt the indices
-- of mails we haven't processed yet.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Inbox Module
-------------------------------------------------------------------------------

MR.Inbox = {}

-------------------------------------------------------------------------------
-- Inbox Cache
-- Stores scanned mail headers so we can display inbox info, filter by
-- sender/subject, and check expiry without repeatedly querying the API.
-- Refreshed on every MAIL_INBOX_UPDATE event.
-------------------------------------------------------------------------------

local mailCache = {}

-------------------------------------------------------------------------------
-- Collect Tracking
-- Tracks gold and item counts before and after a collect-all operation
-- so we can show a summary when the queue finishes.
-------------------------------------------------------------------------------

local collectTracker = {
    goldBefore  = 0,  -- player's gold (copper) when collect started
    itemCount   = 0,  -- number of item-take operations queued
    moneyCount  = 0,  -- number of money-take operations queued
    active      = false,
}

-------------------------------------------------------------------------------
-- Scanning
-------------------------------------------------------------------------------

-- Scans all mail currently loaded in the inbox and caches header info.
-- Called on MAIL_INBOX_UPDATE. The cache is wiped and rebuilt each time
-- because mail indices shift as items are taken or deleted, making
-- incremental updates unreliable.
function MR.Inbox:ScanInbox()
    wipe(mailCache)

    local numItems = MR.GetInboxNumItems()
    for i = 1, numItems do
        local packageIcon, stationeryIcon, sender, subject, money,
              CODAmount, daysLeft, hasItem, wasRead, wasReturned,
              textCreated, canReply, isGM = MR.GetInboxHeaderInfo(i)

        mailCache[i] = {
            index        = i,
            sender       = sender or "Unknown",
            subject      = subject or "",
            money        = money or 0,
            CODAmount    = CODAmount or 0,
            daysLeft     = daysLeft or 0,
            hasItem      = hasItem,
            wasRead      = wasRead,
            wasReturned  = wasReturned,
            isGM         = isGM,
            packageIcon  = packageIcon,
        }
    end

    return mailCache
end

-- Returns the cached mail data.
-- @return (table) Array of mail info tables indexed by inbox position.
function MR.Inbox:GetCache()
    return mailCache
end

-- Returns the number of cached mail entries.
-- @return (number) Count of cached mails.
function MR.Inbox:GetCount()
    return #mailCache
end

-------------------------------------------------------------------------------
-- Bulk Operations
-- These functions build a list of queue operations and feed them into
-- MR.Queue. Operations are added in reverse index order (highest index
-- first) because taking mail at index N does not shift indices above N,
-- but does shift indices below it. Processing from the top down avoids
-- index corruption when deleteEmpty is enabled.
-------------------------------------------------------------------------------

-- Queues operations to collect all money and items from all inbox mail.
-- Skips COD mail if the user has skipCOD enabled. When skipCOD is off,
-- COD mail triggers a confirmation dialog via MR.Alerts instead of
-- being silently accepted.
-- Processes from highest index to lowest to avoid index shifting issues.
function MR.Inbox:CollectAll()
    local numItems = MR.GetInboxNumItems()
    if numItems == 0 then
        MR.Addon:Print("No mail to collect.")
        return
    end

    local skipCOD = MR.Addon.db.profile.skipCOD
    local deleteEmpty = MR.Addon.db.profile.deleteEmpty

    -- Initialize collect tracking so we can show a summary when done.
    collectTracker.goldBefore = GetMoney()
    collectTracker.itemCount = 0
    collectTracker.moneyCount = 0
    collectTracker.active = true

    local opsQueued = 0

    -- Process in reverse order. We capture each index value in a closure
    -- at queue-add time so the closure holds the correct index regardless
    -- of when it actually executes.
    for i = numItems, 1, -1 do
        local info = mailCache[i]
        if not info then
            -- Mail may not be cached if MAIL_INBOX_UPDATE hasn't fired yet.
            -- Skip rather than error.
        elseif info.CODAmount > 0 then
            -- COD mail handling:
            -- If skipCOD is on, we silently skip this mail.
            -- If skipCOD is off, we pause the queue and show a confirmation
            -- dialog. The player can accept (which queues the take as a
            -- priority op) or decline (which resumes the queue without it).
            if not skipCOD then
                local idx = i
                local codAmt = info.CODAmount
                MR.Queue.Add(function()
                    -- Pause the queue while the dialog is open. The dialog's
                    -- OnAccept/OnCancel callbacks will resume it.
                    MR.Queue.Pause()
                    MR.Alerts:ShowCODConfirm(idx, codAmt)
                end)
                opsQueued = opsQueued + 1
            end
        else
            -- Normal mail: collect money, then items, then optionally delete.

            -- Collect money if present.
            if info.money > 0 then
                local idx = i
                MR.Queue.Add(function()
                    MR.TakeInboxMoney(idx)
                end)
                opsQueued = opsQueued + 1
                collectTracker.moneyCount = collectTracker.moneyCount + 1
            end

            -- Collect items if present. We check each attachment slot at
            -- execution time because the slot contents may have changed
            -- since the operation was queued (e.g., another addon took an
            -- item). Slot 1 is always tried first; after each take the
            -- remaining items shift down into lower slots.
            if info.hasItem then
                local idx = i
                -- INBOX_ITEM_MAX: maximum attachment slots per mail.
                -- This is 12 on Retail and Classic.
                local INBOX_ITEM_MAX = 12
                for slot = 1, INBOX_ITEM_MAX do
                    MR.Queue.Add(function()
                        -- Check if there's still an item in slot 1.
                        -- We always take from slot 1 because items shift
                        -- down as they're removed.
                        local name = MR.GetInboxItem(idx, 1)
                        if name then
                            MR.TakeInboxItem(idx, 1)
                            collectTracker.itemCount = collectTracker.itemCount + 1
                        end
                    end)
                    opsQueued = opsQueued + 1
                end
            end

            -- Delete empty mail after collecting, if the preference is set.
            -- This runs after all takes for this mail index, so the mail
            -- should be empty by this point. DeleteInboxItem only works on
            -- mail with no remaining attachments or gold.
            if deleteEmpty then
                local idx = i
                MR.Queue.Add(function()
                    MR.DeleteInboxItem(idx)
                end)
                opsQueued = opsQueued + 1
            end
        end
    end

    if opsQueued == 0 then
        MR.Addon:Print("No collectible mail found.")
        collectTracker.active = false
        return
    end

    -- Set up the queue completion callback to show the collect summary.
    local previousOnStop = MR.Queue.onStop
    MR.Queue.onStop = function()
        if collectTracker.active then
            local goldAfter = GetMoney()
            local goldCollected = goldAfter - collectTracker.goldBefore
            if goldCollected < 0 then goldCollected = 0 end

            MR.Alerts:ShowCollectSummary(goldCollected, collectTracker.itemCount)
            collectTracker.active = false
        end

        -- Restore the previous onStop (the button text updater from MailFrame).
        if previousOnStop then
            previousOnStop()
        end
    end

    MR.Addon:Print("Collecting from " .. numItems .. " mail(s)...")
end

-- Queues operations to open (read) all mail without collecting.
-- "Opening" mail means calling GetInboxText which marks the mail as
-- read on the server. This is useful to stop the "new mail" indicator
-- without actually taking anything. Processes in reverse order for
-- consistency with CollectAll.
function MR.Inbox:OpenAll()
    local numItems = MR.GetInboxNumItems()
    if numItems == 0 then
        MR.Addon:Print("No mail to open.")
        return
    end

    local count = 0
    for i = numItems, 1, -1 do
        local info = mailCache[i]
        -- Only open mail that hasn't been read yet.
        if info and not info.wasRead then
            local idx = i
            MR.Queue.Add(function()
                -- GetInboxText marks the mail as read server-side.
                -- The body text itself is discarded; we only care about
                -- the read-state side effect.
                GetInboxText(idx)
            end)
            count = count + 1
        end
    end

    if count == 0 then
        MR.Addon:Print("All mail already read.")
    else
        MR.Addon:Print("Opening " .. count .. " unread mail(s)...")
    end
end

-------------------------------------------------------------------------------
-- Expiry Warnings
-------------------------------------------------------------------------------

-- Returns a list of cached mails that will expire within the configured
-- warning threshold.
-- @return (table) Array of mail info tables for expiring mail.
function MR.Inbox:GetExpiringMail()
    local threshold = MR.Addon.db.profile.expiryWarningDays
    local expiring = {}

    for _, info in ipairs(mailCache) do
        if info.daysLeft > 0 and info.daysLeft <= threshold then
            table.insert(expiring, info)
        end
    end

    return expiring
end

-------------------------------------------------------------------------------
-- Filtering
-- Provides search/filter over the cached inbox for UI display.
-------------------------------------------------------------------------------

-- Searches the mail cache for entries matching a query string.
-- Matches against sender name and subject line (case-insensitive).
-- @param query (string) The search string.
-- @return (table) Array of matching mail info tables.
function MR.Inbox:Search(query)
    if not query or query == "" then
        return mailCache
    end

    local results = {}
    local lowerQuery = strlower(query)

    for _, info in ipairs(mailCache) do
        if strlower(info.sender):find(lowerQuery, 1, true) or
           strlower(info.subject):find(lowerQuery, 1, true) then
            table.insert(results, info)
        end
    end

    return results
end

-------------------------------------------------------------------------------
-- Event Handlers
-- Registered in MailFrame.lua when the mail frame is shown.
-------------------------------------------------------------------------------

-- Called when MAIL_INBOX_UPDATE fires. Re-scans the inbox to keep the
-- cache fresh. This event fires after mail is opened, taken, deleted,
-- or when new mail arrives while the mailbox is open.
function MR.Inbox:OnMailInboxUpdate()
    self:ScanInbox()
end
