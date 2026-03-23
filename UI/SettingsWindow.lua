-- Mailroom / SettingsWindow.lua
-- Fully custom settings window built with WoW's native Frame API.
-- ElvUI-inspired dark flat design with configurable accent color.
-- Provides a sidebar-navigated, data-driven module configuration UI
-- without any dependency on AceGUI or AceConfigDialog. All settings
-- read and write directly to MR.Addon.db.profile for instant effect.
-- The Profiles panel integrates with AceDB for profile management.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Settings Module
-- Extends the MR.Settings table (already created in Core/Settings.lua)
-- with custom window display methods.
-------------------------------------------------------------------------------

MR.Settings = MR.Settings or {}

-------------------------------------------------------------------------------
-- Color Constants
-- Dark, flat, ElvUI-inspired palette. Near-black surfaces with a single
-- configurable accent color (cyan by default). All colors are RGBA tables
-- suitable for SetColorTexture / SetTextColor / SetBackdropColor.
-------------------------------------------------------------------------------

MR.Colors = {
    windowBg      = {0.067, 0.067, 0.071, 1.0},  -- #111112 near-black body
    sidebarBg     = {0.051, 0.051, 0.055, 1.0},  -- #0d0d0e darker sidebar
    titlebarBg    = {0.102, 0.102, 0.118, 1.0},  -- #1a1a1e title bar strip
    borderDark    = {0.165, 0.165, 0.180, 1.0},  -- #2a2a2e subtle border
    accentCyan    = {0.310, 0.765, 0.969, 1.0},  -- #4fc3f7 default accent
    textPrimary   = {0.910, 0.910, 0.925, 1.0},  -- #e8e8ec bright text
    textMuted     = {0.533, 0.533, 0.565, 1.0},  -- #888890 muted text
    textDim       = {0.267, 0.267, 0.284, 1.0},  -- #444448 dim text
    rowBg         = {0.086, 0.086, 0.094, 1.0},  -- #161618 row bg
    inputBg       = {0.078, 0.078, 0.086, 1.0},  -- #141416 input bg
    dotEnabled    = {0.298, 0.686, 0.314, 1.0},  -- #4caf50 green dot
    dotDisabled   = {0.165, 0.165, 0.188, 1.0},  -- #2a2a30 dark dot
    enabledBadge  = {0.102, 0.165, 0.102, 1.0},  -- #1a2a1a badge bg
}

-------------------------------------------------------------------------------
-- Module Definitions
-- Data-driven table describing every module, its category, profile keys,
-- and individual settings. The UI is generated entirely from this table.
--
-- Supported setting types:
--   "toggle"  -- boolean checkbox
--   "range"   -- numeric stepper with +/- buttons
--   "input"   -- single-line text edit box
--
-- enabledKey is the db.profile key for the master toggle. nil means
-- the module is always active (e.g., Core). The Profiles entry has
-- enabledKey = nil and uses custom panel building instead of data-driven
-- settings (its settings table is empty).
-------------------------------------------------------------------------------

local MODULE_DEFS = {
    ---------------------------------------------------------------------------
    -- General
    ---------------------------------------------------------------------------
    {
        key = "core",
        name = "Core",
        desc = "Throttle queue and general addon settings.",
        category = "General",
        enabledKey = nil,
        settings = {
            { key = "throttleDelay", name = "Throttle Delay", desc = "Seconds between mail operations. Lower is faster but risks silent failures.", type = "range", min = 0.05, max = 1.0, step = 0.05 },
        },
    },
    {
        key = "profiles",
        name = "Profiles",
        desc = "Manage AceDB profiles. Switch, copy, create, or reset settings profiles.",
        category = "General",
        enabledKey = nil,
        settings = {},
    },
    {
        key = "enhancedUI",
        name = "Enhanced UI",
        desc = "Auto subject lines, full subject tooltips, and session summary.",
        category = "General",
        enabledKey = "enhancedUIEnabled",
        settings = {
            { key = "autoSubjectGold", name = "Auto Subject for Gold", desc = "Auto-fill subject when sending gold.", type = "toggle" },
            { key = "autoSubjectText", name = "Auto Subject Text", desc = "Default subject text for gold-only mail.", type = "input" },
        },
    },
    {
        key = "sound",
        name = "Sound",
        desc = "Audio feedback for Mailroom actions.",
        category = "General",
        enabledKey = "soundEnabled",
        settings = {
            { key = "soundItemCollect", name = "Item Collect", desc = "Play sound when items are collected.", type = "toggle" },
            { key = "soundGoldCollect", name = "Gold Collect", desc = "Play sound when gold is collected.", type = "toggle" },
            { key = "soundOpenAllComplete", name = "Open All Complete", desc = "Play sound when open-all finishes.", type = "toggle" },
            { key = "soundMailReturned", name = "Mail Returned", desc = "Play sound when mail is returned.", type = "toggle" },
            { key = "soundTradeBlocked", name = "Trade Blocked", desc = "Play sound when a trade is blocked.", type = "toggle" },
            { key = "soundToastShow", name = "Gold Toast", desc = "Play sound when gold toast appears.", type = "toggle" },
        },
    },

    ---------------------------------------------------------------------------
    -- Inbox
    ---------------------------------------------------------------------------
    {
        key = "openAll",
        name = "Open All",
        desc = "Smart open-all with mail type filtering and bag space protection.",
        category = "Inbox",
        enabledKey = "openAllEnabled",
        settings = {
            { key = "skipCOD", name = "Skip COD Mail", desc = "Skip mail that requires a COD payment.", type = "toggle" },
            { key = "collectAH", name = "Collect AH Mail", desc = "Collect auction house result mail.", type = "toggle" },
            { key = "collectPostmaster", name = "Collect Postmaster Mail", desc = "Collect Postmaster system mail.", type = "toggle" },
            { key = "collectItems", name = "Collect Item Mail", desc = "Collect mail with item attachments.", type = "toggle" },
            { key = "collectGold", name = "Collect Gold-Only Mail", desc = "Collect mail with gold only.", type = "toggle" },
            { key = "minFreeBagSlots", name = "Min Free Bag Slots", desc = "Pause when fewer slots remain.", type = "range", min = 0, max = 20, step = 1 },
            { key = "deleteEmpty", name = "Delete Empty Mail", desc = "Auto-delete mail after collecting.", type = "toggle" },
        },
    },
    {
        key = "bulkSelect",
        name = "Bulk Select",
        desc = "Checkbox multi-selection on inbox rows with Shift and Ctrl modifiers.",
        category = "Inbox",
        enabledKey = "bulkSelectEnabled",
        settings = {},
    },
    {
        key = "quickActions",
        name = "Quick Actions",
        desc = "Modifier-key shortcuts: Shift-collect, Ctrl-return, Alt-forward.",
        category = "Inbox",
        enabledKey = "quickActionsEnabled",
        settings = {},
    },
    {
        key = "doNotWant",
        name = "Do Not Want",
        desc = "Expiry action icons showing what happens when mail expires.",
        category = "Inbox",
        enabledKey = "doNotWantEnabled",
        settings = {
            { key = "expiryGreenDays", name = "Green Threshold (Days)", desc = "Mail with more than this many days shows green.", type = "range", min = 1, max = 30, step = 1 },
            { key = "expiryYellowDays", name = "Yellow Threshold (Days)", desc = "Below green but above this shows yellow. Below is red.", type = "range", min = 0.5, max = 15, step = 0.5 },
        },
    },
    {
        key = "mailBag",
        name = "MailBag",
        desc = "Bag-style grid view of all inbox attachments.",
        category = "Inbox",
        enabledKey = "mailBagEnabled",
        settings = {
            { key = "mailBagAutoOpen", name = "Auto-Open MailBag", desc = "Open MailBag view when mailbox opens.", type = "toggle" },
            { key = "mailBagShowQuality", name = "Show Quality Borders", desc = "Tint slot borders by item quality.", type = "toggle" },
            { key = "mailBagShowGold", name = "Show Gold Slots", desc = "Display gold as its own slot type.", type = "toggle" },
        },
    },
    {
        key = "snooze",
        name = "Snooze",
        desc = "Temporarily hide specific mail without deleting or returning.",
        category = "Inbox",
        enabledKey = "snoozeEnabled",
        settings = {
            { key = "showSnoozed", name = "Show Snoozed Mail", desc = "Temporarily reveal all snoozed mail.", type = "toggle" },
        },
    },

    ---------------------------------------------------------------------------
    -- Sending
    ---------------------------------------------------------------------------
    {
        key = "addressBook",
        name = "Address Book",
        desc = "Autocomplete dropdown with contacts from friends, guild, and alts.",
        category = "Sending",
        enabledKey = "addressBookEnabled",
        settings = {
            { key = "showFriends", name = "Include Friends", desc = "Show friends list in autocomplete.", type = "toggle" },
            { key = "showGuild", name = "Include Guild", desc = "Show guild members in autocomplete.", type = "toggle" },
            { key = "showAlts", name = "Include Alts", desc = "Show alts in autocomplete.", type = "toggle" },
            { key = "prefillRecent", name = "Pre-fill Recent", desc = "Auto-fill To: with most recent recipient.", type = "toggle" },
        },
    },
    {
        key = "quickAttach",
        name = "Quick Attach",
        desc = "Category buttons on the send frame for fast item attachment.",
        category = "Sending",
        enabledKey = "quickAttachEnabled",
        settings = {},
    },
    {
        key = "forward",
        name = "Forward",
        desc = "Forward button on open mail that pre-fills the send frame.",
        category = "Sending",
        enabledKey = "forwardEnabled",
        settings = {},
    },
    {
        key = "carbonCopy",
        name = "Carbon Copy",
        desc = "Copy mail contents to clipboard or a selectable text box.",
        category = "Sending",
        enabledKey = "carbonCopyEnabled",
        settings = {},
    },
    {
        key = "templates",
        name = "Templates",
        desc = "Save and load reusable outgoing mail templates.",
        category = "Sending",
        enabledKey = "templatesEnabled",
        settings = {},
    },

    ---------------------------------------------------------------------------
    -- Tracking
    ---------------------------------------------------------------------------
    {
        key = "rake",
        name = "Rake",
        desc = "Track and display total gold collected during each mailbox session.",
        category = "Tracking",
        enabledKey = "rakeEnabled",
        settings = {
            { key = "goldToastEnabled", name = "Gold Toast", desc = "Animated gold toast when mailbox closes.", type = "toggle" },
        },
    },
    {
        key = "analytics",
        name = "Analytics",
        desc = "Session report tracking gold, items, AH sales, and time spent.",
        category = "Tracking",
        enabledKey = "analyticsEnabled",
        settings = {
            { key = "analyticsMaxSessions", name = "Max Stored Sessions", desc = "Number of historical sessions to keep.", type = "range", min = 5, max = 100, step = 5 },
        },
    },
    {
        key = "pendingIncome",
        name = "Pending Income",
        desc = "Track active AH listings and estimate incoming gold from sales.",
        category = "Tracking",
        enabledKey = "pendingIncomeEnabled",
        settings = {},
    },
    {
        key = "expiryTicker",
        name = "Expiry Ticker",
        desc = "Minimap button with persistent expiry countdown.",
        category = "Tracking",
        enabledKey = "expiryTickerEnabled",
        settings = {
            { key = "expiryTickerThreshold", name = "Alert Threshold (Hours)", desc = "Pulse minimap button when mail expires within this many hours.", type = "range", min = 1, max = 72, step = 1 },
        },
    },
    {
        key = "tradeBlock",
        name = "Trade Block",
        desc = "Auto-decline trades and guild charters while mailbox is open.",
        category = "Tracking",
        enabledKey = "tradeBlockEnabled",
        settings = {
            { key = "blockTrades", name = "Block Trades", desc = "Auto-decline incoming trade requests.", type = "toggle" },
            { key = "blockCharters", name = "Block Charters", desc = "Auto-decline guild charter requests.", type = "toggle" },
        },
    },
}

-- Category display order for the sidebar. Modules appear under these
-- headings in the order they are listed in MODULE_DEFS.
local CATEGORY_ORDER = { "General", "Inbox", "Sending", "Tracking" }

-------------------------------------------------------------------------------
-- Layout Constants
-- Dimensions and offsets used to build the window. Gathered here so
-- changes to proportions only require touching one place.
-------------------------------------------------------------------------------

local WINDOW_WIDTH       = 700
local WINDOW_HEIGHT      = 500
local WINDOW_MIN_W       = 600
local WINDOW_MIN_H       = 400
local WINDOW_MAX_W       = 1000
local WINDOW_MAX_H       = 800
local ACCENT_TOP_HEIGHT  = 3       -- thin accent bar across very top
local TITLEBAR_HEIGHT    = 32
local FOOTER_HEIGHT      = 28
local SIDEBAR_WIDTH      = 170
local CATEGORY_LABEL_H   = 20
local NAV_ITEM_HEIGHT    = 22
local NAV_DOT_SIZE       = 6
local ACCENT_BAR_WIDTH   = 3
local CONTENT_PAD        = 16
local HEADER_HEIGHT      = 50
local ROW_HEIGHT         = 28
local TOGGLE_PILL_W      = 44
local TOGGLE_PILL_H      = 22
local STEPPER_BTN_SIZE   = 22
local STEPPER_VALUE_W    = 50
local CLOSE_BTN_SIZE     = 20

-------------------------------------------------------------------------------
-- Forward Declarations
-------------------------------------------------------------------------------

local mainFrame           -- the top-level window frame
local sidebarFrame        -- left nav panel
local contentFrame        -- right panel container
local navItems = {}       -- { [moduleKey] = { button, dot, accent, label } }
local contentPanels = {}  -- { [moduleKey] = frame }  created lazily
local selectedModule      -- currently selected module key string
local BuildContentPanel   -- forward declaration; defined after row builders
local BuildProfilesPanel  -- forward declaration; custom profiles panel builder

-------------------------------------------------------------------------------
-- Utility: Backdrop Helper
-- BackdropTemplate is required on 9.0+ clients for SetBackdrop to work.
-- On Classic clients that lack it, we still create the frame normally
-- but without the template mixin.
-------------------------------------------------------------------------------

-- Returns the appropriate backdrop mixin name string, or nil on Classic
-- clients that do not require it.
local function GetBackdropMixin()
    if BackdropTemplateMixin then
        return "BackdropTemplate"
    end
    return nil
end

-- Creates a frame with optional backdrop template, handling the client
-- difference between 9.0+ (requires BackdropTemplate) and Classic.
-- @param frameType (string) Frame type, e.g. "Frame".
-- @param name (string|nil) Global name, or nil for anonymous.
-- @param parent (Frame) Parent frame.
-- @param extraTemplate (string|nil) Additional template to include.
-- @return (Frame) The created frame.
local function CreateBackdropFrame(frameType, name, parent, extraTemplate)
    local bdMixin = GetBackdropMixin()
    local tpl = nil
    if bdMixin and extraTemplate then
        tpl = bdMixin .. "," .. extraTemplate
    elseif bdMixin then
        tpl = bdMixin
    elseif extraTemplate then
        tpl = extraTemplate
    end
    return CreateFrame(frameType, name, parent, tpl)
end

-------------------------------------------------------------------------------
-- Utility: Color Texture
-- Shorthand for creating a solid-color texture on a frame. Used heavily
-- for backgrounds, borders, dots, and accent bars.
-------------------------------------------------------------------------------

-- Creates a solid-color texture filling the given frame.
-- @param frame (Frame) The parent frame.
-- @param r, g, b, a (number) Color components.
-- @return (Texture) The created texture.
local function CreateSolidBg(frame, r, g, b, a)
    local tex = frame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(frame)
    tex:SetColorTexture(r, g, b, a)
    return tex
end

-------------------------------------------------------------------------------
-- Utility: Styled Dark Button
-- A flat dark button with subtle border, used for footer Close button
-- and profile management buttons. Avoids the Blizzard gold standard
-- template to stay consistent with the dark theme.
-------------------------------------------------------------------------------

-- Creates a dark flat button with hover and press feedback.
-- @param parent (Frame) The parent frame.
-- @param width (number) Button width.
-- @param height (number) Button height.
-- @param text (string) Button label text.
-- @return (Button) The styled button.
local function CreateDarkButton(parent, width, height, text)
    local btn = CreateBackdropFrame("Button", nil, parent)
    btn:SetSize(width, height)

    -- Track background with subtle border
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropColor(0.12, 0.12, 0.13, 1.0)
    btn:SetBackdropBorderColor(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], MR.Colors.borderDark[4])

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(unpack(MR.Colors.textPrimary))
    btn._label = label

    -- Hover feedback: lighten background slightly.
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.16, 0.16, 0.18, 1.0)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.13, 1.0)
    end)

    -- Press feedback: darken background.
    btn:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.09, 1.0)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(0.16, 0.16, 0.18, 1.0)
    end)

    return btn
end

-------------------------------------------------------------------------------
-- Utility: Styled Dark EditBox
-- A flat dark input field with subtle border matching the dark theme.
-------------------------------------------------------------------------------

-- Creates a dark-themed EditBox without the default Blizzard template styling.
-- @param parent (Frame) Parent frame.
-- @param width (number) EditBox width.
-- @param height (number) EditBox height.
-- @return (EditBox) The styled edit box.
local function CreateDarkEditBox(parent, width, height)
    local container = CreateBackdropFrame("Frame", nil, parent)
    container:SetSize(width, height)
    container:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    container:SetBackdropColor(MR.Colors.inputBg[1], MR.Colors.inputBg[2],
        MR.Colors.inputBg[3], MR.Colors.inputBg[4])
    container:SetBackdropBorderColor(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], MR.Colors.borderDark[4])

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -2)
    editBox:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 2)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontNormalSmall")
    editBox:SetTextColor(unpack(MR.Colors.textPrimary))

    -- Store the container so callers can position it.
    editBox._container = container

    return editBox
end

-------------------------------------------------------------------------------
-- Main Window Construction
-- Builds the top-level frame, accent bar, title bar, sidebar, content
-- area, and footer. Called once on first Toggle/Show; the frame is then
-- reused by showing and hiding.
-------------------------------------------------------------------------------

-- Builds the entire settings window. Called only once.
-- @return (Frame) The main window frame.
local function BuildMainFrame()
    local f = CreateBackdropFrame("Frame", "MailroomSettingsWindow", UIParent)
    f:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)

    -- SetResizeBounds was added in 9.0; older clients use SetMinResize/SetMaxResize.
    if f.SetResizeBounds then
        f:SetResizeBounds(WINDOW_MIN_W, WINDOW_MIN_H, WINDOW_MAX_W, WINDOW_MAX_H)
    else
        f:SetMinResize(WINDOW_MIN_W, WINDOW_MIN_H)
        f:SetMaxResize(WINDOW_MAX_W, WINDOW_MAX_H)
    end

    -- Main background — near-black
    CreateSolidBg(f, unpack(MR.Colors.windowBg))

    -- 1px subtle border around the entire window
    local borderSize = 1
    local bc = MR.Colors.borderDark

    local borderTop = f:CreateTexture(nil, "BORDER")
    borderTop:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    borderTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(borderSize)

    local borderBot = f:CreateTexture(nil, "BORDER")
    borderBot:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    borderBot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    borderBot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    borderBot:SetHeight(borderSize)

    local borderLeft = f:CreateTexture(nil, "BORDER")
    borderLeft:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    borderLeft:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(borderSize)

    local borderRight = f:CreateTexture(nil, "BORDER")
    borderRight:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    borderRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(borderSize)

    -- 3px accent color bar across the very top of the window.
    -- This is the signature visual element — a thin cyan strip that
    -- immediately communicates the dark theme's accent color.
    local accentBar = f:CreateTexture(nil, "ARTWORK")
    accentBar:SetColorTexture(unpack(MR.Colors.accentCyan))
    accentBar:SetPoint("TOPLEFT", f, "TOPLEFT", borderSize, -borderSize)
    accentBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -borderSize, -borderSize)
    accentBar:SetHeight(ACCENT_TOP_HEIGHT)

    -- Escape key closes the window via Blizzard's special frame mechanism.
    table.insert(UISpecialFrames, "MailroomSettingsWindow")

    return f
end

-------------------------------------------------------------------------------
-- Title Bar
-- Slightly lighter dark strip below the accent bar with "MAILROOM" in
-- accent color (uppercase, spaced lettering) and a circular close button.
-------------------------------------------------------------------------------

-- Builds the title bar region.
-- @param parent (Frame) The main window frame.
-- @return (Frame) The title bar frame.
local function BuildTitleBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -(1 + ACCENT_TOP_HEIGHT))
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -(1 + ACCENT_TOP_HEIGHT))
    bar:SetHeight(TITLEBAR_HEIGHT)

    CreateSolidBg(bar, unpack(MR.Colors.titlebarBg))

    -- Title text — uppercase with letter spacing achieved via spaces.
    -- The accent color makes it pop against the dark title bar.
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", bar, "LEFT", 14, 0)
    title:SetText("M A I L R O O M")
    title:SetTextColor(unpack(MR.Colors.accentCyan))

    -- Make the title bar draggable so the player can reposition the window.
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() parent:StartMoving() end)
    bar:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)

    -- Circular close button (top-right).
    -- Built as a small dark circle with an "X" label. The circle is
    -- achieved with a backdrop and rounded edge file at small size.
    local closeBtn = CreateBackdropFrame("Button", nil, bar)
    closeBtn:SetSize(CLOSE_BTN_SIZE, CLOSE_BTN_SIZE)
    closeBtn:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    closeBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    closeBtn:SetBackdropColor(0.14, 0.14, 0.16, 1.0)
    closeBtn:SetBackdropBorderColor(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], MR.Colors.borderDark[4])

    local closeX = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeX:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeX:SetText("X")
    closeX:SetTextColor(unpack(MR.Colors.textMuted))

    closeBtn:SetScript("OnEnter", function(self)
        closeX:SetTextColor(unpack(MR.Colors.textPrimary))
        self:SetBackdropColor(0.20, 0.20, 0.22, 1.0)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        closeX:SetTextColor(unpack(MR.Colors.textMuted))
        self:SetBackdropColor(0.14, 0.14, 0.16, 1.0)
    end)
    closeBtn:SetScript("OnClick", function() parent:Hide() end)

    -- Separator line below the title bar
    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], 0.8)
    sep:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

    return bar
end

-------------------------------------------------------------------------------
-- Footer
-- Thin bar at the bottom with hint text on the left and a dark rounded
-- Close button on the right.
-------------------------------------------------------------------------------

-- Builds the footer bar.
-- @param parent (Frame) The main window frame.
-- @return (Frame) The footer frame.
local function BuildFooter(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 1, 1)
    bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)
    bar:SetHeight(FOOTER_HEIGHT)

    CreateSolidBg(bar, unpack(MR.Colors.titlebarBg))

    -- Separator line above the footer
    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], 0.8)
    sep:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    sep:SetHeight(1)

    -- Hint text
    local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", bar, "LEFT", 12, 0)
    hint:SetText("Settings apply immediately  |  /mr to toggle")
    hint:SetTextColor(unpack(MR.Colors.textDim))

    -- Close button (bottom-right) — dark styled
    local closeBtn = CreateDarkButton(bar, 70, 20, "Close")
    closeBtn:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    closeBtn:SetScript("OnClick", function() parent:Hide() end)

    return bar
end

-------------------------------------------------------------------------------
-- Resize Grip
-- A small draggable grip in the bottom-right corner that allows the
-- player to resize the window within the defined bounds.
-------------------------------------------------------------------------------

-- Builds the resize grip handle.
-- @param parent (Frame) The main window frame.
local function BuildResizeGrip(parent)
    local grip = CreateFrame("Frame", nil, parent)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    grip:EnableMouse(true)

    -- Visual indicator: subtle diagonal marks
    local tex = grip:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(grip)
    tex:SetColorTexture(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], 0.5)

    grip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            parent:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        parent:StopMovingOrSizing()
    end)
end

-------------------------------------------------------------------------------
-- Sidebar Navigation
-- Left panel with category headers and clickable module items. Each item
-- shows a colored dot (green=enabled, dark=disabled) and highlights on
-- hover and selection. Selected item gets a left accent bar in cyan.
-------------------------------------------------------------------------------

-- Updates a nav item's dot color based on the module's enabled state.
-- Modules without an enabledKey (Core, Profiles) always show green.
-- @param def (table) The module definition from MODULE_DEFS.
local function UpdateNavDot(def)
    local item = navItems[def.key]
    if not item or not item.dot then return end

    -- Core and Profiles have no enabledKey and are always "on".
    if not def.enabledKey then
        item.dot:SetColorTexture(unpack(MR.Colors.dotEnabled))
        return
    end

    local enabled = MR.Addon.db.profile[def.enabledKey]
    if enabled then
        item.dot:SetColorTexture(unpack(MR.Colors.dotEnabled))
    else
        item.dot:SetColorTexture(unpack(MR.Colors.dotDisabled))
    end
end

-- Selects a module in the sidebar, showing its content panel and
-- updating visual state for all nav items. The accent bar (left cyan
-- strip) is shown only on the selected item.
-- @param moduleKey (string) The key from MODULE_DEFS to select.
local function SelectModule(moduleKey)
    selectedModule = moduleKey

    -- Update all nav items: show accent bar only on selected, dim others
    for key, item in pairs(navItems) do
        if key == moduleKey then
            item.accent:Show()
            item.label:SetTextColor(unpack(MR.Colors.textPrimary))
        else
            item.accent:Hide()
            item.label:SetTextColor(MR.Colors.textPrimary[1], MR.Colors.textPrimary[2],
                MR.Colors.textPrimary[3], 0.6)
        end
    end

    -- Show/hide content panels
    for key, panel in pairs(contentPanels) do
        if key == moduleKey then
            panel:Show()
        else
            panel:Hide()
        end
    end

    -- Lazily build the content panel if it hasn't been created yet.
    -- This happens the first time a module is selected.
    if not contentPanels[moduleKey] then
        for _, def in ipairs(MODULE_DEFS) do
            if def.key == moduleKey then
                contentPanels[moduleKey] = BuildContentPanel(def)
                contentPanels[moduleKey]:Show()
                break
            end
        end
    end
end

-- Builds the entire sidebar with category headers and nav items.
-- @param parent (Frame) The main window frame.
-- @param titleBar (Frame) The title bar (for vertical anchoring).
-- @param footer (Frame) The footer bar (for vertical anchoring).
-- @return (Frame) The sidebar frame.
local function BuildSidebar(parent, titleBar, footer)
    local sidebar = CreateFrame("Frame", nil, parent)
    sidebar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)

    CreateSolidBg(sidebar, unpack(MR.Colors.sidebarBg))

    -- Right edge separator — subtle dark line between sidebar and content
    local sep = sidebar:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], 0.6)
    sep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sep:SetWidth(1)

    -- Scroll frame for the nav items so they don't clip if the
    -- window is resized to be short.
    local scrollFrame = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -16, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(SIDEBAR_WIDTH - 16)
    scrollFrame:SetScrollChild(scrollChild)

    local yOffset = 0

    -- Build category sections with their modules
    for _, category in ipairs(CATEGORY_ORDER) do
        -- Category label — uppercase, muted, acts as a section header
        local catLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset)
        catLabel:SetText(category:upper())
        catLabel:SetTextColor(unpack(MR.Colors.textDim))
        yOffset = yOffset + CATEGORY_LABEL_H

        -- Module items in this category
        for _, def in ipairs(MODULE_DEFS) do
            if def.category == category then
                local itemBtn = CreateFrame("Button", nil, scrollChild)
                itemBtn:SetSize(SIDEBAR_WIDTH - 16, NAV_ITEM_HEIGHT)
                itemBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)

                -- Hover highlight — very subtle lightening effect
                local hoverBg = itemBtn:CreateTexture(nil, "BACKGROUND")
                hoverBg:SetAllPoints(itemBtn)
                hoverBg:SetColorTexture(1.0, 1.0, 1.0, 0.03)
                hoverBg:Hide()

                itemBtn:SetScript("OnEnter", function() hoverBg:Show() end)
                itemBtn:SetScript("OnLeave", function() hoverBg:Hide() end)

                -- Left accent bar (accent cyan, visible only when selected)
                local accent = itemBtn:CreateTexture(nil, "ARTWORK")
                accent:SetColorTexture(unpack(MR.Colors.accentCyan))
                accent:SetPoint("TOPLEFT", itemBtn, "TOPLEFT", 0, 0)
                accent:SetPoint("BOTTOMLEFT", itemBtn, "BOTTOMLEFT", 0, 0)
                accent:SetWidth(ACCENT_BAR_WIDTH)
                accent:Hide()

                -- Enabled/disabled dot — 6px circle indicator
                local dot = itemBtn:CreateTexture(nil, "ARTWORK")
                dot:SetSize(NAV_DOT_SIZE, NAV_DOT_SIZE)
                dot:SetPoint("LEFT", itemBtn, "LEFT", 12, 0)
                dot:SetColorTexture(unpack(MR.Colors.dotEnabled))

                -- Module name label
                local label = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("LEFT", dot, "RIGHT", 8, 0)
                label:SetText(def.name)
                label:SetTextColor(MR.Colors.textPrimary[1], MR.Colors.textPrimary[2],
                    MR.Colors.textPrimary[3], 0.6)

                -- Store references for later updates
                navItems[def.key] = {
                    button = itemBtn,
                    dot    = dot,
                    accent = accent,
                    label  = label,
                }

                -- Click handler — select this module
                local moduleKey = def.key
                itemBtn:SetScript("OnClick", function()
                    SelectModule(moduleKey)
                end)

                -- Set initial dot color based on current db state
                UpdateNavDot(def)

                yOffset = yOffset + NAV_ITEM_HEIGHT
            end
        end

        -- Small gap between categories
        yOffset = yOffset + 8
    end

    -- Set the scroll child height so scrolling works correctly.
    scrollChild:SetHeight(yOffset)

    return sidebar
end

-------------------------------------------------------------------------------
-- Master Toggle (iOS-Style Pill)
-- A styled on/off toggle resembling an iOS switch. Green track + white
-- knob = enabled; dark track + gray knob = disabled. Used for module
-- master toggles, positioned on the same line as the module name in the
-- content panel header.
-------------------------------------------------------------------------------

-- Creates a pill-shaped master toggle button.
-- The track is a rounded capsule built with BackdropTemplate using the
-- tooltip edge file for soft rounded corners at small sizes. The knob
-- is a circular highlight texture that slides left/right.
-- @param parent (Frame) The parent frame to attach to.
-- @param profileKey (string) The db.profile key this toggle controls.
-- @param onChanged (function) Callback fired after the value changes.
--        Receives the new boolean value as its argument.
-- @return (Frame) The toggle frame with a .Refresh() method.
local function CreatePillToggle(parent, profileKey, onChanged)
    local pill = CreateFrame("Button", nil, parent)
    pill:SetSize(TOGGLE_PILL_W, TOGGLE_PILL_H)

    -- Track background — rounded rectangle built from backdrop system.
    -- The tooltip edge file provides soft rounded corners at the small
    -- pill size, giving the iOS-style capsule appearance.
    local trackBg = CreateBackdropFrame("Frame", nil, pill)
    trackBg:SetAllPoints(pill)
    trackBg:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    trackBg:EnableMouse(false)
    pill._trackBg = trackBg

    -- Knob — circular disc that slides between left (off) and right (on).
    -- Uses TempPortraitAlphaMask which is a clean filled circle texture
    -- available on all WoW clients.
    local KNOB_SIZE = TOGGLE_PILL_H - 6
    local knob = pill:CreateTexture(nil, "OVERLAY")
    knob:SetSize(KNOB_SIZE, KNOB_SIZE)
    knob:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    pill._knob = knob

    -- Hover highlight — subtle brightening on mouseover
    pill:SetScript("OnEnter", function(self)
        self._trackBg:SetAlpha(1.0)
    end)
    pill:SetScript("OnLeave", function(self)
        self._trackBg:SetAlpha(0.85)
    end)

    -- Updates the visual state of the pill to match the current db value.
    -- Green track + white knob on right = enabled.
    -- Dark track + gray knob on left = disabled.
    local function Refresh()
        local val = MR.Addon.db.profile[profileKey]
        knob:ClearAllPoints()
        if val then
            trackBg:SetBackdropColor(0.20, 0.55, 0.20, 0.95)
            trackBg:SetBackdropBorderColor(0.28, 0.65, 0.28, 0.7)
            knob:SetPoint("RIGHT", pill, "RIGHT", -3, 0)
            knob:SetVertexColor(0.95, 0.95, 0.95, 1.0)
        else
            trackBg:SetBackdropColor(0.12, 0.12, 0.14, 0.95)
            trackBg:SetBackdropBorderColor(0.20, 0.20, 0.22, 0.7)
            knob:SetPoint("LEFT", pill, "LEFT", 3, 0)
            knob:SetVertexColor(0.40, 0.40, 0.42, 1.0)
        end
    end

    pill:SetScript("OnClick", function()
        local newVal = not MR.Addon.db.profile[profileKey]
        MR.Addon.db.profile[profileKey] = newVal
        Refresh()
        if onChanged then
            onChanged(newVal)
        end
    end)

    pill.Refresh = Refresh
    Refresh()

    return pill
end

-------------------------------------------------------------------------------
-- Setting Row Builders
-- Each setting type (toggle, range, input) has a builder that creates
-- the appropriate control. All builders follow the same signature so
-- the content panel can loop over settings generically.
-------------------------------------------------------------------------------

-- Creates a toggle (styled checkbox) setting row.
-- The checkbox uses an accent-colored checkmark when checked.
-- @param parent (Frame) The content panel.
-- @param settingDef (table) Setting definition from MODULE_DEFS.
-- @param yOffset (number) Vertical offset from top of parent.
-- @param moduleDef (table) The parent module definition (for disabled state).
-- @return (number) The height consumed by this row.
local function BuildToggleRow(parent, settingDef, yOffset, moduleDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, -yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", -CONTENT_PAD, 0)
    row:SetHeight(ROW_HEIGHT)

    -- Subtle alternating row background for readability
    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints(row)
    rowBg:SetColorTexture(MR.Colors.rowBg[1], MR.Colors.rowBg[2],
        MR.Colors.rowBg[3], 0.4)

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetText(settingDef.name)
    label:SetTextColor(unpack(MR.Colors.textPrimary))

    -- Styled checkbox — dark background with accent-colored checkmark
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    cb:SetSize(22, 22)

    -- Read current value
    cb:SetChecked(MR.Addon.db.profile[settingDef.key] or false)

    cb:SetScript("OnClick", function(self)
        MR.Addon.db.profile[settingDef.key] = self:GetChecked() and true or false
    end)

    -- Tooltip on the label for discoverability
    if settingDef.desc then
        local lFrame = CreateFrame("Frame", nil, row)
        lFrame:SetAllPoints(label)
        lFrame:EnableMouse(true)
        lFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(settingDef.name, 1, 1, 1)
            GameTooltip:AddLine(settingDef.desc, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        lFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Store refresh function so we can update state when module toggle changes.
    -- When the module master toggle is off, child settings are dimmed and disabled.
    row.Refresh = function()
        local disabled = moduleDef.enabledKey and not MR.Addon.db.profile[moduleDef.enabledKey]
        if disabled then
            label:SetTextColor(MR.Colors.textDim[1], MR.Colors.textDim[2],
                MR.Colors.textDim[3], 0.7)
            cb:Disable()
        else
            label:SetTextColor(unpack(MR.Colors.textPrimary))
            cb:Enable()
        end
        cb:SetChecked(MR.Addon.db.profile[settingDef.key] or false)
    end

    parent._settingRows = parent._settingRows or {}
    table.insert(parent._settingRows, row)

    return ROW_HEIGHT
end

-- Creates a numeric stepper setting row with dark - and + buttons
-- flanking a centered value display.
-- @param parent (Frame) The content panel.
-- @param settingDef (table) Setting definition from MODULE_DEFS.
-- @param yOffset (number) Vertical offset from top of parent.
-- @param moduleDef (table) The parent module definition (for disabled state).
-- @return (number) The height consumed by this row.
local function BuildRangeRow(parent, settingDef, yOffset, moduleDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, -yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", -CONTENT_PAD, 0)
    row:SetHeight(ROW_HEIGHT)

    -- Subtle row background
    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints(row)
    rowBg:SetColorTexture(MR.Colors.rowBg[1], MR.Colors.rowBg[2],
        MR.Colors.rowBg[3], 0.4)

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetText(settingDef.name)
    label:SetTextColor(unpack(MR.Colors.textPrimary))

    -- Value display — centered between the - and + buttons
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetWidth(STEPPER_VALUE_W)
    valueText:SetJustifyH("CENTER")
    valueText:SetTextColor(unpack(MR.Colors.textPrimary))

    -- Format the displayed value. We show two decimals for steps < 1
    -- (e.g., throttle delay 0.15), otherwise integers.
    local function FormatValue(val)
        if settingDef.step and settingDef.step < 1 then
            return string.format("%.2f", val)
        else
            return tostring(math.floor(val + 0.5))
        end
    end

    local function RefreshValue()
        local val = MR.Addon.db.profile[settingDef.key]
        valueText:SetText(FormatValue(val))
    end

    RefreshValue()

    -- Plus button — dark rounded style
    local plusBtn = CreateDarkButton(row, STEPPER_BTN_SIZE, STEPPER_BTN_SIZE, "+")
    plusBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    plusBtn:SetScript("OnClick", function()
        local cur = MR.Addon.db.profile[settingDef.key]
        local step = settingDef.step or 1
        local newVal = math.min(cur + step, settingDef.max)
        -- Round to avoid floating point drift when using fractional steps
        newVal = math.floor(newVal / step + 0.5) * step
        MR.Addon.db.profile[settingDef.key] = newVal
        RefreshValue()
    end)

    -- Value text positioned between - and +
    valueText:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)

    -- Minus button — dark rounded style
    local minusBtn = CreateDarkButton(row, STEPPER_BTN_SIZE, STEPPER_BTN_SIZE, "-")
    minusBtn:SetPoint("RIGHT", valueText, "LEFT", -4, 0)
    minusBtn:SetScript("OnClick", function()
        local cur = MR.Addon.db.profile[settingDef.key]
        local step = settingDef.step or 1
        local newVal = math.max(cur - step, settingDef.min)
        newVal = math.floor(newVal / step + 0.5) * step
        MR.Addon.db.profile[settingDef.key] = newVal
        RefreshValue()
    end)

    -- Tooltip
    if settingDef.desc then
        local lFrame = CreateFrame("Frame", nil, row)
        lFrame:SetAllPoints(label)
        lFrame:EnableMouse(true)
        lFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(settingDef.name, 1, 1, 1)
            GameTooltip:AddLine(settingDef.desc, nil, nil, nil, true)
            GameTooltip:AddLine(string.format("Range: %s - %s",
                FormatValue(settingDef.min), FormatValue(settingDef.max)), 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        lFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Refresh for disabled state — grays out controls when module is off
    row.Refresh = function()
        local disabled = moduleDef.enabledKey and not MR.Addon.db.profile[moduleDef.enabledKey]
        if disabled then
            label:SetTextColor(MR.Colors.textDim[1], MR.Colors.textDim[2],
                MR.Colors.textDim[3], 0.7)
            valueText:SetTextColor(MR.Colors.textDim[1], MR.Colors.textDim[2],
                MR.Colors.textDim[3], 0.7)
            plusBtn:Disable()
            minusBtn:Disable()
        else
            label:SetTextColor(unpack(MR.Colors.textPrimary))
            valueText:SetTextColor(unpack(MR.Colors.textPrimary))
            plusBtn:Enable()
            minusBtn:Enable()
        end
        RefreshValue()
    end

    parent._settingRows = parent._settingRows or {}
    table.insert(parent._settingRows, row)

    return ROW_HEIGHT
end

-- Creates a text input setting row with a dark-themed EditBox.
-- @param parent (Frame) The content panel.
-- @param settingDef (table) Setting definition from MODULE_DEFS.
-- @param yOffset (number) Vertical offset from top of parent.
-- @param moduleDef (table) The parent module definition (for disabled state).
-- @return (number) The height consumed by this row.
local function BuildInputRow(parent, settingDef, yOffset, moduleDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, -yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", -CONTENT_PAD, 0)
    row:SetHeight(ROW_HEIGHT)

    -- Subtle row background
    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints(row)
    rowBg:SetColorTexture(MR.Colors.rowBg[1], MR.Colors.rowBg[2],
        MR.Colors.rowBg[3], 0.4)

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetText(settingDef.name)
    label:SetTextColor(unpack(MR.Colors.textPrimary))

    -- Dark-themed EditBox
    local editBox = CreateDarkEditBox(row, 140, 20)
    editBox._container:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    editBox:SetText(MR.Addon.db.profile[settingDef.key] or "")

    -- Commit on Enter or focus loss
    editBox:SetScript("OnEnterPressed", function(self)
        MR.Addon.db.profile[settingDef.key] = self:GetText()
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(MR.Addon.db.profile[settingDef.key] or "")
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        MR.Addon.db.profile[settingDef.key] = self:GetText()
    end)

    -- Tooltip
    if settingDef.desc then
        local lFrame = CreateFrame("Frame", nil, row)
        lFrame:SetAllPoints(label)
        lFrame:EnableMouse(true)
        lFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(settingDef.name, 1, 1, 1)
            GameTooltip:AddLine(settingDef.desc, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        lFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Refresh for disabled state
    row.Refresh = function()
        local disabled = moduleDef.enabledKey and not MR.Addon.db.profile[moduleDef.enabledKey]
        if disabled then
            label:SetTextColor(MR.Colors.textDim[1], MR.Colors.textDim[2],
                MR.Colors.textDim[3], 0.7)
            editBox:Disable()
        else
            label:SetTextColor(unpack(MR.Colors.textPrimary))
            editBox:Enable()
        end
        editBox:SetText(MR.Addon.db.profile[settingDef.key] or "")
    end

    parent._settingRows = parent._settingRows or {}
    table.insert(parent._settingRows, row)

    return ROW_HEIGHT
end

-------------------------------------------------------------------------------
-- Profiles Panel Builder
-- Custom-built panel for AceDB profile management. Unlike other modules,
-- the Profiles panel does not use the data-driven settings system. It
-- directly interfaces with AceDB's profile API to show a scrollable list
-- of profiles with Switch, Delete, New, Copy, and Reset functionality.
-------------------------------------------------------------------------------

-- Rebuilds the profile list inside the scrollable area.
-- Called on initial build and after any profile change (switch, create, delete).
-- @param scrollChild (Frame) The scroll child frame to populate.
-- @param panel (Frame) The parent content panel (for Refresh propagation).
local function RefreshProfileList(scrollChild, panel)
    -- Clear existing children by hiding and releasing them.
    -- We recreate the list each time because profile lists are small
    -- and the simplicity outweighs the cost of recreation.
    local children = { scrollChild:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    local db = MR.Addon.db
    local currentProfile = db:GetCurrentProfile()
    local profiles = db:GetProfiles()

    -- Sort profiles alphabetically for consistent display
    table.sort(profiles)

    local yOffset = 0
    local PROFILE_ROW_HEIGHT = 30

    for _, profileName in ipairs(profiles) do
        local row = CreateBackdropFrame("Frame", nil, scrollChild)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        row:SetHeight(PROFILE_ROW_HEIGHT)

        -- Row background
        row:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        row:SetBackdropColor(MR.Colors.rowBg[1], MR.Colors.rowBg[2],
            MR.Colors.rowBg[3], 0.6)
        row:SetBackdropBorderColor(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
            MR.Colors.borderDark[3], 0.4)

        local isActive = (profileName == currentProfile)

        -- Profile name label
        local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("LEFT", row, "LEFT", 10, 0)
        nameLabel:SetText(profileName)
        if isActive then
            nameLabel:SetTextColor(unpack(MR.Colors.accentCyan))
        else
            nameLabel:SetTextColor(unpack(MR.Colors.textPrimary))
        end

        -- "Active" badge — small green-tinted label shown on the current profile
        if isActive then
            local badge = CreateBackdropFrame("Frame", nil, row)
            badge:SetSize(48, 16)
            badge:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
            badge:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            badge:SetBackdropColor(MR.Colors.enabledBadge[1], MR.Colors.enabledBadge[2],
                MR.Colors.enabledBadge[3], 1.0)
            badge:SetBackdropBorderColor(MR.Colors.dotEnabled[1], MR.Colors.dotEnabled[2],
                MR.Colors.dotEnabled[3], 0.5)

            local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
            badgeText:SetText("Active")
            badgeText:SetTextColor(unpack(MR.Colors.dotEnabled))
        end

        -- Delete button — disabled if this is the active profile or the
        -- last remaining profile (AceDB requires at least one profile).
        local deleteBtn = CreateDarkButton(row, 52, 18, "Delete")
        deleteBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        if isActive or #profiles <= 1 then
            deleteBtn:Disable()
            deleteBtn._label:SetTextColor(MR.Colors.textDim[1], MR.Colors.textDim[2],
                MR.Colors.textDim[3], 0.5)
        else
            local pName = profileName
            deleteBtn:SetScript("OnClick", function()
                -- Confirmation popup before deleting a profile to prevent
                -- accidental data loss.
                StaticPopup_Show("MAILROOM_DELETE_PROFILE", pName)
            end)
        end

        -- Switch button — hidden if this is already the active profile
        if not isActive then
            local switchBtn = CreateDarkButton(row, 52, 18, "Switch")
            switchBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -4, 0)
            local pName = profileName
            switchBtn:SetScript("OnClick", function()
                db:SetProfile(pName)
                RefreshProfileList(scrollChild, panel)
                -- Refresh all panels and nav dots since profile data changed
                if panel._refreshAll then
                    panel._refreshAll()
                end
            end)
        end

        yOffset = yOffset + PROFILE_ROW_HEIGHT + 2
    end

    scrollChild:SetHeight(math.max(yOffset, 1))
end

-- Builds the full Profiles content panel with AceDB integration.
-- This is a special-case builder called instead of the standard
-- data-driven BuildContentPanel when the "profiles" module is selected.
-- @param parent (Frame) The content container frame.
-- @return (Frame) The profiles panel frame.
BuildProfilesPanel = function(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    panel._settingRows = {}

    local yOffset = CONTENT_PAD

    ---------------------------------------------------------------------------
    -- Header
    ---------------------------------------------------------------------------

    local nameText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    nameText:SetText("Profiles")
    nameText:SetTextColor(unpack(MR.Colors.accentCyan))

    yOffset = yOffset + 22

    local descText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    descText:SetPoint("RIGHT", panel, "RIGHT", -CONTENT_PAD, 0)
    descText:SetJustifyH("LEFT")
    descText:SetText("Manage AceDB profiles. Switch, copy, create, or reset settings profiles.")
    descText:SetTextColor(unpack(MR.Colors.textMuted))

    yOffset = yOffset + 20

    -- Horizontal rule
    local hr = panel:CreateTexture(nil, "ARTWORK")
    hr:SetColorTexture(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], 0.6)
    hr:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    hr:SetPoint("RIGHT", panel, "RIGHT", -CONTENT_PAD, 0)
    hr:SetHeight(1)

    yOffset = yOffset + 12

    ---------------------------------------------------------------------------
    -- Active Profile Display
    ---------------------------------------------------------------------------

    local activeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    activeLabel:SetText("Active Profile:")
    activeLabel:SetTextColor(unpack(MR.Colors.textMuted))

    local activeValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeValue:SetPoint("LEFT", activeLabel, "RIGHT", 8, 0)
    activeValue:SetText(MR.Addon.db:GetCurrentProfile())
    activeValue:SetTextColor(unpack(MR.Colors.accentCyan))

    yOffset = yOffset + 24

    ---------------------------------------------------------------------------
    -- Action Buttons Row: New Profile, Copy From, Reset to Defaults
    ---------------------------------------------------------------------------

    local newBtn = CreateDarkButton(panel, 100, 22, "New Profile")
    newBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    newBtn:SetScript("OnClick", function()
        StaticPopup_Show("MAILROOM_NEW_PROFILE")
    end)

    local copyBtn = CreateDarkButton(panel, 100, 22, "Copy From...")
    copyBtn:SetPoint("LEFT", newBtn, "RIGHT", 8, 0)
    copyBtn:SetScript("OnClick", function()
        StaticPopup_Show("MAILROOM_COPY_PROFILE")
    end)

    local resetBtn = CreateDarkButton(panel, 120, 22, "Reset to Defaults")
    resetBtn:SetPoint("LEFT", copyBtn, "RIGHT", 8, 0)
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("MAILROOM_RESET_PROFILE")
    end)

    yOffset = yOffset + 32

    ---------------------------------------------------------------------------
    -- Profile List (Scrollable)
    ---------------------------------------------------------------------------

    local listLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    listLabel:SetText("Saved Profiles")
    listLabel:SetTextColor(unpack(MR.Colors.textMuted))

    yOffset = yOffset + 16

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(CONTENT_PAD + 16), CONTENT_PAD)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Wire up the scroll child width to match the scroll frame width.
    -- OnSizeChanged fires when the parent panel resizes (e.g., window resize).
    scrollFrame:SetScript("OnSizeChanged", function(self, width)
        scrollChild:SetWidth(width)
    end)

    -- Store a refresh-all callback so profile switches can refresh the
    -- entire settings window (nav dots, setting rows, etc.).
    panel._refreshAll = function()
        activeValue:SetText(MR.Addon.db:GetCurrentProfile())
        for _, def in ipairs(MODULE_DEFS) do
            UpdateNavDot(def)
        end
        for _, p in pairs(contentPanels) do
            if p._settingRows then
                for _, row in ipairs(p._settingRows) do
                    if row.Refresh then row.Refresh() end
                end
            end
            if p._pillToggle and p._pillToggle.Refresh then
                p._pillToggle.Refresh()
            end
        end
    end

    -- Initial population of the profile list
    RefreshProfileList(scrollChild, panel)

    -- Store references so we can refresh from static popups
    panel._scrollChild = scrollChild
    panel._activeValue = activeValue

    return panel
end

-------------------------------------------------------------------------------
-- Static Popups for Profile Management
-- Registered once at file load time. These dialogs handle confirmation
-- and text input for creating, deleting, copying, and resetting profiles.
-------------------------------------------------------------------------------

StaticPopupDialogs["MAILROOM_NEW_PROFILE"] = {
    text = "Enter a name for the new profile:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        if name and name ~= "" then
            MR.Addon.db:SetProfile(name)
            -- Refresh the profiles panel if it exists
            local panel = contentPanels["profiles"]
            if panel and panel._scrollChild then
                RefreshProfileList(panel._scrollChild, panel)
                if panel._refreshAll then panel._refreshAll() end
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        if name and name ~= "" then
            MR.Addon.db:SetProfile(name)
            local panel = contentPanels["profiles"]
            if panel and panel._scrollChild then
                RefreshProfileList(panel._scrollChild, panel)
                if panel._refreshAll then panel._refreshAll() end
            end
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

StaticPopupDialogs["MAILROOM_DELETE_PROFILE"] = {
    text = "Delete profile \"%s\"? This cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, profileName)
        MR.Addon.db:DeleteProfile(profileName, true)
        local panel = contentPanels["profiles"]
        if panel and panel._scrollChild then
            RefreshProfileList(panel._scrollChild, panel)
            if panel._refreshAll then panel._refreshAll() end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MAILROOM_COPY_PROFILE"] = {
    text = "Enter the name of the profile to copy settings from:",
    button1 = "Copy",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        if name and name ~= "" then
            -- CopyProfile copies settings from the named profile into
            -- the current profile, overwriting current settings.
            MR.Addon.db:CopyProfile(name, true)
            local panel = contentPanels["profiles"]
            if panel and panel._scrollChild then
                RefreshProfileList(panel._scrollChild, panel)
                if panel._refreshAll then panel._refreshAll() end
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        if name and name ~= "" then
            MR.Addon.db:CopyProfile(name, true)
            local panel = contentPanels["profiles"]
            if panel and panel._scrollChild then
                RefreshProfileList(panel._scrollChild, panel)
                if panel._refreshAll then panel._refreshAll() end
            end
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

StaticPopupDialogs["MAILROOM_RESET_PROFILE"] = {
    text = "Reset the current profile to default values? This cannot be undone.",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        MR.Addon.db:ResetProfile(false, true)
        local panel = contentPanels["profiles"]
        if panel and panel._scrollChild then
            RefreshProfileList(panel._scrollChild, panel)
            if panel._refreshAll then panel._refreshAll() end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
-- Content Panel Builder
-- Creates the right-side panel for a single module. Contains the header
-- with name (in accent color), description (muted), and master toggle
-- pill (same line as name), followed by a horizontal rule and setting rows.
-- Panels are created once and cached in contentPanels[].
-- The Profiles module is a special case that uses BuildProfilesPanel.
-------------------------------------------------------------------------------

-- Forward-declared above SelectModule, defined here because it references
-- BuildToggleRow etc. which must be defined first.
-- @param def (table) A module definition from MODULE_DEFS.
-- @return (Frame) The content panel frame.
BuildContentPanel = function(def)
    -- Profiles gets a completely custom panel instead of data-driven rows.
    if def.key == "profiles" then
        return BuildProfilesPanel(contentFrame)
    end

    local panel = CreateFrame("Frame", nil, contentFrame)
    panel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    panel._settingRows = {}

    local yOffset = CONTENT_PAD

    ---------------------------------------------------------------------------
    -- Header: module name in accent color, description in muted, master toggle
    ---------------------------------------------------------------------------

    -- Module name — larger font, accent cyan color
    local nameText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    nameText:SetText(def.name)
    nameText:SetTextColor(unpack(MR.Colors.accentCyan))

    -- Master toggle pill (only if the module has an enabledKey).
    -- Positioned on the same line as the module name, right-aligned.
    -- This is the iOS-style pill toggle: green track = on, dark = off.
    local pillToggle = nil
    if def.enabledKey then
        pillToggle = CreatePillToggle(panel, def.enabledKey, function(newVal)
            -- Update the sidebar dot color when the master toggle changes.
            UpdateNavDot(def)
            -- Refresh all child setting rows to reflect enabled/disabled state.
            for _, row in ipairs(panel._settingRows) do
                if row.Refresh then row.Refresh() end
            end
        end)
        -- Anchor the pill to the right side of the header, vertically
        -- centered with the module name text.
        pillToggle:SetPoint("RIGHT", panel, "RIGHT", -CONTENT_PAD, 0)
        pillToggle:SetPoint("TOP", nameText, "TOP", 0, 2)
        panel._pillToggle = pillToggle
    end

    yOffset = yOffset + 22

    -- Description — one-line summary in muted text color
    local descText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    descText:SetPoint("RIGHT", panel, "RIGHT",
        -(CONTENT_PAD + (def.enabledKey and (TOGGLE_PILL_W + 10) or 0)), 0)
    descText:SetJustifyH("LEFT")
    descText:SetText(def.desc)
    descText:SetTextColor(unpack(MR.Colors.textMuted))

    yOffset = yOffset + 20

    -- Horizontal rule below header — subtle dark border color
    local hr = panel:CreateTexture(nil, "ARTWORK")
    hr:SetColorTexture(MR.Colors.borderDark[1], MR.Colors.borderDark[2],
        MR.Colors.borderDark[3], 0.6)
    hr:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    hr:SetPoint("RIGHT", panel, "RIGHT", -CONTENT_PAD, 0)
    hr:SetHeight(1)

    yOffset = yOffset + 12

    ---------------------------------------------------------------------------
    -- Setting Rows
    ---------------------------------------------------------------------------

    -- If no child settings, show a message indicating toggle-only module.
    if #def.settings == 0 then
        local noSettings = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noSettings:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
        noSettings:SetText("No additional settings. Use the toggle above to enable or disable.")
        noSettings:SetTextColor(unpack(MR.Colors.textDim))
    else
        for _, settingDef in ipairs(def.settings) do
            local consumed = 0
            if settingDef.type == "toggle" then
                consumed = BuildToggleRow(panel, settingDef, yOffset, def)
            elseif settingDef.type == "range" then
                consumed = BuildRangeRow(panel, settingDef, yOffset, def)
            elseif settingDef.type == "input" then
                consumed = BuildInputRow(panel, settingDef, yOffset, def)
            end
            yOffset = yOffset + consumed
        end
    end

    contentPanels[def.key] = panel
    return panel
end

-------------------------------------------------------------------------------
-- Content Container
-- The right-side region where module panels are shown. Anchored to the
-- right of the sidebar and between title bar and footer.
-------------------------------------------------------------------------------

-- Builds the content container frame.
-- @param parent (Frame) The main window frame.
-- @param sbar (Frame) The sidebar frame (for left anchoring).
-- @param titleBar (Frame) The title bar (for top anchoring).
-- @param footer (Frame) The footer (for bottom anchoring).
-- @return (Frame) The content container frame.
local function BuildContentContainer(parent, sbar, titleBar, footer)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", sbar, "TOPRIGHT", 0, 0)
    container:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -1, 0)

    return container
end

-------------------------------------------------------------------------------
-- Window Assembly
-- Wires all pieces together and pre-builds the sidebar. Content panels
-- are built lazily on first selection for efficiency, though we pre-build
-- all of them for instant switching.
-------------------------------------------------------------------------------

-- Assembles the entire settings window. Called once on first show.
local function AssembleWindow()
    mainFrame = BuildMainFrame()

    local titleBar = BuildTitleBar(mainFrame)
    local footer = BuildFooter(mainFrame)
    BuildResizeGrip(mainFrame)

    sidebarFrame = BuildSidebar(mainFrame, titleBar, footer)
    contentFrame = BuildContentContainer(mainFrame, sidebarFrame, titleBar, footer)

    -- Pre-build all content panels so switching between modules is instant.
    -- The memory cost is negligible since panels are simple frame trees.
    for _, def in ipairs(MODULE_DEFS) do
        BuildContentPanel(def)
    end

    -- Select the first module by default.
    SelectModule(MODULE_DEFS[1].key)

    mainFrame:Hide()
end

-------------------------------------------------------------------------------
-- Public API
-- MR.Settings:Toggle(), :Show(), :Hide() control the window.
-- MR.Settings:CreateMailFrameButton() adds a button on the Blizzard mail frame.
-------------------------------------------------------------------------------

-- Shows the settings window. Builds it on first call.
-- Refreshes all nav dots and content rows in case profile values changed
-- while the window was closed (e.g., via slash commands or profile switch).
function MR.Settings:Show()
    if not mainFrame then
        AssembleWindow()
    end

    -- Refresh all nav dots to reflect current enabled state
    for _, def in ipairs(MODULE_DEFS) do
        UpdateNavDot(def)
    end

    -- Refresh all setting rows and pill toggles in all panels
    for _, panel in pairs(contentPanels) do
        if panel._settingRows then
            for _, row in ipairs(panel._settingRows) do
                if row.Refresh then row.Refresh() end
            end
        end
        if panel._pillToggle and panel._pillToggle.Refresh then
            panel._pillToggle.Refresh()
        end
    end

    -- Refresh the profiles panel active profile display
    local profilesPanel = contentPanels["profiles"]
    if profilesPanel and profilesPanel._activeValue then
        profilesPanel._activeValue:SetText(MR.Addon.db:GetCurrentProfile())
    end
    if profilesPanel and profilesPanel._scrollChild then
        RefreshProfileList(profilesPanel._scrollChild, profilesPanel)
    end

    mainFrame:Show()
end

-- Hides the settings window.
function MR.Settings:Hide()
    if mainFrame then
        mainFrame:Hide()
    end
end

-- Toggles the settings window visibility.
function MR.Settings:Toggle()
    if mainFrame and mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-------------------------------------------------------------------------------
-- Mail Frame Button
-- A styled button anchored to the Blizzard MailFrame that opens
-- the custom settings window. Created once on first MAIL_SHOW.
-- Styled to match the dark theme with accent color hover state.
-------------------------------------------------------------------------------

local mailFrameButtonCreated = false

-- Creates the Mailroom button on the Blizzard mail frame.
-- Safe to call multiple times; only creates the button once.
function MR.Settings:CreateMailFrameButton()
    if mailFrameButtonCreated then return end
    mailFrameButtonCreated = true

    local btn = CreateFrame("Button", "MailroomSettingsButton", MailFrame, "UIPanelButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -60, -4)
    btn:SetText("Mailroom")
    btn:SetScript("OnClick", function()
        MR.Settings:Toggle()
    end)
end
