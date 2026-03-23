-- Mailroom / Mailroom.lua
-- AceAddon entry point, namespace initialization, AceDB setup, and
-- AceConfig options registration. This is the first Core file loaded
-- after Compat.lua and establishes the addon object that all other
-- modules reference via MR.Addon.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Addon Object
-- Creates the main AceAddon with AceConsole (slash commands + :Print) and
-- AceEvent (event registration) mixed in. Stored on MR so every file can
-- access it without globals.
-------------------------------------------------------------------------------

local Addon = LibStub("AceAddon-3.0"):NewAddon("Mailroom",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0"
)
MR.Addon = Addon

-------------------------------------------------------------------------------
-- AceDB Defaults
-- profile: per-character UI preferences, behavior toggles, and contacts.
-- factionrealm: shared across characters on the same faction+realm,
--               used for alt tracking (gold snapshots, item lists).
-------------------------------------------------------------------------------

local defaults = {
    profile = {
        throttleDelay     = 0.15,  -- seconds between queue operations
        skipCOD           = false, -- if true, skips COD mail during open-all
        autoCollect       = false, -- collect money/items immediately on mail open
        expiryWarningDays = 3,     -- warn when mail expires within this many days
        deleteEmpty       = true,  -- auto-delete empty read mail after collecting
        showMinimap       = false, -- reserved for future minimap button
        contacts          = {},    -- address book: name -> { addedAt, source }
    },
    factionrealm = {
        altData = {},              -- keyed by "Name-Realm", stores gold + item snapshots
    },
}

-------------------------------------------------------------------------------
-- AceConfig Options Table
-- Defines all user-facing settings in one place. Rendered by AceConfig
-- into the Blizzard Interface Options panel and via /mailroom config.
-------------------------------------------------------------------------------

local options = {
    name = "Mailroom",
    type = "group",
    args = {
        general = {
            name = "General",
            type = "group",
            order = 1,
            inline = true,
            args = {
                throttleDelay = {
                    name = "Throttle Delay",
                    desc = "Seconds between mail operations. Lower is faster but risks silent failures. 0.15 is safe for most connections.",
                    type = "range",
                    min = 0.05,
                    max = 1.0,
                    step = 0.05,
                    order = 1,
                    get = function() return Addon.db.profile.throttleDelay end,
                    set = function(_, val) Addon.db.profile.throttleDelay = val end,
                },
                skipCOD = {
                    name = "Skip COD Mail",
                    desc = "When collecting all mail, skip any mail that requires a COD payment instead of prompting.",
                    type = "toggle",
                    order = 2,
                    get = function() return Addon.db.profile.skipCOD end,
                    set = function(_, val) Addon.db.profile.skipCOD = val end,
                },
                autoCollect = {
                    name = "Auto-Collect on Open",
                    desc = "Automatically start collecting all mail when you open the mailbox.",
                    type = "toggle",
                    order = 3,
                    get = function() return Addon.db.profile.autoCollect end,
                    set = function(_, val) Addon.db.profile.autoCollect = val end,
                },
                deleteEmpty = {
                    name = "Delete Empty Mail",
                    desc = "Automatically delete mail after all attachments and gold have been collected.",
                    type = "toggle",
                    order = 4,
                    get = function() return Addon.db.profile.deleteEmpty end,
                    set = function(_, val) Addon.db.profile.deleteEmpty = val end,
                },
                expiryWarningDays = {
                    name = "Expiry Warning (Days)",
                    desc = "Show a warning when mail expires within this many days.",
                    type = "range",
                    min = 1,
                    max = 30,
                    step = 1,
                    order = 5,
                    get = function() return Addon.db.profile.expiryWarningDays end,
                    set = function(_, val) Addon.db.profile.expiryWarningDays = val end,
                },
            },
        },
    },
}

-------------------------------------------------------------------------------
-- Lifecycle Callbacks
-------------------------------------------------------------------------------

-- OnInitialize fires once when the addon is first loaded (before PLAYER_LOGIN).
-- Sets up the saved variables database and registers configuration UI.
function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("MailroomDB", defaults, true)

    LibStub("AceConfig-3.0"):RegisterOptionsTable("Mailroom", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Mailroom", "Mailroom")

    self:RegisterChatCommand("mailroom", "OnSlashCommand")
    self:RegisterChatCommand("mr", "OnSlashCommand")
end

-- OnEnable fires after PLAYER_LOGIN when the addon becomes active.
-- Registers events and kicks off any startup logic that requires
-- the game world to be available (event registration, alt data init).
function Addon:OnEnable()
    MR.MailFrame:RegisterEvents()
    MR.AltData:OnLogin()

    self:Print("Mailroom loaded. Type /mr help for commands.")
end

-------------------------------------------------------------------------------
-- Slash Command Handler
-- Routes /mailroom and /mr commands to subcommand handlers.
-------------------------------------------------------------------------------

-- Handles slash command input.
-- Supported subcommands:
--   (none) or "config"  — opens the settings panel
--   "help"              — prints available commands
--   "alts"              — shows alt gold overview
--   "address add <name>"  — adds a contact
--   "address remove <name>" — removes a contact
--   "address list"      — lists all contacts
--   "collect"           — triggers collect-all (if mailbox is open)
-- @param input (string) The text after /mailroom or /mr, trimmed.
function Addon:OnSlashCommand(input)
    local cmd, rest = self:GetArgs(input, 2, nil, input)

    if cmd == "config" or cmd == "" or cmd == nil then
        LibStub("AceConfigDialog-3.0"):Open("Mailroom")

    elseif cmd == "help" then
        self:Print("Mailroom Commands:")
        self:Print("  /mr config  — open settings")
        self:Print("  /mr alts  — show alt gold overview")
        self:Print("  /mr address list  — list contacts")
        self:Print("  /mr address add <name>  — add a contact")
        self:Print("  /mr address remove <name>  — remove a contact")
        self:Print("  /mr collect  — collect all mail (mailbox must be open)")

    elseif cmd == "alts" then
        self:ShowAlts()

    elseif cmd == "address" then
        local subcmd, name = self:GetArgs(rest or "", 2)
        if subcmd == "add" and name and name ~= "" then
            MR.AddressBook:Add(name)
            self:Print("Added " .. name .. " to address book.")
        elseif subcmd == "remove" and name and name ~= "" then
            MR.AddressBook:Remove(name)
            self:Print("Removed " .. name .. " from address book.")
        elseif subcmd == "list" then
            self:ShowAddressBook()
        else
            self:Print("Usage: /mr address <add|remove|list> [name]")
        end

    elseif cmd == "collect" then
        if MR.MailFrame:IsOpen() then
            MR.Inbox:CollectAll()
        else
            self:Print("You need to open a mailbox first.")
        end

    else
        self:Print("Unknown command '" .. cmd .. "'. Type /mr help for a list.")
    end
end

-------------------------------------------------------------------------------
-- Info Display Helpers
-------------------------------------------------------------------------------

-- Prints an overview of all tracked alts and their gold totals.
-- Shows character name, on-hand gold, and gold sitting in their mailbox.
function Addon:ShowAlts()
    local altData = MR.AltData:GetAll()
    local currentKey = MR.AltData:GetCurrentKey()
    local hasData = false

    self:Print("--- Alt Overview ---")
    for key, data in pairs(altData) do
        hasData = true
        local marker = (key == currentKey) and " *" or ""
        local gold = MR.FormatMoney(data.gold or 0)
        local mailGold = ""
        if data.mailMoney and data.mailMoney > 0 then
            mailGold = "  (mail: " .. MR.FormatMoney(data.mailMoney) .. ")"
        end
        local mailItems = ""
        if data.mailItems and data.mailItems > 0 then
            mailItems = "  [" .. data.mailItems .. " mail w/ items]"
        end
        self:Print("  " .. key .. marker .. ": " .. gold .. mailGold .. mailItems)
    end

    if not hasData then
        self:Print("  No alt data yet. Log in on other characters to populate.")
    end
end

-- Prints all contacts in the address book.
function Addon:ShowAddressBook()
    local contacts = MR.AddressBook:GetAll()
    local count = 0

    self:Print("--- Address Book ---")
    -- Sort contacts alphabetically for display.
    local sorted = {}
    for name, _ in pairs(contacts) do
        table.insert(sorted, name)
        count = count + 1
    end
    table.sort(sorted)

    for _, name in ipairs(sorted) do
        local info = contacts[name]
        local source = info.source == "manual" and " (manual)" or ""
        self:Print("  " .. name .. source)
    end

    if count == 0 then
        self:Print("  No contacts yet. Send or receive mail to auto-populate.")
    else
        self:Print("  " .. count .. " contact(s)")
    end
end
