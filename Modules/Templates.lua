-- Mailroom / Modules / Templates.lua
-- Save and load outgoing mail templates.
-- Captures the current send frame state (recipient, subject, body, money)
-- into a named template stored in the profile database. Templates can be
-- loaded back to pre-fill the send frame, avoiding repetitive data entry
-- for frequently sent mail patterns (e.g., weekly guild bank deposits,
-- reagent requests to alts).

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Templates Module
-------------------------------------------------------------------------------

MR.Templates = {}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local buttonsCreated = false
local pickerFrame    = nil

-------------------------------------------------------------------------------
-- Template Capture
-- Reads the current state of the Blizzard SendMailFrame fields and
-- returns a template data table. We read from the EditBox widgets
-- directly because there is no API to query "pending send" state.
-------------------------------------------------------------------------------

-- Captures the current send frame field values into a template table.
-- @return (table) Template data with recipient, subject, body, gold,
--                 silver, and copper fields.
local function CaptureTemplate()
    local recipient = SendMailNameEditBox:GetText() or ""
    local subject   = SendMailSubjectEditBox:GetText() or ""
    local body      = SendMailBodyEditBox:GetText() or ""
    local gold      = tonumber(SendMailMoneyGold:GetText()) or 0
    local silver    = tonumber(SendMailMoneySilver:GetText()) or 0
    local copper    = tonumber(SendMailMoneyCopper:GetText()) or 0

    return {
        recipient = recipient,
        subject   = subject,
        body      = body,
        gold      = gold,
        silver    = silver,
        copper    = copper,
    }
end

-------------------------------------------------------------------------------
-- Template Application
-- Fills the Blizzard SendMailFrame fields from a template table.
-- We set each EditBox value individually rather than simulating clicks
-- to avoid triggering unintended hooks from other addons.
-------------------------------------------------------------------------------

-- Loads a template's values into the send frame fields.
-- @param template (table) Template data with recipient, subject, body,
--                         gold, silver, and copper fields.
local function ApplyTemplate(template)
    if not template then return end

    SendMailNameEditBox:SetText(template.recipient or "")
    SendMailSubjectEditBox:SetText(template.subject or "")
    SendMailBodyEditBox:SetText(template.body or "")

    -- Money fields accept string values. We convert numbers to strings
    -- and only set non-zero values to keep the UI clean.
    if template.gold and template.gold > 0 then
        SendMailMoneyGold:SetText(tostring(template.gold))
    else
        SendMailMoneyGold:SetText("")
    end

    if template.silver and template.silver > 0 then
        SendMailMoneySilver:SetText(tostring(template.silver))
    else
        SendMailMoneySilver:SetText("")
    end

    if template.copper and template.copper > 0 then
        SendMailMoneyCopper:SetText(tostring(template.copper))
    else
        SendMailMoneyCopper:SetText("")
    end

    MR.Addon:Print("Template loaded.")
end

-------------------------------------------------------------------------------
-- Save Dialog
-- A StaticPopup with an EditBox prompting for the template name.
-- On accept, the current send frame state is captured and stored.
-------------------------------------------------------------------------------

StaticPopupDialogs["MAILROOM_SAVE_TEMPLATE"] = {
    text = "Save mail template as:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        if not name or name == "" then
            MR.Addon:Print("Template name cannot be empty.")
            return
        end

        local template = CaptureTemplate()
        MR.Addon.db.profile.mailTemplates[name] = template
        MR.Addon:Print("Template '" .. name .. "' saved.")
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        if name and name ~= "" then
            local template = CaptureTemplate()
            MR.Addon.db.profile.mailTemplates[name] = template
            MR.Addon:Print("Template '" .. name .. "' saved.")
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- Template Picker Frame
-- A scrollable list of saved templates. Each row shows the template name,
-- a summary of its contents, a "Load" button, and a "Delete" button.
-- Created once and reused.
-------------------------------------------------------------------------------

local pickerScrollChild = nil

-- Creates the picker frame if it does not exist.
local function CreatePickerFrame()
    if pickerFrame then return end

    pickerFrame = CreateFrame("Frame", "MailroomTemplatePicker",
        UIParent, "BasicFrameTemplateWithInset")
    pickerFrame:SetSize(350, 300)
    pickerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    pickerFrame:SetFrameStrata("DIALOG")
    pickerFrame:SetMovable(true)
    pickerFrame:EnableMouse(true)
    pickerFrame:RegisterForDrag("LeftButton")
    pickerFrame:SetScript("OnDragStart", pickerFrame.StartMoving)
    pickerFrame:SetScript("OnDragStop", pickerFrame.StopMovingOrSizing)

    pickerFrame.TitleText = pickerFrame:CreateFontString(nil, "OVERLAY",
        "GameFontHighlight")
    pickerFrame.TitleText:SetPoint("TOP", pickerFrame, "TOP", 0, -5)
    pickerFrame.TitleText:SetText("Mail Templates")

    local scrollFrame = CreateFrame("ScrollFrame", nil, pickerFrame,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", pickerFrame, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", pickerFrame, "BOTTOMRIGHT", -30, 10)

    pickerScrollChild = CreateFrame("Frame", nil, scrollFrame)
    pickerScrollChild:SetSize(300, 1)
    scrollFrame:SetScrollChild(pickerScrollChild)

    pickerFrame:Hide()
end

-- Formats a compact summary string for a template.
-- Shows recipient and a truncated subject to give context at a glance.
-- @param template (table) Template data table.
-- @return (string) Summary like "To: Thrall  |  Subject: Greetings".
local function FormatTemplateSummary(template)
    local parts = {}

    if template.recipient and template.recipient ~= "" then
        table.insert(parts, "To: " .. template.recipient)
    end

    if template.subject and template.subject ~= "" then
        local subj = template.subject
        if #subj > 25 then
            subj = subj:sub(1, 22) .. "..."
        end
        table.insert(parts, "Subj: " .. subj)
    end

    local totalMoney = (template.gold or 0) * 10000 +
                       (template.silver or 0) * 100 +
                       (template.copper or 0)
    if totalMoney > 0 then
        table.insert(parts, MR.FormatMoney(totalMoney))
    end

    if #parts == 0 then
        return "(empty template)"
    end

    return table.concat(parts, "  |  ")
end

-- Populates the picker frame with template rows from the database.
-- Clears existing rows and rebuilds. Called each time the picker opens
-- to reflect any changes (saves or deletes since last open).
local function PopulatePicker()
    CreatePickerFrame()

    -- Clear existing children.
    local children = { pickerScrollChild:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    local templates = MR.Addon.db.profile.mailTemplates
    local sorted = {}
    for name, _ in pairs(templates) do
        table.insert(sorted, name)
    end
    table.sort(sorted)

    if #sorted == 0 then
        local noData = pickerScrollChild:CreateFontString(nil, "OVERLAY",
            "GameFontNormal")
        noData:SetPoint("TOP", pickerScrollChild, "TOP", 0, -10)
        noData:SetText("No templates saved yet.")
        pickerScrollChild:SetHeight(30)
        return
    end

    local yOffset = -5
    local rowHeight = 50

    for _, name in ipairs(sorted) do
        local template = templates[name]

        local row = CreateFrame("Frame", nil, pickerScrollChild,
            "BackdropTemplate")
        row:SetSize(290, rowHeight - 5)
        row:SetPoint("TOPLEFT", pickerScrollChild, "TOPLEFT", 0, yOffset)
        row:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.6)

        -- Template name.
        local nameText = row:CreateFontString(nil, "OVERLAY",
            "GameFontNormal")
        nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
        nameText:SetText(name)
        nameText:SetTextColor(0.9, 0.8, 0.5)

        -- Summary line.
        local summary = row:CreateFontString(nil, "OVERLAY",
            "GameFontNormalSmall")
        summary:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
        summary:SetText(FormatTemplateSummary(template))
        summary:SetTextColor(0.7, 0.7, 0.7)

        -- Load button.
        local loadBtn = CreateFrame("Button", nil, row,
            "UIPanelButtonTemplate")
        loadBtn:SetSize(50, 18)
        loadBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -60, 4)
        loadBtn:SetText("Load")
        loadBtn:SetScript("OnClick", function()
            ApplyTemplate(template)
            pickerFrame:Hide()
        end)

        -- Delete button.
        local deleteBtn = CreateFrame("Button", nil, row,
            "UIPanelButtonTemplate")
        deleteBtn:SetSize(55, 18)
        deleteBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
        deleteBtn:SetText("Delete")
        deleteBtn:SetScript("OnClick", function()
            templates[name] = nil
            MR.Addon:Print("Template '" .. name .. "' deleted.")
            PopulatePicker()
        end)

        yOffset = yOffset - rowHeight
    end

    pickerScrollChild:SetHeight(math.abs(yOffset) + 10)
end

-------------------------------------------------------------------------------
-- SendMailFrame Buttons
-- "Save as Template" and "Load Template" buttons on the Blizzard send
-- mail frame. Created once on first MAIL_SHOW.
-------------------------------------------------------------------------------

-- Creates the Save and Load buttons on SendMailFrame.
local function CreateButtons()
    if buttonsCreated then return end
    buttonsCreated = true

    -- "Save as Template" button.
    local saveBtn = CreateFrame("Button", "MailroomTemplateSaveButton",
        SendMailFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(110, 22)
    saveBtn:SetPoint("BOTTOMLEFT", SendMailFrame, "BOTTOMLEFT", 8, 8)
    saveBtn:SetText("Save Template")
    saveBtn:SetScript("OnClick", function()
        StaticPopup_Show("MAILROOM_SAVE_TEMPLATE")
    end)

    -- "Load Template" button.
    local loadBtn = CreateFrame("Button", "MailroomTemplateLoadButton",
        SendMailFrame, "UIPanelButtonTemplate")
    loadBtn:SetSize(110, 22)
    loadBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
    loadBtn:SetText("Load Template")
    loadBtn:SetScript("OnClick", function()
        PopulatePicker()
        pickerFrame:Show()
    end)
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Creates the template buttons when the mailbox opens.
function MR.Templates:OnMailShow()
    if not MR.Addon.db.profile.templatesEnabled then return end
    CreateButtons()
end

-- Hides the picker frame when the mailbox closes.
function MR.Templates:OnMailClosed()
    if pickerFrame then
        pickerFrame:Hide()
    end
end
