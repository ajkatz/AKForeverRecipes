-- Lookup: the questions the rest of the addon asks of the recipe table - a recipe by its spell or by the
-- recipe item that teaches it, where a recipe comes from for one faction, a search by name, place or NPC.
-- Pure: nothing here asks the client anything.
local _, ns = ...

local Lookup = {}
ns.Lookup = Lookup

local Data = ns.Data

local bySpell, byRecipeItem = {}, {}
for index, recipe in ipairs(Data.recipes) do
    recipe.index = index
    bySpell[recipe.spell] = recipe
    if recipe.recipe then
        byRecipeItem[recipe.recipe.id] = recipe
    end
end

function Lookup.Recipes()
    return Data.recipes
end

function Lookup.BySpell(spell)
    return bySpell[spell]
end

function Lookup.ByRecipeItem(itemID)
    return byRecipeItem[itemID]
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
--   { trainer, taught, vendors, quests, drops, favor, classic, any, unknown, otherSide }
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
        taught = recipe.taught,
        vendors = vendors,
        quests = filtered(recipe.quests, side),
        drops = recipe.drops or {},
        favor = recipe.favor,
        classic = recipe.classic or false,
    }
    sources.any = sources.trainer or sources.taught ~= nil or #sources.vendors > 0 or #sources.quests > 0 or #sources.drops > 0
    local listed = (recipe.vendors and #recipe.vendors > 0) or (recipe.quests and #recipe.quests > 0)
    sources.unknown = not sources.any and not listed
    sources.otherSide = not sources.any and listed and true or false
    return sources
end

-- a recipe in a few words, for the right-hand column: "trainer", "vendor: Stormwind City", "quest", ...
function Lookup.Summary(recipe, side)
    local sources = Lookup.Sources(recipe, side)
    if sources.trainer then
        return "trainer"
    elseif sources.taught then
        return sources.taught.zone or sources.taught.npc
    elseif #sources.vendors == 1 then
        return "vendor: " .. (sources.vendors[1].zone or sources.vendors[1].npc)
    elseif #sources.vendors > 1 then
        return #sources.vendors .. " vendors"
    elseif #sources.quests > 0 then
        return "quest" .. (sources.quests[1].zone and (": " .. sources.quests[1].zone) or "")
    elseif #sources.drops == 1 then
        return "drop" .. (sources.drops[1].zone and (": " .. sources.drops[1].zone) or "")
    elseif #sources.drops > 1 then
        return "drop"
    elseif sources.otherSide then
        return "other faction"
    end
    return "source unknown"
end

local function contains(haystack, needle)
    return type(haystack) == "string" and string.find(string.lower(haystack), needle, 1, true) ~= nil
end

-- does the recipe match the typed words: its name, what it gives, or any NPC, zone or quest of its sources
function Lookup.Matches(recipe, query, side)
    if type(query) ~= "string" then
        return true
    end
    local needle = string.lower((string.gsub((string.gsub(query, "^%s+", "")), "%s+$", "")))
    if needle == "" then
        return true
    end
    if contains(recipe.name, needle) or contains(recipe.effect, needle) then
        return true
    end
    local sources = Lookup.Sources(recipe, side)
    if sources.trainer and contains("trainer", needle) then
        return true
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

function Lookup.Counts()
    local counts = { recipes = #Data.recipes, new = 0, trainer = 0, withVendors = 0, withQuests = 0, withDrops = 0, unknown = 0 }
    for _, recipe in ipairs(Data.recipes) do
        if recipe.new then counts.new = counts.new + 1 end
        if recipe.trainer then counts.trainer = counts.trainer + 1 end
        if recipe.vendors then counts.withVendors = counts.withVendors + 1 end
        if recipe.quests then counts.withQuests = counts.withQuests + 1 end
        if recipe.drops then counts.withDrops = counts.withDrops + 1 end
        if not (recipe.trainer or recipe.taught or recipe.vendors or recipe.quests or recipe.drops) then
            counts.unknown = counts.unknown + 1
        end
    end
    return counts
end
