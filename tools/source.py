# Reads the saved profession pages of foreverchanges.pro into one shape for fetch_binds.py and gen_data.py.
#
#   mkdir tools/pages
#   for each page below:  curl -sL -A "Mozilla/5.0" -o tools/pages/<page>.html https://foreverchanges.pro/professions/<page>
#
# Each page is a Next.js page: its data sits in self.__next_f.push([1,"..."]) chunks, as JSON inside JS
# string literals. Eight pages hold "rows" (one entry per recipe) and "items" (names and icons by item id);
# the Enchanting page holds "enchants" (no spell ids: joined by name with its "recipes" map, or by the
# spell Wowhead says the formula teaches) plus a short "rows" list for rods and oils.
# Not shipped to players.
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(HERE, "pages")

# key, name, skill line id, page, short label, the icon of the profession
PROFESSIONS = [
    ("alchemy", "Alchemy", 171, "alchemy", "Alch", "trade_alchemy"),
    ("blacksmithing", "Blacksmithing", 164, "blacksmithing", "BS", "trade_blacksmithing"),
    ("enchanting", "Enchanting", 333, "enchanting", "Ench", "trade_engraving"),
    ("engineering", "Engineering", 202, "engineering", "Eng", "trade_engineering"),
    ("leatherworking", "Leatherworking", 165, "leatherworking", "LW", "inv_misc_armorkit_17"),
    ("tailoring", "Tailoring", 197, "tailoring", "Tailor", "trade_tailoring"),
    ("cooking", "Cooking", 185, "cooking", "Cook", "inv_misc_food_15"),
    ("firstaid", "First Aid", 129, "first-aid", "Aid", "spell_holy_sealofsacrifice"),
    ("mining", "Mining", 186, "mining", "Mining", "trade_mining"),
]

DECODER = json.JSONDecoder()


def payload(page):
    html = open(os.path.join(PAGES, page + ".html"), encoding="utf-8").read()
    chunks = re.findall(r'self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)', html)
    return "".join(json.loads(chunk) for chunk in chunks)


def decode_at(text, marker, back=0):
    at = text.find(marker)
    if at < 0:
        return None
    value, _ = DECODER.raw_decode(text, at + back)
    return value


def load_binds():
    path = os.path.join(HERE, "binds.json")
    return json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}


def load_found():
    """what research.py found for the recipes the pages leave open (found_sources.json), or {}"""
    path = os.path.join(HERE, "found_sources.json")
    return json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}


def load(key, binds=None, found=None):
    """The recipes of one profession: a list of dicts
       spell, item, name, icon, learn, yellow, green, grey, new, kind, stats, effect, count,
       formula {id, name, bound} | None, source {...} | {}, byQuest,
       reagents [ {id, count, name, icon} ], station {id, name} | None (the camp object it is made at)"""
    binds = binds if binds is not None else load_binds()
    page = next(p[3] for p in PROFESSIONS if p[0] == key)
    text = payload(page)
    items = decode_at(text, '"items":{', back=len('"items":')) or {}
    rows = decode_at(text, '[{"spell":') or []
    result, skipped = [], []

    def item(item_id):
        return items.get(str(item_id)) or {}

    def reagents(entries):
        return [{"id": e["id"], "count": e.get("count") or 1, "name": item(e["id"]).get("n"), "icon": item(e["id"]).get("k")} for e in entries or []]

    def station(item_id):
        return item_id and {"id": item_id, "name": item(item_id).get("n")} or None

    if key != "enchanting":
        for r in rows:
            dish = item(r["id"])
            if not dish.get("n"):
                skipped.append("no name for item %s (spell %s)" % (r["id"], r["spell"]))
                continue
            result.append({
                "spell": r["spell"], "item": r["id"], "name": dish["n"], "icon": dish.get("k"),
                "learn": r["learn"], "yellow": r["yellow"], "green": r["green"], "grey": r["grey"],
                "new": bool(r.get("isNew")), "kind": r.get("kind") or "", "stats": r.get("stats") or [],
                "effect": r.get("effect") or "", "count": r.get("count") or 1,
                "formula": r.get("formula"), "source": r.get("source") or {}, "byQuest": bool(r.get("byQuest")),
                "reagents": reagents(r.get("reagents")), "station": station(r.get("station")),
                "spec": {20219: "Gnomish", 20222: "Goblin"}.get(r.get("spec")),
            })
        return result, skipped

    # Enchanting
    enchants = decode_at(text, '"enchants":[', back=len('"enchants":')) or []
    recipes = decode_at(text, '"recipes":{"', back=len('"recipes":')) or {}
    spell_by_name = {}
    for spell, recipe in recipes.items():
        spell_by_name.setdefault(recipe["name"], int(spell))
    seen = set()
    for e in enchants:
        formula = e.get("formula")
        spell = spell_by_name.get(e["name"])
        if not spell and formula:
            spell = (binds.get(str(formula["id"])) or {}).get("spell")
        if not spell and found:
            spell = (found.get("spells", {}).get(key) or {}).get(e["name"])  # by name in the client's skill line
        if not spell:
            skipped.append("no spell for " + e["name"])
            continue
        if spell in seen:
            continue
        seen.add(spell)
        result.append({
            "spell": spell, "item": None, "name": e["name"], "icon": "trade_engraving",
            "learn": e["learn"], "yellow": e["yellow"], "green": e.get("green") or e["yellow"], "grey": e["grey"],
            "new": bool(e.get("isNew")), "kind": "", "stats": [], "effect": e.get("text") or "", "count": 1,
            "formula": formula and {"id": formula["id"], "name": formula["name"], "bound": formula.get("bound")},
            "source": e.get("source") or {}, "byQuest": False,
            "reagents": reagents(e.get("reagents")), "station": None,
        })
    for r in rows:  # rods, oils, wands: made items
        if r["spell"] in seen:
            continue
        thing = item(r["id"])
        if not thing.get("n"):
            skipped.append("no name for item %s (spell %s)" % (r["id"], r["spell"]))
            continue
        seen.add(r["spell"])
        taught = r.get("taught_by")
        result.append({
            "spell": r["spell"], "item": r["id"], "name": thing["n"], "icon": thing.get("k"),
            "learn": r["learn"], "yellow": r["yellow"], "green": r.get("green") or r["yellow"], "grey": r["grey"],
            "new": bool(r.get("isNew")), "kind": "", "stats": [], "effect": "", "count": r.get("count") or 1,
            "formula": taught and {"id": taught, "name": item(taught).get("n") or ("item " + str(taught))},
            "source": {}, "byQuest": False,
            "reagents": reagents((recipes.get(str(r["spell"])) or {}).get("reagents")), "station": None,
        })
    return result, skipped


def formula_ids():
    """Every recipe item id of every profession (Enchanting's before its spells are known)."""
    ids = set()
    for key, _, _, page, _, _ in PROFESSIONS:
        text = payload(page)
        for r in decode_at(text, '[{"spell":') or []:
            if r.get("formula"):
                ids.add(r["formula"]["id"])
            if r.get("taught_by"):
                ids.add(r["taught_by"])
        for e in decode_at(text, '"enchants":[', back=len('"enchants":')) or []:
            if e.get("formula"):
                ids.add(e["formula"]["id"])
    return sorted(ids)
