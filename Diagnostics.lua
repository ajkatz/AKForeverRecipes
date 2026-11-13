-- Diagnostics: '/akr diag' writes a report into the saved file - what the client offers (the trade skill
-- and spellbook APIs), what the last pass found and by which of the two ways, what the client says of a
-- few sample recipes, every error. Nothing in it is a frame; every value is checked
-- before it is copied so that a secret cannot poison the file.
local _, ns = ...

local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function sanitize(value, depth)
    depth = depth or 0
    if ns.IsSecret(value) then
        return "<secret>"
    end
    local kind = type(value)
    if kind == "table" then
        if depth >= 7 then
            return "<too deep>"
        end
        if type(value.GetObjectType) == "function" then
            return "<frame>"
        end
        local copy = {}
        for k, v in pairs(value) do
            local key = k
            if ns.IsSecret(k) then
                key = "<secret key>"
            elseif type(k) ~= "string" and type(k) ~= "number" then
                key = tostring(k)
            end
            copy[key] = sanitize(v, depth + 1)
        end
        return copy
    elseif kind == "string" or kind == "number" or kind == "boolean" then
        return value
    elseif kind == "nil" then
        return nil
    end
    return "<" .. kind .. ">"
end
Diagnostics.Sanitize = sanitize

local function has(fn)
    return type(fn) == "function"
end

-- what the client says, raw, of the first, a middle and the last recipe of the table - and of one the
-- character is known to have, so that a "learned" answer can be seen as the client gives it
local function samples()
    local list = {}
    -- of the character's first profession - Cooking when none is known
    local prof = ns.Known:ProfessionsOf(ns.cdb)[1] or "cooking"
    local recipes = ns.Lookup.Recipes(prof)
    local picks = { recipes[1], recipes[math.floor(#recipes / 2)], recipes[#recipes] }
    for spell in pairs(ns.cdb and ns.cdb.learned or {}) do
        picks[#picks + 1] = ns.Lookup.BySpell(spell)
        break
    end
    for _, recipe in ipairs(picks) do
        local entry = { spell = recipe.spell, name = recipe.name, prof = recipe.prof }
        local getInfo = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo
        if has(getInfo) then
            local ok, info = pcall(getInfo, recipe.spell)
            if not ok then
                entry.recipeInfo = "error: " .. tostring(info)
            else
                entry.recipeInfo = sanitize(info)
                if entry.recipeInfo == nil then
                    entry.recipeInfo = "nil"
                end
            end
        end
        local known = ns.Readable(C_SpellBook and C_SpellBook.IsSpellKnown, recipe.spell)
        entry.isSpellKnown = known and tostring(known[1]) or "no answer"
        local player = ns.Readable(IsPlayerSpell, recipe.spell)
        entry.isPlayerSpell = player and tostring(player[1]) or "no answer"
        list[#list + 1] = entry
    end
    return list
end

function Diagnostics:Client()
    local faction = ns.Readable(UnitFactionGroup, "player")
    return {
        tradeSkill = {
            getRecipeInfo = has(C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo),
            getAllRecipeIDs = has(C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs),
            professionInfoBySkillLine = has(C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID),
            isTradeSkillReady = has(C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady),
        },
        spellBook = { isSpellKnown = has(C_SpellBook and C_SpellBook.IsSpellKnown), isPlayerSpell = has(IsPlayerSpell) },
        merchant = { itemID = has(GetMerchantItemID), itemInfo = has(GetMerchantItemInfo), cItemInfo = has(C_MerchantFrame and C_MerchantFrame.GetItemInfo) },
        faction = faction and faction[1] or "no answer",
        samples = samples(),
    }
end

function Diagnostics:Collect()
    local db = ns.db or {}
    local report = {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or "?",
        addonVersion = ns.version,
        character = ns.characterKey,
        savedStateSource = ns.savedStateSource,
        savedVariableLoads = db.loads,
        client = self:Client(),
        data = ns.Lookup.Counts(),
        dataReadOn = ns.Data.readOn,
        known = ns.Known:Describe(),
        window = ns.Window:Describe(),
        guild = ns.Guild and ns.Guild:Describe() or nil,
        friends = ns.Friends and ns.Friends:Describe() or nil,
        locks = ns.Locks and ns.Locks:Describe() or nil,
        vendorsSeen = db.vendors,
        errors = {},
        blockedActions = ns.blockedActions,
        unknownEvents = ns.unknownEvents,
        session = ns.sessionLog,
    }
    if GetBuildInfo then
        local version, build, buildDate, toc = GetBuildInfo()
        report.build = { version = version, build = build, date = buildDate, toc = toc }
    end
    for message, count in pairs(ns.errors) do
        report.errors[#report.errors + 1] = { message = message, count = count }
    end
    return sanitize(report)
end

-- A report asked for with '/akr diag' is kept; the one taken at logout goes beside it.
function Diagnostics:Save(asked)
    if not ns.db then
        return
    end
    local report = self:Collect()
    if asked then
        report.asked = true
        ns.db.diag = report
        Diagnostics.asked = true
    elseif Diagnostics.asked then
        ns.db.diagAtLogout = report
    else
        ns.db.diag = report
        ns.db.diagAtLogout = nil
    end
end

ns:RegisterCommand("diag", "save a report into the settings file (then /reload, so that it is written to disk)", function()
    Diagnostics:Save(true)
    ns:Print("report saved - /reload (or log out) writes it to disk.")
end)

ns:On("PLAYER_LOGOUT", function()
    Diagnostics:Save()
end)
