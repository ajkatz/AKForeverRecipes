# Reads the installed QuestieDB's Forever database (its baked TOC: "## X-<Entity>-<id>-<field>: <base64 CBOR>")
# for where items come from: the NPCs that drop them, the objects, the containers, the quests that reward
# them, the vendors. Used by research.py to look for sources the profession pages do not have.
#
# QuestieDB is GPL-3.0; nothing of it is copied into the addon's code - only facts looked up here (who
# sells what) end up, with their provenance, in tools/found_sources.json. Not shipped to players.
import base64
import os
import re

TOC = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\QuestieDB\QuestieDB_Forever.toc"
ITEM_FIELDS = {2: "npcDrops", 3: "objectDrops", 4: "itemDrops", 6: "questRewards", 14: "vendors", 16: "teachesSpell"}


def cbor(data, at=0):
    """A minimal CBOR decoder: enough for the integers, strings, arrays and maps of the baked store."""
    first = data[at]
    major, info = first >> 5, first & 31
    at += 1
    if info < 24:
        value = info
    elif info == 24:
        value, at = data[at], at + 1
    elif info == 25:
        value, at = int.from_bytes(data[at:at + 2], "big"), at + 2
    elif info == 26:
        value, at = int.from_bytes(data[at:at + 4], "big"), at + 4
    elif info == 27:
        value, at = int.from_bytes(data[at:at + 8], "big"), at + 8
    else:
        raise ValueError("indefinite or reserved CBOR at %d" % at)
    if major == 0:
        return value, at
    if major == 1:
        return -1 - value, at
    if major == 2:
        return bytes(data[at:at + value]), at + value
    if major == 3:
        return data[at:at + value].decode("utf-8", "replace"), at + value
    if major == 4:
        items = []
        for _ in range(value):
            item, at = cbor(data, at)
            items.append(item)
        return items, at
    if major == 5:
        result = {}
        for _ in range(value):
            k, at = cbor(data, at)
            v, at = cbor(data, at)
            result[k] = v
        return result, at
    if major == 7:
        if info == 20:
            return False, at
        if info == 21:
            return True, at
        if info == 22:
            return None, at
        if info == 26:
            import struct
            return struct.unpack(">f", data[at - 4:at])[0], at
        if info == 27:
            import struct
            return struct.unpack(">d", data[at - 8:at])[0], at
        return value, at
    raise ValueError("CBOR major %d" % major)


def decode(text):
    value, _ = cbor(base64.b64decode(text))
    return value


class Store:
    def __init__(self, path=TOC):
        self.lines = {}
        if not os.path.exists(path):
            return
        pattern = re.compile(r"^## X-(Item|Npc|Object|Quest)-(\d+)-(\w+): (.*)$")
        for line in open(path, encoding="utf-8", errors="replace"):
            m = pattern.match(line.rstrip("\n"))
            if m:
                self.lines[(m.group(1), int(m.group(2)), m.group(3))] = m.group(4)

    def available(self):
        return bool(self.lines)

    def raw(self, entity, entity_id, field):
        text = self.lines.get((entity, entity_id, str(field)))
        if text is None:
            return None
        try:
            return decode(text)
        except Exception as error:  # noqa: BLE001
            return {"error": str(error)}

    def summary(self, entity, entity_id):
        """the record's short fields as { field index: value }; {} when absent or stored another way"""
        value = self.raw(entity, entity_id, "S")
        if isinstance(value, list):  # some records store their fields as a plain list, in order
            return {index + 1: v for index, v in enumerate(value) if v is not None}
        return value if isinstance(value, dict) else {}

    def has(self, entity, entity_id):
        return (entity, entity_id, "S") in self.lines
