<p align="center"><img src="https://raw.githubusercontent.com/tadamczak/BootyLib/master/Assets/readme-header.png" width="100%" alt="Sons of Mukla"></p>

# BootyRaider

Raid and loot management for **WoW 1.12**. Works standalone or inside **BootySuite**.

## Features

- Raid sessions, attendance and loot history, including players who leave early.
- Loot Master tools and MS, OS, Tmog, Reycoin and SR rolls.
- Rank checkboxes grant extra rights; ordinary MS / OS / eligible Tmog rolls do not require them.
- Tmog uses equipment slots, including all main-hand, off-hand and ranged items.
- Soft Reserve import, manual edits and item names without links.
- Raid Stats and CSR points from saved, ended raids.
- Automatic officer synchronization, session recovery and Raid Log.

## Installation

- Install **[BootyLib](https://github.com/tadamczak/BootyLib)** and **BootyRaider** in `Interface/AddOns`.
- Enable both in the addon list and restart WoW. BootySuite is optional.
- All synchronizing officers should use matching versions.

## Commands

- `/br` — command list.
- `/br raid` — raid sessions.
- `/br stats` — raid statistics.
- `/br csr` — CSR balances.
- `/br config` — settings.
- `/br roll` — custom-roll syntax and options.

## Session basics

- **New Raid** starts a session, including before you join a group.
- **Save Raid** saves without leaving; **Leave Session** closes only your view.
- To copy a saved raid, use **Session → Save Raid** with a new **Raid ID**.
- **End & Save** saves and ends the shared raid; other officers can choose to continue.
- **Session removed** means the saved snapshot remains; load it to start a new session.
- Removing a reopened, previously ended session keeps its saved raid **Ended**.
- Saved raids show the newest saves first; removed sessions stay out of the Sync list.
- Uncheck **Raid sync** for a private raid; previously shared copies remain.
- Use `/reload` or log out normally to write received data to disk.

**Upgrading from old test builds:** pre-journal raid/CSR test data is cleared once; settings and current synchronized data are retained.
