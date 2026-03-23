-- Mailroom / Send.lua
-- Send frame enhancements.
-- Hooks into the default send mail UI to add address book integration
-- and send confirmation for gold amounts over a threshold. The actual
-- sending still goes through the standard Blizzard flow — we only
-- augment the UI, not replace it.
--
-- The autocomplete dropdown is a lightweight frame anchored below the
-- recipient EditBox. It shows up to 10 matches from the address book
-- and lets the player click or arrow-key to select a contact.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Send Module
-------------------------------------------------------------------------------

MR.Send = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Gold threshold (in copper) above which we prompt for send confirmation.
-- 100g = 100 * 100 * 100 = 1,000,000 copper.
local LARGE_GOLD_THRESHOLD = 1000000

-- Maximum number of autocomplete suggestions to display.
local MAX_SUGGESTIONS = 8

-- Height of each suggestion row in pixels.
local ROW_HEIGHT = 16

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local hookInstalled = false
local autocompleteInstalled = false
local dropdownFrame = nil      -- the autocomplete dropdown frame
local suggestionRows = {}      -- reusable FontString rows in the dropdown
local currentSuggestions = {}  -- current list of matching contact names
local selectedIndex = 0        -- keyboard-selected index (0 = none)

-------------------------------------------------------------------------------
-- Static Popup: Large Gold Send Confirmation
-- Warns the player before sending more than LARGE_GOLD_THRESHOLD copper.
-------------------------------------------------------------------------------

StaticPopupDialogs["MAILROOM_LARGE_GOLD_CONFIRM"] = {
    text = "You are about to send %s to %s. Are you sure?",
    button1 = "Send",
    button2 = "Cancel",
    OnAccept = function(self, data)
        -- The original SendMail call was blocked; now re-issue it.
        -- We set a bypass flag so our hook doesn't intercept it again.
        if data then
            MR.Send._bypassConfirm = true
            MR.SendMail(data.recipient, data.subject, data.body)
            MR.Send._bypassConfirm = false
        end
    end,
    timeout = 30,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- Autocomplete Dropdown
-- A minimal dropdown frame that appears below the recipient EditBox
-- when the player types. Each row is a clickable highlight that fills
-- the recipient field on click.
-------------------------------------------------------------------------------

-- Creates the autocomplete dropdown frame. Called once on first use.
-- The frame is parented to SendMailFrame so it inherits visibility
-- and strata automatically.
local function CreateDropdown()
    if dropdownFrame then return end

    dropdownFrame = CreateFrame("Frame", "MailroomAutocompleteDropdown",
        SendMailFrame, "BackdropTemplate")
    dropdownFrame:SetFrameStrata("DIALOG")
    dropdownFrame:SetSize(200, 10)
    dropdownFrame:Hide()

    -- Use a simple dark backdrop so suggestions are readable over the
    -- mail frame's textured background.
    dropdownFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 12,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dropdownFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    dropdownFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    -- Create reusable suggestion row buttons.
    for i = 1, MAX_SUGGESTIONS do
        local row = CreateFrame("Button", nil, dropdownFrame)
        row:SetSize(196, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 2,
            -2 - (i - 1) * ROW_HEIGHT)

        -- Highlight texture shown on mouseover.
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.3, 0.5, 0.8, 0.3)

        -- Selected texture shown for keyboard selection.
        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetColorTexture(0.3, 0.5, 0.8, 0.5)
        selected:Hide()
        row.selectedTex = selected

        -- Contact name text.
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", 4, 0)
        text:SetPoint("RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        -- On click, fill the recipient field and hide the dropdown.
        local rowIndex = i
        row:SetScript("OnClick", function()
            local name = currentSuggestions[rowIndex]
            if name then
                SendMailNameEditBox:SetText(name)
                SendMailNameEditBox:SetCursorPosition(#name)
                MR.Send:HideDropdown()
            end
        end)

        suggestionRows[i] = row
    end
end

-- Shows the autocomplete dropdown with the given list of suggestions.
-- Positions it directly below the recipient EditBox.
-- @param suggestions (table) Array of contact name strings.
local function ShowDropdown(suggestions)
    if not dropdownFrame then
        CreateDropdown()
    end

    currentSuggestions = suggestions
    selectedIndex = 0

    if #suggestions == 0 then
        dropdownFrame:Hide()
        return
    end

    -- Position below the recipient field.
    dropdownFrame:ClearAllPoints()
    dropdownFrame:SetPoint("TOPLEFT", SendMailNameEditBox, "BOTTOMLEFT", 0, -2)

    local visibleCount = math.min(#suggestions, MAX_SUGGESTIONS)
    dropdownFrame:SetSize(200, visibleCount * ROW_HEIGHT + 4)

    -- Populate rows and hide extras.
    for i = 1, MAX_SUGGESTIONS do
        local row = suggestionRows[i]
        if i <= visibleCount then
            row.text:SetText(suggestions[i])
            row.selectedTex:Hide()
            row:Show()
        else
            row:Hide()
        end
    end

    dropdownFrame:Show()
end

-------------------------------------------------------------------------------
-- Dropdown Keyboard Navigation
-- Allows arrow keys and Enter/Tab to navigate and select suggestions
-- while the recipient field retains focus.
-------------------------------------------------------------------------------

-- Updates the visual selection indicator on rows.
local function UpdateSelection()
    for i = 1, MAX_SUGGESTIONS do
        local row = suggestionRows[i]
        if row and row:IsShown() then
            if i == selectedIndex then
                row.selectedTex:Show()
            else
                row.selectedTex:Hide()
            end
        end
    end
end

-- Moves the keyboard selection up or down.
-- @param delta (number) +1 to move down, -1 to move up.
local function MoveSelection(delta)
    local count = math.min(#currentSuggestions, MAX_SUGGESTIONS)
    if count == 0 then return end

    selectedIndex = selectedIndex + delta
    if selectedIndex < 1 then
        selectedIndex = count
    elseif selectedIndex > count then
        selectedIndex = 1
    end

    UpdateSelection()
end

-- Accepts the currently selected suggestion, filling the recipient field.
-- Returns true if a selection was accepted, false if nothing was selected.
-- @return (boolean) Whether a suggestion was accepted.
local function AcceptSelection()
    if selectedIndex > 0 and selectedIndex <= #currentSuggestions then
        local name = currentSuggestions[selectedIndex]
        SendMailNameEditBox:SetText(name)
        SendMailNameEditBox:SetCursorPosition(#name)
        MR.Send:HideDropdown()
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Hides the autocomplete dropdown and resets selection state.
function MR.Send:HideDropdown()
    if dropdownFrame then
        dropdownFrame:Hide()
    end
    currentSuggestions = {}
    selectedIndex = 0
end

-- Installs hooks on the send mail UI. Called once on first MAIL_SHOW.
-- Hooks the send button to add sent contacts to the address book,
-- and hooks SendMail for large gold confirmation.
function MR.Send:InstallHooks()
    if hookInstalled then return end
    hookInstalled = true

    -- Hook the send button to record the recipient in the address book
    -- and hide the autocomplete dropdown.
    local sendButton = SendMailMailButton
    if sendButton then
        sendButton:HookScript("OnClick", function()
            MR.Send:OnSendClicked()
        end)
    end

    -- Hook the actual SendMail function to intercept large gold sends.
    -- hooksecurefunc runs our code after the original, but we need a
    -- pre-hook to block the call. We replace the shim on MR instead.
    local originalSendMail = MR.SendMail
    MR.SendMail = function(recipient, subject, body)
        -- Check if this is a bypass call from the confirmation dialog.
        if MR.Send._bypassConfirm then
            originalSendMail(recipient, subject, body)
            return
        end

        -- Check the gold amount in the send money fields.
        local gold = tonumber(SendMailMoneyGold:GetText()) or 0
        local silver = tonumber(SendMailMoneySilver:GetText()) or 0
        local copper = tonumber(SendMailMoneyCopper:GetText()) or 0
        local totalCopper = gold * 10000 + silver * 100 + copper

        if totalCopper >= LARGE_GOLD_THRESHOLD then
            -- Show confirmation dialog instead of sending immediately.
            local moneyText = MR.FormatMoney(totalCopper)
            local dialog = StaticPopup_Show("MAILROOM_LARGE_GOLD_CONFIRM",
                moneyText, recipient)
            if dialog then
                dialog.data = {
                    recipient = recipient,
                    subject = subject,
                    body = body,
                }
            end
            return
        end

        originalSendMail(recipient, subject, body)
    end
end

-- Called when the player clicks the Send button. Records the recipient
-- in the address book for future autocomplete and hides the dropdown.
function MR.Send:OnSendClicked()
    -- Add the recipient to the address book as a manual contact.
    local recipient = SendMailNameEditBox:GetText()
    if recipient and recipient ~= "" then
        MR.AddressBook:Add(recipient)
    end

    self:HideDropdown()
end

-- Attaches autocomplete behavior to the send mail recipient EditBox.
-- Hooks OnTextChanged for live search and OnKeyDown for arrow/enter
-- navigation. Called once during first MAIL_SHOW.
function MR.Send:SetupAutocomplete()
    if autocompleteInstalled then return end
    autocompleteInstalled = true

    local recipientField = SendMailNameEditBox
    if not recipientField then return end

    -- Create the dropdown frame lazily on first use.
    CreateDropdown()

    -- Live search: query address book on each keystroke.
    recipientField:HookScript("OnTextChanged", function(self, userInput)
        -- Only trigger autocomplete on user-initiated changes, not
        -- programmatic SetText calls (which set userInput to false).
        if not userInput then
            MR.Send:HideDropdown()
            return
        end

        local text = self:GetText()
        if text and #text >= 1 then
            local matches = MR.AddressBook:Search(text)
            -- Don't show dropdown if the only match is exactly what's typed.
            if #matches == 1 and matches[1] == text then
                MR.Send:HideDropdown()
            else
                ShowDropdown(matches)
            end
        else
            MR.Send:HideDropdown()
        end
    end)

    -- Keyboard navigation: arrow keys to select, Enter/Tab to accept,
    -- Escape to dismiss.
    recipientField:HookScript("OnKeyDown", function(self, key)
        if not dropdownFrame or not dropdownFrame:IsShown() then
            return
        end

        if key == "DOWN" then
            MoveSelection(1)
        elseif key == "UP" then
            MoveSelection(-1)
        elseif key == "TAB" or key == "ENTER" then
            if AcceptSelection() then
                -- Prevent the default Tab/Enter behavior so the cursor
                -- doesn't jump to the next field before we fill the name.
                -- Note: this only suppresses the key for this frame.
            end
        elseif key == "ESCAPE" then
            MR.Send:HideDropdown()
        end
    end)

    -- Hide dropdown when the recipient field loses focus.
    recipientField:HookScript("OnEditFocusLost", function()
        -- Small delay so click events on the dropdown can fire first.
        C_Timer.After(0.1, function()
            MR.Send:HideDropdown()
        end)
    end)
end

-- Called when the recipient field text changes. Kept as a no-op since
-- the HookScript in SetupAutocomplete handles everything directly.
-- @param text (string) Current text in the recipient field.
function MR.Send:OnRecipientChanged(text)
    -- Handled by SetupAutocomplete's OnTextChanged hook.
end
