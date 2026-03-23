-- Mailroom / MailFrame.lua
-- Hooks into the Blizzard mail frame.
-- Registers for MAIL_SHOW and MAIL_CLOSED events to coordinate inbox
-- scanning, alt data updates, and UI enhancements. Adds "Collect All"
-- and "Open All" buttons to the inbox frame. All UI modifications are
-- done via hooks (HookScript / hooksecurefunc) so we layer on top of
-- the default UI rather than replacing it.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- MailFrame Module
-------------------------------------------------------------------------------

MR.MailFrame = {}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local mailFrameOpen = false   -- tracks whether the mail frame is currently open
local buttonsCreated = false  -- ensures we only create our buttons once

-------------------------------------------------------------------------------
-- Status Text
-- A small FontString at the bottom of the inbox showing item count
-- and total gold waiting in the inbox.
-------------------------------------------------------------------------------

local statusText = nil

-- Updates the status text with current inbox summary info.
-- Shows mail count and total uncollected gold.
local function UpdateStatus()
    if not statusText then return end

    local cache = MR.Inbox:GetCache()
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

-------------------------------------------------------------------------------
-- Button Creation
-- Creates Collect All, Open All buttons, and a status line at the
-- bottom of the inbox frame. Uses standard Blizzard button templates
-- for a native look.
-------------------------------------------------------------------------------

-- Creates the UI elements on the inbox frame.
-- Called once on the first MAIL_SHOW event. Uses UIPanelButtonTemplate
-- which is available on all three clients.
local function CreateButtons()
    if buttonsCreated then return end
    buttonsCreated = true

    -- Collect All button — collects money and items from all mail.
    local collectBtn = CreateFrame("Button", "MailroomCollectAllButton",
        InboxFrame, "UIPanelButtonTemplate")
    collectBtn:SetSize(120, 25)
    collectBtn:SetPoint("BOTTOM", InboxFrame, "BOTTOM", -65, 100)
    collectBtn:SetText("Collect All")
    collectBtn:SetScript("OnClick", function()
        if MR.Queue.IsRunning() then
            MR.Queue.Clear()
            MR.Addon:Print("Collection cancelled.")
        else
            MR.Inbox:CollectAll()
        end
    end)

    -- Open All button — marks all unread mail as read without collecting.
    local openBtn = CreateFrame("Button", "MailroomOpenAllButton",
        InboxFrame, "UIPanelButtonTemplate")
    openBtn:SetSize(120, 25)
    openBtn:SetPoint("BOTTOM", InboxFrame, "BOTTOM", 65, 100)
    openBtn:SetText("Open All")
    openBtn:SetScript("OnClick", function()
        if MR.Queue.IsRunning() then
            MR.Queue.Clear()
            MR.Addon:Print("Cancelled.")
        else
            MR.Inbox:OpenAll()
        end
    end)

    -- Status text — shows mail count and gold summary below the buttons.
    statusText = InboxFrame:CreateFontString(nil, "OVERLAY",
        "GameFontNormalSmall")
    statusText:SetPoint("BOTTOM", InboxFrame, "BOTTOM", 0, 84)
    statusText:SetTextColor(0.8, 0.8, 0.8)

    -- Update button text based on queue state.
    MR.Queue.onStart = function()
        collectBtn:SetText("Cancel")
    end
    MR.Queue.onStop = function()
        collectBtn:SetText("Collect All")
        -- Refresh status after collection finishes.
        UpdateStatus()
    end
    MR.Queue.onProgress = function(remaining, total)
        if total > 0 then
            collectBtn:SetText("Cancel (" .. remaining .. ")")
        end
    end
end

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

-- Called when the player opens a mailbox (MAIL_SHOW event).
-- Scans the inbox, creates UI buttons, installs send hooks, and
-- records alt data. Shows expiry warnings via the Alerts module.
function MR.MailFrame:OnMailShow()
    mailFrameOpen = true

    CreateButtons()
    MR.Inbox:ScanInbox()
    MR.Send:InstallHooks()
    MR.Send:SetupAutocomplete()

    -- Update status line with inbox summary.
    UpdateStatus()

    -- Show detailed expiry warnings via Alerts module.
    local expiring = MR.Inbox:GetExpiringMail()
    MR.Alerts:ShowExpiryWarnings(expiring)

    -- Update alt data with current mailbox contents.
    local cache = MR.Inbox:GetCache()
    MR.AltData:UpdateMailSnapshot(cache)

    -- Auto-populate address book with inbox senders.
    MR.AddressBook:PopulateFromInbox(cache)

    -- If auto-collect is enabled, start collecting immediately.
    if MR.Addon.db.profile.autoCollect then
        MR.Inbox:CollectAll()
    end
end

-- Called when the player closes the mailbox (MAIL_CLOSED event).
-- Clears any running queue since mail operations can't proceed with
-- the mailbox closed, hides the autocomplete dropdown, and updates
-- the alt data snapshot one final time.
function MR.MailFrame:OnMailClosed()
    mailFrameOpen = false
    MR.Queue.Clear()
    MR.Send:HideDropdown()

    -- Final alt data snapshot captures any changes made during the session.
    MR.AltData:UpdateMailSnapshot(MR.Inbox:GetCache())
end

-- Called on MAIL_INBOX_UPDATE to refresh the cache and status while
-- the mailbox is open. This event fires after taking items, deleting
-- mail, or when new mail arrives.
function MR.MailFrame:OnMailInboxUpdate()
    if mailFrameOpen then
        MR.Inbox:OnMailInboxUpdate()
        UpdateStatus()
    end
end

-- Returns whether the mail frame is currently open.
-- @return (boolean) True if the mailbox UI is visible.
function MR.MailFrame:IsOpen()
    return mailFrameOpen
end

-------------------------------------------------------------------------------
-- Event Registration
-- Hooks into the addon's AceEvent system. Called from Mailroom.lua OnEnable.
-------------------------------------------------------------------------------

-- Registers all mail-related events on the addon object.
-- Must be called after AceAddon is initialized (in OnEnable).
function MR.MailFrame:RegisterEvents()
    MR.Addon:RegisterEvent("MAIL_SHOW", function()
        MR.MailFrame:OnMailShow()
    end)
    MR.Addon:RegisterEvent("MAIL_CLOSED", function()
        MR.MailFrame:OnMailClosed()
    end)
    MR.Addon:RegisterEvent("MAIL_INBOX_UPDATE", function()
        MR.MailFrame:OnMailInboxUpdate()
    end)
    MR.Addon:RegisterEvent("PLAYER_MONEY", function()
        MR.AltData:OnPlayerMoney()
    end)
end
