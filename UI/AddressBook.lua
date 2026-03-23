-- Mailroom / AddressBook.lua
-- Autocomplete and address book UI.
-- Maintains a list of known contacts (characters the player has sent
-- mail to or received mail from) and provides a searchable dropdown
-- for the send mail recipient field. Contacts are stored in the
-- profile DB so each character can have their own address book.
--
-- Contact sources:
-- 1. Inbox senders — added automatically when mail is scanned
-- 2. Manual entries — player can add/remove contacts via /mr address
-- 3. Alt data — characters from MR.AltData are included automatically

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- AddressBook Module
-------------------------------------------------------------------------------

MR.AddressBook = {}

-------------------------------------------------------------------------------
-- Contact Management
-------------------------------------------------------------------------------

-- Adds a contact to the address book if not already present.
-- @param name (string) Character name, optionally with realm ("Name" or
--             "Name-Realm"). Names without a realm suffix are assumed to
--             be on the player's home realm.
function MR.AddressBook:Add(name)
    if not name or name == "" or name == "Unknown" then return end

    local db = MR.Addon.db.profile
    if not db.contacts then
        db.contacts = {}
    end

    -- Normalize: trim whitespace, store as-is (case sensitive to match
    -- WoW's character naming which is always Title Case).
    name = strtrim(name)
    if not db.contacts[name] then
        db.contacts[name] = {
            addedAt = time(),
            source  = "auto",  -- "auto" from inbox scan, "manual" from user
        }
    end
end

-- Removes a contact from the address book.
-- @param name (string) The exact contact name to remove.
function MR.AddressBook:Remove(name)
    local db = MR.Addon.db.profile
    if db.contacts then
        db.contacts[name] = nil
    end
end

-- Searches the address book for contacts matching a prefix.
-- Used by the send frame autocomplete. Returns up to 10 matches
-- sorted alphabetically.
-- @param prefix (string) The search prefix (case-insensitive).
-- @return (table) Array of matching contact name strings.
function MR.AddressBook:Search(prefix)
    local results = {}
    local db = MR.Addon.db.profile
    if not db.contacts then return results end

    local lowerPrefix = strlower(prefix)

    for name, _ in pairs(db.contacts) do
        if strlower(name):sub(1, #lowerPrefix) == lowerPrefix then
            table.insert(results, name)
        end
    end

    -- Include alt names from AltData
    local altData = MR.AltData:GetAll()
    if altData then
        for key, _ in pairs(altData) do
            -- AltData keys are "Name-Realm", extract just the name
            local altName = key:match("^([^-]+)")
            if altName and strlower(altName):sub(1, #lowerPrefix) == lowerPrefix then
                -- Avoid duplicates
                local found = false
                for _, existing in ipairs(results) do
                    if existing == altName then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(results, altName)
                end
            end
        end
    end

    table.sort(results)

    -- Cap results to prevent UI overflow
    if #results > 10 then
        local capped = {}
        for i = 1, 10 do
            capped[i] = results[i]
        end
        return capped
    end

    return results
end

-- Returns all contacts in the address book.
-- @return (table) Map of name -> { addedAt, source } entries.
function MR.AddressBook:GetAll()
    return MR.Addon.db.profile.contacts or {}
end

-------------------------------------------------------------------------------
-- Auto-Population
-- Scans inbox senders and adds them to the address book automatically.
-- Called after each inbox scan.
-------------------------------------------------------------------------------

-- Scans the mail cache and adds all senders to the address book.
-- @param mailCache (table) The mail cache from MR.Inbox:GetCache().
function MR.AddressBook:PopulateFromInbox(mailCache)
    for _, info in ipairs(mailCache) do
        self:Add(info.sender)
    end
end
