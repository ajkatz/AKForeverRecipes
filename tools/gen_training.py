# Writes Data/Training.lua: how each profession's skill cap is raised - who teaches Apprentice,
# Journeyman, Expert and Artisan, the books and quests that stand in for a trainer - and the
# specializations of Blacksmithing, Engineering and Leatherworking.
#
#   python tools/gen_training.py
#
# From: tools/wowhead_ranks.txt (Wowhead's Forever pages of the rank spells: trainers, the Expert books,
# the Artisan quests), the installed QuestieDB Forever database (who sells a book, who gives a quest - the
# specialization quests are found there by their ids) and the client's AreaTable for zone names
# (tools/pages/research/AreaTable.csv, fetched by research.py). What a trainer asks for a rank is in
# tools/trainer_costs.json ({ "<spell id>": copper }, Wowhead's Forever spell lists - see gen_data.py).
#
# The skill a rank needs (50 / 125 / 200) is Classic's; a book's or a quest's own requirement is used where
# one is known. The specialization quests are Classic's, found in Questie's Forever database; Wowhead's
# Forever quest pages have all seven with the same words (read 2026-11-16), and the window says that is
# where they stand - nobody has reported doing one in the game yet. Not shipped to players.
import csv
import datetime
import glob
import json
import os
import re

import questie
import source

ROOT = os.path.dirname(source.HERE)
RANKS = ["Apprentice", "Journeyman", "Expert", "Artisan"]
CAPS = {"Apprentice": 75, "Journeyman": 150, "Expert": 225, "Artisan": 300}
NEEDS = {"Journeyman": 50, "Expert": 125, "Artisan": 200}  # Classic's
SPELLS = {  # profession -> its four rank spells
    "alchemy": [2259, 3101, 3464, 11611], "blacksmithing": [2018, 3100, 3538, 9785], "enchanting": [7411, 7412, 7413, 13920],
    "engineering": [4036, 4037, 4038, 12656], "leatherworking": [2108, 3104, 3811, 10662], "tailoring": [3908, 3909, 3910, 12180],
    "cooking": [2550, 3102, 3413, 18260], "firstaid": [3273, 3274, 7924, 10846], "mining": [2575, 2576, 3564, 10248],
}
# specializations: name, the quest(s) that grant it by Questie quest id
SPECS = {
    "blacksmithing": [("Armorsmith", [5283, 5301]), ("Weaponsmith", [5284, 5302])],
    "engineering": [("Gnomish Engineering", [3641, 3643]), ("Goblin Engineering", [3639])],
    "leatherworking": [("Dragonscale Leatherworking", [5141, 5145]), ("Elemental Leatherworking", [5144, 5146]), ("Tribal Leatherworking", [5143, 5148])],
}
ALLIANCE, HORDE = 77, 178
# What a rank's quest wants brought (the user, 2026-11-16: "for recipes for 225 cooking it should show the raw
# materials you need to bring down to dirge"): the items from Questie's objectives, how many of each from
# the quest's own words ("12 Giant Eggs.", "10 pieces of Zesty Clam Meat.") - the same numbers Wowhead's
# Forever page of quest 6610 gives (12 / 10 / 20, read 2026-11-16 in a browser). An item's icon is the one
# the recipe tables already carry (Data/*.lua: a reagent's I(...) line, a made thing's recipe); for an item no
# recipe uses or makes, the name of its icon on Wowhead's Forever item page, written here by hand:
ITEM_ICONS = {8932: "inv_misc_food_37"}  # Alterac Swiss (wowhead.com/forever/item=8932, read 2026-11-16)
# The specializations' quests list theirs the same way (the user, 2026-11-16: "can you do the same for the
# engineering/leatherworking specialties" - Blacksmithing's two come along, they are the same kind). Their
# words name one of a thing with "a" / "an" ("an Accurate Scope", "a Wild Leather Vest") and things in the
# plural ("2 Advanced Target Dummies"). Wowhead's Forever pages of quests 3641, 3639, 5141, 5144, 5143, 5283
# and 5284 have the same words as Questie (read 2026-11-16 in a browser).


def lua(value):
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if isinstance(value, (int, float)):
        return repr(value)
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def fields(pairs):
    return "{ " + ", ".join(k + " = " + lua(v) for k, v in pairs if v is not None and v != "") + " }"


def text_of(value):
    return value.decode("utf-8", "replace") if isinstance(value, bytes) else value


# a quest's entry: one line, or - when it wants items brought - its fields, then the items a line each
def quest_lines(w, q, pairs):
    line = fields(pairs)
    if not q.get("bring"):
        w("                %s," % line)
        return
    w("                %s," % line[:-2])
    w("                  bring = {")
    for item in q["bring"]:
        w("                    %s," % fields([("id", item["id"]), ("count", item["count"]), ("name", item["name"]), ("icon", item["icon"])]))
    w("                  } },")


def main():
    areas = {}
    for r in csv.DictReader(open(os.path.join(source.PAGES, "research", "AreaTable.csv"), encoding="utf-8")):
        areas[int(r["ID"])] = r.get("AreaName_lang")
    store = questie.Store()
    if not store.available():
        raise SystemExit("QuestieDB is not installed: the books' vendors and the quests' givers come from it")

    def npc(npc_id):
        s = store.summary("Npc", npc_id)
        friendly = text_of(s.get(13)) or ""
        return {"npc": text_of(s.get(1)), "zone": areas.get(s.get(9)), "side": {"A": "A", "H": "H"}.get(friendly)}

    # the icons the recipe tables carry: a reagent's I(12207, "Giant Egg", "inv_egg_03"), and a made thing's
    # recipe: spell = 3965, item = 4392, name = "Advanced Target Dummy", icon = "inv_crate_05",
    icons = dict(ITEM_ICONS)
    for path in glob.glob(os.path.join(ROOT, "Data", "*.lua")):
        if os.path.basename(path) == "Training.lua":
            continue
        text = open(path, encoding="utf-8").read()
        for item, icon in re.findall(r'^I\((\d+), "[^"]*", "([^"]+)"\)', text, re.M):
            icons.setdefault(int(item), icon)
        for item, icon in re.findall(r'^\s*spell = \d+, item = (\d+), name = "[^"]*", icon = "([^"]+)"', text, re.M):
            icons.setdefault(int(item), icon)

    # how many of an item a quest's words ask for: "12 Giant Eggs", "10 pieces of Zesty Clam Meat",
    # "2 Advanced Target Dummies" (a name in -y), "an Accurate Scope" (one); None when they do not say
    def count_in(words, name):
        named = re.escape(name[:-1]) + "(?:y|ies)" if name.endswith("y") else re.escape(name)
        number = re.search(r"(\d+)\s+(?:pieces of\s+)?" + named, words, re.I)
        if number:
            return int(number.group(1))
        return 1 if re.search(r"\ban?\s+" + named, words, re.I) else None

    def bring(quest_id):
        objectives = store.raw("Quest", quest_id, 10)
        wanted = (objectives.get(3) or objectives.get("3")) if isinstance(objectives, dict) else None
        words = " ".join(text_of(t) or "" for t in (store.raw("Quest", quest_id, 8) or []))
        items = []
        for entry in wanted or []:
            item = entry[0]
            name = text_of(store.summary("Item", item).get(1))
            if not name:
                raise SystemExit("quest %d wants item %d, which Questie does not name" % (quest_id, item))
            count = count_in(words, name)
            if not count:
                raise SystemExit("quest %d: how many %s? Its words do not say: %s" % (quest_id, name, words))
            if not icons.get(item):
                raise SystemExit("quest %d: no icon for %s (item %d) - add it to ITEM_ICONS" % (quest_id, name, item))
            items.append({"id": item, "count": count, "name": name, "icon": icons.get(item)})
        return items

    def quest(quest_id):
        s = store.summary("Quest", quest_id)
        if not s.get(1):
            return None
        started = store.raw("Quest", quest_id, 2) or s.get(2) or [[]]
        givers = [npc(n) for n in (started[0] or [])] if isinstance(started, list) and started else []
        races = s.get(6) or 0
        side = "A" if (races & ALLIANCE and not races & HORDE) else ("H" if (races & HORDE and not races & ALLIANCE) else None)
        skill = store.raw("Quest", quest_id, 18) or s.get(18)
        giver = givers[0] if givers else {}
        return {"name": text_of(s[1]), "npc": giver.get("npc"), "zone": giver.get("zone"), "side": side or giver.get("side"),
                "level": s.get(4), "skill": skill[1] if isinstance(skill, list) and len(skill) > 1 else None,
                "bring": bring(quest_id)}

    # Wowhead's rank pages
    pages = {}
    for line in open(os.path.join(source.HERE, "wowhead_ranks.txt"), encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        spell, *parts = line.split("|")
        entry = {}
        for part in parts:
            kind, _, body = part.partition("=")
            if kind == "N":
                total, _, body = body.partition("#")
                entry["total"] = int(total)
                entry["trainers"] = []
                for t in body.split(";"):
                    name, zone, side, title = t.split("~")
                    entry["trainers"].append({"npc": name, "zone": areas.get(int(zone)), "side": {"a": "A", "h": "H"}.get(side)})
            elif kind == "I":
                item, name, skill = body.split(";")[0].split("~")
                entry["book"] = {"id": int(item), "name": name, "skill": int(skill) if skill else None,
                                 "vendors": [npc(v) for v in (store.raw("Item", int(item), 14) or [])]}
            elif kind == "Q":
                entry["quests"] = [q for q in (quest(int(x.split("~")[0])) for x in body.split(";")) if q]
        pages[int(spell)] = entry

    costs_file = os.path.join(source.HERE, "trainer_costs.json")
    costs = json.load(open(costs_file, encoding="utf-8")) if os.path.exists(costs_file) else {}
    # the day the rank pages were read, not the day this ran
    read = datetime.date.fromtimestamp(os.path.getmtime(os.path.join(source.HERE, "wowhead_ranks.txt"))).isoformat()

    out = []
    w = out.append
    w("-- GENERATED by tools/gen_training.py - do not edit by hand; edit the generator and run it again.")
    w("-- How a profession's skill cap is raised, rank by rank, and its specializations.")
    w("-- Sources: Wowhead's Forever pages of the rank spells (trainers, books, quests), Questie's Forever database")
    w("-- (who sells a book, who gives a quest), read " + read + "; a trainer's price from Wowhead's Forever spell lists.")
    w("--")
    w("-- Data.training[profession key] = {")
    w("--   ranks = { { name, cap (the skill it allows), needs (the skill it asks for), spell,")
    w("--               cost (what a trainer asks for it, in copper; a price read in a trainer's own window wins),")
    w("--               trainers = { { npc, zone, side } }, total (how many trainers there are in all),")
    w("--               book = { name, vendors = { { npc, zone, side } } },")
    w("--               quests = { { name, npc, zone, side, level,")
    w("--                            bring = { { id, count, name, icon } } (the items the quest wants brought) } },")
    w("--               unsure = true: the trainers are the rank below's - this rank's own were not read } },")
    w("--   specs = { { name, needs, level, quests = { { name, npc, zone, side, bring = { ... as a rank's quest } } } } }")
    w("--           -- Classic's quests; on Wowhead's Forever quest pages with the same words (read 2026-11-16)")
    w("-- }")
    w("local _, ns = ...")
    w("")
    w("ns.Data.training = {")
    for key, name, line, page, short, icon in source.PROFESSIONS:
        w("    %s = {" % key)
        w("        ranks = {")
        previous = None
        for rank, spell in zip(RANKS, SPELLS[key]):
            entry = pages.get(spell)
            unsure = False
            if not entry and previous:
                entry, unsure = {"trainers": previous.get("trainers"), "total": previous.get("total")}, True
            entry = entry or {}
            needs = NEEDS.get(rank)
            if entry.get("book") and entry["book"].get("skill"):
                needs = entry["book"]["skill"]
            if entry.get("quests") and entry["quests"][0].get("skill"):
                needs = entry["quests"][0]["skill"]
            # a trainer's price only where a trainer is the way: a book or a quest has none
            cost = costs.get(str(spell)) if entry.get("trainers") and not entry.get("book") and not entry.get("quests") else None
            w("            { name = %s, cap = %d,%s spell = %d,%s%s" % (lua(rank), CAPS[rank], (" needs = %d," % needs) if needs else "", spell,
                                                                    (" cost = %d," % cost) if cost else "", " unsure = true," if unsure else ""))
            if entry.get("trainers"):
                w("              total = %d, trainers = {" % entry.get("total", len(entry["trainers"])))
                for t in entry["trainers"]:
                    w("                %s," % fields([("npc", t["npc"]), ("zone", t["zone"]), ("side", t["side"])]))
                w("              },")
            if entry.get("book"):
                w("              book = { name = %s, vendors = {" % lua(entry["book"]["name"]))
                for v in entry["book"]["vendors"]:
                    w("                %s," % fields([("npc", v["npc"]), ("zone", v["zone"]), ("side", v["side"])]))
                w("              } },")
            if entry.get("quests"):
                w("              quests = {")
                for q in entry["quests"]:
                    quest_lines(w, q, [("name", q["name"]), ("npc", q["npc"]), ("zone", q["zone"]), ("side", q["side"]), ("level", q["level"])])
                w("              },")
            w("            },")
            if not unsure:
                previous = entry
        w("        },")
        if key in SPECS:
            w("        specs = {")
            for spec_name, quest_ids in SPECS[key]:
                quests = [q for q in (quest(i) for i in quest_ids) if q]
                needs = next((q["skill"] for q in quests if q.get("skill")), None)
                level = next((q["level"] for q in quests if q.get("level")), None)
                w("            { name = %s,%s%s quests = {" % (lua(spec_name), (" needs = %d," % needs) if needs else "", (" level = %d," % level) if level else ""))
                for q in quests:
                    quest_lines(w, q, [("name", q["name"]), ("npc", q["npc"]), ("zone", q["zone"]), ("side", q["side"])])
                w("            } },")
            w("        },")
        w("    },")
    w("}")
    w("")
    open(os.path.join(ROOT, "Data", "Training.lua"), "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print("Data/Training.lua:", len(out), "lines")


main()
