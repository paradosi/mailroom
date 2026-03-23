-- Mailroom / Modules / CarbonCopy.lua
-- Copies open mail contents to the system clipboard (Retail) or to a
-- selectable EditBox (Classic/MoP) for manual Ctrl+C.
-- Creates a "Copy" button on the OpenMailFrame (the mail reading pane).
-- Strips WoW color escape codes from the body text so the copied output
-- is clean plain text suitable for pasting into Discord, forums, etc.
--
-- On Retail, C_System.CopyToClipboard() is available and the text goes
-- directly to the OS clipboard. On Classic clients this API does not
-- exist, so we create a temporary multi-line EditBox with the text
-- pre-selected. The player can then Ctrl+C to copy manually.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- CarbonCopy Module
-------------------------------------------------------------------------------

MR.CarbonCopy = {}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local copyButtonCreated = false
local copyButton        = nil
local clipboardFrame    = nil  -- the fallback EditBox frame for Classic
local clipboardEditBox  = nil  -- the EditBox inside clipboardFrame

-------------------------------------------------------------------------------
-- Text Formatting
-- Builds a plain-text representation of the currently open mail.
-- Strips WoW color codes (|cXXXXXXXX, |r, |H...|h, |h) so the output
-- is clean for pasting outside the game.
-------------------------------------------------------------------------------

-- Strips all WoW escape sequences from a string.
-- WoW uses |cAARRGGBB...|r for colors, |Hlink|htext|h for hyperlinks,
-- and |T...|t for textures. We remove all of these to produce plain text.
-- @param text (string) The raw WoW-formatted text.
-- @return (string) Plain text with all escape sequences removed.
local function StripColorCodes(text)
    if not text then return "" end

    -- Remove color start codes: |cAARRGGBB (10 chars total).
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    -- Remove color end codes: |r
    text = text:gsub("|r", "")
    -- Remove hyperlink wrappers: |Hplayer:Name|h[Name]|h -> [Name]
    -- We keep the display text between |h...|h but strip the link data.
    text = text:gsub("|H[^|]*|h", "")
    text = text:gsub("|h", "")
    -- Remove texture escape sequences: |TPath:size:...|t
    text = text:gsub("|T[^|]*|t", "")
    -- Remove any remaining pipe-letter escape codes we missed.
    text = text:gsub("|[AKNn]", "")

    return text
end

-- Builds the full plain-text content of the currently open mail.
-- Includes sender, subject, and body separated by newlines.
-- @return (string) The formatted mail text, or nil if no mail is open.
local function BuildMailText()
    -- OpenMailFrame exposes the current mail's info through global frames.
    local sender  = OpenMailSender and OpenMailSender:GetText() or "Unknown"
    local subject = OpenMailSubject and OpenMailSubject:GetText() or "(no subject)"
    local body    = OpenMailBodyText and OpenMailBodyText:GetText() or ""

    sender  = StripColorCodes(sender)
    subject = StripColorCodes(subject)
    body    = StripColorCodes(body)

    -- Trim trailing whitespace from the body.
    body = body:gsub("%s+$", "")

    local lines = {
        "From: " .. sender,
        "Subject: " .. subject,
        "---",
        body,
    }

    return table.concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- Clipboard Fallback Frame
-- On Classic clients where CopyToClipboard is unavailable, we show a
-- small frame with a multi-line EditBox containing the mail text,
-- pre-selected so the player only needs to press Ctrl+C.
-------------------------------------------------------------------------------

-- Creates the fallback clipboard frame (once). Subsequent calls are no-ops.
local function CreateClipboardFrame()
    if clipboardFrame then return end

    clipboardFrame = CreateFrame("Frame", "MailroomClipboardFrame", UIParent,
        "BasicFrameTemplateWithInset")
    clipboardFrame:SetSize(400, 300)
    clipboardFrame:SetPoint("CENTER")
    clipboardFrame:SetFrameStrata("DIALOG")
    clipboardFrame:SetMovable(true)
    clipboardFrame:EnableMouse(true)
    clipboardFrame:RegisterForDrag("LeftButton")
    clipboardFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    clipboardFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    clipboardFrame:Hide()

    -- Title text.
    local title = clipboardFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", clipboardFrame, "TOP", 0, -6)
    title:SetText("Copy Mail (Ctrl+C)")

    -- Scroll frame to hold the EditBox for scrollable text.
    local scrollFrame = CreateFrame("ScrollFrame", "MailroomClipboardScroll",
        clipboardFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", clipboardFrame, "TOPLEFT", 12, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", clipboardFrame, "BOTTOMRIGHT", -30, 10)

    -- Multi-line EditBox: holds the mail text for selection and copying.
    clipboardEditBox = CreateFrame("EditBox", "MailroomClipboardEditBox",
        scrollFrame)
    clipboardEditBox:SetMultiLine(true)
    clipboardEditBox:SetAutoFocus(true)
    clipboardEditBox:SetFontObject(ChatFontNormal)
    clipboardEditBox:SetWidth(scrollFrame:GetWidth() - 10)
    clipboardEditBox:SetScript("OnEscapePressed", function()
        clipboardFrame:Hide()
    end)

    scrollFrame:SetScrollChild(clipboardEditBox)
end

-- Shows the clipboard frame with the given text pre-selected.
-- @param text (string) The text to display for copying.
local function ShowClipboardFrame(text)
    CreateClipboardFrame()
    clipboardEditBox:SetText(text)
    clipboardFrame:Show()

    -- Select all text so Ctrl+C copies everything immediately.
    -- We use a short timer because SetText triggers layout updates
    -- and HighlightText may not work until the next frame.
    C_Timer.After(0.05, function()
        clipboardEditBox:HighlightText()
        clipboardEditBox:SetFocus()
    end)
end

-------------------------------------------------------------------------------
-- Copy Button
-- Created once on the OpenMailFrame. Clicking it either copies directly
-- to clipboard (Retail) or opens the fallback frame (Classic).
-------------------------------------------------------------------------------

-- Creates the Copy button on the OpenMailFrame.
local function CreateCopyButton()
    if copyButtonCreated then return end
    copyButtonCreated = true

    -- OpenMailFrame is the Blizzard frame shown when reading a mail.
    if not OpenMailFrame then return end

    copyButton = CreateFrame("Button", "MailroomCopyButton",
        OpenMailFrame, "UIPanelButtonTemplate")
    copyButton:SetSize(70, 22)
    -- Position to the right of the reply button (or bottom-right of the frame).
    copyButton:SetPoint("BOTTOMRIGHT", OpenMailFrame, "BOTTOMRIGHT", -8, 4)
    copyButton:SetText("Copy")
    copyButton:SetScript("OnClick", function()
        if not MR.Addon.db.profile.carbonCopyEnabled then return end

        local text = BuildMailText()
        if not text or text == "" then
            MR.Addon:Print("No mail content to copy.")
            return
        end

        if MR.CopyToClipboard then
            -- Retail: copy directly to system clipboard.
            MR.CopyToClipboard(text)
            MR.Addon:Print("Mail copied to clipboard.")
        else
            -- Classic/MoP: show the selectable EditBox fallback.
            ShowClipboardFrame(text)
        end
    end)

    -- Tooltip explaining the button.
    copyButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Copy Mail")
        if MR.CopyToClipboard then
            GameTooltip:AddLine("Copies mail text to clipboard.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Opens a text box to copy mail contents.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    copyButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-------------------------------------------------------------------------------
-- Module Lifecycle (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Called when the mailbox opens. Creates the copy button if needed.
function MR.CarbonCopy:OnMailShow()
    if not MR.Addon.db.profile.carbonCopyEnabled then return end
    CreateCopyButton()
end

-- Called when the mailbox closes. Hides the clipboard fallback frame
-- if it was open, since the mail data is no longer valid.
function MR.CarbonCopy:OnMailClosed()
    if clipboardFrame and clipboardFrame:IsShown() then
        clipboardFrame:Hide()
    end
end
