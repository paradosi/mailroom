-- Mailroom / Mailroom.lua
-- AceAddon entry point, namespace initialization, AceDB setup, and
-- event coordination. All settings are defined in Core/Settings.lua.
-- This file is the central hub that initializes AceDB, registers
-- events, and delegates to modules.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Addon Object
-- Creates the main AceAddon with AceConsole (slash commands + :Print),
-- AceEvent (event registration), and AceTimer mixed in. Stored on MR
-- so every file can access it without globals.
-------------------------------------------------------------------------------

local Addon = LibStub("AceAddon-3.0"):NewAddon("Mailroom",
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0"
)
MR.Addon = Addon

-------------------------------------------------------------------------------
-- Inbox Cache
-- Shared mail cache that all modules read from. Rebuilt on every
-- MAIL_INBOX_UPDATE event. Stored on MR so modules can access it.
-------------------------------------------------------------------------------

MR.mailCache = {}
MR.mailFrameOpen = false

-- Scans all mail currently loaded in the inbox and rebuilds the cache.
-- Called on MAIL_INBOX_UPDATE. The cache is wiped and rebuilt each time
-- because mail indices shift as items are taken or deleted, making
-- incremental updates unreliable.
function MR.ScanInbox()
    wipe(MR.mailCache)

    local numItems = MR.GetInboxNumItems()
    for i = 1, numItems do
        local packageIcon, stationeryIcon, sender, subject, money,
              CODAmount, daysLeft, hasItem, wasRead, wasReturned,
              textCreated, canReply, isGM = MR.GetInboxHeaderInfo(i)

        MR.mailCache[i] = {
            index        = i,
            sender       = sender or "Unknown",
            subject      = subject or "",
            money        = money or 0,
            CODAmount    = CODAmount or 0,
            daysLeft     = daysLeft or 0,
            hasItem      = hasItem,
            wasRead      = wasRead,
            wasReturned  = wasReturned,
            isGM         = isGM,
            packageIcon  = packageIcon,
        }
    end

    return MR.mailCache
end

-------------------------------------------------------------------------------
-- Mail Type Classification
-- Identifies what kind of mail an item is by examining sender and subject.
-- Used by OpenAll to apply per-type filters. Returns a string type tag.
-------------------------------------------------------------------------------

-- Known AH sender names across clients.
local AH_SENDERS = {
    ["Auction House"] = true,
    ["Alliance Auction House"] = true,
    ["Horde Auction House"] = true,
    ["Booty Bay Auction House"] = true,
    ["Goblin Auction House"] = true,
}

-- The Postmaster sender name.
local POSTMASTER_SENDER = "The Postmaster"

-- Classifies a cached mail entry by type.
-- @param info (table) A mail info table from MR.mailCache.
-- @return (string) One of: "ah", "postmaster", "cod", "player", "system".
function MR.ClassifyMail(info)
    if info.CODAmount > 0 then
        return "cod"
    elseif AH_SENDERS[info.sender] then
        return "ah"
    elseif info.sender == POSTMASTER_SENDER then
        return "postmaster"
    elseif info.wasReturned or (not info.isGM and info.sender ~= "Unknown") then
        return "player"
    else
        return "system"
    end
end

-------------------------------------------------------------------------------
-- Bag Space Utility
-- Returns total free bag slots across all bags. Used by OpenAll to
-- enforce the minimum free slots threshold.
-------------------------------------------------------------------------------

-- Counts total free bag slots across all standard bags.
-- @return (number) Total free slots.
function MR.GetFreeBagSlots()
    local free = 0
    for bag = 0, MR.NUM_BAG_SLOTS do
        local slots = MR.GetContainerNumFreeSlots(bag)
        free = free + (slots or 0)
    end
    return free
end

-------------------------------------------------------------------------------
-- Lifecycle Callbacks
-------------------------------------------------------------------------------

-- OnInitialize fires once when the addon is first loaded (before PLAYER_LOGIN).
-- Sets up the saved variables database and registers configuration UI.
function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("MailroomDB", MR.defaults, true)

    -- AceConfig is still used for data storage and the Blizzard options
    -- fallback, but the primary UI is the custom SettingsWindow.
    local options = MR.Settings:BuildOptions()
    LibStub("AceConfig-3.0"):RegisterOptionsTable("Mailroom", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Mailroom", "Mailroom")

    self:RegisterChatCommand("mailroom", "OnSlashCommand")
    self:RegisterChatCommand("mr", "OnSlashCommand")
end

-- OnEnable fires after PLAYER_LOGIN when the addon becomes active.
-- Registers core events and initializes alt tracking.
function Addon:OnEnable()
    -- Core mail frame events.
    self:RegisterEvent("MAIL_SHOW", "OnMailShow")
    self:RegisterEvent("MAIL_CLOSED", "OnMailClosed")
    self:RegisterEvent("MAIL_INBOX_UPDATE", "OnMailInboxUpdate")

    -- Alt data events.
    self:RegisterEvent("PLAYER_MONEY", function()
        MR.AltData:UpdateGold()
    end)
    MR.AltData:OnLogin()

    self:Print("Mailroom loaded. Type /mr help for commands.")
end

-------------------------------------------------------------------------------
-- Core Event Handlers
-- These coordinate all modules. Individual modules hook into these
-- via their own MR.ModuleName:OnMailShow() etc. methods.
-------------------------------------------------------------------------------

-- MAIL_SHOW: player opened a mailbox.
function Addon:OnMailShow()
    MR.mailFrameOpen = true
    MR.ScanInbox()

    -- Create the settings button on the mail frame.
    MR.Settings:CreateMailFrameButton()

    -- Notify all modules that have an OnMailShow handler.
    local modules = { "OpenAll", "BulkSelect", "AddressBook", "QuickActions",
                      "CarbonCopy", "DoNotWant", "Forward", "QuickAttach",
                      "Rake", "TradeBlock", "EnhancedUI", "MailBag",
                      "Analytics", "Snooze", "Templates", "PendingIncome",
                      "ExpiryTicker", "SoundDesign" }
    for _, name in ipairs(modules) do
        local mod = MR[name]
        if mod and mod.OnMailShow then
            mod:OnMailShow()
        end
    end

    -- Update alt data with current mailbox contents.
    MR.AltData:UpdateMailSnapshot(MR.mailCache)
end

-- MAIL_CLOSED: player closed the mailbox.
function Addon:OnMailClosed()
    MR.mailFrameOpen = false
    MR.Queue.Clear()

    -- Notify all modules.
    local modules = { "OpenAll", "BulkSelect", "AddressBook", "QuickActions",
                      "CarbonCopy", "DoNotWant", "Forward", "QuickAttach",
                      "Rake", "TradeBlock", "EnhancedUI", "MailBag",
                      "Analytics", "Snooze", "Templates", "PendingIncome",
                      "ExpiryTicker", "SoundDesign" }
    for _, name in ipairs(modules) do
        local mod = MR[name]
        if mod and mod.OnMailClosed then
            mod:OnMailClosed()
        end
    end

    -- Final alt data snapshot.
    MR.AltData:UpdateMailSnapshot(MR.mailCache)
end

-- MAIL_INBOX_UPDATE: inbox contents changed while mailbox is open.
function Addon:OnMailInboxUpdate()
    if not MR.mailFrameOpen then return end
    MR.ScanInbox()

    -- Notify modules that care about inbox refresh.
    local modules = { "OpenAll", "BulkSelect", "DoNotWant", "EnhancedUI", "MailBag" }
    for _, name in ipairs(modules) do
        local mod = MR[name]
        if mod and mod.OnMailInboxUpdate then
            mod:OnMailInboxUpdate()
        end
    end
end

-------------------------------------------------------------------------------
-- Slash Command Handler
-------------------------------------------------------------------------------

-- Handles slash command input.
-- @param input (string) The text after /mailroom or /mr, trimmed.
function Addon:OnSlashCommand(input)
    local cmd, rest = self:GetArgs(input, 2, nil, input)

    if cmd == "config" or cmd == "" or cmd == nil then
        MR.Settings:Toggle()

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
            MR.AddressBook:AddContact(name, "manual")
            self:Print("Added " .. name .. " to address book.")
        elseif subcmd == "remove" and name and name ~= "" then
            MR.AddressBook:RemoveContact(name)
            self:Print("Removed " .. name .. " from address book.")
        elseif subcmd == "list" then
            self:ShowAddressBook()
        else
            self:Print("Usage: /mr address <add|remove|list> [name]")
        end

    elseif cmd == "collect" then
        if MR.mailFrameOpen then
            MR.OpenAll:CollectAll()
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
    local contacts = MR.Addon.db.profile.contacts or {}
    local count = 0

    self:Print("--- Address Book ---")
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
