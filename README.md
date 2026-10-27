<p align="center"><img src="https://raw.githubusercontent.com/tadamczak/BootyLib/develop/Assets/readme-header.png" width="100%" alt="Sons of Mukla"></p>

# BootyRaider

BootyRaider provides raid sessions, loot tools, Raid Stats and CSR for WoW 1.12.

## Table of contents

- [Installation](#installation)
- [Basic usage](#basic-usage)
- [Existing data](#existing-data)
- [Officer synchronization](#officer-synchronization)

## Installation

Install **BootyLib** and **BootyRaider** in `Interface/AddOns`, then enable them in the character's addon list. Booty Suite is optional. Without Suite, BootyRaider has its own minimap menu and separate feature windows. With Suite, the same screens and settings appear in the shared interface.

## Basic usage

Use `/br` to open Raid, `/br stats` for Raid Stats, `/br csr` for CSR and `/br settings` for configuration. `/br roll` opens New Roll. `/br roll [item]` starts the default OS, MS and RC modes, plus Tmog for supported equipment; player names and explicit roll modes can follow the item. You must be the physical raid's Loot Master, leader or assistant; an addon raid session is optional.

Tmog is available for cloaks, head, shoulders, chest/robes, shirts, wrists, gloves, belts, legs, boots and weapons. Other slots and non-equippable items do not offer it. If item data is not cached, refocus the item field after the client receives it.

In **New Roll**, either paste an item link or type its full name. A typed name starts the roll even without an item cache entry. SR names match without case or extra-space sensitivity; use the item's full in-game name. Tmog still needs an item link with cached equipment information.

Name-only reservations also earn CSR under the saved raid's normal eligibility rules. Names differing only in case or extra spaces share one balance. Receiving the item resets earlier CSR; later unsuccessful reserves earn points again. Named sources support Archive and Activate. Saved item names connect manual reservations with identified items when the name identifies one item ID.

Current player results include their roll type, for example **97 SR** or **27 Tmog**. In Loot Master message settings, **Send in whisper** can send invalid-roll and unavailable-recipient notices directly to the affected player. It is off by default; winner announcements keep their raid audience.

New Raid also works outside a raid, creating an empty session you can prepare before grouping. In a raid it captures the physical roster independently of guild membership. Leaving or disbanding the group keeps the session, roster and Save controls available until you explicitly save/end or quit. **Convert to Raid**, beside Raid Info, lets a party leader convert the group. It is grey and inactive when conversion is unavailable, and hidden while already in a raid. Save Raid preserves roster, loot and selected statistics. Live tracking, group/list appearance, the default game Raid tab and Loot Master messages have independent settings.

In the Raid list, use **+** beside an empty SR or **Edit** beside its delete icon. Choose one item from the selected raid's catalogue; another choice replaces it. For an item missing from the catalogue, type its full name in the search field and click **Add name**, then **Save**. This also works for Other raids. Named SRs are saved and included in the review after another import. **Allow to SR without loot rights** admits that player's assigned SR, including restricted items, without changing their guild rank, Reycoin or CSR rights. An asterisk marks an exception in the SR column.

After importing SR again, select which manual changes to reapply in **Reapply custom SR changes**. Unchecked changes are discarded when you press **Apply selected**. Closing keeps the review pending; reopen it through **Import SR → Review custom changes**. Edits, removals, reassignment and exceptions are included. The independent catalogue covers Molten Core, Blackwing Lair, Onyxia's Lair, Zul'Gurub and Karazhan10 (Lower Karazhan Halls). Uncached names appear as item IDs. Other raid types have no catalogue.

Master Loot waits up to five seconds for delivery confirmation. If confirmation is missing, it releases the pending request and reports the item and recipient. Check whether the recipient received the item before trying again. Requests are never retried automatically; confirmed SR/Reycoin transfers remain available.

Logging in outside a raid does not show a raid-departure warning. An unfinished session from an earlier login remains accessible in Raid for review, Save or Quit. Refresh explicitly to update its roster; leaving a raid observed during the current login still asks whether to continue or end the session.

Loot Rules belong to the current raid. Each raid keeps its own save choices. Saving under another display name retains the same session identity; use **New Raid** for an independent recording. CSR uses only raids saved with **Save CSR** and their saved eligibility rules. Subsequent synchronized SR, loot, eligibility and archive corrections update that raid's CSR sources. Loading a saved raid accepts that session immediately.

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

A partially available physical raid roster cannot start a ready session or replace a complete roster. An intentional start outside a raid creates an empty session; a roster disappearing during a raid start still fails safely. If New Raid fails, the dialog retains your input so you can try again when the roster is available.

Import SR validates the entire RaidRes Base64 export before replacing reservations. Participants without reserved items, including RaidRes empty-choice placeholders, are accepted and receive no SR. Damaged exports leave the previous SR, loot and history intact; a valid empty reservation list clears SR. Imports accept up to 16000 bytes of pasted text.

Raid class and rank filters use the space needed by their captions. Filter and search controls wrap on narrow windows and expand again when space is available, in both standalone mode and Booty Suite.

Standalone Settings has two main sections: **Profile** and **Raid**. Use **Profile → General** to add, save, load, delete or export named preferences in either standalone mode or Booty Suite. Reset keeps raid and loot history.

Loot Master, New Roll and further loot dialogs open above the window that launched them, including in standalone mode.

Soft Reserve warnings stay above raid members in List and Groups. Their INFO and FIX SR windows close when the warning is dismissed or the Raid view is hidden.

Raid Leader Tools and Loot Master Tools menus open above every part of these warning cards.

## Existing data

This experimental branch clears pre-journal active raids, saved raids and CSR history once, retaining addon preferences. These records were test data; there is no migration or backward data recovery. The new synchronized records survive subsequent loads.

With current BootyProfiler installed, **Booty Diagnostics → Profile Booty** can measure selected BootyRaider operations after you select the addon and press **Start**. **Stop** ends the capture. The report covers the listed Lua entry points; it does not measure total addon CPU, RAM or disk size.

Click the displayed **Raid Type** during a real raid session to choose another raid. SR, loot, members and session timing are retained; the SR item picker uses the selected raid. Save the session to update its saved raid statistics and CSR raid filter. Search stays beside filters whenever the window is wide enough.

Loot Master Tools lists LM Mode, LM Config, New Roll, Reycoin list, Import SR, Share SR link, Set Loot Rules, Send Loot Rules and Reset Loot History. LM Config opens the same configuration with or without LM Mode. Manual Add/Edit SR selects one item; choosing another replaces it. Imported multiple reservations remain intact until you save an edit. Gold Add, Edit and Remove icons occupy space only when visible. The raid type stays visible when header actions wrap; a hidden Convert to Raid reserves no space.

Changing the active Raid Type also selects its auto-loot exclusion preset and updates an open LM Config window. Previous preset entries are replaced while your own exclusions remain. Other clears the preset entries. The save status stays beside the raid type when toolbar buttons wrap. Standalone messages use `[BootyRaider]`; `/bootyraider help` explains the common commands.

LM Config opened from Loot Master Tools can be dragged like Reycoin list. Add SR uses a gold plus, Remove uses a trash bin, and edit actions use the same gold wrench.

Auto Loot Inclusions follows Raid Type: Molten Core includes Lava Core and Fiery Core; other raids currently have empty presets. Changing type retains your custom inclusions. The SR editor automatically requests uncached visible items and highlights the selected catalogue row. Allow to SR without loot rights is available only when that player has no SR rights. Saving without rights and without this exception asks for confirmation. The exception asterisk remains visible when hovering the item.

The SR editor retains resolved item names and quality colours across selection, filtering and reopening for the current login. The missing-rights confirmation uses a short, fully visible message.

Raid Log shows dated officer actions, original nicknames and before/after details. Open it from Raid Leader Tools, the log icon beside a saved raid, or `/br log [raid ID]`. Imports appear as one summary; unchanged saves, UI activity and routine observations do not spam the log. Conflict decisions preserve the earlier proposals and their status.

## Officer synchronization

With synchronization enabled in Settings, guild officers exchange missing raid changes while online, including outside the raid. Any officer holding a copy can pass it on after the author logs out. Everyone needs a compatible BootyRaider build. Data waits when no holder is online.

Open **Sync / Recover** beside New Raid, **Raid Sync / Conflicts** in Raid Leader Tools, or `/br sync`. Select a session and **Recover** to continue with its existing identity, SR, loot and rules. To record the current physical roster, use **Start Live Tracking** in Raid Leader Tools and confirm the refresh. Recovery never repeats loot distribution or announcements.

**Conflicts** shows the agreed value and each officer's proposal. Choose the intended SR or loot correction; a stale editor draft asks you to reopen it before saving. Asterisks mark provisional CSR while a source is disputed. When two officers record separately, use **Compare raids** and decide whether matching awards are duplicates or separate items before merging.

If recording a confirmed loot receipt fails, use **Save Raid** to retry. Recovery stays blocked until those local loot and entitlement changes are safely recorded.

Peer confirmation means another client has received data in memory. `/reload` or normal logout writes SavedVariables; losing every unsaved copy cannot be repaired. A recording gap cannot reconstruct events nobody observed. Raid Log retains author attribution supplied by trusted guild officers; it is not tamper-proof evidence.
