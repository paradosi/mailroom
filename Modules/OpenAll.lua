-- Mailroom / Modules / OpenAll.lua
-- Smart open-all button with mail type filtering and bag protection.
-- Identifies mail by type (AH, Postmaster, COD, player) and applies
-- per-type toggles from settings. Checks free bag slots before each
-- item take and pauses the queue when the threshold is breached.
-- Holding Shift while clicking bypasses all type filters.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- OpenAll Module
-------------------------------------------------------------------------------

MR.OpenAll = {}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local buttonsCreated = false
local collectBtn = nil
local openBtn = nil
local statusText = nil

-------------------------------------------------------------------------------
-- Bag Space Check
-- Called before each item-take operation to ensure the player has
-- enough free bag slots. If slots are below the configured minimum,
-- the queue pauses and the player is notified.
-------------------------------------------------------------------------------

-- Checks if there are enough free bag slots to continue collecting.
-- Pauses the queue and notifies the player if slots are too low.
-- @return (boolean) True if collection can proceed.
local function CheckBagSpace()
    local minFree = MR.Addon.db.profile.minFreeBagSlots
    local free = MR.GetFreeBagSlots()
    if free <= minFree then
        MR.Queue.Pause()
        MR.Addon:Print("Bags nearly full (" .. free .. " free). Collection paused.")
        return false
    end
    return true
end

-------------------------------------------------------------------------------
-- Mail Type Filter
-- Determines whether a given mail should be collected based on the
-- player's per-type settings. Shift-click bypasses all filters.
-------------------------------------------------------------------------------

-- Checks whether a mail entry should be collected given current settings.
-- @param info (table) A mail info table from MR.mailCache.
-- @param forceAll (boolean) If true, skip all type filters (Shift-click).
-- @return (boolean) True if this mail should be collected.
local function ShouldCollect(info, forceAll)
    if forceAll then return true end

    local db = MR.Addon.db.profile
    local mailType = MR.ClassifyMail(info)

    if mailType == "cod" and db.skipCOD then
        return false
    elseif mailType == "ah" and not db.collectAH then
        return false
    elseif mailType == "postmaster" and not db.collectPostmaster then
        return false
    elseif mailType == "player" then
        -- Player mail may have items, gold, or both.
        if info.hasItem and not db.collectItems then
            return false
        end
        if info.money > 0 and not info.hasItem and not db.collectGold then
            return false
        end
    end

    return true
end

-------------------------------------------------------------------------------
-- Collect All
-- Builds and enqueues operations for all eligible mail.
-------------------------------------------------------------------------------

-- Queues operations to collect all money and items from eligible mail.
-- @param forceAll (boolean) If true, ignores type filters (Shift-click).
function MR.OpenAll:CollectAll(forceAll)
    if not MR.Addon.db.profile.openAllEnabled then
        MR.Addon:Print("Open All is disabled in settings.")
        return
    end

    local numItems = MR.GetInboxNumItems()
    if numItems == 0 then
        MR.Addon:Print("No mail to collect.")
        return
    end

    local deleteEmpty = MR.Addon.db.profile.deleteEmpty
    local opsQueued = 0

    -- Process in reverse order to avoid index corruption from deletes.
    for i = numItems, 1, -1 do
        local info = MR.mailCache[i]
        if not info then
            -- Mail not cached yet, skip.
        elseif not ShouldCollect(info, forceAll) then
            -- Filtered out by type settings.
        else
            -- Collect money if present.
            if info.money > 0 then
                local idx = i
                MR.Queue.Add(function()
                    MR.TakeInboxMoney(idx)
                end)
                opsQueued = opsQueued + 1
            end

            -- Collect items if present. We check bag space before each take
            -- and always take from slot 1 (items shift down as taken).
            if info.hasItem then
                local idx = i
                local INBOX_ITEM_MAX = 12
                for slot = 1, INBOX_ITEM_MAX do
                    MR.Queue.Add(function()
                        if not CheckBagSpace() then return end
                        local name = MR.GetInboxItem(idx, 1)
                        if name then
                            MR.TakeInboxItem(idx, 1)
                        end
                    end)
                    opsQueued = opsQueued + 1
                end
            end

            -- Delete empty mail after collecting.
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
        MR.Addon:Print("No collectible mail (check type filters in settings).")
        return
    end

    MR.Addon:Print("Collecting from " .. numItems .. " mail(s)...")
end

-------------------------------------------------------------------------------
-- Open All (Read Only)
-- Marks all unread mail as read without collecting anything.
-------------------------------------------------------------------------------

-- Queues operations to mark all unread mail as read.
function MR.OpenAll:ReadAll()
    local numItems = MR.GetInboxNumItems()
    if numItems == 0 then
        MR.Addon:Print("No mail to open.")
        return
    end

    local count = 0
    for i = numItems, 1, -1 do
        local info = MR.mailCache[i]
        if info and not info.wasRead then
            local idx = i
            MR.Queue.Add(function()
                MR.GetInboxText(idx)
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
-- UI: Buttons and Status
-------------------------------------------------------------------------------

-- Updates the status text with inbox summary.
local function UpdateStatus()
    if not statusText then return end

    local cache = MR.mailCache
    local count = #cache
    local totalGold = 0
    for _, info in ipairs(cache) do
        totalGold = totalGold + info.money
    end

    local parts = { count .. " mail" }
    if totalGold > 0 then
        table.insert(parts, MR.FormatMoney(totalGold))
    end
    statusText:SetText(table.concat(parts, "  |  "))
end

-- Creates the Collect All, Open All buttons and status text.
local function CreateButtons()
    if buttonsCreated then return end
    buttonsCreated = true

    -- Collect All button.
    collectBtn = CreateFrame("Button", "MailroomCollectAllButton",
        InboxFrame, "UIPanelButtonTemplate")
    collectBtn:SetSize(120, 25)
    collectBtn:SetPoint("BOTTOM", InboxFrame, "BOTTOM", -65, 100)
    collectBtn:SetText("Collect All")
    collectBtn:SetScript("OnClick", function()
        if MR.Queue.IsRunning() then
            MR.Queue.Clear()
            MR.Addon:Print("Collection cancelled.")
        else
            -- Shift-click bypasses all type filters.
            local forceAll = IsShiftKeyDown()
            MR.OpenAll:CollectAll(forceAll)
        end
    end)

    -- Open All button (read only, no collecting).
    openBtn = CreateFrame("Button", "MailroomOpenAllButton",
        InboxFrame, "UIPanelButtonTemplate")
    openBtn:SetSize(120, 25)
    openBtn:SetPoint("BOTTOM", InboxFrame, "BOTTOM", 65, 100)
    openBtn:SetText("Open All")
    openBtn:SetScript("OnClick", function()
        if MR.Queue.IsRunning() then
            MR.Queue.Clear()
            MR.Addon:Print("Cancelled.")
        else
            MR.OpenAll:ReadAll()
        end
    end)

    -- Status text.
    statusText = InboxFrame:CreateFontString(nil, "OVERLAY",
        "GameFontNormalSmall")
    statusText:SetPoint("BOTTOM", InboxFrame, "BOTTOM", 0, 84)
    statusText:SetTextColor(0.8, 0.8, 0.8)

    -- Queue callbacks update button text.
    MR.Queue.onStart = function()
        collectBtn:SetText("Cancel")
    end
    MR.Queue.onStop = function()
        collectBtn:SetText("Collect All")
        UpdateStatus()
    end
    MR.Queue.onProgress = function(remaining, total)
        if total > 0 then
            collectBtn:SetText("Cancel (" .. remaining .. ")")
        end
    end
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

function MR.OpenAll:OnMailShow()
    if not MR.Addon.db.profile.openAllEnabled then return end
    CreateButtons()
    UpdateStatus()
end

function MR.OpenAll:OnMailInboxUpdate()
    if not MR.Addon.db.profile.openAllEnabled then return end
    UpdateStatus()
end
