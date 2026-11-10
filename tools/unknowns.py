# Lists what the pages leave open, as JSON (tools/unknowns.json) and a summary:
#   unknown   a recipe item exists, no source is published
#   unsure    Forever added it, no recipe item exists, no source: shown as "probably a trainer"
#   byquest   "a quest teaches it", which one is not said
#   nospell   Enchanting: an enchant with no spell id (left out of the addon)
# and the recipes whose source IS known (known), to calibrate another source against.
import collections
import json
import os

import source

binds = source.load_binds()
out = {"unknown": [], "unsure": [], "byquest": [], "nospell": [], "known": []}
for key, name, line, page, short, icon in source.PROFESSIONS:
    rows, skipped = source.load(key, binds)
    for s in skipped:
        if s.startswith("no spell for "):
            out["nospell"].append({"prof": key, "name": s[len("no spell for "):]})
    for r in rows:
        src = r["source"]
        has = bool(src.get("vendors") or src.get("quests") or src.get("drops") or src.get("world") or src.get("trainers")
                   or src.get("capitals") or src.get("made") or src.get("objects"))
        entry = {"prof": key, "spell": r["spell"], "item": r["item"], "name": r["name"], "learn": r["learn"], "new": r["new"],
                 "formula": r["formula"] and r["formula"]["id"], "formulaName": r["formula"] and r["formula"]["name"]}
        if has:
            entry["source"] = {k: src[k] for k in ("vendors", "quests", "drops", "world", "trainers", "capitals", "made", "objects", "read") if src.get(k)}
            out["known"].append(entry)
        elif r["formula"]:
            entry["bind"] = (binds.get(str(r["formula"]["id"])) or {}).get("bind")
            out["unknown"].append(entry)
        elif r["byQuest"]:
            out["byquest"].append(entry)
        elif r["new"]:
            out["unsure"].append(entry)

json.dump(out, open(os.path.join(source.HERE, "unknowns.json"), "w", encoding="utf-8", newline="\n"), indent=1)
for kind in ("unknown", "unsure", "byquest", "nospell", "known"):
    by = collections.Counter(e["prof"] for e in out[kind])
    print("%-8s %4d  %s" % (kind, len(out[kind]), dict(by)))
u = out["unknown"]
print("unknown: new", sum(1 for e in u if e["new"]), "classic", sum(1 for e in u if not e["new"]), "| bop", sum(1 for e in u if e["bind"] == "pickup"))
print("classic unknown e.g.", [e["formulaName"] for e in u if not e["new"]][:12])
print("new unknown e.g.", [e["formulaName"] for e in u if e["new"]][:12])
