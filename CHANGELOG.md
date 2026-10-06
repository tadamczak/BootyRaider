# Changelog

## 0.1.0-dev.6 — 2026-10-06

- Support BootyUI previews of existing main and game Raid-tab group appearance settings without saving until Apply.
- Refresh visible group appearance from the current roster without a new roster scan.
- Retain independent appearance settings, content choices and gameplay preferences during edits.

## 0.1.0-dev.5 — 2026-10-06

- Let BootyUI select native or BootyRaider content for the game Raid tab while retaining Raider's independent fallback setting.
- Keep hidden Raid content lazy and report failed attachment or conflicting addon wrappers without taking over later changes.
- Keep Raider active when its Raid-tab content cannot be detached safely during Stop.

## 0.1.0-dev.4 — 2026-10-05

- Keep Soft Reserve warning cards and their controls above raid rows and group tiles, including when docked or minimized.
- Close warning details, Fix SR confirmations and the assignment editor when the warning or Raid view is hidden.

## 0.1.0-dev.3 — 2026-10-05

- Keep Loot Master, New Roll, loot rules and nested dialogs above their opening window.
- Preserve owned confirmations for loot awards, saved-raid deletion and session reminders.

## 0.1.0-dev.2 — 2026-10-05

- Use corrected shared Settings accordion actions, including during a loaded raid.
- Document standalone Settings under Profile and Raid.

## 0.1.0-dev.1 — 2026-10-05

- Extract Raid, Raid Stats, CSR, loot tools and native Raid integration into BootyRaider with BootyLib as its only required addon.
- Share the same screens between standalone windows and Booty Suite; retain raid data, settings and roll commands.
- Initialize Master Loot UI when first used and start raid sessions independently of guild roster scans.
- Preserve independent rarity and raid preset choices when resetting selected settings; keep shared chat preferences in BootyLib.
- Apply full settings profiles with one visible Raid refresh and discard transient side effects when a write is rolled back.
