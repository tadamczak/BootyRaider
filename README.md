<p align="center"><img src="https://raw.githubusercontent.com/tadamczak/MuklaOfficerSuite/master/Assets/readme-header.png" width="100%" alt="Sons of Mukla"></p>

# BootyRaider

BootyRaider provides raid sessions, loot tools, Raid Stats and CSR for WoW 1.12.

## Table of contents

- [Installation](#installation)
- [Basic usage](#basic-usage)
- [Existing data](#existing-data)

## Installation

Install **BootyLib** and **BootyRaider** in `Interface/AddOns`, then enable them in the character's addon list. Booty Suite is optional. Without Suite, BootyRaider has its own minimap menu and separate feature windows. With Suite, the same screens and settings appear in the shared interface.

## Basic usage

Use `/br` to open Raid, `/br stats` for Raid Stats, `/br csr` for CSR and `/br settings` for configuration. `/br roll` opens New Roll. `/br roll [item]` starts the default Tmog, OS, MS and RC modes; player names and explicit roll modes can follow the item. The established `/mos roll` command remains available when Booty Suite is absent.

New sessions capture the physical raid independently of guild membership. Save Raid preserves roster, loot and selected statistics. Live tracking, group/list appearance, the default game Raid tab and Loot Master messages have independent settings.

When BootyUI controls the game Raid tab, choose native or BootyRaider content in BootyUI. The corresponding Raider setting opens that selection. When BootyUI stops, Raider returns to its retained fallback setting; stopping Raider keeps its Raid-tab content inactive.

With current BootyUI installed, `/bui appearance` previews group colors, text sizes, background textures and header transparency. **Raider group view** and **Raider in Raid tab** retain independent settings. Apply saves the appearance in Raider; Cancel restores it. The same values remain available in Raider Settings, and changing them there ends an unfinished preview. Editing appearance preserves the selected Raid content, tracking and loot preferences.

Standalone Settings has two main sections: **Profile** and **Raid**. Use **Profile → General** to add, save, load, delete or export named preferences in either standalone mode or Booty Suite. Reset keeps raid and loot history.

Loot Master, New Roll and further loot dialogs open above the window that launched them, including in standalone mode.

Soft Reserve warnings stay above raid members in List and Groups. Their INFO and FIX SR windows close when the warning is dismissed or the Raid view is hidden.

## Existing data

Existing Mukla Officer Suite data is imported by the optional migration bridge. Keep the old SavedVariables until migration has been confirmed in game.
