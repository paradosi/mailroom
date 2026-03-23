-- Mailroom / Settings.lua
-- AceConfig options table and settings panel.
-- Defines all user-facing settings in one place, organized by module.
-- Each module gets its own section with a master on/off toggle.
-- A small arrow button on the mail frame opens the panel directly.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Settings Module
-------------------------------------------------------------------------------

MR.Settings = {}

-------------------------------------------------------------------------------
-- AceDB Defaults
-- profile: per-character UI preferences, module toggles, and settings.
-- factionrealm: shared across characters on the same faction+realm,
--               used for alt tracking and address book contacts.
-------------------------------------------------------------------------------

MR.defaults = {
    profile = {
        -- Core
        throttleDelay     = 0.15,  -- seconds between queue operations

        -- OpenAll
        openAllEnabled    = true,  -- master toggle for Open All module
        skipCOD           = true,  -- skip COD mail during open-all
        collectAH         = true,  -- collect auction house result mail
        collectPostmaster = true,  -- collect Postmaster system mail
        collectItems      = true,  -- collect mail with item attachments
        collectGold       = true,  -- collect mail with gold only
        minFreeBagSlots   = 2,     -- pause collection when fewer slots remain
        deleteEmpty       = true,  -- auto-delete empty mail after collecting

        -- BulkSelect
        bulkSelectEnabled = true,  -- master toggle for Bulk Select module

        -- AddressBook
        addressBookEnabled = true,  -- master toggle for Address Book module
        showFriends       = true,   -- include friends list in autocomplete
        showGuild         = true,   -- include guild roster in autocomplete
        showAlts          = true,   -- include alts in autocomplete
        prefillRecent     = false,  -- pre-fill To: with most recent recipient
        contacts          = {},     -- saved contacts: name -> { addedAt, source }
        recentRecipients  = {},     -- ordered list of recent send targets
        recentMaxCount    = 20,     -- max entries in recent recipients list

        -- QuickActions
        quickActionsEnabled = true, -- master toggle for Quick Actions module

        -- CarbonCopy
        carbonCopyEnabled = true,   -- master toggle for Carbon Copy module

        -- DoNotWant
        doNotWantEnabled  = true,   -- master toggle for Do Not Want module
        expiryGreenDays   = 3,      -- green threshold (more than N days)
        expiryYellowDays  = 1,      -- yellow threshold (more than N days, less than green)
        -- below yellowDays = red

        -- Forward
        forwardEnabled    = true,   -- master toggle for Forward module

        -- QuickAttach
        quickAttachEnabled = true,  -- master toggle for Quick Attach module
        quickAttachRecipients = {}, -- category -> default recipient name

        -- Rake
        rakeEnabled       = true,   -- master toggle for Rake (gold summary) module

        -- TradeBlock
        tradeBlockEnabled = true,   -- master toggle for Trade Block module
        blockTrades       = true,   -- block incoming trade requests at mailbox
        blockCharters     = true,   -- block guild charter requests at mailbox

        -- EnhancedUI
        enhancedUIEnabled = true,   -- master toggle for Enhanced UI module
        autoSubjectGold   = true,   -- auto-fill subject when sending gold
        autoSubjectText   = "Gold", -- default subject text for gold-only mail

        -- MailBag
        mailBagEnabled    = true,   -- master toggle for MailBag module
        mailBagAutoOpen   = false,  -- auto-open MailBag view on mailbox open
        mailBagShowQuality = true,  -- show item quality borders on bag slots
        mailBagShowGold   = true,   -- show gold as its own slot type

        -- Analytics
        analyticsEnabled     = true,  -- master toggle for Analytics module
        analyticsMaxSessions = 20,    -- max historical sessions to keep
        analyticsHistory     = {},    -- array of past session report tables

        -- Snooze
        snoozeEnabled    = true,  -- master toggle for Snooze module
        snoozedMail      = {},    -- { [mailKey] = expiryTimestamp }
        showSnoozed      = false, -- temporarily reveal all snoozed mail

        -- Templates
        templatesEnabled = true,  -- master toggle for Templates module
        mailTemplates    = {},    -- { [name] = { recipient, subject, body, gold, silver, copper } }

        -- PendingIncome
        pendingIncomeEnabled = true, -- master toggle for Pending Income module

        -- ExpiryTicker
        expiryTickerEnabled   = true, -- master toggle for Expiry Ticker module
        expiryTickerThreshold = 24,   -- hours: pulse minimap button when mail expires within

        -- SoundDesign
        soundEnabled         = true,  -- master toggle for all sounds
        soundItemCollect     = true,  -- play sound on item collect
        soundGoldCollect     = true,  -- play sound on gold collect
        soundOpenAllComplete = true,  -- play sound when open-all finishes
        soundMailReturned    = true,  -- play sound when mail is returned
        soundTradeBlocked    = true,  -- play sound when trade is blocked
        soundToastShow       = true,  -- play sound when gold toast appears

        -- Gold Toast (part of Rake)
        goldToastEnabled = true,  -- show animated gold toast on mailbox close
    },
    factionrealm = {
        altData         = {},     -- keyed by "Name-Realm", stores gold + item snapshots
        pendingListings = {},     -- AH listings tracked by PendingIncome module
        expiryCache     = {},     -- mail expiry timestamps cached by ExpiryTicker
    },
}

-------------------------------------------------------------------------------
-- Options Table Builder
-- Each module section has a master toggle as the first entry. Disabling
-- a module grays out all its child settings.
-------------------------------------------------------------------------------

-- Helper: returns a toggle option that enables/disables a module.
-- @param key (string) The profile key for this module's enabled state.
-- @param name (string) Display name of the module.
-- @param desc (string) Description shown in tooltip.
-- @param order (number) Sort order in the options panel.
-- @return (table) AceConfig option entry.
local function ModuleToggle(key, name, desc, order)
    return {
        name = name,
        desc = desc,
        type = "toggle",
        width = "full",
        order = order,
        get = function() return MR.Addon.db.profile[key] end,
        set = function(_, val) MR.Addon.db.profile[key] = val end,
    }
end

-- Helper: returns a disabled function that checks a module's enabled key.
-- Used to gray out child settings when the parent module is off.
-- @param key (string) The profile key for the module's enabled state.
-- @return (function) A function returning true when the module is disabled.
local function DisabledUnless(key)
    return function() return not MR.Addon.db.profile[key] end
end

-- Builds the full AceConfig options table. Called once during OnInitialize.
-- @return (table) AceConfig options table.
function MR.Settings:BuildOptions()
    return {
        name = "Mailroom",
        type = "group",
        childGroups = "tab",
        args = {
            ------------------- Core -------------------------------------------
            core = {
                name = "Core",
                type = "group",
                order = 1,
                args = {
                    throttleDelay = {
                        name = "Throttle Delay",
                        desc = "Seconds between mail operations. Lower is faster but risks silent failures. 0.15 is safe for most connections.",
                        type = "range",
                        min = 0.05, max = 1.0, step = 0.05,
                        order = 1,
                        get = function() return MR.Addon.db.profile.throttleDelay end,
                        set = function(_, val) MR.Addon.db.profile.throttleDelay = val end,
                    },
                },
            },

            ------------------- Open All ---------------------------------------
            openAll = {
                name = "Open All",
                type = "group",
                order = 2,
                args = {
                    enabled = ModuleToggle("openAllEnabled", "Enable Open All",
                        "Smart open-all button with mail type filtering and bag protection.", 1),
                    skipCOD = {
                        name = "Skip COD Mail",
                        desc = "Skip mail that requires a COD payment.",
                        type = "toggle", order = 2,
                        disabled = DisabledUnless("openAllEnabled"),
                        get = function() return MR.Addon.db.profile.skipCOD end,
                        set = function(_, val) MR.Addon.db.profile.skipCOD = val end,
                    },
                    collectAH = {
                        name = "Collect Auction House Mail",
                        desc = "Collect gold and items from AH results (won, outbid, expired, cancelled).",
                        type = "toggle", order = 3,
                        disabled = DisabledUnless("openAllEnabled"),
                        get = function() return MR.Addon.db.profile.collectAH end,
                        set = function(_, val) MR.Addon.db.profile.collectAH = val end,
                    },
                    collectPostmaster = {
                        name = "Collect Postmaster Mail",
                        desc = "Collect items from Postmaster system mail.",
                        type = "toggle", order = 4,
                        disabled = DisabledUnless("openAllEnabled"),
                        get = function() return MR.Addon.db.profile.collectPostmaster end,
                        set = function(_, val) MR.Addon.db.profile.collectPostmaster = val end,
                    },
                    collectItems = {
                        name = "Collect Item Mail",
                        desc = "Collect mail with item attachments.",
                        type = "toggle", order = 5,
                        disabled = DisabledUnless("openAllEnabled"),
                        get = function() return MR.Addon.db.profile.collectItems end,
                        set = function(_, val) MR.Addon.db.profile.collectItems = val end,
                    },
                    collectGold = {
                        name = "Collect Gold-Only Mail",
                        desc = "Collect mail that only contains gold (no items).",
                        type = "toggle", order = 6,
                        disabled = DisabledUnless("openAllEnabled"),
                        get = function() return MR.Addon.db.profile.collectGold end,
                        set = function(_, val) MR.Addon.db.profile.collectGold = val end,
                    },
                    minFreeBagSlots = {
                        name = "Minimum Free Bag Slots",
                        desc = "Pause collection when fewer than this many bag slots remain.",
                        type = "range",
                        min = 0, max = 20, step = 1,
                        order = 7,
                        disabled = DisabledUnless("openAllEnabled"),
                        get = function() return MR.Addon.db.profile.minFreeBagSlots end,
                        set = function(_, val) MR.Addon.db.profile.minFreeBagSlots = val end,
                    },
                    deleteEmpty = {
                        name = "Delete Empty Mail",
                        desc = "Auto-delete mail after all attachments and gold are collected.",
                        type = "toggle", order = 8,
                        disabled = DisabledUnless("openAllEnabled"),
                        get = function() return MR.Addon.db.profile.deleteEmpty end,
                        set = function(_, val) MR.Addon.db.profile.deleteEmpty = val end,
                    },
                },
            },

            ------------------- Bulk Select ------------------------------------
            bulkSelect = {
                name = "Bulk Select",
                type = "group",
                order = 3,
                args = {
                    enabled = ModuleToggle("bulkSelectEnabled", "Enable Bulk Select",
                        "Checkbox multi-selection on inbox rows with Shift and Ctrl click modifiers.", 1),
                },
            },

            ------------------- Address Book -----------------------------------
            addressBook = {
                name = "Address Book",
                type = "group",
                order = 4,
                args = {
                    enabled = ModuleToggle("addressBookEnabled", "Enable Address Book",
                        "Autocomplete dropdown on the send frame with contacts from multiple sources.", 1),
                    showFriends = {
                        name = "Include Friends List",
                        desc = "Show friends list contacts in autocomplete.",
                        type = "toggle", order = 2,
                        disabled = DisabledUnless("addressBookEnabled"),
                        get = function() return MR.Addon.db.profile.showFriends end,
                        set = function(_, val) MR.Addon.db.profile.showFriends = val end,
                    },
                    showGuild = {
                        name = "Include Guild Roster",
                        desc = "Show guild members in autocomplete.",
                        type = "toggle", order = 3,
                        disabled = DisabledUnless("addressBookEnabled"),
                        get = function() return MR.Addon.db.profile.showGuild end,
                        set = function(_, val) MR.Addon.db.profile.showGuild = val end,
                    },
                    showAlts = {
                        name = "Include Alts",
                        desc = "Show characters from alt tracking in autocomplete.",
                        type = "toggle", order = 4,
                        disabled = DisabledUnless("addressBookEnabled"),
                        get = function() return MR.Addon.db.profile.showAlts end,
                        set = function(_, val) MR.Addon.db.profile.showAlts = val end,
                    },
                    prefillRecent = {
                        name = "Pre-fill Recent Recipient",
                        desc = "Auto-fill the To: field with the most recently mailed player.",
                        type = "toggle", order = 5,
                        disabled = DisabledUnless("addressBookEnabled"),
                        get = function() return MR.Addon.db.profile.prefillRecent end,
                        set = function(_, val) MR.Addon.db.profile.prefillRecent = val end,
                    },
                },
            },

            ------------------- Quick Actions ----------------------------------
            quickActions = {
                name = "Quick Actions",
                type = "group",
                order = 5,
                args = {
                    enabled = ModuleToggle("quickActionsEnabled", "Enable Quick Actions",
                        "Modifier-key shortcuts on inbox rows: Shift-click to collect, Ctrl-click to return, Alt-click to forward.", 1),
                },
            },

            ------------------- Carbon Copy ------------------------------------
            carbonCopy = {
                name = "Carbon Copy",
                type = "group",
                order = 6,
                args = {
                    enabled = ModuleToggle("carbonCopyEnabled", "Enable Carbon Copy",
                        "Copy mail contents to the system clipboard (or a selectable text box on Classic).", 1),
                },
            },

            ------------------- Do Not Want ------------------------------------
            doNotWant = {
                name = "Do Not Want",
                type = "group",
                order = 7,
                args = {
                    enabled = ModuleToggle("doNotWantEnabled", "Enable Do Not Want",
                        "Expiry action icons on each inbox row showing what happens when mail expires.", 1),
                    expiryGreenDays = {
                        name = "Green Threshold (Days)",
                        desc = "Mail with more than this many days remaining shows green.",
                        type = "range",
                        min = 1, max = 30, step = 1,
                        order = 2,
                        disabled = DisabledUnless("doNotWantEnabled"),
                        get = function() return MR.Addon.db.profile.expiryGreenDays end,
                        set = function(_, val) MR.Addon.db.profile.expiryGreenDays = val end,
                    },
                    expiryYellowDays = {
                        name = "Yellow Threshold (Days)",
                        desc = "Mail with more than this many days (but less than green) shows yellow. Below this is red.",
                        type = "range",
                        min = 0.5, max = 15, step = 0.5,
                        order = 3,
                        disabled = DisabledUnless("doNotWantEnabled"),
                        get = function() return MR.Addon.db.profile.expiryYellowDays end,
                        set = function(_, val) MR.Addon.db.profile.expiryYellowDays = val end,
                    },
                },
            },

            ------------------- Forward ----------------------------------------
            forward = {
                name = "Forward",
                type = "group",
                order = 8,
                args = {
                    enabled = ModuleToggle("forwardEnabled", "Enable Forward",
                        "Forward button on open mail that pre-fills the send frame.", 1),
                },
            },

            ------------------- Quick Attach -----------------------------------
            quickAttach = {
                name = "Quick Attach",
                type = "group",
                order = 9,
                args = {
                    enabled = ModuleToggle("quickAttachEnabled", "Enable Quick Attach",
                        "Category buttons on the send frame for fast item attachment.", 1),
                },
            },

            ------------------- Rake ------------------------------------------
            rake = {
                name = "Rake",
                type = "group",
                order = 10,
                args = {
                    enabled = ModuleToggle("rakeEnabled", "Enable Rake",
                        "Track and display total gold collected during each mailbox session.", 1),
                    goldToast = {
                        name = "Gold Toast",
                        desc = "Show an animated toast notification with the gold total when the mailbox closes.",
                        type = "toggle", order = 2,
                        disabled = DisabledUnless("rakeEnabled"),
                        get = function() return MR.Addon.db.profile.goldToastEnabled end,
                        set = function(_, val) MR.Addon.db.profile.goldToastEnabled = val end,
                    },
                },
            },

            ------------------- Trade Block ------------------------------------
            tradeBlock = {
                name = "Trade Block",
                type = "group",
                order = 11,
                args = {
                    enabled = ModuleToggle("tradeBlockEnabled", "Enable Trade Block",
                        "Automatically decline trade and guild charter requests while the mailbox is open.", 1),
                    blockTrades = {
                        name = "Block Trade Requests",
                        desc = "Auto-decline incoming trade requests at the mailbox.",
                        type = "toggle", order = 2,
                        disabled = DisabledUnless("tradeBlockEnabled"),
                        get = function() return MR.Addon.db.profile.blockTrades end,
                        set = function(_, val) MR.Addon.db.profile.blockTrades = val end,
                    },
                    blockCharters = {
                        name = "Block Guild Charters",
                        desc = "Auto-decline guild charter signature requests at the mailbox.",
                        type = "toggle", order = 3,
                        disabled = DisabledUnless("tradeBlockEnabled"),
                        get = function() return MR.Addon.db.profile.blockCharters end,
                        set = function(_, val) MR.Addon.db.profile.blockCharters = val end,
                    },
                },
            },

            ------------------- Enhanced UI ------------------------------------
            enhancedUI = {
                name = "Enhanced UI",
                type = "group",
                order = 12,
                args = {
                    enabled = ModuleToggle("enhancedUIEnabled", "Enable Enhanced UI",
                        "Small improvements: auto subject for gold sends, full subject tooltips, session summary.", 1),
                    autoSubjectGold = {
                        name = "Auto Subject for Gold",
                        desc = "Auto-fill the subject line when sending gold with an empty subject.",
                        type = "toggle", order = 2,
                        disabled = DisabledUnless("enhancedUIEnabled"),
                        get = function() return MR.Addon.db.profile.autoSubjectGold end,
                        set = function(_, val) MR.Addon.db.profile.autoSubjectGold = val end,
                    },
                    autoSubjectText = {
                        name = "Auto Subject Text",
                        desc = "The default subject text used when sending gold.",
                        type = "input", order = 3,
                        disabled = DisabledUnless("enhancedUIEnabled"),
                        get = function() return MR.Addon.db.profile.autoSubjectText end,
                        set = function(_, val) MR.Addon.db.profile.autoSubjectText = val end,
                    },
                },
            },

            ------------------- MailBag ----------------------------------------
            mailBag = {
                name = "MailBag",
                type = "group",
                order = 13,
                args = {
                    enabled = ModuleToggle("mailBagEnabled", "Enable MailBag",
                        "Bag-style grid view of all inbox attachments.", 1),
                    autoOpen = {
                        name = "Auto-Open MailBag",
                        desc = "Automatically open the MailBag view when the mailbox opens.",
                        type = "toggle", order = 2,
                        disabled = DisabledUnless("mailBagEnabled"),
                        get = function() return MR.Addon.db.profile.mailBagAutoOpen end,
                        set = function(_, val) MR.Addon.db.profile.mailBagAutoOpen = val end,
                    },
                    showQuality = {
                        name = "Show Item Quality Borders",
                        desc = "Tint slot borders by item quality (common, uncommon, rare, etc.).",
                        type = "toggle", order = 3,
                        disabled = DisabledUnless("mailBagEnabled"),
                        get = function() return MR.Addon.db.profile.mailBagShowQuality end,
                        set = function(_, val) MR.Addon.db.profile.mailBagShowQuality = val end,
                    },
                    showGold = {
                        name = "Show Gold Slots",
                        desc = "Display gold from mail as its own slot type in the grid.",
                        type = "toggle", order = 4,
                        disabled = DisabledUnless("mailBagEnabled"),
                        get = function() return MR.Addon.db.profile.mailBagShowGold end,
                        set = function(_, val) MR.Addon.db.profile.mailBagShowGold = val end,
                    },
                },
            },

            ------------------- Analytics --------------------------------------
            analytics = {
                name = "Analytics",
                type = "group",
                order = 14,
                args = {
                    enabled = ModuleToggle("analyticsEnabled", "Enable Analytics",
                        "Session report panel tracking gold, items, AH sales, and time spent.", 1),
                    maxSessions = {
                        name = "Max Stored Sessions",
                        desc = "Number of historical sessions to keep in the database.",
                        type = "range",
                        min = 5, max = 100, step = 5,
                        order = 2,
                        disabled = DisabledUnless("analyticsEnabled"),
                        get = function() return MR.Addon.db.profile.analyticsMaxSessions end,
                        set = function(_, val) MR.Addon.db.profile.analyticsMaxSessions = val end,
                    },
                },
            },

            ------------------- Snooze -----------------------------------------
            snooze = {
                name = "Snooze",
                type = "group",
                order = 15,
                args = {
                    enabled = ModuleToggle("snoozeEnabled", "Enable Snooze",
                        "Temporarily hide specific mail from Mailroom views without deleting or returning.", 1),
                    showSnoozed = {
                        name = "Show Snoozed Mail",
                        desc = "Temporarily reveal all snoozed mail in Mailroom views.",
                        type = "toggle", order = 2,
                        disabled = DisabledUnless("snoozeEnabled"),
                        get = function() return MR.Addon.db.profile.showSnoozed end,
                        set = function(_, val) MR.Addon.db.profile.showSnoozed = val end,
                    },
                },
            },

            ------------------- Templates --------------------------------------
            templates = {
                name = "Templates",
                type = "group",
                order = 16,
                args = {
                    enabled = ModuleToggle("templatesEnabled", "Enable Templates",
                        "Save and load reusable outgoing mail templates.", 1),
                },
            },

            ------------------- Pending Income ---------------------------------
            pendingIncome = {
                name = "Pending Income",
                type = "group",
                order = 17,
                args = {
                    enabled = ModuleToggle("pendingIncomeEnabled", "Enable Pending Income",
                        "Track active AH listings and estimate incoming gold from sales.", 1),
                },
            },

            ------------------- Expiry Ticker ----------------------------------
            expiryTicker = {
                name = "Expiry Ticker",
                type = "group",
                order = 18,
                args = {
                    enabled = ModuleToggle("expiryTickerEnabled", "Enable Expiry Ticker",
                        "Minimap button with persistent expiry countdown, visible outside the mailbox.", 1),
                    threshold = {
                        name = "Alert Threshold (Hours)",
                        desc = "Pulse the minimap button when any mail expires within this many hours.",
                        type = "range",
                        min = 1, max = 72, step = 1,
                        order = 2,
                        disabled = DisabledUnless("expiryTickerEnabled"),
                        get = function() return MR.Addon.db.profile.expiryTickerThreshold end,
                        set = function(_, val) MR.Addon.db.profile.expiryTickerThreshold = val end,
                    },
                },
            },

            ------------------- Sound Design -----------------------------------
            soundDesign = {
                name = "Sound",
                type = "group",
                order = 19,
                args = {
                    enabled = ModuleToggle("soundEnabled", "Enable Sounds",
                        "Play sounds for Mailroom actions.", 1),
                    itemCollect = {
                        name = "Item Collect Sound", type = "toggle", order = 2,
                        disabled = DisabledUnless("soundEnabled"),
                        get = function() return MR.Addon.db.profile.soundItemCollect end,
                        set = function(_, val) MR.Addon.db.profile.soundItemCollect = val end,
                    },
                    goldCollect = {
                        name = "Gold Collect Sound", type = "toggle", order = 3,
                        disabled = DisabledUnless("soundEnabled"),
                        get = function() return MR.Addon.db.profile.soundGoldCollect end,
                        set = function(_, val) MR.Addon.db.profile.soundGoldCollect = val end,
                    },
                    openAllComplete = {
                        name = "Open All Complete Sound", type = "toggle", order = 4,
                        disabled = DisabledUnless("soundEnabled"),
                        get = function() return MR.Addon.db.profile.soundOpenAllComplete end,
                        set = function(_, val) MR.Addon.db.profile.soundOpenAllComplete = val end,
                    },
                    mailReturned = {
                        name = "Mail Returned Sound", type = "toggle", order = 5,
                        disabled = DisabledUnless("soundEnabled"),
                        get = function() return MR.Addon.db.profile.soundMailReturned end,
                        set = function(_, val) MR.Addon.db.profile.soundMailReturned = val end,
                    },
                    tradeBlocked = {
                        name = "Trade Blocked Sound", type = "toggle", order = 6,
                        disabled = DisabledUnless("soundEnabled"),
                        get = function() return MR.Addon.db.profile.soundTradeBlocked end,
                        set = function(_, val) MR.Addon.db.profile.soundTradeBlocked = val end,
                    },
                    toastShow = {
                        name = "Gold Toast Sound", type = "toggle", order = 7,
                        disabled = DisabledUnless("soundEnabled"),
                        get = function() return MR.Addon.db.profile.soundToastShow end,
                        set = function(_, val) MR.Addon.db.profile.soundToastShow = val end,
                    },
                },
            },
        },
    }
end

-------------------------------------------------------------------------------
-- Settings Panel Button
-- A small button on the Blizzard mail frame that opens the Mailroom
-- settings panel. Created once on first MAIL_SHOW.
-------------------------------------------------------------------------------

local settingsButtonCreated = false

-- Creates the settings button on the mail frame.
-- Called once from Mailroom.lua when the mail frame first opens.
function MR.Settings:CreateMailFrameButton()
    if settingsButtonCreated then return end
    settingsButtonCreated = true

    local btn = CreateFrame("Button", "MailroomSettingsButton",
        MailFrame, "UIPanelButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -60, -4)
    btn:SetText("Mailroom")
    btn:SetScript("OnClick", function()
        LibStub("AceConfigDialog-3.0"):Open("Mailroom")
    end)
end
