-- Mailroom / Compat.lua
-- Client detection and API shims.
-- Centralizes all client-version branching so that feature code never
-- needs to check which WoW client is running. Every API that differs
-- between Retail, MoP Classic, and Classic Era is wrapped here as a
-- shim on the MR namespace.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Client Detection
-- GetBuildInfo()'s fourth return is the interface version number.
-- Retail: 110000+ (11.x), MoP Classic: 50000-59999 (5.x), Era/SoD: < 20000.
-------------------------------------------------------------------------------

local version = select(4, GetBuildInfo())

MR.isRetail  = (version >= 100000)
MR.isMoP     = (version >= 50000 and version < 60000)
MR.isClassic = (version < 20000)

-------------------------------------------------------------------------------
-- Mail API Shims
-- The C_Mail namespace was introduced in Shadowlands (9.0) and contains
-- modern versions of the mail functions. Classic clients only have the
-- original global functions. We prefer C_Mail where available for forward
-- compatibility, falling back to globals for Classic/MoP.
-------------------------------------------------------------------------------

-- GetInboxNumItems returns the number of mail items currently loaded in
-- the inbox. C_Mail wraps this on Retail; Classic uses the global.
MR.GetInboxNumItems = (C_Mail and C_Mail.GetInboxNumItems) or GetInboxNumItems

-- TakeInboxItem removes an attachment from a mail at the given index.
-- The C_Mail version is functionally identical but routed through the
-- new namespace on Retail.
MR.TakeInboxItem = (C_Mail and C_Mail.TakeInboxItem) or TakeInboxItem

-- TakeInboxMoney collects the gold attached to a mail at the given index.
MR.TakeInboxMoney = (C_Mail and C_Mail.TakeInboxMoney) or TakeInboxMoney

-- SendMail sends a new mail to a recipient. The C_Mail version wraps
-- the original global on Retail.
MR.SendMail = (C_Mail and C_Mail.SendMail) or SendMail

-- GetInboxHeaderInfo returns subject, icon, sender, and other metadata
-- for a mail at the given index. Used by inbox scanning.
MR.GetInboxHeaderInfo = (C_Mail and C_Mail.GetInboxHeaderInfo) or GetInboxHeaderInfo

-- GetInboxItem returns info about an attachment in a specific mail slot.
MR.GetInboxItem = (C_Mail and C_Mail.GetInboxItem) or GetInboxItem

-- GetInboxText returns the body text of a mail and marks it as read
-- on the server. Used by OpenAll to mark mail without collecting.
MR.GetInboxText = (C_Mail and C_Mail.GetInboxText) or GetInboxText

-- DeleteInboxItem deletes a mail from the inbox (only works on read,
-- empty mail with no attachments or gold remaining).
MR.DeleteInboxItem = (C_Mail and C_Mail.DeleteInboxItem) or DeleteInboxItem

-- ReturnInboxItem returns a mail to its sender. Only works on
-- player-sent mail, not system or AH mail.
MR.ReturnInboxItem = (C_Mail and C_Mail.ReturnInboxItem) or ReturnInboxItem

-- AutoLootMailItem is available on Retail to loot all attachments from
-- a single mail at once. Classic clients lack this, so we store nil
-- and handle multi-attachment looting manually in OpenAll.
MR.AutoLootMailItem = (C_Mail and C_Mail.AutoLootMailItem) or nil

-------------------------------------------------------------------------------
-- Friends List Shims
-- Retail uses C_FriendList namespace; Classic uses legacy globals.
-- AddressBook uses these to pull the player's friends list.
-------------------------------------------------------------------------------

-- GetNumFriends returns the count of friends on the regular friends list.
-- Retail moved this to C_FriendList; Classic keeps the global.
MR.GetNumFriends = (C_FriendList and C_FriendList.GetNumFriends) or GetNumFriends

-- GetFriendInfo returns info about a friend at the given index.
-- Retail returns a table via C_FriendList.GetFriendInfoByIndex; Classic
-- returns multiple values from GetFriendInfo. We normalize in AddressBook.
MR.GetFriendInfoByIndex = (C_FriendList and C_FriendList.GetFriendInfoByIndex) or nil
MR.GetFriendInfo = GetFriendInfo  -- Classic fallback, always available

-------------------------------------------------------------------------------
-- Guild Roster Shims
-- GuildRoster() triggers a server query on Classic. On Retail,
-- C_GuildInfo.GuildRoster() does the same. GetNumGuildMembers and
-- GetGuildRosterInfo are globals on all clients.
-------------------------------------------------------------------------------

MR.GuildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster

-------------------------------------------------------------------------------
-- Clipboard Shim
-- C_System.CopyToClipboard exists on Retail but not on Classic.
-- CarbonCopy falls back to a selectable EditBox on Classic.
-------------------------------------------------------------------------------

MR.CopyToClipboard = (C_System and C_System.CopyToClipboard) or nil

-------------------------------------------------------------------------------
-- Money Formatting
-- GetCoinTextureString uses inline textures (gold/silver/copper icons).
-- GetMoneyString is a plain-text alternative. We prefer textures when
-- available, with a plain-text fallback.
-------------------------------------------------------------------------------

MR.FormatMoney = GetCoinTextureString or GetMoneyString

-------------------------------------------------------------------------------
-- Bag Space
-- C_Container is the modern bag API on Retail. Classic uses the legacy
-- GetContainerNumFreeSlots global. OpenAll uses this to check free
-- bag space before collecting items.
-------------------------------------------------------------------------------

MR.GetContainerNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
MR.NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4  -- always 4 on Classic, 5 on Retail (includes reagent bag)
