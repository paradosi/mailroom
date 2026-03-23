-- Mailroom / Modules / Forward.lua
-- Forward button on the open mail reading frame.
-- When clicked, switches to the send tab and pre-fills the subject with
-- "Fwd: [original subject]" and the body with a divider line followed
-- by the original message text. The To: field is left blank for the
-- player to fill in.
--
-- If the original mail had attachments, a note is appended to the body
-- indicating whether they were already looted. Attachments cannot be
-- forwarded programmatically (WoW API limitation), so this is purely
-- informational.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Forward Module
-------------------------------------------------------------------------------

MR.Forward = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Divider line separating the player's new text from the forwarded content.
local FWD_DIVIDER = "\n\n---------- Forwarded Mail ----------\n"

-- Prefix added to the subject line of forwarded mail.
local FWD_PREFIX = "Fwd: "

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local buttonCreated = false
local forwardButton = nil

-------------------------------------------------------------------------------
-- Text Formatting
-- Strips WoW color codes from the original mail text so the forwarded
-- content is clean. Uses the same pattern as CarbonCopy.
-------------------------------------------------------------------------------

-- Removes WoW escape sequences (color codes, hyperlinks, textures) from text.
-- @param text (string) Raw WoW-formatted text.
-- @return (string) Clean plain text.
local function StripEscapes(text)
    if not text then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H[^|]*|h", "")
    text = text:gsub("|h", "")
    text = text:gsub("|T[^|]*|t", "")
    text = text:gsub("|[AKNn]", "")
    return text
end

-------------------------------------------------------------------------------
-- Forward Action
-- Reads the currently open mail, builds the forwarded content, switches
-- to the send tab, and fills in subject and body.
-------------------------------------------------------------------------------

-- Reads the currently open mail and switches to the send tab with
-- forwarded content pre-filled.
local function DoForward()
    -- Read current mail info from the open mail frame.
    local sender  = OpenMailSender and OpenMailSender:GetText() or "Unknown"
    local subject = OpenMailSubject and OpenMailSubject:GetText() or ""
    local body    = OpenMailBodyText and OpenMailBodyText:GetText() or ""

    sender  = StripEscapes(sender)
    subject = StripEscapes(subject)
    body    = StripEscapes(body)

    -- Build the forwarded subject: add "Fwd: " prefix if not already present.
    -- We check for an existing prefix to avoid "Fwd: Fwd: Fwd: ..." chains
    -- when forwarding already-forwarded mail.
    local fwdSubject = subject
    if not fwdSubject:find("^Fwd:") then
        fwdSubject = FWD_PREFIX .. fwdSubject
    end

    -- Build the forwarded body with attribution and divider.
    local fwdBody = FWD_DIVIDER
    fwdBody = fwdBody .. "From: " .. sender .. "\n"
    fwdBody = fwdBody .. "Subject: " .. subject .. "\n\n"
    fwdBody = fwdBody .. body

    -- Check for attachments and add a note if present.
    -- We inspect the open mail's attachment area to determine attachment status.
    -- OpenMailFrame.itemIndex tells us how many attachment slots were shown,
    -- but we check each slot to see if items remain.
    local attachNote = ""
    local hasAttachments = false
    local attachmentsLooted = true

    -- ATTACHMENTS_MAX_SEND is typically 12 on Retail, fewer on Classic.
    -- We check up to 12 slots to be safe across all clients.
    for slot = 1, 12 do
        local name, itemID, itemTexture, count, quality, canUse =
            MR.GetInboxItem(InboxFrame.openMailID or 0, slot)
        if name then
            hasAttachments = true
            -- If we can still read the item info, it hasn't been looted yet.
            attachmentsLooted = false
        end
    end

    -- If the original mail had attachments based on the mail cache, note it.
    if InboxFrame.openMailID then
        local info = MR.mailCache[InboxFrame.openMailID]
        if info and info.hasItem then
            hasAttachments = true
        end
    end

    if hasAttachments then
        if attachmentsLooted then
            attachNote = "\n\n[Attachments were already collected]"
        else
            attachNote = "\n\n[Original mail has attachments that cannot be forwarded]"
        end
        fwdBody = fwdBody .. attachNote
    end

    -- Switch to the send tab. MailFrameTab_OnClick is the Blizzard function
    -- that handles tab switching. Tab 2 is the send tab.
    if MailFrameTab2 then
        MailFrameTab_OnClick(nil, 2)
    end

    -- Fill in subject and body. Leave To: blank so the player chooses
    -- the recipient. The cursor is placed at the start of the body so
    -- the player can add their own message before the forwarded content.
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText(fwdSubject)
    end
    if SendMailBodyEditBox then
        SendMailBodyEditBox:SetText(fwdBody)
        -- Move cursor to the very start so the player types above the divider.
        SendMailBodyEditBox:SetCursorPosition(0)
    end
    if SendMailNameEditBox then
        -- Focus the To: field since the player needs to enter a recipient.
        SendMailNameEditBox:SetFocus()
    end
end

-------------------------------------------------------------------------------
-- UI Creation
-- Creates the Forward button on the OpenMailFrame once. The button sits
-- next to the Reply button at the bottom of the mail reading pane.
-------------------------------------------------------------------------------

-- Creates the Forward button on the open mail frame.
local function CreateForwardButton()
    if buttonCreated then return end
    buttonCreated = true

    if not OpenMailFrame then return end

    forwardButton = CreateFrame("Button", "MailroomForwardButton",
        OpenMailFrame, "UIPanelButtonTemplate")
    forwardButton:SetSize(80, 22)

    -- Position next to the Reply button. OpenMailReplyButton is the
    -- Blizzard reply button on the open mail frame.
    if OpenMailReplyButton then
        forwardButton:SetPoint("LEFT", OpenMailReplyButton, "RIGHT", 4, 0)
    else
        -- Fallback position if Reply button doesn't exist on this client.
        forwardButton:SetPoint("BOTTOMLEFT", OpenMailFrame, "BOTTOMLEFT", 100, 4)
    end

    forwardButton:SetText("Forward")
    forwardButton:SetScript("OnClick", function()
        if not MR.Addon.db.profile.forwardEnabled then return end
        DoForward()
    end)

    -- Tooltip.
    forwardButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Forward Mail")
        GameTooltip:AddLine("Switch to send tab with this mail's content.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    forwardButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-------------------------------------------------------------------------------
-- Module Lifecycle (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Called when the mailbox opens. Creates the forward button if needed.
function MR.Forward:OnMailShow()
    if not MR.Addon.db.profile.forwardEnabled then return end
    CreateForwardButton()
end

-- Called when the mailbox closes. No cleanup needed since the button is
-- parented to OpenMailFrame and hides automatically with it.
function MR.Forward:OnMailClosed()
    -- No-op. Button is parented to OpenMailFrame and auto-hides.
end
