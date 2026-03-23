-- Mailroom / Modules / EnhancedUI.lua
-- Small targeted improvements to the default Blizzard mail frame.
-- Features:
--   Auto subject for gold: fills subject with "Gold" when sending gold
--     with an empty subject line.
--   Full subject on hover: shows the complete subject text in a tooltip
--     when hovering inbox rows that clip long subjects.
--   Session summary header: a line above the inbox showing total
--     attachments and gold waiting to be collected.
-- No changes to frame layout, sizing, or position — purely additive.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- EnhancedUI Module
-------------------------------------------------------------------------------

MR.EnhancedUI = {}

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local hooksInstalled = false
local sendHookInstalled = false
local summaryText = nil

-------------------------------------------------------------------------------
-- Auto Subject for Gold
-- When the player puts gold in the money fields but leaves the subject
-- empty, we fill it with the configured text (default "Gold").
-------------------------------------------------------------------------------

-- Installs a hook on the send button to auto-fill the subject.
local function InstallSendHook()
    if sendHookInstalled then return end
    sendHookInstalled = true

    local sendButton = SendMailMailButton
    if not sendButton then return end

    -- Pre-hook: runs before the send fires. We check the subject field
    -- and fill it if empty and gold is present.
    sendButton:HookScript("PreClick", function()
        if not MR.Addon.db.profile.enhancedUIEnabled then return end
        if not MR.Addon.db.profile.autoSubjectGold then return end

        local subject = SendMailSubjectEditBox:GetText()
        if subject and subject ~= "" then return end

        -- Check if gold is being sent.
        local gold = tonumber(SendMailMoneyGold:GetText()) or 0
        local silver = tonumber(SendMailMoneySilver:GetText()) or 0
        local copper = tonumber(SendMailMoneyCopper:GetText()) or 0
        if gold > 0 or silver > 0 or copper > 0 then
            local autoText = MR.Addon.db.profile.autoSubjectText or "Gold"
            SendMailSubjectEditBox:SetText(autoText)
        end
    end)
end

-------------------------------------------------------------------------------
-- Full Subject on Hover
-- Hooks inbox item button tooltips to show the full subject line.
-------------------------------------------------------------------------------

-- Installs hover hooks on inbox item buttons to show full subjects.
local function InstallInboxHoverHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- The inbox has 7 visible mail slots, named MailItem1 through MailItem7.
    for i = 1, 7 do
        local button = _G["MailItem" .. i]
        if button then
            button:HookScript("OnEnter", function(self)
                if not MR.Addon.db.profile.enhancedUIEnabled then return end

                -- The inbox button index maps to the mail cache via its
                -- InboxFrame.page offset + the button's visual position.
                local mailIndex = ((InboxFrame.pageNum - 1) * 7) + i
                local info = MR.mailCache[mailIndex]
                if info and info.subject and info.subject ~= "" then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(info.subject, 1, 1, 1, true)
                    GameTooltip:AddLine(info.sender, 0.7, 0.7, 0.7)
                    if info.daysLeft > 0 then
                        local dayText
                        if info.daysLeft < 1 then
                            dayText = "< 1 day"
                        else
                            dayText = math.floor(info.daysLeft) .. " day(s)"
                        end
                        GameTooltip:AddLine("Expires: " .. dayText, 0.6, 0.6, 0.6)
                    end
                    GameTooltip:Show()
                end
            end)
            button:HookScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
end

-------------------------------------------------------------------------------
-- Session Summary Header
-- Shows total attachments and gold across all inbox mail.
-------------------------------------------------------------------------------

-- Updates the session summary text above the inbox list.
local function UpdateSummary()
    if not summaryText then return end

    local cache = MR.mailCache
    local totalGold = 0
    local totalItems = 0

    for _, info in ipairs(cache) do
        totalGold = totalGold + info.money
        if info.hasItem then
            totalItems = totalItems + 1
        end
    end

    local parts = {}
    if totalItems > 0 then
        table.insert(parts, totalItems .. " with attachments")
    end
    if totalGold > 0 then
        table.insert(parts, MR.FormatMoney(totalGold) .. " waiting")
    end

    if #parts > 0 then
        summaryText:SetText(table.concat(parts, "  |  "))
        summaryText:Show()
    else
        summaryText:Hide()
    end
end

-- Creates the summary text FontString on the inbox frame.
local function CreateSummary()
    if summaryText then return end

    summaryText = InboxFrame:CreateFontString(nil, "OVERLAY",
        "GameFontNormalSmall")
    summaryText:SetPoint("TOP", InboxFrame, "TOP", 0, -28)
    summaryText:SetTextColor(0.9, 0.8, 0.5)
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

function MR.EnhancedUI:OnMailShow()
    if not MR.Addon.db.profile.enhancedUIEnabled then return end
    InstallSendHook()
    InstallInboxHoverHooks()
    CreateSummary()
    UpdateSummary()
end

function MR.EnhancedUI:OnMailInboxUpdate()
    if not MR.Addon.db.profile.enhancedUIEnabled then return end
    UpdateSummary()
end
