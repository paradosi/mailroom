-- Mailroom / Modules / MailBag.lua
-- Bag-style grid view of all inbox attachments.
-- Creates a toggleable frame anchored to the Blizzard mail frame that
-- displays every item attachment across all mail as icon slots in a grid.
-- Duplicate items (same itemID) are consolidated into single slots with
-- summed stack counts so the player sees a compact inventory-like view
-- of everything waiting in the inbox.
--
-- Features:
--   Search EditBox: filters displayed items by name.
--   Expiry tint: slots are tinted green/yellow/red based on the mail's
--     remaining days, using the same thresholds as DoNotWant.
--   Left-click: queues collection of that item via MR.Queue.
--   Shift-click: inserts the item's chat link via ChatEdit_InsertLink.
--   Gold slots: if enabled, shows each gold-carrying mail as a special
--     coin-icon slot.
--   Toggle button: switches between the default list view and grid view.
--
-- The grid rebuilds on every MAIL_INBOX_UPDATE because mail indices shift
-- as items are collected. Caching the grid across updates would risk
-- stale index references that point to wrong mail items.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- MailBag Module
-------------------------------------------------------------------------------

MR.MailBag = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Grid layout parameters.
local SLOT_SIZE    = 37   -- icon slot width and height in pixels
local SLOT_PADDING = 3    -- gap between slots
local GRID_COLS    = 8    -- number of columns in the grid
local FRAME_INSET  = 10   -- padding inside the frame borders

-- Gold slot icon (standard gold coin texture).
local GOLD_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- Item quality colors for border tinting. Sourced from the global
-- ITEM_QUALITY_COLORS table at runtime, but we define fallbacks here
-- in case the table isn't populated yet at load time.
local QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },  -- Poor (grey)
    [1] = { r = 1.00, g = 1.00, b = 1.00 },  -- Common (white)
    [2] = { r = 0.12, g = 1.00, b = 0.00 },  -- Uncommon (green)
    [3] = { r = 0.00, g = 0.44, b = 0.87 },  -- Rare (blue)
    [4] = { r = 0.64, g = 0.21, b = 0.93 },  -- Epic (purple)
    [5] = { r = 1.00, g = 0.50, b = 0.00 },  -- Legendary (orange)
}

-- Expiry tint colors (same thresholds as DoNotWant).
local TINT_GREEN  = { r = 0.2, g = 1.0, b = 0.2, a = 0.3 }
local TINT_YELLOW = { r = 1.0, g = 0.8, b = 0.0, a = 0.3 }
local TINT_RED    = { r = 1.0, g = 0.2, b = 0.2, a = 0.3 }

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local uiCreated    = false
local bagFrame     = nil   -- the main MailBag frame
local toggleButton = nil   -- button on MailFrame to toggle the grid view
local searchBox    = nil   -- EditBox for filtering by item name
local slotButtons  = {}    -- pool of slot button frames (reused on refresh)
local gridData     = {}    -- current grid data: array of item/gold entries
local searchFilter = ""    -- current search filter text (lowercased)

-------------------------------------------------------------------------------
-- Expiry Tint Helper
-- Returns a tint color based on how many days the mail has remaining.
-- Uses the same thresholds as DoNotWant for visual consistency.
-------------------------------------------------------------------------------

-- Returns expiry tint color for a given daysLeft value.
-- @param daysLeft (number) Days until the mail expires.
-- @return (table) Color table with r, g, b, a fields.
local function GetExpiryTint(daysLeft)
    local db = MR.Addon.db.profile
    local greenDays  = db.expiryGreenDays or 3
    local yellowDays = db.expiryYellowDays or 1

    if daysLeft > greenDays then
        return TINT_GREEN
    elseif daysLeft > yellowDays then
        return TINT_YELLOW
    else
        return TINT_RED
    end
end

-- Returns the quality border color for an item.
-- Falls back to QUALITY_COLORS if the global ITEM_QUALITY_COLORS is missing.
-- @param quality (number) Item quality index (0-5).
-- @return (number, number, number) r, g, b color values.
local function GetQualityColor(quality)
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        return c.r, c.g, c.b
    end
    local c = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
    return c.r, c.g, c.b
end

-------------------------------------------------------------------------------
-- Grid Data Builder
-- Scans the mail cache and attachment data to build the consolidated
-- grid. Items with the same itemID are merged into single entries with
-- summed counts. Each entry tracks which mail indices contain that item
-- so click-to-collect knows where to take from.
-------------------------------------------------------------------------------

-- Builds the grid data from the current mail cache.
-- @return (table) Array of grid entries, each with:
--   type: "item" or "gold"
--   itemID: (number, items only) the item ID
--   name: (string) display name
--   texture: (number/string) icon texture
--   count: (number) total stack count across all mail
--   quality: (number, items only) item quality
--   sources: (table) array of { mailIndex, slot } pairs for collection
--   daysLeft: (number) minimum daysLeft across all source mails
--   link: (string, items only) item link for chat insertion
local function BuildGridData()
    local items = {}       -- keyed by itemID for consolidation
    local itemOrder = {}   -- tracks insertion order for stable sorting
    local goldEntries = {} -- separate list for gold slots

    local numMail = MR.GetInboxNumItems()

    for i = 1, numMail do
        local info = MR.mailCache[i]
        if not info then break end

        -- Scan attachments for this mail.
        if info.hasItem then
            local numAttach = info.hasItem
            if type(numAttach) == "number" and numAttach > 0 then
                for slot = 1, numAttach do
                    local name, itemID, itemTexture, count, quality, canUse =
                        MR.GetInboxItem(i, slot)
                    if name and itemID then
                        local link = GetInboxItemLink(i, slot)

                        if items[itemID] then
                            -- Consolidate: add count and source reference.
                            items[itemID].count = items[itemID].count + (count or 1)
                            table.insert(items[itemID].sources, {
                                mailIndex = i,
                                slot = slot,
                            })
                            -- Track the most urgent expiry across all sources.
                            if info.daysLeft < items[itemID].daysLeft then
                                items[itemID].daysLeft = info.daysLeft
                            end
                        else
                            items[itemID] = {
                                type    = "item",
                                itemID  = itemID,
                                name    = name,
                                texture = itemTexture,
                                count   = count or 1,
                                quality = quality or 0,
                                link    = link,
                                daysLeft = info.daysLeft,
                                sources = { { mailIndex = i, slot = slot } },
                            }
                            table.insert(itemOrder, itemID)
                        end
                    end
                end
            end
        end

        -- Gold entries (one per mail, not consolidated).
        if info.money and info.money > 0 then
            table.insert(goldEntries, {
                type     = "gold",
                name     = MR.FormatMoney(info.money),
                texture  = GOLD_ICON,
                count    = 1,
                money    = info.money,
                daysLeft = info.daysLeft,
                sources  = { { mailIndex = i } },
            })
        end
    end

    -- Build final array: items first (in insertion order), then gold.
    local result = {}
    for _, itemID in ipairs(itemOrder) do
        table.insert(result, items[itemID])
    end

    -- Only include gold slots if the setting is enabled.
    if MR.Addon.db.profile.mailBagShowGold then
        for _, goldEntry in ipairs(goldEntries) do
            table.insert(result, goldEntry)
        end
    end

    return result
end

-------------------------------------------------------------------------------
-- Slot Button Pool
-- We maintain a pool of reusable slot buttons. On each refresh we show/hide
-- as needed rather than creating and destroying frames every update, which
-- would cause memory churn and potential taint issues.
-------------------------------------------------------------------------------

-- Ensures at least `count` slot buttons exist in the pool.
-- @param count (number) Minimum number of slot buttons needed.
local function EnsureSlotButtons(count)
    for i = #slotButtons + 1, count do
        local btn = CreateFrame("Button", "MailroomBagSlot" .. i,
            bagFrame.content)
        btn:SetSize(SLOT_SIZE, SLOT_SIZE)

        -- Background (black).
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetColorTexture(0, 0, 0, 0.8)

        -- Item icon.
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        btn.icon = icon

        -- Quality border (colored frame around the slot).
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(btn)
        border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        border:SetBlendMode("ADD")
        border:SetAlpha(0.6)
        btn.border = border

        -- Count text (bottom-right corner).
        local countFS = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        btn.countFS = countFS

        -- Expiry tint overlay.
        local tint = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        tint:SetAllPoints(icon)
        tint:SetColorTexture(1, 1, 1, 0.3)
        btn.tint = tint

        btn:Hide()
        slotButtons[i] = btn
    end
end

-------------------------------------------------------------------------------
-- Grid Refresh
-- Rebuilds the visual grid from the current grid data, applying the
-- search filter and expiry tints.
-------------------------------------------------------------------------------

-- Refreshes the grid display with current data and filter.
local function RefreshGrid()
    gridData = BuildGridData()

    -- Apply search filter.
    local filtered = {}
    for _, entry in ipairs(gridData) do
        if searchFilter == "" then
            table.insert(filtered, entry)
        else
            local name = entry.name or ""
            if name:lower():find(searchFilter, 1, true) then
                table.insert(filtered, entry)
            end
        end
    end

    -- Ensure enough slot buttons exist.
    EnsureSlotButtons(#filtered)

    -- Hide all existing slots first.
    for _, btn in ipairs(slotButtons) do
        btn:Hide()
    end

    -- Position and populate visible slots.
    local db = MR.Addon.db.profile
    local showQuality = db.mailBagShowQuality

    for i, entry in ipairs(filtered) do
        local btn = slotButtons[i]
        local col = (i - 1) % GRID_COLS
        local row = math.floor((i - 1) / GRID_COLS)

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bagFrame.content, "TOPLEFT",
            FRAME_INSET + (col * (SLOT_SIZE + SLOT_PADDING)),
            -(FRAME_INSET + (row * (SLOT_SIZE + SLOT_PADDING))))

        -- Set icon texture.
        if entry.texture then
            btn.icon:SetTexture(entry.texture)
            btn.icon:Show()
        else
            btn.icon:Hide()
        end

        -- Count text: only show if count > 1 for items. Always show for gold.
        if entry.type == "item" and entry.count > 1 then
            btn.countFS:SetText(entry.count)
            btn.countFS:Show()
        elseif entry.type == "gold" then
            btn.countFS:SetText("")
            btn.countFS:Hide()
        else
            btn.countFS:SetText("")
            btn.countFS:Hide()
        end

        -- Quality border.
        if showQuality and entry.type == "item" then
            local r, g, b = GetQualityColor(entry.quality)
            btn.border:SetVertexColor(r, g, b)
            btn.border:Show()
        else
            btn.border:Hide()
        end

        -- Expiry tint.
        local tintColor = GetExpiryTint(entry.daysLeft)
        btn.tint:SetColorTexture(tintColor.r, tintColor.g, tintColor.b, tintColor.a)

        -- Store entry data on the button for click/tooltip handlers.
        btn.entryData = entry

        -- Click handlers.
        btn:SetScript("OnClick", function(self, button)
            local data = self.entryData
            if not data then return end

            if IsShiftKeyDown() and data.type == "item" and data.link then
                -- Shift-click: insert chat link.
                if ChatEdit_InsertLink then
                    ChatEdit_InsertLink(data.link)
                end
                return
            end

            -- Left-click: queue collection from the first available source.
            -- We use the first source's mail index and slot. For consolidated
            -- items, this collects from one mail; the player clicks again
            -- for the next stack.
            if data.sources and #data.sources > 0 then
                local source = data.sources[1]
                if data.type == "item" then
                    local capturedIndex = source.mailIndex
                    local capturedSlot = source.slot
                    MR.Queue.Add(function()
                        MR.TakeInboxItem(capturedIndex, capturedSlot)
                    end)
                    MR.Addon:Print("Collecting: " .. (data.name or "item"))
                elseif data.type == "gold" then
                    local capturedIndex = source.mailIndex
                    MR.Queue.Add(function()
                        MR.TakeInboxMoney(capturedIndex)
                    end)
                    MR.Addon:Print("Collecting gold.")
                end
            end
        end)

        -- Tooltip.
        btn:SetScript("OnEnter", function(self)
            local data = self.entryData
            if not data then return end

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

            if data.type == "item" and data.sources and #data.sources > 0 then
                -- Show the actual item tooltip from the mail.
                local src = data.sources[1]
                GameTooltip:SetInboxItem(src.mailIndex, src.slot)
                -- Add count info if consolidated.
                if #data.sources > 1 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Total: " .. data.count ..
                        " across " .. #data.sources .. " mail",
                        0.7, 0.7, 0.7)
                end
            elseif data.type == "gold" then
                GameTooltip:SetText("Gold")
                GameTooltip:AddLine(data.name, 1, 1, 1)
            end

            -- Expiry info.
            local daysText = string.format("%.1f days remaining", data.daysLeft)
            GameTooltip:AddLine(daysText, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Click|r to collect", 1, 1, 1)
            if data.type == "item" then
                GameTooltip:AddLine("|cff00ff00Shift-click|r to link in chat", 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        btn:Show()
    end

    -- Resize content frame to fit all rows.
    local totalRows = math.ceil(#filtered / GRID_COLS)
    local contentHeight = (FRAME_INSET * 2) + (totalRows * (SLOT_SIZE + SLOT_PADDING))
    contentHeight = math.max(contentHeight, SLOT_SIZE + FRAME_INSET * 2)
    bagFrame.content:SetHeight(contentHeight)
end

-------------------------------------------------------------------------------
-- Main Frame Creation
-- The MailBag frame is a bordered frame anchored to the right side of
-- the Blizzard MailFrame. Contains a search box at the top and a scrollable
-- grid of item slots below.
-------------------------------------------------------------------------------

-- Creates the MailBag frame and toggle button (once).
local function CreateUI()
    if uiCreated then return end
    uiCreated = true

    -- Calculate frame dimensions based on grid layout.
    local frameWidth = (FRAME_INSET * 2) + (GRID_COLS * (SLOT_SIZE + SLOT_PADDING)) - SLOT_PADDING + 30
    local frameHeight = 360

    -- Main frame.
    bagFrame = CreateFrame("Frame", "MailroomMailBagFrame",
        MailFrame, "BasicFrameTemplateWithInset")
    bagFrame:SetSize(frameWidth, frameHeight)
    bagFrame:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 2, 0)
    bagFrame:SetFrameStrata("HIGH")
    bagFrame:Hide()

    -- Title.
    local title = bagFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", bagFrame, "TOP", 0, -6)
    title:SetText("MailBag")

    -- Search EditBox at the top of the frame.
    searchBox = CreateFrame("EditBox", "MailroomMailBagSearch",
        bagFrame, "InputBoxTemplate")
    searchBox:SetSize(frameWidth - 60, 20)
    searchBox:SetPoint("TOP", bagFrame, "TOP", 0, -24)
    searchBox:SetAutoFocus(false)

    -- Placeholder text for the search box.
    local placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    placeholder:SetText("Search...")
    searchBox.placeholder = placeholder

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        searchFilter = text:lower()
        -- Show/hide placeholder.
        if text == "" then
            self.placeholder:Show()
        else
            self.placeholder:Hide()
        end
        RefreshGrid()
    end)
    searchBox:SetScript("OnEditFocusGained", function(self)
        self.placeholder:Hide()
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self.placeholder:Show()
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Scroll frame for the grid content.
    local scrollFrame = CreateFrame("ScrollFrame", "MailroomMailBagScroll",
        bagFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", bagFrame, "TOPLEFT", 8, -48)
    scrollFrame:SetPoint("BOTTOMRIGHT", bagFrame, "BOTTOMRIGHT", -28, 8)

    -- Content frame (holds slot buttons, sized dynamically).
    local content = CreateFrame("Frame", "MailroomMailBagContent", scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    content:SetHeight(1)  -- set dynamically by RefreshGrid
    scrollFrame:SetScrollChild(content)

    bagFrame.scrollFrame = scrollFrame
    bagFrame.content = content

    -- Toggle button on the mail frame to switch between list and grid view.
    toggleButton = CreateFrame("Button", "MailroomMailBagToggle",
        MailFrame, "UIPanelButtonTemplate")
    toggleButton:SetSize(70, 22)
    toggleButton:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -145, -4)
    toggleButton:SetText("MailBag")
    toggleButton:SetScript("OnClick", function()
        if not MR.Addon.db.profile.mailBagEnabled then
            MR.Addon:Print("MailBag is disabled in settings.")
            return
        end

        if bagFrame:IsShown() then
            bagFrame:Hide()
        else
            RefreshGrid()
            bagFrame:Show()
        end
    end)

    -- Tooltip on the toggle button.
    toggleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("MailBag")
        GameTooltip:AddLine("Toggle bag-style grid view of inbox items.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    toggleButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-------------------------------------------------------------------------------
-- Module Lifecycle (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Called when the mailbox opens. Creates UI if needed and optionally
-- auto-opens the grid view based on settings.
function MR.MailBag:OnMailShow()
    if not MR.Addon.db.profile.mailBagEnabled then return end

    CreateUI()

    -- Auto-open if configured.
    if MR.Addon.db.profile.mailBagAutoOpen then
        RefreshGrid()
        bagFrame:Show()
    end
end

-- Called when the mailbox closes. Hides the grid frame and resets filter.
function MR.MailBag:OnMailClosed()
    if bagFrame and bagFrame:IsShown() then
        bagFrame:Hide()
    end
    searchFilter = ""
    if searchBox then
        searchBox:SetText("")
    end
end

-- Called on MAIL_INBOX_UPDATE. Rebuilds the grid if visible because
-- mail indices may have shifted. We do a full rebuild rather than
-- incremental updates because index stability cannot be guaranteed
-- after items are taken or mail is deleted.
function MR.MailBag:OnMailInboxUpdate()
    if not MR.Addon.db.profile.mailBagEnabled then return end

    if bagFrame and bagFrame:IsShown() then
        RefreshGrid()
    end
end
