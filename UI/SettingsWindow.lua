-- Mailroom / SettingsWindow.lua
-- Fully custom settings window built with WoW's native Frame API.
-- Provides a sidebar-navigated, data-driven module configuration UI
-- without any dependency on AceGUI or AceConfigDialog. All settings
-- read and write directly to MR.Addon.db.profile for instant effect.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Settings Module
-- Extends the MR.Settings table (already created in Core/Settings.lua)
-- with custom window display methods.
-------------------------------------------------------------------------------

MR.Settings = MR.Settings or {}

-------------------------------------------------------------------------------
-- Color Constants
-- Warm, parchment-inspired palette used throughout the settings window.
-- All colors are RGBA tables suitable for SetColorTexture / SetTextColor.
-------------------------------------------------------------------------------

MR.Colors = {
    windowBg      = {0.10, 0.07, 0.03, 1.0},  -- main body background
    sidebarBg     = {0.06, 0.04, 0.02, 1.0},  -- left nav panel
    titlebarBg    = {0.18, 0.12, 0.04, 1.0},  -- top title strip
    borderGold    = {0.48, 0.38, 0.19, 1.0},  -- outer frame border
    textGold      = {0.91, 0.78, 0.44, 1.0},  -- primary text color
    textMuted     = {0.42, 0.34, 0.19, 1.0},  -- secondary / hint text
    accentGold    = {0.78, 0.56, 0.19, 1.0},  -- selected item left bar
    dotEnabled    = {0.23, 0.48, 0.23, 1.0},  -- green dot: module on
    dotDisabled   = {0.29, 0.22, 0.09, 1.0},  -- brown dot: module off
    groupBg       = {0.07, 0.05, 0.02, 1.0},  -- grouped-section backdrop
}

-------------------------------------------------------------------------------
-- Module Definitions
-- Data-driven table describing every module, its category, profile keys,
-- and individual settings. The UI is generated entirely from this table.
--
-- Supported setting types:
--   "toggle"  — boolean checkbox
--   "range"   — numeric stepper with +/- buttons
--   "input"   — single-line text edit box
--
-- enabledKey is the db.profile key for the master toggle. nil means
-- the module is always active (e.g., Core).
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
            { key = "throttleDelay", name = "Throttle Delay", desc = "Seconds between mail operations.", type = "range", min = 0.05, max = 1.0, step = 0.05 },
        },
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
local TOGGLE_PILL_W      = 40
local TOGGLE_PILL_H      = 20
local STEPPER_BTN_SIZE   = 18
local STEPPER_VALUE_W    = 50

-------------------------------------------------------------------------------
-- Forward Declarations
-------------------------------------------------------------------------------

local mainFrame           -- the top-level window frame
local sidebarFrame        -- left nav panel
local contentFrame        -- right panel container
local navItems = {}       -- { [moduleKey] = { button, dot, accent } }
local contentPanels = {}  -- { [moduleKey] = frame }  created lazily
local selectedModule      -- currently selected module key string
local BuildContentPanel   -- forward declaration; defined after row builders

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
-- Main Window Construction
-- Builds the top-level frame, title bar, sidebar, content area, and footer.
-- Called once on first Toggle/Show; the frame is then reused by showing
-- and hiding.
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

    -- Main background
    CreateSolidBg(f, unpack(MR.Colors.windowBg))

    -- 1px gold border around the entire window
    local borderSize = 1
    local bc = MR.Colors.borderGold

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

    -- Escape key closes the window via Blizzard's special frame mechanism.
    table.insert(UISpecialFrames, "MailroomSettingsWindow")

    return f
end

-------------------------------------------------------------------------------
-- Title Bar
-- Dark gradient strip at the top with "MAILROOM" in gold and a close button.
-------------------------------------------------------------------------------

-- Builds the title bar region.
-- @param parent (Frame) The main window frame.
-- @return (Frame) The title bar frame.
local function BuildTitleBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -1)
    bar:SetHeight(TITLEBAR_HEIGHT)

    CreateSolidBg(bar, unpack(MR.Colors.titlebarBg))

    -- Title text
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", bar, "LEFT", 12, 0)
    title:SetText("MAILROOM")
    title:SetTextColor(unpack(MR.Colors.textGold))

    -- Make the title bar draggable
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() parent:StartMoving() end)
    bar:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)

    -- Close button (top-right)
    local closeBtn = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() parent:Hide() end)

    -- Separator line below the title bar
    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(MR.Colors.borderGold[1], MR.Colors.borderGold[2],
        MR.Colors.borderGold[3], 0.6)
    sep:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

    return bar
end

-------------------------------------------------------------------------------
-- Footer
-- Thin bar at the bottom with hint text and a Close button.
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
    sep:SetColorTexture(MR.Colors.borderGold[1], MR.Colors.borderGold[2],
        MR.Colors.borderGold[3], 0.6)
    sep:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    sep:SetHeight(1)

    -- Hint text
    local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", bar, "LEFT", 12, 0)
    hint:SetText("Settings apply immediately. /mr to toggle.")
    hint:SetTextColor(unpack(MR.Colors.textMuted))

    -- Close button (bottom-right)
    local closeBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    closeBtn:SetSize(70, 20)
    closeBtn:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    closeBtn:SetText("Close")
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

    -- Visual indicator: small diagonal lines (using a simple texture)
    local tex = grip:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(grip)
    tex:SetColorTexture(MR.Colors.borderGold[1], MR.Colors.borderGold[2],
        MR.Colors.borderGold[3], 0.4)

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
-- shows a colored dot (green=enabled, brown=disabled) and highlights on
-- hover and selection.
-------------------------------------------------------------------------------

-- Updates a nav item's dot color based on the module's enabled state.
-- @param def (table) The module definition from MODULE_DEFS.
local function UpdateNavDot(def)
    local item = navItems[def.key]
    if not item or not item.dot then return end

    -- Core and other modules without an enabledKey are always "on".
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
-- updating visual state for all nav items.
-- @param moduleKey (string) The key from MODULE_DEFS to select.
local function SelectModule(moduleKey)
    selectedModule = moduleKey

    -- Update all nav items: show accent bar only on selected
    for key, item in pairs(navItems) do
        if key == moduleKey then
            item.accent:Show()
            item.label:SetTextColor(unpack(MR.Colors.textGold))
        else
            item.accent:Hide()
            item.label:SetTextColor(MR.Colors.textGold[1], MR.Colors.textGold[2],
                MR.Colors.textGold[3], 0.7)
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

    -- Right edge separator
    local sep = sidebar:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(MR.Colors.borderGold[1], MR.Colors.borderGold[2],
        MR.Colors.borderGold[3], 0.4)
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
        -- Category label
        local catLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -yOffset)
        catLabel:SetText(category:upper())
        catLabel:SetTextColor(unpack(MR.Colors.textMuted))
        yOffset = yOffset + CATEGORY_LABEL_H

        -- Module items in this category
        for _, def in ipairs(MODULE_DEFS) do
            if def.category == category then
                local itemBtn = CreateFrame("Button", nil, scrollChild)
                itemBtn:SetSize(SIDEBAR_WIDTH - 16, NAV_ITEM_HEIGHT)
                itemBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)

                -- Hover highlight
                local hoverBg = itemBtn:CreateTexture(nil, "BACKGROUND")
                hoverBg:SetAllPoints(itemBtn)
                hoverBg:SetColorTexture(MR.Colors.accentGold[1], MR.Colors.accentGold[2],
                    MR.Colors.accentGold[3], 0.08)
                hoverBg:Hide()

                itemBtn:SetScript("OnEnter", function() hoverBg:Show() end)
                itemBtn:SetScript("OnLeave", function() hoverBg:Hide() end)

                -- Gold left accent bar (visible only when selected)
                local accent = itemBtn:CreateTexture(nil, "ARTWORK")
                accent:SetColorTexture(unpack(MR.Colors.accentGold))
                accent:SetPoint("TOPLEFT", itemBtn, "TOPLEFT", 0, 0)
                accent:SetPoint("BOTTOMLEFT", itemBtn, "BOTTOMLEFT", 0, 0)
                accent:SetWidth(ACCENT_BAR_WIDTH)
                accent:Hide()

                -- Enabled/disabled dot
                local dot = itemBtn:CreateTexture(nil, "ARTWORK")
                dot:SetSize(NAV_DOT_SIZE, NAV_DOT_SIZE)
                dot:SetPoint("LEFT", itemBtn, "LEFT", 10, 0)
                dot:SetColorTexture(unpack(MR.Colors.dotEnabled))

                -- Module name label
                local label = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("LEFT", dot, "RIGHT", 8, 0)
                label:SetText(def.name)
                label:SetTextColor(MR.Colors.textGold[1], MR.Colors.textGold[2],
                    MR.Colors.textGold[3], 0.7)

                -- Store references for later updates
                navItems[def.key] = {
                    button = itemBtn,
                    dot    = dot,
                    accent = accent,
                    label  = label,
                }

                -- Click handler
                local moduleKey = def.key
                itemBtn:SetScript("OnClick", function()
                    SelectModule(moduleKey)
                end)

                -- Set initial dot color
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
-- Master Toggle (Pill Shape)
-- A styled on/off toggle resembling a pill-shaped switch. Green when
-- enabled, dark brown when disabled. Used for module master toggles.
-------------------------------------------------------------------------------

-- Creates a pill-shaped master toggle button.
-- @param parent (Frame) The parent frame to attach to.
-- @param profileKey (string) The db.profile key this toggle controls.
-- @param onChanged (function) Callback fired after the value changes.
--        Receives the new boolean value as its argument.
-- @return (Frame) The toggle frame.
local function CreatePillToggle(parent, profileKey, onChanged)
    local pill = CreateFrame("Button", nil, parent)
    pill:SetSize(TOGGLE_PILL_W, TOGGLE_PILL_H)

    -- Track background
    local track = pill:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(pill)

    -- Knob (the sliding circle)
    local knob = pill:CreateTexture(nil, "ARTWORK")
    knob:SetSize(TOGGLE_PILL_H - 4, TOGGLE_PILL_H - 4)

    -- Updates the visual state of the pill to match the current db value.
    local function Refresh()
        local val = MR.Addon.db.profile[profileKey]
        if val then
            track:SetColorTexture(MR.Colors.dotEnabled[1], MR.Colors.dotEnabled[2],
                MR.Colors.dotEnabled[3], 0.9)
            knob:SetPoint("RIGHT", pill, "RIGHT", -2, 0)
            knob:ClearAllPoints()
            knob:SetPoint("RIGHT", pill, "RIGHT", -2, 0)
            knob:SetColorTexture(0.85, 0.85, 0.85, 1.0)
        else
            track:SetColorTexture(MR.Colors.dotDisabled[1], MR.Colors.dotDisabled[2],
                MR.Colors.dotDisabled[3], 0.9)
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", pill, "LEFT", 2, 0)
            knob:SetColorTexture(0.55, 0.55, 0.55, 1.0)
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

-- Creates a toggle (checkbox) setting row.
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

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetText(settingDef.name)
    label:SetTextColor(unpack(MR.Colors.textGold))

    -- Checkbox
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    cb:SetSize(24, 24)

    -- Read current value
    cb:SetChecked(MR.Addon.db.profile[settingDef.key] or false)

    cb:SetScript("OnClick", function(self)
        MR.Addon.db.profile[settingDef.key] = self:GetChecked() and true or false
    end)

    -- Tooltip on the label
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
    row.Refresh = function()
        local disabled = moduleDef.enabledKey and not MR.Addon.db.profile[moduleDef.enabledKey]
        if disabled then
            label:SetTextColor(MR.Colors.textMuted[1], MR.Colors.textMuted[2],
                MR.Colors.textMuted[3], 0.5)
            cb:Disable()
        else
            label:SetTextColor(unpack(MR.Colors.textGold))
            cb:Enable()
        end
        cb:SetChecked(MR.Addon.db.profile[settingDef.key] or false)
    end

    parent._settingRows = parent._settingRows or {}
    table.insert(parent._settingRows, row)

    return ROW_HEIGHT
end

-- Creates a numeric stepper setting row with - and + buttons.
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

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetText(settingDef.name)
    label:SetTextColor(unpack(MR.Colors.textGold))

    -- Value display
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetPoint("RIGHT", row, "RIGHT", -STEPPER_BTN_SIZE - 4, 0)
    valueText:SetWidth(STEPPER_VALUE_W)
    valueText:SetJustifyH("CENTER")
    valueText:SetTextColor(unpack(MR.Colors.textGold))

    -- Format the displayed value. We show one decimal for steps < 1,
    -- otherwise integers.
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

    -- Plus button
    local plusBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    plusBtn:SetSize(STEPPER_BTN_SIZE, STEPPER_BTN_SIZE)
    plusBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    plusBtn:SetText("+")
    plusBtn:SetScript("OnClick", function()
        local cur = MR.Addon.db.profile[settingDef.key]
        local step = settingDef.step or 1
        local newVal = math.min(cur + step, settingDef.max)
        -- Round to avoid floating point drift
        newVal = math.floor(newVal / step + 0.5) * step
        MR.Addon.db.profile[settingDef.key] = newVal
        RefreshValue()
    end)

    -- Minus button
    local minusBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    minusBtn:SetSize(STEPPER_BTN_SIZE, STEPPER_BTN_SIZE)
    minusBtn:SetPoint("RIGHT", valueText, "LEFT", -4, 0)
    minusBtn:SetText("-")
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

    -- Refresh for disabled state
    row.Refresh = function()
        local disabled = moduleDef.enabledKey and not MR.Addon.db.profile[moduleDef.enabledKey]
        if disabled then
            label:SetTextColor(MR.Colors.textMuted[1], MR.Colors.textMuted[2],
                MR.Colors.textMuted[3], 0.5)
            valueText:SetTextColor(MR.Colors.textMuted[1], MR.Colors.textMuted[2],
                MR.Colors.textMuted[3], 0.5)
            plusBtn:Disable()
            minusBtn:Disable()
        else
            label:SetTextColor(unpack(MR.Colors.textGold))
            valueText:SetTextColor(unpack(MR.Colors.textGold))
            plusBtn:Enable()
            minusBtn:Enable()
        end
        RefreshValue()
    end

    parent._settingRows = parent._settingRows or {}
    table.insert(parent._settingRows, row)

    return ROW_HEIGHT
end

-- Creates a text input setting row.
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

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 0, 0)
    label:SetText(settingDef.name)
    label:SetTextColor(unpack(MR.Colors.textGold))

    -- EditBox
    local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    editBox:SetSize(120, 20)
    editBox:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontNormalSmall")
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
            label:SetTextColor(MR.Colors.textMuted[1], MR.Colors.textMuted[2],
                MR.Colors.textMuted[3], 0.5)
            editBox:Disable()
        else
            label:SetTextColor(unpack(MR.Colors.textGold))
            editBox:Enable()
        end
        editBox:SetText(MR.Addon.db.profile[settingDef.key] or "")
    end

    parent._settingRows = parent._settingRows or {}
    table.insert(parent._settingRows, row)

    return ROW_HEIGHT
end

-------------------------------------------------------------------------------
-- Content Panel Builder
-- Creates the right-side panel for a single module. Contains the header
-- with name, description, and master toggle, followed by setting rows.
-- Panels are created once and cached in contentPanels[].
-------------------------------------------------------------------------------

-- Forward-declared above SelectModule, defined here because it references
-- BuildToggleRow etc. which must be defined first.
-- @param def (table) A module definition from MODULE_DEFS.
-- @return (Frame) The content panel frame.
BuildContentPanel = function(def)
    local panel = CreateFrame("Frame", nil, contentFrame)
    panel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    panel._settingRows = {}

    local yOffset = CONTENT_PAD

    ---------------------------------------------------------------------------
    -- Header: module name, description, master toggle
    ---------------------------------------------------------------------------

    -- Module name
    local nameText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    nameText:SetText(def.name)
    nameText:SetTextColor(unpack(MR.Colors.textGold))

    -- Master toggle pill (only if the module has an enabledKey)
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
        pillToggle:SetPoint("RIGHT", panel, "RIGHT", -CONTENT_PAD, -yOffset - 8)
    end

    yOffset = yOffset + 20

    -- Description
    local descText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_PAD, -yOffset)
    descText:SetPoint("RIGHT", panel, "RIGHT", -(CONTENT_PAD + TOGGLE_PILL_W + 10), 0)
    descText:SetJustifyH("LEFT")
    descText:SetText(def.desc)
    descText:SetTextColor(unpack(MR.Colors.textMuted))

    yOffset = yOffset + 20

    -- Horizontal rule below header
    local hr = panel:CreateTexture(nil, "ARTWORK")
    hr:SetColorTexture(MR.Colors.borderGold[1], MR.Colors.borderGold[2],
        MR.Colors.borderGold[3], 0.4)
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
        noSettings:SetTextColor(unpack(MR.Colors.textMuted))
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
-- are built lazily on first selection.
-------------------------------------------------------------------------------

-- Assembles the entire settings window. Called once on first show.
local function AssembleWindow()
    mainFrame = BuildMainFrame()

    local titleBar = BuildTitleBar(mainFrame)
    local footer = BuildFooter(mainFrame)
    BuildResizeGrip(mainFrame)

    sidebarFrame = BuildSidebar(mainFrame, titleBar, footer)
    contentFrame = BuildContentContainer(mainFrame, sidebarFrame, titleBar, footer)

    -- Pre-build all content panels so switching is instant.
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
function MR.Settings:Show()
    if not mainFrame then
        AssembleWindow()
    end

    -- Refresh all nav dots and content rows in case profile values changed
    -- while the window was closed (e.g., via slash commands).
    for _, def in ipairs(MODULE_DEFS) do
        UpdateNavDot(def)
    end
    for _, panel in pairs(contentPanels) do
        if panel._settingRows then
            for _, row in ipairs(panel._settingRows) do
                if row.Refresh then row.Refresh() end
            end
        end
        -- Refresh pill toggles if present
        if panel._pillToggle then
            panel._pillToggle.Refresh()
        end
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
-- A small styled button anchored to the Blizzard MailFrame that opens
-- the custom settings window. Created once on first MAIL_SHOW.
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
