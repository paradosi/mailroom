-- Mailroom / Modules / BulkSelect.lua
-- Checkbox multi-selection on inbox rows with bulk action buttons.
-- Adds a checkbox overlay to each of the 7 visible MailItem buttons.
-- Supports Shift-click for range selection and Ctrl-click to select
-- all mail from the same sender. Selected mail can be collected,
-- returned, or deleted in bulk via the throttle queue.
--
-- All bulk operations process indices in reverse order (highest first)
-- to prevent index shifting from corrupting subsequent operations.
-- For example, deleting mail #5 before mail #3 means mail #3 still
-- points to the same item. If we deleted #3 first, the old #5 would
-- shift down to #4.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- BulkSelect Module
-------------------------------------------------------------------------------

MR.BulkSelect = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- The Blizzard inbox shows 7 mail items per page.
local INBOX_ROWS = 7

-- Highlight color for selected rows (semi-transparent gold).
local HIGHLIGHT_R, HIGHLIGHT_G, HIGHLIGHT_B, HIGHLIGHT_A = 1.0, 0.82, 0.0, 0.25

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local uiCreated      = false  -- true after checkboxes and buttons are built
local selected       = {}     -- set of selected inbox indices (1-based absolute, not row)
local lastClickIndex = nil    -- tracks the last clicked index for Shift range selection
local actionFrame    = nil    -- frame holding the bulk action buttons
local countText      = nil    -- fontstring showing "X selected"
local checkboxes     = {}     -- checkbox frames indexed 1-7 (per visible row)
local highlights     = {}     -- highlight textures indexed 1-7

-------------------------------------------------------------------------------
-- Selection Helpers
-------------------------------------------------------------------------------

-- Returns the absolute mail index for a given row (1-7) on the current page.
-- The Blizzard inbox uses InboxFrame.pageNum (0-based) to offset rows.
-- Row 1 on page 0 = index 1, row 1 on page 1 = index 8, etc.
-- @param row (number) Row number 1-7.
-- @return (number) The absolute inbox index for that row.
local function RowToIndex(row)
    local page = InboxFrame.pageNum or 0
    return (page * INBOX_ROWS) + row
end

-- Returns the row (1-7) for a given absolute index on the current page,
-- or nil if the index is not visible on the current page.
-- @param index (number) Absolute inbox index.
-- @return (number|nil) Row 1-7, or nil if not on current page.
local function IndexToRow(index)
    local page = InboxFrame.pageNum or 0
    local firstOnPage = (page * INBOX_ROWS) + 1
    local lastOnPage  = firstOnPage + INBOX_ROWS - 1
    if index >= firstOnPage and index <= lastOnPage then
        return index - firstOnPage + 1
    end
    return nil
end

-- Returns a sorted list of all selected indices in descending order.
-- Descending order is critical for bulk operations: processing higher
-- indices first means lower indices remain valid after each operation.
-- @return (table) Array of selected indices, highest first.
local function GetSelectedDescending()
    local result = {}
    for idx in pairs(selected) do
        table.insert(result, idx)
    end
    table.sort(result, function(a, b) return a > b end)
    return result
end

-- Returns the count of currently selected items.
-- @return (number) Number of selected mail items.
local function GetSelectedCount()
    local count = 0
    for _ in pairs(selected) do
        count = count + 1
    end
    return count
end

-- Clears all selections and resets visual state.
local function ClearSelection()
    wipe(selected)
    lastClickIndex = nil
end

-------------------------------------------------------------------------------
-- Visual Updates
-- Synchronizes checkbox state and row highlights with the selected table.
-- Called after any selection change and on page turns.
-------------------------------------------------------------------------------

-- Updates all 7 row checkboxes and highlights to reflect current selection.
local function RefreshVisuals()
    local numItems = MR.GetInboxNumItems()
    local count = GetSelectedCount()

    for row = 1, INBOX_ROWS do
        local idx = RowToIndex(row)
        local cb = checkboxes[row]
        local hl = highlights[row]

        if cb then
            if idx <= numItems then
                cb:Show()
                cb:SetChecked(selected[idx] or false)
            else
                cb:Hide()
                cb:SetChecked(false)
            end
        end

        if hl then
            if selected[idx] then
                hl:Show()
            else
                hl:Hide()
            end
        end
    end

    -- Update the count text and show/hide action buttons.
    if countText then
        if count > 0 then
            countText:SetText(count .. " selected")
            countText:Show()
        else
            countText:SetText("")
            countText:Hide()
        end
    end

    if actionFrame then
        if count > 0 then
            actionFrame:Show()
        else
            actionFrame:Hide()
        end
    end
end

-------------------------------------------------------------------------------
-- Click Handlers
-- Handle plain click, Shift-click (range), and Ctrl-click (same sender).
-------------------------------------------------------------------------------

-- Handles a checkbox click for a given row.
-- Plain click: toggles the single index.
-- Shift-click: selects/deselects the range between lastClickIndex and this one.
-- Ctrl-click: selects all mail from the same sender as this row's mail.
-- @param row (number) The row (1-7) that was clicked.
local function OnCheckboxClick(row)
    local idx = RowToIndex(row)
    local numItems = MR.GetInboxNumItems()
    if idx > numItems then return end

    if IsShiftKeyDown() and lastClickIndex then
        -- Range selection: select everything between the last click and this click.
        -- We add to existing selection rather than replacing, matching standard
        -- file-manager behavior where Shift extends the selection.
        local lo = math.min(lastClickIndex, idx)
        local hi = math.max(lastClickIndex, idx)
        for i = lo, hi do
            if i <= numItems then
                selected[i] = true
            end
        end
    elseif IsControlKeyDown() then
        -- Same-sender selection: find the sender for this mail and select
        -- all mail from that sender across the entire inbox.
        local info = MR.mailCache[idx]
        if info and info.sender then
            local targetSender = info.sender
            for i = 1, numItems do
                local mailInfo = MR.mailCache[i]
                if mailInfo and mailInfo.sender == targetSender then
                    selected[i] = true
                end
            end
        end
    else
        -- Plain toggle: flip this single index.
        if selected[idx] then
            selected[idx] = nil
        else
            selected[idx] = true
        end
    end

    lastClickIndex = idx
    RefreshVisuals()
end

-------------------------------------------------------------------------------
-- Bulk Action Handlers
-- Each action builds a list of operations and feeds them into MR.Queue
-- in reverse index order. Reverse order prevents index corruption:
-- taking mail at index 7 does not affect indices 1-6, but taking mail
-- at index 3 would shift everything above it down by one.
-------------------------------------------------------------------------------

-- Queues collection of all money and items from selected mail.
-- For each selected mail (in descending index order), queues TakeInboxMoney
-- if gold is present, then TakeInboxItem for each attachment slot.
local function CollectSelected()
    local indices = GetSelectedDescending()
    if #indices == 0 then return end

    for _, idx in ipairs(indices) do
        local info = MR.mailCache[idx]
        if info then
            -- Queue money collection first, then items.
            if info.money and info.money > 0 then
                local capturedIdx = idx
                MR.Queue.Add(function()
                    MR.TakeInboxMoney(capturedIdx)
                end)
            end

            if info.hasItem then
                -- GetInboxNumItems returns the attachment count for a specific
                -- mail when called with the mail index. However, the hasItem
                -- field from GetInboxHeaderInfo gives us the attachment count
                -- directly. We iterate from ATTACHMENTS_MAX_SEND (or hasItem
                -- count) down to 1 to collect all slots.
                local numAttach = info.hasItem
                if type(numAttach) == "number" and numAttach > 0 then
                    for slot = 1, numAttach do
                        local capturedIdx2 = idx
                        local capturedSlot = slot
                        MR.Queue.Add(function()
                            MR.TakeInboxItem(capturedIdx2, capturedSlot)
                        end)
                    end
                end
            end
        end
    end

    ClearSelection()
    RefreshVisuals()
    MR.Addon:Print("Collecting " .. #indices .. " selected mail.")
end

-- Queues return-to-sender for all selected mail.
-- Only player-sent, non-returned mail can be returned. System mail and
-- already-returned mail are silently skipped with a warning.
local function ReturnSelected()
    local indices = GetSelectedDescending()
    if #indices == 0 then return end

    local returnCount = 0
    local skipCount = 0

    for _, idx in ipairs(indices) do
        local info = MR.mailCache[idx]
        if info then
            local mailType = MR.ClassifyMail(info)
            -- Only player mail that hasn't already been returned can be sent back.
            -- AH, system, and GM mail have no valid return address.
            if mailType == "player" and not info.wasReturned then
                local capturedIdx = idx
                MR.Queue.Add(function()
                    MR.ReturnInboxItem(capturedIdx)
                end)
                returnCount = returnCount + 1
            else
                skipCount = skipCount + 1
            end
        end
    end

    ClearSelection()
    RefreshVisuals()

    local msg = "Returning " .. returnCount .. " mail."
    if skipCount > 0 then
        msg = msg .. " Skipped " .. skipCount .. " (system/AH/already returned)."
    end
    MR.Addon:Print(msg)
end

-- Queues deletion of all selected mail.
-- Only mail with no remaining attachments or gold can be deleted. Mail
-- that still has items or money is skipped to prevent accidental data loss.
local function DeleteSelected()
    local indices = GetSelectedDescending()
    if #indices == 0 then return end

    local deleteCount = 0
    local skipCount = 0

    for _, idx in ipairs(indices) do
        local info = MR.mailCache[idx]
        if info then
            -- DeleteInboxItem only works on mail with no remaining attachments
            -- or gold. Attempting to delete mail with items silently fails.
            local hasStuff = (info.money and info.money > 0) or info.hasItem
            if not hasStuff then
                local capturedIdx = idx
                MR.Queue.Add(function()
                    MR.DeleteInboxItem(capturedIdx)
                end)
                deleteCount = deleteCount + 1
            else
                skipCount = skipCount + 1
            end
        end
    end

    ClearSelection()
    RefreshVisuals()

    local msg = "Deleting " .. deleteCount .. " empty mail."
    if skipCount > 0 then
        msg = msg .. " Skipped " .. skipCount .. " (still have items/gold)."
    end
    MR.Addon:Print(msg)
end

-------------------------------------------------------------------------------
-- UI Creation
-- Builds checkboxes on each MailItem row, highlight textures for selection
-- feedback, and the action button bar for bulk operations.
-------------------------------------------------------------------------------

-- Creates all UI elements: checkboxes, highlights, action buttons, count text.
-- Called once on first MAIL_SHOW. Subsequent calls are no-ops.
local function CreateUI()
    if uiCreated then return end
    uiCreated = true

    -- Create checkboxes and highlights on each of the 7 inbox rows.
    for row = 1, INBOX_ROWS do
        local mailButton = _G["MailItem" .. row .. "Button"]
        if mailButton then
            -- Checkbox: positioned on the left side of the row, offset slightly
            -- so it doesn't overlap the mail icon.
            local cb = CreateFrame("CheckButton", "MailroomBulkCB" .. row,
                mailButton, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("LEFT", mailButton, "LEFT", 2, 0)
            cb:SetFrameLevel(mailButton:GetFrameLevel() + 2)

            -- We capture the row number in the closure so the click handler
            -- knows which row was activated.
            local capturedRow = row
            cb:SetScript("OnClick", function()
                OnCheckboxClick(capturedRow)
            end)

            checkboxes[row] = cb

            -- Highlight: a full-width semi-transparent gold overlay behind
            -- the row to visually indicate selection.
            local hl = mailButton:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(mailButton)
            hl:SetColorTexture(HIGHLIGHT_R, HIGHLIGHT_G, HIGHLIGHT_B, HIGHLIGHT_A)
            hl:SetDrawLayer("BACKGROUND", 1)
            hl:Hide()
            highlights[row] = hl
        end
    end

    -- Action button bar: sits below the inbox list, shows when items are selected.
    actionFrame = CreateFrame("Frame", "MailroomBulkActions", InboxFrame)
    actionFrame:SetSize(320, 30)
    actionFrame:SetPoint("BOTTOM", InboxFrame, "BOTTOM", 0, 6)
    actionFrame:Hide()

    -- Collect Selected button.
    local collectBtn = CreateFrame("Button", "MailroomBulkCollect",
        actionFrame, "UIPanelButtonTemplate")
    collectBtn:SetSize(100, 24)
    collectBtn:SetPoint("LEFT", actionFrame, "LEFT", 0, 0)
    collectBtn:SetText("Collect")
    collectBtn:SetScript("OnClick", CollectSelected)

    -- Return Selected button.
    local returnBtn = CreateFrame("Button", "MailroomBulkReturn",
        actionFrame, "UIPanelButtonTemplate")
    returnBtn:SetSize(100, 24)
    returnBtn:SetPoint("LEFT", collectBtn, "RIGHT", 4, 0)
    returnBtn:SetText("Return")
    returnBtn:SetScript("OnClick", ReturnSelected)

    -- Delete Selected button.
    local deleteBtn = CreateFrame("Button", "MailroomBulkDelete",
        actionFrame, "UIPanelButtonTemplate")
    deleteBtn:SetSize(100, 24)
    deleteBtn:SetPoint("LEFT", returnBtn, "RIGHT", 4, 0)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", DeleteSelected)

    -- Selection count text: positioned to the right of the action buttons.
    countText = actionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("LEFT", deleteBtn, "RIGHT", 8, 0)
    countText:SetTextColor(1, 0.82, 0)
    countText:Hide()

    -- Hook page navigation so selection visuals update when the player
    -- changes inbox pages. The checkboxes represent absolute indices, not
    -- rows, so we need to re-check which checkboxes should be ticked.
    if InboxNextPageButton then
        InboxNextPageButton:HookScript("OnClick", RefreshVisuals)
    end
    if InboxPrevPageButton then
        InboxPrevPageButton:HookScript("OnClick", RefreshVisuals)
    end
end

-------------------------------------------------------------------------------
-- Module Lifecycle (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Called when the mailbox opens. Creates UI if needed and resets selection.
function MR.BulkSelect:OnMailShow()
    if not MR.Addon.db.profile.bulkSelectEnabled then return end

    CreateUI()
    ClearSelection()
    RefreshVisuals()
end

-- Called when the mailbox closes. Clears selection and hides action buttons.
function MR.BulkSelect:OnMailClosed()
    ClearSelection()
    RefreshVisuals()
end

-- Called on MAIL_INBOX_UPDATE. Refreshes visuals because mail indices may
-- have shifted (items taken, mail deleted, new mail arrived).
function MR.BulkSelect:OnMailInboxUpdate()
    if not MR.Addon.db.profile.bulkSelectEnabled then return end

    -- Prune selections that reference indices beyond the current mail count.
    -- This handles the case where mail was deleted or collected, reducing
    -- the total count below a previously selected index.
    local numItems = MR.GetInboxNumItems()
    for idx in pairs(selected) do
        if idx > numItems then
            selected[idx] = nil
        end
    end

    RefreshVisuals()
end
