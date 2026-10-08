# Changelog

## [Unreleased]

### Bug Fixes

- **[Fix — InsertMissingQuestIds String Guard]** Added `if type(QuestieDB.questData) ~= "table" then return end` guard at the start of `InsertMissingQuestIds()` in both `tbcQuestFixes.lua` and `wotlkQuestFixes.lua`. Prevents the function from writing to `questData` while it is still an uncompiled Lua string during early loader initialization, which caused `attempt to index field 'questData' (a string value)` errors on Ascension (WotLK) servers where `questData` is stored as a loadable Lua string rather than a compiled table.

## v1.4.7 (2026-03-22)
- **[Architecture]** Refactored all monolithic database files to use an isolated `addonTable` rather than writing directly to the global `QuestieDB` variable. 
- **[Taint Prevention]** Completely eliminated global namespace pollution during database load to prevent `ADDON_ACTION_BLOCKED` errors on secure functions like `UseAction()` and `CastSpellByName()` in the core addon.
- **[Bugfix]** Fixed the capitalization of export globals in `Loader.lua` (`QuestieX_WotLKDB_npc` instead of `_NPC`) so the core addon can correctly absorb statistics and database contents during initialization.
- **[Integration]** Fully integrated the `Database/Corrections` system into the table loader. All quest, NPC, item, and object overrides are now pre-applied during addon load, ensuring data accuracy in the split-table format.
