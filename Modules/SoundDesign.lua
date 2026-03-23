-- Mailroom / Modules / SoundDesign.lua
-- Sound constants and playback helpers.
-- Defines all sound kit IDs used by Mailroom in a central location and
-- provides a unified playback API. Each sound has its own toggle in
-- the profile database, plus a master toggle that disables all sounds.
-- This is a utility module with no event handlers — other modules call
-- MR.SoundDesign:PlayIfEnabled(key) when they want to play a sound.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- SoundDesign Module
-------------------------------------------------------------------------------

MR.SoundDesign = {}

-------------------------------------------------------------------------------
-- Sound Kit IDs
-- These are Blizzard sound kit IDs passed to PlaySound(). Each constant
-- maps to a specific in-game sound effect. The IDs are sourced from
-- the WoW client's internal SoundKit table.
--
-- ITEM_COLLECT:      Pickup sound played when a bag item is looted.
-- GOLD_COLLECT:      Coin clink played when gold is received.
-- OPEN_ALL_COMPLETE: Level-up style chime for queue completion.
-- MAIL_RETURNED:     Whoosh sound for mail being sent back.
-- TRADE_BLOCKED:     Error/deny sound for blocked actions.
-- TOAST_SHOW:        Notification chime for the gold summary toast.
-------------------------------------------------------------------------------

MR.Sounds = {
    ITEM_COLLECT      = 120571, -- LOOTWINDOW_COIN_SOUND (item pickup)
    GOLD_COLLECT      = 120572, -- money coin clink
    OPEN_ALL_COMPLETE = 888,    -- LEVELUPSOUND (completion chime)
    MAIL_RETURNED     = 863,    -- whoosh / send effect
    TRADE_BLOCKED     = 847,    -- igPlayerInviteDecline (error deny)
    TOAST_SHOW        = 888,    -- LEVELUPSOUND (toast notification)
}

-------------------------------------------------------------------------------
-- Sound Key to Profile Key Mapping
-- Each sound kit constant has a corresponding boolean toggle in the
-- profile database. This table maps from the sound key name (as passed
-- to PlayIfEnabled) to the profile field name. This indirection lets
-- us keep the public API clean (using semantic names like "ITEM_COLLECT")
-- while the profile stores more descriptive field names.
-------------------------------------------------------------------------------

local SOUND_TOGGLES = {
    ITEM_COLLECT      = "soundItemCollect",
    GOLD_COLLECT      = "soundGoldCollect",
    OPEN_ALL_COMPLETE = "soundOpenAllComplete",
    MAIL_RETURNED     = "soundMailReturned",
    TRADE_BLOCKED     = "soundTradeBlocked",
    TOAST_SHOW        = "soundToastShow",
}

-------------------------------------------------------------------------------
-- Playback API
-------------------------------------------------------------------------------

-- Plays a sound by its key name, bypassing all enable checks.
-- Use this only for sounds that should always play regardless of settings
-- (there are currently none, but the API exists for completeness).
-- @param soundKey (string) One of the keys in MR.Sounds (e.g. "ITEM_COLLECT").
function MR.SoundDesign:Play(soundKey)
    local soundID = MR.Sounds[soundKey]
    if not soundID then return end
    PlaySound(soundID)
end

-- Plays a sound by its key name if both the master toggle and the
-- individual sound toggle are enabled. This is the main entry point
-- that other modules should call.
--
-- The two-level toggle system lets the player disable all sounds at
-- once via the master toggle, or selectively disable individual sounds
-- they find annoying while keeping others active.
--
-- @param soundKey (string) One of the keys in MR.Sounds (e.g. "GOLD_COLLECT").
function MR.SoundDesign:PlayIfEnabled(soundKey)
    -- Check master toggle first. If sounds are globally disabled,
    -- skip the per-sound check entirely.
    if not MR.Addon.db.profile.soundEnabled then return end

    -- Check the individual sound toggle.
    local profileKey = SOUND_TOGGLES[soundKey]
    if profileKey and not MR.Addon.db.profile[profileKey] then
        return
    end

    local soundID = MR.Sounds[soundKey]
    if not soundID then return end

    PlaySound(soundID)
end

-- Returns whether a specific sound is currently enabled (both master
-- and individual toggles must be on).
-- @param soundKey (string) One of the keys in MR.Sounds.
-- @return (boolean) True if the sound would play when requested.
function MR.SoundDesign:IsEnabled(soundKey)
    if not MR.Addon.db.profile.soundEnabled then return false end

    local profileKey = SOUND_TOGGLES[soundKey]
    if profileKey then
        return MR.Addon.db.profile[profileKey] ~= false
    end

    return true
end

-- Returns the sound kit ID for a given key name.
-- @param soundKey (string) One of the keys in MR.Sounds.
-- @return (number or nil) The sound kit ID, or nil if the key is invalid.
function MR.SoundDesign:GetSoundID(soundKey)
    return MR.Sounds[soundKey]
end
