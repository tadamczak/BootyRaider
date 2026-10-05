# Changelog

## 0.1.0-dev.2 — 2026-10-05

- Use corrected shared Settings accordion actions, including during a loaded raid.
- Document standalone Settings under Profile and Raid.

## 0.1.0-dev.1 — 2026-10-05

- Extract Raid, Raid Stats, CSR, loot tools and native Raid integration into BootyRaider with BootyLib as its only required addon.
- Share the same screens between standalone windows and Booty Suite; retain raid data, settings and roll commands.
- Initialize Master Loot UI when first used and start raid sessions independently of guild roster scans.
- Preserve independent rarity and raid preset choices when resetting selected settings; keep shared chat preferences in BootyLib.
- Apply full settings profiles with one visible Raid refresh and discard transient side effects when a write is rolled back.
