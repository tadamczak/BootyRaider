# Changelog

## 1.0.1-dev.2 — 2026-10-31

- Save long raids as journal differences instead of resending already recorded loot.
- Wait for returning officers before retrying their transfers; avoid repeated discovery while recording alone.
- Reduce loot projection allocations and defer journal maintenance until outside a raid.

## 1.0.1-dev.1 — 2026-10-31

- Shorten README to essential features, installation and basic usage.

## 1.0.0 — 2026-10-31

- First production release of raid sessions, loot tools, Soft Reserves, Raid Stats and CSR, standalone or in Booty Suite.
- Synchronize authorized officers, recover interrupted sessions and review saved-raid conflicts; private raids remain independent.
- Retain departed participants, named reserves and completed history, with compact CSR views and an isolated Test Lab.
- Bound background synchronization and hidden UI work. Preserve existing journal data and preferences.
- Requires BootyLib 0.1.0. Update all synchronizing officers together. Pre-journal test raid/CSR data is reset once.

## 1.0.0-dev.36 — 2026-10-31

- Keep private raid offers from blocking other synchronized raids or falsely timing out their officers.
- Include compact CSR history, clearer archived/awarded sources and structured Test Lab player, item and timeline controls.
- Return to saved CSR when the CSR page closes; retain the temporary Lab data for explicit reopening.
- Keep legacy Suite minimap preferences separate from BootyRaider's standalone setting.
- Candidate for in-game verification with BootyLib 0.1.0-dev.84. Update all synchronizing officers together; current journal data and preferences are retained.

## 1.0.0-dev.35 — 2026-10-31

- Stop redundant Raid renders, hidden drag updates and equal-opacity polling in Loot Master Mode.
- Pause historical synchronization work correctly in combat and start inventory timeouts when data is sent, keeping queued transfers safe.
- Keep published Raid Stats/CSR stable during partial synchronization; preserve named SR and departed participants when editing saved raids.

## 1.0.0-dev.34 — 2026-10-31

- Reduce initial synchronization traffic with compact data messages and coalesced relay announcements, keeping the existing sending limit. Reload every officer client after updating.
- Keep incomplete historical transfers out of active-session projections and report progress until the raid is complete; preserve existing local data during catch-up.

## 1.0.0-dev.33 — 2026-10-31

- Preserve officer connections and transfers while the guild roster refreshes, then resume with fresh permissions. Recover automatically after a longer directory pause.
- Disable manual roster refresh whenever Live tracking is enabled, including sessions outside a raid.

## 1.0.0-dev.32 — 2026-10-31

- Recover interrupted synchronization without stale transfer queues; report Sync interrupted and reject packets from earlier connections. Officers must use this same synchronization build.
- Fit full native raid class names and use matching role icons. Simplify /br commands, add a login hint and standalone minimap preference.
- Capture current settings once as the protected BootyRaider Default profile. Keep Raid Stats/CSR editing restricted to guild officers and the guild master.

## 1.0.0-dev.31 — 2026-10-31

- Keep Save Raid in the active session. Retain departed participants, join/leave times and their statistics/CSR through tracking, saving and synchronization.
- Add an explicit No Soft Reserve choice for one or more players. Show readable Raid Log before/after details with item links and aligned columns.

## 1.0.0-dev.30 — 2026-10-31

- Keep custom SR review usable after session data refreshes, while guarding newer imports and selected-player edits. Ordinary SR saves no longer record an unchanged exception as a removal.

## 1.0.0-dev.29 — 2026-10-30

- Separate editable inclusion/exclusion presets with protected built-ins and custom deletion. Add section resets, restore the native raid appearance, align hidden-header filters and resize persistent loot/SR lists with gold context columns. Preserve older recorded loot times.

## 1.0.0-dev.28 — 2026-10-30

- Add active-session removal while preserving saved snapshots, editable auto-loot presets and matching LM selectors. Reorganize settings, allow individual Raid Stats/CSR filters to be hidden, reclaim unused layout space and unify gold column headings.

## 1.0.0-dev.27 — 2026-10-29

- Include only saved, ended raids in Raid Stats and CSR. Add display settings, toggled item lists with loot timestamps, independent Raid Log recording, native Group defaults and corrected member menus. Allow a narrower synchronization window.

## 1.0.0-dev.26 — 2026-10-29

- Fix standalone tab separators and restore Raid Stats immediately with the updated shared window controls. Keep the save dialog inside its frame and add an editor toolbar with readable headings and per-raid Loot Rules. Clicking CSR Test Lab again closes it.

## 1.0.0-dev.25 — 2026-10-29

- Notify officers with an open session when another officer saves and ends it: Continue Session reopens it; Quit returns to the raid list without another save.
- Suppress obsolete departure/save prompts after a shared end, including already-open confirmations, and refresh the raid screen on Quit.

## 1.0.0-dev.24 — 2026-10-29

- Save a loaded raid under a different Raid ID as an independent copy, preserving the original through synchronization and reload.
- Preserve destination identity for confirmed replacements, copy sync preferences and raid data, and keep save failures atomic.

## 1.0.0-dev.23 — 2026-10-29

- Make End & Save from both raid-context prompts end the shared session as well as save its snapshot.
- Reset the save dialog mode explicitly on every entry point, preserving cancellation and failed-save behavior.

## 1.0.0-dev.22 — 2026-10-29

- Align standalone Raid toolbars and filter/history separators with the top navigation separator.

## 1.0.0-dev.21 — 2026-10-29

- Keep the window position and size when switching standalone tabs; resize content through live native anchors like Suite.
- Enable dragging LM Config when opened from the main Raid view.

## 1.0.0-dev.20 — 2026-10-29

- Avoid duplicate Raid redraws during host-managed resizing.
- Add visible Raid, Raid Stats and CSR tabs to standalone windows; preserve integrated Suite navigation.

## 1.0.0-dev.19 — 2026-10-29

- Reduce redundant discovery replies and suppress advertisements for private raid edits.
- Prevent live raid changes being delayed by repeated inventory discovery; support concurrent incoming streams from all twelve peers within the existing byte budget.
- Coalesce technical status redraws and skip queue scans while waiting for the next scheduled wake.

## 1.0.0-dev.18 — 2026-10-29

- Unify raid row actions at 24px with matching Join/Load icons and distinct sync-on/off icons.
- Compact Session and match its open state and Sync tabs to Loot Master Tools; remove redundant active-session Sync.
- Reapply separator texture bounds at the inner window border.

## 1.0.0-dev.17 — 2026-10-28

- Choose Raid sync when creating a session; toggle sharing for active and saved raids.
- Put Save Raid, Raid Sync, Leave Session and End & Save in the Session menu.
- Show individual raid status and sync status in the compact Sync table; fix separator bounds.
- Block disabled raids in inventory, queued transfers and incoming updates; resume missing changes on opt in.

## 1.0.0-dev.16 — 2026-10-28

- Fix the leftover Convert to Raid control over the history toolbar.
- Add saved status, active storage/last save, short raid names and HH:MM:SS duration.
- Clarify conflict outcomes and raid comparisons with per-row Details and named value panes.
- Exclude ended, unsaved journal-only sessions from the raid catalog; preserve recovery and deletion history.

## 1.0.0-dev.15 — 2026-10-28

- Separate Leave Session from End & Save; ending now saves a snapshot before closing the shared session.
- Show live raid roles from the game roster instead of stale synchronized crowns.
- Compact Raid Log with gold timestamps, smaller minimum size and concise before/after details.

## 1.0.0-dev.14 — 2026-10-28

- Active raid edits automatically use the latest concurrent change; ended raids retain manual conflict review. Timestamp ties resolve consistently across officers.

## 1.0.0-dev.13 — 2026-10-28

- Use measured, matching raid tables and compact synchronization controls. Keep session actions in Raid.
- Resolve conflicts by selecting Your data or an officer’s synced data, with item tooltips and one Accept button.
- Rename live tracking to Record raid events and reduce synchronization/dialog minimum sizes.

## 1.0.0-dev.12 — 2026-10-28

- Open conflicts directly in a sectioned comparison with one Accept action; keep unresolved loot/SR when ending a raid. Color connected-officer captions gold.

## 1.0.0-dev.11 — 2026-10-28

- Keep the saved-raid scrollbar tied to measured overflow; add full active-session columns.
- Compact sync tabs and actions, color status captions gold and offer one join action appropriate to the session state.

## 1.0.0-dev.10 — 2026-10-28

- Align raid history actions in one full-width bordered toolbar, with unique icons and matching active/saved section headings.

## 1.0.0-dev.9 — 2026-10-27

- List active sessions above saved raids and guard new sessions when a group already has one; loading an ended snapshot reopens its shared session.
- Show snapshot storage state, last editor and Last save; add concise sync status and per-officer progress.
- Rename Sync log, use gold timestamps, record disconnects and ignore obsolete packets after reload.
- Keep sync tabs and officer headers clear of icons and table rows when resizing.

## 1.0.0-dev.8 — 2026-10-27

- Keep authenticated officers connected when the cached guild roster still says offline; honor subsequent roster updates and officer access changes.
- Log connections and explicit receipts for new officer changes without duplicate packet entries; clarify status wording.

## 1.0.0-dev.7 — 2026-10-27

- Automatically reconnect officer synchronization on guild presence changes; keep idle online officers connected.
- Open ended raids with continuing updates, explicitly reopen shared sessions, and load the latest synchronized snapshot data.
- Keep Raid Sync beside Raid Info; combine raid actions in one table, simplify statuses and add a bounded Synchro Log.
- Resize synchronization, comparison, conflict and Raid Log dialogs with remembered dimensions.

## 1.0.0-dev.6 — 2026-10-27

- Ignore guild messages echoed to their own sender instead of showing a false synchronization rejection.

## 1.0.0-dev.5 — 2026-10-27

- Fix officer synchronization rejected by the native chat escape parser. All synchronizing officers must reload this transport update.

## 1.0.0-dev.4 — 2026-10-27

- Preserve confirmed local loot and consumed entitlements after journal errors: recovery requires a successful Save Raid retry before replacing the active session.

## 1.0.0-dev.3 — 2026-10-27

- Exchange missing raid and CSR source changes between guild officers, including relay without the author and recovery after disconnects.
- Preserve conflicting SR/loot edits for explicit resolution; mark affected CSR provisional and compare independently recorded raids before merging.
- Add Sync / Recover, officer status and conflict details; retain stale editor drafts without overwriting received changes.
- Keep audit attribution through relays and checkpoints; bound transfer queues and stop idle scheduling. Native multi-client acceptance is pending.

## 1.0.0-dev.2 — 2026-10-27

- Add a compact local Raid Log for officer edits, imports, loot allocations/corrections, saved raids and CSR archive decisions; unchanged actions stay silent.
- Keep session/allocation identities across capture, save and load; show before/after details lazily.
- Reset pre-journal raid/CSR test data once, retaining preferences. This experimental branch does not enable peer transport or remote recovery.

## 1.0.0-dev.1 — 2026-10-27

- Add the local causal journal foundation with stable identities, atomic operations, duplicate checks and data-only replay; peer transport remains disabled.

## 0.1.0-dev.34 — 2026-10-27

- Preserve resolved SR item names and quality colours across editor refreshes; shorten the missing-rights confirmation and fit all message lines.

## 0.1.0-dev.33 — 2026-10-27

- Apply MC inclusions with Raid Type; preserve SR exception markers, gate exceptions by rights, confirm ineligible saves and preload/highlight selected SR items.

## 0.1.0-dev.32 — 2026-10-26

- Allow dragging standalone LM Config; use a gold plus for Add SR, a trash bin for Remove and the same gold wrench for edit actions.

## 0.1.0-dev.31 — 2026-10-26

- Update exclusion presets and open LM Config when changing raid type, preserving custom exclusions; keep save status beside the raid type when actions wrap.

## 0.1.0-dev.30 — 2026-10-26

- Order Loot Master Tools and share LM Config; center dropdown captions, limit manual SR to one item, use compact gold SR actions and retain raid type when header actions wrap.

## 0.1.0-dev.29 — 2026-10-26

- Change the active raid type from its heading while preserving session data; keep Search inline when filters fit at native control heights.

## 0.1.0-dev.28 — 2026-10-26

- Count named SR toward CSR without item IDs, ignoring case and extra spaces; preserve award resets and source archiving.
- Grey out unavailable Convert to Raid and hide it while already in a raid; update on party and leader changes.

## 0.1.0-dev.27 — 2026-10-26

- Add uncatalogued SR items by name and match them without case or extra-space sensitivity, including real item links and confirmed receipts.
- Accept typed item names in New Roll without requiring an item link or cache entry.
- Preserve named reservations in saved raids, statistics and selective custom-change review after import.

## 0.1.0-dev.26 — 2026-10-26

- Start sessions outside a raid and keep their roster and controls available after disband.
- Add Convert to Raid beside Raid Info for party leaders.
- Add manual SR selection/editing, per-player SR exceptions and selective custom-change review after reimport.
- Include a compact independent item catalogue for the five named raid types.

## 0.1.0-dev.25 — 2026-10-25

- Allow cloaks in Tmog rolls, including default categories, commands and New Roll.

## 0.1.0-dev.24 — 2026-10-22

- Release stalled Master Loot requests after five seconds without confirmation, including when the loot window closes.
- Report failed delivery separately from an already awarded item; preserve confirmed SR/Reycoin transfers during cleanup.

## 0.1.0-dev.23 — 2026-10-22

- Expose explicit on-demand timing targets for Booty Diagnostics without idle scanning or memory measurements.

## 0.1.0-dev.22 — 2026-10-22

- Do not treat logging in outside a raid as leaving one.
- Keep recovered unsaved sessions visible for review, saving or quitting.

## 0.1.0-dev.21 — 2026-10-17

- Keep consumed CSR history as AWARDED with zero points.
- Compact CSR columns and archive filter; use matching gold action icons.
- Expand the isolated CSR Test Lab with player selection, archive actions and day controls.
- Use subtle alternating snapshot row backgrounds.

## 0.1.0-dev.20 — 2026-10-17

- Restore the original thin CSR project border after the rejected outline change.

## 0.1.0-dev.19 — 2026-10-17

- Render CSR accordion outlines with the existing project border's locally anchored texture pieces.

## 0.1.0-dev.18 — 2026-10-17

- Archive individual CSR sources and reactivate manually archived sources before expiration.
- Restrict CSR changes and saved raid editing/removal to current Officer Wukong and Mukla ranks.
- Add CSR class icons/colors, align nested columns and compact the archive filter.
- Use Raid ID / Raid Type and give duration more space in saved raid history.

## 0.1.0-dev.17 — 2026-10-17

- Record and optionally edit the actual raid end time; format duration as hours, minutes and seconds.
- Edit saved raid IDs, names and types from history and change raid type in Raid Stats.
- Use Created At for CSR expiration and match nested tables to the Profiler style.
- Minimize and restore warning cards with Issues.
- Group Loot Master messages by topic and preview their full text while editing.

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
