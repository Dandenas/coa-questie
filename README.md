# Questie-X for Conquest of Azeroth

[Questie-X](https://github.com/Xurkon/Questie-X), the quest helper (quest givers, objectives and turn-ins on the map and minimap, a quest arrow, a tracker), set up to work on **Conquest of Azeroth** (Ascension-based 3.3.5a) servers. It includes a **CoA quest database generated from a CoA server's own world database**.

This is an unofficial compatibility package. All credit for Questie-X and its databases goes to Xurkon and the Questie team.

## Install

1. Close the game.
2. Remove any older Questie (`Questie`, `Questie-335`, `PE-Questie`, an older `Questie-X`) from `Interface\AddOns\`.
3. Download this repository (Code → Download ZIP) and copy **all four folders** into `<your client>\Interface\AddOns\`:

   | Folder | What it is |
   |---|---|
   | `Questie-X` | The addon (1.6.4) with the CoA detection change |
   | `Questie-X-WotLKDB` | Base 3.3.5 quest/NPC/object/item data (1.4.8). The folder **must** keep this exact name |
   | `Questie-X-AscensionDB` | Ascension data (1.0.5) plus map sizes for CoA's own caves and sub-zones |
   | `Questie-X-CoADB` | CoA quests generated from a CoA server (see below) |

4. Start the game. After login, chat shows the Ascension plugin loading ("Plugin registered … Data injection complete").

If you also use Zygor or TomTom, turn off one of the quest arrows so they don't fight.

## What's changed for CoA

- **Server detection.** Questie-X and its Ascension plugin recognised Ascension only by realm *name* (Area 52, Bronzebeard, …). CoA servers can be called anything, so the Ascension client's own API (`C_CharacterAdvancement`) now counts too. Stock 3.3.5 clients are unaffected. The changes are one-line edits in:
  - `Questie-X\Modules\QuestieServer.lua`
  - `Questie-X\Compat\Compat.lua`
  - `Questie-X-AscensionDB\AscensionLoader.lua`
  - `Questie-X-AscensionDB\Zones\AscensionUiMapData.lua`
  - `Questie-X-AscensionDB\Zones\AscensionZoneTables.lua`
- **CoA caves and sub-zones.** `Questie-X-AscensionDB\Zones\CoAExtraZones.lua` adds map sizes for 26 CoA open-world maps the plugin doesn't know (Jangolode Mine, Gold Coast Quarry, Stillpine Hold, Dustwind Cave, Dun Kazad, …), taken from the client's `WorldMapArea.dbc`, so pins and the arrow work inside them.
- **CoA quests (`Questie-X-CoADB`).** Generated from a CoA server's world database (the [CoA AzerothCore repo](https://github.com/jealous-sound/azerothcore-wotlk-coa), core `8b1f3a0c`, 2026-10-08). It contains only what differs from Questie's stock data:
  - **325 new quests** (CoA's own), with givers, turn-ins, objectives, item drops and exploration spots;
  - **499 changed quests** (extra or different givers and turn-ins, levels, names);
  - the NPCs, objects and items those need.

  Quests the server marks "any race" but which only Alliance-friendly (or only Horde-friendly) NPCs give are marked for that faction, so the other faction doesn't see their markers.

## If your server is different

Servers built from a different CoA core (for example the CoA Server Manager's fork) or much newer or older versions may have quests that differ from this snapshot. You can rebuild `Questie-X-CoADB` from your own server with the tools below.

## Tools (`tools/`)

Requirements: Python 3 (standard library only), and Lua 5.1 for the stock-index and test scripts. Set `COA_CLIENT` to your client folder if it isn't `D:\COA Client`.

| Script | Does |
|---|---|
| `tools/gen_coa_maps.py` | Regenerates `CoAExtraZones.lua` from your client's `WorldMapArea.dbc` |
| `tools/mpq.py` | Minimal read-only MPQ reader used by the generators |
| `tools/coadb/questie-export.py` | **Runs on the server.** Read-only (`SELECT` only) export of the quests, NPCs, objects, items, spawns and drop sources Questie needs, as one `.json.gz` |
| `tools/coadb/dump_stock.lua` | Indexes Questie's stock WotLK/Ascension data for the comparison: `lua5.1 dump_stock.lua <AddOns>\Questie-X-WotLKDB <AddOns>\Questie-X-AscensionDB > stock_index.tsv` |
| `tools/coadb/build_coadb.py` | `python build_coadb.py <export.json.gz>` builds `Questie-X-CoADB` (only new and changed records; spawn positions converted with the client's map data) |
| `tools/coadb/test_coadb.lua` | Load test for the built plugin: `lua5.1 test_coadb.lua Questie-X-CoADB` |

To rebuild:
1. Run the exporter on your server and copy the `.json.gz` to your PC.
2. Run `dump_stock.lua`.
3. Run `build_coadb.py`.
4. Run `test_coadb.lua`.
5. Copy the new `Questie-X-CoADB` folder into `Interface\AddOns`.

## Known limits

- Holiday quests whose givers only appear during events are left to Questie's stock data.
- NPC spawns inside dungeons aren't included.
- The Ascension plugin's sub-zone "folding" table is left switched off on purpose: Questie would also point the parent zone at the sub-map and move the whole zone's pins onto a cave map.
- Questie-X itself is on hiatus upstream, so these are community fixes.

## Credits and licenses

- **Questie-X** by Xurkon and the Questie team ([Xurkon/Questie-X](https://github.com/Xurkon/Questie-X)): MIT, see `Questie-X/LICENSE`.
- **Questie-X-WotLKDB** and **Questie-X-AscensionDB** by the Questie-X team ([Questie-X-WotLKDB](https://github.com/Xurkon/Questie-X-WotLKDB), [Questie-X-AscensionDB](https://github.com/Xurkon/Questie-X-AscensionDB)). They're included here so the package works out of the box. If you're an author and want them removed or credited differently, please open an issue.
- **Questie-X-CoADB** and the tools: generated from a CoA server's world database (AzerothCore + CoA). Game data belongs to its respective owners.
