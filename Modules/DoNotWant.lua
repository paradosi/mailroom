-- Mailroom / Modules / DoNotWant.lua
-- Expiry action icons on each inbox row showing what happens when a mail
-- expires and allowing the player to trigger that action immediately.
--
-- Player-sent mail (not wasReturned, not system) is returned to the
-- sender when it expires. We show a return arrow icon for these.
-- System/AH/Postmaster mail is deleted on expiry. We show a trash icon.
--
-- The icon is color-tinted based on how many days remain vs the player's
-- configured thresholds:
--   Green:  daysLeft > expiryGreenDays (plenty of time)
--   Yellow: daysLeft > expiryYellowDays but <= expiryGreenDays (getting close)
--   Red:    daysLeft <= expiryYellowDays (urgent)
--
-- Clicking the icon queues the corresponding action (ReturnInboxItem or
-- DeleteInboxItem) through MR.Queue so it respects throttle timing.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- DoNotWant Module
-------------------------------------------------------------------------------

MR.DoNotWant = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Number of visible inbox rows.
local INBOX_ROWS = 7

-- Icon textures for the two expiry outcomes.
-- Return arrow: represents mail being sent back to the original sender.
local ICON_RETURN = "Interface\\Icons\\Spell_Shadow_SoulGem"
-- Trash: represents mail being permanently deleted.
local ICON_TRASH  = "Interface\\Icons\\INV_Misc_Bag_10"

-- Tint colors for the three urgency levels.
-- Green, yellow, red correspond to safe/warning/urgent time remaining.
local TINT_GREEN  = { r = 0.2, g = 1.0, b = 0.2 }
local TINT_YELLOW = { r = 1.0, g = 0.8, b = 0.0 }
local TINT_RED    = { r = 1.0, g = 0.2, b = 0.2 }

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local uiCreated  = false
local iconButtons = {}  -- icon button frames indexed 1-7

-------------------------------------------------------------------------------
-- Expiry Logic
-- Determines which icon to show and what color tint to apply based on
-- the mail's type and remaining days.
-------------------------------------------------------------------------------

-- Determines the icon texture for a mail based on its expiry behavior.
-- Player-sent mail (not already returned, not system) gets returned to
-- the sender on expiry. Everything else gets deleted.
-- @param info (table) A mail info table from MR.mailCache.
-- @return (string) Icon texture path.
-- @return (string) Action type: "return" or "delete".
local function GetExpiryInfo(info)
    local mailType = MR.ClassifyMail(info)

    -- Player mail that hasn't been returned yet will bounce back to sender.
    -- Already-returned mail and system/AH mail gets deleted permanently.
    if mailType == "player" and not info.wasReturned then
        return ICON_RETURN, "return"
    else
        return ICON_TRASH, "delete"
    end
end

-- Returns the tint color for an icon based on days remaining.
-- Uses the player's configured green/yellow thresholds from settings.
-- @param daysLeft (number) Days until the mail expires.
-- @return (table) Color table with r, g, b fields.
local function GetTintColor(daysLeft)
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

-------------------------------------------------------------------------------
-- Row Index Helper
-------------------------------------------------------------------------------

-- Returns the absolute mail index for a given row on the current page.
-- @param row (number) Row number 1-7.
-- @return (number) The absolute inbox index.
local function RowToIndex(row)
    local page = InboxFrame.pageNum or 0
    return (page * INBOX_ROWS) + row
end

-------------------------------------------------------------------------------
-- Action Handlers
-- Queue the appropriate mail action through MR.Queue when the icon is clicked.
-------------------------------------------------------------------------------

-- Queues a return-to-sender operation for the given mail index.
-- @param index (number) The absolute inbox index.
local function QueueReturn(index)
    local info = MR.mailCache[index]
    if not info then return end

    local capturedIdx = index
    MR.Queue.Add(function()
        MR.ReturnInboxItem(capturedIdx)
    end)
    MR.Addon:Print("Returning mail from " .. (info.sender or "Unknown") .. ".")
end

-- Queues a delete operation for the given mail index.
-- Only works on mail with no remaining items or gold. If the mail still
-- has contents, we warn the player instead of silently failing.
-- @param index (number) The absolute inbox index.
local function QueueDelete(index)
    local info = MR.mailCache[index]
    if not info then return end

    -- Safety check: don't delete mail that still has attachments or gold.
    local hasContents = (info.money and info.money > 0) or info.hasItem
    if hasContents then
        MR.Addon:Print("Cannot delete mail with uncollected items or gold.")
        return
    end

    local capturedIdx = index
    MR.Queue.Add(function()
        MR.DeleteInboxItem(capturedIdx)
    end)
    MR.Addon:Print("Deleting mail: " .. (info.subject or "(no subject)"))
end

-------------------------------------------------------------------------------
-- Visual Refresh
-- Updates all 7 icon buttons to reflect the current mail cache data.
-- Called on initial show, page change, and inbox update.
-------------------------------------------------------------------------------

-- Refreshes all icon buttons with current mail data.
local function RefreshIcons()
    local numItems = MR.GetInboxNumItems()

    for row = 1, INBOX_ROWS do
        local btn = iconButtons[row]
        if btn then
            local idx = RowToIndex(row)

            if idx <= numItems and MR.mailCache[idx] then
                local info = MR.mailCache[idx]
                local icon, action = GetExpiryInfo(info)
                local tint = GetTintColor(info.daysLeft)

                btn.icon:SetTexture(icon)
                btn.icon:SetVertexColor(tint.r, tint.g, tint.b)
                btn.action = action
                btn.mailIndex = idx
                btn:Show()
            else
                btn:Hide()
            end
        end
    end
end

-------------------------------------------------------------------------------
-- UI Creation
-- Creates a small icon button on each of the 7 MailItem rows. The icon
-- is positioned on the right side of the row, inside the button bounds.
-------------------------------------------------------------------------------

-- Creates the icon buttons on all inbox rows.
local function CreateUI()
    if uiCreated then return end
    uiCreated = true

    for row = 1, INBOX_ROWS do
        local mailButton = _G["MailItem" .. row .. "Button"]
        if mailButton then
            local btn = CreateFrame("Button", "MailroomDNW" .. row,
                mailButton)
            btn:SetSize(18, 18)
            -- Position on the right side of the row, before the expiry time text.
            btn:SetPoint("RIGHT", mailButton, "RIGHT", -4, 0)
            btn:SetFrameLevel(mailButton:GetFrameLevel() + 2)

            -- Icon texture fills the button.
            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints(btn)
            btn.icon = iconTex

            -- Store action type and index on the button for click handling.
            btn.action = nil
            btn.mailIndex = nil

            btn:SetScript("OnClick", function(self)
                if not MR.Addon.db.profile.doNotWantEnabled then return end
                if not self.mailIndex then return end

                if self.action == "return" then
                    QueueReturn(self.mailIndex)
                elseif self.action == "delete" then
                    QueueDelete(self.mailIndex)
                end
            end)

            -- Tooltip showing what the icon does.
            btn:SetScript("OnEnter", function(self)
                if not self.mailIndex then return end

                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local info = MR.mailCache[self.mailIndex]
                if not info then return end

                local daysText = string.format("%.1f days remaining", info.daysLeft)

                if self.action == "return" then
                    GameTooltip:SetText("Return to Sender")
                    GameTooltip:AddLine("This mail will be returned on expiry.", 1, 1, 1, true)
                    GameTooltip:AddLine("Click to return now.", 0.5, 1, 0.5)
                else
                    GameTooltip:SetText("Delete Mail")
                    GameTooltip:AddLine("This mail will be deleted on expiry.", 1, 1, 1, true)
                    GameTooltip:AddLine("Click to delete now.", 1, 0.5, 0.5)
                end
                GameTooltip:AddLine(daysText, 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            iconButtons[row] = btn
        end
    end

    -- Hook page navigation to refresh icons when the page changes.
    if InboxNextPageButton then
        InboxNextPageButton:HookScript("OnClick", RefreshIcons)
    end
    if InboxPrevPageButton then
        InboxPrevPageButton:HookScript("OnClick", RefreshIcons)
    end
end

-------------------------------------------------------------------------------
-- Module Lifecycle (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Called when the mailbox opens. Creates UI and refreshes icons.
function MR.DoNotWant:OnMailShow()
    if not MR.Addon.db.profile.doNotWantEnabled then return end
    CreateUI()
    RefreshIcons()
end

-- Called when the mailbox closes. Hides all icon buttons.
function MR.DoNotWant:OnMailClosed()
    for row = 1, INBOX_ROWS do
        if iconButtons[row] then
            iconButtons[row]:Hide()
        end
    end
end

-- Called on MAIL_INBOX_UPDATE. Refreshes icons because mail data may
-- have changed (items taken, mail deleted, new mail arrived).
function MR.DoNotWant:OnMailInboxUpdate()
    if not MR.Addon.db.profile.doNotWantEnabled then return end
    RefreshIcons()
end
