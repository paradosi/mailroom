-- Mailroom / Modules / QuickActions.lua
-- Modifier-key click shortcuts on inbox rows for fast mail operations.
-- Hooks the OnClick script of each MailItem button to intercept modifier
-- key combinations:
--   Shift+click: queue collect all money and items from that mail.
--   Ctrl+click:  queue return-to-sender.
--   Alt+click:   collect items then switch to send frame for forwarding.
-- Also adds modifier hint text to mail row tooltips so the player knows
-- these shortcuts exist.
--
-- Hooks are installed once and persist. The enabled check happens inside
-- the hook so toggling the setting takes effect immediately without
-- needing to reload the UI.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- QuickActions Module
-------------------------------------------------------------------------------

MR.QuickActions = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Number of visible inbox rows in the Blizzard mail frame.
local INBOX_ROWS = 7

-- Tooltip hint lines added to mail row tooltips.
local HINT_SHIFT = "|cff00ff00Shift-click|r to collect all"
local HINT_CTRL  = "|cff00ff00Ctrl-click|r to return to sender"
local HINT_ALT   = "|cff00ff00Alt-click|r to collect and reply"

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local hooksInstalled = false

-------------------------------------------------------------------------------
-- Action Handlers
-- Each handler receives an absolute mail index and queues the appropriate
-- operations through MR.Queue to respect throttle timing.
-------------------------------------------------------------------------------

-- Queues collection of all money and items from a single mail.
-- Captures the index at call time so it remains valid through queue
-- processing delays.
-- @param index (number) The absolute inbox index of the mail to collect.
local function CollectMail(index)
    local info = MR.mailCache[index]
    if not info then return end

    -- Take money first, then items. Order matters because some mail
    -- auto-deletes after all contents are removed, and we want to
    -- ensure gold is captured before the mail disappears.
    if info.money and info.money > 0 then
        local capturedIdx = index
        MR.Queue.Add(function()
            MR.TakeInboxMoney(capturedIdx)
        end)
    end

    if info.hasItem then
        local numAttach = info.hasItem
        if type(numAttach) == "number" and numAttach > 0 then
            for slot = 1, numAttach do
                local capturedIdx = index
                local capturedSlot = slot
                MR.Queue.Add(function()
                    MR.TakeInboxItem(capturedIdx, capturedSlot)
                end)
            end
        end
    end
end

-- Queues return-to-sender for a single mail.
-- Only works on player-sent, non-returned mail. System/AH mail has no
-- valid return address and is silently ignored by the server.
-- @param index (number) The absolute inbox index of the mail to return.
local function ReturnMail(index)
    local info = MR.mailCache[index]
    if not info then return end

    local mailType = MR.ClassifyMail(info)
    if mailType ~= "player" or info.wasReturned then
        MR.Addon:Print("Cannot return this mail (system/AH or already returned).")
        return
    end

    local capturedIdx = index
    MR.Queue.Add(function()
        MR.ReturnInboxItem(capturedIdx)
    end)
    MR.Addon:Print("Returning mail from " .. (info.sender or "Unknown") .. ".")
end

-- Collects items from a mail and then opens the send frame for a reply.
-- The send frame is opened after a short delay to allow the collection
-- queue to process. The To: field is not pre-filled here because the
-- Forward module handles that workflow. This action is for quick
-- "grab and respond" patterns.
-- @param index (number) The absolute inbox index of the mail.
local function CollectAndReply(index)
    local info = MR.mailCache[index]
    if not info then return end

    -- Collect everything from this mail first.
    CollectMail(index)

    -- After the queue processes, switch to the send tab.
    -- We use a queue operation at the end so it fires after all
    -- TakeInboxItem/TakeInboxMoney calls have completed.
    local sender = info.sender
    local subject = info.subject or ""
    MR.Queue.Add(function()
        -- Switch to the send tab.
        if MailFrameTab2 then
            MailFrameTab_OnClick(nil, 2)
        end
        -- Pre-fill the To: field with the sender's name if available.
        if sender and sender ~= "Unknown" and SendMailNameEditBox then
            SendMailNameEditBox:SetText(sender)
        end
        -- Pre-fill the subject with a reply prefix.
        if SendMailSubjectEditBox then
            local replySubject = subject
            if not replySubject:find("^Re:") then
                replySubject = "Re: " .. replySubject
            end
            SendMailSubjectEditBox:SetText(replySubject)
        end
    end)
end

-------------------------------------------------------------------------------
-- Row Index Helper
-- Converts a visible row number (1-7) to an absolute inbox index,
-- accounting for the current page offset.
-------------------------------------------------------------------------------

-- Returns the absolute mail index for a given row on the current page.
-- @param row (number) Row number 1-7.
-- @return (number) The absolute inbox index.
local function RowToIndex(row)
    local page = InboxFrame.pageNum or 0
    return (page * INBOX_ROWS) + row
end

-------------------------------------------------------------------------------
-- Hook Installation
-- Hooks are installed once on the first MAIL_SHOW and persist for the
-- addon lifetime. The enabled check is inside the hook itself so the
-- player can toggle the feature without reloading.
-------------------------------------------------------------------------------

-- Installs OnClick pre-hooks on all 7 MailItem buttons and tooltip hooks.
local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    for row = 1, INBOX_ROWS do
        local mailButton = _G["MailItem" .. row .. "Button"]
        if mailButton then
            local capturedRow = row

            -- PreClick fires before the default OnClick handler. If a modifier
            -- is held, we handle the action and consume the click by hiding
            -- and re-showing the button's highlight (the default handler still
            -- fires but we've already done the work).
            mailButton:HookScript("OnClick", function(self, button)
                if not MR.Addon.db.profile.quickActionsEnabled then return end
                if button ~= "LeftButton" then return end

                local idx = RowToIndex(capturedRow)
                local numItems = MR.GetInboxNumItems()
                if idx > numItems then return end

                if IsShiftKeyDown() then
                    CollectMail(idx)
                elseif IsControlKeyDown() then
                    ReturnMail(idx)
                elseif IsAltKeyDown() then
                    CollectAndReply(idx)
                end
            end)

            -- Tooltip hook: append modifier hints when hovering a mail row.
            mailButton:HookScript("OnEnter", function(self)
                if not MR.Addon.db.profile.quickActionsEnabled then return end

                local idx = RowToIndex(capturedRow)
                local numItems = MR.GetInboxNumItems()
                if idx > numItems then return end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(HINT_SHIFT)
                GameTooltip:AddLine(HINT_CTRL)
                GameTooltip:AddLine(HINT_ALT)
                GameTooltip:Show()
            end)
        end
    end
end

-------------------------------------------------------------------------------
-- Module Lifecycle (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Called when the mailbox opens. Installs hooks on first call.
function MR.QuickActions:OnMailShow()
    if not MR.Addon.db.profile.quickActionsEnabled then return end
    InstallHooks()
end

-- Called when the mailbox closes. No cleanup needed since hooks are
-- inert when the mail frame is hidden and the enabled check inside
-- each hook prevents execution when disabled.
function MR.QuickActions:OnMailClosed()
    -- No-op. Hooks persist and self-disable via the enabled check.
end
