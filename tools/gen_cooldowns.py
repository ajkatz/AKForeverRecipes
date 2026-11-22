# Writes Data/Cooldowns.lua: the crafts of our recipe tables that have a cooldown worth watching.
#
#   python tools/gen_cooldowns.py          (from the repo root; run tools/gen_data.py first)
#
# Source: the Forever client's own tables, as wago.tools exports them (the build research.py reads):
#   SpellCooldowns   RecoveryTime (the spell's own cooldown) and CategoryRecoveryTime (the cooldown it
#                    puts on every spell of its category), in milliseconds
#   SpellCategories  the spell's category (310 = "Transmute - Alchemy")
#   SpellCategory    the categories' names
#   SpellName        the spells' names ("Transmute: Arcanite" - our recipe tables name what is made)
# The files are kept in tools/pages/research (git-ignored) and asked for once.
#
# Checked 2026-11-18 (the user: "i know legionite and arcanite have different cooldowns"): the same
# tables of build 1.60.1.70959, the one installed, give the same rows for every spell here, and the
# client's hotfix cache (Cache/ADB/enUS/DBCache.bin: 92 SpellCooldowns and 162 SpellCategories records)
# holds none for them. Arcanite (17187) and Legionite (1317279) are both category 310, 47 hours.
#
# Rules: a cooldown of ten minutes or more counts. Spells of one category with a category cooldown are
# ONE cooldown (a transmute puts every transmute on cooldown, each for its own length); a spell with a
# cooldown of its own is its own. Refined Deeprock Salt is no recipe: it comes from using the Salt
# Shaker (item 15846, use spell 19566), listed by hand below with the length the table gives.
import csv
import glob
import io
import os
import re
import sys
import urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CACHE = os.path.join(ROOT, "tools", "pages", "research")
WAGO = "https://wago.tools/db2/%s/csv?build=%s"
CLIENT_BUILD = "1.60.1.70938"
MINIMUM = 600  # seconds

CATEGORY_NAMES = {310: ("transmute", "Transmute")}  # [category] = (key, name); others: "c<id>", the table's name
SALT = {"key": "salt", "name": "Refined Deeprock Salt", "prof": "leatherworking", "item": 15846, "itemName": "Salt Shaker",
        "use": 19566, "makes": 15409, "icon": "inv_misc_dust_01"}


def table(name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name + ".csv")
    if not os.path.exists(path):
        request = urllib.request.Request(WAGO % (name, CLIENT_BUILD), headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read()
        with open(path, "wb") as out:
            out.write(data)
    with io.open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def lua(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    own, shared = {}, {}
    for r in table("SpellCooldowns"):
        if r["DifficultyID"] == "0":
            spell = int(r["SpellID"])
            own[spell], shared[spell] = int(r["RecoveryTime"]) // 1000, int(r["CategoryRecoveryTime"]) // 1000
    category = {}
    for r in table("SpellCategories"):
        if r["DifficultyID"] == "0":
            category[int(r["SpellID"])] = int(r["Category"])
    category_names = {int(r["ID"]): r["Name_lang"] for r in table("SpellCategory")}
    names = {int(r["ID"]): r["Name_lang"] for r in table("SpellName")}

    # our recipes: spell -> (profession key, made item, icon)
    recipes = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "Data", "*.lua"))):
        text = io.open(path, encoding="utf-8").read()
        key = re.search(r"ns\.Data\.Register\(\{ key = \"(\w+)\"", text)
        if not key:
            continue
        for m in re.finditer(r"spell = (\d+), item = (\d+|nil), name = \"([^\"]+)\", icon = \"([^\"]*)\"", text):
            recipes[int(m.group(1))] = (key.group(1), m.group(2), m.group(4), m.group(3))

    groups, by_category = [], {}
    for spell in sorted(recipes):
        prof, item, icon, made = recipes[spell]
        entry = {"spell": spell, "name": names.get(spell) or made, "item": item, "icon": icon}
        cat = category.get(spell, 0)
        if cat and shared.get(spell, 0) >= MINIMUM:
            entry["seconds"] = shared[spell]
            group = by_category.get(cat)
            if not group:
                key, name = CATEGORY_NAMES.get(cat, ("c%d" % cat, category_names.get(cat, "Category %d" % cat)))
                group = {"key": key, "name": name, "prof": prof, "shared": True, "spells": []}
                by_category[cat] = group
                groups.append(group)
            group["spells"].append(entry)
        elif own.get(spell, 0) >= MINIMUM:
            entry["seconds"] = own[spell]
            groups.append({"key": "s%d" % spell, "name": entry["name"], "prof": prof, "spells": [entry]})
    for group in groups:
        group["spells"].sort(key=lambda e: (-e["seconds"], e["name"]))
    groups.sort(key=lambda g: (-g["spells"][0]["seconds"], g["name"]))

    salt = dict(SALT)
    salt["seconds"] = max(own.get(SALT["use"], 0), shared.get(SALT["use"], 0))
    if salt["seconds"] < MINIMUM:
        sys.exit("the Salt Shaker's use spell %d has no cooldown in the table" % SALT["use"])

    out = []
    out.append("-- GENERATED by tools/gen_cooldowns.py - do not edit by hand; edit the generator and run it again.")
    out.append("-- Source: the Forever client's spell tables (build %s, as wago.tools exports them): which of our" % CLIENT_BUILD)
    out.append("-- recipes have a cooldown of ten minutes or more, and how long it is (seconds).")
    out.append("--")
    out.append("-- A group is ONE cooldown. shared = true: the spells of one category - making any of them puts all of")
    out.append("-- them on cooldown, for the length of the one that was made. item = ...: not a recipe but an item's")
    out.append("-- use (the Salt Shaker), tracked for whoever owns the item.")
    out.append("local _, ns = ...")
    out.append("")
    out.append("ns.CooldownData = {")
    out.append("    build = %s," % lua(CLIENT_BUILD))
    out.append("    groups = {")
    for group in groups:
        out.append("        { key = %s, name = %s, prof = %s, %sspells = {" % (
            lua(group["key"]), lua(group["name"]), lua(group["prof"]), "shared = true, " if group.get("shared") else ""))
        for e in group["spells"]:
            out.append("            { spell = %d, seconds = %d, name = %s, item = %s, icon = %s }," % (
                e["spell"], e["seconds"], lua(e["name"]), e["item"], lua(e["icon"])))
        out.append("        } },")
    out.append("        { key = %s, name = %s, prof = %s, item = %d, itemName = %s, use = %d, seconds = %d, makes = %d, icon = %s }," % (
        lua(salt["key"]), lua(salt["name"]), lua(salt["prof"]), salt["item"], lua(salt["itemName"]), salt["use"],
        salt["seconds"], salt["makes"], lua(salt["icon"])))
    out.append("    },")
    out.append("}")
    out.append("")
    with io.open(os.path.join(ROOT, "Data", "Cooldowns.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print("Data/Cooldowns.lua: %d cooldowns" % (len(groups) + 1))
    for group in groups:
        print("  %-28s %-14s %s" % (group["name"], group["prof"],
                                   ", ".join("%s %dh" % (e["name"], e["seconds"] // 3600) for e in group["spells"])))
    print("  %-28s %-14s %s %dh" % (salt["name"], salt["prof"], salt["itemName"], salt["seconds"] // 3600))


main()
