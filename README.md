# Mailroom

A clean, modern mail addon for World of Warcraft. Fast mail collection with smart throttling, address book autocomplete, alt gold tracking, and expiry warnings.

## Features

- **Collect All / Open All** — bulk mail operations with throttled queue to prevent silent server-side failures
- **Address Book** — autocomplete dropdown on the send frame, auto-populated from inbox senders and alts
- **Alt Tracking** — cross-character gold and mailbox snapshots stored per faction/realm
- **Expiry Warnings** — alerts when mail is about to expire
- **COD Handling** — confirmation prompts for COD mail, with option to skip during bulk collection
- **Large Gold Guard** — confirmation dialog before sending 100g+
- **Auto-Collect** — optional automatic collection when opening the mailbox
- **Multi-Client** — works on Retail, MoP Classic, and Classic Era / Season of Discovery

## Installation

Copy the `Mailroom` folder into your WoW addons directory:

- **Retail:** `World of Warcraft/_retail_/Interface/AddOns/`
- **Classic:** `World of Warcraft/_classic_/Interface/AddOns/`
- **Classic Era:** `World of Warcraft/_classic_era_/Interface/AddOns/`

## Commands

| Command | Description |
|---------|-------------|
| `/mr` or `/mailroom` | Open settings |
| `/mr help` | List all commands |
| `/mr collect` | Collect all mail (mailbox must be open) |
| `/mr alts` | Show alt gold overview |
| `/mr address list` | List address book contacts |
| `/mr address add <name>` | Add a contact |
| `/mr address remove <name>` | Remove a contact |

## Settings

All settings are available in the Blizzard Interface Options panel under **Mailroom**, or via `/mr config`:

- **Throttle Delay** — time between mail operations (default 0.15s)
- **Skip COD Mail** — skip COD mail during bulk collection
- **Auto-Collect on Open** — start collecting when you open the mailbox
- **Delete Empty Mail** — auto-delete mail after collecting everything
- **Expiry Warning Days** — warn threshold for expiring mail

## License

MIT
