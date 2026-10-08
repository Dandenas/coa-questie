# Changelog

## v1.0.5 — Release Notes

### Database
- **[Cleanup — Remove Redundant Sunstrider Overrides]** Removed temporary `uiMapIdToAreaId` entries for Sunstrider Isle (`1241 -> 3430`, `946 -> 3430`) from `Zones/AscensionZoneTables.lua`.
  - **Why**: The active fix path now lives in Questie-X core, which performs per-zone/ghost-map handling and reverse-map resolution locally. Keeping duplicate plugin-side overrides in AscensionDB risked documentation drift and obscured the actual root cause.
  - **What did NOT work / learned**: Treating AscensionDB as the primary place to solve Sunstrider arrow behavior was a dead end for the current issue. The remaining failures were in Questie-X core tooltip/arrow/map compatibility layers, not in the database plugin.

- **[Fix — Tooltip Objective Precedence]** Updated the tooltip data handoff so active quest tooltips defer to canonical AscensionDB objective data when it is present. This keeps learner-generated tooltip text from obscuring the split-table objective lines during active quest testing and matches the current quest/objective ownership split.

- **[Fix — Quest 8335 Level]** Set `requiredLevel` ([4]) and `questLevel` ([5]) for quest 8335 ("Felendren the Banished") in `Bronzebeard/Split/AscensionQuestDB_questData_1.lua` to 1/1 to match the actual starter level on Ascension's Eversong quest chain. Previously stored as 10/13, which made the quest tracker show an incorrect level for the quest when viewed in the learner's quest list.

### Release v1.0.5
- **[Plugin — Realm Check]** Committed the CoA Beta / Vol'jin realm allowlist fix so `AscensionLoader.lua` now recognizes `CoA`, `Conquest`, and `Vol` realm-name substrings and loads on the Vol'jin CoA Beta environment.
- **[Database — Sunstrider NPC Spawns]** Corrected Sunstrider NPC spawn data in the Ascension database split files, including the trainer / quest chain coverage used by the Eversong and Sunstrider Isle content.
- **[Database — Sunstrider Quest Items]** Added the matching Sunstrider quest item data to the item split tables so the quest chain resolves cleanly without missing item metadata.
- **[Cleanup — Dev/Test Files]** Tightened `.gitignore` and untracked local test/dev Python helpers so repository releases do not ship transient tooling such as `rechunk_db.py`, `test_bracket.py`, or `test-macros-*.lua`.

### Plugin
- **[Fix]** Extended realm allowlist in `AscensionLoader.lua` and `AscensionUiMapData.lua` to include **CoA**, **Conquest**, and **Vol** realm name substrings. This enables the plugin to load correctly on the "Vol'jin - CoA Beta" realm and other Conquest-of-Azeroth realms that were previously being silently skipped.

## v1.0.3 — Initialization Stability and Visibility Fix

### Plugin
- **[Fix]** Database compilation is now deferred to **Stage 3** on WotLK/Ascension clients. This ensures the compilation progress log is fully visible in the chat frame after login.
- **[Fix]** Resolved Stage 2 initialization crash by ensuring `l10n` and `QuestieCorrections` are initialized during deferred flow.
- **[Fix]** Fixed "bad argument #1 to 'pairs' (table expected, got nil)" in `zoneDB.lua` by initializing `QuestPointers` as an empty table in the dummy block.
- **[Stability]** Implemented comprehensive dummy handles and pointers in `QuestieDB.lua` to prevent downstream crashes while the database is being compiled.
- **[Fix]** Added guarded `QuestieDB:Initialize()` call in Stage 3 to ensure handles are properly set up after late compilation.

## v1.0.2 — Injection and Newline Fixes

### Database
- **[Fix]** Fixed hidden literal newline characters (`\\n`) in the rechunking script that were causing all split files to load as a single comment block.
- **[Fix]** Corrected database injection casing in `AscensionLoader.lua` to match `QuestiePluginAPI` requirements (`QUEST`, `NPC`, `OBJECT`, `ITEM`).
- **[Fix]** Restored `InjectUiMapData` call to ensure zone boundary data is correctly loaded.

## v1.0.1 — Architecture Update

### Database
- **[Performance]** Split monolithic database files into smaller chunks to resolve memory allocation errors.
- **[Architecture]** Adopted the split-loading architecture (like WotLKDB) to reduce initial memory footprint and load times.

### Plugin
- **[Loader]** Updated `AscensionLoader.lua` to dynamically inject `addonTable` populated by split files.

## v1.0.0 — Initial Release

### Database
- **[Quests]** Initial Ascension quest loading.

### Plugin
- **[Core]** Created Questie-X-AscensionDB.
