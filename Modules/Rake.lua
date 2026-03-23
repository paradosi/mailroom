-- Mailroom / Modules / Rake.lua
-- Session gold tracking with animated toast notification.
-- Tracks all gold collected from mail during a mailbox session and
-- displays both a chat summary and an animated toast when the mailbox
-- closes. Wraps TakeInboxMoney calls to capture the gold amount
-- before each take.
--
-- The Gold Toast is an animated frame that slides in from the bottom-
-- right, shows the Mailroom icon + gold amount, stays for 3 seconds,
-- then fades out. Falls back to a plain chat line if animations are
-- disabled or if no gold was collected.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Rake Module
-------------------------------------------------------------------------------

MR.Rake = {}

-------------------------------------------------------------------------------
-- Session State
-------------------------------------------------------------------------------

local sessionGold = 0  -- copper collected this session, resets on MAIL_SHOW

-------------------------------------------------------------------------------
-- Gold Capture
-- Wraps the MR.TakeInboxMoney shim to capture gold amounts as they
-- are collected. This wrap is installed once and persists for the
-- lifetime of the addon.
-------------------------------------------------------------------------------

local wrapInstalled = false

-- Installs a wrapper around MR.TakeInboxMoney that records the gold
-- amount from GetInboxHeaderInfo before the take executes.
local function InstallTakeMoneyWrap()
    if wrapInstalled then return end
    wrapInstalled = true

    local originalTakeMoney = MR.TakeInboxMoney
    MR.TakeInboxMoney = function(index, ...)
        -- Look up the gold amount before taking it.
        local _, _, _, _, money = MR.GetInboxHeaderInfo(index)
        if money and money > 0 then
            sessionGold = sessionGold + money
        end
        return originalTakeMoney(index, ...)
    end
end

-------------------------------------------------------------------------------
-- Gold Toast Animation
-- A small frame that slides in from the bottom-right corner, displays
-- the gold amount, and fades out after 3 seconds. Uses Blizzard's
-- built-in CreateAnimationGroup system.
-------------------------------------------------------------------------------

local toastFrame = nil

-- Creates the toast frame and its animation groups. Called once on
-- first use. The frame is hidden by default and shown via ShowToast().
local function CreateToastFrame()
    if toastFrame then return end

    -- Main toast container.
    toastFrame = CreateFrame("Frame", "MailroomGoldToast", UIParent,
        "BackdropTemplate")
    toastFrame:SetSize(260, 50)
    toastFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)
    toastFrame:SetFrameStrata("HIGH")
    toastFrame:Hide()

    -- Dark backdrop so text is readable over any background.
    toastFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 12,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    toastFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    toastFrame:SetBackdropBorderColor(0.8, 0.7, 0.2, 0.8)

    -- Addon icon on the left.
    local icon = toastFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface\\AddOns\\Mailroom\\Media\\icon")

    -- Gold coin icon next to the amount.
    local coinIcon = toastFrame:CreateTexture(nil, "ARTWORK")
    coinIcon:SetSize(20, 20)
    coinIcon:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    coinIcon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")

    -- Gold amount text.
    local amountText = toastFrame:CreateFontString(nil, "OVERLAY",
        "GameFontNormalLarge")
    amountText:SetPoint("LEFT", coinIcon, "RIGHT", 6, 0)
    amountText:SetPoint("RIGHT", -10, 0)
    amountText:SetJustifyH("LEFT")
    amountText:SetTextColor(1, 0.84, 0)
    toastFrame.amountText = amountText

    -- Animation group: fade in, hold, then fade out + slide down.
    local ag = toastFrame:CreateAnimationGroup()
    toastFrame.animGroup = ag

    -- Phase 1: fade in over 0.3 seconds.
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.3)
    fadeIn:SetOrder(1)
    fadeIn:SetSmoothing("IN")

    -- Phase 2: hold fully visible for 3 seconds.
    -- A zero-change alpha animation acts as a delay.
    local hold = ag:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(3.0)
    hold:SetOrder(2)

    -- Phase 3: fade out over 0.5 seconds.
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(3)
    fadeOut:SetSmoothing("OUT")

    -- Hide the frame when the animation finishes.
    ag:SetScript("OnFinished", function()
        toastFrame:Hide()
    end)
end

-- Shows the gold toast with the given copper amount.
-- @param copper (number) The total gold collected in copper.
local function ShowToast(copper)
    CreateToastFrame()

    -- Format the gold amount for display. We use a plain format here
    -- (not MR.FormatMoney) because the toast already has a coin icon.
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100

    local text
    if g > 0 then
        text = string.format("%dg %ds %dc", g, s, c)
    elseif s > 0 then
        text = string.format("%ds %dc", s, c)
    else
        text = string.format("%dc", c)
    end

    toastFrame.amountText:SetText(text)
    toastFrame:SetAlpha(0)
    toastFrame:Show()
    toastFrame.animGroup:Stop()
    toastFrame.animGroup:Play()

    -- Play the toast sound if SoundDesign is available and enabled.
    if MR.SoundDesign and MR.SoundDesign.PlayIfEnabled then
        MR.SoundDesign:PlayIfEnabled("TOAST_SHOW")
    end
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Resets the session counter each time the mailbox opens.
function MR.Rake:OnMailShow()
    if not MR.Addon.db.profile.rakeEnabled then return end
    sessionGold = 0
    InstallTakeMoneyWrap()
end

-- Shows the gold toast (or chat fallback) when the mailbox closes.
function MR.Rake:OnMailClosed()
    if not MR.Addon.db.profile.rakeEnabled then return end

    if sessionGold > 0 then
        -- Show animated toast if enabled, otherwise fall back to chat.
        if MR.Addon.db.profile.goldToastEnabled then
            ShowToast(sessionGold)
        else
            MR.Addon:Print(MR.FormatMoney(sessionGold) .. " collected from mail.")
        end
    end

    sessionGold = 0
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Returns the current session gold total in copper.
-- @return (number) Copper collected this session.
function MR.Rake:GetSessionGold()
    return sessionGold
end
