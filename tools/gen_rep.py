# Which recipe ITEMS need a reputation standing before they can be bought or used, and writes
# tools/rep_requirements.json:
#   { "<recipe item id>": { "faction": <id>, "name": "Timbermaw Hold", "standing": 5, "word": "Honored" } }
#
#   python tools/gen_rep.py
#
# Source: the Forever client's own item table, as wago.tools exports it (ItemSparse: MinFactionID and
# MinReputation - the line the game's tooltip shows as "Requires Timbermaw Hold - Honored") and its
# Faction table for the names. Two downloads, kept under tools/pages/research; delete them to read a
# newer build. gen_data.py reads the json. Not shipped to players.
import csv
import io
import json
import os
import urllib.request

import source

CACHE = os.path.join(source.HERE, "pages", "research")
OUT = os.path.join(source.HERE, "rep_requirements.json")
WAGO = "https://wago.tools/db2/%s/csv?build=%s"
CLIENT_BUILD = "1.60.1.70959"
STANDINGS = {0: "Hated", 1: "Hostile", 2: "Unfriendly", 3: "Neutral", 4: "Friendly", 5: "Honored", 6: "Revered", 7: "Exalted"}


def table(name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "%s.%s.csv" % (name, CLIENT_BUILD))
    if not os.path.exists(path):
        request = urllib.request.Request(WAGO % (name, CLIENT_BUILD), headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=300) as response:
            data = response.read()
        with open(path, "wb") as out:
            out.write(data)
    with io.open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def main():
    wanted = set(source.formula_ids())
    factions = {}
    for row in table("Faction"):
        factions[int(row["ID"])] = row.get("Name_lang") or ""
    found = {}
    for row in table("ItemSparse"):
        item_id = int(row["ID"])
        if item_id not in wanted:
            continue
        faction, standing = int(row.get("MinFactionID") or 0), int(row.get("MinReputation") or 0)
        if faction <= 0:
            continue
        found[str(item_id)] = {"faction": faction, "name": factions.get(faction, ""), "standing": standing,
                               "word": STANDINGS.get(standing, "?"), "item": row.get("Display_lang") or ""}
    json.dump(found, open(OUT, "w", encoding="utf-8", newline="\n"), indent=1, sort_keys=True)
    by_faction = {}
    for entry in found.values():
        key = "%s - %s" % (entry["name"] or entry["faction"], entry["word"])
        by_faction[key] = by_faction.get(key, 0) + 1
    print(len(wanted), "recipe items;", len(found), "need a standing")
    for key in sorted(by_faction):
        print("  %-40s %d" % (key, by_faction[key]))


main()
