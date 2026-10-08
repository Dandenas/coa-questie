"""Builds the Questie-X-CoADB plugin from the CoA server's quest export.

Only what differs from Questie-X's stock WotLK database (and its Ascension plugin) is written:
  - NEW quests (not in either): full records, plus full records for the NPCs, objects and items they need
    that Questie doesn't know, and the drop sources of their quest items.
  - CHANGED quests (different givers/turn-ins, level or name): only the fields that differ.
  - NPCs / objects that give or take a new or changed quest: their questStarts / questEnds lists, computed
    from the whole export (Questie merges plugin data field by field, so stock spawns etc. stay).
Spawn positions are converted from world coordinates to zone map percentages with the client's
WorldMapArea.dbc (coords.py).

    python build_coadb.py <export.json.gz>      writes ./Questie-X-CoADB and prints a report
"""
import collections, gzip, json, os, re, shutil, sys

from coords import Zones

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "Questie-X-CoADB")
CHUNK = 2500  # records per data file (keeps each Lua function well under the constant limit)
ALLIANCE, HORDE = 1 | 4 | 8 | 64 | 1024, 2 | 16 | 32 | 128 | 512
OPEN_WORLD = (0, 1, 530, 571)

export = json.load(gzip.open(sys.argv[1], "rt", encoding="utf-8"))
zones = Zones()
for m in zones.rects:  # CoA's own sub-map areas (10000+) fold into their top-level zone
    zones.rects[m] = [r for r in zones.rects[m] if r[0] < 10000]

# ---- stock index (dump_stock.lua) ----
SQ, SN, SO, SI = {}, set(), set(), set()
def ids(s):
    return set(int(x) for x in s.split(",") if x.strip().lstrip("-").isdigit())
for line in open(os.path.join(HERE, "stock_index.tsv"), encoding="utf-8", errors="replace"):
    p = line.rstrip("\n").split("\t")
    kind, oid = p[0][1], int(p[1])
    if kind == "Q":
        SQ[oid] = dict(src=p[0][0], name=p[2], cs=ids(p[3]), os=ids(p[4]), its=ids(p[5]), ce=ids(p[6]), oe=ids(p[7]),
                       lvl=p[8], qlvl=p[9])
    elif kind == "N":
        SN.add(oid)
    elif kind == "O":
        SO.add(oid)
    elif kind == "I":
        SI.add(oid)

Q = {q["ID"]: q for q in export["quests"]}
C = {c["entry"]: c for c in export["creatures"]}
G = {g["entry"]: g for g in export["gameobjects"]}
I = {i["entry"]: i for i in export["items"]}
src = export["item_sources"]

# FactionTemplate.dbc: ID, Faction, Flags, FactionGroup, FriendGroup, EnemyGroup, ... (groups: 1 player,
# 2 Alliance, 4 Horde, 8 monster). Hostile to a side if its group (or all players) is an enemy; neutral
# (yellow) NPCs count as usable by both.
from coords import read_dbc
templates = {ints[0]: (ints[3], ints[4], ints[5]) for ints, _, _ in read_dbc("FactionTemplate.dbc")}


def sides(template_id):
    group, friend, enemy = templates.get(template_id, (0, 0, 0))
    out = ""
    for letter, bit in (("A", 2), ("H", 4)):
        if enemy & bit or enemy & 1:
            continue
        out += letter
    return out or None


def friendly(entry):
    c = C.get(entry)
    return sides(c["faction"]) if c else None




def clean(text):
    if not text:
        return None
    text = text.replace("$B", " ").replace("$b", " ")
    text = re.sub(r"\$[Nn]", "<name>", text)
    text = re.sub(r"\$[Cc]", "<class>", text)
    text = re.sub(r"\$[Rr]", "<race>", text)
    text = re.sub(r"\$[Gg]([^:;]*):([^;]*);", r"\1", text)
    return re.sub(r"\s+", " ", text).strip() or None


def starters(q):
    s = q.get("starters", {})
    return set(s.get("creature", [])), set(s.get("gameobject", [])), set(s.get("item", []))


def enders(q):
    e = q.get("enders", {})
    return set(e.get("creature", [])), set(e.get("gameobject", []))


def spawns(rows):
    out = collections.OrderedDict()
    for s in rows:
        if s["map"] not in OPEN_WORLD:
            continue
        loc = zones.locate(s["map"], s["position_x"], s["position_y"])
        if loc:
            out.setdefault(loc[0], []).append([loc[1], loc[2]])
    return out


def main_zone(sp):
    return max(sp, key=lambda z: len(sp[z])) if sp else None


# ---- classify quests ----
new, changed = [], {}
for qid, q in Q.items():
    s = SQ.get(qid)
    cs, os_, its = starters(q)
    ce, oe = enders(q)
    if not s:
        new.append(qid)
        continue
    diff = {}
    if s["name"] != q["LogTitle"]:
        diff[1] = q["LogTitle"]
    if s["cs"] != cs or s["os"] != os_ or s["its"] != its:
        diff[2] = [sorted(cs) or None, sorted(os_) or None, sorted(its) or None]
    if s["ce"] != ce or s["oe"] != oe:
        diff[3] = [sorted(ce) or None, sorted(oe) or None]
    if str(q["MinLevel"]) != s["lvl"]:
        diff[4] = q["MinLevel"]
    if str(q["QuestLevel"]) != s["qlvl"]:
        diff[5] = q["QuestLevel"]
    if diff:
        changed[qid] = diff

# exclusive groups (ExclusiveGroup > 0: only one of the group can be done)
groups = collections.defaultdict(list)
for qid, q in Q.items():
    eg = (q.get("addon") or {}).get("ExclusiveGroup", 0)
    if eg > 0:
        groups[eg].append(qid)

# ---- item drop sources ----
loot_to_creatures = collections.defaultdict(set)
for r in src["creature_lootid_to_entry"]:
    loot_to_creatures[r["lootid"]].add(r["entry"])
loot_to_objects = collections.defaultdict(set)
for r in src["gameobject_lootid_to_entry"]:
    loot_to_objects[r["lootid"]].add(r["entry"])
ref_items = collections.defaultdict(set)  # reference id -> items
for r in src["reference_loot"]:
    ref_items[r["Entry"]].add(r["Item"])
npc_drops, obj_drops, item_drops, vendors = (collections.defaultdict(set) for _ in range(4))
for r in src["creature_loot"]:
    for e in loot_to_creatures.get(r["Entry"], ()):
        npc_drops[r["Item"]].add(e)
for r in src["creature_loot_via_reference"]:
    for item in ref_items.get(r["Reference"], ()):
        for e in loot_to_creatures.get(r["Entry"], ()):
            npc_drops[item].add(e)
for r in src["gameobject_loot"]:
    for e in loot_to_objects.get(r["Entry"], ()):
        obj_drops[r["Item"]].add(e)
for r in src["gameobject_loot_via_reference"]:
    for item in ref_items.get(r["Reference"], ()):
        for e in loot_to_objects.get(r["Entry"], ()):
            obj_drops[item].add(e)
for r in src["item_loot"]:
    item_drops[r["Item"]].add(r["Entry"])
for r in src["vendors"]:
    vendors[r["item"]].add(r["entry"])

# ---- full quest records for new quests ----
quest_out = {}
need_npc, need_obj, need_item = set(), set(), set()
for qid in new:
    q, a = Q[qid], (Q[qid].get("addon") or {})
    cs, os_, its = starters(q)
    ce, oe = enders(q)
    creature_obj, object_obj, killcredit = [], [], []
    for i in range(1, 5):
        oid, txt = q.get("RequiredNpcOrGo%d" % i, 0), clean(q.get("ObjectiveText%d" % i))
        if oid > 0:
            c = C.get(oid, {})
            sources = c.get("killcredit_sources") or []
            if sources and not c.get("spawns"):
                killcredit.append([sorted(sources), oid, txt])
                need_npc.update(sources)
            else:
                creature_obj.append([oid, txt])
                need_npc.add(oid)
        elif oid < 0:
            object_obj.append([-oid, txt])
            need_obj.add(-oid)
    item_obj = []
    for i in range(1, 7):
        iid = q.get("RequiredItemId%d" % i, 0)
        if iid:
            item_obj.append([iid])
            need_item.add(iid)
    rep = None
    if q.get("RequiredFactionId1"):
        rep = [q["RequiredFactionId1"], q.get("RequiredFactionValue1", 0)]
    objectives = None
    if creature_obj or object_obj or item_obj or rep or killcredit:
        objectives = [creature_obj or None, object_obj or None, item_obj or None, rep, killcredit or None]
    trigger = None
    for t in q.get("areatriggers") or []:
        loc = zones.locate(t["map"], t["x"], t["y"])
        if loc:
            trigger = [clean(q.get("ObjectiveText1")) or q["LogTitle"], {loc[0]: [[loc[1], loc[2]]]}]
            break
    prev = a.get("PrevQuestID", 0)
    eg = a.get("ExclusiveGroup", 0)
    races = q["AllowableRaces"] or 0
    if races == 0 and cs:
        # "any race" on the server, but a hostile giver keeps the other faction away; tell Questie
        giver_sides = {friendly(e) for e in cs}
        if giver_sides == {"A"}:
            races = ALLIANCE
        elif giver_sides == {"H"}:
            races = HORDE
    rec = {
        1: q["LogTitle"],
        2: [sorted(cs) or None, sorted(os_) or None, sorted(its) or None],
        3: [sorted(ce) or None, sorted(oe) or None],
        4: q["MinLevel"], 5: q["QuestLevel"], 6: races,
        7: a.get("AllowableClasses") or None,
        8: [clean(q.get("LogDescription"))] if clean(q.get("LogDescription")) else None,
        9: trigger, 10: objectives,
        11: q.get("StartItem") or None,
        13: [prev] if prev > 0 else None,
        16: [x for x in groups[eg] if x != qid] or None if eg > 0 else None,
        17: q.get("QuestSortID") or None,
        18: [a["RequiredSkillID"], a.get("RequiredSkillPoints", 0)] if a.get("RequiredSkillID") else None,
        19: [a["RequiredMinRepFaction"], a.get("RequiredMinRepValue", 0)] if a.get("RequiredMinRepFaction") else None,
        20: [a["RequiredMaxRepFaction"], a.get("RequiredMaxRepValue", 0)] if a.get("RequiredMaxRepFaction") else None,
        21: [q["ItemDrop%d" % i] for i in range(1, 5) if q.get("ItemDrop%d" % i)] or None,
        22: q.get("RewardNextQuest") or None,
        23: q.get("Flags") or None, 24: a.get("SpecialFlags") or None,
        25: -prev if prev < 0 else None,
        30: a.get("MaxLevel") or None,
    }
    quest_out[qid] = rec
    need_npc |= cs | ce
    need_obj |= os_ | oe
    need_item |= its
    if q.get("StartItem"):
        need_item.add(q["StartItem"])
for qid, diff in changed.items():
    quest_out[qid] = diff
    if 2 in diff:
        need_npc |= set(diff[2][0] or []); need_obj |= set(diff[2][1] or []); need_item |= set(diff[2][2] or [])
    if 3 in diff:
        need_npc |= set(diff[3][0] or []); need_obj |= set(diff[3][1] or [])

# drop sources of the new quests' items
for iid in list(need_item):
    need_npc |= npc_drops.get(iid, set())
    need_obj |= obj_drops.get(iid, set())

# ---- quest giver / turn-in lists from the whole export ----
starts_n, ends_n, starts_o, ends_o = (collections.defaultdict(set) for _ in range(4))
races_by_npc = collections.defaultdict(set)
for qid, q in Q.items():
    cs, os_, _ = starters(q)
    ce, oe = enders(q)
    for e in cs: starts_n[e].add(qid); races_by_npc[e].add(q["AllowableRaces"] or 0)
    for e in ce: ends_n[e].add(qid); races_by_npc[e].add(q["AllowableRaces"] or 0)
    for e in os_: starts_o[e].add(qid)
    for e in oe: ends_o[e].add(qid)
new_or_changed = set(new) | set(changed)


npc_out, obj_out, item_out = {}, {}, {}
for e in sorted(need_npc):
    c = C.get(e)
    if not c:
        continue
    gives = starts_n.get(e, set()) | ends_n.get(e, set())
    if e in SN:
        if gives & new_or_changed:
            npc_out[e] = {10: sorted(starts_n.get(e, ())) or None, 11: sorted(ends_n.get(e, ())) or None}
        continue
    sp = spawns(c.get("spawns") or [])
    npc_out[e] = {1: c["name"], 2: 0, 3: 0, 4: c["minlevel"], 5: c["maxlevel"], 6: c["rank"],
                  7: sp or None, 9: main_zone(sp),
                  10: sorted(starts_n.get(e, ())) or None, 11: sorted(ends_n.get(e, ())) or None,
                  12: c["faction"], 13: friendly(e), 14: c.get("subname") or None, 15: c.get("npcflag") or None}
for e in sorted(need_obj):
    g = G.get(e)
    if not g:
        continue
    gives = starts_o.get(e, set()) | ends_o.get(e, set())
    if e in SO:
        if gives & new_or_changed:
            obj_out[e] = {2: sorted(starts_o.get(e, ())) or None, 3: sorted(ends_o.get(e, ())) or None}
        continue
    sp = spawns(g.get("spawns") or [])
    obj_out[e] = {1: g["name"], 2: sorted(starts_o.get(e, ())) or None, 3: sorted(ends_o.get(e, ())) or None,
                  4: sp or None, 5: main_zone(sp)}
related = collections.defaultdict(set)
for qid in new:
    q = Q[qid]
    for i in range(1, 7):
        if q.get("RequiredItemId%d" % i):
            related[q["RequiredItemId%d" % i]].add(qid)
for iid in sorted(need_item):
    it = I.get(iid)
    if not it:
        continue
    drops = sorted(npc_drops.get(iid, ())) or None, sorted(obj_drops.get(iid, ())) or None
    if iid in SI:
        if drops[0] or drops[1]:
            item_out[iid] = {2: drops[0], 3: drops[1]}
        continue
    item_out[iid] = {1: it["name"], 2: drops[0], 3: drops[1], 4: sorted(item_drops.get(iid, ())) or None,
                     5: it.get("startquest") or None, 7: it.get("Flags") or None, 9: it.get("ItemLevel"),
                     10: it.get("RequiredLevel"), 12: it.get("class"), 13: it.get("subclass"),
                     14: sorted(vendors.get(iid, ())) or None, 15: sorted(related.get(iid, ())) or None}


# ---- Lua output ----
def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return ("%.2f" % v).rstrip("0").rstrip(".")
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'
    if isinstance(v, dict):
        return "{" + ",".join("[%s]=%s" % (lua(k), lua(x)) for k, x in v.items() if x is not None) + "}"
    if isinstance(v, (list, tuple)):
        if all(x is not None for x in v):
            return "{" + ",".join(lua(x) for x in v) + "}"
        return "{" + ",".join("[%d]=%s" % (i + 1, lua(x)) for i, x in enumerate(v) if x is not None) + "}"
    raise TypeError(type(v))


if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(os.path.join(OUT, "Data"))
files = []
for table, data, stem in (("questData", quest_out, "CoAQuestDB"), ("npcData", npc_out, "CoANpcDB"),
                          ("objectData", obj_out, "CoAObjectDB"), ("itemData", item_out, "CoAItemDB")):
    keys = sorted(data)
    for n, start in enumerate(range(0, max(len(keys), 1), CHUNK), 1):
        name = "%s_%d.lua" % (stem, n)
        with open(os.path.join(OUT, "Data", name), "w", encoding="utf-8", newline="\r\n") as f:
            f.write("-- Generated by tools\\questie-x\\coadb\\build_coadb.py from the CoA server's world DB. Do not edit.\n")
            f.write("local _, addonTable = ...\naddonTable.%s = addonTable.%s or {}\nlocal d = addonTable.%s\n"
                    % (table, table, table))
            for k in keys[start:start + CHUNK]:
                f.write("d[%d]=%s\n" % (k, lua(data[k])))
        files.append("Data\\" + name)

meta = export["meta"]
with open(os.path.join(OUT, "Questie-X-CoADB.toc"), "w", encoding="utf-8", newline="\r\n") as f:
    f.write("## Interface: 30300\n## Title: Questie-X |cFF00FF00[CoADB]|r\n"
            "## Notes: Conquest of Azeroth quest data for Questie-X, generated from the CoA server's world database\n"
            "## Author: CoA addons\n## Version: %s\n## RequiredDeps: Questie-X\n"
            "## OptionalDeps: Questie-X-WotLKDB, Questie-X-AscensionDB\n## X-Questie-Plugin-Name: CoA\n"
            "## X-CoA-Core: %s\n\nCoALoader.lua\n\n" % (meta["exported_at"][:10].replace("-", "."), meta["core_commit"][:8]))
    f.write("\n".join(files) + "\n")
with open(os.path.join(OUT, "CoALoader.lua"), "w", encoding="utf-8", newline="\r\n") as f:
    f.write('''-- Questie-X-CoADB: Conquest of Azeroth quests, NPCs, objects and items that differ from Questie-X's stock
-- WotLK data (new quests in full; changed quest givers/turn-ins/levels/names as single fields).
-- Loads only on the Ascension client (CoA runs on it). Injected at PLAYER_LOGIN, after the Ascension plugin.
local _, addonTable = ...

local function inject()
    if not (_G.C_CharacterAdvancement and QuestieLoader) then return end
    local api = QuestieLoader:ImportModule("QuestiePluginAPI")
    if not api then return end
    local plugin = api:RegisterPlugin("CoA")
    if not plugin then return end
    if addonTable.npcData then plugin:InjectDatabase("NPC", addonTable.npcData) end
    if addonTable.objectData then plugin:InjectDatabase("OBJECT", addonTable.objectData) end
    if addonTable.itemData then plugin:InjectDatabase("ITEM", addonTable.itemData) end
    if addonTable.questData then plugin:InjectDatabase("QUEST", addonTable.questData) end
    -- The plugin API lets fields from the Ascension plugin (Ascension's live servers) win over every other
    -- plugin. On a CoA server its own data is the truth, so re-apply ours on top for those records.
    local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    local function reapply(target, data)
        if type(target) ~= "table" or type(data) ~= "table" then return end
        for id, entry in pairs(data) do
            local existing = target[id]
            if type(existing) == "table" and existing ~= entry then
                for key, value in pairs(entry) do existing[key] = value end
            end
        end
    end
    if QuestieDB then
        reapply(QuestieDB.questDataOverrides, addonTable.questData)
        reapply(QuestieDB.npcDataOverrides, addonTable.npcData)
        reapply(QuestieDB.objectDataOverrides, addonTable.objectData)
        reapply(QuestieDB.itemDataOverrides, addonTable.itemData)
    end
    plugin:FinishLoading("CoA")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    inject()
end)
''')

asc_overlap = sorted(k for k in quest_out if SQ.get(k, {}).get("src") == "A")
print("quests: %d new (full), %d changed (fields: %s)" % (len(new), len(changed),
      dict(collections.Counter(f for d in changed.values() for f in d))))
print("npcs: %d (%d new full, %d giver/turn-in lists)" % (len(npc_out), sum(1 for v in npc_out.values() if 1 in v),
      sum(1 for v in npc_out.values() if 1 not in v)))
print("objects: %d (%d new full)" % (len(obj_out), sum(1 for v in obj_out.values() if 1 in v)))
print("items: %d (%d new full)" % (len(item_out), sum(1 for v in item_out.values() if 1 in v)))
print("new NPCs without open-world spawns: %d" % sum(1 for v in npc_out.values() if 1 in v and not v.get(7)))
print("quests also in the Ascension plugin (its fields win): %d" % len(asc_overlap))
print("files: %s" % ", ".join(files))
