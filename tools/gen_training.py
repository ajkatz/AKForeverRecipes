# Writes Data/Training.lua: how each profession's skill cap is raised - who teaches Apprentice,
# Journeyman, Expert and Artisan, the books and quests that stand in for a trainer - and the
# specializations of Blacksmithing, Engineering and Leatherworking.
#
#   python tools/gen_training.py
#
# From: tools/wowhead_ranks.txt (Wowhead's Forever pages of the rank spells: trainers, the Expert books,
# the Artisan quests), the installed QuestieDB Forever database (who sells a book, who gives a quest - the
# specialization quests are found there by their ids) and the client's AreaTable for zone names
# (tools/pages/research/AreaTable.csv, fetched by research.py).
#
# The skill a rank needs (50 / 125 / 200) is Classic's; a book's or a quest's own requirement is used where
# one is known. The specialization quests are Classic's, found in Questie's Forever database - whether
# Forever keeps them is not confirmed, and the window says so. Not shipped to players.
import csv
import datetime
import os

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
                "level": s.get(4), "skill": skill[1] if isinstance(skill, list) and len(skill) > 1 else None}

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

    out = []
    w = out.append
    w("-- GENERATED by tools/gen_training.py - do not edit by hand; edit the generator and run it again.")
    w("-- How a profession's skill cap is raised, rank by rank, and its specializations.")
    w("-- Sources: Wowhead's Forever pages of the rank spells (trainers, books, quests), Questie's Forever database")
    w("-- (who sells a book, who gives a quest), read " + datetime.date.today().isoformat() + ".")
    w("--")
    w("-- Data.training[profession key] = {")
    w("--   ranks = { { name, cap (the skill it allows), needs (the skill it asks for), spell,")
    w("--               trainers = { { npc, zone, side } }, total (how many trainers there are in all),")
    w("--               book = { name, vendors = { { npc, zone, side } } },")
    w("--               quests = { { name, npc, zone, side, level } },")
    w("--               unsure = true: the trainers are the rank below's - this rank's own were not read } },")
    w("--   specs = { { name, needs, level, quests = { { name, npc, zone, side } } } }  -- as in Classic, unconfirmed")
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
            w("            { name = %s, cap = %d,%s spell = %d,%s" % (lua(rank), CAPS[rank], (" needs = %d," % needs) if needs else "", spell, " unsure = true," if unsure else ""))
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
                    w("                %s," % fields([("name", q["name"]), ("npc", q["npc"]), ("zone", q["zone"]), ("side", q["side"]), ("level", q["level"])]))
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
                    w("                %s," % fields([("name", q["name"]), ("npc", q["npc"]), ("zone", q["zone"]), ("side", q["side"])]))
                w("            } },")
            w("        },")
        w("    },")
    w("}")
    w("")
    open(os.path.join(ROOT, "Data", "Training.lua"), "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print("Data/Training.lua:", len(out), "lines")


main()
