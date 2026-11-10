# The expedition for the "unknowns": recipes the profession pages give no source for. It asks four more
# places and writes what they say, with where each fact came from, to tools/found_sources.json - which
# gen_data.py merges into the data.
#
#   python tools/research.py           (after fetch_binds.py; then run gen_data.py)
#
# The places:
#   fc-quests    foreverchanges.pro/quests/<zone>: every quest with its reward items
#   fc-dungeons  foreverchanges.pro/dungeons/<dungeon>: every boss with its loot and drop chance
#   fc-favor     the profession pages' own Merchant's Favor lists (Enchanting's are not joined to its recipes)
#   questie      the installed QuestieDB Forever database: the NPCs and objects that drop an item, its vendors,
#                the quests that reward it (questie.py). GPL-3.0 - only looked-up facts are kept.
#   wowhead      Wowhead's Forever recipe lists, read by hand in a browser for the leftovers (wowhead_lists.txt):
#                the kind of source (drop / quest / vendor) and, where there is only one, its name
#   client       wago.tools' export of the Forever client's SkillLineAbility + SpellName tables: the spell ids
#                of the enchants the Enchanting page names without one, and which recipes come by themselves
#                with the skill (AcquireMethod 1).
#
# Every place is first measured against the recipes whose source IS known (the calibration printed at the
# end): a place that disagrees with what is known should not be believed about what is not.
# Pages are cached under tools/pages/research/. Not shipped to players.
import collections
import csv
import io
import json
import os
import re
import time
import urllib.request

import questie
import source

CACHE = os.path.join(source.PAGES, "research")
BASE = "https://foreverchanges.pro"
WAGO = "https://wago.tools/db2/%s/csv?build=%s"
CLIENT_BUILD = "1.60.1.70888"
DECODER = json.JSONDecoder()
ALLIANCE, HORDE = 77, 178          # race masks: human dwarf night-elf gnome / orc undead tauren troll
MANY_DROPPERS = 25                 # an item more creatures than this drop is a world drop
SMALL = {"of", "the", "in", "to"}


def fetch(url, name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        data = urllib.request.urlopen(request, timeout=60).read()
        open(path, "wb").write(data)
        time.sleep(0.3)
    return open(path, encoding="utf-8", errors="replace").read()


def page(path):
    html = fetch(BASE + path, (path.strip("/").replace("/", "_") or "index") + ".html")
    chunks = re.findall(r'self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)', html)
    try:
        return html, "".join(json.loads(c) for c in chunks)
    except Exception:  # noqa: BLE001
        return html, html


def title(slug):
    words = slug.split("-")
    return " ".join(w if (i > 0 and w in SMALL) else w.capitalize() for i, w in enumerate(words))


def text_of(value):
    return value.decode("utf-8", "replace") if isinstance(value, bytes) else value


# ----------------------------------------------------------------------------------------------------
# foreverchanges: quests and dungeons
# ----------------------------------------------------------------------------------------------------
def read_quests():
    """item id -> [ {name, level, side, zone} ], and area id -> zone name"""
    index_html, _ = page("/quests")
    slugs = sorted(set(re.findall(r'href="(/quests/[a-z0-9-]+)"', index_html)))
    rewards = collections.defaultdict(dict)
    zone_votes = collections.defaultdict(collections.Counter)
    for path in slugs:
        slug = path.split("/")[-1]
        _, text = page(path)
        for m in re.finditer(r'\{"i":\d+,"n":"', text):
            try:
                q, _ = DECODER.raw_decode(text, m.start())
            except Exception:  # noqa: BLE001
                continue
            where = q.get("c") or []
            if len(where) == 2 and isinstance(where[1], int):
                zone_votes[where[1]][slug] += 1
            for reward in (q.get("r") or []) + (q.get("k") or []):
                if isinstance(reward, list) and reward and isinstance(reward[0], int):
                    rewards[reward[0]][q["i"]] = {"name": q["n"], "level": q.get("l"), "side": q.get("s") or "", "where": where, "page": slug}
    # an area id is the zone of the page most of its quests are listed on
    zones = {}
    for area, votes in zone_votes.items():
        slug, count = votes.most_common(1)[0]
        zones[area] = title(slug)
    result = {}
    for item_id, quests in rewards.items():
        entries = []
        for q in quests.values():
            where = q["where"]
            zone = zones.get(where[1]) if len(where) == 2 else None
            entries.append({"name": q["name"], "level": q["level"], "side": q["side"], "zone": zone})
        # the same quest given to both factions is one line without a side
        merged = {}
        for e in entries:
            key = (e["name"], e["zone"])
            if key in merged and merged[key]["side"] != e["side"]:
                merged[key]["side"] = ""
            else:
                merged.setdefault(key, e)
        result[item_id] = list(merged.values())
    return result, zones, len(slugs)


def read_dungeons():
    """item id -> [ {npc, zone, chance, min, max} ]"""
    index_html, _ = page("/dungeons")
    slugs = sorted(set(re.findall(r'href="(/dungeons/[a-z0-9-]+)"', index_html)))
    drops = collections.defaultdict(list)
    for path in slugs:
        _, text = page(path)
        at = text.find('"bosses":[{"name"')
        if at < 0:
            continue
        bosses, _ = DECODER.raw_decode(text, at + len('"bosses":'))
        names = DECODER.raw_decode(text, text.find('"dungeons":[{"id"') + len('"dungeons":'))[0] if '"dungeons":[{"id"' in text else []
        slug = path.split("/")[-1]
        dungeon = next((d["name"] for d in names if d["id"] == slug), title(slug))
        for boss in bosses:
            for item in boss.get("items") or []:
                drops[item["i"]].append({"npc": boss["name"], "zone": dungeon, "chance": item.get("z"), "level": boss.get("level")})
    return drops, len(slugs)


# ----------------------------------------------------------------------------------------------------
# Questie
# ----------------------------------------------------------------------------------------------------
def side_of_races(mask):
    if not isinstance(mask, int) or mask == 0:
        return ""
    alliance, horde = mask & ALLIANCE, mask & HORDE
    if alliance and not horde:
        return "a"
    if horde and not alliance:
        return "h"
    return ""


def read_questie(store, item_id, zones):
    found = {}
    npcs = store.raw("Item", item_id, 2) or []
    if isinstance(npcs, list) and npcs:
        entries = []
        for npc in npcs:
            s = store.summary("Npc", npc) or {}
            if not s.get(1):
                continue
            entries.append({"npc": text_of(s[1]), "zone": zones.get(s.get(9)), "level": [s.get(4), s.get(5)] if s.get(4) and s.get(5) and s.get(4) != s.get(5) else s.get(4), "id": npc})
        if len(entries) > MANY_DROPPERS:
            levels = [l for e in entries for l in (e["level"] if isinstance(e["level"], list) else [e["level"]]) if l]
            if levels:
                found["world"] = [min(levels), max(levels)]
        elif entries:
            found["drops"] = entries[:8]
            found["more_drops"] = max(0, len(entries) - 8)
    for obj in store.raw("Item", item_id, 3) or []:
        s = store.summary("Object", obj) or {}
        if s.get(1):
            found.setdefault("objects", []).append({"name": text_of(s[1]), "zone": zones.get(s.get(5))})
    for container in store.raw("Item", item_id, 4) or []:
        s = store.summary("Item", container) or {}
        if s.get(1):
            found.setdefault("objects", []).append({"name": text_of(s[1]), "zone": None})
    for vendor in store.raw("Item", item_id, 14) or []:
        s = store.summary("Npc", vendor) or {}
        if s.get(1):
            friendly = text_of(s.get(13)) or ""
            found.setdefault("vendors", []).append({"npc": text_of(s[1]), "zone": zones.get(s.get(9)), "side": {"A": "a", "H": "h"}.get(friendly, "")})
    for quest in store.raw("Item", item_id, 6) or []:
        s = store.summary("Quest", quest) or {}
        if s.get(1):
            zone = zones.get(s.get(17)) if isinstance(s.get(17), int) and s.get(17) > 0 else None
            found.setdefault("quests", []).append({"name": text_of(s[1]), "level": s.get(5), "side": side_of_races(s.get(6)), "zone": zone})
    return found


# ----------------------------------------------------------------------------------------------------
# The client's own tables
# ----------------------------------------------------------------------------------------------------
def read_areas():
    """area id -> zone name, from the client's AreaTable"""
    areas = {}
    for r in csv.DictReader(io.StringIO(fetch(WAGO % ("AreaTable", CLIENT_BUILD), "AreaTable.csv"))):
        areas[int(r["ID"])] = r.get("AreaName_lang") or r.get("ZoneName")
    return areas


def read_wowhead(areas):
    """item id -> {drops, vendors, quests, somewhere: [kinds]} from wowhead_lists.txt"""
    path = os.path.join(source.HERE, "wowhead_lists.txt")
    result = {}
    if not os.path.exists(path):
        return result
    kinds = {"2": "drop", "4": "quest", "5": "vendor"}
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        item_id, codes, more = line.split("|", 2)
        found = {}
        wanted = [kinds[c] for c in codes.split(",") if c in kinds]
        for entry in [m for m in more.split(";") if m]:
            kind, entity, zone, name = entry.split("~", 3)
            zone_name = areas.get(int(zone)) if zone and zone != "0" else None
            if kind == "5":
                found.setdefault("quests", []).append({"name": name, "level": None, "side": "", "zone": zone_name})
            elif kind == "1" and "drop" in wanted and "vendor" not in wanted:
                found.setdefault("drops", []).append({"npc": name, "zone": zone_name, "chance": None, "level": None})
            elif kind == "1" and "vendor" in wanted:
                found.setdefault("vendors", []).append({"npc": name, "zone": zone_name, "side": ""})
            elif kind == "" and zone_name and "drop" in wanted:
                found.setdefault("zones", []).append(zone_name)
        named = {"drop": "drops" in found or "zones" in found, "quest": "quests" in found, "vendor": "vendors" in found}
        somewhere = [k for k in wanted if not named[k]]
        if somewhere:
            found["somewhere"] = somewhere
        found["kinds"] = wanted
        result[int(item_id)] = found
    return result


def read_wowhead_items(areas):
    """item id -> {vendors, cost, drops} from wowhead_items.txt (the item pages of the unnamed ones)"""
    path = os.path.join(source.HERE, "wowhead_items.txt")
    result = {}
    if not os.path.exists(path):
        return result
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        item_id, *parts = line.split("|")
        found = {}
        for part in parts:
            kind, _, body = part.partition("=")
            if kind == "S":
                for entry in body.split(";"):
                    if entry.startswith("+"):
                        continue
                    name, zone, side, copper, currency, stock = entry.split("~")
                    vendor = {"npc": name, "zone": areas.get(int(zone)) if zone != "0" else None, "side": side}
                    if copper != "0":
                        vendor["price"] = int(copper)
                    if stock not in ("-1", "", "undefined"):
                        vendor["limited"] = True
                    found.setdefault("vendors", []).append(vendor)
                    if currency.startswith("3402:"):
                        found["cost"] = {"currency": "Merchant's Favor", "amount": int(currency.split(":")[1])}
            elif kind == "D":
                total, _, body = body.partition("#")
                by_zone = collections.OrderedDict()
                for entry in body.split(";"):
                    name, zone, chance, lo, hi, seen = entry.split("~")
                    by_zone.setdefault(areas.get(int(zone)) if zone != "0" else None, []).append((name, chance, lo, hi))
                drops = []
                for zone, entries in by_zone.items():
                    if len(entries) >= 3:
                        # several bosses of one place share it: one line for the place
                        drops.append({"npc": "Bosses", "zone": zone, "chance": None, "level": None})
                    else:
                        for name, chance, lo, hi in entries:
                            level = None if lo in ("", "9999") else ([int(lo), int(hi)] if lo != hi else int(lo))
                            drops.append({"npc": name, "zone": zone, "chance": float(chance) if chance and float(chance) > 0 else None, "level": level})
                found["drops"] = drops
        result[int(item_id)] = found
    return result


def read_client():
    names = {int(r["ID"]): r["Name_lang"] for r in csv.DictReader(io.StringIO(fetch(WAGO % ("SpellName", CLIENT_BUILD), "SpellName.csv")))}
    lines = collections.defaultdict(dict)
    for r in csv.DictReader(io.StringIO(fetch(WAGO % ("SkillLineAbility", CLIENT_BUILD), "SkillLineAbility.csv"))):
        lines[int(r["SkillLine"])][int(r["Spell"])] = r
    return names, lines


# ----------------------------------------------------------------------------------------------------
def favor_lists():
    """recipe item id -> favor cost, and the vendors the pages name most for favor recipes"""
    costs, vendor_lists = {}, collections.Counter()
    for key, _, _, pg, _, _ in source.PROFESSIONS:
        text = source.payload(pg)
        for f in source.decode_at(text, '"favor":[{"id"', back=len('"favor":')) or []:
            costs[f["id"]] = f["favor"]
    binds = source.load_binds()
    for key, *_ in source.PROFESSIONS:
        rows, _ = source.load(key, binds)
        for r in rows:
            src = r["source"]
            if src.get("cost") and src.get("vendors"):
                vendor_lists[json.dumps(src["vendors"], sort_keys=True)] += 1
    vendors = json.loads(vendor_lists.most_common(1)[0][0]) if vendor_lists else []
    return costs, vendors


def has_source(src):
    return bool(src.get("vendors") or src.get("quests") or src.get("drops") or src.get("world") or src.get("trainers")
                or src.get("capitals") or src.get("made") or src.get("objects"))


def main():
    binds = source.load_binds()
    store = questie.Store()
    print("questie database:", "read, %d records" % len(store.lines) if store.available() else "NOT INSTALLED - skipped")
    quest_rewards, zones, quest_pages = read_quests()
    dungeon_drops, dungeon_pages = read_dungeons()
    favor_costs, favor_vendors = favor_lists()
    names, lines = read_client()
    areas = read_areas()
    wowhead = read_wowhead(areas)
    wowhead_items = read_wowhead_items(areas)
    # the client's zone names where the quest pages have none
    for area, zone in areas.items():
        zones.setdefault(area, zone)
    print("read: %d quest pages (%d items rewarded, %d zones named), %d dungeon pages (%d items dropped), %d favor recipes, client build %s" % (
        quest_pages, len(quest_rewards), len(zones), dungeon_pages, len(dungeon_drops), len(favor_costs), CLIENT_BUILD))

    out = {"sources": {}, "spells": {}, "auto": [], "readOn": time.strftime("%Y-%m-%d"), "clientBuild": CLIENT_BUILD}
    cal = collections.Counter()
    totals = collections.Counter()
    by_prof = collections.defaultdict(collections.Counter)
    leftovers = []

    for key, name, line, pg, short, icon in source.PROFESSIONS:
        rows, skipped = source.load(key, binds)
        # --- the enchants the page names without a spell id, by name in the client's skill line
        by_name = collections.defaultdict(list)
        for spell in lines[line]:
            by_name[names.get(spell)].append(spell)
        for s in skipped:
            if s.startswith("no spell for "):
                wanted = s[len("no spell for "):]
                spells = by_name.get(wanted) or []
                if len(spells) == 1:
                    out["spells"].setdefault(key, {})[wanted] = spells[0]
                    totals["enchant spell ids found"] += 1
                else:
                    totals["enchant spell ids still missing"] += 1
        # --- recipes that come with the skill
        for r in rows:
            info = lines[line].get(r["spell"])
            if info and info["AcquireMethod"] == "1" and not r["formula"] and not has_source(r["source"]):
                out["auto"].append(r["spell"])
                totals["recipes that come with the skill"] += 1

        for r in rows:
            formula = r["formula"]
            if not formula:
                continue
            item_id = formula["id"]
            src = r["source"]
            known = has_source(src)
            q = read_questie(store, item_id, zones) if store.available() else {}
            fq = quest_rewards.get(item_id) or []
            fd = dungeon_drops.get(item_id) or []
            wh = wowhead.get(item_id)

            if known:
                if wh:
                    page_kinds = set()
                    if src.get("vendors") or src.get("trainers") or src.get("capitals"):
                        page_kinds.add("vendor")
                    if src.get("drops") or src.get("world") or src.get("objects"):
                        page_kinds.add("drop")
                    if src.get("quests"):
                        page_kinds.add("quest")
                    cal["wowhead kinds: agree" if page_kinds & set(wh["kinds"]) else "wowhead kinds: DISAGREE (%s vs %s)" % (sorted(page_kinds), wh["kinds"])] += 1
                    page_names = {v["npc"] for v in src.get("vendors") or []} | {d["npc"] for d in src.get("drops") or []} | {x["name"] for x in src.get("quests") or []}
                    wh_names = {v["npc"] for v in wh.get("vendors", [])} | {d["npc"] for d in wh.get("drops", [])} | {x["name"] for x in wh.get("quests", [])}
                    if wh_names:
                        cal["wowhead names: agree" if page_names & wh_names else "wowhead names: DISAGREE"] += 1
                # calibration: does each place agree with what the page knows?
                page_vendors = {v["npc"] for v in src.get("vendors") or []}
                page_drops = {d["npc"] for d in src.get("drops") or []}
                page_quests = {x["name"] for x in src.get("quests") or []}
                if page_vendors and q.get("vendors") is not None:
                    cal["questie vendors: agree" if page_vendors & {v["npc"] for v in q["vendors"]} else "questie vendors: DISAGREE"] += 1
                elif page_vendors:
                    cal["questie vendors: silent"] += 1
                elif q.get("vendors"):
                    cal["questie vendors: page has none"] += 1
                if page_drops and q.get("drops"):
                    cal["questie drops: agree" if page_drops & {d["npc"] for d in q["drops"]} else "questie drops: DISAGREE"] += 1
                elif page_drops and q.get("world"):
                    cal["questie drops: world drop where the page lists creatures"] += 1
                elif page_drops:
                    cal["questie drops: silent"] += 1
                elif q.get("drops") or q.get("world"):
                    cal["questie drops: page has none"] += 1
                if page_quests and q.get("quests"):
                    cal["questie quests: agree" if page_quests & {x["name"] for x in q["quests"]} else "questie quests: DISAGREE"] += 1
                if page_quests:
                    cal["fc-quests: agree" if page_quests & {x["name"] for x in fq} else "fc-quests: silent"] += 1
                elif fq:
                    cal["fc-quests: page has none"] += 1
                if fd:
                    cal["fc-dungeons: agree" if page_drops & {d["npc"] for d in fd} else "fc-dungeons: page lists others"] += 1
                # a quest the quest pages know of and the profession page does not: added to the known recipe
                extra = [x for x in fq if x["name"] not in page_quests]
                if extra:
                    out["sources"][str(item_id)] = {"quests": extra, "from": ["fc-quests"], "adds": True}
                    totals["known recipes given another quest"] += 1
                continue

            found, where = {}, []
            if fq:
                found["quests"] = fq
                where.append("fc-quests")
            if fd:
                found["drops"] = fd
                where.append("fc-dungeons")
            if item_id in favor_costs:
                found["cost"] = {"currency": "Merchant's Favor", "amount": favor_costs[item_id]}
                found["vendors"] = favor_vendors
                where.append("fc-favor")
            used_questie = False
            for kind in ("vendors", "quests", "drops", "world", "objects"):
                if q.get(kind) and not found.get(kind):
                    found[kind] = q[kind]
                    used_questie = True
            if used_questie:
                where.append("questie")
            whi = wowhead_items.get(item_id)
            if whi:
                # its own page names what the list only gave the kind of
                wh = dict(wh or {})
                wh.pop("somewhere", None)
                for kind in ("vendors", "drops"):
                    if whi.get(kind):
                        wh[kind] = whi[kind]
                if whi.get("cost") and not found.get("cost"):
                    found["cost"] = whi["cost"]
                totals["  of which named from a Wowhead item page"] += 1
            if wh:
                used = False
                for kind in ("vendors", "quests", "drops"):
                    if wh.get(kind) and not found.get(kind):
                        found[kind] = wh[kind]
                        used = True
                if wh.get("zones") and not found.get("drops") and not found.get("world"):
                    found["drops"] = [{"npc": "Creatures and bosses", "zone": z, "chance": None, "level": None} for z in wh["zones"]]
                    used = True
                have = {"vendor": bool(found.get("vendors")), "quest": bool(found.get("quests")), "drop": bool(found.get("drops") or found.get("world") or found.get("objects"))}
                somewhere = [k for k in wh.get("somewhere", []) if not have[k]]
                if somewhere:
                    found["somewhere"] = somewhere
                    used = True
                if used:
                    where.append("wowhead")
            if found:
                found["from"] = where
                out["sources"][str(item_id)] = found
                totals["unknown recipes given a source"] += 1
                by_prof[key]["found"] += 1
                for w in where:
                    totals["  of which from " + w] += 1
            else:
                totals["unknown recipes still unknown"] += 1
                by_prof[key]["left"] += 1
                leftovers.append({"prof": key, "item": item_id, "name": formula["name"], "learn": r["learn"], "new": r["new"],
                                  "bind": (binds.get(str(item_id)) or {}).get("bind"), "in_questie": store.has("Item", item_id)})

    json.dump(out, open(os.path.join(source.HERE, "found_sources.json"), "w", encoding="utf-8", newline="\n"), indent=1, sort_keys=True)
    json.dump(leftovers, open(os.path.join(source.HERE, "still_unknown.json"), "w", encoding="utf-8", newline="\n"), indent=1)

    print()
    print("CALIBRATION - each place against the recipes whose source the pages know:")
    for k in sorted(cal):
        print("   %-62s %4d" % (k, cal[k]))
    print()
    print("RESULT:")
    for k, v in totals.items():
        print("   %-44s %4d" % (k, v))
    print("   per profession:", {k: dict(v) for k, v in by_prof.items()})
    new = sum(1 for e in leftovers if e["new"])
    print("   still unknown: %d new in Forever, %d from Classic; %d bind on pickup" % (new, len(leftovers) - new, sum(1 for e in leftovers if e["bind"] == "pickup")))


main()
