#!/usr/bin/env python3
"""Read-only export of quest data from an AzerothCore / Conquest of Azeroth (CoA) world database,
for building a Questie-X database plugin.

Only SELECT statements are sent (enforced in q()); nothing in any database is changed.
Output: one gzipped JSON document with raw values (coordinates are raw map/x/y/z world units; convert
them to zone map coordinates with the client's WorldMapArea.dbc when building the plugin).

Contents
  quests       quest_template + quest_template_addon for every quest with a starter, with its starters and
               enders (creature / gameobject / item) and exploration triggers (areatrigger_involvedrelation
               joined to the areatrigger table: map, x, y, z, radius, box size, orientation)
  creatures    creature_template for starters, enders, RequiredNpcOrGo > 0, entries whose KillCredit1/2 point at
               those, drop sources of quest items and vendors of quest items; all spawns; killcredit mapping
  gameobjects  gameobject_template for starters, enders, RequiredNpcOrGo < 0 and loot sources of quest items
               (chests: Data1 of type 3, fishing holes: Data1 of type 25); all spawns
  items        item_template for RequiredItemId, ItemDrop, StartItem and item starters; drop sources from
               creature/gameobject/item loot templates (reference loot resolved one level); npc_vendor rows
  meta         core commit (if --core-dir is given), export time, row counts, stock vs custom quest id counts

Connecting (pick one):
  local/remote MySQL   --host 127.0.0.1 --port 3306 --user acore
                       password: set MYSQL_PWD in the environment, or use --defaults-file with a [client] section
  MySQL in Docker      --docker-container <name>   (runs the mysql client inside that container; the password
                       is read from the container's own environment variable, --docker-password-env,
                       default MYSQL_ROOT_PASSWORD, with --user default root)

Examples
  MYSQL_PWD=... python3 questie-export.py --host 127.0.0.1 --user acore --out coa-questie-export.json.gz
  python3 questie-export.py --docker-container ac-database --core-dir /path/to/azerothcore --out export.json.gz

Requires Python 3.8+ and the mysql command-line client (locally, or inside the container). Takes about a
minute on a CoA-sized world database; best run outside heavy load.
"""
import argparse
import datetime
import gzip
import json
import os
import subprocess
import sys

CHUNK = 4000
STOCK_MAX_QUEST_ID = 26034   # highest quest id in stock 3.3.5a (12340); above = custom (CoA/Ascension)
ARGS = None                  # set in main()


def unescape(v):
    """mysql --batch escapes \\, tab, newline and NUL in values; NULL comes through as the word NULL."""
    if v == 'NULL':
        return None
    if '\\' not in v:
        return v
    out, i = [], 0
    while i < len(v):
        c = v[i]
        if c == '\\' and i + 1 < len(v):
            out.append({'n': '\n', 't': '\t', '0': '\0', '\\': '\\'}.get(v[i + 1], v[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def num(v):
    if v is None:
        return None
    try:
        return int(v)
    except ValueError:
        try:
            return float(v)
        except ValueError:
            return v


def mysql_command(sql):
    base = ['--batch', '--default-character-set=utf8mb4', ARGS.world_db, '-e']
    if ARGS.docker_container:
        user = ARGS.user or 'root'
        inner = (f'mysql -u{user} -p"${ARGS.docker_password_env}" --batch --default-character-set=utf8mb4 '
                 f'{ARGS.world_db} -e "$Q"')
        return ['docker', 'exec', '-e', 'Q=' + sql, ARGS.docker_container, 'sh', '-c', inner]
    cmd = [ARGS.mysql]
    if ARGS.defaults_file:
        cmd.append('--defaults-extra-file=' + ARGS.defaults_file)   # must come first
    cmd += ['-h', ARGS.host, '-P', str(ARGS.port)]
    if ARGS.user:
        cmd += ['-u', ARGS.user]
    return cmd + base + [sql]


def q(sql, numeric=True):
    """Run one read-only query in the world DB; returns a list of dicts."""
    if not sql.lstrip().upper().startswith('SELECT'):
        raise SystemExit('refusing a non-SELECT statement: ' + sql[:80])
    r = subprocess.run(mysql_command(sql), capture_output=True, text=True, encoding='utf-8', errors='replace')
    err = '\n'.join(l for l in r.stderr.splitlines() if 'Using a password' not in l)
    if r.returncode != 0:
        raise SystemExit(f'query failed: {err}\n{sql[:200]}')
    lines = r.stdout.split('\n')
    if not lines or not lines[0]:
        return []
    cols = lines[0].split('\t')
    rows = []
    for line in lines[1:]:
        if not line:
            continue
        vals = [unescape(x) for x in line.split('\t')]
        rows.append({c: (num(v) if numeric else v) for c, v in zip(cols, vals)})
    return rows


def q_in(sql_template, ids, numeric=True):
    """sql_template has one {ids} placeholder; runs it in chunks of CHUNK ids."""
    ids = sorted({int(i) for i in ids if i})
    rows = []
    for k in range(0, len(ids), CHUNK):
        rows += q(sql_template.format(ids=','.join(map(str, ids[k:k + CHUNK]))), numeric)
    return rows


def text_fields(rows, names):
    """Keep text columns as text (num() would turn a quest title like "1000" into a number)."""
    for r in rows:
        for n in names:
            if r.get(n) is not None:
                r[n] = str(r[n])
    return rows


def parse_args():
    p = argparse.ArgumentParser(description='Read-only quest data export for a Questie-X database plugin.')
    p.add_argument('--out', required=True, help='output file (.json.gz)')
    p.add_argument('--world-db', default='acore_world', help='world database name (default acore_world)')
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--port', type=int, default=3306)
    p.add_argument('--user', default=None, help='MySQL user (default: acore for direct, root for --docker-container)')
    p.add_argument('--mysql', default='mysql', help='mysql client binary (default: mysql)')
    p.add_argument('--defaults-file', default=None, help='MySQL option file with [client] user/password')
    p.add_argument('--docker-container', default=None, help='run the mysql client inside this container')
    p.add_argument('--docker-password-env', default='MYSQL_ROOT_PASSWORD',
                   help='password variable inside the container (default MYSQL_ROOT_PASSWORD)')
    p.add_argument('--core-dir', default=None, help='AzerothCore source checkout, to record its git commit')
    a = p.parse_args()
    if not a.docker_container and a.user is None and not a.defaults_file:
        a.user = 'acore'
    return a


def main():
    global ARGS
    ARGS = parse_args()
    started = datetime.datetime.now(datetime.timezone.utc)
    print('reading quest starters ...')
    c_start = q('SELECT id, quest FROM creature_queststarter')
    g_start = q('SELECT id, quest FROM gameobject_queststarter')
    # one pass over item_template (568k rows), no correlated subquery
    i_start = q('SELECT entry, startquest FROM item_template WHERE startquest > 0')
    quest_ids = {r['quest'] for r in c_start} | {r['quest'] for r in g_start} | {r['startquest'] for r in i_start}

    qt_cols = ('ID, QuestType, QuestLevel, MinLevel, QuestSortID, QuestInfoID, SuggestedGroupNum, Flags, '
               'AllowableRaces, LogTitle, LogDescription, QuestDescription, AreaDescription, StartItem, '
               'RequiredFactionId1, RequiredFactionId2, RequiredFactionValue1, RequiredFactionValue2, RewardNextQuest, '
               'RequiredNpcOrGo1, RequiredNpcOrGo2, RequiredNpcOrGo3, RequiredNpcOrGo4, '
               'RequiredNpcOrGoCount1, RequiredNpcOrGoCount2, RequiredNpcOrGoCount3, RequiredNpcOrGoCount4, '
               'ObjectiveText1, ObjectiveText2, ObjectiveText3, ObjectiveText4, '
               'RequiredItemId1, RequiredItemId2, RequiredItemId3, RequiredItemId4, RequiredItemId5, RequiredItemId6, '
               'RequiredItemCount1, RequiredItemCount2, RequiredItemCount3, RequiredItemCount4, RequiredItemCount5, '
               'RequiredItemCount6, ItemDrop1, ItemDrop2, ItemDrop3, ItemDrop4, '
               'ItemDropQuantity1, ItemDropQuantity2, ItemDropQuantity3, ItemDropQuantity4, '
               'RewardFactionID1, RewardFactionValue1, RewardFactionID2, RewardFactionValue2, RewardFactionID3, '
               'RewardFactionValue3, RewardFactionID4, RewardFactionValue4, RewardFactionID5, RewardFactionValue5, '
               'RequiredPlayerKills, TimeAllowed')
    print(f'reading {len(quest_ids)} quests ...')
    quests = text_fields(q_in(f'SELECT {qt_cols} FROM quest_template WHERE ID IN ({{ids}})', quest_ids),
                         ['LogTitle', 'LogDescription', 'QuestDescription', 'AreaDescription',
                          'ObjectiveText1', 'ObjectiveText2', 'ObjectiveText3', 'ObjectiveText4'])
    quest_ids = {r['ID'] for r in quests}   # drop starters that point at missing quests
    addon = {r['ID']: r for r in q_in(
        'SELECT ID, MaxLevel, AllowableClasses, SourceSpellID, PrevQuestID, NextQuestID, ExclusiveGroup, '
        'BreadcrumbForQuestId, RequiredSkillID, RequiredSkillPoints, RequiredMinRepFaction, RequiredMaxRepFaction, '
        'RequiredMinRepValue, RequiredMaxRepValue, ProvidedItemCount, SpecialFlags '
        'FROM quest_template_addon WHERE ID IN ({ids})', quest_ids)}
    c_end = q_in('SELECT id, quest FROM creature_questender WHERE quest IN ({ids})', quest_ids)
    g_end = q_in('SELECT id, quest FROM gameobject_questender WHERE quest IN ({ids})', quest_ids)
    triggers = q_in('SELECT r.id AS trigger_id, r.quest, a.map, a.x, a.y, a.z, a.radius, a.length, a.width, '
                    'a.height, a.orientation FROM areatrigger_involvedrelation r '
                    'LEFT JOIN areatrigger a ON a.entry = r.id WHERE r.quest IN ({ids})', quest_ids)

    def by_quest(rows, key='id', quest='quest'):
        m = {}
        for r in rows:
            if r[quest] in quest_ids:
                m.setdefault(r[quest], []).append(r[key])
        return m

    starters = {'creature': by_quest(c_start), 'gameobject': by_quest(g_start),
                'item': by_quest(i_start, 'entry', 'startquest')}
    enders = {'creature': by_quest(c_end), 'gameobject': by_quest(g_end)}
    trig_by_quest = {}
    for t in triggers:
        trig_by_quest.setdefault(t['quest'], []).append({k: v for k, v in t.items() if k != 'quest'})
    for r in quests:
        qid = r['ID']
        r['addon'] = addon.get(qid)
        r['starters'] = {k: v.get(qid, []) for k, v in starters.items()}
        r['enders'] = {k: v.get(qid, []) for k, v in enders.items()}
        r['areatriggers'] = trig_by_quest.get(qid, [])

    # --- items -------------------------------------------------------------------------------------
    item_ids = {r['entry'] for r in i_start if r['startquest'] in quest_ids}
    for r in quests:
        for f in ['StartItem'] + [f'RequiredItemId{i}' for i in range(1, 7)] + [f'ItemDrop{i}' for i in range(1, 5)]:
            if r.get(f):
                item_ids.add(r[f])
    print(f'reading {len(item_ids)} items and their sources ...')
    items = text_fields(q_in('SELECT entry, name, startquest, Flags, FlagsExtra, class, subclass, Quality, ItemLevel, '
                             'RequiredLevel, AllowableClass, AllowableRace, maxcount, stackable, lockid '
                             'FROM item_template WHERE entry IN ({ids})', item_ids), ['name'])
    loot_cols = 'Entry, Item, Reference, Chance, QuestRequired, GroupId, MinCount, MaxCount'
    c_loot = q_in(f'SELECT {loot_cols} FROM creature_loot_template WHERE Item IN ({{ids}}) AND Reference = 0', item_ids)
    g_loot = q_in(f'SELECT {loot_cols} FROM gameobject_loot_template WHERE Item IN ({{ids}}) AND Reference = 0', item_ids)
    it_loot = q_in(f'SELECT {loot_cols} FROM item_loot_template WHERE Item IN ({{ids}}) AND Reference = 0', item_ids)
    ref_loot = q_in(f'SELECT {loot_cols} FROM reference_loot_template WHERE Item IN ({{ids}})', item_ids)
    ref_ids = {r['Entry'] for r in ref_loot}
    # one level: which loot templates pull those references in
    c_loot_ref = q_in(f'SELECT {loot_cols} FROM creature_loot_template WHERE Reference IN ({{ids}})', ref_ids)
    g_loot_ref = q_in(f'SELECT {loot_cols} FROM gameobject_loot_template WHERE Reference IN ({{ids}})', ref_ids)
    vendors = q_in('SELECT entry, item, maxcount, incrtime, ExtendedCost FROM npc_vendor WHERE item IN ({ids})', item_ids)

    # loot ids -> template entries
    c_lootids = {r['Entry'] for r in c_loot + c_loot_ref}
    loot_creatures = q_in('SELECT entry, lootid FROM creature_template WHERE lootid IN ({ids})', c_lootids)
    g_lootids = {r['Entry'] for r in g_loot + g_loot_ref}
    loot_gos = q_in('SELECT entry, type, Data1 AS lootid FROM gameobject_template '
                    'WHERE type IN (3, 25) AND Data1 IN ({ids})', g_lootids)

    # --- creatures and gameobjects -------------------------------------------------------------------
    creature_ids = {i for v in starters['creature'].values() for i in v} | \
                   {i for v in enders['creature'].values() for i in v}
    go_ids = {i for v in starters['gameobject'].values() for i in v} | \
             {i for v in enders['gameobject'].values() for i in v}
    for r in quests:
        for i in range(1, 5):
            v = r.get(f'RequiredNpcOrGo{i}') or 0
            if v > 0:
                creature_ids.add(v)
            elif v < 0:
                go_ids.add(-v)
    required_creatures = set(creature_ids)
    killcredit = q_in('SELECT entry, KillCredit1, KillCredit2 FROM creature_template '
                      'WHERE KillCredit1 IN ({ids}) OR KillCredit2 IN ({ids})', required_creatures)
    creature_ids |= {r['entry'] for r in killcredit}
    creature_ids |= {r['entry'] for r in loot_creatures}
    creature_ids |= {r['entry'] for r in vendors}
    go_ids |= {r['entry'] for r in loot_gos}

    print(f'reading {len(creature_ids)} creatures and {len(go_ids)} gameobjects with spawns ...')
    creatures = text_fields(q_in(
        'SELECT entry, name, subname, minlevel, maxlevel, `rank`, faction, npcflag, type, unit_class, '
        'HealthModifier, KillCredit1, KillCredit2, lootid FROM creature_template WHERE entry IN ({ids})',
        creature_ids), ['name', 'subname'])
    c_spawns = q_in('SELECT id, map, zoneId, areaId, position_x, position_y, position_z, spawnMask, phaseMask '
                    'FROM creature WHERE id IN ({ids})', creature_ids)
    gos = text_fields(q_in('SELECT entry, name, type, Data0, Data1 FROM gameobject_template WHERE entry IN ({ids})',
                           go_ids), ['name'])
    g_spawns = q_in('SELECT id, map, zoneId, areaId, position_x, position_y, position_z, spawnMask, phaseMask '
                    'FROM gameobject WHERE id IN ({ids})', go_ids)

    def group(rows, key):
        m = {}
        for r in rows:
            m.setdefault(r[key], []).append({k: v for k, v in r.items() if k != key})
        return m

    cs, gs = group(c_spawns, 'id'), group(g_spawns, 'id')
    kc_of = {}
    for r in killcredit:
        for f in ('KillCredit1', 'KillCredit2'):
            if r[f] in required_creatures:
                kc_of.setdefault(r[f], []).append(r['entry'])
    for r in creatures:
        r['spawns'] = cs.get(r['entry'], [])
        r['killcredit_sources'] = kc_of.get(r['entry'], [])
    for r in gos:
        r['spawns'] = gs.get(r['entry'], [])

    stock = sum(1 for i in quest_ids if i <= STOCK_MAX_QUEST_ID)
    sha = None
    if ARGS.core_dir:
        sha = subprocess.run(['git', '-C', ARGS.core_dir, 'rev-parse', 'HEAD'],
                             capture_output=True, text=True).stdout.strip() or None
    doc = {
        'meta': {
            'core_commit': sha, 'database': ARGS.world_db,
            'exported_at': started.isoformat(timespec='seconds'),
            'coordinates': 'raw map/x/y/z (world units)',
            'quests_stock_le_%d' % STOCK_MAX_QUEST_ID: stock, 'quests_custom_gt_%d' % STOCK_MAX_QUEST_ID: len(quest_ids) - stock,
            'counts': {'quests': len(quests), 'creatures': len(creatures), 'creature_spawns': len(c_spawns),
                       'gameobjects': len(gos), 'gameobject_spawns': len(g_spawns), 'items': len(items),
                       'areatriggers': len(triggers), 'vendor_rows': len(vendors)},
        },
        'quests': quests,
        'creatures': creatures,
        'gameobjects': gos,
        'items': items,
        'item_sources': {
            'creature_loot': c_loot, 'gameobject_loot': g_loot, 'item_loot': it_loot,
            'reference_loot': ref_loot, 'creature_loot_via_reference': c_loot_ref,
            'gameobject_loot_via_reference': g_loot_ref,
            'creature_lootid_to_entry': loot_creatures, 'gameobject_lootid_to_entry': loot_gos,
            'vendors': vendors,
        },
    }
    path = ARGS.out
    with gzip.open(path, 'wt', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, separators=(',', ':'))
    print(json.dumps(doc['meta'], indent=2))
    print(f'wrote {path} ({os.path.getsize(path) / 1e6:.1f} MB)')


if __name__ == '__main__':
    sys.exit(main())
