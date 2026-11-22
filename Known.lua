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
--  * The standing with the nine factions a recipe item can ask one of (see "Reputation" below).
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

-- A profession's skill and its cap are asked three ways, the first that names a skill above zero wins:
--   1. the professions book (GetProfessions, GetProfessionInfo) - answers at login, no window open;
--   2. the skill window's lines (C_SkillInfo), for what the book leaves out;
--   3. the trade skill call (GetProfessionInfoBySkillLineID) - the only one asked until 2026-11-16.
-- Why: on build 70938 the trade skill call answered 0/0 for all nine lines at login, so a cap kept from an
-- earlier read went stale - the user, 2026-11-16: "i completed dirge's quest and it still doesn't think i
-- have artisan unlocked" (the book said Cooking 225/300 in the same second the card kept 225).

-- the professions book: { [skill line id] = entry, [name] = entry }, entry = { skill, max }; nil when the
-- client does not answer or names no profession
local function readBook()
    local slots = ns.Readable(GetProfessions)
    if not slots or type(GetProfessionInfo) ~= "function" then
        return nil
    end
    local found = {}
    for i = 1, 6 do
        local slot = readableNumber(slots[i])
        if slot then
            local ok, name, _, rank, maxRank, _, _, line = pcall(GetProfessionInfo, slot)
            rank = ok and readableNumber(rank) or nil
            if rank then
                local entry = { skill = rank, max = readableNumber(maxRank) }
                if readableNumber(line) then found[line] = entry end
                if readable(name) then found[name] = entry end
            end
        end
    end
    return next(found) and found or nil -- a book that names nothing has not answered
end

-- the skill window's lines, the same shape; nil when the client has no such list
local function readSkillWindow()
    local api = type(C_SkillInfo) == "table" and C_SkillInfo or nil
    local count = api and ns.Readable(api.GetNumSkillLines)
    count = count and readableNumber(count[1])
    if not count or type(api.GetSkillLineInfo) ~= "function" then
        return nil
    end
    local found = {}
    for index = 1, count do
        local ok, info = pcall(api.GetSkillLineInfo, index)
        if ok and not ns.IsSecret(info) and type(info) == "table" and not ns.IsSecret(info.isHeader) and not info.isHeader then
            local rank = readableNumber(info.rank)
            if rank then
                local entry = { skill = rank, max = readableNumber(info.maxRank) }
                if readableNumber(info.skillID) then found[info.skillID] = entry end
                if readable(info.name) then found[info.name] = entry end
            end
        end
    end
    return next(found) and found or nil
end

-- the skill of every profession; gives back how many professions the client answered for
function Known:ReadSkills()
    local book, window = readBook(), readSkillWindow()
    local fn = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
    local answered = 0
    for _, key in ipairs(Lookup.Professions()) do
        local meta = Lookup.Profession(key)
        local raw = { line = meta.line }
        local api
        if type(fn) == "function" then
            local ok, info = pcall(fn, meta.line)
            if ok and not ns.IsSecret(info) and type(info) == "table" then
                api = { skill = readableNumber(info.skillLevel), max = readableNumber(info.maxSkillLevel) }
                raw.skill, raw.max, raw.name = api.skill or "?", api.max or "?", readable(info.professionName) or "?"
                raw.api = (api.skill or "?") .. "/" .. (api.max or "?")
            else
                raw.answered = false
            end
        end
        local ways = {
            { "professions book", book and (book[meta.line] or book[meta.name]) },
            { "skill window", window and (window[meta.line] or window[meta.name]) },
            { "trade skill API", api },
        }
        raw.how = "nothing above zero"
        for _, way in ipairs(ways) do
            local read = way[2]
            if read and read.skill and read.skill > 0 then
                local before = ns.cdb.skills[key]
                -- a way that names no cap leaves the cap read before
                ns.cdb.skills[key] = { skill = read.skill, max = read.max or (type(before) == "table" and before.max) or nil }
                ns.cdb.profs[key] = true
                raw.how, raw.skill, raw.max = way[1], read.skill, read.max or "?"
                break
            end
        end
        if book or window or (api and api.skill) then
            answered = answered + 1
        end
        Known.skillRaw[key] = raw
    end
    return answered
end

------------------------------------------------------------------------
-- Reputation
------------------------------------------------------------------------
-- The character's standing with the factions a recipe item can ask one of (asked "Also show each
-- character's own standing against the requirement?", the user, 2026-11-20: "Yes, add standing"). Asked
-- by faction id - C_Reputation.GetFactionDataByID, the call Forever's own reputation window is built on -
-- at login and a moment after the game says a standing moved, and kept on the character:
--   cdb.rep[faction id] = { s = the standing, v = reputation earned inside it, m = how much it holds,
--                           a = the reputation itself, as the client counts it (Neutral starts at 0) }
--                       | false: the client answered, and has nothing on this faction for the character
--   cdb.repAt           = when they were last read
-- s counts as the item table does (0 Hated .. 4 Friendly .. 7 Exalted); the client's `reaction` counts
-- from 1, so s = reaction - 1.
-- Nothing is written unless the client answered: no such call, secrets, an error, or an empty reputation
-- list with no faction answering leave what was read before as it was - and an unread character unread.
Known.repRaw, Known.repReads = {}, 0

function Known:ReadStandings()
    local api = type(C_Reputation) == "table" and C_Reputation or nil
    local byID = api and api.GetFactionDataByID
    if type(byID) ~= "function" then
        Known.repRaw = { answered = "no such call" }
        return false
    end
    local count = ns.Readable(api.GetNumFactions)
    count = count and readableNumber(count[1]) or nil
    local read, raw = {}, { factions = count or "?" }
    local answered = (count or 0) > 0 -- the list is there: a faction it says nothing of was never met
    for faction in pairs(Lookup.RepFactions()) do
        local ok, data = pcall(byID, faction)
        if not ok then
            raw[faction] = "error"
        elseif ns.IsSecret(data) then
            raw[faction] = "secret"
        elseif data == nil then
            raw[faction], read[faction] = "nil", false
        elseif type(data) ~= "table" then
            raw[faction] = type(data)
        else
            local reaction = readableNumber(data.reaction)
            if reaction and reaction >= 1 and reaction <= 8 then
                local entry = { s = reaction - 1 }
                local floor, ceiling = readableNumber(data.currentReactionThreshold), readableNumber(data.nextReactionThreshold)
                local value = readableNumber(data.currentStanding)
                if floor and ceiling and value and ceiling > floor and value >= floor then
                    entry.v, entry.m, entry.a = value - floor, ceiling - floor, value
                end
                read[faction], answered = entry, true
                raw[faction] = reaction .. (entry.m and (" " .. entry.v .. "/" .. entry.m) or "")
            else
                raw[faction] = "unreadable"
            end
        end
    end
    Known.repRaw = raw
    Known.repReads = Known.repReads + 1
    if not answered then
        return false
    end
    local kept = type(ns.cdb.rep) == "table" and ns.cdb.rep or {}
    local changed = false
    for faction, entry in pairs(read) do
        local before = kept[faction]
        if entry == false then
            changed = changed or before ~= false
        else
            changed = changed or type(before) ~= "table" or before.s ~= entry.s or before.v ~= entry.v or before.m ~= entry.m
                or before.a ~= entry.a
        end
        kept[faction] = entry
    end
    ns.cdb.rep, ns.cdb.repAt = kept, now()
    if changed then
        ns:Fire("STANDING_CHANGED") -- the window's alone: a standing is no news for the guild or friends
    end
    return changed
end

-- one read, two seconds after the first UPDATE_FACTION of a burst (every kill for a faction says it)
function Known:QueueStandings()
    if Known.repPending then
        return
    end
    if C_Timer and type(C_Timer.After) == "function" then
        Known.repPending = true
        C_Timer.After(2, function()
            Known.repPending = nil
            ns.SafeCall(Known.ReadStandings, Known)
        end)
    else
        self:ReadStandings()
    end
end

-- A character against the standing a recipe item asks for (need = Lookup.Rep's):
--   true / false, and the standing kept ({ s, v, m }, or false: never met the faction)
--   nil: nothing is known - the character's standings were never read, or the recipe asks for none
function Known:Meets(profile, need)
    local rep = type(profile) == "table" and type(profile.rep) == "table" and profile.rep or nil
    if not rep or type(need) ~= "table" then
        return nil
    end
    local entry = rep[need.faction]
    if entry == false then
        return false, false
    end
    if type(entry) ~= "table" or type(entry.s) ~= "number" then
        return nil
    end
    return entry.s >= need.standing, entry
end

-- How much reputation is still to earn to reach a standing (the user, 2026-11-20: "instead of showing
-- like neutral/honored can we just show exactly how many reputation points you need to earn to get to
-- that goal?"), or nil when it cannot be said: never met, already there, or the client gave no numbers.
--  * Into the very next standing: the client's own numbers (what the standing holds, less what is earned).
--  * Further: over the standings between, on the scale every ordinary faction has - where each standing
--    starts, below. All nine factions a recipe asks for are ordinary ones in the client's faction table
--    (no friendship or renown scale, build 70959). It is only summed when the client's own numbers for
--    the standing the character is in sit on that scale; otherwise nothing is said.
local STANDING_STARTS = { [0] = -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }

function Known.PointsTo(entry, standing)
    if type(entry) ~= "table" or type(entry.s) ~= "number" or type(standing) ~= "number" or entry.s >= standing then
        return nil
    end
    local earned, holds = entry.v, entry.m
    if type(earned) ~= "number" or type(holds) ~= "number" then
        return nil
    end
    if entry.s + 1 == standing then
        return holds - earned
    end
    local starts, nextStarts, goal = STANDING_STARTS[entry.s], STANDING_STARTS[entry.s + 1], STANDING_STARTS[standing]
    if starts and nextStarts and goal and type(entry.a) == "number"
        and entry.a - earned == starts and holds == nextStarts - starts then
        return goal - entry.a
    end
    return nil
end

-- 16800 as "16,800"
function Known.Grouped(number)
    local digits = tostring(math.floor(number))
    local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
    return (string.gsub(grouped, "^,", ""))
end

-- "8,800 to go" for a standing short of what is asked - or where it is, in the client's own numbers
-- ("Friendly 1200/8000"), when the distance cannot be said; nil: never met
function Known.ToGoText(entry, standing)
    local points = Known.PointsTo(entry, standing)
    if points then
        return Known.Grouped(points) .. " to go", points
    end
    return Known.StandingText(entry)
end

-- "Honored 3200/12000" - or the word alone at Exalted and when the client gave no numbers; nil: never met
function Known.StandingText(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local word = Lookup.StandingWord(entry.s) or "?"
    if entry.s < 7 and entry.v and entry.m then
        return word .. " " .. entry.v .. "/" .. entry.m
    end
    return word
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

-- A trainer's window: the price it asks for each recipe it teaches (the user, 2026-11-13: "for recipes can we
-- try to include trainer cost"). The tables carry Wowhead's prices; the trainer's own wins, for every
-- character of the account. A service is a recipe by its name, among the trainer-taught recipes of the
-- professions built so far (a class trainer's spells match none).
local byTrainerName -- [recipe name] = recipe, of the trainer-taught recipes
Known.trainerReads, Known.trainerPrices = 0, 0

function Known:ReadTrainer()
    local count = ns.Readable(GetNumTrainerServices)
    count = count and readableNumber(count[1]) or 0
    if count == 0 or type(GetTrainerServiceInfo) ~= "function" or type(GetTrainerServiceCost) ~= "function" then
        return
    end
    Lookup.BuildAll()
    if not byTrainerName then
        byTrainerName = {}
        for _, key in ipairs(ns.Data.order) do
            for _, recipe in ipairs(Lookup.Recipes(key) or {}) do
                if recipe.trainer then
                    byTrainerName[recipe.name] = recipe
                end
            end
        end
    end
    local changed = false
    for index = 1, count do
        local info = ns.Readable(GetTrainerServiceInfo, index)
        local name = info and ns.ReadableString(info[1])
        local recipe = name and byTrainerName[name]
        if recipe then
            local cost = ns.Readable(GetTrainerServiceCost, index)
            cost = cost and readableNumber(cost[1])
            if cost then
                local entry = ns.db.trainerCosts[recipe.spell]
                if not entry or entry.cost ~= cost then
                    changed = true
                    Known.trainerPrices = Known.trainerPrices + 1
                end
                ns.db.trainerCosts[recipe.spell] = { cost = cost, at = now() }
            end
        end
    end
    Known.trainerReads = Known.trainerReads + 1
    if changed then
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
        chars[key] = { learned = Known:Count(profile), skills = profile.skills, professions = Known:ProfessionsOf(profile), side = profile.side, scannedAt = profile.scannedAt,
            rep = profile.rep, repAt = profile.repAt }
    end
    return {
        -- what the client last said of each faction a recipe asks a standing of: "6 3200/12000" (its
        -- reaction, 1 Hated .. 8 Exalted, and how far into it), "nil", "secret", "unreadable", "error"
        rep = { raw = Known.repRaw, reads = Known.repReads },
        lastScan = Known.lastScan, scans = Known.scans or 0, skillRaw = Known.skillRaw, merchantReads = Known.merchantReads,
        heardLearned = Known.heardLearned, chars = chars,
        trainerReads = Known.trainerReads, trainerPrices = Known.trainerPrices,
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
    ns.SafeCall(Known.ReadStandings, Known)
    -- a cold login: the client may not have the trade skill data yet; once more, a little later
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(5, function()
            ns.SafeCall(Known.Scan, Known, "auto")
            ns.SafeCall(Known.ReadStandings, Known)
        end)
    end
end)

ns:On("UPDATE_FACTION", function()
    Known:QueueStandings()
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

for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do
    ns:On(event, function()
        ns.SafeCall(Known.ReadTrainer, Known)
    end)
end
