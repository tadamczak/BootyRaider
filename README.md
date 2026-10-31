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

New Raid also works outside a raid, creating an empty session you can prepare before grouping. In a raid it captures the physical roster independently of guild membership. Leaving or disbanding the group keeps the session, roster and Save controls available until you explicitly save/end or quit. **Convert to Raid**, beside Raid Info, lets a party leader convert the group. It is grey and inactive when conversion is unavailable, and hidden while already in a raid. Save Raid preserves the roster and loot. Raid Stats and CSR include a raid only after it has been saved and ended; reopening removes it from both summaries until it is ended again. Live tracking, group/list appearance, the default game Raid tab and Loot Master messages have independent settings.

In the Raid list, use **+** beside an empty SR or **Edit** beside its delete icon. Choose one item from the selected raid's catalogue; another choice replaces it. For an item missing from the catalogue, type its full name in the search field and click **Add name**, then **Save**. This also works for Other raids. Named SRs are saved and included in the review after another import. **Allow to SR without loot rights** admits that player's assigned SR, including restricted items, without changing their guild rank, Reycoin or CSR rights. An asterisk marks an exception in the SR column.

After importing SR again, select which manual changes to reapply in **Reapply custom SR changes**. Unchecked changes are discarded when you press **Apply selected**. Closing keeps the review pending; reopen it through **Import SR → Review custom changes**. Routine session refreshes keep the review usable; a different import, ended session or newer SR for a selected player requires reviewing the latest data. Exception changes appear only when the exception was actually enabled or disabled. Older pending entries remain available to select or discard. Edits, removals and reassignment are also included. The independent catalogue covers Molten Core, Blackwing Lair, Onyxia's Lair, Zul'Gurub and Karazhan10 (Lower Karazhan Halls). Uncached names appear as item IDs. Other raid types have no catalogue.

Master Loot waits up to five seconds for delivery confirmation. If confirmation is missing, it releases the pending request and reports the item and recipient. Check whether the recipient received the item before trying again. Requests are never retried automatically; confirmed SR/Reycoin transfers remain available.

Logging in outside a raid does not show a raid-departure warning. An unfinished session from an earlier login remains accessible in Raid for review, Save or Quit. Refresh explicitly to update its roster; leaving a raid observed during the current login still asks whether to continue or end the session.

Loot Rules belong to the current raid. Each raid keeps its own save choices. Saving a loaded snapshot under a different **Raid ID** creates an independent copy and keeps the original. Saving under the same ID replaces that snapshot after confirmation; choosing another existing ID replaces only the confirmed destination. Copies keep the raid dates, loot rules and sync preference; each copy uses its own **Save CSR** choice. To rename the original instead, use **Edit** in Saved raids. CSR uses only ended raids saved with **Save CSR** and their saved eligibility rules. Subsequent synchronized SR, loot, eligibility and archive corrections update that raid's CSR sources. Loading a saved raid accepts that session immediately.

Saved raids show **Duration**, **Created At** and **Modified At**. Duration uses the recorded raid end and displays, for example, **1h 05min 09s**. **Save raid end time** records the end when saving; **Modify raid end time** enables changing an existing end in **DD.MM.YYYY HH:MM:SS** format. Without a recorded end, duration is **Unknown**. Editing or copying a raid preserves its original creation date and recorded end.

Saved lists use **Raid ID** and **Raid Type**. Use **Edit** beside a saved raid to change its ID and type. Raid Stats also lets you change the type. Finish an active raid before renaming its ID. Saving metadata offers the usual reload prompt. The **Issues** button minimizes or restores Soft Reserve warnings.

Loot Master message settings are grouped by topic. Each text field shows a complete example that updates while you edit, including your prefix and whisper preference.

In Raid Stats, **Select all** selects or clears the currently filtered raids. Search also matches players and partial item names. Names saved with the raid are searchable even without the client cache; older records containing only item IDs need cached names.

CSR retains history beyond 60 days. **Show archived CSR** includes expired reserves with zero points. **Group By** offers Default, Player and Item; expand rows to inspect source raids, dates, expiration and ACTIVE/ARCHIVED status. Click column headings to sort each table. Editing or copying an old raid does not renew its CSR expiration. History remains until manually deleted; records removed by older versions cannot be recovered.

Each CSR source has an eye icon to view its raid. **Archive** removes that source's points while retaining its history. With **Show archived CSR** checked, **Activate** restores a manually archived source before its original expiration. Expired sources cannot be activated. Overwriting the same raid preserves archive decisions; a new Raid ID has independent sources.

Receiving an item retains its previous reserve entries as **AWARDED** under **Show archived CSR**. These entries grant zero CSR and cannot be activated. A later unsuccessful reserve starts accumulating points again.

**CSR Test Lab** uses temporary data. Select an earlier test player to add more reserves or award the selected item, archive test sources, and advance time with **+1 Day** or **+7 Days**. View Raid is disabled for simulated sources. Exit Test returns to saved history.

Only current guild ranks **Officer Wukong** and **Mukla** can archive/activate CSR, edit saved raid details, or edit/remove Raid Stats. Reading history remains available to everyone. These controls wait for current guild information; a raid leader or assistant role alone grants no history editing rights.

**Settings → Addon UI → CSR → General** offers **Use class colors**. **Layout** controls class icons and visibility of each filter. These options are enabled by default. Hiding all filters removes the filter toolbar; hidden filters retain their selected values. Expand controls appear before the class/item icon and name.

**Save Raid** keeps the current session open, with its tracking and selected player unchanged. **Leave Session** returns to the raid list; **End & Save** also saves and ends the shared raid. Save Raid offers a reload to write data to disk. This waits until other Booty products have no active raid or recording. A failed startup or Stop reports its reason and retains raid data.

Players who leave remain in the session list with **Left raid** status. Expand a player to see **Joined raid** and **Left raid** timestamps above their loot. Rejoining preserves the first join time. Saving after players leave keeps their attendance, SR and loot for the completed raid's statistics and CSR. A new session starts from the current physical roster.

In **Raid members without SR → Fix SR**, select **No Soft Reserve** on the right and click one or more players, then save. This acknowledges their lack of an SR and clears the warning without granting an item or CSR. Assigning an item replaces that choice. It participates in the review of manual changes after another import.

A partially available physical raid roster cannot start a ready session or replace a complete roster. An intentional start outside a raid creates an empty session; a roster disappearing during a raid start still fails safely. If New Raid fails, the dialog retains your input so you can try again when the roster is available.

Import SR validates the entire RaidRes Base64 export before replacing reservations. Participants without reserved items, including RaidRes empty-choice placeholders, are accepted and receive no SR. Damaged exports leave the previous SR, loot and history intact; a valid empty reservation list clears SR. Imports accept up to 16000 bytes of pasted text.

Raid class and rank filters use the space needed by their captions. Filter and search controls wrap on narrow windows and expand again when space is available, in both standalone mode and Booty Suite.

Standalone Settings groups addon preferences under **BootyRaider**. Use **Profile → General** to add, save, load, delete or export named preferences; BootySuite lists the addon profiles separately under Profile. Reset keeps raid and loot history.

Loot Master, New Roll and further loot dialogs open above the window that launched them, including in standalone mode.

Soft Reserve warnings stay above raid members in List and Groups. Their INFO and FIX SR windows close when the warning is dismissed or the Raid view is hidden.

Raid Leader Tools and Loot Master Tools menus open above every part of these warning cards.

## Existing data

This experimental branch clears pre-journal active raids, saved raids and CSR history once, retaining addon preferences. These records were test data; there is no migration or backward data recovery. The new synchronized records survive subsequent loads.

With current BootyProfiler installed, **Booty Diagnostics → Profile Booty** can measure selected BootyRaider operations after you select the addon and press **Start**. **Stop** ends the capture. The report covers the listed Lua entry points; it does not measure total addon CPU, RAM or disk size.

Click the displayed **Raid Type** during a real raid session to choose another raid. SR, loot, members and session timing are retained; the SR item picker uses the selected raid. Save and end the session to include its updated type in Raid Stats and CSR. Search stays beside filters whenever the window is wide enough.

Loot Master Tools lists LM Mode, LM Config, New Roll, Reycoin list, Import SR, Share SR link, Set Loot Rules, Send Loot Rules and Reset Loot History. LM Config opens the same configuration with or without LM Mode. Manual Add/Edit SR selects one item; choosing another replaces it. Imported multiple reservations remain intact until you save an edit. Gold Add, Edit and Remove icons occupy space only when visible. The raid type stays visible when header actions wrap; a hidden Convert to Raid reserves no space.

Changing the active Raid Type also selects its auto-loot exclusion preset and updates an open LM Config window. Previous preset entries are replaced while your own exclusions remain. Other clears the preset entries. The save status stays beside the raid type when toolbar buttons wrap. Standalone messages use `[BootyRaider]`; `/bootyraider help` explains the common commands.

LM Config opened from Loot Master Tools can be dragged like Reycoin list. Add SR uses a gold plus, Remove uses a trash bin, and edit actions use the same gold wrench.

Auto Loot Inclusions follows Raid Type: Molten Core includes Lava Core and Fiery Core; other raids initially have empty inclusion presets. LM Config offers both **Add Exclusion Preset** and **Add Inclusion Preset**. In **Settings → Addon UI → Raid → Loot Master Mode → LM Config**, the independent **Exclusion Presets** and **Inclusion Presets** forms offer Add, Save and Delete. The five built-in raid presets can be edited but cannot be renamed or deleted. Custom presets belong only to their own list. Changing Raid Type applies both matching built-in presets and retains your manual entries. The SR editor automatically requests uncached visible items and highlights the selected catalogue row. Allow to SR without loot rights is available only when that player has no SR rights. Saving without rights and without this exception asks for confirmation. The exception asterisk remains visible when hovering the item.

The SR editor retains resolved item names and quality colours across selection, filtering and reopening for the current login. The missing-rights confirmation uses a short, fully visible message.

Raid Log shows project-gold timestamps and values aligned with their column headings. Details show **Who**, **Action** and **Time**, followed by **Before** and **After** columns with gold labels. SR changes identify the player and previous/new item, with item tooltips and link clicks. Its minimum size is 520 × 200; the number of visible rows follows its height. Open it from Raid Leader Tools, the log icon beside a saved raid, or `/br log [raid ID]`. Imports appear as one summary; unchanged saves, UI activity and routine observations do not spam the log. Conflict decisions preserve the earlier proposals and their status. SR resolution entries name the raid, player and chosen item. Compare raids provides a Details button for each difference, with separate named panes for both recordings.

## Officer synchronization

New Raid, Test Raid and Sync share the left side of the raid toolbar; Raid Info stays on its right. Active sessions show their ID, raid, recorded member count, capacity, creation date, storage and last save. Saved raids also show Active/Ended status. Raid names use MC, BWL, ZG, Ony and K10; duration uses HH:MM:SS. Join and reopen sessions from the Raid tab. Sync lists active sessions (including unsaved memory copies) and saved raids for conflict review and recording comparisons. Ended sessions without a snapshot are excluded. Offline officers do not remove active sessions from recovery. Active and saved session headings use matching text sizes and distinct icons.

**Active raid sessions** appears above Saved raids. Join the existing session when another officer in your current party or raid has one; New Raid is disabled while that session is known or being checked. Separate groups can record separate sessions. Loading an ended snapshot reopens that same shared session (officer access required). Saved raids show **In memory** after changes and **On disk** for the version read at addon startup, plus the last editor; the active raid shows **Last save**. Save does not itself write WoW SavedVariables files.

**Sync status** shows **Syncing…**, **Up to date**, **New data received. Please reload!**, or **Sync error! Send log**. Officers show synced/pending/error individually. Reload writes the current client data and loads it again; the disk indicator describes this character’s copy, not another officer’s disk. A connection alone does not prove an individual change was received.

With synchronization enabled in Settings, guild officers exchange missing raid changes while online, including outside the raid. Any officer holding a copy can pass it on after the author logs out. Everyone needs a compatible BootyRaider build. Data waits when no holder is online.

Open **Sync** on the Raid list, **Session → Raid Sync** during a session, or use `/br sync`. Raids and updates arrive automatically when officers are online. The Sync table has gold icon actions for resolving conflicts and comparing another recording with the open raid. Hover an icon for its action. **Settings → Addon UI → Raid → General → Live tracking** controls roster observation and is enabled for new preferences. Opening a raid never repeats loot distribution or announcements. **Leave Session** closes it only on your character, without creating a snapshot; other officers continue. **End & Save** opens save options and, after a successful save, ends the shared session for all officers. Cancel or a failed save leaves it active. The saved snapshot continues synchronizing. Officers who still have that session open see who ended it and choose **Continue Session** to reopen the same shared raid, or **Quit** to return to the raid list without saving again. Ending replaces any pending departure/save prompt; leaving the physical raid afterwards does not ask for another End & Save. If confirmed loot changes exist only on this character because their earlier save failed, Quit keeps them safe and explains that they must be saved first. **Reopen** asks for confirmation before making an ended session active again. **Sync log** keeps the latest 100 meaningful received updates, confirmed deliveries, officer connections/disconnections and errors on this character, without duplicate packet or refresh messages. Drag the resize grip to resize sync and Raid Log windows; their dimensions are remembered.

The conflict action shows the agreed value and each officer's proposal. Choose the intended SR or loot correction; a stale editor draft asks you to reopen it before saving. Asterisks mark provisional CSR while a source is disputed. When two officers record separately, use the compare icon and decide whether matching awards are duplicates or separate items before merging.

If recording a confirmed loot receipt fails, use **Save Raid** to retry. Recovery stays blocked until those local loot and entitlement changes are safely recorded.

Peer confirmation means another client has received data in memory. `/reload` or normal logout writes SavedVariables; losing every unsaved copy cannot be repaired. A recording gap cannot reconstruct events nobody observed. Raid Log retains author attribution supplied by trusted guild officers; it is not tamper-proof evidence.

Officer synchronization requires the same transport build on all participating clients. After updating to 1.0.0-dev.5, reload every client to enable the native chat-compatible transport. Existing raid data is retained.

Conflict review opens directly from the raid row. Select Your data or the named officer’s synced data, then Accept. The counter shows progress through conflicts. For a conflict containing several changes, each choice is collected before saving the complete decision. Item values support tooltips and item-link clicks. Ended raids support manual review of remaining loot and SR conflicts.

During an active session, concurrent edits use the newest recorded change automatically. A causal later edit supersedes its ancestors; concurrent timestamps are compared, with an immutable change ID breaking ties. Both versions remain in history. Ending the raid makes unresolved differences available for manual review; reopening restores automatic latest-change selection. Saving a snapshot while the session remains active does not switch this policy.

New sessions have **Raid sync** checked by default. Uncheck it to keep that raid and its CSR source data on this character. Gold sync icons beside active and saved raids toggle this setting; a pressed icon means sharing is enabled. Stopping synchronization does not delete copies already received by other officers. Enabling it again exchanges missing changes. The setting is saved per raid on this character.

The trash icon in **Active raid sessions** removes that session after confirmation, including its active copies on synchronizing officers. Previously saved snapshots are retained; unsaved changes are not saved by this action. Loading a retained snapshot starts a separate session with a **(restored)** name, preserving the original saved raid. Update all synchronizing officers to the same build before using this action.

During a session, use **Session → Save Raid / Raid Sync / Leave Session / End & Save**. Raid Sync for a local-only raid shows **Start raid synchronization** in the center. The Sync table shows #, Raid ID, Raid, Active/Ended status, individual sync status, conflicts and actions. The current raid has a Stop Sync icon. Connected officers remain beside the tabs; the global status stays on the main Raid tab.

Raid row actions use matching compact gold buttons. Sync uses a circular-arrow icon when on and a disabled icon when off, with an explicit state tooltip. Join and Load share the same play icon. The compact Session menu is the active raid’s Sync entry point. Raid Log describes data edits and their authors; Sync log describes data exchange, delivery confirmations, officer connections and synchronization errors.

Synchronization supports up to 12 other officers (13 clients including yours). It sends missing changes and inventory metadata; unchanged discovery does not resend the raid database. Private raid edits do not trigger shared inventory announcements. Technical status display updates are grouped during packet bursts; raid data changes remain immediate.

Without BootySuite, the top tabs **Raid**, **Raid Stats** and **CSR** switch between BootyRaider views while retaining your raid session, window position and size. Standalone resizing follows Suite behavior. Drag the LM Config window when opened from the main Raid view.

Standalone Raid separators align with the top tabs and the side frame, including after resizing.

**End & Save** after leaving a raid instance saves the same raid and marks the shared session **Ended**, just like the Session menu action. Cancelling or a failed save leaves the session active.

Raid Stats editing has an action toolbar with **Add Entry**, **Loot Rules**, **Cancel** and **Save**. Loot Rules edits apply to that saved raid when you save; enable the relevant rank’s CSR rights and **Save CSR** to include its eligible reserves. Cancel discards the draft. Click **CSR Test Lab** again to close it and return to your saved history; reopening retains the temporary simulation. Minimizing and restoring Raid Stats keeps the selected raid visible.

In **Settings → Addon UI → Raid Stats**, General controls the heading and class colors for all details. Layout controls each filter, Raid ID/time in the raid list, attendance in single-raid details, and attendance/SR/loot in multi-raid details. Hiding ID or time makes the raid list narrower. Hiding all filters removes their toolbar; hidden filters retain their selected values. CSR has its own General heading and class-color options. **Addon UI → General** contains **Synchronize raids and CSR with other officers** and **Show action messages in chat**. Raid → Layout → Loot Master Mode View controls opacity. Raid → Loot Master Mode → LM Config uses the same auto-loot mode and rarity selectors as the LM Config window. Game UI options are grouped under Raid; fresh and reset addon Groups use the same stock appearance as native Groups, while existing custom preferences are kept.

Click **Loot received** or **Soft Reserves** again to close its list. Both windows can be resized and remember their own dimensions. Soft Reserves aligns the gold Raid ID and date in separate columns. Loot received shows the actual receipt date and time in gold, without Raid ID; older loot without a recorded time shows **Time not recorded**. Repeated ordinary receipts remain grouped with the first receipt time.

CSR class icons are under **Layout → General**. Each Group/List layout subsection, Raid Stats/CSR layout subsection, native Raid layout subsection and Loot Master message section has its own **Reset** button. It leaves other preferences and saved raids unchanged. This update restores the integrated native Raid view to the stock font, spacing, empty-slot artwork and portrait once; subsequent customization is retained. Existing main-window Group preferences are kept.

Raid Log recording is separate from Live tracking. In an active session, open **Raid Leader Tools → Raid Log** and click **Start Recording Raid Events** to record future officer actions on this character for that raid. Existing historical entries remain readable. This choice does not disable raid/CSR synchronization. The player context menu closes when clicking outside it; **New Leader** uses the native leader action.
