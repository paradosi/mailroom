# Mailroom — Claude Code Project Context

## Project Overview

**Mailroom** is a from-scratch WoW mail addon written in Lua. It is NOT a fork or derivative of Postal or any other existing mail addon. All code must be original.

Mailroom ships on all three clients: **Retail**, **MoP Classic**, and **Classic Era / SoD**.

---

## Feature Specifications

Every feature below is a first-class module. Each lives in its own file under `Modules/`. Every module must be independently toggleable via AceConfig. Disabling any module must never cause errors or affect other modules.

---

### Open All
A single button that sweeps the entire inbox using the throttle queue. Mailroom knows what kind of mail it's looking at and acts accordingly.

- Identifies mail by type before touching it: auction house results (won, outbid, expired, cancelled), Postmaster notices, and mail carrying items or gold
- Each mail type is a separate toggle in settings — players can tell Mailroom to skip AH spam but always grab attachments, for example
- Before collecting each item, checks remaining free bag slots against a configurable minimum (default: 2 free slots). If collecting would breach that threshold, the queue pauses and the player is notified
- Holding Shift while clicking Open All ignores all type filters and collects everything in the inbox unconditionally
- All operations go through the throttle queue — no raw loops, no silent server failures

---

### Bulk Select
Adds fine-grained multi-selection to the inbox list so players can act on groups of mail at once.

- Every inbox row gets a checkbox for individual selection
- Holding Shift while clicking a second checkbox selects all rows between the two clicks
- Holding Ctrl while clicking any row selects every piece of mail from that same sender
- Once a selection is made, action buttons appear to collect, return, or delete the entire group via the queue
- Selected rows are visually highlighted; a count of selected items shows in the action area

---

### Address Book
A unified recipient picker attached to the send frame, pulling contacts from every source Mailroom knows about.

- **Saved contacts** — a manual list the player curates, stored per faction/realm in AceDB
- **Send history** — every successfully sent mail adds the recipient to a recent list, configurable length
- **Realm alts** — characters on the same realm and faction, detected automatically from AltData as the player logs into each one
- **All alts** — full cross-realm alt roster with class colors applied to names
- **Friends list** — populated via `C_FriendList` on Retail or `GetFriendInfo` on Classic (compat shim in Compat.lua)
- **Guild roster** — all guild members pulled from the guild API on mailbox open
- Typing in the To: field filters all sources simultaneously and shows a live dropdown of matches
- An optional setting pre-fills the To: field with whoever the player mailed most recently
- All sources are merged and duplicate names suppressed before display

---

### Quick Actions
Modifier-key shortcuts that let players act on individual inbox mail without opening it first.

- **Shift + click** — immediately queues collection of all attachments and gold from that mail
- **Ctrl + click** — queues a return-to-sender for that mail
- **Alt + click** — pulls the mail's attached item(s) and opens the send frame with them pre-attached
- Modifier combinations are chosen to avoid collision with any Blizzard default inbox click behavior
- A hover tooltip on each mail row lists the available modifier shortcuts as a reminder

---

### Carbon Copy
Lets players copy the full contents of any inbox mail to their system clipboard.

- A button (or right-click menu entry) on each open mail triggers the copy
- Captured content: sender name, subject, body text, and if the mail is an auction invoice, the item name, stack size, and price paid
- Output is formatted as clean readable plain text with no WoW color codes or markup
- Uses `C_System.CopyToClipboard` where available (Retail); falls back to a selectable EditBox containing the text on Classic clients where the API does not exist

---

### Do Not Want
Gives each inbox row a small icon that tells the player exactly what will happen to that mail when it expires — before it happens.

- Icon shows one of two states: a return arrow (mail will go back to sender) or a trash icon (mail will be deleted by the server)
- State is determined from mail metadata — player-sent mail returns, system and AH mail deletes
- Clicking the icon performs the action immediately via the queue, without waiting for expiry
- Icon color reflects time remaining: green for more than 3 days, yellow for 1–3 days, red for under 24 hours
- Day thresholds are adjustable in settings

---

### Forward
Lets players re-send the contents of a received mail to a different player.

- A Forward button appears when viewing any inbox mail
- Clicking it opens the send frame with the subject pre-filled as "Fwd: [original subject]", the original body quoted after a divider line, and any uncollected attachments re-attached
- If attachments were already looted, the forwarded body notes that they were not included
- The To: field is left blank for the player to fill in

---

### Quick Attach
A row of trade goods category buttons on the send frame that make stuffing mail with bag items faster.

- Categories cover the most common tradeskill materials: Cloth, Leather, Herbs, Ore, Gems, Enchanting Materials, Fish, plus one user-defined custom category
- Left-clicking a category button opens a filtered item picker showing only matching items from the player's bags; clicking an item attaches it (respecting the per-mail attachment cap)
- Right-clicking a category button opens a small prompt to set a default recipient for that category, stored in the player's AceDB profile; future left-clicks on that button also auto-fill the To: field with that name
- Category matching uses item class and subclass from `GetItemInfo` — no hardcoded item IDs

---

### Rake
Tracks all gold collected from mail during a mailbox session and reports the total when the mailbox closes. Full implementation details in the Gold Collection Summary section.

---

### Trade Block
Automatically handles disruptive social interactions that tend to happen at inconvenient times — like while you're trying to empty 80 pieces of mail.

- Any incoming trade request while `MAIL_SHOW` is active is automatically declined
- Any guild charter signature request while `MAIL_SHOW` is active is suppressed
- A short chat message confirms each blocked interaction: `[Mailroom] Blocked trade request from PlayerName.`
- Trade blocking and charter blocking are separate toggles in settings
- Both blocks clear the moment `MAIL_CLOSED` fires — normal interaction resumes immediately

---

### Enhanced UI
Small targeted improvements to the default Blizzard mail frame that add up to a noticeably better experience.

- **Auto subject for gold** — if the player puts gold in the money field but leaves the subject empty, Mailroom fills it in with "Gold" (or a custom string they configure)
- **Full subject on hover** — inbox rows clip long subjects; hovering the row shows the complete subject text in a GameTooltip
- **Session summary header** — a line above the inbox list shows the total number of attachments and total gold waiting to be collected across all mail
- No changes to frame layout, sizing, or position — purely additive

---

### MailBag
An alternative inbox view that displays all mail attachments and gold as a grid of items, like a bag, instead of a list of messages.

- Every attachment across every inbox mail is shown as a single item slot in the grid
- Duplicate items are consolidated into one slot showing a total count
- A search box at the top of the grid filters visible slots by item name
- Each slot is tinted by expiry urgency using the same green/yellow/red thresholds as Do Not Want
- Left-clicking a slot collects that item (and any gold from its mail) via the throttle queue
- Shift-clicking a slot posts the item as a chat link
- Optional per-character settings: show item quality borders, show gold as its own slot type, automatically open MailBag whenever the mailbox opens
- Toggled via a button added to the main mail frame — the default list view remains accessible

---

### Per-Character Profiles
Each character the player logs into gets its own independent settings profile by default.

- Profile mode defaults to per-character so settings don't bleed between alts
- Players can create shared profiles and assign multiple characters to them via the standard AceDB profile interface
- Profile switching is accessible from the settings panel inside the mailbox
- All module states, thresholds, and preferences belong to the active profile

---

### Settings
A configuration panel accessible directly from the mailbox without leaving the game or opening a separate window.

- A small arrow button at the top-left of the Blizzard mail frame opens the Mailroom settings panel
- The panel is organized by module, each with its own section and a master on/off toggle
- All settings apply immediately on change — no UI reload required
- Typing `/mailroom` or `/mr` in chat opens the same panel from anywhere in the game

---

### Analytics
A session report panel that shows a full breakdown of everything that happened during a mailbox visit.

- Tracks and displays: total gold collected, number of AH sales, items received, items returned, attachments looted, and total time spent at the mailbox
- Data accumulates across the session and is presented in a clean summary frame when the mailbox closes or on demand via a button
- Historical sessions are stored in AceDB (last N sessions, configurable) so players can look back at previous visits
- Designed to be screenshot-worthy — traders and AH goblins should want to share it
- Separate from the Rake gold toast — Analytics is the full picture, Rake is the quick headline number

---

### Snooze
Lets players temporarily hide specific mail from Mailroom's view without deleting or returning it.

- A snooze button appears on each open mail
- Player picks a duration: 1 hour, 4 hours, 1 day, 3 days, or a custom value
- Mailroom stores the mail's ID and snooze expiry timestamp in AceDB and hides it from all Mailroom views (inbox list, MailBag grid, Bulk Select) until the snooze expires
- The mail still exists on the server and is visible in Blizzard's default frame — Mailroom simply filters it out of its own display
- A snoozed mail count badge shows on the mailbox so the player knows hidden mail exists
- Snoozed mail surfaces automatically when its timer expires or when the player clicks "Show Snoozed" in settings

---

### Templates
Save any outgoing mail as a reusable template for repeated sends.

- A "Save as Template" button on the send frame captures the current To:, subject, body, and gold amount
- Templates are named and stored in AceDB profile scope
- A template picker button on the send frame lets players browse and load saved templates
- Loading a template populates `SendMailNameEditBox`, `SendMailSubjectEditBox`, `SendMailBodyEditBox`, and the money field programmatically
- Templates are editable and deletable from the picker panel
- Useful for regular gold transfers to alts, recurring guild messages, standard trade offers

---

### Pending Income
Tracks the player's active AH listings locally and estimates incoming mail revenue.

- Hooks the AH posting event to record each listing: item, quantity, asking price, and timestamp — stored in AceDB
- A small display (minimap button tooltip or dedicated panel) shows total estimated incoming gold from active tracked listings
- **Important caveat baked into the display:** only listings posted while Mailroom was active are tracked. The display notes this clearly — "X tracked listings, ~Y gold pending"
- When AH result mail arrives and is collected, Mailroom matches it against the tracked listing and marks it resolved
- Listings that go unresolved past their auction duration are flagged as expired
- No AH API queries — purely local bookkeeping from hook data

---

### Expiry Ticker
A persistent at-a-glance reminder of upcoming mail expiry, visible even when not at the mailbox.

- On each mailbox visit, Mailroom caches every mail's expiry time from `GetInboxHeaderInfo` into AceDB
- A `C_Timer.NewTicker` running every 60 seconds checks cached expiry times against the current time
- The minimap button tooltip always shows the most urgent expiry: "2 mails expire in 4h 22m"
- If any mail will expire within the threshold (configurable, default 24 hours), the minimap button pulses or changes color to draw attention
- Works passively in the background — no mailbox visit required after the initial cache

---

### Sound Design
Every Mailroom action has a corresponding sound to make the experience feel polished and rewarding.

- Uses Blizzard's built-in sound kit IDs — no external sound files, keeps the addon lightweight
- Each action type has its own sound:
  - Individual item collect: a short coin or item pickup sound
  - Gold collect: a satisfying coin clink
  - Open All completion: a distinct chime signaling the sweep is done
  - Mail returned: a subtle whoosh
  - Trade blocked: a soft deny sound
- All sounds independently toggleable in settings — players who want silence can turn off any or all
- Sound IDs defined in a single constants table in `Core/Mailroom.lua` so they are easy to swap or update

---

### Gold Toast
When the mailbox closes and gold was collected during the session, display an animated toast notification instead of a plain chat line.

- A small frame slides in from the bottom-right of the screen (or configurable anchor) using WoW's native animation system (`CreateAnimationGroup`, alpha + position keyframes)
- Shows the Mailroom icon, a gold coin icon, and the formatted gold amount
- Stays visible for 3 seconds then fades out smoothly
- Falls back gracefully to the chat line summary if animations are disabled in settings or if the amount is zero
- Implementation uses only Blizzard's built-in animation API — no external libraries needed:

```lua
-- Toast animation skeleton
local toast = CreateFrame("Frame", "MailroomToast", UIParent)
local ag = toast:CreateAnimationGroup()
local fadeIn = ag:CreateAnimation("Alpha")
fadeIn:SetFromAlpha(0)
fadeIn:SetToAlpha(1)
fadeIn:SetDuration(0.3)
fadeIn:SetOrder(1)
-- slide and fade out follow in order 2 and 3
```

---

## Project Structure

```
Mailroom/
├── CLAUDE.md
├── Mailroom.toc                  -- Retail TOC
├── Mailroom_MoP.toc              -- MoP Classic TOC (interface 50401)
├── Mailroom_Vanilla.toc          -- Classic Era / SoD TOC (interface 11503)
├── embeds.xml
├── Core/
│   ├── Mailroom.lua              -- AceAddon entry point, namespace, init, slash commands
│   ├── Compat.lua                -- Client detection and API shims
│   ├── MailQueue.lua             -- Throttled open/collect queue
│   ├── AltData.lua               -- Cross-character gold and item tracking
│   └── Settings.lua              -- AceConfig options table, settings frame hook
├── Modules/
│   ├── OpenAll.lua               -- Smart open all with filtering and bag protection
│   ├── BulkSelect.lua            -- Checkbox, shift/ctrl-click multi-select
│   ├── AddressBook.lua           -- Contacts, alts, friends, guild, autocomplete
│   ├── QuickActions.lua          -- Modifier-key click shortcuts
│   ├── CarbonCopy.lua            -- Clipboard copy of mail contents
│   ├── DoNotWant.lua             -- Expiry action icons per mail row
│   ├── Forward.lua               -- Forward mail to another player
│   ├── QuickAttach.lua           -- Category-based item attachment buttons
│   ├── Rake.lua                  -- Session gold summary and animated toast
│   ├── TradeBlock.lua            -- Block trades and guild charters at mailbox
│   ├── EnhancedUI.lua            -- Auto subject, long tooltips, inbox summary
│   ├── MailBag.lua               -- Bag-style grid inbox view (default view)
│   ├── Analytics.lua             -- Session report panel and history
│   ├── Snooze.lua                -- Temporarily hide mail from Mailroom views
│   ├── Templates.lua             -- Save and load outgoing mail templates
│   ├── PendingIncome.lua         -- AH listing tracker and income estimator
│   ├── ExpiryTicker.lua          -- Persistent expiry countdown on minimap button
│   └── SoundDesign.lua           -- Sound constants and playback helpers
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
    ├── icon.tga                  -- 64x64 minimap button icon
    └── icon-large.tga            -- 256x256 full resolution icon
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

## Gold Collection Summary (Rake Feature)

Mailroom tracks all gold collected from mail during a mailbox session and displays a summary when the mailbox is closed.

### Behavior

- When the mailbox opens (`MAIL_SHOW`), start a session gold counter at zero
- Each time `TakeInboxMoney()` is called via the queue, add the collected amount to the session counter
- When the mailbox closes (`MAIL_CLOSED`), if any gold was collected display a summary message in the chat frame:

```
[Mailroom] Collected 14g 32s 17c from mail.
```

- If no gold was collected during the session, print nothing — no empty "Collected 0g" messages
- Reset the session counter to zero on `MAIL_SHOW` so each mailbox visit starts fresh

### Implementation Notes

```lua
-- In Core/Mailroom.lua or Core/Inbox.lua
local sessionGold = 0  -- resets each MAIL_SHOW

-- When queuing a TakeInboxMoney call, wrap it to capture the amount:
local function MakeTakeMoneyOp(index)
    return function()
        local _, _, _, money = GetInboxHeaderInfo(index)
        if money and money > 0 then
            sessionGold = sessionGold + money
        end
        MR.TakeInboxMoney(index)
    end
end

-- On MAIL_CLOSED:
if sessionGold > 0 then
    MR.Addon:Print(MR.FormatMoney(sessionGold) .. " collected from mail.")
end
sessionGold = 0
```

### FormatMoney Utility

Implement a `MR.FormatMoney(copper)` utility in `Core/Mailroom.lua` that formats a copper integer into a readable gold/silver/copper string. Use WoW's coin texture codes on Retail if available, plain text on Classic:

```lua
-- Returns formatted money string e.g. "14g 32s 17c"
-- On Retail, uses gold/silver/copper texture icons if available.
function MR.FormatMoney(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%dg %ds %dc", g, s, c)
end
```

---

## Reference

- WoW API: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
- FrameXML source: https://github.com/Gethe/wow-ui-source
- Ace3 docs: https://www.wowace.com/projects/ace3
- LibStub: https://www.wowace.com/projects/libstub
