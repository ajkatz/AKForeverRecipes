-- Known: what each character has learned. It only reads, and what it reads is kept per character in the
-- account-wide saved table, so that any character's recipes can be looked at from any other.
--
--  * Which professions the character has: the ones whose skill line the client gives a skill above zero
--    for - and any a recipe was ever seen learned in.
--  * A recipe is learned when the client says so - asked spell by spell, two ways: the trade skill API's
--    recipe info (its `learned` field) and the spellbook's "is this spell known". Either saying yes is
--    enough; neither answering changes nothing. A recipe once seen learned stays learned: an unanswered
--    question must not empty the book.
--  * NEW_RECIPE_LEARNED names the recipe just learned: written down at once.
--  * A merchant's window: recipe items of ours on sale are written down with the merchant and the price -
--    that is how the recipes nobody has a source for yet get one.
--
-- Only the character's own professions are asked about (a hundred to a few hundred calls each), at login,
-- when a trade skill window opens or its list changes - gathered into one pass half a second later - and
-- when the window's Refresh is pressed. When the client says nothing about any skill line, the login pass
-- and Refresh ask about every profession instead, so that the addon is never blind.
local _, ns = ...

local Known = {}
ns.Known = Known

local Lookup = ns.Lookup
local readable, readableNumber = ns.ReadableString, ns.ReadableNumber

Known.lastScan = nil    -- what the last pass found, for /akr diag
Known.skillRaw = {}     -- [profession key] = what the client said of its skill line
Known.merchantReads = 0
Known.heardLearned = 0

local function now()
    return type(time) == "function" and time() or 0
end

------------------------------------------------------------------------
-- Asking the client about one recipe
------------------------------------------------------------------------
-- true / false as the trade skill API says, nil when it does not answer
local function askRecipeInfo(spell)
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo
    if type(fn) ~= "function" then
        return nil
    end
    local ok, info = pcall(fn, spell)
    if not ok or ns.IsSecret(info) or type(info) ~= "table" then
        return nil
    end
    local learned = info.learned
    if ns.IsSecret(learned) or type(learned) ~= "boolean" then
        return nil
    end
    return learned
end

-- true / false as the spellbook says, nil when it does not answer
local function askSpellKnown(spell)
    local answered, known = false, false
    local asked = {
        C_SpellBook and C_SpellBook.IsSpellKnown,
        IsPlayerSpell,
    }
    for index = 1, 2 do
        local result = ns.Readable(asked[index], spell)
        if result and type(result[1]) == "boolean" then
            answered = true
            known = known or result[1]
        end
    end
    if not answered then
        return nil
    end
    return known
end

------------------------------------------------------------------------
-- The character
------------------------------------------------------------------------
function Known:ReadSide()
    local result = ns.Readable(UnitFactionGroup, "player")
    local side = result and Lookup.Side(result[1])
    if side then
        ns.cdb.side = side
    end
    return ns.cdb.side
end

-- the skill of every profession; gives back how many skill lines the client answered for
function Known:ReadSkills()
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
    if type(fn) ~= "function" then
        return 0
    end
    local answered = 0
    for _, key in ipairs(Lookup.Professions()) do
        local meta = Lookup.Profession(key)
        local ok, info = pcall(fn, meta.line)
        if ok and not ns.IsSecret(info) and type(info) == "table" then
            local skill, max = readableNumber(info.skillLevel), readableNumber(info.maxSkillLevel)
            Known.skillRaw[key] = { line = meta.line, skill = skill or "?", max = max or "?", name = readable(info.professionName) or "?" }
            if skill then
                answered = answered + 1
                if skill > 0 then
                    ns.cdb.skills[key] = { skill = skill, max = max }
                    ns.cdb.profs[key] = true
                end
            end
        else
            Known.skillRaw[key] = { line = meta.line, answered = false }
        end
    end
    return answered
end

------------------------------------------------------------------------
-- The passes
------------------------------------------------------------------------
local function markLearned(recipe, how)
    local learned = ns.cdb.learned
    if learned[recipe.spell] then
        return false
    end
    learned[recipe.spell] = now()
    ns.cdb.profs[recipe.prof] = true
    ns:Log("learned", { spell = recipe.spell, prof = recipe.prof, how = how })
    return true
end

-- One pass over the character's professions. everything = true: over every profession (Refresh; or the
-- client said nothing about the skill lines, so nobody knows which professions there are).
function Known:Scan(everything)
    Known.pending = nil
    local scan = { at = now(), recipes = 0, infoAnswered = 0, infoLearned = 0, spellAnswered = 0, spellLearned = 0, new = 0, professions = {} }
    self:ReadSide()
    scan.skillLines = self:ReadSkills()
    if everything == "auto" then
        -- blind (no skill line answered) and nothing known of this character yet: ask about everything
        everything = scan.skillLines == 0 and next(ns.cdb.profs) == nil
    end
    scan.everything = everything and true or false
    for _, key in ipairs(Lookup.Professions()) do
        if everything or ns.cdb.profs[key] then
            scan.professions[#scan.professions + 1] = key
            for _, recipe in ipairs(Lookup.Recipes(key)) do
                scan.recipes = scan.recipes + 1
                local byInfo, bySpell = askRecipeInfo(recipe.spell), askSpellKnown(recipe.spell)
                if byInfo ~= nil then
                    scan.infoAnswered = scan.infoAnswered + 1
                    if byInfo then scan.infoLearned = scan.infoLearned + 1 end
                end
                if bySpell ~= nil then
                    scan.spellAnswered = scan.spellAnswered + 1
                    if bySpell then scan.spellLearned = scan.spellLearned + 1 end
                end
                if (byInfo or bySpell) and markLearned(recipe, byInfo and "info" or "spell") then
                    scan.new = scan.new + 1
                end
            end
        end
    end
    ns.cdb.scannedAt = scan.at
    scan.total = Known:Count(ns.cdb)
    Known.lastScan = scan
    Known.scans = (Known.scans or 0) + 1
    ns:Fire("KNOWN_CHANGED")
    return scan
end

-- one pass, half a second after the first of a burst of events asked for it
function Known:Queue()
    if Known.pending then
        return
    end
    if C_Timer and type(C_Timer.After) == "function" then
        Known.pending = true
        C_Timer.After(0.5, function()
            ns.SafeCall(Known.Scan, Known)
        end)
    else
        self:Scan()
    end
end

-- the recipe tables of every profession any character of the account has: a merchant's wares and a
-- recipe just learned are looked up in these
function Known:BuildAccount()
    for _, profile in pairs(ns.db and ns.db.chars or {}) do
        for key in pairs(type(profile) == "table" and type(profile.profs) == "table" and profile.profs or {}) do
            Lookup.Recipes(key)
        end
    end
end

------------------------------------------------------------------------
-- A merchant's window
------------------------------------------------------------------------
local function merchantPrice(index)
    local getInfo = C_MerchantFrame and C_MerchantFrame.GetItemInfo
    if type(getInfo) == "function" then
        local ok, info = pcall(getInfo, index)
        if ok and not ns.IsSecret(info) and type(info) == "table" then
            return readableNumber(info.price)
        end
    end
    if type(GetMerchantItemInfo) ~= "function" then
        return nil
    end
    local ok, _, _, price = pcall(GetMerchantItemInfo, index)
    if ok then
        return readableNumber(price)
    end
    return nil
end

function Known:ReadMerchant()
    local count = ns.Readable(GetMerchantNumItems)
    count = count and readableNumber(count[1]) or 0
    if count == 0 or type(GetMerchantItemID) ~= "function" then
        return
    end
    local npc, zone, found
    for index = 1, count do
        local id = ns.Readable(GetMerchantItemID, index)
        id = id and readableNumber(id[1])
        local recipe = id and Lookup.ByRecipeItem(id)
        if recipe then
            if not npc then
                npc = UnitName and readable((UnitName("npc")))
                zone = (GetRealZoneText and readable(GetRealZoneText())) or (GetZoneText and readable(GetZoneText()))
            end
            if npc then
                local vendors = ns.db.vendors
                vendors[id] = vendors[id] or {}
                local price = merchantPrice(index)
                local entry = vendors[id][npc]
                if not entry then
                    found = true
                end
                vendors[id][npc] = { zone = zone, price = (price and price > 0) and price or (entry and entry.price) or nil, side = ns.cdb.side, at = now() }
            end
        end
    end
    Known.merchantReads = Known.merchantReads + 1
    if found then
        ns:Log("merchant", { npc = npc, zone = zone })
        ns:Fire("KNOWN_CHANGED")
    end
end

------------------------------------------------------------------------
-- Answers
------------------------------------------------------------------------
-- the profile of a character by its key; no key: the one logged in
function Known:Profile(key)
    if key and ns.db and type(ns.db.chars[key]) == "table" then
        return ns.db.chars[key]
    end
    return ns.cdb
end

function Known:IsLearned(spell, key)
    local profile = self:Profile(key)
    return type(profile.learned) == "table" and profile.learned[spell] ~= nil
end

function Known:Count(profile)
    local count = 0
    for _ in pairs(type(profile.learned) == "table" and profile.learned or {}) do
        count = count + 1
    end
    return count
end

-- the professions of a character, in the table's order
function Known:ProfessionsOf(profile)
    local list = {}
    local profs = type(profile) == "table" and type(profile.profs) == "table" and profile.profs or {}
    for _, key in ipairs(Lookup.Professions()) do
        if profs[key] then
            list[#list + 1] = key
        end
    end
    return list
end

function Known:Has(profile, prof)
    return type(profile) == "table" and type(profile.profs) == "table" and profile.profs[prof] == true
end

-- { skill, max } of a character's profession, or nil
function Known:Skill(profile, prof)
    local skills = type(profile) == "table" and profile.skills
    local entry = type(skills) == "table" and skills[prof]
    if type(entry) == "table" and type(entry.skill) == "number" then
        return entry.skill, entry.max
    end
    return nil
end

-- how many of an item the character logged in has, bank included - nil when the client does not say
function Known:ItemCount(itemID)
    local result = ns.Readable(C_Item and C_Item.GetItemCount, itemID, true)
    return result and readableNumber(result[1]) or nil
end

-- "Purr Gola" from "Purr Gola - Realm"
function Known.ShortName(key)
    return (string.match(key or "", "^(.-) %- ")) or key or "?"
end

-- the characters whose recipes can be shown: the one logged in first, then every other with a profession
function Known:Characters()
    local list = {}
    if ns.characterKey then
        list[1] = ns.characterKey
    end
    local others = {}
    for key, profile in pairs(ns.db and ns.db.chars or {}) do
        if key ~= ns.characterKey and #self:ProfessionsOf(profile) > 0 then
            others[#others + 1] = key
        end
    end
    table.sort(others)
    for _, key in ipairs(others) do
        list[#list + 1] = key
    end
    return list
end

-- the other characters with this recipe's profession: who has the recipe, who does not
function Known:Others(recipe, exceptKey)
    local has, lacks = {}, {}
    for _, key in ipairs(self:Characters()) do
        if key ~= exceptKey and self:Has(self:Profile(key), recipe.prof) then
            local list = self:IsLearned(recipe.spell, key) and has or lacks
            list[#list + 1] = Known.ShortName(key)
        end
    end
    return has, lacks
end

function Known:Describe()
    local chars = {}
    for key, profile in pairs(ns.db and ns.db.chars or {}) do
        chars[key] = { learned = Known:Count(profile), skills = profile.skills, professions = Known:ProfessionsOf(profile), side = profile.side, scannedAt = profile.scannedAt }
    end
    return {
        lastScan = Known.lastScan, scans = Known.scans or 0, skillRaw = Known.skillRaw, merchantReads = Known.merchantReads,
        heardLearned = Known.heardLearned, chars = chars,
    }
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local function readLevel(level)
    if level == nil and type(UnitLevel) == "function" then
        level = UnitLevel("player")
    end
    level = ns.ReadableNumber(level)
    if level and level > 0 and ns.cdb then
        ns.cdb.level = level
    end
end

ns:On("PLAYER_LEVEL_UP", function(_, level)
    readLevel(level)
end)

ns:Listen("LOGIN", function()
    readLevel()
    Known:BuildAccount()
    Known:Scan("auto")
    -- a cold login: the client may not have the trade skill data yet; once more, a little later
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(5, function()
            ns.SafeCall(Known.Scan, Known, "auto")
        end)
    end
end)

for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED" }) do
    ns:On(event, function()
        Known:Queue()
    end)
end

ns:On("NEW_RECIPE_LEARNED", function(_, recipeID)
    Known.heardLearned = Known.heardLearned + 1
    local spell = readableNumber(recipeID)
    local recipe = spell and Lookup.BySpell(spell)
    if spell and not recipe then
        Lookup.BuildAll() -- the first recipe of a profession nobody on the account had
        recipe = Lookup.BySpell(spell)
    end
    if recipe and markLearned(recipe, "event") then
        ns:Fire("KNOWN_CHANGED")
    end
    Known:Queue() -- the skill moved too, and a recipe of another name may have come with it
end)

for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
    ns:On(event, function()
        Known:ReadMerchant()
    end)
end
