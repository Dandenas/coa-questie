# Questie-X-WotLKDB

A [Questie-X](https://github.com/Xurkon/Questie-X) database plugin providing the full **Wrath of the Lich King (3.3.5)** quest, NPC, object, and item database — including TBC baseline data and expansion corrections.

---

## Requirements

- [Questie-X](https://github.com/Xurkon/Questie-X) must be installed. This plugin will not load without it.
- WoW client: 3.3.5a (WotLK)

---

## Installation

1. Download the latest release archive from the [Releases](https://github.com/Xurkon/Questie-X-WotLKDB/releases) page.
2. Extract it into your `Interface/AddOns/` directory.
3. The extracted folder **must** be named `Questie-X-WotLKDB`.
4. Ensure `Questie-X` is also present in `Interface/AddOns/`.
5. Reload your UI or restart the client.

Your addon list should look like:
```
Interface/AddOns/
  Questie-X/
  Questie-X-WotLKDB/
```

---

## What is Included

| Path | Contents |
|------|----------|
| `Database/Wotlk/Split/` | Quest, NPC, object, and item tables split into chunks for WoW 3.3.5 file-size compatibility |
| `Database/QuestXP/xpDB-wotlk.lua` | Quest XP reward data |
| `Database/Corrections/` | TBC and WotLK quest/NPC/item/object corrections |
| `Localization/` | Locale lookup tables (quest names, NPC names, etc.) |
| `Loader.lua` | Plugin entry point — registers data via `QuestiePluginAPI` |

---

## How It Works

`Loader.lua` fires on `PLAYER_LOGIN`, detects that split DB files have already been loaded into globals by the TOC, and registers the full dataset with `QuestiePluginAPI`. Questie-X merges this data into its runtime database at init time, enabling full quest tracking, map pins, and tooltip support for all WotLK content.

---

## Contributing

Submit quest data corrections, NPC fixes, or missing entries via pull request. See the existing correction files under `Database/Corrections/` for the expected format.

---

## License

MIT License