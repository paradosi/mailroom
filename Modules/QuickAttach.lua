-- Mailroom / Modules / QuickAttach.lua
-- Category-based item attachment buttons on the send mail frame.
-- Creates a row of small category buttons (Cloth, Leather, Herbs, etc.)
-- near the send frame's attachment area. Left-clicking a category opens
-- a scrollable item picker showing matching items from the player's bags.
-- Clicking an item in the picker attaches it to the outgoing mail.
--
-- Right-clicking a category button opens an EditBox to set a default
-- recipient for that category, stored in db.profile.quickAttachRecipients.
-- This is useful for players who regularly send materials to a crafting alt.
--
-- Item matching uses GetItemInfoInstant's classID and subClassID to
-- categorize bag items. The TRADE_GOODS_CATEGORIES table maps each
-- button label to the corresponding Enum.ItemClass values.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- QuickAttach Module
-------------------------------------------------------------------------------

MR.QuickAttach = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Trade goods class/subclass mapping.
-- Enum.ItemClass values: 7 = Tradeskill (trade goods).
-- Subclass IDs within class 7 vary by expansion but the core ones are stable.
-- We use GetItemInfoInstant which returns classID, subclassID directly.
--
-- Subclass reference (trade goods, class 7):
--   5  = Cloth
--   6  = Leather
--   9  = Herb
--   7  = Metal & Stone (ore)
--   4  = Jewelcrafting (gems)
--   12 = Enchanting
--   8  = Cooking (includes fish in some expansions)
-- On Classic, some subclass IDs differ slightly but the broad categories hold.
local TRADE_GOODS_CATEGORIES = {
    { label = "Cloth",     classID = 7, subclassIDs = { [5] = true } },
    { label = "Leather",   classID = 7, subclassIDs = { [6] = true } },
    { label = "Herbs",     classID = 7, subclassIDs = { [9] = true } },
    { label = "Ore",       classID = 7, subclassIDs = { [7] = true } },
    { label = "Gems",      classID = 7, subclassIDs = { [4] = true } },
    { label = "Enchanting", classID = 7, subclassIDs = { [12] = true } },
    { label = "Fish",      classID = 7, subclassIDs = { [8] = true } },
}

-- Maximum number of item slots visible in the picker at once.
local PICKER_VISIBLE_ROWS = 8

-- Size of each item row in the picker.
local PICKER_ROW_HEIGHT = 28

-- Size of each category button.
local CAT_BUTTON_WIDTH  = 60
local CAT_BUTTON_HEIGHT = 22

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local uiCreated       = false
local categoryButtons = {}    -- array of category button frames
local pickerFrame     = nil   -- the scrollable item picker frame
local pickerButtons   = {}    -- item row buttons inside the picker
local recipientFrame  = nil   -- small EditBox frame for setting default recipient
local recipientEditBox = nil
local activeCategory  = nil   -- currently open category (table from TRADE_GOODS_CATEGORIES)

-------------------------------------------------------------------------------
-- Bag Scanning
-- Searches all player bags for items matching a given category's class
-- and subclass IDs. Returns a list of items with enough info to display
-- and attach them.
-------------------------------------------------------------------------------

-- Scans bags for items matching the given category definition.
-- Uses GetContainerNumSlots and GetContainerItemInfo (via C_Container
-- on Retail) to iterate all bag slots, then GetItemInfoInstant to check
-- item class/subclass without requiring a server query.
-- @param category (table) A category entry from TRADE_GOODS_CATEGORIES.
-- @return (table) Array of { bag, slot, itemID, name, texture, count, quality }.
local function ScanBagsForCategory(category)
    local results = {}
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemInfo = (C_Container and C_Container.GetContainerItemInfo) or nil

    for bag = 0, MR.NUM_BAG_SLOTS do
        local numSlots = getNumSlots(bag) or 0
        for slot = 1, numSlots do
            local itemID, name, texture, count, quality

            if getItemInfo then
                -- Retail / modern client: C_Container.GetContainerItemInfo
                -- returns a table with named fields.
                local info = getItemInfo(bag, slot)
                if info then
                    itemID  = info.itemID
                    name    = info.itemName or ""
                    texture = info.iconFileID
                    count   = info.stackCount or 1
                    quality = info.quality or 0

                    -- On some clients itemName may be nil if the item hasn't
                    -- been cached yet. Fall back to GetItemInfo for the name.
                    if (not name or name == "") and itemID then
                        name = GetItemInfo(itemID) or ""
                    end
                end
            else
                -- Classic: GetContainerItemInfo returns positional values.
                -- texture, count, locked, quality, readable, lootable, link, filtered, noValue, itemID
                local tex, cnt, _, qual, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
                if id then
                    itemID  = id
                    texture = tex
                    count   = cnt or 1
                    quality = qual or 0
                    name    = GetItemInfo(id) or ""
                end
            end

            -- Check if this item matches the category.
            if itemID then
                local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
                if classID == category.classID and category.subclassIDs[subclassID] then
                    table.insert(results, {
                        bag     = bag,
                        slot    = slot,
                        itemID  = itemID,
                        name    = name or "",
                        texture = texture,
                        count   = count or 1,
                        quality = quality or 0,
                    })
                end
            end
        end
    end

    -- Sort by item name for consistent display.
    table.sort(results, function(a, b) return a.name < b.name end)
    return results
end

-------------------------------------------------------------------------------
-- Item Picker Frame
-- A scrollable list of items matching the active category. Clicking an
-- item uses ClickSendMailItemButton to attach it to the outgoing mail.
-------------------------------------------------------------------------------

-- Creates the picker frame (once). Positioned below the category buttons.
local function CreatePickerFrame()
    if pickerFrame then return end

    pickerFrame = CreateFrame("Frame", "MailroomQuickAttachPicker",
        SendMailFrame, "BasicFrameTemplateWithInset")
    pickerFrame:SetSize(220, (PICKER_VISIBLE_ROWS * PICKER_ROW_HEIGHT) + 44)
    pickerFrame:SetPoint("TOPLEFT", SendMailFrame, "TOPRIGHT", 2, 0)
    pickerFrame:SetFrameStrata("DIALOG")
    pickerFrame:Hide()

    -- Title.
    local title = pickerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", pickerFrame, "TOP", 0, -6)
    title:SetText("Select Item")

    -- Scroll frame.
    local scrollFrame = CreateFrame("ScrollFrame", "MailroomQAPScroll",
        pickerFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", 8, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", pickerFrame, "BOTTOMRIGHT", -28, 8)

    -- Content frame inside the scroll.
    local content = CreateFrame("Frame", "MailroomQAPContent", scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)  -- height set dynamically
    scrollFrame:SetScrollChild(content)

    pickerFrame.scrollFrame = scrollFrame
    pickerFrame.content = content
end

-- Populates the picker with items matching the active category.
-- Clears all existing item buttons and creates new ones.
local function PopulatePicker()
    if not pickerFrame then return end
    if not activeCategory then return end

    -- Clear existing buttons.
    for _, btn in ipairs(pickerButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(pickerButtons)

    local items = ScanBagsForCategory(activeCategory)
    local content = pickerFrame.content

    -- Update title to show category name.
    local titleFS = pickerFrame:GetRegions()
    if titleFS and titleFS.SetText then
        titleFS:SetText(activeCategory.label)
    end

    if #items == 0 then
        -- No matching items: show a message.
        local noItems = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        noItems:SetPoint("TOP", content, "TOP", 0, -10)
        noItems:SetText("No matching items in bags")
        -- Store it so we can clean it up next time.
        local dummyBtn = CreateFrame("Frame", nil, content)
        dummyBtn:SetSize(1, 1)
        dummyBtn.label = noItems
        table.insert(pickerButtons, dummyBtn)
        content:SetHeight(PICKER_ROW_HEIGHT)
        return
    end

    content:SetHeight(#items * PICKER_ROW_HEIGHT)

    for i, item in ipairs(items) do
        local row = CreateFrame("Button", nil, content)
        row:SetSize(content:GetWidth() - 4, PICKER_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -((i - 1) * PICKER_ROW_HEIGHT))

        -- Item icon.
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        if item.texture then
            icon:SetTexture(item.texture)
        end

        -- Item name and count.
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        local displayText = item.name
        if item.count > 1 then
            displayText = displayText .. " x" .. item.count
        end
        label:SetText(displayText)

        -- Color by quality.
        local r, g, b = GetItemQualityColor(item.quality or 0)
        if r then
            label:SetTextColor(r, g, b)
        end

        -- Highlight on hover.
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(row)
        highlight:SetColorTexture(1, 1, 1, 0.1)

        -- Click handler: uses ClickSendMailItemButton with UseContainerItem
        -- to attach the item to the outgoing mail. ClickSendMailItemButton
        -- is the Blizzard function that handles the send mail attachment
        -- slot clicking. However, the actual attachment is done by using
        -- the container item while the send mail frame is open.
        local capturedBag = item.bag
        local capturedSlot = item.slot
        row:SetScript("OnClick", function()
            -- UseContainerItem picks up the item and places it in the
            -- next available send mail attachment slot.
            local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
            if useItem then
                useItem(capturedBag, capturedSlot)
            end
            -- Refresh the picker after a short delay to reflect the change.
            C_Timer.After(0.1, PopulatePicker)
        end)

        -- Tooltip on hover showing the full item tooltip.
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            -- SetBagItem shows the full item tooltip including stats.
            if C_Container and C_Container.GetContainerItemInfo then
                GameTooltip:SetBagItem(capturedBag, capturedSlot)
            else
                GameTooltip:SetBagItem(capturedBag, capturedSlot)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        table.insert(pickerButtons, row)
    end
end

-------------------------------------------------------------------------------
-- Recipient EditBox Frame
-- A small frame with an EditBox for setting the default recipient for
-- a category. Opened by right-clicking a category button.
-------------------------------------------------------------------------------

-- Creates the recipient EditBox frame (once).
local function CreateRecipientFrame()
    if recipientFrame then return end

    recipientFrame = CreateFrame("Frame", "MailroomQARecipient",
        UIParent, "BasicFrameTemplateWithInset")
    recipientFrame:SetSize(250, 80)
    recipientFrame:SetPoint("CENTER")
    recipientFrame:SetFrameStrata("DIALOG")
    recipientFrame:Hide()

    local title = recipientFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", recipientFrame, "TOP", 0, -6)
    title:SetText("Default Recipient")
    recipientFrame.titleFS = title

    recipientEditBox = CreateFrame("EditBox", "MailroomQARecipientEB",
        recipientFrame, "InputBoxTemplate")
    recipientEditBox:SetSize(180, 22)
    recipientEditBox:SetPoint("CENTER", recipientFrame, "CENTER", 0, -6)
    recipientEditBox:SetAutoFocus(true)

    -- Save on Enter, cancel on Escape.
    recipientEditBox:SetScript("OnEnterPressed", function(self)
        if activeCategory then
            local name = self:GetText()
            local db = MR.Addon.db.profile
            if name and name ~= "" then
                db.quickAttachRecipients[activeCategory.label] = name
                MR.Addon:Print("Default recipient for " .. activeCategory.label ..
                    " set to: " .. name)
            else
                db.quickAttachRecipients[activeCategory.label] = nil
                MR.Addon:Print("Cleared default recipient for " .. activeCategory.label .. ".")
            end
        end
        recipientFrame:Hide()
    end)
    recipientEditBox:SetScript("OnEscapePressed", function()
        recipientFrame:Hide()
    end)
end

-- Shows the recipient frame for a given category.
-- @param category (table) The category to configure.
local function ShowRecipientFrame(category)
    CreateRecipientFrame()
    activeCategory = category

    local db = MR.Addon.db.profile
    local currentRecipient = db.quickAttachRecipients[category.label] or ""

    recipientFrame.titleFS:SetText("Recipient: " .. category.label)
    recipientEditBox:SetText(currentRecipient)
    recipientFrame:Show()
    recipientEditBox:SetFocus()
    recipientEditBox:HighlightText()
end

-------------------------------------------------------------------------------
-- Category Buttons
-- A row of small buttons on the send frame, one per trade goods category.
-- Left-click opens the item picker. Right-click opens the recipient editor.
-------------------------------------------------------------------------------

-- Creates all category buttons on the send mail frame.
local function CreateCategoryButtons()
    if uiCreated then return end
    uiCreated = true

    if not SendMailFrame then return end

    -- Anchor point for the button row. We place them below the attachment
    -- area, which is near the bottom of the send frame.
    local anchor = SendMailFrame
    local prevButton = nil

    for i, category in ipairs(TRADE_GOODS_CATEGORIES) do
        local btn = CreateFrame("Button", "MailroomQACat" .. i,
            SendMailFrame, "UIPanelButtonTemplate")
        btn:SetSize(CAT_BUTTON_WIDTH, CAT_BUTTON_HEIGHT)

        if prevButton then
            btn:SetPoint("LEFT", prevButton, "RIGHT", 2, 0)
        else
            -- First button anchored below the attachment slots.
            -- SendMailAttachment1 is the first attachment slot on the send frame.
            if _G["SendMailAttachment1"] then
                btn:SetPoint("TOPLEFT", _G["SendMailAttachment1"], "BOTTOMLEFT", 0, -4)
            else
                btn:SetPoint("BOTTOMLEFT", SendMailFrame, "BOTTOMLEFT", 10, 36)
            end
        end

        btn:SetText(category.label)
        -- Shrink font to fit the narrow buttons.
        btn:GetFontString():SetFont(btn:GetFontString():GetFont(), 9)

        local capturedCat = category

        -- Register for both left and right clicks.
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        btn:SetScript("OnClick", function(self, button)
            if not MR.Addon.db.profile.quickAttachEnabled then return end

            if button == "RightButton" then
                -- Right-click: set default recipient for this category.
                ShowRecipientFrame(capturedCat)
            else
                -- Left-click: open the item picker for this category.
                -- If a default recipient is set, also fill the To: field.
                activeCategory = capturedCat

                local db = MR.Addon.db.profile
                local defaultRecip = db.quickAttachRecipients[capturedCat.label]
                if defaultRecip and defaultRecip ~= "" and SendMailNameEditBox then
                    local currentTo = SendMailNameEditBox:GetText()
                    if currentTo == "" then
                        SendMailNameEditBox:SetText(defaultRecip)
                    end
                end

                CreatePickerFrame()
                PopulatePicker()
                pickerFrame:Show()
            end
        end)

        -- Tooltip showing category info and right-click hint.
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
            GameTooltip:SetText(capturedCat.label)
            GameTooltip:AddLine("Left-click to browse bag items.", 1, 1, 1)
            local db = MR.Addon.db.profile
            local recip = db.quickAttachRecipients[capturedCat.label]
            if recip and recip ~= "" then
                GameTooltip:AddLine("Default recipient: " .. recip, 0.5, 1, 0.5)
            end
            GameTooltip:AddLine("Right-click to set default recipient.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        categoryButtons[i] = btn
        prevButton = btn
    end
end

-------------------------------------------------------------------------------
-- Module Lifecycle (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Called when the mailbox opens. Creates category buttons if needed.
function MR.QuickAttach:OnMailShow()
    if not MR.Addon.db.profile.quickAttachEnabled then return end
    CreateCategoryButtons()
end

-- Called when the mailbox closes. Hides the picker and recipient frames.
function MR.QuickAttach:OnMailClosed()
    if pickerFrame and pickerFrame:IsShown() then
        pickerFrame:Hide()
    end
    if recipientFrame and recipientFrame:IsShown() then
        recipientFrame:Hide()
    end
end
