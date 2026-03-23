-- Mailroom / Modules / AddressBook.lua
-- Unified recipient picker attached to the send frame.
-- Pulls contacts from multiple sources: saved contacts, send history,
-- realm alts, friends list, and guild roster. Shows a live dropdown
-- of filtered matches as the player types in the To: field.
--
-- Contact sources are merged and deduplicated before display. Each
-- source can be independently toggled in settings. The dropdown uses
-- keyboard navigation (arrow keys, Tab/Enter to select, Escape to
-- dismiss) and hides when the field loses focus.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- AddressBook Module
-------------------------------------------------------------------------------

MR.AddressBook = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Maximum suggestions shown in the dropdown.
local MAX_SUGGESTIONS = 10

-- Height of each dropdown row in pixels.
local ROW_HEIGHT = 16

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local autocompleteInstalled = false
local sendHookInstalled = false
local dropdownFrame = nil
local suggestionRows = {}
local currentSuggestions = {}
local selectedIndex = 0

-- Guild roster cache, refreshed each MAIL_SHOW.
local guildCache = {}

-- Friends cache, refreshed each MAIL_SHOW.
local friendsCache = {}

-------------------------------------------------------------------------------
-- Contact Management
-- Saved contacts are stored in db.profile.contacts as a map of
-- name -> { addedAt, source }. The "source" field distinguishes
-- manual adds from auto-populated entries.
-------------------------------------------------------------------------------

-- Adds a contact to the saved contacts list.
-- @param name (string) Character name to add.
-- @param source (string) "auto" for inbox-populated, "manual" for user-added.
function MR.AddressBook:AddContact(name, source)
    if not name or name == "" or name == "Unknown" then return end

    local db = MR.Addon.db.profile
    name = strtrim(name)
    if not db.contacts[name] then
        db.contacts[name] = {
            addedAt = time(),
            source  = source or "auto",
        }
    end
end

-- Removes a contact from the saved contacts list.
-- @param name (string) The exact contact name to remove.
function MR.AddressBook:RemoveContact(name)
    MR.Addon.db.profile.contacts[name] = nil
end

-- Records a recipient in the send history. Called after successful send.
-- Maintains an ordered list capped at recentMaxCount.
-- @param name (string) The recipient name.
function MR.AddressBook:RecordSend(name)
    if not name or name == "" then return end

    local db = MR.Addon.db.profile
    local recent = db.recentRecipients

    -- Remove existing entry if present (we'll re-add at front).
    for i = #recent, 1, -1 do
        if recent[i] == name then
            table.remove(recent, i)
            break
        end
    end

    -- Insert at front.
    table.insert(recent, 1, name)

    -- Trim to max count.
    while #recent > db.recentMaxCount do
        table.remove(recent)
    end
end

-- Auto-populates contacts from the inbox cache senders.
-- Called on MAIL_SHOW after the inbox is scanned.
-- @param mailCache (table) The shared MR.mailCache table.
function MR.AddressBook:PopulateFromInbox(mailCache)
    for _, info in ipairs(mailCache) do
        self:AddContact(info.sender, "auto")
    end
end

-------------------------------------------------------------------------------
-- Source Gathering
-- Each source returns a list of { name, source } pairs. Sources are
-- gathered on demand when the player types in the recipient field.
-------------------------------------------------------------------------------

-- Refreshes the friends list cache.
-- On Retail, C_FriendList.GetFriendInfoByIndex returns a table.
-- On Classic, GetFriendInfo returns multiple values.
local function RefreshFriends()
    wipe(friendsCache)

    local numFriends = MR.GetNumFriends() or 0
    for i = 1, numFriends do
        if MR.GetFriendInfoByIndex then
            -- Retail: returns a table with .name field.
            local info = MR.GetFriendInfoByIndex(i)
            if info and info.name then
                table.insert(friendsCache, info.name)
            end
        elseif MR.GetFriendInfo then
            -- Classic: returns name as first value.
            local name = MR.GetFriendInfo(i)
            if name then
                table.insert(friendsCache, name)
            end
        end
    end
end

-- Refreshes the guild roster cache.
-- Triggers a server query via GuildRoster() and reads results from
-- GetGuildRosterInfo. The query is async but roster data is usually
-- available by the time the player starts typing.
local function RefreshGuild()
    wipe(guildCache)

    if not IsInGuild() then return end

    -- Request fresh data from the server.
    if MR.GuildRoster then
        MR.GuildRoster()
    end

    local numMembers = GetNumGuildMembers() or 0
    for i = 1, numMembers do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name then
            -- Guild names come as "Name-Realm"; strip the realm for
            -- same-realm members to keep autocomplete clean.
            local shortName = name:match("^([^-]+)")
            table.insert(guildCache, shortName or name)
        end
    end
end

-- Gathers all contacts from all enabled sources and returns a
-- deduplicated, sorted list matching the given prefix.
-- @param prefix (string) The search prefix (case-insensitive).
-- @return (table) Array of matching name strings, capped at MAX_SUGGESTIONS.
function MR.AddressBook:Search(prefix)
    if not prefix or prefix == "" then return {} end

    local db = MR.Addon.db.profile
    local lowerPrefix = strlower(prefix)
    local seen = {}
    local results = {}

    -- Helper to add a name if it matches and isn't a duplicate.
    local function TryAdd(name)
        if not name then return end
        local lower = strlower(name)
        if lower:sub(1, #lowerPrefix) == lowerPrefix and not seen[lower] then
            seen[lower] = true
            table.insert(results, name)
        end
    end

    -- Source 1: Saved contacts.
    for name, _ in pairs(db.contacts) do
        TryAdd(name)
    end

    -- Source 2: Recent recipients (send history).
    for _, name in ipairs(db.recentRecipients) do
        TryAdd(name)
    end

    -- Source 3: Alts from AltData.
    if db.showAlts and MR.AltData then
        local altData = MR.AltData:GetAll()
        if altData then
            for key, _ in pairs(altData) do
                local altName = key:match("^([^-]+)")
                TryAdd(altName)
            end
        end
    end

    -- Source 4: Friends list.
    if db.showFriends then
        for _, name in ipairs(friendsCache) do
            TryAdd(name)
        end
    end

    -- Source 5: Guild roster.
    if db.showGuild then
        for _, name in ipairs(guildCache) do
            TryAdd(name)
        end
    end

    table.sort(results)

    -- Cap results.
    if #results > MAX_SUGGESTIONS then
        local capped = {}
        for i = 1, MAX_SUGGESTIONS do
            capped[i] = results[i]
        end
        return capped
    end

    return results
end

-------------------------------------------------------------------------------
-- Autocomplete Dropdown UI
-- A lightweight frame anchored below the recipient EditBox.
-------------------------------------------------------------------------------

-- Creates the dropdown frame. Called once on first use.
local function CreateDropdown()
    if dropdownFrame then return end

    dropdownFrame = CreateFrame("Frame", "MailroomAddressBookDropdown",
        SendMailFrame, "BackdropTemplate")
    dropdownFrame:SetFrameStrata("DIALOG")
    dropdownFrame:SetSize(200, 10)
    dropdownFrame:Hide()

    dropdownFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 12,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dropdownFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    dropdownFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    for i = 1, MAX_SUGGESTIONS do
        local row = CreateFrame("Button", nil, dropdownFrame)
        row:SetSize(196, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", 2,
            -2 - (i - 1) * ROW_HEIGHT)

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.3, 0.5, 0.8, 0.3)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetColorTexture(0.3, 0.5, 0.8, 0.5)
        selected:Hide()
        row.selectedTex = selected

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", 4, 0)
        text:SetPoint("RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        local rowIndex = i
        row:SetScript("OnClick", function()
            local name = currentSuggestions[rowIndex]
            if name then
                SendMailNameEditBox:SetText(name)
                SendMailNameEditBox:SetCursorPosition(#name)
                MR.AddressBook:HideDropdown()
            end
        end)

        suggestionRows[i] = row
    end
end

-- Shows the dropdown with the given suggestions.
-- @param suggestions (table) Array of contact name strings.
local function ShowDropdown(suggestions)
    if not dropdownFrame then CreateDropdown() end

    currentSuggestions = suggestions
    selectedIndex = 0

    if #suggestions == 0 then
        dropdownFrame:Hide()
        return
    end

    dropdownFrame:ClearAllPoints()
    dropdownFrame:SetPoint("TOPLEFT", SendMailNameEditBox, "BOTTOMLEFT", 0, -2)

    local visibleCount = math.min(#suggestions, MAX_SUGGESTIONS)
    dropdownFrame:SetSize(200, visibleCount * ROW_HEIGHT + 4)

    for i = 1, MAX_SUGGESTIONS do
        local row = suggestionRows[i]
        if i <= visibleCount then
            row.text:SetText(suggestions[i])
            row.selectedTex:Hide()
            row:Show()
        else
            row:Hide()
        end
    end

    dropdownFrame:Show()
end

-------------------------------------------------------------------------------
-- Keyboard Navigation
-------------------------------------------------------------------------------

-- Updates the visual selection highlight.
local function UpdateSelection()
    for i = 1, MAX_SUGGESTIONS do
        local row = suggestionRows[i]
        if row and row:IsShown() then
            if i == selectedIndex then
                row.selectedTex:Show()
            else
                row.selectedTex:Hide()
            end
        end
    end
end

-- Moves the selection up or down.
-- @param delta (number) +1 for down, -1 for up.
local function MoveSelection(delta)
    local count = math.min(#currentSuggestions, MAX_SUGGESTIONS)
    if count == 0 then return end

    selectedIndex = selectedIndex + delta
    if selectedIndex < 1 then selectedIndex = count end
    if selectedIndex > count then selectedIndex = 1 end
    UpdateSelection()
end

-- Accepts the current selection.
-- @return (boolean) True if a selection was accepted.
local function AcceptSelection()
    if selectedIndex > 0 and selectedIndex <= #currentSuggestions then
        local name = currentSuggestions[selectedIndex]
        SendMailNameEditBox:SetText(name)
        SendMailNameEditBox:SetCursorPosition(#name)
        MR.AddressBook:HideDropdown()
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Hides the autocomplete dropdown.
function MR.AddressBook:HideDropdown()
    if dropdownFrame then dropdownFrame:Hide() end
    currentSuggestions = {}
    selectedIndex = 0
end

-------------------------------------------------------------------------------
-- Hook Installation
-------------------------------------------------------------------------------

-- Installs autocomplete hooks on the recipient EditBox.
-- Called once on first MAIL_SHOW.
local function InstallAutocomplete()
    if autocompleteInstalled then return end
    autocompleteInstalled = true

    local field = SendMailNameEditBox
    if not field then return end

    CreateDropdown()

    -- Live search on text change.
    field:HookScript("OnTextChanged", function(self, userInput)
        if not MR.Addon.db.profile.addressBookEnabled then return end
        if not userInput then
            MR.AddressBook:HideDropdown()
            return
        end

        local text = self:GetText()
        if text and #text >= 1 then
            local matches = MR.AddressBook:Search(text)
            if #matches == 1 and matches[1] == text then
                MR.AddressBook:HideDropdown()
            else
                ShowDropdown(matches)
            end
        else
            MR.AddressBook:HideDropdown()
        end
    end)

    -- Keyboard navigation.
    field:HookScript("OnKeyDown", function(self, key)
        if not dropdownFrame or not dropdownFrame:IsShown() then return end

        if key == "DOWN" then
            MoveSelection(1)
        elseif key == "UP" then
            MoveSelection(-1)
        elseif key == "TAB" or key == "ENTER" then
            AcceptSelection()
        elseif key == "ESCAPE" then
            MR.AddressBook:HideDropdown()
        end
    end)

    -- Hide on focus loss (with delay for click events).
    field:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.1, function()
            MR.AddressBook:HideDropdown()
        end)
    end)
end

-- Installs a hook on the send button to record the recipient.
local function InstallSendHook()
    if sendHookInstalled then return end
    sendHookInstalled = true

    local sendButton = SendMailMailButton
    if not sendButton then return end

    sendButton:HookScript("OnClick", function()
        if not MR.Addon.db.profile.addressBookEnabled then return end

        local recipient = SendMailNameEditBox:GetText()
        if recipient and recipient ~= "" then
            MR.AddressBook:AddContact(recipient, "auto")
            MR.AddressBook:RecordSend(recipient)
        end
        MR.AddressBook:HideDropdown()
    end)
end

-------------------------------------------------------------------------------
-- Event Handlers (called from Mailroom.lua)
-------------------------------------------------------------------------------

-- Called when the mailbox opens. Refreshes contact sources and
-- installs UI hooks.
function MR.AddressBook:OnMailShow()
    if not MR.Addon.db.profile.addressBookEnabled then return end

    -- Refresh external sources.
    RefreshFriends()
    RefreshGuild()

    -- Auto-populate from inbox.
    self:PopulateFromInbox(MR.mailCache)

    -- Install hooks (once).
    InstallAutocomplete()
    InstallSendHook()

    -- Pre-fill with most recent recipient if enabled.
    if MR.Addon.db.profile.prefillRecent then
        local recent = MR.Addon.db.profile.recentRecipients
        if #recent > 0 and SendMailNameEditBox then
            SendMailNameEditBox:SetText(recent[1])
        end
    end
end

-- Called when the mailbox closes.
function MR.AddressBook:OnMailClosed()
    self:HideDropdown()
end
