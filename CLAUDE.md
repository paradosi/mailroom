# Mailroom — Claude Code Project Context

## Project Overview

**Mailroom** is a from-scratch WoW mail addon written in Lua. It is NOT a fork or derivative of Postal or any other existing mail addon. All code must be original.

The goal is a clean, modern, efficient mail addon that:
- Opens and collects mail with smart throttling
- Manages inbox with filtering and expiry warnings
- Enhances the send frame with an address book and autocomplete
- Tracks gold and items across alts (account-wide AceDB)
- Ships on all three clients: **Retail**, **MoP Classic**, and **Classic Era / SoD**

---

## Project Structure

```
Mailroom/
├── CLAUDE.md
├── Mailroom.toc              -- Retail TOC
├── Mailroom_MoP.toc          -- MoP Classic TOC (interface 50401)
├── Mailroom_Vanilla.toc      -- Classic Era / SoD TOC (interface 11503)
├── embeds.xml
├── Core/
│   ├── Mailroom.lua          -- AceAddon entry point, namespace, init
│   ├── Compat.lua            -- Client detection and API shims
│   ├── MailQueue.lua         -- Throttled open/collect queue
│   ├── Inbox.lua             -- Inbox scanning and caching
│   ├── Send.lua              -- Send frame enhancements
│   └── AltData.lua           -- Cross-character data tracking
├── UI/
│   ├── MailFrame.lua         -- Hooks into Blizzard mail frame
│   ├── AddressBook.lua       -- Autocomplete and address book UI
│   └── Alerts.lua            -- Expiry warnings, COD prompts
├── Libs/
│   ├── LibStub/
│   ├── AceAddon-3.0/
│   ├── AceDB-3.0/
│   ├── AceConfig-3.0/
│   ├── AceConsole-3.0/
│   ├── AceEvent-3.0/
│   ├── AceGUI-3.0/
│   └── AceTimer-3.0/
└── Media/
    └── (textures, sounds if needed)
```

---

## Namespace Convention

Every file must use the standard Ace3 two-value namespace pattern. Never use globals directly.

```lua
local AddonName, MR = ...
-- MR is the shared namespace table passed between files
-- AddonName is the string "Mailroom"
```

The core addon object lives at `MR.Addon` (the AceAddon object). Sub-modules are registered as mixins or stored on the `MR` table, never as independent globals.

**Never declare bare globals.** Always use `MR.Something` or `local`.

---

## Client Compatibility (Critical)

Mailroom targets three clients. Always use `Compat.lua` shims — never inline client checks in feature code.

### Client Detection (defined in Compat.lua)

```lua
local version = select(4, GetBuildInfo())
MR.isRetail  = (version >= 100000)
MR.isMoP     = (version >= 50000 and version < 60000)
MR.isClassic = (version < 20000)  -- Era / SoD
```

### Mail API by Client

| Operation         | Retail / MoP         | Classic Era         |
|-------------------|----------------------|---------------------|
| Get inbox count   | `C_Mail.GetInboxNumItems()` OR `GetInboxNumItems()` | `GetInboxNumItems()` |
| Take item         | `TakeInboxItem()`    | `TakeInboxItem()`   |
| Take money        | `TakeInboxMoney()`   | `TakeInboxMoney()`  |
| Send mail         | `C_Mail.SendMail()`  | `SendMail()`        |
| Open all event    | `MAIL_INBOX_UPDATE`  | `MAIL_INBOX_UPDATE` |

Always define shims in `Compat.lua`:

```lua
MR.TakeInboxItem = C_Mail and C_Mail.TakeInboxItem or TakeInboxItem
MR.SendMail      = C_Mail and C_Mail.SendMail      or SendMail
```

Feature code always calls `MR.TakeInboxItem(...)`, never the raw API.

---

## Throttling (Non-Negotiable)

The server silently drops mail operations that fire too fast. This is the most important implementation detail in the entire addon.

**The correct pattern — always use this:**

```lua
local THROTTLE_DELAY = 0.15  -- seconds between operations (tunable)

local queue = {}
local queueRunning = false

local function ProcessQueue()
    if #queue == 0 then
        queueRunning = false
        return
    end
    local op = table.remove(queue, 1)
    op()
    C_Timer.After(THROTTLE_DELAY, ProcessQueue)
end

function MR.Queue.Add(op)
    table.insert(queue, op)
    if not queueRunning then
        queueRunning = true
        ProcessQueue()
    end
end
```

**Never do this:**
```lua
-- BAD: fires all at once, silent server-side failures
for i = 1, count do
    TakeInboxItem(i)
end
```

Use `C_Timer.After` everywhere. Never use `OnUpdate` frame polling for timing.

---

## Ace3 Conventions

### AceAddon Entry Point

```lua
local MR_Addon = LibStub("AceAddon-3.0"):NewAddon("Mailroom",
    "AceConsole-3.0",
    "AceEvent-3.0"
)
MR.Addon = MR_Addon
```

### AceEvent — Always Use Mixin Style

```lua
-- Good
MR.Addon:RegisterEvent("MAIL_SHOW", function() MR.Inbox:OnMailShow() end)

-- Bad
local f = CreateFrame("Frame")
f:RegisterEvent("MAIL_SHOW")
f:SetScript("OnEvent", ...)
```

### AceDB Schema

```lua
local defaults = {
    profile = {
        throttleDelay = 0.15,
        skipCOD = false,
        autoCollect = false,
        expiryWarningDays = 3,
    },
    factionrealm = {
        -- Alt tracking data keyed by "Name-Realm"
        altData = {},
    },
}
MR.Addon.db = LibStub("AceDB-3.0"):New("MailroomDB", defaults, true)
```

- `profile` — per-character UI preferences
- `factionrealm` — shared across chars on same faction/realm (alt tracking)
- Never use `global` scope in AceDB for this addon

### AceConfig Options

All user-facing settings go through AceConfig. No ad-hoc slash command parsing. Register options in `Core/Mailroom.lua` during `OnInitialize`.

---

## What Not To Do

- **No global namespace pollution.** No `Mailroom_Something` globals. Everything in `MR.*` or local.
- **No `OnUpdate` polling** for any timing logic. Use `C_Timer.After` or `C_Timer.NewTicker`.
- **No hardcoded client checks in feature files.** Use `Compat.lua` shims only.
- **No bare `print()`** for user messages. Use `MR.Addon:Print()` (AceConsole).
- **No inline options tables** scattered across files. All settings defined in one AceConfig block.
- **No copying or referencing Postal source code.** All logic must be original.
- **No `SLASH_POSTAL` or any Postal-referencing identifiers** anywhere in the codebase.
- **No AI attribution anywhere.** No "generated by", "written by Claude", "AI-assisted", or any similar comments, headers, or notes in any file. Code is authored by paradosi (paradosi@dreamscythe), full stop.

---

## TOC Files

Each client needs its own TOC. The Interface version number must be correct.

**Mailroom.toc (Retail):**
```
## Interface: 110100
## Title: Mailroom
## Notes: Fast, modern mail management.
## Author: paradosi
## Version: 0.1.0
## X-License: MIT
## SavedVariables: MailroomDB

embeds.xml
Core\Compat.lua
Core\Mailroom.lua
Core\MailQueue.lua
Core\Inbox.lua
Core\Send.lua
Core\AltData.lua
UI\MailFrame.lua
UI\AddressBook.lua
UI\Alerts.lua
```

MoP and Classic TOCs follow the same pattern with correct Interface versions (`50401`, `11503`).

---

## Testing Approach

- Test mail open/collect on a character with 10+ mails to validate throttle queue
- Test COD mail handling explicitly (skip and accept paths)
- Test alt data population by logging in on two characters
- Test all three clients before any release tag
- Use **BugGrabber + BugSack** in-game for runtime Lua errors
- Run **Luacheck** on all `.lua` files before committing

---

## Code Style

- 4-space indentation
- `local` everything that doesn't need to be on `MR`
- One blank line between functions
- File header comment in every file:

```lua
-- Mailroom / MailQueue.lua
-- Throttled queue for mail open and collect operations.
-- Handles all TakeInboxItem and TakeInboxMoney calls with server-safe
-- delays to prevent silent operation failures.
```

---

## Documentation Standards (Required)

All code must be thoroughly documented. This is not optional. Future maintainers (and future Claude Code sessions) must be able to understand every file without additional context.

### Every Function Gets a Header Block

```lua
-- Opens the next item in the mail queue.
-- Pops the first operation from the queue table, executes it,
-- then schedules itself again via C_Timer.After if more items remain.
-- Sets queueRunning = false and exits cleanly when the queue is empty.
local function ProcessQueue()
    ...
end
```

### Parameters and Return Values

Document all non-obvious parameters and return values:

```lua
-- Adds a mail operation to the throttle queue.
-- @param op (function) The operation to execute. Should be a zero-arg closure
--            capturing any needed index or mail ID values at queue time,
--            not at execution time (indices shift as mail is taken).
-- @param priority (boolean) If true, inserts at front of queue instead of back.
function MR.Queue.Add(op, priority)
    ...
end
```

### Section Separators in Longer Files

Use clear section breaks in files with multiple logical areas:

```lua
-------------------------------------------------------------------------------
-- Queue State
-------------------------------------------------------------------------------

local queue        = {}
local queueRunning = false

-------------------------------------------------------------------------------
-- Queue Operations
-------------------------------------------------------------------------------

function MR.Queue.Add(op) ... end
function MR.Queue.Clear() ... end

-------------------------------------------------------------------------------
-- Internal Processing
-------------------------------------------------------------------------------

local function ProcessQueue() ... end
```

### Explain the "Why", Not Just the "What"

Don't just describe what code does — explain *why* it does it that way:

```lua
-- We capture `index` at queue-add time rather than passing it through
-- because TakeInboxItem indices are 1-based and shift downward as items
-- are removed. By the time a queued op executes, the original index may
-- point to a different mail item. Using a closure captures the correct
-- reference at the moment the user triggered the action.
local function MakeTakeOp(index)
    return function() MR.TakeInboxItem(index) end
end
```

### Compat Shims Must Be Explained

Every shim in `Compat.lua` needs a comment explaining the API difference:

```lua
-- TakeInboxItem exists on all clients but the C_Mail namespace was
-- introduced in Shadowlands (9.0). We prefer C_Mail where available
-- for forward compatibility, but fall back to the global for Classic/MoP.
MR.TakeInboxItem = (C_Mail and C_Mail.TakeInboxItem) or TakeInboxItem
```

### AceDB Fields

Every field in the defaults table must have an inline comment:

```lua
local defaults = {
    profile = {
        throttleDelay    = 0.15,  -- seconds between queue operations
        skipCOD          = false, -- if true, skips COD mail during open-all
        autoCollect      = false, -- collect money/items immediately on mail open
        expiryWarningDays = 3,    -- warn when mail expires within this many days
    },
    factionrealm = {
        altData = {},             -- keyed by "Name-Realm", stores gold + item snapshots
    },
}
```

### TOC Notes Field

Keep the `## Notes:` field in each TOC accurate and descriptive — it shows on CurseForge and in addon managers.

---

## Reference

- WoW API: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
- FrameXML source: https://github.com/Gethe/wow-ui-source
- Ace3 docs: https://www.wowace.com/projects/ace3
- LibStub: https://www.wowace.com/projects/libstub
