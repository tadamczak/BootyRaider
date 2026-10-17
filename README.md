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

Saved raids show **Duration**, **Created At** and **Modified At**. Duration uses the recorded raid end and displays, for example, **1h 05min 09s**. **Save raid end time** records the end when saving; **Modify raid end time** enables changing an existing end in **DD.MM.YYYY HH:MM:SS** format. Without a recorded end, duration is **Unknown**. Editing or copying a raid preserves its original creation date and recorded end.

Saved lists use **Raid ID** and **Raid Type**. Use **Edit** beside a saved raid to change its ID and type. Raid Stats also lets you change the type. Finish an active raid before renaming its ID. Saving metadata offers the usual reload prompt. The **Issues** button minimizes or restores Soft Reserve warnings.

Loot Master message settings are grouped by topic. Each text field shows a complete example that updates while you edit, including your prefix and whisper preference.

In Raid Stats, **Select all** selects or clears the currently filtered raids. Search also matches players and partial item names. Names saved with the raid are searchable even without the client cache; older records containing only item IDs need cached names.

CSR retains history beyond 60 days. **Show archived CSR** includes expired reserves with zero points. **Group By** offers Default, Player and Item; expand rows to inspect source raids, dates, expiration and ACTIVE/ARCHIVED status. Click column headings to sort each table. Editing or copying an old raid does not renew its CSR expiration. History remains until manually deleted; records removed by older versions cannot be recovered.

Each CSR source has an eye icon to view its raid. **Archive** removes that source's points while retaining its history. With **Show archived CSR** checked, **Activate** restores a manually archived source before its original expiration. Expired sources cannot be activated. Overwriting the same raid preserves archive decisions; a new Raid ID has independent sources.

Receiving an item retains its previous reserve entries as **AWARDED** under **Show archived CSR**. These entries grant zero CSR and cannot be activated. A later unsuccessful reserve starts accumulating points again.

**CSR Test Lab** uses temporary data. Select an earlier test player to add more reserves or award the selected item, archive test sources, and advance time with **+1 Day** or **+7 Days**. View Raid is disabled for simulated sources. Exit Test returns to saved history.

Only current guild ranks **Officer Wukong** and **Mukla** can archive/activate CSR, edit saved raid details, or edit/remove Raid Stats. Reading history remains available to everyone. These controls wait for current guild information; a raid leader or assistant role alone grants no history editing rights.

**Settings → Addon UI → CSR → Display** offers **Show class icon** and **Use class colors**, both enabled by default. Expand controls appear before the class/item icon and name.

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
