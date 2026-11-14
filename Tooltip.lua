-- Tooltip: on a recipe item's tooltip - a drop in the loot window or a roll, your bags, a merchant, a chat
-- link - which of your characters can use it (the user, 2026-11-13: "see if when a recipe drops if one of
-- your current characters can use it"; his choices: the recipe item's tooltip, only the characters that
-- have the profession). One line each, from what the addon already keeps per character:
--   "Purrdee: can learn it (Tailoring 120)"     the profession, skill at least what the recipe needs
--   "Bubson: Tailoring 20, needs 25"            the profession, the skill not there yet
--   "Gorm: knows it"                            learned already
-- Characters on another realm, and a faction's own recipe for a character of the other faction, are left
-- out. Nobody with the profession: no lines at all. The recipe item has to be in the tables (Lookup).
local _, ns = ...

local Tip = {}
ns.Tip = Tip
Tip.stats = { shown = 0, lines = 0 }

local Lookup, Known = ns.Lookup, ns.Known

local COLORS = {
    learn = { 0.25, 1.0, 0.25 },
    low = { 1.0, 0.5, 0.25 },
    known = { 0.6, 0.6, 0.6 },
    head = { 1.0, 0.82, 0 },
}
local ORDER = { learn = 1, low = 2, known = 3 }

local function realmOf(key)
    return type(key) == "string" and string.match(key, " %- (.+)$") or nil
end

local function shortName(key)
    return string.match(key, "^(.-) %- ") or key -- the whole name, "First Last": alts can share a first name
end

-- { { name, status = "learn" | "low" | "known", skill, me }, ... } for one recipe, best first
function Tip.Who(recipe)
    local out = {}
    local chars = ns.db and ns.db.chars
    local realm = realmOf(ns.characterKey)
    if type(chars) ~= "table" or not realm or type(recipe) ~= "table" then
        return out
    end
    for key, profile in pairs(chars) do
        if type(profile) == "table" and realmOf(key) == realm and Known:Has(profile, recipe.prof)
            and not (recipe.side and profile.side and recipe.side ~= profile.side) then
            local skill = Known:Skill(profile, recipe.prof)
            local status
            if type(profile.learned) == "table" and profile.learned[recipe.spell] ~= nil then
                status = "known"
            elseif skill and skill >= (recipe.learn or 0) then
                status = "learn"
            else
                status = "low"
            end
            out[#out + 1] = { name = shortName(key), status = status, skill = skill, me = key == ns.characterKey }
        end
    end
    table.sort(out, function(a, b)
        if a.status ~= b.status then
            return ORDER[a.status] < ORDER[b.status]
        end
        if a.me ~= b.me then
            return a.me
        end
        return a.name < b.name
    end)
    return out
end

-- the lines: { { text, r, g, b }, ... }
function Tip.Lines(itemID)
    local recipe = Lookup.ByRecipeItem(itemID)
    if not recipe then
        return {}
    end
    local who = Tip.Who(recipe)
    if #who == 0 then
        return {}
    end
    local prof = Lookup.ProfessionName(recipe.prof)
    local spec = recipe.spec and (" - " .. recipe.spec .. " " .. prof .. " only") or ""
    local lines = { { "Your characters" .. spec .. ":", COLORS.head[1], COLORS.head[2], COLORS.head[3] } }
    for _, w in ipairs(who) do
        local text
        if w.status == "known" then
            text = w.name .. ": knows it"
        elseif w.status == "learn" then
            text = string.format("%s: can learn it (%s %d)", w.name, prof, w.skill)
        elseif w.skill then
            text = string.format("%s: %s %d, needs %d", w.name, prof, w.skill, recipe.learn or 0)
        else
            text = string.format("%s: needs %s %d", w.name, prof, recipe.learn or 0)
        end
        local c = COLORS[w.status]
        lines[#lines + 1] = { "  " .. text, c[1], c[2], c[3] }
    end
    return lines
end

function Tip.Add(tooltip, data)
    if not ns:GetOption("tooltip") then
        return
    end
    if tooltip ~= _G.GameTooltip and tooltip ~= _G.ItemRefTooltip then
        return
    end
    local id = type(data) == "table" and data.id or nil
    if type(id) ~= "number" or (ns.IsSecret and ns.IsSecret(id)) then
        return
    end
    local lines = Tip.Lines(id)
    if #lines == 0 then
        return
    end
    for _, line in ipairs(lines) do
        tooltip:AddLine(line[1], line[2], line[3], line[4])
    end
    Tip.stats.shown = Tip.stats.shown + 1
    Tip.stats.lines = Tip.stats.lines + #lines
end

ns:Listen("LOGIN", function()
    local kinds = Enum and Enum.TooltipDataType
    if type(TooltipDataProcessor) == "table" and type(TooltipDataProcessor.AddTooltipPostCall) == "function" and kinds and kinds.Item ~= nil then
        TooltipDataProcessor.AddTooltipPostCall(kinds.Item, function(tooltip, data)
            ns.SafeCall(Tip.Add, tooltip, data)
        end)
        Tip.hooked = true
    end
end)

ns:RegisterCommand("tooltip", "'/akr tooltip on | off': on a recipe item's tooltip, which of your characters can use it (on by default)", function(rest)
    local word = string.lower(rest or "")
    if word == "on" or word == "off" then
        ns:SetOption("tooltip", word == "on")
    end
    ns:Print("recipe tooltips are " .. (ns:GetOption("tooltip") and "on" or "off") .. ". '/akr tooltip on' or '/akr tooltip off'.")
end)
