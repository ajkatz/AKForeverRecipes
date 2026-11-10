# Asks Wowhead's Forever tooltip service how every recipe ITEM of every profession binds, and writes
# tools/binds.json:
#   { "<item id>": { "bind": "pickup" | "equip" | "use" | "none", "spell": <the spell it teaches>, "unique": bool, "name": ... } }
#
#   python tools/fetch_binds.py            (the pages saved under tools/pages, see source.py)
#
# Items already in binds.json are not asked again (delete the file to start over); the file is saved every
# 50 items, so an interrupted run loses little. gen_data.py reads the file. Not shipped to players.
import json
import os
import re
import time
import urllib.request

import source

OUT = os.path.join(source.HERE, "binds.json")
URL = "https://nether.wowhead.com/forever/tooltip/item/%d"


def save(binds):
    json.dump(binds, open(OUT, "w", encoding="utf-8", newline="\n"), indent=1, sort_keys=True)


def main():
    ids = source.formula_ids()
    binds = source.load_binds()
    asked = 0
    for item_id in ids:
        if str(item_id) in binds:
            continue
        request = urllib.request.Request(URL % item_id, headers={"User-Agent": "Mozilla/5.0"})
        try:
            tip = json.loads(urllib.request.urlopen(request, timeout=20).read().decode("utf-8"))
        except Exception as error:  # noqa: BLE001 - reported, and asked again on the next run
            print(item_id, "failed:", error, flush=True)
            continue
        tooltip = tip.get("tooltip") or ""
        # A recipe's tooltip carries the tooltip of what it makes underneath: only the FIRST bind slot
        # (between the "bo" and "ue" markers) is the recipe item's own - the second is the made item's.
        own = re.search(r"<!--bo-->(.*?)<!--ue-->", tooltip, re.S)
        own = own.group(1) if own else ""
        bind = "none"
        if "Binds when picked up" in own:
            bind = "pickup"
        elif "Binds when equipped" in own:
            bind = "equip"
        elif "Binds when used" in own:
            bind = "use"
        spell = re.search(r"/forever/spell=(\d+)/", tooltip)
        binds[str(item_id)] = {"bind": bind, "spell": int(spell.group(1)) if spell else None, "unique": "Unique" in own, "name": tip.get("name")}
        asked += 1
        if asked % 50 == 0:
            save(binds)
            print(asked, "asked", flush=True)
        time.sleep(0.15)
    save(binds)
    counts = {}
    for item_id in ids:
        entry = binds.get(str(item_id))
        word = entry["bind"] if entry else "not answered"
        counts[word] = counts.get(word, 0) + 1
    print(len(ids), "recipe items;", counts)


main()
