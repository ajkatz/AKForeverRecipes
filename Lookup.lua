-- Lookup: the questions the rest of the addon asks of the recipe tables - a profession's recipes, a recipe
-- by its spell or by the recipe item that teaches it, where a recipe comes from for one faction, a search
-- by name, place or NPC. Pure: nothing here asks the client anything.
local _, ns = ...

local Lookup = {}
ns.Lookup = Lookup

local Data = ns.Data

-- recipes by spell and by recipe item, of the professions built so far
local bySpell, byRecipeItem = {}, {}
Data.onBuilt = function(_, recipes)
    for index, recipe in ipairs(recipes) do
        recipe.index = index
        bySpell[recipe.spell] = recipe
        if recipe.recipe then
            byRecipeItem[recipe.recipe.id] = recipe
        end
    end
end

-- the keys of every profession, in the table's order
function Lookup.Professions()
    return Data.order
end

-- { key, name, line, short, icon, count } of a profession, or nil
function Lookup.Profession(key)
    return Data.professions[key]
end

function Lookup.ProfessionName(key)
    local meta = Data.professions[key]
    return meta and meta.name or tostring(key)
end

-- the recipes of one profession (built on the first ask)
function Lookup.Recipes(key)
    return Data.Recipes(key)
end

-- every profession built, so that BySpell / ByRecipeItem answer for all of them
function Lookup.BuildAll()
    for _, key in ipairs(Data.order) do
        Data.Recipes(key)
    end
end

-- a recipe of a profession built so far
function Lookup.BySpell(spell)
    return bySpell[spell]
end

function Lookup.ByRecipeItem(itemID)
    return byRecipeItem[itemID]
end

-- what a recipe is made of: a list of { id, count, name, icon } - the name "item <id>" when the table has none
function Lookup.Reagents(recipe)
    local list = {}
    for _, reagent in ipairs(recipe.reagents or {}) do
        local item = Data.items[reagent[1]]
        list[#list + 1] = { id = reagent[1], count = reagent[2], name = item and item.name or ("item " .. reagent[1]), icon = item and item.icon }
    end
    return list
end

-- the name of an item the tables know (a reagent, a camp object), or nil
function Lookup.ItemName(itemID)
    local item = itemID and Data.items[itemID]
    return item and item.name or nil
end

-- how a profession's skill cap is raised: { ranks = { ... }, specs = { ... } | nil } (Data\Training.lua), or nil
function Lookup.Training(key)
    return Data.training and Data.training[key] or nil
end

-- the entries of a list (trainers, vendors, quests) a character of `side` can use
function Lookup.ForSide(list, side)
    local result = {}
    for _, entry in ipairs(list or {}) do
        if entry.side == nil or side == nil or entry.side == side then
            result[#result + 1] = entry
        end
    end
    return result
end

-- "A" | "H" from what UnitFactionGroup says; nil for anything else
function Lookup.Side(faction)
    if faction == "Alliance" then
        return "A"
    elseif faction == "Horde" then
        return "H"
    end
    return nil
end

-- may a character of `side` use a source marked `entrySide`? An unknown side on either end: yes.
local function usable(entrySide, side)
    return entrySide == nil or side == nil or entrySide == side
end

local function filtered(list, side)
    local result = {}
    for _, entry in ipairs(list or {}) do
        if usable(entry.side, side) then
            result[#result + 1] = entry
        end
    end
    return result
end

-- the vendors a merchant window showed selling this recipe's item (db.vendors), as vendor entries; the
-- ones the table already names are left out
local function seenVendors(recipe, side, listed)
    local result = {}
    local seen = recipe.recipe and ns.db and ns.db.vendors and ns.db.vendors[recipe.recipe.id]
    if type(seen) ~= "table" then
        return result
    end
    local names = {}
    for _, vendor in ipairs(listed) do
        names[vendor.npc] = true
    end
    for npc, info in pairs(seen) do
        if type(info) == "table" and not names[npc] and usable(info.side, side) then
            result[#result + 1] = { npc = npc, zone = info.zone, price = info.price, side = info.side, seen = true }
        end
    end
    table.sort(result, function(a, b)
        return a.npc < b.npc
    end)
    return result
end

-- Where a recipe comes from for a character of `side` ("A" | "H" | nil = either):
--   { trainer, unsure, byQuest, taught, vendors, quests, drops, world, trainersSell, capitals, made, favor,
--     classic, any, unknown, otherSide }
-- any       = there is a way to get it for this side
-- unknown   = nobody has written down where it comes from yet
-- otherSide = every known source belongs to the other faction
function Lookup.Sources(recipe, side)
    local vendors = filtered(recipe.vendors, side)
    for _, vendor in ipairs(seenVendors(recipe, side, vendors)) do
        vendors[#vendors + 1] = vendor
    end
    local sources = {
        trainer = recipe.trainer or false,
        unsure = recipe.unsure or false,
        byQuest = recipe.byQuest or false,
        taught = recipe.taught,
        vendors = vendors,
        quests = filtered(recipe.quests, side),
        drops = recipe.drops or {},
        world = recipe.world,
        trainersSell = recipe.trainersSell,
        capitals = recipe.capitals or false,
        made = recipe.made,
        favor = recipe.favor,
        classic = recipe.classic or false,
        auto = recipe.auto or false,
        somewhere = recipe.somewhere,
        via = recipe.via,
    }
    sources.any = sources.trainer or sources.auto or sources.somewhere ~= nil or sources.byQuest or sources.taught ~= nil or #sources.vendors > 0 or #sources.quests > 0
        or #sources.drops > 0 or sources.world ~= nil or sources.trainersSell ~= nil or sources.capitals or sources.made ~= nil
    local listed = (recipe.vendors and #recipe.vendors > 0) or (recipe.quests and #recipe.quests > 0)
    sources.unknown = not sources.any and not listed
    sources.otherSide = not sources.any and listed and true or false
    if recipe.side and side and recipe.side ~= side then
        -- the other faction's own recipe (Data.lua: its text says so)
        sources.any, sources.unknown, sources.otherSide = false, false, true
    end
    return sources
end

-- the kinds of source a recipe has for this side, in the order the cards name them:
-- a list of "auto" | "trainer" | "taught" | "vendor" | "quest" | "drop" | "made"
function Lookup.Kinds(sources)
    local kinds = {}
    local somewhere = sources.somewhere or {}
    if sources.auto then kinds[#kinds + 1] = "auto" end
    if sources.trainer then kinds[#kinds + 1] = "trainer" end
    if sources.taught then kinds[#kinds + 1] = "taught" end
    if #sources.vendors > 0 or sources.trainersSell or sources.capitals or somewhere.vendor then kinds[#kinds + 1] = "vendor" end
    if #sources.quests > 0 or sources.byQuest or somewhere.quest then kinds[#kinds + 1] = "quest" end
    if #sources.drops > 0 or sources.world or somewhere.drop then kinds[#kinds + 1] = "drop" end
    if sources.made then kinds[#kinds + 1] = "made" end
    return kinds
end

-- how the recipe ITEM binds: "bop" (binds when picked up: only the character that gets it can learn it),
-- "boe" (it can be traded, mailed to an alt, auctioned) - nil when there is no item (a trainer teaches
-- it) or nobody knows
function Lookup.Bind(recipe)
    if not recipe.recipe or recipe.recipe.bind == "?" then
        return nil
    end
    return recipe.recipe.bop and "bop" or "boe"
end

-- a recipe in a few words, for chat: "trainer", "vendor: Stormwind City", "quest", ...
function Lookup.Summary(recipe, side)
    local sources = Lookup.Sources(recipe, side)
    local somewhere = sources.somewhere or {}
    if sources.auto then
        return "with the skill"
    elseif sources.trainer then
        return "trainer"
    elseif sources.taught then
        return sources.taught.zone or sources.taught.npc
    elseif #sources.vendors == 1 then
        return "vendor: " .. (sources.vendors[1].zone or sources.vendors[1].npc)
    elseif #sources.vendors > 1 then
        return #sources.vendors .. " vendors"
    elseif sources.trainersSell or sources.capitals then
        return "vendor"
    elseif #sources.quests > 0 then
        return "quest" .. (sources.quests[1].zone and (": " .. sources.quests[1].zone) or "")
    elseif sources.byQuest then
        return "quest"
    elseif #sources.drops == 1 then
        return "drop" .. (sources.drops[1].zone and (": " .. sources.drops[1].zone) or "")
    elseif #sources.drops > 1 or sources.world then
        return "drop"
    elseif sources.made then
        return "crafted"
    elseif somewhere.vendor then
        return "vendor"
    elseif somewhere.quest then
        return "quest"
    elseif somewhere.drop then
        return "drop"
    elseif sources.otherSide then
        return "other faction"
    end
    return "source unknown"
end

local function contains(haystack, needle)
    return type(haystack) == "string" and string.find(string.lower(haystack), needle, 1, true) ~= nil
end

-- does the recipe match the typed words: its name, what it is, or any NPC, zone or quest of its sources -
-- or the word of one of its tags ("bop", "boe", "vendor", "quest", "drop", "trainer", "made")
function Lookup.Matches(recipe, query, side)
    if type(query) ~= "string" then
        return true
    end
    local needle = string.lower((string.gsub((string.gsub(query, "^%s+", "")), "%s+$", "")))
    if needle == "" then
        return true
    end
    if contains(recipe.name, needle) or contains(recipe.desc, needle) then
        return true
    end
    if recipe.spec and needle == string.lower(recipe.spec) then
        return true -- "gnomish", "goblin"
    end
    -- what it is made of: "linen cloth" lists everything that uses it
    for _, reagent in ipairs(recipe.reagents or {}) do
        local item = Data.items[reagent[1]]
        if item and contains(item.name, needle) then
            return true
        end
    end
    local sources = Lookup.Sources(recipe, side)
    if needle == Lookup.Bind(recipe) then
        return true
    end
    for _, kind in ipairs(Lookup.Kinds(sources)) do
        if needle == kind then
            return true
        end
    end
    if sources.taught and (contains(sources.taught.npc, needle) or contains(sources.taught.zone, needle)) then
        return true
    end
    for _, vendor in ipairs(sources.vendors) do
        if contains(vendor.npc, needle) or contains(vendor.zone, needle) then
            return true
        end
    end
    for _, quest in ipairs(sources.quests) do
        if contains(quest.name, needle) or contains(quest.zone, needle) then
            return true
        end
    end
    for _, drop in ipairs(sources.drops) do
        if contains(drop.npc, needle) or contains(drop.zone, needle) then
            return true
        end
    end
    return false
end

-- an icon as text in a line: |T...|t with the border of the icon file cut away
function Lookup.IconText(icon, size)
    if not icon then
        return ""
    end
    size = size or 16
    return "|TInterface\\Icons\\" .. tostring(icon) .. ":" .. size .. ":" .. size .. ":0:0:64:64:4:60:4:60|t "
end

-- what the tables hold, without building any of them
function Lookup.Counts()
    local counts = { professions = #Data.order, recipes = 0, built = 0, perProfession = {}, training = 0 }
    for _ in pairs(Data.training or {}) do
        counts.training = counts.training + 1 -- 0: Data\Training.lua did not load (a file new to the TOC needs a client restart)
    end
    for _, key in ipairs(Data.order) do
        local meta = Data.professions[key]
        counts.recipes = counts.recipes + (meta.count or 0)
        counts.perProfession[key] = meta.count
        if Data.IsBuilt(key) then
            counts.built = counts.built + 1
        end
    end
    return counts
end
