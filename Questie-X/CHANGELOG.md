# Changelog

## [1.6.4] - 2026-06-12

> **⚠ Performance Refactor In Progress** — This release ships bug fixes, new features, and the first stage of universal Lua 5.0 (Vanilla 1.12) → Retail compatibility. Several measured performance optimizations (hot-path localization caching, available-quest redraw batching, `QuestieDB.IsDoable` batch reads, `GetTime()` hoists, NPC fallback lookup caching, validate-cache allocation cleanup) remain staged on the `phase3-measured-perf` branch and are being cherry-picked and in-game tested one at a time on top of this release. They are NOT all included in this build yet.

### Compatibility

- **[Lua 5.0 - Modulo Operator]** Routed the nine arithmetic `%` modulo sites (daily/weekly quest flag tests, Darkmoon Faire cycle math, learner GUID/flag math, race/class flag tests) through the existing `math.mod` shim. Lua 5.0 has no `%` operator outside string formatting, so this was a parse error on Vanilla 1.12 clients; the addon now parses on 5.0 through Retail.
- **[Lua 5.0 - Options Tab Tables]** Fixed `QuestieOptions.tabs.{auto,dbm,icons,nameplate}` being initialized with `{...}` instead of `{}`. On Lua 5.1 this silently captured the addon varargs into the table; on Lua 5.0 it is a parse error. All sibling tabs already used `{}`, and `Initialize` repopulates the table, so there is no behavioral change.

## [Unreleased] - Performance Refactor Branches

### Performance

- **[Questie Debug - Message Throttle]** Added a live debug-message throttle so non-fatal debug output cannot spam chat faster than it can be read. The throttle is configurable in the Advanced tab and keeps fatal output separate.
- **[Questie Learner - Tooltip Controls]** Added learner-specific tooltip controls so players can toggle the learned spawn line, total learned spawn count, learner confidence lines, automatic tooltip resizing, and a secondary learner tooltip from the Tooltip options. The learner tooltip paths now respect those toggles before adding extra lines.
- **[Questie Options - Faster Live Slider Refresh]** Reduced the redraw debounce on the icon, clustering, and learner spawn-dedup sliders so changes refresh pins much sooner after the user releases the slider instead of waiting half a second before `SmoothReset()` even begins. Also made `ClusterRedraw()` pass `{ skipCacheTest = true }` so clustering-only slider changes skip the `QuestLogCache.TestGameCache()` wait entirely and redraw immediately without blocking on quest log state.
- **[Questie Options - ClusterRedraw SkipCache]** `SmoothReset()` now accepts an optional `{ skipCacheTest = true }` table. `ClusterRedraw()` uses it so the Objective Icon Cluster Amount and Dense Pin Clustering Aggressiveness sliders redraw icons immediately without waiting on quest log readiness. The Quel'Danas phase, icon limit, and other callers continue to use the full `SmoothReset()` path unchanged.
- **[QuestieLearner - Kill/Pin Refresh Throttling]** Debounced learner-triggered map-pin refreshes so heavy kill streaks do not redraw pins on every event. Added a maximum wait cap so batched updates still flush predictably instead of being pushed out forever by constant activity.
- **[QuestieLearner - Bystander Kill Suppression]** Changed visible nearby `UNIT_DIED` handling so kills from other players can update short-lived correlation evidence without immediately running full learner injection or pin refresh work.
- **[QuestieLearner - PARTY_KILL Event-Order Fix]** Fixed an edge case where a `UNIT_DIED` debounce entry could suppress a later authoritative `PARTY_KILL` for the same GUID. The debounce now tracks event type and allows the player's/group's kill event through while still suppressing true duplicates.
- **[QuestieLearner - Immediate Spawn Pin Rendering]** Learner kill evidence now becomes spawn coordinates immediately in learner mode so learned NPC kills can spawn map pins without waiting for the later confidence merge path.
- **[QuestieLearner - Quest Accept Resolver Hardening]** Removed the learner `QUEST_ACCEPTED` last-resort quest-ID fallback that could invent impossible quest IDs from raw event arguments. Accepted quests now only learn when the ID resolves back to a real quest-log entry, which prevents bogus keys from being persisted in learner SavedVariables or live overrides.
- **[QuestieLearner - Live Performance Options]** Added Advanced-tab controls for learner intensity, pin refresh delay, maximum pin refresh wait, minimum kills before learned pins, and live NPC update delay so users can tune the system for low-end PCs or heavy-activity zones.
- **[QuestieComms - User-Controlled Intensity]** Added Advanced-tab QuestieComms controls, including a full disable switch and live throttles for queue processing, quest-state broadcasts, and bulk sync pacing.
- **[QuestieComms - Disable Gate Fix]** Scoped the comms enable helper so the disable switch no longer calls a nil global and every send/process entry point consistently respects the setting.
- **[Arrow - Low-End Performance Controls]** Added live Arrow update throttles to reduce repeated nearest-target and coordinate work while preserving existing arrow behavior.
- **[Measured Hot Paths - Phase 3]** Landed measured optimizations on the phase 3 branch for literal localization caching, available quest redraw batching, `QuestieDB.IsDoable` batch reads, hot profile aliases, `GetTime()` hoists, NPC fallback lookup caching, and validate-cache allocation cleanup.
- **[Localization - Zero-Arg Translate Fast Path]** `_l10n:translate` now short-circuits the common no-argument case (`select("#", ...) == 0`) and returns the translation directly, skipping the `{...}` table allocation, the `tostring` coercion loop, and the `safeFormat` call. The vast majority of translation lookups pass no format arguments, so this avoids per-call garbage on a hot path. Behavior matches the existing slow path: a successful no-arg lookup already returned the raw value, and the missing/invalid-entry branches fall back to the key. Cherry-picked from phase2-lua50-sweep.

### Features

- **[Database - Export Current Zone]** Added an "Export Current Zone" button (Database tab) alongside Export Current Server / Export All Servers, so players can share just the learned data for the zone they are standing in. `QuestieLearnerExport:ExportZone(zoneId)` (defaults to the player's current `areaId`) gathers the NPCs and objects that spawn in the zone, then pulls in the items those NPCs drop and the quests they start/finish, so the exported bundle stays referentially consistent. Uses the same `QxLD` string format as the full exports, so the existing Import flow accepts it unchanged.

- **[Map - Minimap Icon Range Cutoff Up To 1000]** Raised the maximum of the "Minimap Icon Range Cutoff" slider from 200 to 1000 (yards), for players who run fully zoomed-out minimaps where quest objective spawns can be far apart. Default and minimum are unchanged.
- **[Map - Minimap Icon Fade Distance Up To 1000]** Raised the maximum of the "Minimap Icon Fade Distance" slider from 100 to 1000 (yards) to match the extended range cutoff. This prevents icons allowed by a high cutoff from becoming fully transparent just past the old 100-yard fade threshold. Changing the fade distance now refreshes minimap icon visibility immediately, like the cutoff slider.

- **[Map - Hide Repeatable/Callboard Quests Below Level 60]** (#10) Added "Hide repeatable quests below level 60" (Icons tab, off by default) which hides repeatable available `!` quests — such as the Ascension Callboard — from the map and minimap until the character reaches level 60, where they become relevant. Enforced both at draw time (`_DrawQuestIfAvailable`) and in `ShouldBeHidden`, so already-drawn pins are removed on the minimap too, and they reappear automatically on hitting 60. Only affects repeatable available quests and only when the option is enabled.

- **[Tooltip - ElvUI Style Without ElvUI]** Added "ElvUI tooltip style" (General tab, on by default) which skins Questie's tooltips — the NPC/item/object and world-map-pin tooltips plus the secondary learner tooltip — with ElvUI's transparent flat look (dark `0.06/0.06/0.06/0.8` background and a thin 1px border) even when ElvUI is not installed, so they match instead of falling back to the chunky default WoW border. `QuestieTooltips:SkinDefaultTooltips` applies it to `GameTooltip`, `WorldMapTooltip`, `ItemRefTooltip` and the shopping tooltips (re-asserted on show), and the secondary learner frame's fallback style was corrected to the same thin border. No-op when ElvUI is loaded, since ElvUI skins the frames itself.

- **[Map - Looted Object Pins Disappear On Loot]** When you open/loot a quest object node (e.g. Fell Wood piles), that specific node's map/minimap pin now disappears immediately even if the objective is not yet fully collected, instead of all node pins staying until turn-in. On `LOOT_OPENED`, `QuestieQuest:RemoveLootedObjectivePins` finds the active object-objective spawn nearest the player's world position (within ~12 yards, since you stand on the node to loot it), records it as consumed in `Questie.db.char.lootedObjectSpawns`, and redraws just that objective so clustering recomputes with the looted node skipped. `_DetermineIconsToDraw` skips consumed object spawns, so removal persists across redraws and `/reload`. The looted history is cleared on quest accept (`QuestieQuest:ClearLootedSpawns`), so abandoning and re-doing the quest — including after an Ascension prestige — shows every node again. Scoped to `object`-type objectives; monster/kill pins are unchanged. Works in every data source mode (auto / learner / static / none): the suppression is centralized in the single shared `_DetermineIconsToDraw` draw path that all redraw routes funnel through (core `UpdateQuest`, the learner's debounced `_DoFlushActiveQuestPins`, slider redraws), and it operates on the already mode-resolved `objective.spawnList`. Matching is radius-based (1.5 zone units) rather than exact-coordinate so that in learner/auto mode a spawn the learner re-adds at the player's position for the just-looted node is also suppressed instead of re-appearing.

- **[Tooltip - Data Source Attribution (Accurate)]** Re-added the "Show data source" tooltip option (General tab, off by default) that adds a `Source:` line to NPC, object, item and world-map-pin tooltips. Unlike the previous version (removed in an earlier build for guessing the source from the global data-source mode), this is accurate per-pin/per-entity and never guesses: each pin is tagged with its real provenance at creation via the new `QuestieDB.GetPinDataSource(entityType, id, spawnData)` helper — `Learner` (per-spawn `isLearned` flag or a learner record), `AscensionDB` (a curated `ascensionOverrideKeys` override for the id), `Townsfolk` (manual/menu notes), or the base `Questie DB` — with a `Comms` overlay appended when comms holds data for the entity. Objective pins are tagged per-spawn in `_DetermineIconsToDraw`; available/finisher pins are quest-scoped (defaulted in `DrawWorldIcon`); manual notes are tagged in `DrawManualIcon`. World-map pins read the per-pin tag (`MapIconTooltip`); unit/object/item hovers derive it per-id at the render layer (`TooltipHandler` via `QuestieTooltips:GetDataSourceLine`). When a pin's source genuinely can't be determined, no line is shown rather than a misleading one.

### Bug Fixes

- **[Map - Suppress Duplicate Native Quest POIs]** Rather than globally disabling the server/Blizzard objective POIs, Questie now keeps them enabled and hides only the individual Blizzard POI buttons for quests that already have a visible Questie POI (per-quest duplicate-POI suppression in `QuestieCompat`, hooked at init). Blizzard POIs still appear for quests Questie does not cover, but no longer stack on top of Questie's own objective icons.
- **[Learner - Tooltips In Auto Mode]** Learner spawn tooltips now appear in Auto data-source mode, not only in learner-only mode, so learned spawn/quest detail still surfaces on hover while Auto is selected.
- **[Prestige - Player Cache Reset]** The cached player level/race/class flags are now reset on prestige so available-quest eligibility recomputes against the new character state instead of stale pre-prestige values.
- **[Quest - Completion Cache Clear On Refresh]** Quest completion lookups are cleared on refresh so re-accepted and re-evaluated quests no longer read stale completion state.
- **[Map - Sunstrider Quest Prereq Gate]** (#8) Added the missing prereq link for `Felendren the Banished` (8335), so the quest no longer appears as available before `Aggression` (8334) is completed.
- **[Icons UI - Minimap Cutoff/Fade Suggestions]** Added short low-end and high-end recommendation text to the Minimap Icon Range Cutoff and Minimap Icon Fade Distance controls so the icon settings explain their intended starting points instead of leaving players to guess.
- **[Map - Minimap Fade No Longer Hides Icons]** (#17) Distance-based minimap fading now clamps to the configured faded-icon opacity floor instead of reaching 0 alpha. The fade distance can visually de-emphasize distant icons, but only the range cutoff can remove them from the minimap.
- **[Regression Tests - Learner Spawn And Tooltip Fallback]** Fixed the two previously failing specs: AscensionDB-owned NPC spawn overrides now keep their curated coordinates even in learner mode, preventing stale learner zones from leaking wrong-corner pins; and NPC quest-start tooltip fallback now calls `QuestieDB:GetQuest` correctly so objective summary text appears when no live objective tooltip is registered.
- **[Performance - Minimap Filter And Learner Kill Hot Paths]** (#20) Reduced two likely stutter sources introduced after 1.6.2: minimap fade passes now cache expensive quest-filter visibility checks for already-visible icons instead of re-running them every 0.1s per icon, while still forcing a fresh check before hidden icons reappear; and the learner kill path no longer runs the spawn-evidence merge scan before the merger's three-evidence minimum can succeed.
- **[Map Tooltip - Objective Progress Refresh]** (#18) Minimap and world-map objective pin tooltips now refresh the underlying objective before rendering progress text, so kill counters update on hover instead of staying at the count captured when the pin was drawn.
- **[Learner - Stop Recording Bystander Kills As Your Own]** Kills of mobs you never engaged (other players killing nearby mobs) were being recorded as spawns at *your* position and inflating the kill count. The combat-log handler passed `px,py=nil` to `LearnNPC` for uncredited kills, whose `GetPlayerCoords` fallback then stored your location as the mob's spawn. Spawn recording (`LearnNPC` + GUID evidence) is now gated on a captured position, so only credited kills (your own / party kills you engaged, where a real position was captured) store a spawn. Bystander kills no longer pollute the learner with your coordinates or inflate the count; the NPC's name/quest data is still learned via mouseover/target.
- **[Fix - Fade Pass Crash On Stale Frame]** Hardened `ShowQuestIcons`/`HideQuestIcons` against a stale-frame desync (`attempt to index local 'icon'`): a frame name lingering in the registry after its frame was reset is now skipped gracefully instead of erroring out of the whole fade pass (and `ShowQuestIcons` no longer `error()`s on the desync), with nil-guards on `icon`/`icon.data`/`icon.data.QuestData`.
- **[Fix - Tooltip Crash On Unit Hover]** Fixed a crash on every unit tooltip (`attempt to call global '_TooltipHasLeftLine'`): the dedupe helper was defined *after* `AddUnitDataToTooltip`, so that function couldn't see the local. It's now defined before all `Add*DataToTooltip` functions.
- **[Tooltip - Robust ID Resolution For Hex/Object GUIDs]** Tooltip NPC IDs are now resolved with the learner's robust GUID parser (`QuestieLearner:GetIdAndTypeFromGUID`, now public) as a fallback when the naive `strsplit("-", guid)` can't parse the GUID — e.g. legacy `0x` hex GUIDs — which previously left the NPC ID line silently unwritten. The Object ID line gained a matching fallback: when a hovered object's name isn't in the lookup, it resolves the ID from the object's GUID via the new `QuestieLearner:GetObjectIdFromGUID`. Both ID lines are also deduped per tooltip.
- **[Tooltip - ID Lines No Longer Vanish On Re-Hover]** The "Item ID" / "NPC ID" lines were only added when the hovered item/unit *changed* (`lastItemId`/`lastGuid` gate). But WoW clears and re-fires `OnTooltipSetItem`/`OnTooltipSetUnit` for the *same* item/unit, rebuilding the tooltip — and the gate skipped re-adding the line on the rebuilt tooltip, so the ID disappeared (e.g. hovering the same quest item twice). The ID lines are now (re)added on every render and deduplicated per tooltip (via `_TooltipHasLeftLine`), so they're always present exactly once.
- **[Learner - Exclude Critters & Fix Sunstrider Object Mis-Key]** Critters (Rabbit, Deer, Sheep, Cow, Cat, …) are never quest-relevant but were being recorded by the learner when killed, polluting the DB. The learner now refuses to record critters (a static list of common classic critters plus runtime detection via `UnitCreatureType` for Ascension's custom critters, flagged the moment a unit token is available on mouseover/target), purges any already-recorded critters on `InjectLearnedData` and on sight, and skips them in every learn path. Also fixed object spawns mis-stored under the Eversong parent areaID `3430` (e.g. object 180516 "Shrine of Dath'Remar", which is on Sunstrider): the migration now moves any `3430`-keyed spawn — and the matching home-zone field — to Sunstrider's uiMapID `1241`, since legitimate Eversong data is always keyed by `1941`.
- **[Learner - InjectLearnedData Was Corrupting Saved Spawns]** The real cause of learner pins collapsing to one (and the data appearing to "not persist"): `InjectLearnedData` ran on every login/redraw and **rewrote the saved learner spawns**. Its zone-key migration was inverted — it called `GetAreaIdByUiMapId(1241)`, which returns the Eversong **parent areaId 3430**, and *moved* Sunstrider's coordinates there (rendering them on the wrong map) while `InsertIfNewBucket` silently deduped distinct coords away. On top of that, `Sanitize` re-deduplicated coordinates with the flat `COORD_GRID` (2.0) instead of the per-zone grid, collapsing Sunstrider's tightly-packed spawns (its grid is 0.5). Together these turned seven saved Arcane Wraith coordinates into one pin and persisted the damage back to SavedVariables. Fixed: the migration now converts only legacy areaId keys **forward** to the canonical uiMapId (never the reverse) and leaves uiMapId keys untouched; the `[9]`/`[5]` home-zone fields are normalized the same direction; and `Sanitize` now de-dups with the correct per-zone grid. A regression test (`Tests/QuestieLearnerMultiSpawn_spec.lua`) drives `InjectLearnedData` + `GetNPC` and asserts all distinct learner spawns survive.
- **[Learner - Sunstrider Shows Every Learned Pin Again]** Learner-recorded spawns on Sunstrider Isle were being collapsed to a single pin: a prior change kept clustering enabled there in learner mode, so several distinct learned coordinates (e.g. seven Arcane Wraith spots) consolidated into one icon — breaking the DB-building workflow where every learned spawn must be visible. Sunstrider (uiMapID 1241) now shows every distinct pin by default in **all** data-source modes; consolidation only happens if the player explicitly raises the Dense Pin Clustering Aggressiveness knob. (The data was correct in SavedVariables the whole time — this was purely a display/clustering regression.)
- **[Tooltip - Collapse Stacked Ascension Quest-Progress Lines]** (#9) Tooltips could pile up a stack of progress lines for the same objective — `0/8`, `1/8`, `2/8`, `3/8` — because the Ascension server appends a new progress line on every objective update instead of replacing the old one. A new always-on pass (`DedupeAscensionProgressLines`) collapses each stack to its single most-progressed line. It only ever hides a line when the same tooltip holds another progress line with the same objective text and denominator, so it never touches other addons' tooltip lines or Questie's own single-line objectives (unit-tested). This is separate from the opt-in "Hide Ascension quest progress lines" option (#16), which removes such lines entirely.
- **[Map - Completed Quest Pins Stuck On The World Map Until Reload]** (#9) A completed quest/objective's pin could stay on the world map (while the minimap correctly cleared it) until a `/reload`. Cause: a draw-queue race. The world-map and minimap draw queues are processed independently in `ProcessQueue`, so when a frame was unloaded while still queued (e.g. an objective that completes the same tick its pins were queued), the frame's minimap-queue entry could trigger the deferred `Unload` first — removing both icons and clearing the unload flag — and then a later map-queue entry would re-add the world-map icon. Because `Unload` had already nil'd the `questIdFrames`/`_G` reference, that re-added pin was orphaned and survived until `/reload`. `Unload` now drops the frame's pending draw-queue entries (new `QuestieMap:DequeueFrameDrawCalls`), so an unloaded frame can never be re-added to a map — keeping both maps in sync.
- **[Map - Quest-Type Filters Now Truly Apply To The Minimap]** (#11) Filtered quest types (e.g. dungeon quests) could still show on the minimap while correctly hidden on the world map. The previous fix made the minimap `FadeLogic` re-check `ShouldBeHidden` only when deciding whether to *re-show* an already-hidden icon — so an icon that was already visible (or that HBD's pin renderer showed on coming into range) was never hidden. `FadeLogic` now proactively calls `ShouldBeHidden` for every in-range minimap icon and `FakeHide`s it when filtered, in both minimap fade paths (quest icons and townsfolk/manual icons). The same path also picked up the #17 minimap-radius cutoff gating it was missing.
- **[Learner - Kills Never Recorded Spawn Coordinates]** The combat-log kill handler computed the player's spawn position inside `if credited then ... end`, but `credited` was read **before** it was assigned (the `local credited = ...` came several lines later), so it was always `nil` — the position-capture block never ran. Every killed NPC was saved with `spawnSource="fallback"` and no `[7]` spawns regardless of kill count, so in learner-only mode their pins never appeared (and re-killing didn't help). Moved the `credited` computation above the position capture, and guard against a `0,0` position being stored. The learner's `GetPlayerCoords` (used by quest-giver/object learning) also now uses the robust `QuestieCompat.GetCurrentPlayerPosition()` (handles `SetMapToCurrentZone` and the Sunstrider parent/child coordinate correction) instead of the raw `GetPlayerMapPosition`, returning `nil` when no valid position exists so no `0,0` pins are recorded. Newly killed mobs now record real coordinates and their learner pins persist. **Hardening:** the kill spawn is now keyed under the same map space the coordinates were captured in (`GetCurrentPlayerPosition`'s mapId) rather than a separately-derived `GetZoneId()` that can disagree with the coordinate space on subzones; a throttled debug warning surfaces credited kills that yield no usable position; and a regression test (`Tests/QuestieLearnerKillCapture_spec.lua`) drives the real kill handler end-to-end and asserts capture, the `0,0` guard, and the per-mode display contract (learner shows the learned spawn, static never exposes learner spawns).
- **[Map - Minimap Icon Alignment At Non-1 UI Scales]** (#6) Reverted the attempted physical-pixel snapping fix and corrected the underlying minimap coordinate math instead. HBD pins already use `SetPoint` offsets in the minimap frame's coordinate space, so multiplying the minimap half-width by `GetScale()` made Questie `?`/`!` pins drift away from the native minimap quest blips whenever UI/minimap scale was not 1.0. Minimap pins now combine the live minimap view radius with unscaled `GetWidth()/2` and `GetHeight()/2`, which keeps placement resolution-independent across fractional UI scales.
- **[Map - Hide Callboard Quests: Robust Board Detection]** (#10) The "hide repeatable quests below level 60" option only hid quests flagged repeatable in the DB, but Ascension's Call Board / Contract Board bounties (e.g. NPC 24 "Outlaw's Contract Board") aren't reliably flagged repeatable, so their `!` markers still showed. Added `QuestieDB.IsBoardQuest(questId)` which detects these by their starter NPC/object name containing "board" (cached per quest), and the hide-below-60 option now hides a quest when it is repeatable **or** a board quest — closing the gap in both the available-quest draw path and the icon visibility check.
- **[Tooltip - ElvUI Style No Longer On By Default]** (#16) The "ElvUI tooltip style" option shipped enabled by default, so Questie restyled every default WoW tooltip — stripping the border — for users who never asked for it and don't run ElvUI. It is now opt-in (default off), and a one-time migration resets it off for existing installs so their default tooltips return. Users who want the flat style can re-enable it in the General tab.
- **[Quest - Turned-In Quests Misclassified As Abandoned]** (#9) On Ascension some turn-ins (notably crafting/auto-complete quests) fire `QUEST_REMOVED` without a preceding `QUEST_TURNED_IN`, so Questie's 1-second abandon timer ran `MarkQuestAsAbandoned`. By then `QuestLogCache.RemoveQuest` had already cleared the quest, so the `IsComplete` check returned 0 and the *turned-in* quest was treated as abandoned — leaving its objective pins and turn-in `?` lingering on the map and minimap. The completion state is now snapshotted at `QUEST_REMOVED` time (while the quest is still in the cache) and used by the abandon timer, so a quest that was complete at removal is correctly completed (pins/`?` cleared) rather than abandoned.
- **[Map - Minimap Range Cutoff No Longer Clips Visible Icons]** (#17) The "Minimap Icon Range Cutoff" added in a prior build hid every quest icon beyond its yard value *before* checking whether the icon was within the minimap's visible circle. Because the minimap's view radius is 133–466 yards depending on zoom, a cutoff of 100 (the default) hid icons that were clearly on the minimap — they only appeared once the player was very close. The cutoff now only clips icons that fall *outside* the minimap's visible radius: in HBD's pin renderer it is gated on `dist > 1` (outside the visible circle), and in `QuestieMap`'s minimap `FadeLogic` the effective cutoff is raised to at least the current minimap view radius (read from the new `HBDPins:GetMinimapRadius()`). Icons within the visible minimap always show again; the cutoff still controls how far edge-floating icons reach for far-apart objectives when zoomed out.
- **[Tooltip - Ascension Quest-Line Stripping Now Opt-In]** (#16) `HideAscensionQuestLines` ran on every tooltip and removed any line matching a quest-objective pattern (`N/M`, `[N] ...`), which also stripped legitimate lines added by other tooltip addons (durability, stack counts, etc.) — so Questie still "aggressively overrode" tooltips even with the ElvUI style off. It is now gated behind a new General-tab option, **"Hide Ascension quest progress lines"** (default off), so by default Questie no longer modifies tooltip lines it doesn't own. Ascension users who want the server-injected quest-progress spam hidden can enable it.
- **[Tooltip - Stop Eating ID Lines & Other Addons' Tooltip Text]** `HideAscensionQuestLines` (which hides Ascension's injected quest-objective progress text from tooltips) was too greedy: once it found an objective line (e.g. `0/8 Arcane Wraith slain`) it kept hiding every following non-indented line until an indented one. Because Questie's own `Item ID`/`NPC ID`/`Object ID` lines and other addons' additions (e.g. an item-count overlay) are appended at the *bottom* of the tooltip — after the objective block — a refresh pass wiped them too, so the ID you needed to report data never showed. It now hides only the lines that themselves match an Ascension objective pattern (`N/M`, `[N] ...`, `- N/M ...`) and never the trailing lines, so IDs and other addons' text are left intact.
- **[Learner - Don't Purge NPCs With Useful State But No Spawns]** The `InjectLearnedData` purge loop was deleting entire NPC entries from `Questie.dbLearner.global.npcs` whenever `data[7]` (spawns) was empty, even if the entry still had a name, home zone, recorded kills, or quest references. This caused learner data to silently disappear on `/reload` for NPCs that had been learned but never killed in a position the learner could record (e.g. party-kill position attribution fix now passes nil coords for uncredited kills). Now only purges when ALL of name, zone, kills, and quest references are missing. Entries with other useful state get `data[7] = nil` instead so the row survives.
- **[Learner - Import Shows Actual Spawn Coordinates Added]** The import completion message now shows how many spawn *coordinates* were really added (e.g. "Added 842 new spawn coordinates") rather than just entry counts. Counts `[7]` for NPCs and `[4]` for objects before and after the merge. A sparse export that merges entries but carries no coords means nothing new will appear on the map — the new message makes this clear.
- **[Learner - Import Updates Map & Stats Live (No Reload)]** After importing learned data, the Database tab's live entry counts now update immediately and the imported spawns appear on the map/minimap without a `/reload`. `MergeImport` now runs `QuestieQuest:SmoothReset()` (guarded) after `InjectLearnedData` so freshly merged NPC/object spawns are recalculated and redrawn, and the import dialog fires `AceConfigRegistry:NotifyChange("Questie")` so the "Total entries" stats refresh in place. Also hardened the import against pathological payloads — `ValidateImport` rejects strings claiming more than 200,000 entries before the synchronous merge runs — and the shared serialize/encode step is now wrapped defensively so a malformed sub-entry surfaces as a clean error instead of a Lua error.
- **[Learner - Robust Safety Fallbacks For All Types]** Hardened the learner's data-ingestion paths against malformed/partial data for every learner type (NPC/object/item/quest). The spawn validator now checks object spawn coordinates (key `[4]`) in addition to NPC spawns (key `[7]`) — previously object coords were unvalidated. The incoming-data merge skips malformed zone keys and coordinates (non-number/out-of-range) per entry instead of erroring, and guards the item drop-list merge against non-number NPC ids. The live comms-merge flush now isolates each broadcast in a `pcall`, so a single malformed entry can't abort the batch or break the live-update loop, and the post-merge `InjectLearnedData` is likewise guarded.
- **[Learner - Hardened Import/Merge For Multi-Player Data]** Importing learned data merged from several different players is now safe and clean. Fixed a prefix-validation bug in `ValidateImport` (`not str:sub(...) == x` parsed as `(not str:sub(...)) == x`, always false, so non-Questie strings were never rejected). `MergeImport` now: ensures the learner stores exist (so a fresh profile can import), merges each entry **synchronously and defensively** via `_ApplyIncomingNetworkMerge` (which validates key/coordinate structure and only adopts fields the local store is missing — never overwriting good local data), isolates every entry in a `pcall` so one corrupt entry is skipped/counted instead of aborting the import or corrupting the store, and reports accurate `merged / skipped / rejected` counts. Merging synchronously also fixes `InjectLearnedData` previously running before the queued merges landed.
- **[Quest - Turn-In '?' Missing For Quests In The Log]** A quest in the player's log is active and not yet turned in, so its turn-in `?` finisher should always be drawable — but `AddFinisher` also required `not char.complete[questId]`, so a quest completed in a previous Ascension prestige (still flagged in `char.complete`) and then re-accepted had its finisher suppressed while standing at the turn-in NPC. `AddFinisher` now trusts the live quest log: if the quest is in `currentQuestlog` and not failed, the finisher draws regardless of the (possibly stale) completed flag. No quest-completion data is modified.
- **[Learner - Turn-In/Quest NPC Not Learned When Targeted]** In learner mode the turn-in NPC's location wasn't always recorded, so its `?` finisher couldn't draw. `OnTargetChanged` only cached the GUID and never called `LearnNPC`; it now learns the spawn of quest-giver/turn-in NPCs (gated like `OnMouseoverUnit`), so simply targeting a turn-in NPC records its position. The `QUEST_COMPLETE`/`QUEST_TURNED_IN` handlers also fall back to the `target` unit when the `npc` gossip unit is already cleared, so the finisher NPC is reliably learned on turn-in.
- **[Map - Completed Quests Still Shown As Available]** (#7) The server's completed-quest list is delivered asynchronously (the `QUEST_QUERY_COMPLETE` event), often after available quests were first drawn — so quests that were actually already complete kept showing as available `!` until something forced a redraw (e.g. `/reload`). Questie now recalculates available quests once `char.complete` is populated by that event, removing the completed ones. This also clears the "already completed" subset of the false-available pins reported in #8.
- **[Map - Available '!' Lingered On Minimap For Accepted Quests]** (#9) When a quest was accepted, its available `!` icon could remain on the minimap until a `/reload`. `QuestieMap:UnloadQuestFramesByDataType` unloaded the frame but left its name in the frame registry and `_G`, so the minimap icon was not fully torn down. It now removes the registry/global reference as well, so the available icon is cleared immediately on accept for both the map and minimap.

- **[Tooltip - Data Source In Secondary Tooltip Only]** The `Source:` attribution line now appears only inside the secondary learner tooltip (when "Use secondary learner tooltip" is enabled) and is never added to the main NPC/object/item tooltip; with the secondary tooltip disabled it does not appear at all. The map-pin source line is gated the same way. The "Show data source" option now depends on the secondary-tooltip option being enabled.
- **[Tooltip - Learner Pin Mislabelled As AscensionDB]** A spawn freshly learned via the learner was shown as `Source: AscensionDB` instead of `Learner`. `QuestieDB.GetPinDataSource` resolved AscensionDB-curated ownership before checking the learner, but in learner-only mode the displayed spawns are the learner's (curated coords are discarded by `GetNPC`/`GetObject`). It is now mode-aware: in learner mode, an entity with a learner record reports `Learner` even when AscensionDB also curates it.
- **[Learner - Learner-Only Mode No Longer Draws AscensionDB/Static Pins]** In learner-only mode the map/minimap drew curated AscensionDB (and static) spawns for every quest NPC/object the player had not personally recorded, instead of only the learner's own spawns. `QuestieDB:GetNPC`/`GetObject` fall back to the `npcDataOverrides`/`objectDataOverrides` entry for metadata when there is no learner record, and that entry's spawns (AscensionDB-curated for un-recorded entities) were being used as pins. Both functions now track whether a real learner record exists and, in learner mode, strip the spawns when it does not — so learner-only mode shows exclusively what the learner has recorded (the metadata fallback for names/tooltips is kept). Added a regression test. Recorded entities still show their learner spawns; auto/static/none modes are unchanged.
- **[Map - Quest Type Filters Now Apply To Minimap]** (#11) Quest-type filters (Available Dungeon/Raid/PvP/Repeatable/Event Quests, plus other `ShouldBeHidden` rules like untracked/unexplored and `enableMiniMapIcons`) were honored on the world map but not the minimap. The world-map icon stayed hidden once `ShouldBeHidden` filtered it, but the minimap icon's per-frame `FadeLogic` re-showed any hidden icon as soon as the player came within range, so e.g. a filtered dungeon quest still appeared on the minimap. `FadeLogic` now re-checks `ShouldBeHidden` before re-showing, so the same filters apply to both maps (fixed in both the world-icon and manual-icon minimap fade paths). Dungeon detection is also hardened now: when the quest tag is missing, Questie falls back to quest zone/sort data and dungeon-only starter spawns so missing quest-key flags do not leak dungeon quests back onto the minimap.
- **[Libs/AceComm - Long Comm Prefix Login Error]** (#12) Fixed a recurring login Lua error `AceComm:RegisterComm(...): prefix length is limited to 16 characters` on servers like ChromieCraft. The cause is a third-party addon (e.g. AtlasLoot) registering an AceComm prefix longer than the client's 16-character limit; because Questie's bundled AceComm is the LibStub winner and its `xpcall` polyfill wraps AceAddon's `OnEnable`, the upstream hard `error()` surfaced through Questie's frames every login. Our bundled `AceComm:RegisterComm` now degrades gracefully for over-long prefixes (which can never work on the client anyway): it warns once and skips the registration instead of throwing, so the offending addon's `OnEnable` is no longer aborted and the error popup is gone.
- **[Tracker - VoiceOver questPlayButtons Nil Crash]** (#15) Fixed `attempt to index field 'questPlayButtons' (a nil value)` in `TrackerUtils:UpdateVoiceOverPlayButtons` and `TrackerLinePool.SetAllPlayButtonAlpha`. `TrackerUtils:IsVoiceOverLoaded` only checked that the VoiceOver addons were loaded, but some VoiceOver builds (seen on Elune) expose a `QuestOverlayUI` without a `questPlayButtons` table. It now also verifies `VoiceOver.QuestOverlayUI.questPlayButtons` exists; since every play-button call site gates on this function, the integration is now safely skipped instead of crashing on those builds.
- **[Libs/AceGUI - Tree Tooltip Nil Crash]** (#15) Hardened `AceGUIContainer-TreeGroup` against `attempt to index ... 'tooltip' (a nil value)` when a conflicting addon registers a broken `AceGUI-3.0` core (observed in the wild as version `1.#INF`) that wins LibStub but never creates the shared `AceGUI.tooltip` frame. The tree button enter/leave handlers now lazily (re)create the tooltip frame; the widget version was bumped 47→48 so the fixed widget wins registration over an unpatched same-version copy.
- **[Tooltip - Learner Spawn Data Never In Main Tooltip]** Learner spawn/kill data is no longer added inline to the main NPC tooltip under any setting. Previously, with the "Use secondary learner tooltip" option off, `_AddLearnedSpawnTooltipLine` appended the lines directly to `GameTooltip`. The toggle now gates the data entirely: on = shown in the separate secondary frame, off = not shown anywhere. Removed the now-unused `_AddTooltipSeparator` helper and updated the option description. (Complements the earlier System A suppression that kept the duplicate learner lines out of the main tooltip.)
- **[Tooltip - Stale Quest Objective Lookup On Turn-In]** Hovering an NPC right after turning in (or abandoning) one of its associated quests spammed a `debugstack` trace in DEVELOP mode: the learner objective-correlation block in `QuestieTooltips:GetTooltip` called `QuestLogCache.GetQuestObjectives` for a quest no longer in `QuestLogCache` (gracefully returns `{}`, but logs a stack). The NPC and object correlation loops now skip quests not in `QuestiePlayer.currentQuestlog`, so live objective progress is only looked up for quests the player is currently on. No functional change for active quests (a completed quest had no progress to show anyway).
- **[Tooltip - Secondary Learner Tooltip Leak]** With the "Use secondary learner tooltip" option enabled, learner spawn/kill lines still appeared in the main NPC tooltip instead of going solely to the secondary frame. Two parallel learner-tooltip systems were both rendering on unit hover: QuestieLearner's `OnTooltipSetUnit` hook (toggle-aware, secondary-capable) and `Tooltip.lua`'s `_GetLearnerTooltipLines` (always injected "Learned spawn / Total spawns learned / Total kills recorded" into the `m_<npcId>` tooltip data). `QuestieTooltips:GetTooltip` now takes a `suppressLearnerLines` flag, and the NPC unit-hover call in `TooltipHandler.lua` passes it so the inline learner lines are omitted there — the `OnTooltipSetUnit` hook owns that display and routes it to the main tooltip (secondary off) or the separate secondary frame (secondary on). Map-pin and object tooltips are unaffected and keep their learner lines. Also removes the latent duplicate learner lines that appeared in the main tooltip even with the secondary frame disabled.
- **[Map - Completed Objective Pins Linger]** Added `QuestieMap:UnloadQuestFramesForObjective(questId, objectiveIndex)` and call it from every completion path in `QuestieQuest:PopulateObjective` (objective completed, hidden by `ShouldHideObjective`, and static no-`Update` objectives). Previously, removing a completed objective's map/minimap pins relied solely on `_UnloadAlreadySpawnedIcons`, which walks `objective.AlreadySpawned`. That table desyncs from the frames actually on screen after learner spawn-list invalidation or complete→abandon→reaccept cycles, so when it was reset to `{}` the live frames leaked and pins for fully-completed objectives (e.g. 6/6 kills, a collected item objective) stayed on the map even though tooltips updated correctly. The new function unloads frames deterministically off the map's own `questIdFrames` registry by matching `frame.data.ObjectiveIndex`, so completed-objective pins are removed regardless of `AlreadySpawned` state. Restricted to positive standard-objective indices; SpecialObjectives (sentinel index 0) keep using `AlreadySpawned` to avoid cross-unloading siblings.
- **[QuestieLib - GetColoredQuestName Nil Guard]** Added a nil guard in `QuestieLib:GetColoredQuestName` so a synthetic `questId` (e.g. one used in a chat link on servers that do not have a real quest entry) no longer crashes with `attempt to index a nil value`. The function now checks `QuestieDB.GetQuest(questId)` before reading its `isComplete` flag.
- **[Tooltip - Item Flicker on ElvUI Refresh]** Simplified the `AddItemDataToTooltip` redraw check to key purely on `itemId`. The previous condition also re-keyed on tooltip name, line count, and frame name — all of which ElvUI's tooltip-frame recycling transiently resets, so every refresh cycle looked like a new item and caused Questie's lines to flicker repeatedly. The new condition only re-adds when the actual itemId changes, so the tooltip stays stable across ElvUI's refresh ticks.
- **[Tooltip - First-Hover Resize Pop]** Removed the unconditional `QuestieTooltips:ResizeTooltip(self)` call from `AddItemDataToTooltip`. With the flicker fix in place, the resize pass still fired once per item hover and triggered ElvUI's smooth-resize animation, causing a visible frame pop on first hover. ElvUI already manages tooltip sizing correctly, so the Questie resize call is no longer needed for item tooltips.
- **[QuestieLearner - Quest Detail Field Mapping]** Fixed three quest-field index bugs in `OnQuestDetail` / `OnQuestAccepted` that were silently corrupting learner `questDataOverrides`. The detail handler was writing the objectives text into `data[6]` (the `requiredRaces` bitmask field), the quest body into `data[17]` (the `zoneOrSort` field), and the current zone areaId into `data[8]` (the `objectivesText` table field). Each write permanently blocked the correct value for that field because `LearnQuest` only writes nil keys. The detail handler now only writes `name` and `zoneOrSort`, and the accepted handler is annotated to make the schema restrictions explicit so future fields are not added by guess.
- **[QuestieLearner - Accepted Handler Reducer]** Collapsed a redundant second pass over the quest log in `OnQuestAccepted` that was about to introduce a `local logIdx = 0` redeclaration. The index found while building the data table is now reused for the subsequent objective-mapping scan instead of being re-derived from scratch.
- **[Tooltip - Item ID Always Shown]** `AddItemDataToTooltip` previously gated the "Item ID" line on the item having a registered quest-objective tooltip — for items that are not part of any quest objective (e.g. trade goods, vendor trash, quest-start items with no other Questie data attached), the option to show IDs had no visible effect. The line is now added for every item hover when the option is enabled, mirroring the NPC/Object tooltip behavior. Also switched the call to `self:AddDoubleLine` so the ID lands on the actual frame that fired `OnTooltipSetItem` (which can be `ItemRefTooltip` for chat links, not just `GameTooltip`).
- **[Tooltip - Item Starts Quest]** Item tooltips now surface a "Drops a quest !" line with the quest title when the item has a non-zero `startQuest` value in the static DB / Ascension override table and the player does not already have the quest (active or turned in). The item→quest relationship is a build-time DB field — we never know it ahead of runtime observation — so it is read directly from `QueryItemSingle` at hover time. The line uses `QuestieLib:GetColoredQuestName` so the quest title respects the same level/complete state formatting the rest of Questie uses.
- **[QuestieDB - Auto Mode Learner Enrichment]** In `auto` data-source mode, `QuestieDB.GetQuest` now overlays the SavedVariables learner payload on top of the static DB record, filling only fields the static record leaves `nil` and deep-merging `objectives`/`objIndex`. This fixes quests like 8325 where the shipped DB carries only a stub record but QuestieLearner holds the real objective mapping — previously the stub blocked the learned objectives from ever surfacing. Learner data never clobbers a present static value, so it strictly enriches and cannot regress shipped data.
- **[QuestieLearner - Accept-Time Objective Pin Seeding]** `OnQuestAccepted` now seeds objective pins directly from the SavedVariables learner payload (`objIndex`) the moment a quest is accepted in learner mode, instead of waiting for quest-log text sync. This makes quests like 8325 spawn pins immediately on accept when the objective mapping already exists. The accept-time ID lookup was also widened from `killcredit` to also cover `monster` objectives, and now falls back to `objData.Id` when no `IdList` is present, catching cases where the quest-log text does not normalize cleanly to the NPC name.
- **[QuestieLearner - Persisted Spawn Restore on Load]** `InjectLearnedData` stripped each learned NPC's spawn field (`[7]`) when injecting into `QuestieDB.npcDataOverrides`, deferring to `_MergeSpawnEvidence`. But that promoter only runs on **live kill evidence**, so spawns learned in a prior session never returned to the queryable DB on `/reload` — pins for a freshly accepted quest (e.g. 8325 → Mana Wyrm 15274 on Sunstrider) stayed missing until the player re-killed the mob. The saved spawns are now restored into the override at injection time under their **native uiMapId keys**, captured from a snapshot taken *before* the internal uiMapId→areaId migration runs. This matches exactly what the live kill path stores (e.g. Sunstrider `1241`), so pins render on the correct map and HBD `isSameZoneSpace` shows them on the Eversong map too. The restore deliberately does **not** convert keys through areaId — uiMapId `1241` resolves to the Eversong parent areaId `3430` → Eversong map `1941`, which had been placing Sunstrider pins in the wrong (NE) corner. Gated by `IsAscensionProtected` so curated AscensionDB coords are never overwritten (always restored in learner mode; in auto mode only non-curated NPCs). Regression introduced by commit `7ce0cdc`.
- **[QuestieLearner - AscensionDB Spawn Deference (Sunstrider pin placement)]** For NPCs whose spawn data AscensionDB hand-curates (e.g. Sunstrider's Mana Wyrm 15274 on quest 8325), the learner now **defers entirely** to the curated coords instead of mixing in its own — even in learner mode. The learner's Sunstrider coordinates are frequently stored under the wrong map/zone (a kill mis-recorded under zone `1445` rendered as a pin in the NE corner of the map), and `_MergeOverride` deep-merges spawn tables, so in learner mode (where `rawdata` is the learner record) those bad zones survived because AscensionDB had no matching entry to displace them. Fixes: (1) `QuestieDB.GetNPC` now uses the curated override spawns **only** for AscensionDB-owned NPCs, discarding merged learner zones; (2) `InjectLearnedData`'s spawn restore and (3) `_MergeSpawnEvidence`'s Sunstrider guard both use a new mode-independent `AscensionOwnsNpcSpawns()` check instead of `IsAscensionProtected()` (which returns false in learner mode). This restores the protection commit `e80a008` documented and commit `0f20ea8` had silently bypassed with a `(not learnerLiveMode)` condition.
- **[Options - Tab Table Vararg Typo]** Five Options files initialized their tab tables with `{ ... }` instead of `{}` (`QuestieOptions.tabs` plus the Arrow, General, Keybinds, and Tracker tabs). At chunk scope WoW passes `...` = `(addonName, addonTable)`, so each table was seeded with two stray junk entries (`[1]="Questie"`, `[2]=<addonTable>`) instead of being empty, and the `{ ... }` expression is also a hard parse error under strict Lua 5.0. Changed all five to `{}`.

### Bug Fixes (2026-06-09)

- **[QuestieLearner - Learner-Only Spawn Isolation]** Fixed learner-only mode showing AscensionDB-curated coords instead of learner data. `GetNPC` now discards `npcDataOverrides` in learner mode (where `_Asc_MergeInto` had written curated coords), returning only the learner record. Three-mode spawn-merge semantics: learner uses learner data exclusively, auto fills gaps with learner while protecting curated spawns, static uses base DB only. Also hardened the object-spawn live-injection path with the same three-mode pattern using a new `AscensionOwnsObjectSpawns()` helper. Removed the `allowSpawnMerge` bypass that was the original hole letting learner coords leak into curated spawns in auto mode.
- **[QuestieLearner - Kill Position Attribution]** Fixed the learner recording the local player's position for other players' kills. `OnCombatLogEvent` now only calls `GetCurrentPlayerPosition()` for credited kills (your own kills or mobs you damaged within 60 seconds). Non-credited party/raid kills still update the NPC's learned name and zone but no longer pollute the spawn map with the wrong coordinates.
- **[QuestieLearner - Area 52 Compat]** Fixed `HasQuestReferences` crashing with `attempt to index local 'entry' (a number value)` on Area 52. Some quest records store `qData[2][3]` as a flat number instead of a table-of-tables; the inner loop now normalizes with a type check before comparing.
- **[Tooltip - Learner Spawn Data in Tooltips]** Added learner spawn data to NPC tooltips: learned spawn position (from the most-visited GUID), total distinct spawns learned, and total kills recorded. Shown on both unit hover tooltips (via `Tooltip.lua`) and world-map pin tooltips (via `MapIconTooltip.lua`). The old `Source:` attribution line was removed since per-pin provenance tracking would require changing every spawn registration site; the learner data lines are factual (they show what was recorded) rather than attributing a source.

### Tooltip

- **[Tooltip - Data Source Attribution Line]** Objective tooltips and world-map icon tooltips now append a greyed-out `Source:` line listing where the data came from — `Static DB` or `Learner` depending on the active data-source mode, plus `Comms` when remote player data exists for that key. This makes it clear at a glance whether a pin/objective is backed by the shipped database, runtime-learned evidence, or another player's broadcast. The objective-tooltip path also corrects an internal `QuestieDB:GetQuest` colon call to the dot form `QuestieDB.GetQuest`.
- **[QuestieLearner - Secondary Tooltip Style Match]** The optional secondary learner tooltip frame is now styled to match the standard GameTooltip whether or not ElvUI is installed. When ElvUI is loaded, the frame defers to `ElvUI:GetModule("Tooltip"):SetStyle(frame)` so the user's configured colors and fonts take effect. When ElvUI is absent, the frame applies a hard-coded replica of ElvUI's default "Transparent" template (backdrop color `0.06, 0.06, 0.06, 0.8`, black 1px border, `FRIZQT__.TTF` 12px, 3px insets, 12px edge) using the standard GameTooltip textures. The skin is re-applied on every `OnShow` so the frame stays consistent if ElvUI loads late or its settings change.
- **[QuestieLearner - Combined Tooltip Spacing]** When the secondary learner tooltip is disabled and learner stats are appended directly to the active GameTooltip, the learner section is now framed by an invisible spacer line above and below. This keeps NPC/quest data above and any other-addon data below from being visually crammed against the learner counts, while adding no new texture or color assets.

- **[QuestieDB - Required Source Item Guard]** Fixed a fresh-load crash in `QuestieDB.GetQuest()` where quests that had `requiredSourceItems` but no `objectives` table would dereference `objectives[3]` while building `SpecialObjectives`. This was a code-side nil guard bug on our end, not a saved-variable problem, and it is now covered by a regression test.
- **[QuestieLearner - Learner Sunstrider Clustering]** Relaxed the Sunstrider Isle clustering override in learner mode so the clustering/deduplication knobs can still consolidate newly learned pins there. Static/auto keeps the original Sunstrider visibility behavior, but learner mode now preserves clustering so nearby learner spawns do not render as an unbounded fan-out of separate icons.
- **[QuestieLearner - Turn-In Arrow Spawn Promotion]** Allowed quest-related NPC and object spawns to keep their live learner coordinates even when the static database marks those spawn fields as protected. Learner mode now merges the learner's live override tables back into the getter path too, so quest giver and turn-in locations can point from learner-discovered hand-in targets without relaxing protection for unrelated world spawns.
- **[QuestieLearner - Quest-Only Item Learning]** Hardened item learning so plain junk loot no longer gets recorded as learner state. Only quest-relevant items are accepted now, including items that already have quest references in learned quest data. Quest-item drops still learn and still build source pins, but non-quest loot like generic trade goods and junk no longer pollutes the item learner or source cache.
- **[QuestieLearner - Quest-Only Object Learning]** Hardened object learning so non-quest world objects are ignored unless they are explicitly tied to a quest flow. Quest giver, turn-in, objective, and `GAMEOBJECT_USED` promotions now mark the object as quest-relevant before it is stored, and learned object coordinates are only promoted into live object overrides when the object has quest references. This keeps source pins for real quest objects while preventing unrelated world objects from being recorded.
- **[QuestieLearner - Quest Object Coordinate Promotion]** When a quest-related object is learned, the learner now preserves the actual interaction coordinates when available instead of relying only on fallback player position. Object objective mapping now reuses the recent object evidence cache so the stored spawn point matches the real interaction location and can render immediately as a map pin.
- **[QuestieLearner - Source Merge Hardening]** Incoming ITEM and OBJECT network merges now reject non-quest data unless the payload is already marked quest-relevant or the local quest graph proves a quest reference exists. This prevents comms-fed junk loot or unrelated objects from reappearing after the local learner gate has filtered them out.
- **[QuestieLearner - Source Pin Cache Hygiene]** Updated learner cache invalidation and live override injection so quest-item and quest-object updates clear stale caches and rebuild the source pin data immediately instead of waiting for a reload.
- **[Error Suppression - Debug Modes]** Moved missing quest and other non-fatal database/error spam out of normal chat output and into Questie debug-critical/developer output. Fatal startup failures remain loud.
- **[Tooltip Data Precedence]** Updated tooltip handling so QuestieLearner defers to AscensionDB-owned tooltip/objective data instead of hiding or replacing server-plugin data for active quests.
- **[QuestieQuest - Unavailable Quest Guard]** Guarded the available-quest draw thread so unresolved quest IDs are skipped safely instead of crashing the thread, and deduped the skip log so the same missing quest does not spam every redraw.
- **[QuestieLearner - Data Source Mode Cohesion]** Reworked the Auto / Learner / Static / Neither data-source modes so switching between them applies live and consistently. A single missing static sub-table (npc/object/quest/item) no longer locks the whole addon into learner mode — only the genuinely-missing store falls back. Static and Neither no longer silently fall back to learner records, switching modes now clears the per-zone quest cache, and the mode switch drives a full pin/tracker redraw through `QuestieQuest:SmoothReset()` (the previous redraw call imported a mis-named module and silently did nothing).
- **[QuestieLearner - Pin Refresh Latency]** Collapsed a redundant second debounce stage on the live-learn pin-refresh path. Newly learned spawns now redraw within a single debounce window instead of waiting out both the NPC live-update delay and a separate pin-refresh delay, roughly halving perceived pin-update latency in the Balanced and Low presets. Also fixed a latent infinite timer re-arm that could occur once the pin flush was triggered directly.
- **[Map - Dense Pin Clustering Aggressiveness Knob]** Re-implemented density-adaptive clustering for crowded kill objectives, now controlled by a new "Dense pin clustering aggressiveness" slider on the Advanced tab (0 = show every pin, higher = tighter consolidation where many pins share a zone). Coincident pins are always deduplicated regardless of the clustering settings, and the intentional per-zone (Sunstrider Isle) and object-icon range overrides are preserved.
- **[QuestieLearner - One Pin Per Spawn, Not Per Kill]** Fixed learner kill evidence rendering a separate pin for every kill. Because kill coordinates are the player's position at kill time (and respawns carry fresh GUIDs), repeated kills at the same spot drifted just enough to dodge the exact-match dedup. The immediate learner-mode spawn builder now merges evidence within a small radius into one pin per physical spawn, and the weighted spawn-evidence merge groups kills by coordinate bucket so a single spot can actually accumulate enough evidence to clear the confidence threshold. The merge distance is exposed as a new "Spawn Pin Dedup Radius" slider on the Advanced tab (0 = show every distinct position, higher = fewer/tighter pins per spawn) which redraws live.

### Branch / Release Notes

- The most complete performance candidate is not yet a single branch: `questie-learner-comms-improvements` has the latest learner/comms/arrow controls, while `phase3-measured-perf` has the broader measured hot-path changes.
- Before release, merge into a dedicated integration branch, remove or revalidate the stale `QuestieMap.ProcessQueue` profile-local commit that was reverted on `main`, fix the unrelated Arrow asset test expectation mismatch, and validate in game with minimap open, nearby-player kills, looting, comms toggles, Arrow throttles, and learner-only/static-only mode switching.

## [1.6.3]

### Bug Fixes

- **[Docs - Release Metadata Sync]** Updated the README badge, documentation version badges, and in-game addon version to `v1.6.3`, then tightened the release filters so handoff notes, local dev settings, and other workspace-only artifacts stay out of the exported release archive.
- **[Docs — Minimap Range Cutoff]** Documented the new minimap icon range cutoff slider and its real-time refresh behavior so the published release notes match the current UI and runtime behavior.
- **[Fix - Debug-Only Error Policy]** Routed non-fatal addon errors through `Questie:Debug(Questie.DEBUG_CRITICAL, ...)` so normal play no longer gets spammed by red chat errors, while the small set of startup-breaking conditions still uses a separate fatal path.
- **[Fix - Arrow Asset Regression]** Restored the default `Arrow1` asset from the original `XPArrow4.png` source, renamed the bundled image arrows to `Arrow1` through `Arrow4`, regenerated the bundled arrow manifest from the actual image data, and added a busted regression test so `arrowold` remains the only bundled sprite sheet.
- **[Fix - Arrow UI / Attachment Redesign]** Reworked the Arrow tab so the arrow and objective text can be detached, reattached, locked independently, and reset independently. Added an attached-gap slider, objective transparency slider, distance-unit selector, larger font sizing, and drop-in preview support for the generated arrow swatches.
- **[Fix - Arrow Asset Size Reduction]** Rewrote the bundled image arrows to their visible bounds and saved them with TGA RLE compression, which keeps the same in-game appearance while reducing the arrow asset footprint dramatically.
- **[Fix - Arrow Texture Cache Bust]** Moved the default Arrow style onto the fresh `Icons\\Arrows\\Arrow1.tga` texture path so WoW stops reusing the old sheet data under the original filename.
- **[Fix - Arrow Live Texture Fallback]** Routed bundled image arrow rendering through the generated preview textures at runtime so image-based styles stay stable even if a source TGA has odd client-side rendering behavior. The sheet arrow remains on `arrowold` only.
- **[Fix - Arrow Sheet Guardrail]** Hardened the runtime arrow renderer so only `arrowold` and explicitly custom sheet uploads can enter sprite-sheet mode. All bundled image arrows are now forced down the image/rotation path even if an asset manifest entry gets out of sync.
- **[Fix — Minimap Pin Drift: Live View-Radius API + Corrected Pixel Math]** Resolved the long-running minimap pin drift bug where quest pins appeared to "follow" the player or jump on every frame. This one took three weeks of iteration, including three false starts and one regression, before the live API path and pixel math finally lined up. Pins now stay anchored to their world positions across all minimap zoom levels (0-5+) and across both Stock UI and ElvUI.
  - **Root Cause 1 — Hardcoded lookup table used on 3.3.5a**: `Compat/HBD.lua` was reading `mapRadius` from a hardcoded `minimap_size` lookup table calibrated for stock WoW zoom levels. The API check `C_Minimap and C_Minimap.GetViewRadius` evaluated to `nil` on 3.3.5a (and Ascension), so the broken lookup table was always used. The lookup value `minimap_size.outdoor[5] = 250` produced `mapRadius = 125`, but the actual live minimap view radius at zoom 5 is `116.67` yards (from `Minimap:GetViewRadius()`). This 6.7% error compounded across all pin offsets.
  - **Root Cause 2 — Factor-of-2 in pixel math**: `minimapWidth` was computed as `(GetWidth() * mapRadius / 155.52) / 2`, mixing pixel-half-width with a yards-based scale factor. The `/ 155.52` constant was a hardcoded normalization that did not match the live API value. The math was self-inconsistent: ratio `minimapWidth / mapRadius` was `0.56` (off by ~7% from the correct `0.6`).
  - **Root Cause 3 — Scale not applied to pixel dimensions**: `minimapWidth` was based on `GetWidth()` alone, ignoring `GetScale()`. When UI scale changed, the pixel dimensions reported by `GetWidth()` would diverge from the actual on-screen size, while `mapRadius` (in yards) stayed fixed. This caused drift to worsen at higher zoom levels where the ratio was most sensitive.
  - **Fix (`Compat/HBD.lua` lines 337-339)**: Changed the radius API detection to use the 3.3.5a-native `Minimap:GetViewRadius()` (instance method), with `C_Minimap.GetViewRadius` as secondary fallback. The new line:
    ```lua
    local MinimapRadiusAPI = (C_Minimap and C_Minimap.GetViewRadius) or Minimap.GetViewRadius
    ```
  - **Fix (`Compat/HBD.lua` line 528 and line 639)**: Replaced `C_Minimap.GetViewRadius()` with `MinimapRadiusAPI(Minimap)` in both call sites, so the live API is invoked through the resolved function reference.
  - **Fix (`Compat/HBD.lua` lines 536-540 and lines 653-656)**: Replaced the `minimapWidth = (GetWidth() / 2) * (mapRadius / 155.52)` formula with `minimapWidth = GetWidth() * GetScale() / 2`. The new formula yields the actual half-width of the visible minimap in screen pixels, which is the correct multiplier for `diffX * minimapWidth` when `diffX` is normalized by `mapRadius` (yards in viewport).
  - **Fix (debug code preserved as comments)**: All `QDMATH` / `UPDATE entering` / `ICON` debug prints and `_G.QuestieDebugPinMath` global state in `Compat/HBD.lua` are now wrapped in `--[[ DEBUG: ... --]]` block comments. The drift bug is fixed; debug output is silent in production. The commented-out blocks are preserved for future regression investigation — to re-enable, remove the `--[[` and `--]]` markers and reload.
  - **Verification**: Live `Minimap:GetViewRadius()` returns `116.67` at zoom 5. `minimapWidth = 70` (from `GetWidth()=140 * GetScale()=1.0 / 2`). `diffX * minimapWidth / mapRadius` = `diffX * 0.6`, matching the expected 0.6 pixels-per-yard scaling. Pins now stay anchored to their world positions as the player moves; the per-frame `diffX` of ~0.35 yards during walking translates to ~0.21 pixels of pin movement per frame (correct for 1 yard of world movement).

- **[Fix — Sunstrider Isle: 5 Mana Wyrm Pins Now Show Correctly]** Resolved two interacting bugs that caused only 2 pins (instead of 5) to appear for the "Slay Mana Wyrm" kill objective on Sunstrider Isle, and caused pin data to corrupt on subsequent mob kills.

  - **Root Cause 1 — Learner bypassed AscensionDB protection in isSunstrider block**: `_MergeSpawnEvidence` in `QuestieLearner.lua` had an `isSunstrider` special case (lines 1106–1134) that wrote learner kill-evidence coords directly to `npcDataOverrides[npcId][7][3431]` WITHOUT checking `IsAscensionProtected`. This is the same bypass guard that the live-injection path (line 864) correctly checks. The result: after AscensionDB injected 5 clean coords at zone 1241, each kill event added zone 3431 learner coords that competed with (or replaced) the AscensionDB data, leaving `dbSpawns={z3431=2}` instead of `{z1241=5}`.
    - **Fix (`QuestieLearner.lua`)**: Added `if IsAscensionProtected("NPC", npcId, 7) then return false end` at the top of the isSunstrider block. AscensionDB-owned NPCs are now completely immune to learner injection in this path.
    - **REGRESSION WARNING**: Removing or disabling the `IsAscensionProtected` guard in `_MergeSpawnEvidence` will immediately reintroduce z3431 data pollution and restore the 2-pin bug.

  - **Root Cause 2 — Clustering collapsed 4 of 5 spawns into 1 pin**: `_DrawObjectiveIcons` uses `clusterLevelHotzone = 50` yards as the pin clustering radius. Four of the five AscensionDB Mana Wyrm spawn coords are within 27 yards of each other, so they were collapsed into a single centroid pin. Only the outlier at `{57.78, 64.93}` (~94 yards away) remained separate, yielding 2 pins total from 5 coords.
    - **Fix (`QuestieQuest.lua`)**: Added `if orderedList[1] and orderedList[1].zone == 1241 then range = 0 end` after the existing object-icon range reduction. Zone 1241 (Sunstrider Isle) is a tiny starter area where every spawn coord should be shown individually.

- **[Fix — QuestieLearner Zone ID Normalization]** All learner spawn data was being stored under raw area IDs (e.g. `3431` for Sunstrider Isle) rather than the map IDs (`1241`) that AscensionDB, ZoneDB, and the pin rendering pipeline use. This caused learner pins for any NPC on Sunstrider to be silently dropped by `DrawWorldIcon`/HBD because `mapData[3431]` does not exist.
  - **Root Cause**: `LearnNPC` and `_StoreGuidSpawnEvidence` stored the raw `spawnZoneId` (area ID from `GetAreaID()`) without converting it. `NormalizeSpawnZoneKey` only handled ghost map 946 and was never called at storage time.
  - **Fix**: Rewrote `NormalizeSpawnZoneKey` to consult `ZoneDB.private.areaIdToUiMapId` — the same authoritative table used by AscensionDB — for all zone ID conversions. `LearnNPC` now calls it immediately after obtaining `zoneId`. `_StoreGuidSpawnEvidence` calls it before storing evidence. `_MergeSpawnEvidence` isSunstrider check updated from `topEvidence.zoneId == 3431` to `IsSunstriderNativeZone(topEvidence.zoneId)` since normalized zone IDs are now map IDs (1241) not area IDs (3431).
  - **Result**: Learner spawns are now stored under map IDs matching AscensionDB's key space (`z1241`, `z1941`, etc.), ensuring consistent zone keys across both data sources and correct pin rendering for all zones.

### Bug Fixes

- **[Fix — Arrow Rendering: Single-Frame SetRotation]** Replaced the sprite sheet-based arrow rendering with a single-frame texture + `SetRotation()` for perfectly smooth rotation. The sprite sheet approach used 108 discrete frames (3.33° per step), causing visible jitter. The previous attempt to fix this with `SetRotation` sub-cell interpolation broke WoW's UV sampling and displayed the entire sprite sheet on screen.
  - **New arrow texture**: `Icons/arrow.tga` was set to X-PLORE's `XPArrow4.tga` — a single 256×256 RGBA TGA with a blue neon arrow pointing UP at `SetRotation(0)`, centered at pixel (128,128) for clean pivot rotation.
  - **Removed all sprite sheet logic**: No more `ARROW_SHEET_*`, `ARROW_CELL_*`, `ARROW_TOTAL_CELLS`, `SetTexCoord` cell selection, or UV padding. Replaced with `ARROW_DISPLAY_SIZE` (single constant for on-screen pixel size) and `SetRotation(-angle)` for infinite angular resolution.
  - **Direction math**: WoW's `SetRotation` is clockwise-positive (CW for positive r). The arrow angle `0` = target ahead (north), positive = clockwise, so we apply `SetRotation(angle)`.
  - **Arrow anchor**: Changed from `SetPoint("TOP")` to `SetPoint("CENTER")` so the rotation pivot aligns with the frame center.
  - **No color tint**: `SetVertexColor(1, 1, 1)` preserves the original blue neon appearance.

- **[Fix — Arrow Target Selection: Mixed Coordinate Systems]** Fixed the GPS arrow not pointing to the nearest objective when quests span calibrated (Sunstrider) and normal zones. Three interacting bugs caused incorrect distance sorting:
  - **_CollectFinisherSpawns used HBD exclusively**: On Sunstrider, objective distances used calibrated pseudo-world coordinates (0-1353 range) while finisher distances used HBD world coordinates (tens of thousands range). These incomparable units caused quests with both objectives and turn-in NPCs on the same map to sort incorrectly — a Sunstrider finisher NPC at calibrated distance 500 (≈500 yards) could lose to an objective at HBD distance 300 because 300 < 500, even though the finisher was closer. Now `_CollectFinisherSpawns` uses `QuestieCompat.GetCalibratedWorldCoordinatesFromZone` and calibrated Euclidean distance for calibrated targets, matching `_CollectObjective`.
  - **Player position in HBD distance calls**: On Sunstrider, `_arrow_playerX/Y` held calibrated pseudo-world coordinates (0-1353). Both `_CollectObjective` and `_CollectFinisherSpawns` passed these to `HBD:GetWorldDistance(pInst, pX, pY, tX, tY)` for non-calibrated targets, mixing pseudo-world player coords with real-world target coords. Now both functions use `_arrow_hbdPlayerX/Y` (always in HBD world coordinate space) for HBD distance calculations, ensuring the coordinate systems match.
  - **Cross-instance penalty for calibrated targets**: The `tInst ~= pInst` penalty (`500000 + dist * 100`) applied to calibrated targets on Sunstrider where `tInst = 0` (from `GetCalibratedWorldCoordinatesFromZone`) and `pInst` was the real instance ID. Now gated behind `(not calibratedTargetGroup)` so calibrated targets are never penalized for instance mismatch.

- **[Fix — Complete-Abandon-Reaccept Pin Lifecycle]** Fixed quest map pins and GPS arrow not reappearing after completing quest objectives, abandoning the quest, and re-accepting it from the quest giver. Five interacting bugs caused stale state to survive the quest reset:
  - **MarkQuestAsAbandoned**: The `objectivesWereComplete` path called `CompleteQuest` without clearing `quest.Objectives`, `quest.WasComplete`, or `quest.isComplete`. Stale `Completed=true` and `isUpdated=true` flags caused `PopulateObjectiveNotes` to skip drawing pins on re-accept. Now clears objectives/flags and calls `SetObjectivesDirty(questId)` before `CompleteQuest`.
  - **CompleteQuest**: Did not clear `quest.Objectives` (unlike `AbandonedQuest` which does). Now adds `quest.Objectives = {}` with type guard as defense-in-depth.
  - **QUEST_TURNED_IN dead code**: `questLog[questId] = {}` wiped state before the QUEST_TURNED_IN state check could read it, making the auto-complete cleanup unreachable. Moved the check before the wipe.
  - **AcceptQuest reset**: Added `SetObjectivesDirty(questId)` in the quest re-accept reset block for defense-in-depth, ensuring `isUpdated` flags are reset even if stale objectives somehow survive.
  - **Arrow spawnList gap**: The GPS arrow's `_CollectObjective` silently skipped objectives with nil/empty `spawnList`. After quest re-accept, `PopulateQuestLogInfo` creates objectives without `spawnList`; `PopulateObjectiveNotes` builds it later in the TaskQueue. Added `QuestieQuest:BuildObjectiveSpawnList(objective, objectiveData)` public API that lazily builds `spawnList` from `objectiveSpawnListCallTable` handlers (which include QuestieLearner-injected NPC/object/item spawn data from SavedVariables). The arrow now calls this when `spawnList` is missing.
- **[Fix — MapIconTooltip _GetLevelString Guard]** Resolved `attempt to concatenate local 'minLevel' (a nil value)` crash in `MapIconTooltip.lua:494` (`_GetLevelString` function). The creature name "Uneasy Citizen" existed in `creatureLevels` as an empty table `{}` rather than the expected `[1]=minLevel, [2]=maxLevel, [3]=rank` tuple, causing `creatureLevels[name][1]` to return nil. Added an early-return guard at the top of `_GetLevelString`: if `creatureLevels[name]` is falsy or not a table with a numeric level at index `[1]`, return the name unmodified.
- **[Fix — Tooltip Learned Data Schema Mismatch]** Reworked learned NPC/object tooltip registration in `Modules/Tooltips/Tooltip.lua` to match the actual `QuestieLearner` storage format.
  - **Player-Facing Symptom**: Fixed the Stormwind mouseover crash reported on Bronzebeard while hovering city guards and other learned tooltip targets: `Questie-X\\Modules\\Tooltips\\Tooltip.lua:240: attempt to index local 'objList' (a number value)`.
  - **Root Cause**: `QuestieLearner:_AddToArray` stores flat arrays of quest IDs (`learnedNpc[10] = { questId1, questId2, ... }`, `learnedObj[2] = { questId1, questId2, ... }`), but the pushed tooltip code still iterated them as `{ questId -> objList }` maps. That caused crashes like `attempt to index local 'objList' (a number value)` when a quest ID number was treated like an objective-text array.
  - **Fix**: Replaced the legacy `for questId, objList in next, ...` / `objList[oIndex]` traversal with schema-correct lookup: iterate learned quest IDs via `ipairs`, fetch `QuestieLearner.data.quests[questId]`, then walk `qData[10]` objective slots and entries (`objEntry[2]`) to reconstruct tooltip text safely.
  - **Scope**: Applied to both learned NPC tooltips (`m_<id>`) and learned object tooltips (`o_<id>`). Object lookup now reads quest IDs from `learnedObj[2]` (quest starts) instead of the old `learnedObj[10]` path.
- **[Fix — InsertMissingQuestIds String Guard]** Added `if type(QuestieDB.questData) ~= "table" then return end` guard at the start of `InsertMissingQuestIds()` in both `tbcQuestFixes.lua` and `wotlkQuestFixes.lua`. Prevents the function from writing to `questData` while it is still an uncompiled string during early loader initialization.
- **[Fix — Sunstrider Isle Arrow Distance (Map Closed)]** Resolved arrow distance showing ~1118 yards instead of ~37 yards on Sunstrider Isle when the world map is NOT open. Map open and zoomed out showed correct distance.
  - **Root Cause (Player Position)**: `HBD:GetPlayerWorldPosition()` returns a non-nil value on Sunstrider Isle, but those coords are Eastern Kingdoms world position (wrong), not Sunstrider's actual position. Because a non-nil value is returned, the fallback chain never fires. The arrow then calculates distance using wrong player coords vs correct target coords, giving a wildly incorrect distance.
  - **Root Cause (Ghost Map Player Position)**: `C_Map.GetPlayerMapPosition(946, "player")` where `946` is Ascension's ghost/cosmic map for Sunstrider Isle returns `(0, 0)` because the ghost map has no valid coordinate data. The correct map for player position on Sunstrider is `1941` (Eversong Woods parent), which shares the same world coordinate space and returns valid zone coords.
  - **Root Cause (OnUpdate same-map check)**: `OnUpdate` was using `_ResolveArrowUiMapId(_arrow_playerUiMapId)` (which resolves 1241→1941) for the player-side uiMapId, making it equal to `target.uiMapId` (also 1941). This caused the same-map branch to fire, which then called `C_Map.GetPlayerMapPosition(_arrow_playerUiMapId)` with 946, getting `(0, 0)` and computing wrong distance.
  - **Fix — QuestieArrow.lua UpdateNearestTargets**: Added Sunstrider detection (`zoneId == 3430 OR 3431 OR uiMapId == 1241`) BEFORE calling `HBD:GetPlayerWorldPosition()` to force the C_Map fallback path. All 4 Sunstrider detection checks in QuestieArrow.lua now accept zoneId 3430 OR 3431 OR uiMapId 1241 (lines 354, 395, 747, 782), since `GetCurrentZoneId()` can return either 3430 or 3431 when the player is physically on uiMap 1241. The fallback now calls `C_Map.GetPlayerMapPosition(1241, "player")` to get Sunstrider map-space coords, then converts through `HBD:GetWorldCoordinatesFromZone(..., 1941)` using Eversong Woods bounds — which share Sunstrider's world coordinate space.
  - **Fix — QuestieArrow.lua OnUpdate same-map branch**: Changed `C_Map.GetPlayerMapPosition(1941, "player")` for player zone coords (not `_arrow_playerUiMapId` which is 946). Normalizes both `playerUiMapId` and `targetUiMapId` through `_ResolveArrowUiMapId()` before same-map comparison. Uses `zoneScale = 13.53` yards/zone-unit for distance. Declares `worldPlayerX/Y` before the if-else to prevent nil in debug prints.
  - **Debug Output**: Added debug prints showing UnitPosition vs HBD player coords comparison, raw vs resolved uiMapIds, branch selection, and per-frame distance calculation inputs.
- **[Fix — Sunstrider Isle Map Pins Not Appearing]** Resolved quest objective icons (map pins) not appearing on the world map when zoomed into Sunstrider Isle (uiMapId 1241), even though they appeared correctly when zoomed out to Eversong Woods (uiMapId 1941).
  - **Root Cause**: `HBDPins:HandlePin` (HereBeDragons-Pins-2.0:424) has an early-return guard: `if not HBD.mapData[uiMapID] then return end`. When the player zooms into Sunstrider Isle, `uiMapID` is 1241, but `HBD.mapData[1241]` is nil — no mapData entry existed for Sunstrider's custom child map. The icon was silently dropped before any coordinate conversion occurred.
  - **Fix — Compat/HBD.lua**: Added `mapData[1241] = mapData[1941]` alias and `mapData[946] = mapData[1941]` alias. Sunstrider Isle (1241) and its ghost map (946) share Eversong Woods' (1941) world coordinate space for these conversions.
  - **Fix — HBD fallback loading**: Added a lazy fallback to the real HBD library's `mapData` for maps not present in Questie's compat table, so custom/private-server maps can still resolve world and zone coordinates when QuestieCompat lacks a local entry.
  - **Fix — Modules/Map/QuestieMap.lua**: Added `_ResolveMapUiMapId()` helper (1241→1941) applied across `FadeLogic`, `FindClosestStarter`, `GetNearestSpawn`, and `GetNearestQuestSpawn`. `DrawWorldIcon` and `DrawManualIcon` now also store and render Sunstrider map icons against the resolved parent map coordinate space.
- **[Fix — Northshire Valley UiMapData Registration]** Added explicit `QuestieCompat.UiMapData[1238]` for Northshire Valley so custom/private-server zone lookups have concrete geometry for the child map instead of relying on incomplete parent fallbacks.
- **[Fix — QuestieLearner Icon Preservation]** Preserved the learned objective icon when registering with the tooltip system so nameplates can render the correct learned slay/loot/talk marker. Previously the icon was always nil on fresh registration.
- **[Fix — Override Data Invisible to GetNPC/GetObject/GetItem]** — CRITICAL bug where ALL override data (from wotlkNPCFixes, AscensionDB, and QuestieLearner) was silently ignored by the three entity getter functions. Root cause: GetNPC/GetObject/GetItem iterated `npcKeys/objectKeys/itemKeys` using string keys (e.g. override["spawns"]) but ALL override sources store data using numeric keys via the key constants (e.g. override[npcKeys.spawns] = override[7]). In Lua, t["spawns"] ≠ t[7]. Fix: Added `_MergeOverride(result, override, rawdata, keyMap)` helper that tries both string and numeric keys before falling back to rawdata. Applied to GetNPC, GetObject, and GetItem. This ensures AscensionDB spawn data, wotlkNPCFixes corrections, and QuestieLearner-learned spawns are all visible through the database API.
- **[Fix — QuestieLearner Spawn Zone Tracking]** All LearnNPC call sites now explicitly pass zoneId as the spawnZoneId parameter, ensuring learned spawn data is stored under the correct areaId key (3430 for Eversong) instead of leaving it nil for the fallback GetZoneId() which previously returned the wrong uiMapId. Affected call sites: OnMouseoverUnit (passes areaId from l10n), OnQuestDetail, OnQuestComplete, OnQuestAccepted, OnQuestTurnedIn, and GOSSIP_SHOW handler. OnQuestComplete also now captures zoneId via GetZoneId() before using it.
- **[Fix — Sunstrider Isle Zone Mapping]** Changed `areaIdToUiMapId[3430]` from 1241 to 1941. Both WotLKDB and AscensionDB store Eversong-wide coordinates under zone 3430; mapping 3430→1241 forced those coordinates onto the Sunstrider sub-map, placing pins in mountains. Now 3430→1941 renders pins correctly on Eversong, and ZONE_REDIRECT provides cross-visibility to Sunstrider (1241). Removed redundant `UiMapIdOverrides[1241]=3430`. Additionally, removed the 1241→1941 redirect in `_ResolveMapUiMapId()` so pins targeting Sunstrider render natively using Ascension-calibrated bounds. Added `areaIdToUiMapId[1241] = 1241` mapping in zoneDB.lua so `DrawWorldIcon` can place pins directly on the Sunstrider sub-map.
- **[Fix — Sunstrider Map Pin System]** Removed the 1241→1941 redirect in `_ResolveMapUiMapId()`. Pins on 1241 now render natively using Ascension-calibrated bounds instead of being forced to 1941's coordinate space. Added `areaIdToUiMapId[1241] = 1241` mapping in zoneDB.lua so `DrawWorldIcon` can place pins directly on the Sunstrider sub-map. HBD's ZONE_REDIRECT visibility (`ResolveZone(1241)=1941`) ensures pins on 1241 are also visible on the Eversong map.
- **[Fix — Sunstrider zoneId 3431 Detection (QuestieArrow.lua)]** `GetCurrentZoneId()` returns 3431 (Eversong Woods) when the player is physically on uiMap 1241 (Sunstrider Isle), not 3430 as previously assumed. All 4 Sunstrider detection checks in QuestieArrow.lua now accept zoneId 3430 OR 3431 OR uiMapId 1241 (lines 354, 395, 747, 782). Without this fix, NONE of the Sunstrider coordinate overrides triggered, causing the arrow to compute player and target positions in different coordinate spaces (858 yard offset).
- **[Fix — Arrow Rotation Direction (QuestieArrow.lua)]** WoW's `Texture:SetRotation(r)` rotates CW for positive r, NOT CCW as the code comment claimed. Changed `rotAngle = -relative` to `rotAngle = relative` (line 441). The arrow was rotating in the opposite direction of the target, pointing away instead of toward it.
- **[Fix — Collection Function Distance Mismatch (QuestieArrow.lua)]** `_CollectFinisherSpawns` and `_CollectObjective` converted targets through 1941 (Eversong) bounds while player coordinates were in 1241 (Sunstrider) bounds. Added `sunOverride = (pMap == 1241)` variable and forced target conversion through 1241 bounds at all 4 conversion sites in both functions. Without this fix, sortedTargets showed dist=1261 instead of the correct ~48 yards.
- **[Fix — NPC Spawn Zone for Sunstrider (AscensionDB)]** NPC 15281 (Lanthan Perilon) spawn data changed from zone 3430 to zone 1241. Coordinates gathered via `GetPlayerMapPosition` on uiMap 1241 are in 1241's normalized space, NOT 1941's. Using zone 3430 (→1941) produced world coordinates outside 1241's 0-1 range, making map pins invisible on the Sunstrider sub-map. HBD's ZONE_REDIRECT visibility (`ResolveZone(1241)=1941`) ensures pins on 1241 are also visible on the Eversong map.

### Notes

- The 1.6.3 section reflects the published release state. Future entries will be added above this section in the next release cycle.
- Several Sunstrider experiments did NOT work and are intentionally not the documented fix path: relying on `HBD:GetPlayerWorldPosition()` on the closed map, using ghost map `946` for `C_Map.GetPlayerMapPosition`, and treating `QuestieLearner` tooltip data as `{ questId -> objList }` instead of flat quest-id arrays.

## v1.6.1 (2026-05-04)

### Bug Fixes

- **[Fix - Map Icon Completion]** Resolved a bug where quest objective icons (map pins and minimap markers) persisted on the world map and minimap after objectives were fulfilled, only disappearing after speaking to the quest giver to complete the quest.
  - **SpecialObjectives Dirty Flag**: Added a missing loop in `SetObjectivesDirty` to reset `isUpdated = false` on `quest.SpecialObjectives` alongside the existing `quest.Objectives` loop. Previously, special objectives (e.g. demonic runestones, portal-closing mechanics) would skip the `ObjectiveUpdate` early-exit guard because their `isUpdated` flag was never cleared, preventing `objective.Completed` from being set to `true` and leaving map icons on-screen indefinitely.
  - **Completion Guard in PopulateObjective**: Added a defensive check in `PopulateObjective` so that objectives without an `Update` function still unload their spawned icons if `objective.Completed` or `quest.isComplete` is already `true` from a prior update cycle.
- **[Fix - QuestLogCache Error Spam]** Silenced repetitive `[ERROR] Please report this error. GetQuest/GetQuestObjectives: The quest doesn't exist in QuestLogCache` chat messages that fired for quests not present in the cache (e.g. quest IDs 595, 959, 254048).
  - **Root Cause**: `QuestLogCache.GetQuest` and `QuestLogCache.GetQuestObjectives` called `Questie:Error(...)` unconditionally whenever a quest ID was not found in the cache, flooding chat on every objective update cycle.
  - **Fix**: Demoted both calls (and the accompanying `debugstack` print) from `Questie:Error` to `Questie:Debug(Questie.DEBUG_DEVELOP, ...)`. The messages are now silent during normal play and only visible when developer debug mode is active.

## Session 34 (2026-05-02)

### Maintenance

- **Removed unsupported legacy server references** — Deleted an unsupported legacy server row from the server compatibility table and removed its load tip from installation instructions in README.md.

### Documentation

- **Clarified two-addon installation requirement** — Updated README.md installation instructions to explicitly state that Questie-X requires BOTH the core addon AND a server-specific database plugin to function.

## v1.6.0 (2026-04-08)

### Bug Fixes

- **[Fix — Map Search DB]** Resolved a critical database issue where objects and NPCs searched via Advanced Search failed to display all available spawn locations.
  - **Override Prioritization**: Refactored `GetObject`, `GetNPC`, and `GetItem` in `QuestieDB` to prioritize manual corrections (overrides) over the compiled database. This ensures human-verified data is always used when available.
  - **Correction Loader Fix**: Resolved a fundamental flaw in the correction system where WotLK-specific object fixes were being written to the binary database companion table (`objectData`) instead of the active override table (`objectDataOverrides`), causing overrides to be ignored by the rendering engine.
  - **Data Compatibility**: Hardened the database engine to support both integer and string-based indexing, preventing `nil` errors on legacy clients while maintaining performance.
- **[Fix — Object Spawn Data]** Restored missing "Blood of Heroes" (ID 176213) spawn locations.
  - **Override Migration**: Restructured the 150+ verified spawn locations to use the direct override path, ensuring they correctly render for all factions in Plaguelands on WotLK servers.
  - **Data Merge**: Integrated 150+ verified spawn locations from both the Classic database and Wowhead scraping into the WotLK module.
  - **Deduplication**: Sanitized coordinate data to remove duplicate pins, providing a cleaner map interface for high-density spawns in Plaguelands.
- **[UI — Search Experience]** Improved the Advanced Search results interface.
  - **Dynamic Button States**: Fixed the "Show on Map" button state management to correctly toggle to "Remove from Map" when pins are active.
  - **Stability**: Removed experimental rendering logic that caused regressions with standard quest objective icons.
- **[Fix — ChatFilter Mythic Keystone Parsing]** Resolved a bug where mythic keystone IDs posted in chat were incorrectly parsed as quest links and converted to broken clickable quests.
  - **Pattern Guard**: Added an early skip in `ChatFilter.Filter` to detect and skip entries where the extracted name starts with `"Keystone"`, preventing keystones from entering the quest-link conversion path.
  - **Root Cause**: The regex `\[(.+) %((%d+)%)]` matched chat messages like `[Keystone 12345]` because the name portion "Keystone 12345" matched `.+` and the ID happened to correspond to a valid quest ID in `QuestPointers`, causing a false-positive hyperlink replacement.
- **[Fix — Ebonhold Call Board Repeatable Quests]** Resolved a bug where repeatable quests from the Ebonhold Call Board showed as permanently complete in the tracker after re-accepting them.
  - **State Leak**: On Ebonhold, Call Board quests auto-complete and vanish from the quest log without firing a `QUEST_REMOVED` event. Questie was marking them as `QUEST_TURNED_IN` in the internal `questLog` table but never cleaning that state on re-accept, causing the tracker to render them as already-complete.
  - **Re-Accept Guard**: Added a pre-check in the `QUEST_ACCEPTED` handler that detects quests already in `QUEST_TURNED_IN` state and performs full cleanup (`QuestLogCache.RemoveQuest`, `CompleteQuest`, `Journey:CompleteQuest`, `Announce:CompletedQuest`, `Tracker:RemoveQuest`, `questLog[questId] = nil`) before processing the fresh accept.

## v1.5.9 (2026-04-08)

### Bug Fixes

- **[Fix — QuestieQuest Crash]** Resolved a critical runtime crash occurring after killing certain NPCs (specifically Water Revenant 30877 in Wintergrasp). 
  - **Harden Error Handling**: Replaced the fragile `print(debugstack())` in `ERR_FUNCTION` with a robust `Questie:Error` handler to prevent secondary crashes from masking real errors.
  - **Fix NPC Mapping**: Resolved a variable shadowing bug and fixed the mapping logic in `QuestieQuestPrivates:killcredit` to ensure NPC objective data is correctly populated during combat updates.

## v1.5.8 (2026-04-07)


## Questie-X - Expanded Font Selection

### New Features

- **Arrow Font Options**: Added font family and size settings for the arrow:
  - Arrow Font selector (SharedMedia + common WoW fonts)
  - Arrow Font Size slider (8-18)
- **Tracker "Apply to All" Options**: Added ability to set font and size for all tracker elements at once:
  - Font for All - sets font for Header, Zones, Quests, and Objectives simultaneously
  - Font Size for All - sets all font sizes simultaneously
- **Expanded Font List**: Both Arrow and Tracker font dropdowns now include common WoW fonts in addition to SharedMedia fonts (Friz Quadrata TT, Arial Narrow, GameFont variants, etc.)

### Bug Fixes

- **Arrow Scale/Alpha Real-time Updates**: Arrow scale, transparency, and font settings now update in real-time when changed in options
- **Arrow Position Reset**: Reset position button now properly resets the arrow to center screen
- **Arrow Font**: Fixed font not changing - now properly uses `SharedMedia:Fetch` to get actual font objects
- **Font List Blank**: Fixed font list being empty by using `pairs()` instead of `ipairs()` for hash table iteration (Lua 5.x compatible)

## v1.5.7 (2026-04-02)

### Stability & Initialization

- **[Fix — Options Crash]** Resolved a critical runtime error on WotLK 3.3.5a: `attempt to call method 'AddToBlizOptions' (a nil value)`. This was caused by the modern `AceConfigDialog-3.0` library attempting to use the Retail-only `Settings` API. A compatibility shim has been implemented in `!X-Libs` to bridge this call back to the native `InterfaceOptions_AddCategory` API.
- **[Fix — Library Load Order]** Updated core library package to `!X-Libs` to ensure it loads before all other addons. This guarantees that `LibStub` is initialized and available for addons like `BugSack` that load very early in the sequence.

## v1.5.5 (2026-03-29)

### Performance — Profiler-Driven Optimizations

Addressed micro-stutters and FPS drops (190 → sub-100) reported during high-frequency NPC/player mouseover interactions. Five targeted fixes based on profiler data.

- **[Perf — Position Caching]** Cached `HBD:GetPlayerWorldPosition()` and `HBD:GetPlayerZonePosition()` at a 50ms interval (20 Hz). Previously these called `QuestieCompat.GetCurrentPlayerPosition()` — a C API round-trip — on every minimap `OnUpdate` frame (60–144 times/sec), accounting for **1,171ms / 45,570 calls** over 10 minutes in profiler data. Cache is invalidated immediately on `PLAYER_ENTERING_WORLD` and `ZONE_CHANGED_*` events. Expected call reduction: ~97%.

- **[Perf — ZoneDB O(1) Lookup]** Replaced the O(n) linear scan in `ZoneDB:GetAreaIdByUiMapId` with an O(1) pre-built reverse lookup cache (`uiMapIdToAreaIdCache`). The old implementation iterated the entire `uiMapIdToAreaId` table on every call, accounting for **6.92ms / 375 calls** in the profiler (called by `QuestieArrow` and `QuestiePlayer`). The cache is built once at `ZoneDB:Initialize()` via a new `_ZoneDB:BuildUiMapIdToAreaIdCache()` function and kept in sync by `ApplyCustomZones()`. The name-match fallback remains available for unmapped IDs and now caches its results on first use.

- **[Perf — Tooltip OnUpdate Throttle]** Throttled the `GameTooltip:HookScript("OnUpdate", ...)` callback to a maximum of **10 checks per second** (100ms interval). This hook was previously firing every frame (60–144 Hz) and calling `GetText()`, `CountTooltip()`, and potentially `AddObjectDataToTooltip()` on every frame regardless of whether the tooltip changed. Added a `_tooltipLastText` cache so expensive work is skipped when the hovered object hasn't changed.

- **[Perf — Arrow Closure Hoisting]** Hoisted four inner `local function` declarations out of `_CollectQuestTargets` (called at 1 Hz by `QuestieArrow:UpdateNearestTargets`): `_HasMissingCompletedFlag`, `_GetCompleteIconType`, `_CollectFinisherSpawns`, and `_CollectObjective`. These were re-allocated as closures on every call, producing GC pressure. They are now module-level functions that read per-cycle context from shared `_arrow_*` upvalue variables set at the start of each `UpdateNearestTargets` call.

- **[Perf — LearnerComms Micro-Optimizations]** Four targeted fixes in `QuestieLearnerComms`:
  - **Ticker rate**: `ProcessQueues` ticker reduced from 0.2s to 0.5s (still 7× faster than the 3.5s `minChatInterval` rate limit, so no messages are delayed).
  - **Channel ID caching**: Hidden channel ID is now cached at `Initialize()` and lazily refreshed on disconnect, instead of calling `GetChannelName` on every queue tick.
  - **Compression level**: `LibDeflate:CompressDeflate` level reduced from 9 (slowest/max) to 1 (fastest). For small addon message payloads the size difference is negligible but the CPU cost is substantially lower.
  - **Dedup counter**: `IsDuplicateMessage` now uses an O(1) integer counter (`messageCacheCount`) to track cache size instead of an O(n) `for _ in pairs(messageCache)` scan on every incoming message.

- **[Fix — Profiler UI]** Resolved an issue where the `QuestieProfiler` UI text was overlapping horizontally when function names were too long, rendering the time and call counts illegible. Lines are now appropriately spaced and function names are clamped and left-aligned.

- **[Perf — Math Inlining]** Removed `QuestieLib:Euclid` function call overhead from the minimap icon `FadeLogic` hot loop in favor of an inline Pythagorean distance check, reducing micro-stutters during movement.

- **[Perf — Quest Tracker Bag Scans]** Removed O(N) nested loops iterating over the entire character inventory in `TrackerLinePool:SetItem` and `QuestieQuest:CheckQuestSourceItem`, replacing them with native O(1) `GetItemCount(itemId)` queries. Completely eliminated thousands of `GetContainerItemInfo` calls.

- **[Perf — Tracker Cooldown Throttling]** Added a 5Hz (0.2s) execution throttle to the tracker quest item button `btn.OnUpdate` frame handler, dropping baseline `GetItemCooldown` API polls from ~6000+ checks every few minutes down to a fraction of that load.

- **[Fix — Tooltip Duplicates]** Added aggressive regex filtering to automatically strip Ascension's duplicate native custom quest text lines from appearing twice in unit and item tooltips (Before Questie seamlessly injects its own higher-fidelity formatted data).

## v1.5.4 (2026-03-29)

### Ascension Custom Zone Support

- **[Fix — PrintDifficultyColor Nil Text]** Fixed crash in `PrintDifficultyColor` when quest name is nil. Added defensive nil check in `GetColoredQuestName` to return early if `QuestieDB.QueryQuestSingle` returns nil for a quest, preventing "attempt to concatenate local 'text' (a nil value)" errors.

- **[Fix — Townsfolk POI Map IDs]** Fixed some Townsfolk POIs not appearing in custom zones. Removed the `uiMapId > 1000` restriction in `ZoneDB:ApplyCustomZones()` that was preventing custom zone IDs below 1000 from being registered as self-mappings. This caused some Townsfolk NPCs with zone IDs < 1000 to fail UiMapId lookups and not display on the map.

- **[Fix — Townsfolk DataOverrides Lookup]** Fixed Townsfolk initialization to properly check both `QuestieDB.npcData` and `QuestieDB.npcDataOverrides` / `QuestieDB.objectDataOverrides`. On custom servers (Ebonhold, Ascension), the database is loaded via plugins into overrides tables, but `Townsfolk.Initialize()` was only checking the base database tables which are empty until Stage 3 compilation. This affected Flight Masters, Auctioneers, Innkeepers, Repair Vendors, Class Trainers, and Mailboxes.

- **[Fix — Custom Zone Map Pins]** Fixed map icons not appearing in Ascension custom zones (e.g., Valley of Trials, Northshire Valley). The issue was that custom zone UiMapData was not properly injected into `QuestieCompat.UiMapData` before HBD initialized its map cache. Added `ApplyCustomZones()` function in `ZoneDB` that hooks `ZoneDB.Initialize` to inject custom zones BEFORE the original initialization runs, ensuring HBD's `mapData` table contains custom zone entries like 1244 (Valley of Trials).

- **[Fix — Zone Name Fallback]** Fixed "Unknown Zone" display for custom zones in the tracker. When `GetZoneNameByID` fails for custom zone IDs, the system now falls back to `GetQuestLogZoneName` which reads the zone header directly from the quest log where custom zone names are properly displayed.

- **[Fix — GetCurrentUiMapID]** Updated `QuestieCompat.GetCurrentUiMapID` to check `QuestieCompat.UiMapData` directly for custom zone IDs. Previously, only `mapIdToUiMapId` was checked, which doesn't contain custom zones.

- **[Fix — Arrow Waypoint Zone Filter]** Fixed waypoint arrow not showing targets in custom zones. The arrow's auto-tracking logic was filtering out objectives by zone comparison, but custom zones use different IDs (e.g., 1244 for Valley of Trials) than their parent zones (e.g., 14 for Durotar). Added `QuestiePlayer:GetCurrentUiMapId()` function and updated arrow zone filtering to compare both `playerZoneId` AND `playerUiMapId` against objective zone IDs.

- **[Fix — Tracker Objective Nil Check]** Added defensive nil check for `objective.Description` when rendering quest objectives. Custom server quests may have objectives without a Description field, which would previously cause a crash.

- **[Fix — InjectUiMapData Registration]** Fixed `QuestiePluginAPI:InjectUiMapData` to call `ZoneDB:ApplyCustomZones()` after injecting custom zone data, ensuring the zone mappings are properly registered with both `ZoneDB` and `QuestieCompat.UiMapData`.

### Realm Detection

- **[Fix — Realm Name Matching]** Fixed Ascension realm detection in `AscensionUiMapData.lua` to use `string.find()` instead of exact string comparison. Realms like "Bronzebeard - Warcraft Reborn" now properly match the "Bronzebeard" pattern, allowing custom zone data to load on all Ascension server variants.

### Database

- **[Feature — Use Quest Item Keybind]** Added configurable keyboard hotkey to automatically use the quest item for the nearest incomplete quest objective. When pressed, Questie scans active quests for usable quest items (items with spells), checks which ones are in the player's bags, calculates proximity to quest objectives, and uses the nearest one. Configurable via Tracker options tab under "Use Quest Item (Nearest)".

### Keybinds

- **[Feature — Dedicated Keybinds Tab]** Added a new Keybinds options tab with configurable keybinds for:
  - **Use Nearest Quest Item** — Press to automatically use the quest item for the nearest incomplete quest objective
  - **Toggle Options** — Open/close the Questie Options window
  - **Toggle Tracker** — Show/hide the Questie Tracker
  - **Toggle My Journey** — Open/close the Journey window

## v1.5.2 (2026-03-29)

### Ascension Custom Zone Support

- **[Fix — Custom Zone Map Pins]** Fixed map icons not appearing in Ascension custom zones (e.g., Valley of Trials, Northshire Valley). The issue was that custom zone UiMapData was not properly injected into `QuestieCompat.UiMapData` before HBD initialized its map cache. Added `ApplyCustomZones()` function in `ZoneDB` that hooks `ZoneDB.Initialize` to inject custom zones BEFORE the original initialization runs, ensuring HBD's `mapData` table contains custom zone entries like 1244 (Valley of Trials).

- **[Fix — Zone Name Fallback]** Fixed "Unknown Zone" display for custom zones in the tracker. When `GetZoneNameByID` fails for custom zone IDs, the system now falls back to `GetQuestLogZoneName` which reads the zone header directly from the quest log where custom zone names are properly displayed.

- **[Fix — GetCurrentUiMapID]** Updated `QuestieCompat.GetCurrentUiMapID` to check `QuestieCompat.UiMapData` directly for custom zone IDs. Previously, only `mapIdToUiMapId` was checked, which doesn't contain custom zones.

- **[Fix — Arrow Waypoint Zone Filter]** Fixed waypoint arrow not showing targets in custom zones. The arrow's auto-tracking logic was filtering out objectives by zone comparison, but custom zones use different IDs (e.g., 1244 for Valley of Trials) than their parent zones (e.g., 14 for Durotar). Added `QuestiePlayer:GetCurrentUiMapId()` function and updated arrow zone filtering to compare both `playerZoneId` AND `playerUiMapId` against objective zone IDs.

- **[Fix — Tracker Objective Nil Check]** Added defensive nil check for `objective.Description` when rendering quest objectives. Custom server quests may have objectives without a Description field, which would previously cause a crash.

- **[Fix — InjectUiMapData Registration]** Fixed `QuestiePluginAPI:InjectUiMapData` to call `ZoneDB:ApplyCustomZones()` after injecting custom zone data, ensuring the zone mappings are properly registered with both `ZoneDB` and `QuestieCompat.UiMapData`.

### Realm Detection

- **[Fix — Realm Name Matching]** Fixed Ascension realm detection in `AscensionUiMapData.lua` to use `string.find()` instead of exact string comparison. Realms like "Bronzebeard - Warcraft Reborn" now properly match the "Bronzebeard" pattern, allowing custom zone data to load on all Ascension server variants.

### Database

- **[Feature — Use Quest Item Keybind]** Added configurable keyboard hotkey to automatically use the quest item for the nearest incomplete quest objective. When pressed, Questie scans active quests for usable quest items (items with spells), checks which ones are in the player's bags, calculates proximity to quest objectives, and uses the nearest one. Configurable via Tracker options tab under "Use Quest Item (Nearest)".

## v1.5.1 (2026-03-28)

- **[Fix — Minimap Icons]** Prevented external "minimap button grabber" addons (e.g., Leatrix Plus, MBB) from incorrectly hiding Questie-X quest pins. Minimap icons now use a protected `QuestieFrameGroup` container that is ignored by these addons while maintaining correct spatial anchoring via `HereBeDragons`.
- **[Fix — Tracker Crash]** Fixed "attempt to index field 'Description' (a nil value)" crash in `QuestieTracker` when iterating over `quest.Objectives` that contain nil entries. Added nil check before accessing `objective.Description` to prevent crashes on custom server quest data.
- **[Fix — Killcredit NPC Linking]** Enhanced `killcredit` objective handling to properly link NPCs when database entries have missing or invalid IDs. Added two-pass approach: first tries ID-based lookup, then falls back to name-based search using the objective description text. Also fixed `monster` function to gracefully handle `npcId <= 0` instead of erroring.
- **[Feature — Existing Quest Scanning]** Added `ScanExistingQuestLog` function to proactively map objectives for quests already in the quest log on addon initialization. Previously, objective mapping only occurred for newly accepted quests.
- **[Fix — AceComm-3.0]** Added nil check for `RegisterAddonMessagePrefix` on private servers where this API may not be available.

## v1.5.0 (2026-03-28)

- **[Fix — Database Robustness]** Added strict guards against invalid or zero IDs in `QuestieDB` lookup functions (`GetNPC`, `GetObject`, `GetItem`). This prevents the "rawdata is nil" debug spam that occurred when custom plugins attempted to access uninitialized or malformed entity data.
- **[Refactor — Lookup Logic]** Refactored `QuestieDB` override handling to support both numeric and string keys simultaneously. This ensures that custom server data (e.g., Ascension, Ebonhold) is correctly resolved regardless of how the third-party plugin formats its internal IDs.
- **[Refactor — Data Injection]** Updated `QuestieLearner:InjectLearnedData` to enforce numeric key normalization. All dynamically learned spawn data is now strictly indexed by numeric IDs, preventing type-mismatch collisions during database merging.
- **[Feature — Enhanced Logging]** Improved Stage 3 initialization logging to provide detailed reporting on custom data injection. Developers can now verify the exact number of NPCs, Objects, and Items injected by plugins directly from the `DEVELOP` log.
- **[Fix — Ascension Zone Mapping]** Fixed a regression in `QuestieCompat` where `uiMapData` for Ascension-specific zones was not correctly propagating to the global mapping table, restoring map pin functionality for seasonal and custom zones.
- **[Fix — QuestieLearner]** Centralized zone/area ID lookup in `l10n` module to prevent `GetAreaIdByLocalName` nil errors (Fixes Project Ebonhold runtime crash).
- **[Fix — Custom Server Compilation]** Fixed database compilation not running on custom servers (Ascension, Ebonhold, etc.) where plugins inject data after initial load.
  - Modified `Modules/QuestieInit.lua` Stage1 to defer compilation to Stage3 for custom servers, ensuring plugins finish injecting data before compilation runs.
  - Added `l10n:Initialize()` and `QuestieCorrections:MinimalInit()` calls when deferring to Stage3, as Stage2 (`QuestieJourney:Initialize()`) requires `hiddenQuests` to be populated.
  - Added "Bronzebeard" and "Warcraft Reborn" to Ascension realm detection patterns in `Modules/QuestieServer.lua`.
- **[Fix — Zone Mapping Bug]** Fixed incorrect key assignment in `QuestiePluginAPI:InjectZoneTables()`. Changed `areaIdToUiMapId[uiMapId] = uiMapId` to `areaIdToUiMapId[areaId] = uiMapId` at line 138. This caused zone lookups to fail, resulting in "No UiMapID or fitting parentAreaId" errors for custom zone IDs.

### Known Issues (v1.5.0)

- **[Ebonhold Detection]** The `Questie.IsEbonhold` flag detection remains brittle. It currently relies on a substring match against `GetRealmName()`. Variations like "Test Ebonhold" or localized names may cause the flag to fail, resulting in missing Questie-X-Ebonhold features. A more robust detection pattern using `GetCVar("realmName")` or server-pushed flags is planned for a future update.

## v1.4.9 (2026-03-26)

- **[Fix — Quest Cache]** Resolved the "GetQuest: The quest doesn't exist in QuestLogCache" fatal error occurring during initialization on the Ascension WoW client.
  - Implemented a robust retry mechanism in `_QuestEventHandler:InitQuestLog` to wait for the game's quest log data to become fully available before populating the local cache.
  - Refactored `QuestLogCache.GetQuest` and `GetQuestObjectives` to fail gracefully (returning `nil` or `{}`, respectively) instead of throwing a fatal error when data is accessed prematurely during the initialization handshake.
- **[Robustness]** Improved cache-miss handling for `questId == 0` and early-access calls from third-party addons during the login process.
- **[Fix — Validation Crash]** Fixed crash in `DecodePointerMap` when compiled database pointer map was empty or corrupted. Added defensive check to return empty table instead of crashing.
- **[Fix — Database Compiler]** Added skip logic in `ValidateObjects` and `ValidateQuests` when compiled binary data is missing, preventing validation failures on cached databases from incomplete previous sessions.
- **[Fix — Initialization]** Modified `QuestieInit` to skip validation in Stage 1 when plugins are pending, since plugins inject data after compilation and validation would compare stale pre-plugin data against post-plugin data.
- **[Fix — Quest Links]** Fixed duplicate quest links when shift-clicking quests in the quest log (e.g., "[A Boar's Vitality] [A Boar's Vitality]"). Removed redundant `ChatEdit_InsertLink` call from `QuestLogTitleButton_OnClick` hook; Blizzard's native function now handles link insertion.
- **[Fix — Profiler]** Fixed "memory allocation error: block too big" crash in `QuestieProfiler`. Added early-exit logic in `HookTable` to skip large pure-data tables (e.g., `npcDataOverrides` spawn coordinates) that don't benefit from profiling.
- **[Fix — Zone Mapping]** Added UiMapId overrides for 1415 (Eastern Kingdoms) and 947 (Azeroth) in `zoneDB.lua` to resolve "No AreaId found" warnings on Ascension servers.
- **[Fix — Quest Validation]** Fixed `QuestieValidateGameCache` to silently skip "ghost quests" (removed from database but still in quest log) instead of failing validation, resolving infinite retry loops on servers with custom quest content.
- **[Fix — AscensionDB]** Fixed syntax error in `AscensionNpcDB_2.lua` (missing closing `}` at end of NPC entry for ID 3287).
- **[Map Pin Gating]** Learned map pins (sword icons) now only appear after reaching a configurable confidence threshold (default: 2).
- **[Confidence in Tooltips]** NPC and Object tooltips now display their confidence level (e.g., `(Learned - Confidence: 2)`).
- **[Timestamp Tracking]** Added `lastSeen` (`ls`) timestamps to all learned entries to track data freshness.

### QuestieLearnerComms.lua — Global Data Sharing

- **[Community Reinforcement]** Expanded data sharing from Party/Guild to a global hidden channel. Confidence values (`mc`) now increment when identical data is received from other Questie users, allowing the community to verify spawns collectively.
- **[Network Freshness]** Receiving data over the network now refreshes the `lastSeen` timestamp, keeping active community spawns from being pruned.

### QuestieLearnerExport.lua — Tiered Stale Data Cleanup

- **[Tiered Pruning]** Implemented a robust cleanup system that protects "Verified" (high-confidence) data from age-based deletion.
- **[Age-Based Pruning]** "Unconfirmed" data is now automatically pruned if it hasn't been seen within a configurable timeframe (default: 90 days).
- **[Redundancy Pruning]** Logic to remove data already present in the official Questie database now respects the `pruneVerified` toggle, allowing users to keep verified personal data even if it overlaps with the core DB.

### QuestieOptionsDatabase.lua — Advanced Cleanup Controls

- **[Stale Data Threshold]** Added a slider to control the age-pruning threshold (1-180 days) for unconfirmed data.
- **[Verified Data Protection]** Added a toggle to include or exclude verified data from redundancy pruning.
- **[UI Reorganization]** Refactored the Database tab's cleanup section for better logical flow and clarity.

---

## v1.2.9 — QuestieLearner Cross-Link Engine + Tracker Zone Fix + Untrack Fix

### QuestieLearner.lua — Universal Cross-Link Engine

- **[Cross-link engine — full rewrite]** Replaced the narrow NPC↔Quest cross-link stubs with a comprehensive bidirectional relationship engine covering all four entity types. Three shared primitives underpin the whole system: `_AddToArray(tbl, key, value, ovrTable, ovrId)` adds a value to an array field and mirrors it to the live `*DataOverrides` table in the same call; `_AddToNestedArray` does the same for two-level nested arrays (used for quest starters/finishers sub-slots); `_AddToQuestObjective` inserts `{entityId, text}` pairs into `quest[10][slot]` (the objectives array) with the same dual-write pattern. Every write is idempotent (no-op if value already present).
- **[CrossLinkAfterNPC]** Called whenever a new NPC ID is first committed to `learnedData.npcs`. Iterates all learned quests: (a) if quest`[2][1]` contains this npcId → adds questId to `npc[10]` (questStarts); (b) if quest`[3][1]` contains this npcId → adds questId to `npc[11]` (questEnds); (c) walks quest`[10][3]` (item objectives) — for each item whose `item[2]` (npcDrops) already references this NPC, the NPC is injected into `quest[10][1]` as a creature objective so it can receive map pins and tooltip text.
- **[CrossLinkAfterQuest]** Called when a new quest is first committed to `learnedData.quests`. Links all referenced entities: starter NPCs (quest`[2][1]`) → each known NPC's `npc[10]`; starter objects (quest`[2][2]`) → each known object's `obj[2]`; finisher NPCs (quest`[3][1]`) → `npc[11]`; finisher objects (quest`[3][2]`) → `obj[3]`; source item (quest`[11]`) → `item[5]` (startQuest key per itemDB schema); item drop chain (quest`[10][3]` items whose `item[2]` lists known NPCs) → those NPCs are injected into `quest[10][1]` as a creature objective. This means: learn a quest that needs Wolf Fur → later kill a wolf that drops it → the wolf NPC immediately becomes a tracked creature objective for that quest.
- **[CrossLinkAfterObject]** Called when a new object is first committed to `learnedData.objects`. Scans all learned quests: if quest`[2][2]` references this objectId → adds questId to `obj[2]` (questStarts); if quest`[3][2]` references it → adds questId to `obj[3]` (questEnds).
- **[CrossLinkAfterItem]** Called when a new item is first committed to `learnedData.items` AND whenever a new drop-NPC relationship is added via `LearnItemDrop`. Two passes: (1) scan all learned quests for `quest[11] == itemId` → set `item[5] = questId` (item starts this quest); (2) scan all learned quests for `quest[10][3]` entries matching itemId — for each such quest, every NPC in `item[2]` (drop sources) is injected into `quest[10][1]` as a creature objective. This means: learn a quest that needs Wolf Fur → later kill a wolf that drops it → the wolf NPC immediately becomes a tracked creature objective for that quest.
- **[CrossLinkAfterQuestGiver]** Now handles all three entity type slots (1=NPC, 2=Object, 3=Item) instead of only NPCs. For typeSlot=1: stitches `npc[10/11]` ↔ `quest[2/3][1]` bidirectionally. For typeSlot=2: stitches `obj[2/3]` ↔ `quest[2/3][2]`. For typeSlot=3: adds itemId to `quest[2][3]` (item starters slot). All writes go to both `learnedData` (SavedVariables) and live `*DataOverrides` tables simultaneously.
- **[LearnItemDrop hook]** Now calls `CrossLinkAfterItem(itemId)` every time a new NPC is added to an item's drop list, not just on initial item creation. This propagates the drop→quest objective chain retroactively.
- **[LearnQuest hook]** Calls `CrossLinkAfterQuest(questId)` on first creation of a quest record.
- **[LearnObject hook]** Calls `CrossLinkAfterObject(objectId)` on first creation of an object record.
- **[LearnItem hook]** Calls `CrossLinkAfterItem(itemId)` on first creation of an item record.
- **[Item schema correction]** Fixed incorrect use of key `[9]` (itemLevel) for quest-source storage. Now correctly uses `[5]` (`startQuest`) per `QuestieDB.itemKeys` schema.
- **[Mouseover — all NPCs now learned]** Removed the `UnitReaction < 4` early-return guard that blocked hostile/neutral NPC learning via mouseover. All NPCs are now learned on hover. The existing `QUESTGIVER` NPC-flag check remains as the primary filter for quest-relevant NPCs during mouseover. Hostile quest objective NPCs are now captured on any interaction (mouseover, targeting, or kill) and are correctly cross-linked to relevant quests.

### TrackerUtils.lua — Zone Resolution Rewrite

- **[GetQuestLogZoneName — canonical 3.3.5 zone lookup]** Added new local function `GetQuestLogZoneName(questId)`. Implements the canonical 3.3.5a zone resolution method: iterates the quest log from index 1 to `GetNumQuestLogEntries()` to locate the quest's log index, then walks backwards from that index checking `isHeader` until the nearest zone header title is found. This is the only fully reliable zone name source in 3.3.5a — the client places zone header entries (where `isHeader=true`) immediately above the quests belonging to that zone in the quest log flat list. `GetRealZoneText()` and `GetCurrentMapAreaID()` are unreliable because they depend on the currently viewed map, not the quest's actual zone.
- **[BuildFallbackQuest — zone via log walk]** Replaced the previous `GetRealZoneText()` call with the quest log header walk. The existing loop that iterates the quest log to find the quest entry now continues backwards from that index to find the header title. `GetAreaIdByZoneName()` is still called to convert the string to an area ID for `zoneOrSort`, but the string itself is always the ground truth used for display.
- **[_isLogFallback patch block — zone fix]** The block that patches QuestLogCache fallback objects (those with `_isLogFallback=true` but no `IsComplete` method) now calls `GetQuestLogZoneName(capturedId)` immediately after patching `Objectives`/`SpecialObjectives`/`ExtraObjectives`. If a zone name is returned, both `quest.zoneName` and `quest.zoneOrSort` are set on the object. Previously this block left `zoneOrSort=0` and `zoneName=nil`, causing every fallback quest to group under "Unknown Zone".
- **[Fallback cache invalidation]** `_fallbackQuests[qid]` is now evicted and rebuilt if the cached entry has no `zoneName`. This handles the case where `BuildFallbackQuest` was called during addon init (before the quest log was fully populated) and cached a zoneless entry.
- **[GetAreaIdByZoneName preserved]** Still available for converting zone header strings to numeric area IDs for `zoneOrSort`. The area ID is used by the proximity sort and zone grouping logic; the string is used for display labels.

### QuestieTracker.lua — Untrack Fix

- **[UntrackQuestId — logic was inverted]** `UntrackQuestId` was setting `AutoUntrackedQuests[questId] = nil` when untracking. The tracker filter reads `not Questie.db.char.AutoUntrackedQuests[questId]` — `nil` evaluates as "show this quest", so clearing the entry on untrack immediately re-showed the quest on the next update tick. Fix: when `autoTrackQuests = true`, untrack now sets `AutoUntrackedQuests[questId] = true` (hide); when `autoTrackQuests = false`, it clears `TrackedQuests[questId]` (manual mode). The two modes are now cleanly separated.
- **[AQW_Insert — removed QuestLogFrame gate]** The `IsShiftKeyDown() and QuestLogFrame:IsShown()` guard that was blocking re-tracking quests from outside the quest log frame has been removed. Re-tracking (clearing `AutoUntrackedQuests[questId]`) now works from any context. The shift-click-to-untrack path was already handled by `RemoveQuestWatch` → `UntrackQuestId`; this gate was only blocking the re-track flow.
- **[Quest completion cleanup]** `_RemoveQuestIdFromCharTables` already clears `AutoUntrackedQuests` when a quest leaves the log (completed or abandoned), preventing stale hidden-quest entries in SavedVariables.

---

## v1.2.7 — WotLKDB Plugin Stats Fix + Kill Tracking Refinement

### QuestieInit.lua — LoadBaseDB Count Tracking

- **[WotLKDB stats fix]** `LoadBaseDB()` now counts all four data tables (`questData`, `npcData`, `objectData`, `itemData`) **before** clearing the `QuestieX_WotLKDB_*` globals. Counts are stored in `_G.QuestieX_WotLKDB_Counts` for `Loader.lua` to read at `PLAYER_LOGIN`. This resolves WotLKDB showing `Quests:0 NPCs:0 Objects:0 Items:0` in the Advanced options plugin panel.

### QuestieLearner.lua — Kill Coordinate Filtering

- **[Kill tracking scoped to quest NPCs]** `OnCombatLogEvent(UNIT_DIED)` now only records kill coordinates when the killed NPC is either: (a) already present in `QuestieDB` (known quest objective mob), or (b) explicitly present in `_Learner.guidNpcCache` (was targeted or moused over as a known quest giver before the kill). Random mob kills that match neither condition are silently ignored. This prevents the learner from accumulating useless entries for every creature killed while questing.
- **[Removed dead hex-prefix fallback branch]** The "hex prefix scan for untargeted creatures not in cache" comment block was removed — it was a no-op that could never produce an NPC ID.

### Questie-X-WotLKDB Loader.lua — Plugin Stats Population

- **[Read counts from QuestieX_WotLKDB_Counts]** After `RegisterPlugin("WotLKDB")`, Loader.lua reads the counts global set by `LoadBaseDB()` and assigns them to `plugin.stats.QUEST/NPC/OBJECT/ITEM`. Frees the global after reading. Plugin panel now displays correct totals (e.g., `Quests: 9086`).

### Research Folder

- Added `Research/QuestieLearner-Verification.md` — step-by-step in-game test guide covering all 12 QuestieLearner subsystems (mouseover filter, quest accept/turn-in, kill coords, item loot async retry, object detection, export/import round-trip, plugin panel stats, peer sharing).
- Added `Research/SessionSummary-2026-03-16.md` — full developer session log covering all architectural decisions, errors, and fixes from the plugin architecture overhaul through the QuestieLearner rewrite.

---

## v1.2.6 — QuestieLearner Comprehensive Overhaul

> Rewrote QuestieLearner from scratch to fix all known data-capture deficiencies. Adds full quest field coverage, grid-based coordinate clustering, quest-giver-only mouseover filtering, async item-info retry, object loot detection, and live inject-on-import so imported data takes effect without a reload.

### QuestieLearner.lua — Full Rewrite

- **[Quest capture completeness]** `LearnQuest` now accepts a generic `data` table keyed by Questie wiki array indices rather than individual positional arguments. `OnQuestDetail` captures title, objectives text block, quest description body, and current zone as `zoneOrSort[8]`. `OnQuestAccepted` fills quest level from `GetQuestLogTitle`, per-objective text from `GetQuestLogLeaderBoard`, and required money from `GetQuestLogRequiredMoney`. `OnQuestComplete` captures finish/reward text via `GetRewardText`.
- **[Mouseover filter]** `OnMouseoverUnit` now only learns an NPC if its `UnitNPCFlags` bitmask includes the `QUESTGIVER` bit (`0x02`), OR if the NPC already exists in `QuestieDB` as a known quest starter/finisher. All other NPCs are silently ignored — this eliminates the flood of irrelevant NPC entries the learner previously accumulated.
- **[Target changed]** `OnTargetChanged` no longer calls `LearnNPC` on every target switch. It now only populates the `guidNpcCache` for kill-tracking purposes, avoiding recording non-quest NPCs.
- **[Coordinate clustering — grid bucketing]** Replaced the naive "within 1 unit radius" deduplication with a 2×2 grid bucket scheme (`COORD_GRID = 2.0`). A new point is inserted only when no existing point shares the same grid cell. This prevents coordinate scatter across a kill area while still preserving distinct spawn clusters. The `InsertIfNewBucket` helper is shared across NPC, Object, and all merge paths (including `InjectLearnedData` and `HandleNetworkData`).
- **[Object recording]** `OnLootOpened` now checks whether the loot source GUID is a `GameObject` (not just a creature). If so, `LearnObject` is called with the object's ID and name. `OnGossipShow` records both objects and NPCs via `GetIdAndTypeFromGUID`. `OnQuestDetail` and `OnQuestComplete` also record the interacting object when the quest giver/finisher is a `GameObject`.
- **[Item loot — async GetItemInfo retry]** `OnLootOpened` queues unresolved item links (where `GetItemInfo` returns nil because the item is not yet in the client cache) into `_Learner.pendingItemLinks`. A new `OnGetItemInfoReceived(itemId)` handler fires on the `GET_ITEM_INFO_RECEIVED` event, resolves queued links for that item ID, and calls `LearnItem`/`LearnItemDrop` once the data is available. This fixes silent data loss on first-encounter loots.
- **[Quest giver entity type]** `LearnQuestGiver` now accepts an `entityType` argument (1=NPC, 2=GameObject, 3=item) and stores starters/finishers in the correct sub-array slot matching the Questie wiki spec `{ [1]={npcIds}, [2]={objIds}, [3]={itemIds} }`.
- **[Kill tracking fallback]** `OnCombatLogEvent` retains all three GUID-resolution paths (dash-split, GUID cache, hex-prefix) with a 10-minute TTL cache cleanup. Uses `CombatLogGetCurrentEventInfo()` with fallback to varargs for cross-client compatibility.
- **[GET_ITEM_INFO_RECEIVED event]** Registered in `RegisterEvents` so the async item retry path fires correctly.
- **[InjectLearnedData — grid clustering]** All coordinate merge loops in `InjectLearnedData` now use `InsertIfNewBucket` instead of the old radius check.

### QuestieLearnerExport.lua — Import Live-Inject Fix

- **[MergeImport → InjectLearnedData]** After `MergeType` completes for all four categories, `MergeImport` now immediately calls `QuestieLearner:InjectLearnedData()`. Imported data is pushed into `QuestieDB.*DataOverrides` in the same frame — override-driven map pins update without a `/reload`. A full reload is still needed to pick up newly imported quest starters/finishers for quests already tracked in the player's quest log.

### README — Import Clarification

- Corrected the "no reload required" claim. The import flow now accurately describes when an immediate effect is visible versus when a `/reload` is beneficial.

---

## v1.2.5 — Ebonhold DB Plugin Load Fix

> Fixed a fatal load-time crash in all four Ebonhold DB files caused by calling `GetRealmName()` and `QuestieLoader:CreateModule()` at file scope (before WoW's API is fully available). Switched to plain global table population; realm-gating and injection remain safely deferred to `EbonholdLoader.lua`'s `PLAYER_LOGIN` handler.

### Questie-X-EbonholdDB — DB File Refactor

- **[Root cause]** `EbonholdNpcDB.lua`, `EbonholdObjectDB.lua`, `EbonholdItemDB.lua`, and `EbonholdQuestDB.lua` each started with `if GetRealmName() ~= "Rogue-Lite (Live)" then return end` followed immediately by `QuestieLoader:CreateModule("EbonholdDB")`. Both calls execute at file-load time (during `LoadAddOn()`), before `PLAYER_LOGIN` has fired and before `QuestieLoader` is guaranteed to be populated. This produced `attempt to index global 'QuestieLoader' (a nil value)` on every load.
- **[Ebonhold/EbonholdNpcDB.lua]** Removed file-level realm guard and `QuestieLoader:CreateModule` call. Replaced with `_G.EbonholdDB = _G.EbonholdDB or {}` and a local alias. Data is now populated unconditionally into the global at load time.
- **[Ebonhold/EbonholdObjectDB.lua]** Same fix as NpcDB.
- **[Ebonhold/EbonholdItemDB.lua]** Same fix as NpcDB.
- **[Ebonhold/EbonholdQuestDB.lua]** Same fix as NpcDB.
- **[EbonholdLoader.lua]** Replaced `QuestieLoader:ImportModule("EbonholdDB")` with `_G.EbonholdDB or {}`. The loader's existing `PLAYER_LOGIN` handler with realm check remains intact as the sole gate for injection into Questie-X.

---

## v1.2.2 — DB Plugin Pull Architecture & Compiler Hardening

> Overhauled the DB plugin loading pipeline from a fragile push/bridge pattern to a direct pull at init time. Fixed a long-standing compiler bug that silently dropped `extraobjective` condition data. Removed all `DevTools_Dump` calls that were printing raw Lua table syntax to chat during validation.

### DB Plugin Architecture — Pull Pattern

- **[QuestieInit:LoadBaseDB]** Replaced the broken `QuestieX_CoreDB` bridge mechanism with a direct pull of DB plugin globals at init time. `LoadBaseDB()` now checks for `QuestieX_WotLKDB_quest`, `QuestieX_WotLKDB_npc`, `QuestieX_WotLKDB_object`, and `QuestieX_WotLKDB_item` globals and assigns them directly to `QuestieDB.*Data` before calling `LoadDatabase()` on each key. Globals are cleared (`= nil`) after transfer to free memory. This approach is unconditionally reliable — it runs inside Questie-X's own init coroutine at a known point in the load sequence, with no dependency on cross-addon module references.
- **[QuestieInit:LoadBaseDB — diagnostics]** Replaced the old "WotLKDB addon loaded / SplitLoaded flag / quest global" diagnostic lines with new pull-result lines: `WotLKDB pull: quest=true/false npc=true/false obj=true/false item=true/false` and per-key type/length lines, making it immediately obvious whether the DB plugin data was absorbed.
- **[QuestieDB.lua]** Removed `_G.QuestieX_CoreDB = QuestieDB` export. The CoreDB bridge global is no longer needed and was never reliably accessible from DB plugin Loader.lua files due to module-registry timing.

### DB Plugin — Loader.lua Simplification

- **[Questie-X-WotLKDB/Loader.lua]** Stripped the entire data-transfer block (the `if not QuestieX_CoreDB then return end` guard and subsequent `QuestieX_CoreDB.*Data = ...` assignments). The file is now purely a `PLAYER_LOGIN` handler that: registers the plugin with `QuestiePluginAPI`, counts and logs the absorbed quest/NPC/object/item table sizes via `QuestieDB` module reference, and emits a `DEBUG_CRITICAL` warning if `questData` is still empty after init (indicating a load-order or split-file failure). This makes Loader.lua a diagnostic and registration stub rather than a critical data pathway.

### Compiler — extraobjectives Conditions Field

- **[compiler.lua — writer `extraobjectives`]** Added serialization of `data[6]` (conditions table). After writing the 5 existing fields per entry (spawnlist, icon, description, objectiveIndex, reflist), the writer now writes a `WriteByte(n)` count followed by `WriteShortString(key)` + `WriteInt24(value)` for each condition entry. If `data[6]` is nil or not a table, writes `0` (no conditions).
- **[compiler.lua — reader `extraobjectives`]** Added deserialization of the conditions field. After reading the 5 fields per entry, reads a `ReadByte()` condition count; if non-zero, reconstructs the conditions table as `{[key]=value}` and assigns it to `entry[6]`. If count is 0, `entry[6]` is left nil (no allocation).
- **[compiler.lua — skipper `extraobjectives`]** Updated to skip condition bytes: reads the condition count byte, then for each condition skips a `ShortString` (`ReadShort() + _pointer`) and an `Int24` (`_pointer + 3`).
- **[Root cause]** `QuestieDB.lua:1443` reads `HideCondition = o[6]` from each extraobjective at quest-object build time. Before this fix, compiled data always produced `o[6] = nil`, so `ShouldHideObjective()` never activated. The `hideIfQuestActive` / `hideIfQuestComplete` conditions defined in corrections (e.g. quest 12924 — "Pick up 'You Can't Miss Him'") were silently ignored post-compilation. Validation also flagged the mismatch on every load, which triggered `DevTools_Dump` to flood chat with raw Lua table syntax.

### Compiler — DevTools_Dump Removal

- **[compiler.lua — ValidateNPCs / ValidateObjects / ValidateItems / ValidateQuests]** Removed all four `DevTools_Dump({["Compiled Table:"]=a, ["Base Table:"]=b})` calls from the table-mismatch branches in each validator. These calls serialized full Lua tables to the chat frame as raw source code, which appeared to users as a syntax error or data corruption. The preceding `Questie:Warning(...)` line in each branch already captures the mismatch identity (key, field id, entry ID). `DevTools_Dump` is a retail WoW debugging API unavailable or unreliable on private/custom servers and should not be called in production validation paths.

---

## v1.2.4 — Retail/SoD Corrections Removed

> Deleted all Season of Discovery, Season of Mastery, and Hardcore correction files. These were retail-specific and never referenced by the TOC. Cleaned up all dead imports, constants, and code branches they left behind in `QuestieCorrections.lua`.

### Files Deleted

- **`Database/Corrections/SeasonOfDiscovery.lua`** — SoD base quest/NPC/object/item overrides
- **`Database/Corrections/sodQuestFixes.lua`** — SoD quest corrections
- **`Database/Corrections/sodNPCFixes.lua`** — SoD NPC corrections
- **`Database/Corrections/sodItemFixes.lua`** — SoD item corrections
- **`Database/Corrections/sodObjectFixes.lua`** — SoD object corrections
- **`Database/Corrections/Automatic/sodBaseQuests.lua`** — SoD auto-generated base quests
- **`Database/Corrections/Automatic/sodBaseNPCs.lua`** — SoD auto-generated base NPCs
- **`Database/Corrections/Automatic/sodBaseItems.lua`** — SoD auto-generated base items
- **`Database/Corrections/Automatic/sodBaseObjects.lua`** — SoD auto-generated base objects
- **`Database/Corrections/HardcoreBlacklist.lua`** — Hardcore mode quest blacklist
- **`Database/Corrections/SoMPhases.lua`** — Season of Mastery phase data (was already commented out in TOC)

### QuestieCorrections.lua Cleanup

- **Imports removed**: `HardcoreBlacklist` and `SeasonOfDiscovery` `ImportModule` calls deleted.
- **Constants removed**: `SOD_ONLY = 5` and `HIDE_SOD = 6` deleted from the expansion filter enum. Remaining constants (`TBC_ONLY`, `CLASSIC_ONLY`, `WOTLK_ONLY`, `TBC_AND_WOTLK`, `CLASSIC_AND_TBC`) are unchanged.
- **`filterExpansion`**: removed the `isSoD` local and the two `SOD_ONLY` / `HIDE_SOD` branches.
- **`MinimalInit`**: removed the `if Questie.IsSoD then addOverride(...SeasonOfDiscovery:LoadFactionQuestFixes()...) end` block.
- **`MinimalInit`**: removed the `if Questie.IsHardcore then HardcoreBlacklist:Load() end` block.
- **`Initialize`**: removed the 8-call `if Questie.IsSoD then SeasonOfDiscovery:LoadBase*/Load*() end` block covering quest/NPC/item/object base data and fixes.
- **TOC**: removed the commented-out `#Database\Corrections\SoMPhases.lua` line.

---

## v1.2.3 — Diagnostics Refactor & Monolithic DB Removal

> Moved all DB init diagnostics out of chat and into the Develop debug level. Replaced hardcoded quest-ID spot-checks with generic per-table stats. Removed the stale monolithic database folders that have been fully superseded by the DB plugin architecture.

### DB Init Diagnostics — DEVELOP Level

- **[QuestieInit — _dbStats helper]** Added a local `_dbStats(t)` function that returns `count=N minID=X maxID=Y` for any table. Used at every checkpoint so diagnostic output is meaningful for any server's dataset without hardcoding expansion-specific IDs.
- **[QuestieInit — _dbDiag table removed]** Eliminated the `local _dbDiag = {}` accumulator table and the deferred `C_Timer.After(6, ...)` print block. Diagnostics are now emitted inline as `Questie:Debug(Questie.DEBUG_DEVELOP, "[DBDiag] ...")` calls at the exact point each stage completes, making them visible in real time when Develop logging is enabled rather than appearing as a delayed flood 6 seconds after load.
- **[QuestieInit:LoadBaseDB]** Pull result line (`WotLKDB pull: quest=... npc=... obj=... item=...`) converted to `DEBUG_DEVELOP`.
- **[QuestieInit:loadFullDatabase]** Four diagnostic checkpoints converted to `DEBUG_DEVELOP` with generic `_dbStats` output: After LoadBaseDB (quest + npc on one line, obj + item on the next), After Corrections (quest + npc), Before Compile (quest + npc), After Compile (type= of each key, confirming binary serialization completed).
- **[QuestieInit:LoadDatabase — error paths]** Two `_dbDiag` push lines for `loadstring` parse errors and `pcall` execution errors converted to `DEBUG_DEVELOP`.
- **[QuestieInit.Stages[1] — cached path]** `DB was CACHED (no recompile)` line converted to `DEBUG_DEVELOP`.

### DB Plugin — Loader.lua Premature Count Check Removed

- **[Questie-X-WotLKDB/Loader.lua]** Removed the `countTable` / quest+npc+obj+item count block and the `DEBUG_CRITICAL` "questData is empty" warning that fired at `PLAYER_LOGIN`. This check always reported zero counts because it ran before `QuestieInit`'s loading coroutine had started. The `[DBDiag]` lines (now at `DEBUG_DEVELOP`) are the correct place to verify data absorption. Loader.lua is now a minimal registration stub: registers the plugin with `QuestiePluginAPI`, prints the confirmed registration line, and calls `plugin:FinishLoading`.

### Monolithic Database Folders Removed

- **[Database/Classic/]** Deleted `classicQuestDB.lua` (1.0 MB), `classicNpcDB.lua` (2.0 MB), `classicObjectDB.lua` (1.0 MB), `classicItemDB.lua` (2.1 MB). These monolithic files were never listed in `Questie-X.toc` and would have been silently skipped by WoW 3.3.5 anyway due to the ~1 MB per-file parse limit. Classic data is now provided exclusively by the ClassicDB plugin.
- **[Database/TBC/]** Deleted `tbcQuestDB.lua` (1.6 MB), `tbcNpcDB.lua` (3.5 MB), `tbcObjectDB.lua` (1.6 MB), `tbcItemDB.lua` (3.3 MB). TBC data is now provided exclusively by the TBCDB plugin.
- **[Database/Wotlk/]** Deleted `wotlkQuestDB.lua` (2.3 MB), `wotlkNpcDB.lua` (5.2 MB), `wotlkObjectDB.lua` (2.0 MB), `wotlkItemDB.lua` (4.4 MB). WotLK data is now provided exclusively by the WotLKDB plugin via the split-file mechanism. Combined removal: ~30 MB of dead weight from the core repository.

---

## v1.1.7 - v1.2.1 — DB Loading Diagnostics & Fallback Tracker

> Ongoing stability pass. Hardened the entire database loading pipeline, wired up the live quest-log fallback for quests missing from the DB, and fixed a chain of nil-guard crashes across corrections, map, and tracker modules.

### Database Loading

- **[LoadDatabase]** Replaced bare `loadstring()` / `fn()` calls with proper error capture (`local fn, err = loadstring(...)` + `pcall(fn)`). Errors now print to chat with the failing key and string length instead of silently falling back to `{}`.
- **[Compiler]** Fixed `hasData` guard in `QuestieDBCompiler:Compile()` — now accepts `type == "table"` in addition to `"string"`, preventing the compiler from silently aborting when `LoadDatabase` has already decoded the string to a table before compilation.
- **[DB Architecture]** Identified and documented that loading multiple DB plugins simultaneously (e.g. WotLKDB + ClassicDB) causes `questData` overwrites. On WotLK servers only `Questie-X-WotLKDB` should be enabled alongside the server-specific plugin.

### Live Fallback for Missing Quests

- **[QuestieDB.GetQuest]** When `rawdata` is nil, a minimal quest object is now built from `QuestLogCache` instead of returning nil. The fallback populates `name`, `level`, `isComplete`, and an empty `Objectives` table with `_isLogFallback = true`.
- **[QuestieQuest.PopulateQuestLogInfo]** Fallback quests now seed their `Objectives` table from `QuestLogCache.GetQuestObjectives` on first call, then call `obj:Update()` on each to refresh progress from the live quest log.
- **[QuestieQuest.UpdateObjectiveNotes]** Fallback quests now early-return to skip the static DB spawn-list path (`objectiveSpawnListCallTable`), preventing "Corrupted objective data" errors caused by nil NPC IDs.

### Crash Fixes

- **[QuestieLib.GetQuestString]** Guard against nil `name` — returns quest ID string as fallback (tracker error for quest 10482).
- **[QuestieDB spawn loop]** Nil-guard on `objectData[id]` before clearing spawn keys in prune loop (attempt to index nil at QuestieDB:1715).
- **[QuestieDB.GetSpawnList]** Wrapped `objectiveSpawnListCallTable` result in nil-guard before iterating — prevents `pairs(nil)` when a referenced NPC/object is missing from the loaded DB.
- **[QuestieQuestPrivates killcredit]** `monster(killCreditNpcId)` result nil-guarded before indexing — prevents crash for kill-credit NPCs absent from npcData.
- **[Townsfolk]** `flags` nil-guard added before `bitband(flags, VENDOR)` call (bad argument #1 to bitband).
- **[QuestieQuest.UpdateObjectiveNotes]** `quest.SpecialObjectives` nil-guard before `next()` call.
- **[QuestieQuest.PopulateQuestLogInfo]** `quest.SpecialObjectives` nil-guard before `next()` call.

### Junctions & Dev Environment

- Created `mklink /J` junctions for `Questie-X-TBCDB` and `Questie-X-ClassicDB` into Ebonhold AddOns folder for live in-game testing.

---

## v1.1.6 — Minimap Icon & P2 Stability

> Minimap button overhaul and second pass of P2 bug fixes.

### Minimap

- **[MinimapIcon]** Replaced default minimap icon with custom `mmapIcon.tga`. Applied `SetMask` for circular clip on WotLK+ clients with `SetTexCoord` fallback for 1.12 vanilla clients.

### Bug Fixes (P2)

- **[QuestieServer]** Restored plugin status UI, `C_QuestLog`/`C_Map` shims, and `QuestieServer` init sequence.
- **[QuestieLoader]** Corrected `select()` polyfill to not use `arg` table.
- **[TOC]** Added XXH load to TBC toc and guarded `plugin.stats` nil access.

---

## v1.1.5 — QuestieLearner Expansion & Database Options

> Major expansion of the data-learning system and a new Database options tab.

### QuestieLearner

- **[QuestieLearner]** Expanded hook coverage: quest accept, objective kill, object interaction, and item loot all feed learned data back to the appropriate DB table.
- **[QuestieLearnerComms]** Broadcast/receive learned entries to nearby Questie-X users via addon messages.
- **[Custom Server Detection]** Learned data for unrecognised quest IDs is stored under a per-realm key in `QuestieLearnerDB` to separate retail/private/custom content.
- **[DEVELOP logging]** Debug messages emitted on every successful learn and every failed-to-learn event.

### Options — Database Tab

- **[QuestieOptionsDatabase]** New "Database" tab with Import / Export (LibDeflate base64 encoded strings) and Cleanup (prune stale learned entries) functionality.

---

## v1.0 - v1.1.4 — Questie-X: Plugin Architecture & Maintenance Update

> This release marks the official rebranding from **Questie-335** / **PE-Questie** to **Questie-X** and introduces the new plugin architecture. Additionally, this version includes significant UI enhancements, core compatibility refinements for legacy clients, and critical database corrections.

### Architecture Changes

- **[Repo]** Repository renamed and re-homed to `Xurkon/Questie-X`. Remote updated from `PE-Questie` to `Questie-X`.
- **[Plugin API]** Introduced `QuestiePluginAPI` (`Modules/Libs/QuestiePluginAPI.lua`). Plugins register themselves and inject quest, NPC, object, item, and zone data without modifying core files.
- **[Server Detection]** Added `QuestieServer` module (`Modules/QuestieServer.lua`) for improved runtime server environment detection.
- **[Network]** Added `QuestieLearnerComms` module (`Modules/Network/QuestieLearnerComms.lua`) for cross-client quest data sharing.
- **[Database]** Removed embedded `Database/Ascension/` and `Database/Ebonhold/` folders. All custom server data is now distributed via separate plugin addons.

### UI Enhancements

- **[Options]** Resizable Options window! The Questie options UI can now be resized with corner drag functionality. Size and position persist between sessions.
- **[Options]** New **Credits Tab**! A dedicated tab in the options menu to acknowledge contributors and community partners.
- **[Tutorial]** Improved tutorial flows for objective type selection.

### Core & Stability (v1.3.5)

- **[Lua 5.0]** Globally polyfilled `string.match` and `string.gmatch` using `string.find` and `string.gfind` to ensure universal compatibility with legacy WoW clients.
- **[AceTimer]** Patched embedded `AceTimer-3.0` instances in ElvUI and OG-RaidHelper to resolve `math.mod` errors on Lua 5.0 clients.
- **[Colors]** Updated `CreateColor` polyfill with `SetRGB`, `SetRGBA`, `SetColor`, and `GetColor` methods.
- **[Comm]** Improved cross-client data sharing stability.

### Map & Tooltips

- **[Tooltips]** NPC names and objective text now populate reliably on map pins and world unit tooltips.
- **[Tooltips]** Resolved `[QuestieTooltips:GetTooltip] m_20509` debug log spam.

### Quest Data

- **[Database]** Scraped and injected missing spawn coordinates for Bonechewer Mutant, Raider, Evoker, and Scavenger (NPC IDs 16876, 16925, 19701, 18952) from Wowhead.
- **[Quest 10482]** Correctly mapped Bonechewer NPCs to quest objectives in both WotLK and TBC database correction files.

### New Plugins

- **Questie-Ascension** — Project Ascension server database.
- **Questie-Ebonhold** — Ebonhold server database. [Questie-X-EbonholdDB](https://github.com/Xurkon/Questie-X-EbonholdDB)

### TOC / Addon Identity

- **[TOC]** Core addon `.toc` files updated to `Questie-X` title and `v1.3.8`
- **[Libs]** Added `LibDeflate`, `XXH_Lua_Lib`, `LibDBIcon-1.0`, and `LibDataBroker-1.1` to the Libs directory.

### Bug Fixes

- **[QuestieDB]** Overhauled `QuestieDB.IsComplete` to accurately verify all objectives are finished using `numFulfilled == numRequired` instead of the unreliable server-side `finished` flag.
  - Resolves completion state bugs for quests using consumable items (e.g. Cold Iron Key for quest 12843).
  - Fixed Quest Arrow priority logic to properly transition to finishers once objectives are complete.
- **[QuestieQuest]** Implemented `HideCondition` mechanism for objectives, allowing specific spawns to be hidden based on quest log status (`hideIfQuestActive` / `hideIfQuestComplete`).
- **[Cache]** Demoted Cache Validation "0/15 Error" to Debug level to reduce user confusion during login and reloads.
- **[Network]** Fixed sender trust validation in `QuestieLearnerComms`.

---

## v9.9.2 — Final Pre-Refactor Release

> ⚠️ **This is the final stable release before a major architectural refactoring.** All active features and quest data from previous releases are preserved. Future versions will introduce breaking changes to improve multi-server support, the database plugin system, and the zone registration API.

### Fixes

- **[Map]** Resolved an issue where NPC names and objective text were inconsistently missing from map tooltips.
  - Added support for `killcredit` and `spell` objective types in `MapIconTooltip.lua`.
  - Implemented proactive creature name prepending in `QuestieTooltips:GetTooltip` to ensure data visibility for rare/custom objectives.

### New Ebonhold Quests

#### 🗺️ Azeroth

| ID | Quest | Zone | Type |
|----|-------|------|------|
| 50187 | Western Plaguelands Trophy | Western Plaguelands | Kill 1 Rare (tracked rares) |

### NPC Data

- **classicNpcDB.lua** / **EbonholdNpcDB.lua**: Injected spawn coordinates for Western Plaguelands rare NPCs to support quest 50187.

### Documentation

- Completed a full deep-dive code audit of the entire addon codebase.
- Identified areas for improvement including server-agnostic design, version detection improvements, a plugin architecture for custom server databases, configurable level caps, and several code quality issues.
- Audit findings exported to the project research folder.

---

## v9.9.1

### New Ebonhold Quests

#### 🗺️ Azeroth

| ID | Quest | Zone | Type |
|----|-------|------|------|
| 50057 | Brood of the Black Flight | Burning Steppes | Kill 30 Dragonkin (10 NPCs tracked) |

### NPC Data

- **EbonholdNpcDB.lua**: Injected spawn coordinates for 10 Dragonkin NPCs in Burning Steppes (IDs 7040-7049) to support quest 50057.

## v9.9.0

### New Ebonhold Quests

#### 🗺️ Azeroth

| ID | Quest | Zone | Type |
|----|-------|------|------|
| 50128 | Southern Jungle | Stranglethorn Vale | Complete 6 quests |

#### 🌿 Kalimdor

| ID | Quest | Zone | Type |
|----|-------|------|------|
| 50006 | Sandstone Giants | Tanaris | Kill Sandstone Giants |
| 50130 | Felwood Restoration | Felwood | Complete 6 quests |

### Fixes

- **[Quest]** Fixed `QuestieDB` initialization error caused by missing table depth for custom creature objectives in `EbonholdQuestDB`.
- **[System]** Adjusted `Questie:Error` output logic so that critical addon-breaking errors always print regardless of the `Enable Debug-PRINT` setting.
- **[Map]** Fixed missing map pins for "Sandstone Giants" quest — changed objective type from `creatureObjective` to `killCreditObjective` so Questie correctly resolves spawn locations from the NPC database.
- **[Tracking]** Fixed collection quest counters showing stale counts when the Ebonhold scav bot loots items — implemented a 3-stage `BAG_UPDATE_DELAYED` strategy: immediate scan, 0.3s debounce scan, and a 2s follow-up scan to allow the server's quest-objective cache to flush batch loot counts.

## v9.8.9

### New Ebonhold Quests

#### 🗺️ Azeroth

| ID | Quest | Zone | Type |
|----|-------|------|------|
| 50178 | Badlands Trophy | Badlands | Kill 1 Rare (10 rares tracked) |
| 50176 | Arathi Trophy | Arathi Highlands | Kill 1 Rare (10 rares tracked) |
| 50175 | Alterac Trophy | Alterac Mountains | Kill 1 Rare (8 rares tracked) |
| 50162 | Wetlands Trophy | Wetlands | Kill 1 Rare (8 rares tracked) |
| 50160 | Redridge Trophy | Redridge Mountains | Kill 1 Rare (8 rares tracked) |
| 50157 | Modan Trophy | Loch Modan | Kill 1 Rare (7 rares tracked) |
| 50156 | Westfall Trophy | Westfall | Kill 1 Rare (9 rares tracked) |
| 50173 | Northern Jungle Trophy | Stranglethorn Vale | Kill 1 Rare (9 rares tracked) |
| 50183 | Southern Jungle Trophy | Stranglethorn Vale | Kill 1 Rare (9 rares tracked) |
| 50164 | Tirisfal Trophy | Tirisfal Glades | Kill 1 Rare (9 rares tracked) |
| 50153 | Morogh Trophy | Dun Morogh | Kill 1 Rare (6 rares tracked) |
| 50097 | Elwynn Errands | Elwynn Forest | Complete 6 quests |
| 50098 | Morogh Missions | Dun Morogh | Complete 6 quests |
| 50105 | Redridge Resolve | Redridge Mountains | Complete 6 quests |

#### 🌿 Kalimdor

| ID | Quest | Zone | Type |
|----|-------|------|------|
| 50154 | Teldrassil Trophy | Teldrassil | Kill 1 Rare (6 rares tracked) |
| 50034 | Ashen Corruption | Ashenvale | Kill 40 Demons (23 NPCs tracked) |
| 50020 | Spires of Chaos | Thousand Needles | Kill 30 Elementals (5 NPCs tracked) |
| 50099 | Shadow of Teldrassil | Teldrassil | Complete 6 quests |
| 50103 | Darkshore Defense | Darkshore | Complete 6 quests |
| 50104 | Bloodmyst Recovery | Bloodmyst Isle | Complete 6 quests |
| 50100 | Azuremyst Aid | Azuremyst Isle | Complete 6 quests |
| 50108 | Trials of Durotar | Durotar | Complete 6 quests |

#### 🌋 Outland

| ID | Quest | Zone | Type |
|----|-------|------|------|
| 50197 | Shadowmoon Trophy | Shadowmoon Valley | Kill 1 Rare (3 rares tracked) |
| 50195 | Blade's Edge Trophy | Blade's Edge Mountains | Kill 1 Rare (3 rares tracked) |
| 50196 | Netherstorm Trophy | Netherstorm | Kill 1 Rare (3 rares tracked) |
| 50192 | Zangarmarsh Trophy | Zangarmarsh | Kill 1 Rare (3 rares tracked) |
| 50045 | Demon's at the Edge | Blade's Edge Mountains | Kill 40 Demons (37 NPCs tracked) |
| 50044 | Fel Scars of Nagrand | Nagrand | Kill 40 Demons (14 NPCs tracked) |
| 50026 | Elemental Balance | Nagrand | Kill 30 Elementals (12 NPCs tracked) |
| 50060 | Skies of Blade's Edge | Blade's Edge Mountains | Kill 30 Dragonkin (17 NPCs tracked) |
| 50083 | Forest Stalkers | Terokkar Forest | Kill 75 Beasts (53 NPCs tracked) |
| 50082 | Marsh Predators | Zangarmarsh | Kill 75 Beasts (34 NPCs tracked) |
| 50085 | Savage Heights | Blade's Edge Mountains | Kill 75 Beasts (47 NPCs tracked) |
| 50086 | Unstable Fauna | Netherstorm | Kill 75 Beasts (18 NPCs tracked) |
| 50087 | Shadowed Beasts | Shadowmoon Valley | Kill 75 Beasts (25 NPCs tracked) |
| 50111 | Song of the Woods | Eversong Woods | Complete 6 quests |

#### ❄️ Northrend

| ID | Quest | Zone | Type |
|----|-------|------|------|
| 50200 | Fjord Trophy | Howling Fjord | Kill 1 Rare (3 rares tracked) |
| 50201 | Dragonblight Trophy | Dragonblight | Kill 1 Rare (3 rares tracked) |
| 50202 | Grizzly Trophy | Grizzly Hills | Kill 1 Rare (4 rares tracked) |
| 50203 | Zul'Drak Trophy | Zul'Drak | Kill 1 Rare (4 rares tracked) |
| 50199 | Borean Trophy | Borean Tundra | Kill 1 Rare (3 rares tracked) |
| 50205 | Storm Peaks Trophy | The Storm Peaks | Kill 1 Rare (4 rares tracked) |
| 50063 | Frostbound Brood | Borean Tundra | Kill 30 Dragonkin (16 NPCs tracked) |
| 50064 | Heart of the Dragonflights | Dragonblight | Kill 30 Dragonkin (49 NPCs tracked) |
| 50066 | Stormforged Scales | The Storm Peaks | Kill 30 Dragonkin (7 NPCs tracked) |
| 50030 | Tundra Turbulence | Borean Tundra | Kill 30+ Elementals (14 NPCs tracked) |
| 50031 | Stormbound | The Storm Peaks | Kill 30 Elementals (11 NPCs tracked) |
| 50089 | Tundra Hunters | Borean Tundra | Kill 75 Beasts (43 NPCs tracked) |
| 50094 | Wild Basin | Sholazar Basin | Kill 75 Beasts (29 NPCs tracked) |
| 50095 | Peak Predators | The Storm Peaks | Kill 75 Beasts (24 NPCs tracked) |
| 50096 | Peak Predators | Icecrown | Kill 75 Beasts (12 NPCs tracked) |
| 50145 | Fjord Front | Howling Fjord | Complete 6 quests |
| 50149 | Basin Expeditions | Sholazar Basin | Complete 6 quests |
| 50150 | Storm Peak Orders | The Storm Peaks | Complete 6 quests |
| 50151 | Icecrown Advance | Icecrown | Complete 6 quests |

### NPC Data

- **classicNPCFixes.lua**: Injected spawn coordinates for NPC 14224 (7:XT \<Long Distance Recovery Unit\>, Badlands). The native `wotlkNpcDB` entry for ID 14224 is a different NPC (Gnomeregan's Instance Recovery Unit) and `classicNpcDB` had no entry — all 74 Wowhead patrol coordinates for zone 3 (Badlands) were injected.

### Bug Fixes

- **[UI]** Fixed spammy `[CRITICAL] No AreaId found for UiMapId` errors appearing in chat when entering Ascension hub cities (Stormwind, Darnassus, Shattrath, etc.). On Ascension, `C_Map.GetBestMapForUnit("player")` returns a continent-level UiMapId for these cities — Questie logged a CRITICAL error since continent maps have no AreaId mapping, even though the `nil` return was already handled gracefully by callers. Downgraded from `DEBUG_CRITICAL` to `DEBUG_DEVELOP` in `zoneDB.lua`.

## v9.8.8

### New Ebonhold Quests

- **Azeroth**: Alterac Trophy (includes missing Alterac Mountains spawn tracking data for Narillasanz, Cranky Benj, Gravis Slipknot, Araga, Lo'Grosh, Stone Fury, Jimmy the Bleeder, Skhowl). Northern Jungle Trophy (verified Stranglethorn Vale spawn tracking data). Southern Jungle Trophy (verified Stranglethorn Vale spawn tracking data for 4 rares).
- **Kalimdor**: Ashen Corruption (includes missing Ashenvale spawn tracking data for Demon NPCs), Spires of Chaos (includes missing Thousand Needles spawn tracking data for Elemental NPCs).
- **Outland**: Shadowmoon Trophy (verified Shadowmoon Valley spawn tracking data for Collidus the Warp-Watcher, Ambassador Jerrikar, Kraator). Demon's at the Edge (verified Blade's Edge Mountains spawn tracking data for 37 demons).
- **Northrend**: Fjord Trophy (includes missing Howling Fjord spawn tracking data for King Ping, Perobas the Bloodthirster, Vigdis the War Maiden). Frostbound Brood (verified Borean Tundra spawn tracking data for 16 dragonkin).

## v9.8.7

### Fixes

- **[Quest]** Corrected `GetQuestLogTitle` return value indices across multiple modules to match the WoW 3.3.5 client API. The 3.3.5 client returns `suggestedGroup` at index 4, shifting `isHeader` to index 5 and `questId` to index 9. Affected modules previously used indices 4 and 8 (or `select(8, ...)`) and would misidentify quest headers as regular quests and incorrectly assign `isDaily` as `questId`.
- **[Quest]** Removed premature `break` on nil `title` in quest log iteration loops. On this server, quest log slots can be non-contiguous, causing early loop termination to silently skip valid quests. Loops now use a `if title and (not isHeader) then` guard to safely skip empty slots without aborting iteration.
- **Affected modules:** `QuestieValidateGameCache`, `QuestEventHandler`, `QuestLogCache`, `TooltipHandler`, `TrackerUtils`, `QuestieTracker`, `QuestieLearner`.

## v9.8.6

### New Ebonhold Quests

- **Outland**: Blade's Edge Trophy (includes missing Blade's Edge Mountains spawn tracking data for Morcrush, Hemathion, Speaker Mar'grom). Fel Scars of Nagrand (includes missing Nagrand spawn tracking data for Voidwalker Minions, etc). Netherstorm Trophy (includes missing Netherstorm spawn tracking data for Nuramoc, Ever-Core the Punisher, Chief Engineer Lorthander).
- **Northrend**: Borean Trophy (includes missing Borean Tundra spawn tracking data for Fumblub Gearwind, Icehorn, Old Crystalbark).
- **Kalimdor**: Teldrassil Trophy (includes missing Teldrassil spawn tracking data for Threggil, Blackmoss the Fetid, Duskstalker, Uruson, Fury Shelda, Grimmaw). Darkshore Defense (complete 6 quests in Darkshore). Bloodmyst Recovery (complete 6 quests in Bloodmyst Isle).
- **Azeroth**: Arathi Trophy (includes missing Arathi Highlands spawn tracking data for Darbel Montrose, Singer, Foulbelly, Ruul Onestone, Kovork, Molok the Crusher, Zalas Witherbark, Nimar the Slayer, Geomancer Flintdagger, Prince Nazjak). Elwynn Errands (complete 6 quests in Elwynn Forest). Modan Trophy (includes missing Loch Modan spawn tracking data for Grizlak, Magosh, Large Loch Crocolisk, Shanda the Spinner, Lord Condar, Emogg the Crusher, Boss Galgosh). Redridge Resolve (complete 6 quests in Redridge Mountains). Westfall Trophy (includes missing Westfall spawn tracking data for Foe Reaper 4000, Marisa du'Paige, Vultros, Brack, Brainwashed Noble, Leprithus, Master Digger, Sergeant Brashclaw, Slark). Wetlands Trophy (includes missing Wetlands spawn tracking data for Dragonmaw Battlemaster, Razormaw Matriarch, Garneg Charskull, Gnawbone, Sludginn, Ma'ruk Wyrmscale, Leech Widow, Mirelow).

## v9.8.4

### Fixes

- **[Quest]** Fixed a Lua crash ("attempt to index global 'QuestiePlayer'") occurring during chat message processing for auto-completing quests, by explicitly requiring the `QuestiePlayer` module in `QuestEventHandler`.

## v9.8.3

### Fixes

- **[Quest]** Extended `HideCondition` support to regular monster, object, and item objectives in the database.
- **[Quest]** Added `hideIfQuestActive` conditions to quest 13010 objectives to resolve icon overlap at King Jokkum.
- **[Database]** Corrected the finisher for "You Can't Miss Him" (12966) to NPC 30127, properly moving the arrow to Fjorn's Anvil.
- **[Arrow]** Implemented immediate arrow refreshing upon quest acceptance to provide seamless transitions between objective phases.

## v9.8.2

### Fixes

- **[Quest]** Updated the objective tooltip for "Forging an Alliance" (12924) at King Jokkum to explicitly instruct players to pick up the breadcrumb quest "You Can't Miss Him" (12966).

## v9.8.1

### Fixes

- **[Quest]** Fixed QuestieArrow direction for "Forging an Alliance" (12924). Added an extra objective to speak with King Jokkum, ensuring the arrow points toward the breadcrumb quest start at the beginning of the quest.

## v9.8.0

### Fixes

- **[Quest]** Modified `BAG_UPDATE_DELAYED` to trigger a quest log update and instantly refresh the tracker when items are deposited directly into bags by autoloot bots that bypass standard item events.
- **[Map]** Fixed an issue where "Special Objectives" (e.g., source item drops) failed to check player bag contents upon completion, causing their map icons to linger indefinitely until the main quest was turned in.

## v9.7.12

### Fixes

- **[Quest]** Fixed an issue where tracking icons for dynamically updated custom quests like Peak Predators would prematurely disappear due to sync delays on WotLK servers.
- **[Map]** Resolved a frame pool leak that prevented the yellow Finisher icon from appearing immediately on the map after turning in or completing a quest.

- **[Database]** Corrected an error that improperly identified Item Finishers as GameObject Finishers on custom servers, causing map pinpointing errors (e.g. `[QuestieDB:GetObject] rawdata is nil for objectID:`).
- **[Database]** Appended correct fallback spawn data for the "Thorim" listen bunny (`NPC 30514`) so Sibling Rivalry's turn in/listen point functions correctly on WotLK clients.

## v9.7.11

### Fixes

- **[Quest]** Fixed an issue where quest objective icons and waypoints failed to clear from the map after a quest was completed or abandoned.
- **[Tracker]** Prevented quests from falsely flagging as complete and wiping tracking data when the World of Warcraft server drops its objective arrays. Fixes "Peak Predators" icons disappearing randomly.
- **[Database]** Corrected an error that improperly identified Item Finishers as GameObject Finishers on custom servers, causing map pinpointing errors (e.g. `[QuestieDB:GetObject] rawdata is nil for objectID:`).
- **[Database]** Appended correct fallback spawn data for the "Thorim" listen bunny (`NPC 30514`) so Sibling Rivalry's turn in/listen point functions correctly on WotLK clients.

## v9.7.10

### Fixes

- **[Arrow]** Refactored Arrow logic to drastically improve target distance calculations and prioritize targets correctly based on the player's current zone.
- **[Arrow]** Fixed a bug where the Arrow would mistakenly point to previously completed objective locations instead of the Quest Finisher's exact location.
- **[Tracker]** Fixed `QuestieDB.IsComplete` edge case returning incomplete incorrectly; now verifies `numFulfilled == numRequired` to immediately acknowledge completed quests while awaiting the server flag.
- **[Tracker]** Resolved false-positive "broken quest log" errors spamming chat on WotLK servers by correctly handling API responses for trackable objectives.
- **[Tracker]** Demoted harmless WotLK objective cache count mismatches from Error to Debug visibility level to eliminate chat spam on login.
- **[Quest]** Fixed quest arrow pointing to the key-drop NPC after using all consumable quest keys (e.g. Cold Iron Key for "They Took Our Men!" quest 12843). When a quest uses a key item that is consumed on interaction, it leaves the bag and `CheckQuestSourceItem` returns false, incorrectly triggering a quest reset that re-drew the key source NPC on the map. Now checks if all tracked objectives are already `Completed=true` before applying the reset, preventing the spurious icon.

## v9.7.9

### Fixes

- **[Quest]** Fixed tracker objective count staying stale (e.g. stuck at 14/16 when quest is complete) when an autoloot bot bypasses the standard loot frame. Registered `BAG_UPDATE_DELAYED` event to force a full quest log scan on bag changes, catching progress updates that `QUEST_WATCH_UPDATE` would normally fire for manual looting.

## v9.7.8

### Fixes

- **[Quest]** Fixed "There was an error populating objectives" error in chat for `triggerEnd` quests with no map coordinates (e.g., "complete N quests in zone"). `_RegisterObjectiveTooltips` now silently returns for `event`-type objectives with no `spawnList` — these have nothing to register a tooltip for.

## v9.7.7

### Fixes

- **[Quest]** Fixed "Missing event data for Objective" error appearing in chat for all `triggerEnd` quests with no map coordinates (e.g., "complete N quests in zone" types). Nil coordinates are valid for server-tracked objectives with no pin — the handler now returns silently instead of logging a visible error.

## v9.7.6

### Fixes

- **[Database]** Fixed "Missing objective data" error for all "complete N quests in zone" quest types (IDs 50151, 50145, 50098, 50100, 50149, 50099, 50108, 50111, 50150). Added `triggerEnd` (`[9]`) field so Questie correctly registers the server-tracked objective without drawing map pins.

## v9.7.5

### Fixes

- **[Quest]** Fixed objective pins/icons persisting on the map after a quest is completed or abandoned. Added `CleanupRemovedQuestsFallback` which diffs Questie's quest log against the game's actual quest log on every `QUEST_LOG_UPDATE` and correctly calls `CompleteQuest` or `AbandonedQuest` for any quest that silently disappeared, ensuring map icons are removed.
- **[Quest]** Fixed re-accepted repeatable custom quests (e.g., Stormforged Scales) not showing objective icons on the map after being accepted a second time.

### New Quests

- **[Database]** Added **Storm Peak Orders** (ID 50150) - *The Storm Peaks*
  - Objective: Complete any 6 quests in The Storm Peaks.
- **[Database]** Added **Wild Basin** (ID 50094) - *Sholazar Basin*
  - Objective: Kill 75 Beasts. Includes 29 Beast NPC types with full spawn coordinates.
  - NPCs: King Krush, Shardhorn Rhino, Aotona, Pitch, Serfex the Reaver, Dreadsaber, Hardknuckle Matriarch, Shango, Venomtip, Bushwhacker, Hardknuckle Charger, Ravenous Mangal Crocolisk, Farunn, Zeptek the Destroyer, Goretalon Matriarch, Sapphire Hive Wasp, Emperor Cobra, Sapphire Hive Drone, Shattertusk Bull, Siltslither Eel, Spirit of Atha, Stranded Thresher, Mangal Crocolisk, Spirit of Koosu, Longneck Grazer, Goretalon Roc, Sapphire Hive Queen, Spirit of Ha-Khalan, Bittertide Hydra

## v9.7.4

### Fixes

- **[Tooltips]** Fixed "attempt to concatenate local 'name' (a nil value)" error when quest starters/finishers have missing names in the database.
- **[Database]** Added missing spawn coordinates for Quest 50031 "Stormbound" elementals in Storm Peaks (zone 67).
- **[Database]** Fixed "Unknown Zone" issue for custom quests by correcting Zone ID index usage (swapped `[6]` RequiredRaces for `[17]` ZoneID).
- **[Database]** Corrected Dragonblight Zone ID in custom quest definitions.

### New Quests

- **[Database]** Added **Morogh Missions** (ID 50098) - *Dun Morogh*
  - Objective: Complete any 6 quests in Dun Morogh. Auto-completes upon reaching the objective.
- **[Database]** Added **Azuremyst Aid** (ID 50100) - *Azuremyst Isle*
  - Objective: Complete any 6 quests in Azuremyst Isle. Auto-completes upon reaching the objective.
- **[Database]** Added **Stormforged Scales** (ID 50066) - *The Storm Peaks*
  - Objective: Kill 30 Dragonkin. Includes 8 Dragonkin NPC types with full spawn coordinates.
- **[Database]** Added **Peak Predators** (ID 50095) - *The Storm Peaks*
  - Objective: Kill 75 Beasts. Includes 24 Beast NPC types with full spawn coordinates.
- **[Database]** Added **Peak Predators** (ID 50096) - *Icecrown*
  - Objective: Kill 75 Beasts. Includes 12 Beast NPC types with full spawn coordinates.
- **[Database]** Added **Icecrown Advance** (ID 50151) - *Icecrown*
  - Objective: Complete any 6 quests in Icecrown. Auto-completes upon reaching the objective.
- **[Database]** Added **Storm Peaks Trophy** (ID 50205) - *The Storm Peaks*
  - Objective: Kill 1 Rare in The Storm Peaks. Includes 4 Rare NPC types (Skoll, Time-Lost Proto-Drake, Vyragosa, Dirkee) with full spawn coordinates.

## v9.7.3

### New Features

- **[Database]** Implemented **Ebonhold Database Module**.
  - Created dedicated `Database/Ebonhold/` structure for custom server data.
  - Added `EbonholdLoader` to inject custom Quests, NPCs, Objects, and Items as overrides.
  - **Note:** This structure preserves custom data during upstream Questie updates.
- **[Objectives]** Implemented **Automated Text Retrieval**.
  - Questie now attempts to fetch quest text from the server at runtime for custom quests that are missing from the database.
  - Added "Objectives Board" (ID 600600) as a global quest starter.

### Quests (Custom Content)

- **[New]** Added **Heart of the Dragonflights** (ID 50064) - *Dragonblight*
  - Objective: Kill 30 Dragonkin. Includes 49 Dragonkin NPC types.
- **[New]** Added **Skies of Blade's Edge** (ID 50060) - *Blade's Edge Mountains*
  - Objective: Kill 75 Dragonkin. Includes 17 Dragonkin NPC types.
- **[New]** Added **Shadowed Beasts** (ID 50087) - *Shadowmoon Valley*
  - Objective: Kill 75 Beasts. Includes 25 Beast NPC types.
- **[New]** Added **Forest Stalkers** (ID 50083) - *Terokkar Forest*
  - Objective: Kill 75 Beasts. Includes 53 Beast NPC types.
- **[New]** Added **Savage Heights** (ID 50085) - *Blade's Edge Mountains*
  - Objective: Kill 75 Beasts. Includes 47 Beast NPC types.
- **[New]** Added **Unstable Fauna** (ID 50086) - *Netherstorm*
  - Objective: Kill 75 Beasts. Includes 18 Beast NPC types.
- **[New]** Added **Elemental Balance** (ID 50026) - *Nagrand*
  - Objective: Kill 30 Elementals. Includes 12 Elemental NPC types.
- **[New]** Added **Redridge Trophy** (ID 50160) and **Zangarmarsh Trophy** (ID 50192).

### New Ascension Quests

- **Westfall**: Agria's Medicine, Seven Years of Bad Luck, Worm-Eaten Apple, Goldshire's Generosity, Bookworm, Knowledge Corrupts, The Ruins of Northshire, Accursed Sisterhood, Words That Shepherd Madness, Oracular Idol, A Betrayal Within, The Maid I Left Behind, The Saddest Among Us, The Threat Swept Downstream, Stay a While, Defias Disruption.
- **Dun Morogh**: A Small Mistake, We Found Her!, The Scout's Favor, Old Mirsinth, Smoke on the Wind, A Promising Path, A Fitting Disguise, His Radiant Majesty, Deciphering Radiation, Soaking the Masses, Sever the Right Hand, A Growing Business, Thunderbrew's Hop, Stay a While, Live-Fire Demo, Bots on Strike, A Brother's Betrayal, The True Story, Timber for the Coldhewn, Icehide the Unbroken.
- **Teldrassil**: The Carrion Road, The Sister Who Never Returned, Finding the Good Meat, Transsubstantiating the Flesh, Communion Banquet, A Trail of Petals, Restless entrails, A Dark Warning, The Aid of Theren-Dion, No Place for Scavengers, Termites in Teldrassil, Stay a While, Elydna's Heirloom.
- **Durotar**: To Find a Cure, A Dangerous Sample, Knowledge of the Centaurs, Those Who Fell, The Way is Shut, The Sinister Triad, So That He May Hear Again, A Sinister Ritual, Innocents for Sinners, Unease Makes Tongues Wag, A Door Left Ajar, Esgramor's Master, Shinies!, Echoes of Hirsutta, Auction the Past, Stay a While, Durotar's Dire Drought, The Queen's Decree, Avianna's Rose, The Last Piece, Reversion.
- **Tirisfal Glades**: Rude Awakening, Marla's Last Wish, Monsters With Noble Intentions, Restless Family Members, An Unspeakable Secret, A Noble Heritage, The True Heir of the Cains, The Friends We Make Along the Way, I'm Home, Apothecary Flemer, The Nature of Freedom, Spotless Standing, Stay a While, More Than the Sum of its Parts, Scarlet Correspondence, A Humble Duty, The Balnirs' Rest, Brewing Disarray, This Is Justice.
- **Mulgore**: Death and Tribute, Death and Exile, Death and Dishonor, Death and Justice, Death by Laughter, To Whom I Devote, Fighting Over Carrion, Smoke on the Horizon, Amphora of Sacred Water, Stay a While, Exile of Embers, The Smoke that Remembers, The Circle’s Rite.

### New Ebonhold Quests

- **Outland**: Elemental Balance, Savage Heights, Unstable Fauna, Forest Stalkers, Marsh Predators, Skies of Blade's Edge, Shadowed Beasts, Zangarmarsh Trophy.
- **Northrend**: Tundra Turbulence, Stormbound, Dragonblight Trophy, Heart of the Dragonflights, Peak Predators, Icecrown Advance, Storm Peaks Trophy, Stormforged Scales, Fjord Front, Wild Basin, Grizzly Trophy, Zul'Drak Trophy, Basin Expeditions.
- **Azeroth**: Redridge Trophy, Morogh Missions, Azuremyst Aid, Shadow of Teldrassil, Trials of Durotar, Song of the Woods, Morogh Trophy, Tirisfal Trophy.

### Fixes

- **[Tracker]** **Combat Update Fix**: Tracker now updates objectives immediately during combat without causing Lua errors or taint.
- **[Tracker]** **Bag Update Fix**: Quest progress now updates immediately when looting items (fixes delay with loot bots).
- **[Arrow]** **Refined Visibility Logic**:
  - **Auto Nearby**: Arrow correctly defaults to showing the nearest quest when no quests are tracked.
  - **Zone Filter**: In "Auto Mode", the arrow hides if the nearest quest is in a different zone.
  - **Instance Filter**: Arrow explicitly hides if the target is in a different instance.
- **[Map]** Fixed an issue where completed quest icons would persist on the map (`RequestMapUpdate` logic).
- **[Database]** Updated `wotlkNpcDB.lua` with scraped spawn data for 12 key beast NPCs in Terokkar Forest to ensure accuracy.
- **[Arrow]** Fixed a nil function error for `_CollectObjective` when processing incomplete quests.
- **[Arrow]** Fixed syntax issues that prevented `QuestieArrow` module from initializing correctly.
- **[Database]** Fixed a runtime crash in `ZoneDB` when encountering maps with no AreaId mapping (e.g., Kalimdor).

## Session 35 (2026-05-03)

### Housekeeping

- **Discord relay housekeeping** — Discord thread routing config refreshed, stale webhook references cleaned up, no functional addon changes.
