-- Locks: a Lockpicking tab - every lockbox, junkbox, locked chest and door, the skill it needs, where it is,
-- and whether the viewed rogue can open it now.
--
-- WHY. The user, 2026-11-12: "also can we get lockpicking on there" - chosen: a tab of locks, one card per
-- lockbox, junkbox, locked chest or door (not the skill shared with the guild).
--
-- WHAT IS KNOWN. Lockpicking has no recipes, and Forever's professions site does not cover it. The list is
-- Classic's: the items' ids and names checked against Wowhead's Forever item tooltips (2026-11-12: every one
-- of them exists and is "Locked"), the skills and places from the Lockpicking article (warcraft.wiki.gg) and
-- Classic's lockbox drop ranges. The tooltip service does not say the skill a lock needs; the game's own
-- tooltip may ("Requires Lockpicking (N)"): when it does, that number replaces Classic's and the card says it
-- was read from the game. Otherwise a card is marked "as in Classic".
--
-- The character's skill: skill line 633 (Lockpicking) asked of the trade skill API like a profession's,
-- else the old skill list (GetSkillLineInfo) by name. Kept per character like the professions' skills.
local _, ns = ...

local Locks = {}
ns.Locks = Locks

Locks.KEY = "lockpicking"
Locks.meta = { key = "lockpicking", name = "Lockpicking", short = "Locks", line = 633, icon = "ability_rogue_picklock" }
Locks.raw = nil -- what the client said of the skill, for /akr diag

-- kind: box (dropped), junk (pickpocketed), fished, item (other), chest (a world object), quest (a rogue
-- quest's chest), door. skill: Classic's. side: "A" / "H" when only one faction meets it.
local LIST = {
    { kind = "box", id = 4632, name = "Ornate Bronze Lockbox", skill = 1, from = "humanoids around level 10-20" },
    { kind = "box", id = 4633, name = "Heavy Bronze Lockbox", skill = 25, from = "humanoids around level 15-25" },
    { kind = "box", id = 4634, name = "Iron Lockbox", skill = 70, from = "humanoids around level 25-35" },
    { kind = "box", id = 4636, name = "Strong Iron Lockbox", skill = 125, from = "humanoids around level 30-40" },
    { kind = "box", id = 4637, name = "Steel Lockbox", skill = 175, from = "humanoids around level 40-50" },
    { kind = "box", id = 4638, name = "Reinforced Steel Lockbox", skill = 225, from = "humanoids around level 45-55" },
    { kind = "box", id = 5758, name = "Mithril Lockbox", skill = 225, from = "humanoids around level 50-58" },
    { kind = "box", id = 5759, name = "Thorium Lockbox", skill = 225, from = "humanoids around level 55-60" },
    { kind = "box", id = 5760, name = "Eternium Lockbox", skill = 225, from = "humanoids around level 58-63" },
    { kind = "junk", id = 16882, name = "Battered Junkbox", skill = 1, from = "pickpocketed from level 20-30" },
    { kind = "junk", id = 16883, name = "Worn Junkbox", skill = 70, from = "pickpocketed from level 30-40" },
    { kind = "junk", id = 16884, name = "Sturdy Junkbox", skill = 175, from = "pickpocketed from level 40-50" },
    { kind = "junk", id = 16885, name = "Heavy Junkbox", skill = 250, from = "pickpocketed from level 50-60" },
    { kind = "fished", id = 6354, name = "Small Locked Chest", skill = 1, from = "fished in Wetlands, Hillsbrad Foothills, Ashenvale" },
    { kind = "fished", id = 6355, name = "Sturdy Locked Chest", skill = 70, from = "fished in Stranglethorn Vale, Dustwallow Marsh, Swamp of Sorrows" },
    { kind = "fished", id = 13875, name = "Ironbound Locked Chest", skill = 175, from = "fished in The Hinterlands, Azshara, Tanaris, Feralas" },
    { kind = "fished", id = 13918, name = "Reinforced Locked Chest", skill = 250, from = "fished in Azshara" },
    { kind = "item", id = 6712, name = "Practice Lock", skill = 1, from = "made by Engineering (100) - practice" },
    { kind = "item", id = 12033, name = "Thaurissan Family Jewels", skill = 275, from = "Emperor Dagran Thaurissan, Blackrock Depths" },

    { kind = "chest", name = "Large Iron Bound Chest", skill = 25, icon = "inv_box_02",
        from = "Blackfathom Deeps, Gnomeregan, Razorfen Kraul and Downs, Scarlet Monastery, Shadowfang Keep, The Stockade" },
    { kind = "chest", name = "Large Mithril Bound Chest", skill = 175, icon = "inv_box_02", from = "Blackrock Spire, Dire Maul, Stratholme, Uldaman" },
    { kind = "chest", name = "Large Mithril Bound Chest (harder)", skill = 250, icon = "inv_box_02", from = "Western Plaguelands, Blackrock Spire, Dire Maul, Stratholme" },
    { kind = "chest", name = "Alliance Strongbox", skill = 1, icon = "inv_box_01", from = "The Barrens" },
    { kind = "chest", name = "Buccaneer's Strongbox", skill = 1, icon = "inv_box_01", from = "The Barrens" },
    { kind = "chest", name = "Venture Co. Strongbox", skill = 1, icon = "inv_box_01", from = "The Barrens" },
    { kind = "chest", name = "Practice Lockbox", skill = 1, icon = "inv_box_01", from = "Redridge Mountains" },
    { kind = "chest", name = "Alliance Strongbox (Alterac)", skill = 70, icon = "inv_box_01", from = "Alterac Mountains" },
    { kind = "chest", name = "Battered Footlocker", skill = 70, icon = "inv_box_01", from = "Stonetalon Mountains, Hillsbrad Foothills, Wetlands, Badlands" },
    { kind = "chest", name = "Waterlogged Footlocker", skill = 70, icon = "inv_box_01", from = "Ashenvale, Redridge Mountains" },
    { kind = "chest", name = "Battered Footlocker (harder)", skill = 110, icon = "inv_box_01", from = "Wetlands, Hillsbrad Foothills, Stonetalon Mountains" },
    { kind = "chest", name = "Battered Footlocker (Badlands)", skill = 150, icon = "inv_box_01", from = "Badlands" },
    { kind = "chest", name = "Waterlogged Footlocker (Desolace)", skill = 150, icon = "inv_box_01", from = "Desolace" },
    { kind = "chest", name = "Dented Footlocker", skill = 175, icon = "inv_box_01", from = "Badlands, Tanaris" },
    { kind = "chest", name = "Mossy Footlocker", skill = 175, icon = "inv_box_01", from = "Swamp of Sorrows, Desolace, Sunken Temple" },
    { kind = "chest", name = "Dented Footlocker (Searing Gorge)", skill = 200, icon = "inv_box_01", from = "Searing Gorge" },
    { kind = "chest", name = "Dented Footlocker (Tanaris)", skill = 225, icon = "inv_box_01", from = "Tanaris" },
    { kind = "chest", name = "Mossy Footlocker (Azshara)", skill = 225, icon = "inv_box_01", from = "Azshara" },
    { kind = "chest", name = "Scarlet Footlocker", skill = 250, icon = "inv_box_01", from = "Eastern Plaguelands" },

    { kind = "quest", name = "Lucius's Lockbox", skill = 25, side = "A", icon = "inv_box_02", from = "Redridge Mountains - rogue quest Alther's Mill" },
    { kind = "quest", name = "The Jewel of the Southsea", skill = 25, side = "H", icon = "inv_box_02", from = "The Barrens - rogue quest Plundering the Plunderers" },
    { kind = "quest", name = "Ambermill Strongbox", skill = 1, side = "H", icon = "inv_box_02", from = "Silverpine Forest - undead rogue quest Tools of the Trade" },
    { kind = "quest", name = "Duskwood Chest", skill = 70, side = "A", icon = "inv_box_02", from = "Westfall - rogue quest Klaven's Tower" },
    { kind = "quest", name = "Gallywix's Lockbox", skill = 70, side = "H", icon = "inv_box_02", from = "Westfall - rogue quest Mission: Possible But Not Probable" },
    { kind = "quest", name = "Benedict's Chest", skill = 100, side = "H", icon = "inv_box_02", from = "Durotar - quest The Admiral's Orders" },
    { kind = "quest", name = "Cozzle's Footlocker", skill = 160, icon = "inv_box_02", from = "Stranglethorn Vale - quest Goblin Sponsorship" },

    { kind = "door", name = "Ironclad Cove Gate", skill = 1, icon = "inv_misc_key_03", from = "The Deadmines", key = "Defias Gunpowder" },
    { kind = "door", name = "Gnomeregan Workshop Door", skill = 150, icon = "inv_misc_key_03", from = "Gnomeregan", key = "Workshop Key" },
    { kind = "door", name = "Scarlet Monastery Armory Door", skill = 175, icon = "inv_misc_key_03", from = "Scarlet Monastery", key = "The Scarlet Key" },
    { kind = "door", name = "Scarlet Monastery Cathedral Door", skill = 175, icon = "inv_misc_key_03", from = "Scarlet Monastery", key = "The Scarlet Key" },
    { kind = "door", name = "Searing Gorge Gate", skill = 225, icon = "inv_misc_key_03", from = "Loch Modan / Searing Gorge", key = "Key to Searing Gorge" },
    { kind = "door", name = "Shadowforge Gate", skill = 250, icon = "inv_misc_key_03", from = "Blackrock Depths", key = "Shadowforge Key" },
    { kind = "door", name = "Shadowforge Lock", skill = 250, icon = "inv_misc_key_03", from = "Blackrock Depths", key = "Shadowforge Key" },
    { kind = "door", name = "East Garrison Door", skill = 280, icon = "inv_misc_key_03", from = "Blackrock Depths", key = "Shadowforge Key" },
    { kind = "door", name = "Prison Cells", skill = 280, icon = "inv_misc_key_03", from = "Blackrock Depths", key = "Prison Cell Key" },
    { kind = "door", name = "Scholomance Door", skill = 280, icon = "inv_misc_key_03", from = "Scholomance", key = "Skeleton Key" },
    { kind = "door", name = "Scarlet Bastion Door", skill = 300, icon = "inv_misc_key_03", from = "Stratholme", key = "The Scarlet Key" },
    { kind = "door", name = "Stratholme Gate", skill = 300, icon = "inv_misc_key_03", from = "Stratholme", key = "Key to the City" },
    { kind = "door", name = "Crescent Door", skill = 300, icon = "inv_misc_key_03", from = "Dire Maul", key = "Crescent Key" },
}
Locks.LIST = LIST

local KIND_TAG = {
    box = "|cffc79cffDrop|r", junk = "|cffe6cc80Pickpocket|r", fished = "|cff80d0ffFished|r", item = "|cffff9d5cItem|r",
    chest = "|cffffff00Chest|r", quest = "|cffffff00Quest|r", door = "|cffd0a0ffDoor|r",
}
local ITEM_ICONS = { box = "inv_misc_ornatebox", junk = "inv_box_01", fished = "inv_box_03", item = "inv_box_01" }

------------------------------------------------------------------------
-- The skill a lock needs: the game's tooltip when it says, else Classic's
------------------------------------------------------------------------
Locks.read = {} -- [item id] = the skill the game's tooltip named; false = asked, it named none

local function fromTooltip(id)
    local cached = Locks.read[id]
    if cached ~= nil then
        return cached or nil
    end
    local api = C_TooltipInfo
    if type(api) ~= "table" or type(api.GetItemByID) ~= "function" then
        return nil
    end
    local ok, data = pcall(api.GetItemByID, id)
    if not ok or type(data) ~= "table" or ns.IsSecret(data) or type(data.lines) ~= "table" then
        return nil -- (not cached: the item may not be loaded yet)
    end
    for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and ns.ReadableString(line.leftText)
        local skill = text and tonumber(string.match(text, "Lockpicking%s*%((%d+)%)"))
        if skill then
            Locks.read[id] = skill
            return skill
        end
    end
    Locks.read[id] = false
    return nil
end

function Locks.Needs(lock)
    local measured = lock.id and fromTooltip(lock.id)
    if measured then
        return measured, true
    end
    return lock.skill, false
end

------------------------------------------------------------------------
-- The character's skill
------------------------------------------------------------------------
function Locks:ReadSkill()
    local skill, max, how
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
    if type(fn) == "function" then
        local ok, info = pcall(fn, Locks.meta.line)
        if ok and type(info) == "table" and not ns.IsSecret(info) then
            skill, max = ns.ReadableNumber(info.skillLevel), ns.ReadableNumber(info.maxSkillLevel)
            how = "trade skill API"
            if skill == 0 then
                skill = nil
            end
        end
    end
    if not skill and type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        local okCount, count = pcall(GetNumSkillLines)
        for i = 1, (okCount and ns.ReadableNumber(count)) or 0 do
            local ok, name, header, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
            if ok and not header and ns.ReadableString(name) == "Lockpicking" then
                skill, max, how = ns.ReadableNumber(rank), ns.ReadableNumber(maxRank), "skill list"
                break
            end
        end
    end
    Locks.raw = { skill = skill or false, max = max or false, how = how or "nothing answered" }
    if ns.cdb then
        local class = type(UnitClass) == "function" and select(2, UnitClass("player")) or nil
        if not ns.IsSecret(class) and type(class) == "string" then
            ns.cdb.class = class
        end
        if skill and skill > 0 then
            ns.cdb.lockpick = { skill = skill, max = max }
        end
    end
end

-- the viewed character's skill, nil when not known; and whether the tab belongs to it at all
function Locks.Skill(profile)
    local saved = type(profile) == "table" and profile.lockpick
    if type(saved) == "table" and type(saved.skill) == "number" then
        return saved.skill, saved.max
    end
    return nil
end

function Locks.Offered(profile)
    return type(profile) == "table" and (profile.class == "ROGUE" or Locks.Skill(profile) ~= nil)
end

------------------------------------------------------------------------
-- The cards
------------------------------------------------------------------------
local function matches(lock, query)
    if not query or query == "" then
        return true
    end
    query = string.lower(query)
    return string.find(string.lower(lock.name), query, 1, true) ~= nil
        or string.find(string.lower(lock.from or ""), query, 1, true) ~= nil
        or (lock.key and string.find(string.lower(lock.key), query, 1, true) ~= nil)
end

-- cards for Window (its entry shape), and the totals; open: [name] = true for the opened cards
function Locks:Lines(profile, filter, query, open, colour, render)
    local lines = {}
    local skill = Locks.Skill(profile)
    local side = type(profile) == "table" and profile.side or nil
    local total, can, shown = 0, 0, 0
    local sorted = {}
    for _, lock in ipairs(LIST) do
        if not lock.side or not side or lock.side == side then
            sorted[#sorted + 1] = lock
        end
    end
    table.sort(sorted, function(a, b)
        local na, nb = Locks.Needs(a), Locks.Needs(b)
        if na ~= nb then
            return na < nb
        end
        return a.name < b.name
    end)
    for _, lock in ipairs(sorted) do
        local needs, measured = Locks.Needs(lock)
        local opens = skill ~= nil and skill >= needs
        total = total + 1
        if opens then
            can = can + 1
        end
        local wanted = (filter ~= "known" or opens) and (filter ~= "missing" or not opens) and filter ~= "hidden"
        if wanted and matches(lock, query) then
            shown = shown + 1
            local state = (skill == nil and "plain") or (opens and "known") or (skill + 25 >= needs and "now") or "later"
            local right = (skill == nil and (colour.dim .. "needs " .. needs .. "|r"))
                or (opens and (colour.known .. "You can open it|r"))
                or (colour.later .. (needs - skill) .. " more skill|r")
            local entry = {
                card = true, icon = lock.icon or ITEM_ICONS[lock.kind], skill = needs, state = state, skillLabel = "Lockpicking",
                tags = KIND_TAG[lock.kind] .. (measured and "" or (colour.dim .. "   as in Classic|r")),
                text = colour.head .. lock.name .. "|r", desc = colour.dim .. lock.from .. "|r", right = right,
                item = lock.id,
                click = function()
                    open[lock.name] = not open[lock.name] or nil
                    render()
                end,
            }
            if open[lock.name] then
                local details = {
                    { text = colour.dim .. "Needs |r" .. needs .. " Lockpicking" .. (measured and (colour.dim .. " (read from the game)|r") or (colour.dim .. " (as in Classic - not confirmed for Forever)|r")), right = "" },
                    { text = colour.dim .. "Where: |r" .. lock.from, right = "", wrap = true },
                }
                if lock.key then
                    details[#details + 1] = { text = colour.dim .. "Or open it with: |r" .. lock.key, right = "" }
                end
                if lock.side then
                    details[#details + 1] = { text = colour.dim .. (lock.side == "A" and "Alliance" or "Horde") .. " only|r", right = "" }
                end
                details[#details + 1] = { text = colour.dim .. "Your skill: |r" .. (skill and tostring(skill) or "not known - pick a lock once, or open the skill list"), right = "" }
                entry.details = details
            end
            lines[#lines + 1] = entry
        end
    end
    return lines, { total = total, known = can, shown = shown, skill = skill }
end

function Locks:Describe()
    local measured = 0
    for _, value in pairs(Locks.read) do
        if value then measured = measured + 1 end
    end
    return { raw = Locks.raw, readFromTooltip = measured, entries = #LIST }
end

for _, event in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do
    ns:On(event, function()
        Locks:ReadSkill()
    end)
end
ns:Listen("LOGIN", function()
    Locks:ReadSkill()
end)
