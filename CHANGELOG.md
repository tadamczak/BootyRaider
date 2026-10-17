# Changelog

## 0.1.0-dev.16 — 2026-10-17

- Close stale session prompts after saving or ending a raid and guard obsolete Continue actions.
- Show saved-raid duration, creation and modification dates; clarify overwrite confirmation.
- Keep Reycoin rows inside their window and toggle warnings with the Issues button.
- Add filtered Select all, left-aligned headings and item-name search to Raid Stats.
- Retain CSR history, show optional archives and group by player or item with sortable source tables.

## 0.1.0-dev.15 — 2026-10-17

- Keep Loot Rules and save choices independent for each raid.
- Confirm replacement of an existing Raid ID; a different ID creates a separate copy.
- Calculate CSR only from opted-in saved raids and their saved eligibility rules.
- Accept an explicitly loaded session without immediately requesting continuation.

## 0.1.0-dev.14 — 2026-10-17

- Offer Transmog rolls only for the supported armor slots and weapons.
- Accept RaidRes participants without items, including empty-reserve export placeholders.
- Start item rolls without requiring an addon raid session.
- Preserve known ranks during guild refreshes and refresh loot rights when the current guild data becomes ready.
- Show the roll category beside each current result and offer private whispers for individual roll warnings.

## 0.1.0-dev.13 — 2026-10-09

- Use Booty preferences and commands; preserve previous raid settings and saved profiles.

## 0.1.0-dev.12 — 2026-10-08

- Skip attendance lookups for ignored loot events and reuse CSR data during resize, scrolling and row expansion.
- Remove the unused legacy quick-actions getter and global alias; actions remain owned by each Raid screen.

## 0.1.0-dev.11 — 2026-10-07

- Release owned events and loot hooks after failed startup; preserve raid data and report refused cleanup.
- Guard Save Raid reload confirmation against active work in every Booty product.

## 0.1.0-dev.10 — 2026-10-07

- Reject damaged Soft Reserve exports before replacing existing reservations.
- Complete new raid sessions only after a full physical roster capture; retain retry/cancel and previous data after failure.
- Preserve auto loot preferences when settings restoration or cancelled raid creation unwinds changes.

## 0.1.0-dev.9 — 2026-10-07

- Keep Loot Master and Raid Leader dropdown choices above all warning cards.

## 0.1.0-dev.8 — 2026-10-07

- Give Raid class and rank filters enough room for their captions in standalone and Booty Suite.
- Wrap filter and search controls together on narrow windows and restore their layout on growth.

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
