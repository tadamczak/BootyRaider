<p align="center"><img src="https://raw.githubusercontent.com/tadamczak/BootyLib/develop/Assets/readme-header.png" width="100%" alt="Sons of Mukla"></p>

# BootyRaider

BootyRaider provides raid sessions, loot tools, Raid Stats and CSR for WoW 1.12.

## Table of contents

- [Installation](#installation)
- [Basic usage](#basic-usage)
- [Existing data](#existing-data)

## Installation

Install **BootyLib** and **BootyRaider** in `Interface/AddOns`, then enable them in the character's addon list. Booty Suite is optional. Without Suite, BootyRaider has its own minimap menu and separate feature windows. With Suite, the same screens and settings appear in the shared interface.

## Basic usage

Use `/br` to open Raid, `/br stats` for Raid Stats, `/br csr` for CSR and `/br settings` for configuration. `/br roll` opens New Roll. `/br roll [item]` starts the default OS, MS and RC modes, plus Tmog for supported equipment; player names and explicit roll modes can follow the item. You must be the physical raid's Loot Master, leader or assistant; an addon raid session is optional.

Tmog is available for head, shoulders, chest/robes, shirts, wrists, gloves, belts, legs, boots and weapons. Other slots and non-equippable items do not offer it. If item data is not cached, refocus the item field after the client receives it.

Current player results include their roll type, for example **97 SR** or **27 Tmog**. In Loot Master message settings, **Send in whisper** can send invalid-roll and unavailable-recipient notices directly to the affected player. It is off by default; winner announcements keep their raid audience.

New sessions capture the physical raid independently of guild membership. Save Raid preserves roster, loot and selected statistics. Live tracking, group/list appearance, the default game Raid tab and Loot Master messages have independent settings.

Loot Rules belong to the current raid. Unsaved changes do not change saved CSR. Saving an existing Raid ID asks before replacing it; a different ID creates an independent copy. Each raid keeps its own save choices. CSR uses only raids saved with **Save CSR** and their saved eligibility rules. Loading a saved raid accepts that session immediately.

Save Raid offers a reload to write data to disk. This waits until other Booty products have no active raid or recording. A failed startup or Stop reports its reason and retains raid data.

An incomplete client roster cannot start a ready session or replace a complete roster. If New Raid fails, the dialog retains your input so you can try again when the roster is available.

Import SR validates the entire RaidRes Base64 export before replacing reservations. Participants without reserved items, including RaidRes empty-choice placeholders, are accepted and receive no SR. Damaged exports leave the previous SR, loot and history intact; a valid empty reservation list clears SR. Imports accept up to 16000 bytes of pasted text.

Raid class and rank filters use the space needed by their captions. Filter and search controls wrap on narrow windows and expand again when space is available, in both standalone mode and Booty Suite.

Standalone Settings has two main sections: **Profile** and **Raid**. Use **Profile → General** to add, save, load, delete or export named preferences in either standalone mode or Booty Suite. Reset keeps raid and loot history.

Loot Master, New Roll and further loot dialogs open above the window that launched them, including in standalone mode.

Soft Reserve warnings stay above raid members in List and Groups. Their INFO and FIX SR windows close when the warning is dismissed or the Raid view is hidden.

Raid Leader Tools and Loot Master Tools menus open above every part of these warning cards.

## Existing data

Previous data is imported by the optional **Booty Legacy Data Import** addon. Keep the old SavedVariables until migration has been confirmed in game.

Older raids did not store their own Loot Rules. They receive one independent copy of the existing rules on migration. Original choices that were never recorded cannot be recovered; load, review and save individual raids to correct their history.
