-- Data: the professions and their recipes. The recipe tables themselves are the generated files under
-- Data\ (tools/gen_data.py); each registers itself here with a function that builds its entries, and that
-- function runs the first time the profession is asked for - so a character without Tailoring never
-- builds Tailoring's four hundred entries.
--
-- A recipe:
--   spell   the recipe's spell id (what the client is asked about)      item    the made item's id
--   name, icon     kind  what the made thing is ("Plate feet, level 40")     level  the level it needs
--   stats   what it gives, one entry per bonus or effect ({ "+13 Stamina", "+9 Defense Rating" })
--   desc    kind and stats in one line, for a closed card and the search (set here)
--   learn / yellow / green / grey   the skill it is learned at and where its colour turns
--   recipe  the recipe ITEM that teaches it ({ id, name, bop }) - none: it is taught, not read;
--           bop: the item binds when picked up (Wowhead's Forever tooltips), else it can be traded
--   trainer any trainer of the profession teaches it (unsure: a guess - Forever added it and no recipe
--           item exists)                      byQuest  a quest teaches it (which one is not written down)
--   taught  { npc, zone }: one NPC teaches it
--   vendors { npc, zone, side = "A" | "H" | nil, price (copper), limited }
--   quests  { name, level, zone, side }     drops { npc, zone, chance (%), min, max (level), object (a chest) }
--   world   { lo, hi }: a world drop from creatures of these levels
--   trainersSell  that many trainers of the profession sell the recipe item     capitals  sold in the capitals
--   made    { names }: another craft makes the recipe item      favor   its price in Merchant's Favor
--   auto    it comes by itself with the profession's skill (the client's own skill table says so)
--   somewhere { vendor, quest, drop = true }: a source of that kind exists, which one is not written down
--   via     where a source the profession pages lack was found: "Questie", "Wowhead"
--   classic the source is Classic's, unconfirmed for Forever    new     a recipe Forever added
--   reagents { { item id, count }, ... }: what it is made of; the items' names are in Data.items
--   station the item id of the camp object it has to be made at     makes  how many one craft gives
--   spec    the specialization it needs ("Gnomish" | "Goblin" Engineering)
--   prof    the key of its profession (set here)
--
-- Data.training (Data\Training.lua, generated): how each profession's skill cap is raised and its
-- specializations - described at the top of that file.
local _, ns = ...

local Data = { professions = {}, order = {}, items = {} } -- items: [item id] = { name, icon } of reagents
ns.Data = Data
Data.source = "foreverchanges.pro/professions"

local loaders, built = {}, {}

-- a generated file announces its profession: meta = { key, name, line (skill line id), short, icon, count, readOn }
function Data.Register(meta, loader)
    Data.professions[meta.key] = meta
    Data.order[#Data.order + 1] = meta.key
    loaders[meta.key] = loader
    Data.readOn = meta.readOn
end

function Data.IsBuilt(key)
    return built[key] ~= nil
end

-- the recipes of a profession, in skill order; built on the first ask. An unknown key: an empty list.
function Data.Recipes(key)
    local recipes = built[key]
    if recipes then
        return recipes
    end
    recipes = {}
    local loader = loaders[key]
    if loader then
        loader(function(recipe)
            recipe.prof = key
            local stats = recipe.stats and table.concat(recipe.stats, ", ") or nil
            if recipe.kind and stats then
                recipe.desc = recipe.kind .. " - " .. stats
            else
                recipe.desc = recipe.kind or stats
            end
            recipes[#recipes + 1] = recipe
        end, function(itemID, name, icon)
            Data.items[itemID] = { name = name, icon = icon }
        end)
        loaders[key] = nil
    end
    built[key] = recipes
    if Data.onBuilt then
        Data.onBuilt(key, recipes)
    end
    return recipes
end
