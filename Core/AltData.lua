-- Mailroom / AltData.lua
-- Cross-character data tracking.
-- Records gold totals and mailbox item snapshots per character in the
-- factionrealm-scoped AceDB table. This data persists across sessions
-- and is shared between all characters on the same faction and realm,
-- enabling the "alt overview" feature that shows what each character
-- has in their mailbox.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- AltData Module
-------------------------------------------------------------------------------

MR.AltData = {}

-------------------------------------------------------------------------------
-- Character Identity
-- Built from UnitName + GetRealmName at login time. Stored once and
-- reused as the key into the altData table.
-------------------------------------------------------------------------------

local charKey = nil

-- Builds and caches the character key string ("Name-Realm").
-- Called once during OnEnable. Uses UnitFullName which returns name and
-- realm separately; on the home realm, realm may be nil so we fall back
-- to GetRealmName().
-- @return (string) Character key in "Name-Realm" format.
local function GetCharKey()
    if charKey then return charKey end

    local name, realm = UnitFullName("player")
    realm = realm or GetRealmName()
    charKey = name .. "-" .. realm
    return charKey
end

-------------------------------------------------------------------------------
-- Data Recording
-------------------------------------------------------------------------------

-- Snapshots the current character's gold total into the alt data table.
-- Called on PLAYER_MONEY and during login. Gold is stored in copper
-- (the raw value from GetMoney()) for precision.
function MR.AltData:UpdateGold()
    local key = GetCharKey()
    local db = MR.Addon.db.factionrealm.altData

    if not db[key] then
        db[key] = {}
    end

    db[key].gold = GetMoney()
    db[key].lastSeen = time()
end

-- Snapshots what the current character has in their mailbox.
-- Called after an inbox scan completes. Stores a summary (count of
-- items, total gold in mail) rather than full item details, to keep
-- the saved variables file small across many alts.
-- @param mailCache (table) The mail cache from MR.Inbox:GetCache().
function MR.AltData:UpdateMailSnapshot(mailCache)
    local key = GetCharKey()
    local db = MR.Addon.db.factionrealm.altData

    if not db[key] then
        db[key] = {}
    end

    local totalMoney = 0
    local totalItems = 0

    for _, info in ipairs(mailCache) do
        totalMoney = totalMoney + (info.money or 0)
        if info.hasItem then
            totalItems = totalItems + 1
        end
    end

    db[key].mailMoney = totalMoney
    db[key].mailItems = totalItems
    db[key].lastSeen = time()
end

-------------------------------------------------------------------------------
-- Data Access
-------------------------------------------------------------------------------

-- Returns the alt data table for all characters on this faction/realm.
-- Each entry is keyed by "Name-Realm" and contains:
--   gold      (number) copper held by that character
--   mailMoney (number) copper in that character's mailbox
--   mailItems (number) count of mails with items attached
--   lastSeen  (number) Unix timestamp of last update
-- @return (table) The full altData table from AceDB.
function MR.AltData:GetAll()
    return MR.Addon.db.factionrealm.altData
end

-- Returns alt data for a specific character.
-- @param key (string) Character key in "Name-Realm" format.
-- @return (table|nil) The character's data table, or nil if not tracked.
function MR.AltData:Get(key)
    return MR.Addon.db.factionrealm.altData[key]
end

-- Returns the character key for the currently logged-in character.
-- @return (string) "Name-Realm" for the current character.
function MR.AltData:GetCurrentKey()
    return GetCharKey()
end

-------------------------------------------------------------------------------
-- Event Handlers
-- Registered in Mailroom.lua OnEnable.
-------------------------------------------------------------------------------

-- Called on PLAYER_MONEY to keep the gold snapshot current.
function MR.AltData:OnPlayerMoney()
    self:UpdateGold()
end

-- Called on PLAYER_ENTERING_WORLD to record initial gold.
function MR.AltData:OnLogin()
    self:UpdateGold()
end
