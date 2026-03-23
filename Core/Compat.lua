-- Mailroom / Compat.lua
-- Client detection and API shims.
-- Centralizes all client-version branching so that feature code never
-- needs to check which WoW client is running. Every mail API that differs
-- between Retail, MoP Classic, and Classic Era is wrapped here as a shim
-- on the MR namespace.

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
-- for a mail at the given index. Used by Inbox scanning.
MR.GetInboxHeaderInfo = (C_Mail and C_Mail.GetInboxHeaderInfo) or GetInboxHeaderInfo

-- GetInboxItem returns info about an attachment in a specific mail slot.
MR.GetInboxItem = (C_Mail and C_Mail.GetInboxItem) or GetInboxItem

-- DeleteInboxItem deletes a mail from the inbox (only works on read,
-- empty mail with no attachments or gold remaining).
MR.DeleteInboxItem = (C_Mail and C_Mail.DeleteInboxItem) or DeleteInboxItem

-- AutoLootMailItem is available on Retail to loot all attachments from
-- a single mail at once. Classic clients lack this, so we provide a
-- no-op fallback and handle multi-attachment looting manually in MailQueue.
MR.AutoLootMailItem = (C_Mail and C_Mail.AutoLootMailItem) or nil

-------------------------------------------------------------------------------
-- Money Formatting
-- GetMoneyString exists on all clients. GetCoinTextureString is an
-- alternative that uses inline textures (gold/silver/copper icons).
-- We prefer GetCoinTextureString when available, with a plain-text fallback.
-------------------------------------------------------------------------------

MR.FormatMoney = GetCoinTextureString or GetMoneyString
