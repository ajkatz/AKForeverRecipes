-- Scenario tests for AKForeverRecipes: lua tests/run.lua  (from the addon's folder)
package.path = "tests/?.lua;" .. package.path
local Mock = require("wowmock")

local passed, failures = 0, {}

local function check(condition, message)
    if not condition then
        error(message or "check failed", 2)
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message and (message .. ": ") or "") .. "expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function scenario(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok and #Mock.errors > 0 then
        ok, err = false, "the addon raised an error: " .. tostring(Mock.errors[1])
    end
    if ok then
        passed = passed + 1
        Mock.realPrint("  ok    " .. name)
    else
        failures[#failures + 1] = name
        Mock.realPrint("  FAIL  " .. name .. "\n          " .. tostring(err):gsub("\n", "\n          "))
    end
end

-- a fresh client; prepare(state) sets the world up before the character logs in. The mock's character is
-- a cook (Cooking 1/75) unless the scenario says otherwise.
local function start(options, prepare)
    local ns, state = Mock.install(options)
    if prepare then
        prepare(state)
    end
    Mock.login()
    return ns, state
end

local function printed(text)
    for _, line in ipairs(Mock.printed) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

local function has(list, text)
    for _, line in ipairs(list) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

-- the entry of the card of that name in the window, and its index among the cards
local function cardNamed(ns, name)
    for index, entry in ipairs(ns.Window.lines) do
        if entry.card and Mock.plain(entry.text):find(name, 1, true) == 1 then
            return entry, index
        end
    end
    error("no card " .. name)
end

local WESTFALL_STEW, CHARRED_WOLF, CRISPY_BAT_WING, FLANK_AU_POIVRE, FLANK_RECIPE = 2543, 2538, 15935, 1250146, 250177 -- the flank: a recipe nobody has a source for (the steak had none until 2026-11-16)
local BRIGHT_YELLOW_SHIRT = 3869 -- Tailoring: the Alliance's vendor alone, and the pattern binds when picked up
local SHARPENING_STONE, COPPER_CHAIN_VEST = 2660, 3321 -- Blacksmithing
local BLACKSMITHING, TAILORING, ALCHEMY, ENGINEERING, LEATHERWORKING = 164, 197, 171, 202, 165
local KEYS = { "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring", "cooking", "firstaid", "mining" }

------------------------------------------------------------------------
Mock.realPrint("AKForeverRecipes scenarios")

scenario("every profession's table holds each recipe once, in skill order, with a name and usable sources", function()
    local ns = start()
    local Lookup = ns.Lookup
    equal(table.concat(Lookup.Professions(), " "), table.concat(KEYS, " "))
    local spells, items, total = {}, {}, 0
    for _, key in ipairs(KEYS) do
        local meta = Lookup.Profession(key)
        check(meta and meta.name and meta.line and meta.short and meta.icon, key .. ": the profession's own words")
        local recipes = Lookup.Recipes(key)
        equal(#recipes, meta.count, key .. ": as many recipes as its header says")
        check(#recipes >= 15, key .. " lost its recipes")
        total = total + #recipes
        local lastSkill = 0
        for _, recipe in ipairs(recipes) do
            local where = key .. " / " .. tostring(recipe.name)
            equal(recipe.prof, key, where)
            check(type(recipe.spell) == "number" and not spells[recipe.spell], where .. ": spell twice or missing")
            spells[recipe.spell] = true
            check(type(recipe.name) == "string" and recipe.name ~= "", where .. ": no name")
            check(recipe.learn >= lastSkill, where .. " is out of skill order")
            lastSkill = recipe.learn
            -- (the source has a few recipes whose yellow lies under the skill they are learned at)
            check(recipe.yellow <= recipe.green and recipe.green <= recipe.grey, where .. ": skill colours out of order")
            for _, vendor in ipairs(recipe.vendors or {}) do
                check(vendor.npc and vendor.npc ~= "", where .. ": a vendor without a name")
                check(vendor.side == nil or vendor.side == "A" or vendor.side == "H", where .. ": a vendor of no faction")
            end
            for _, quest in ipairs(recipe.quests or {}) do
                check(quest.name and quest.name ~= "", where .. ": a quest without a name")
            end
            for _, drop in ipairs(recipe.drops or {}) do
                check(drop.npc and drop.npc ~= "", where .. ": a drop without a creature")
            end
            if recipe.recipe then
                check(not items[recipe.recipe.id] or items[recipe.recipe.id] == recipe.spell, where .. ": a recipe item shared with another spell")
                items[recipe.recipe.id] = recipe.spell
            end
            check(not (recipe.trainer and recipe.recipe), where .. ": taught by a trainer AND read from an item")
        end
    end
    check(total > 2000, "the tables hold " .. total .. " recipes")
    equal(Lookup.Counts().recipes, total)
    equal(Lookup.BySpell(WESTFALL_STEW).name, "Westfall Stew"); equal(Lookup.BySpell(WESTFALL_STEW).prof, "cooking")
    equal(Lookup.ByRecipeItem(728).name, "Westfall Stew")
    equal(Lookup.BySpell(SHARPENING_STONE).prof, "blacksmithing")
    equal(#Lookup.Recipes("fishing"), 0, "a profession without recipes is an empty list, not an error")
end)

scenario("only the professions somebody on the account has are built and asked about", function()
    local ns, state = start() -- a cook
    check(ns.Data.IsBuilt("cooking"))
    for _, key in ipairs(KEYS) do
        check(key == "cooking" or not ns.Data.IsBuilt(key), key .. " was built for a character without it")
    end
    equal(ns.Known.lastScan.recipes, 123); equal(table.concat(ns.Known.lastScan.professions, " "), "cooking")
    equal(ns.Known.lastScan.skillLines, 9)
    equal(state.calls.info, 123)
    Mock.advance(10) -- the login's second pass: still Cooking alone
    for _, key in ipairs(KEYS) do
        check(key == "cooking" or not ns.Data.IsBuilt(key), key .. " was built a little later")
    end
    -- Refresh asks about every profession: the way out when a profession was not noticed
    ns.Window:Show()
    ns.Window.widgets.refresh:Click()
    check(ns.Known.lastScan.everything and ns.Known.lastScan.recipes > 2000)
    -- a smith and tailor
    ns = start(nil, function(s)
        s.skill = { level = 0, max = 0 }
        s.skills[BLACKSMITHING] = { level = 60, max = 75 }
        s.skills[TAILORING] = { level = 10, max = 75 }
    end)
    equal(table.concat(ns.Known:ProfessionsOf(ns.cdb), " "), "blacksmithing tailoring")
    check(ns.Data.IsBuilt("blacksmithing") and ns.Data.IsBuilt("tailoring") and not ns.Data.IsBuilt("cooking"))
    equal(ns.Known.lastScan.recipes, #ns.Lookup.Recipes("blacksmithing") + #ns.Lookup.Recipes("tailoring"))
    -- the next session, an alt with no profession: the smith's tables are built for merchants, none is asked about
    ns = start({ db = AKForeverRecipesDB, first = "No", last = "Craft" }, function(s)
        s.skill = { level = 0, max = 0 }
    end)
    check(ns.Data.IsBuilt("blacksmithing") and not ns.Data.IsBuilt("alchemy"))
    equal(ns.Known.lastScan.recipes, 0)
end)

scenario("a recipe is known when the trade skill API says it is learned", function()
    local ns = start(nil, function(state)
        state.learned[WESTFALL_STEW] = true
        state.spellMode = "false"
        state.skill = { level = 150, max = 225 }
    end)
    check(ns.Known:IsLearned(WESTFALL_STEW))
    check(not ns.Known:IsLearned(CHARRED_WOLF))
    equal(ns.Known.lastScan.infoAnswered, 123); equal(ns.Known.lastScan.infoLearned, 1); equal(ns.Known.lastScan.total, 1)
    local skill, max = ns.Known:Skill(ns.cdb, "cooking")
    equal(skill, 150); equal(max, 225); equal(ns.cdb.side, "A")
    equal(ns.Known:Skill(ns.cdb, "alchemy"), nil)
end)

scenario("when the trade skill API gives nothing, the spellbook's answer is taken", function()
    local ns = start(nil, function(state)
        state.learned[WESTFALL_STEW] = true
        state.infoMode = "nil"
    end)
    check(ns.Known:IsLearned(WESTFALL_STEW))
    equal(ns.Known.lastScan.infoAnswered, 0); equal(ns.Known.lastScan.spellLearned, 1)
    -- and a client without that function at all
    ns = start({ noRecipeInfo = true }, function(state)
        state.learned[CHARRED_WOLF] = true
    end)
    check(ns.Known:IsLearned(CHARRED_WOLF))
end)

scenario("a client that says nothing about skills is asked about every profession once, then about the ones found", function()
    local ns, state = start({ noSkillInfo = true }, function(s)
        s.learned[SHARPENING_STONE] = true
        s.learned[WESTFALL_STEW] = true
    end)
    check(ns.Known.lastScan.everything and ns.Known.lastScan.recipes > 2000, "blind: the first pass covers everything")
    check(ns.Known:IsLearned(SHARPENING_STONE) and ns.Known:IsLearned(WESTFALL_STEW))
    equal(table.concat(ns.Known:ProfessionsOf(ns.cdb), " "), "blacksmithing cooking", "a learned recipe gives its profession away")
    local before = state.calls.info
    Mock.advance(10) -- the second pass of the login: the two professions found, not everything again
    equal(state.calls.info - before, #ns.Lookup.Recipes("blacksmithing") + 123)
    equal(ns.Known:Skill(ns.cdb, "cooking"), nil)
    ns.Window:Show()
    check(Mock.info():find("of %d+ Blacksmithing recipes known"), Mock.info())
end)

scenario("secret answers and a failing API teach nothing and raise nothing", function()
    for _, mode in ipairs({ "secret", "secretField", "error" }) do
        local ns = start(nil, function(state)
            state.learned[WESTFALL_STEW] = true
            state.infoMode = mode
            state.spellMode = "secret"
            state.skill = { secret = true }
            state.faction = "secret"
        end)
        check(not ns.Known:IsLearned(WESTFALL_STEW), mode .. ": a secret was read as learned")
        equal(ns.Known:Skill(ns.cdb, "cooking"), nil); equal(ns.cdb.side, nil)
        equal(#ns.Known:ProfessionsOf(ns.cdb), 0)
        ns.Window:Show()
        -- every profession is offered, under its short name, dimmed: the character has none of them
        for _, key in ipairs(KEYS) do
            check(ns.Window.widgets.tabs[key]:IsShown(), mode .. ": no tab for " .. key)
        end
        equal(ns.Window.widgets.tabs.leatherworking:GetText(), "|cff808080LW|r")
        check(#Mock.rows() > 100, mode .. ": with no faction known the whole profession is listed")
        Mock.slash("diag")
        equal(#Mock.errors, 0, mode)
    end
end)

scenario("a recipe once read as learned stays learned when the client stops answering", function()
    local ns, state = start(nil, function(s)
        s.learned[WESTFALL_STEW] = true
    end)
    check(ns.Known:IsLearned(WESTFALL_STEW))
    state.infoMode, state.spellMode = "nil", "false"
    ns.Known:Scan()
    check(ns.Known:IsLearned(WESTFALL_STEW), "an unanswered pass emptied the list")
    -- and across sessions, with the skill lines silent too
    ns = start({ db = AKForeverRecipesDB }, function(s)
        s.infoMode, s.spellMode = "nil", "false"
        s.skill = { secret = true }
    end)
    check(ns.Known:IsLearned(WESTFALL_STEW), "the saved list was not read back")
    check(ns.Known:Has(ns.cdb, "cooking"), "the profession was forgotten")
end)

scenario("learning a recipe is heard at once and the open window follows", function()
    local ns = start(nil, function(state)
        state.skill = { level = 100, max = 150 }
    end)
    ns.Window:Show()
    check(Mock.rowIndex("Westfall Stew"), "Westfall Stew should be listed as missing")
    Mock.learn(WESTFALL_STEW)
    check(ns.Known:IsLearned(WESTFALL_STEW))
    check(not Mock.rowIndex("Westfall Stew"), "a learned recipe stayed in the missing list")
    equal(ns.Known.heardLearned, 1)
    -- a spell that is no recipe of ours
    Mock.fire("NEW_RECIPE_LEARNED", 999999)
    equal(ns.Known:Count(ns.cdb), 1)
    -- a secret recipe id is not looked at
    Mock.fire("NEW_RECIPE_LEARNED", Mock.SECRET)
    equal(ns.Known:Count(ns.cdb), 1)
    -- the first recipe of a profession the character did not have: its tab is the character's own now
    equal(ns.Window.widgets.tabs.blacksmithing:GetText(), "|cff808080BS|r")
    Mock.learn(SHARPENING_STONE)
    check(ns.Known:IsLearned(SHARPENING_STONE) and ns.Known:Has(ns.cdb, "blacksmithing"))
    equal(ns.Window.widgets.tabs.blacksmithing:GetText(), "BS", "the new profession's tab is still dimmed")
end)

scenario("a burst of trade skill events is one pass, half a second later", function()
    local ns, state = start()
    Mock.advance(10) -- the second pass of a cold login
    local before = state.calls.info
    for _ = 1, 20 do
        Mock.fire("TRADE_SKILL_LIST_UPDATE")
    end
    Mock.fire("TRADE_SKILL_SHOW")
    equal(state.calls.info, before, "the events themselves must not ask")
    state.learned[CHARRED_WOLF] = true
    Mock.advance(1)
    equal(state.calls.info, before + 123, "one pass, not one per event")
    check(ns.Known:IsLearned(CHARRED_WOLF))
end)

scenario("the tabs are the character's professions; a tab switches the list and is remembered", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 100, max = 150 }
        state.skills[BLACKSMITHING] = { level = 60, max = 75 }
        state.learned[SHARPENING_STONE] = true
    end)
    Mock.slash("show all")
    local tabs = ns.Window.widgets.tabs
    -- every profession has a tab: the character's own first and plain, the others after them and dimmed
    for _, key in ipairs(KEYS) do
        check(tabs[key]:IsShown(), "no tab for " .. key)
    end
    equal(tabs.blacksmithing:GetText(), "BS"); equal(tabs.cooking:GetText(), "Cook")
    equal(tabs.alchemy:GetText(), "|cff808080Alch|r"); equal(tabs.tailoring:GetText(), "|cff808080Tailor|r")
    local function left(tab) local _, _, _, x = tab:GetPoint(1); return x end
    equal(select(1, tabs.blacksmithing:GetPoint(1)), "TOPLEFT", "the first own profession leads the row")
    equal(select(2, tabs.cooking:GetPoint(1)), tabs.blacksmithing, "the second own profession follows it")
    equal(select(2, tabs.alchemy:GetPoint(1)), tabs.cooking, "the professions the character lacks come after its own")
    -- the first profession opens first
    check(Mock.info():find("Purr Gola: 1 of %d+ Blacksmithing recipes known") and Mock.info():find("Blacksmithing 60/75", 1, true), Mock.info())
    check(not tabs.blacksmithing:IsEnabled() and tabs.cooking:IsEnabled(), "the tab you are on is pressed in")
    check(Mock.rowIndex("Rough Sharpening Stone") and not Mock.rowIndex("Westfall Stew"))
    local stone = cardNamed(ns, "Rough Sharpening Stone")
    equal(stone.skillLabel, "Blacksmithing"); equal(stone.state, "known")
    local _, index = cardNamed(ns, "Rough Sharpening Stone")
    equal(Mock.plain(Mock.cards()[index].frame.skillLabel:GetText()), "Blacksmithing")

    tabs.cooking:Click()
    check(Mock.info():find("Cooking 100/150", 1, true), Mock.info())
    check(Mock.rowIndex("Westfall Stew") and not Mock.rowIndex("Rough Sharpening Stone"))
    equal(ns.cdb.options.prof, "cooking")
    -- the next session opens on Cooking
    ns = start({ db = AKForeverRecipesDB, faction = "Alliance" }, function(state)
        state.skills[BLACKSMITHING] = { level = 60, max = 75 }
    end)
    ns.Window:Show()
    check(Mock.info():find("Cooking recipes known", 1, true), Mock.info())
end)

scenario("Artisan Cooking is Dirge's quest: the training card lists what to bring him - 12 Giant Egg, 10 Zesty Clam Meat, 20 Alterac Swiss - and how many of each you have", function()
    local EGG, CLAM, SWISS = 12207, 7974, 8932
    local ns, state = start({ first = "Purr", last = "Gola", faction = "Alliance" }, function(s)
        s.skill = { level = 225, max = 225 } -- an Expert cook at the cap
        s.items[EGG], s.items[CLAM] = 3, 10
    end)
    -- the tables: the quest names its items (Wowhead's Forever page of quest 6610, read 2026-11-16)
    local bring = ns.Lookup.QuestItems(ns.Lookup.Training("cooking").ranks[4].quests[1])
    equal(#bring, 3)
    equal(bring[1].id, EGG); equal(bring[1].name, "Giant Egg"); equal(bring[1].count, 12); equal(bring[1].icon, "inv_egg_03")
    equal(bring[2].id, CLAM); equal(bring[2].name, "Zesty Clam Meat"); equal(bring[2].count, 10)
    equal(bring[3].id, SWISS); equal(bring[3].name, "Alterac Swiss"); equal(bring[3].count, 20); equal(bring[3].icon, "inv_misc_food_37")
    equal(#ns.Lookup.QuestItems(ns.Lookup.Training("firstaid").ranks[4].quests[1]), 0, "Triage asks for no items")
    equal(#ns.Lookup.QuestItems(nil), 0, "no quest: nothing")
    equal(#ns.Lookup.QuestItems({ name = "A quest", bring = 5 }), 0, "a list that is no list: nothing")
    -- the card, closed: the quest, and that there is something to bring
    Mock.slash("show all")
    ns.Window.widgets.tabs.cooking:Click()
    local card = ns.Window.lines[1]
    equal(Mock.plain(card.text), "Artisan Cooking  raises your skill cap to 300")
    equal(Mock.plain(card.right), "Quest: Clamlette Surprise - Dirge Quikcleave, Tanaris  (open for what to bring)")
    -- opened: the items under the quest's line, as a recipe lists its reagents
    card.click()
    local rows = Mock.rows()
    local at
    for i, row in ipairs(rows) do
        if row:find("Quest: Clamlette Surprise - Dirge Quikcleave, Tanaris | level 35", 1, true) then at = i end
    end
    check(at, table.concat(rows, "\n", 1, 10))
    equal(rows[at + 1], "Bring to Dirge Quikcleave | not all yet")
    equal(rows[at + 2], "Giant Egg | have 3/12")
    equal(rows[at + 3], "Zesty Clam Meat | have 10/10")
    equal(rows[at + 4], "Alterac Swiss | have 0/20")
    local raw = Mock.rawRows()
    check(raw[at + 2]:find("|cffff8080have 3/12", 1, true) and raw[at + 3]:find("|cff60ff60have 10/10", 1, true), raw[at + 2] .. "\n" .. raw[at + 3])
    check(raw[at + 2]:find("Interface\\Icons\\inv_egg_03", 1, true), "the item's icon leads its line: " .. raw[at + 2])
    -- everything gathered
    state.items[EGG], state.items[SWISS] = 12, 25
    ns.Window:Render()
    rows = Mock.rows()
    equal(rows[at + 1], "Bring to Dirge Quikcleave | you have it all")
    equal(rows[at + 4], "Alterac Swiss | have 25/20")
    -- the client silent about the bags: the list without counts
    state.bagsSecret = true
    ns.Window:Render()
    rows = Mock.rows()
    equal(rows[at + 1], "Bring to Dirge Quikcleave")
    equal(rows[at + 2], "12 x Giant Egg"); equal(rows[at + 4], "20 x Alterac Swiss")
    state.bagsSecret = nil
    -- seen from another character: that character's bags are not the cook's
    local alt = start({ db = AKForeverRecipesDB, first = "Alt", last = "Two", faction = "Alliance" }, function(s)
        s.skill = { level = 40, max = 75 }
        s.items[EGG] = 50
    end)
    Mock.slash("show all")
    alt.Window.widgets.character:Click() -- on to Purr Gola
    alt.Window.lines[1].click()
    rows = Mock.rows()
    check(has(rows, "Artisan  skill cap 300"), table.concat(rows, "\n", 1, 8))
    check(has(rows, "12 x Giant Egg") and has(rows, "10 x Zesty Clam Meat") and not has(rows, "| have "), table.concat(rows, "\n", 1, 10))
    -- a rank a trainer teaches says nothing of bringing
    alt.Window.widgets.tabs.alchemy:Click()
    check(not Mock.plain(alt.Window.lines[1].right):find("bring", 1, true), Mock.plain(alt.Window.lines[1].right))
end)

scenario("the skill cap comes from the professions book: Dirge's quest done, the trade skill call silent outside its window - the card says Artisan is learned", function()
    -- (the user, 2026-11-16: "i completed dirge's quest and it still doesn't think i have artisan unlocked".
    -- Build 70938: GetProfessionInfoBySkillLineID answered 0/0 for all nine lines at login, while
    -- GetProfessionInfo said Cooking 225/300 in the same second.)
    local ns = start({ first = "Purr", last = "Gola", faction = "Horde" }, function(s)
        s.skill = { level = 225, max = 225 } -- read while the Cooking window was open, before the quest
    end)
    equal(select(2, ns.Known:Skill(ns.cdb, "cooking")), 225)
    equal(ns.Known.skillRaw.cooking.how, "trade skill API")
    -- the next login: the trade skill call says 0/0, the book has the cap the quest gave
    local state
    ns, state = start({ db = AKForeverRecipesDB, first = "Purr", last = "Gola", faction = "Horde" }, function(s)
        s.skill = { level = 0, max = 0 }
        s.book = { [1] = { name = "Leatherworking", level = 180, max = 225 }, -- no skill line id: known by its name
                   [2] = { name = "Verzauberkunst", level = 261, max = 300, line = 333 }, -- another language: by its skill line
                   [5] = { name = "Cooking", level = 225, max = 300, line = 185 } } -- holes, as the client leaves them
    end)
    local skill, max = ns.Known:Skill(ns.cdb, "cooking")
    equal(skill, 225); equal(max, 300)
    equal(ns.Known.skillRaw.cooking.how, "professions book"); equal(ns.Known.skillRaw.cooking.api, "0/0")
    skill, max = ns.Known:Skill(ns.cdb, "leatherworking")
    equal(skill, 180); equal(max, 225); check(ns.Known:Has(ns.cdb, "leatherworking"), "a profession only the book names is the character's")
    equal(select(2, ns.Known:Skill(ns.cdb, "enchanting")), 300)
    check(not ns.Known.lastScan.everything, "the book answered: not blind")
    Mock.slash("show all")
    ns.Window.widgets.tabs.cooking:Click()
    local card = ns.Window.lines[1]
    equal(Mock.plain(card.text), "Cooking training")
    equal(Mock.plain(card.desc), "Your cap is 300 (Artisan): there is no further rank.")
    equal(card.state, "known"); equal(card.skill, 300)
    card.click()
    check(has(Mock.rows(), "Learned: Apprentice, Journeyman, Expert, Artisan"), table.concat(Mock.rows(), "\n", 1, 6))
    check(not has(Mock.rows(), "Clamlette Surprise"), "a rank that is learned lists no quest")
    -- both answer: the book's numbers are the ones kept
    state.skill = { level = 225, max = 225 }
    state.book[5].level = 226
    Mock.fire("SKILL_LINES_CHANGED"); Mock.advance(1)
    skill, max = ns.Known:Skill(ns.cdb, "cooking")
    equal(skill, 226); equal(max, 300); equal(ns.Known.skillRaw.cooking.api, "225/225")
    -- a profession the book leaves out is read from the skill window, by its skill line or its name
    state.skillWindow = { { name = "Mining", rank = 50, max = 75, header = true }, { name = "First Aid", rank = 150, max = 225 },
        { name = "Something", rank = 40, max = 75, line = ALCHEMY }, { name = "Cooking", rank = 1, max = 75, line = 185 } }
    Mock.fire("SKILL_LINES_CHANGED"); Mock.advance(1)
    skill, max = ns.Known:Skill(ns.cdb, "firstaid")
    equal(skill, 150); equal(max, 225); equal(ns.Known.skillRaw.firstaid.how, "skill window")
    equal(select(2, ns.Known:Skill(ns.cdb, "alchemy")), 75)
    equal(ns.Known:Skill(ns.cdb, "mining"), nil, "a header is no skill")
    equal(select(2, ns.Known:Skill(ns.cdb, "cooking")), 300, "the book comes before the skill window")
    -- the book silent again (secrets): what was read stays, nothing breaks
    state.book = { secret = true }
    state.skillWindow = nil
    state.skill = { level = 0, max = 0 }
    Mock.fire("SKILL_LINES_CHANGED"); Mock.advance(1)
    equal(select(2, ns.Known:Skill(ns.cdb, "cooking")), 300)
    equal(ns.Known.skillRaw.cooking.how, "nothing above zero")
    -- a secret rank in the book: that line is not taken
    state.book = { [5] = { name = "Cooking", level = 300, max = 300, line = 185 } }
    state.bookSecretRanks = true
    Mock.fire("SKILL_LINES_CHANGED"); Mock.advance(1)
    equal((ns.Known:Skill(ns.cdb, "cooking")), 226)
    -- the book names a rank without a cap: the cap read before stays
    state.bookSecretRanks = nil
    state.book[5].max = nil
    Mock.fire("SKILL_LINES_CHANGED"); Mock.advance(1)
    skill, max = ns.Known:Skill(ns.cdb, "cooking")
    equal(skill, 300); equal(max, 300)
    -- the report shows how each was read, with no secret in it
    Mock.slash("diag")
    equal(AKForeverRecipesDB.diag.known.skillRaw.cooking.how, "professions book")
    equal(#Mock.errors, 0)
    -- a client with neither the book nor the skill window: the trade skill call alone, as before
    GetProfessions, GetProfessionInfo, C_SkillInfo = nil, nil, nil
    state.skill = { level = 230, max = 300 }
    Mock.fire("SKILL_LINES_CHANGED"); Mock.advance(1)
    equal((ns.Known:Skill(ns.cdb, "cooking")), 230); equal(ns.Known.skillRaw.cooking.how, "trade skill API")
    equal(#Mock.errors, 0)
    -- a client with the book but no trade skill call is not blind: only the book's professions are asked about
    ns = start({ noSkillInfo = true, first = "Other", last = "Cook", faction = "Horde" }, function(s)
        s.book = { [5] = { name = "Cooking", level = 80, max = 150, line = 185 } }
    end)
    check(not ns.Known.lastScan.everything and ns.Known.lastScan.skillLines > 0, "the book answered: not blind")
    equal(select(2, ns.Known:Skill(ns.cdb, "cooking")), 150)
end)

scenario("a specialization's quest lists what to bring too: Gnomish and Goblin Engineering, the three of Leatherworking, the two of Blacksmithing - with how many you have", function()
    local TUBE, SCOPE, DUMMY, VEST, HELMET = 10559, 4407, 4392, 8211, 8214
    local ns, state = start({ first = "Purr", last = "Gola", faction = "Alliance" }, function(s)
        s.skills[ENGINEERING] = { level = 300, max = 300 }
        s.items[TUBE], s.items[DUMMY] = 6, 2
    end)
    -- the tables (Questie's words; Wowhead's Forever pages of the quests have the same, read 2026-11-16)
    local function wants(prof, spec, quest)
        local list = {}
        for _, item in ipairs(ns.Lookup.QuestItems(ns.Lookup.Training(prof).specs[spec].quests[quest])) do
            list[#list + 1] = item.count .. " " .. item.name
        end
        return table.concat(list, ", ")
    end
    -- "6 Mithril Tubes, an Accurate Scope, and 2 Advanced Target Dummies": one by "an", a plural in -ies
    equal(wants("engineering", 1, 1), "6 Mithril Tube, 1 Accurate Scope, 2 Advanced Target Dummy")
    equal(wants("engineering", 1, 2), wants("engineering", 1, 1), "the Horde's Gnomish quest asks for the same")
    equal(wants("engineering", 2, 1), "20 Big Iron Bomb, 20 Solid Dynamite, 5 Explosive Sheep")
    equal(wants("leatherworking", 1, 1), "2 Tough Scorpid Breastplate, 2 Tough Scorpid Gloves, 10 Worn Dragonscale")
    equal(wants("leatherworking", 2, 1), "2 Heart of Fire, 2 Globe of Water, 2 Core of Earth, 2 Breath of Wind")
    equal(wants("leatherworking", 3, 2), "1 Wild Leather Vest, 1 Wild Leather Helmet")
    equal(wants("blacksmithing", 1, 1), "4 Ornate Mithril Helm, 2 Ornate Mithril Boots, 1 Ornate Mithril Breastplate")
    equal(wants("blacksmithing", 2, 2), "4 Moonsteel Broadsword, 4 Massive Iron Axe, 2 Heavy Mithril Axe, 2 Big Black Mace")
    -- every one of them has its items, each with an icon
    for _, prof in ipairs({ "blacksmithing", "engineering", "leatherworking" }) do
        for _, spec in ipairs(ns.Lookup.Training(prof).specs) do
            for _, quest in ipairs(spec.quests) do
                local items = ns.Lookup.QuestItems(quest)
                check(#items >= 2, spec.name .. ": " .. quest.name .. " lists nothing to bring")
                for _, item in ipairs(items) do
                    check(type(item.icon) == "string" and item.icon ~= "", spec.name .. ": " .. item.name .. " has no icon")
                end
            end
        end
    end
    -- the card of an Artisan engineer, closed: there is something to bring
    Mock.slash("show all")
    ns.Window.widgets.tabs.engineering:Click()
    local card = ns.Window.lines[1]
    equal(Mock.plain(card.right), "2 specializations - open for where and what to bring")
    -- opened: each specialization's quest, the items under it; the Horde's quest giver is not shown
    card.click()
    local rows = Mock.rows()
    local function under(quest)
        for i, row in ipairs(rows) do
            if row == quest then return i end
        end
        check(false, "no row \"" .. quest .. "\":\n" .. table.concat(rows, "\n"))
        return 0
    end
    local at = under("Quest: Show Your Work - Tinkmaster Overspark, Ironforge")
    equal(rows[at + 1], "Bring to Tinkmaster Overspark | not all yet")
    equal(rows[at + 2], "Mithril Tube | have 6/6")
    equal(rows[at + 3], "Accurate Scope | have 0/1")
    equal(rows[at + 4], "Advanced Target Dummy | have 2/2")
    check(Mock.rawRows()[at + 4]:find("Interface\\Icons\\inv_crate_05", 1, true), "a made thing's icon comes from its recipe: " .. Mock.rawRows()[at + 4])
    check(not has(rows, "Oglethorpe"), "the Horde's Gnomish quest is shown to the Alliance")
    at = under("Quest: Show Your Work - Nixx Sprocketspring, Tanaris")
    equal(rows[at + 1], "Bring to Nixx Sprocketspring | not all yet")
    equal(rows[at + 2], "Big Iron Bomb | have 0/20"); equal(rows[at + 4], "Explosive Sheep | have 0/5")
    -- the scope made: Gnomish is ready, Goblin is not
    state.items[SCOPE] = 1
    ns.Window:Render()
    rows = Mock.rows()
    equal(rows[under("Quest: Show Your Work - Tinkmaster Overspark, Ironforge") + 1], "Bring to Tinkmaster Overspark | you have it all")
    equal(rows[under("Quest: Show Your Work - Nixx Sprocketspring, Tanaris") + 1], "Bring to Nixx Sprocketspring | not all yet")

    -- a Horde leatherworker: its own quest givers, one of a thing counted as one
    local horde, hordeState = start({ first = "Tusk", last = "Hide", faction = "Horde" }, function(s)
        s.skills[LEATHERWORKING] = { level = 300, max = 300 }
        s.items[VEST] = 1
    end)
    Mock.slash("show all")
    horde.Window.widgets.tabs.leatherworking:Click()
    equal(Mock.plain(horde.Window.lines[1].right), "3 specializations - open for where and what to bring")
    horde.Window.lines[1].click()
    rows = Mock.rows()
    at = under("Quest: Tribal Leatherworking - Se'Jib, Stranglethorn Vale")
    equal(rows[at + 1], "Bring to Se'Jib | not all yet")
    equal(rows[at + 2], "Wild Leather Vest | have 1/1"); equal(rows[at + 3], "Wild Leather Helmet | have 0/1")
    check(not has(rows, "Caryssia Moonhunter"), "the Alliance's Tribal quest is shown to the Horde")
    at = under("Quest: Dragonscale Leatherworking - Thorkaf Dragoneye, Badlands")
    equal(rows[at + 4], "Worn Dragonscale | have 0/10")
    at = under("Quest: Elemental Leatherworking - Brumn Winterhoof, Arathi Highlands")
    equal(rows[at + 1], "Bring to Brumn Winterhoof | not all yet"); equal(rows[at + 5], "Breath of Wind | have 0/2")
    -- the client silent about the bags: the numbers wanted, no counts
    hordeState.bagsSecret = true
    horde.Window:Render()
    rows = Mock.rows()
    at = under("Quest: Tribal Leatherworking - Se'Jib, Stranglethorn Vale")
    equal(rows[at + 1], "Bring to Se'Jib"); equal(rows[at + 2], "1 x Wild Leather Vest")
end)

scenario("the first card of a profession is its training: where the next rank is learned, for your faction", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 130, max = 150 }                  -- a Journeyman cook
        state.skills[ALCHEMY] = { level = 210, max = 225 }        -- an Expert alchemist
        state.skills[BLACKSMITHING] = { level = 300, max = 300 }  -- an Artisan smith
    end)
    Mock.slash("show all")
    local tabs = ns.Window.widgets.tabs
    tabs.cooking:Click()
    local card = ns.Window.lines[1]
    check(card.training, "the training card is not first")
    equal(Mock.plain(card.text), "Expert Cooking  raises your skill cap to 225")
    equal(Mock.plain(card.desc), "Your cap is 150 (Journeyman).  It can be learned at Cooking 125 and level 20.")
    equal(Mock.plain(card.right), "Book: Expert Cookbook - Shandrina, Ashenvale")
    equal(card.state, "now", "skill 130 is enough for a rank that asks for 125"); equal(card.skill, 150); equal(card.skillLabel, "skill cap")
    local frame = Mock.cards()[1].frame
    equal(Mock.plain(frame.skill:GetText()), "150"); equal(Mock.plain(frame.skillLabel:GetText()), "skill cap")
    -- opened: the ranks still to come, each with its way; the Horde's book vendor is not shown
    card.click()
    local rows = Mock.rows()
    check(has(rows, "Learned: Apprentice, Journeyman"))
    check(has(rows, "Expert  skill cap 225 | at Cooking 125"))
    check(has(rows, "Book: Expert Cookbook - Shandrina, Ashenvale | vendor") and not has(rows, "Wulan"))
    check(has(rows, "Artisan  skill cap 300 | at Cooking 225"))
    check(has(rows, "Quest: Clamlette Surprise - Dirge Quikcleave, Tanaris | level 35"))
    check(not frame.hideButton:IsShown(), "the training card cannot be hidden")
    frame:Click("RightButton")
    check(ns.Window.lines[1].training, "a right-click hid the training card")
    frame:Enter()
    check(not (ns.Window.tooltip and ns.Window.tooltip:IsShown()), "the training card has no item tooltip")
    -- it is not a recipe: no count moves, a search and the Hidden list leave it out
    check(Mock.info():find("0 of %d+ Cooking recipes known"), Mock.info())
    ns.Window.widgets.search:SetText("stormwind")
    check(not ns.Window.lines[1].training)
    ns.Window.widgets.search:SetText("")
    ns.Window.widgets.filters.hidden:Click()
    equal(#Mock.cards(), 0)
    ns.Window.widgets.filters.all:Click()

    -- a trainer's rank: your faction's trainers, and "others" when there are more
    tabs.alchemy:Click()
    card = ns.Window.lines[1]
    equal(Mock.plain(card.text), "Artisan Alchemy  raises your skill cap to 300")
    check(Mock.plain(card.right):find("Trainer: Kylanna Windwhisper, Feralas, 5g", 1, true) == 1, Mock.plain(card.right))
    card.click()
    rows = Mock.rows()
    -- what the rank costs, on every trainer's line
    check(has(rows, "Trainer: Kylanna Windwhisper, Feralas | 5g") and has(rows, "Trainer: Master Mycologist Shurome, Felwood | 5g"), table.concat(rows, "\n", 1, 8))
    check(not has(rows, "Rogvar"), "the Horde's Artisan alchemist is shown to the Alliance")
    check(has(rows, "Artisan  skill cap 300 | at Alchemy 200"))

    -- the last rank reached: nothing left, the card is green
    tabs.blacksmithing:Click()
    card = ns.Window.lines[1]
    equal(Mock.plain(card.text), "Blacksmithing training"); equal(card.state, "known")
    check(Mock.plain(card.desc):find("there is no further rank", 1, true), Mock.plain(card.desc))
    -- ... and its specializations, for your faction, marked as Classic's
    card.click()
    rows = Mock.rows()
    check(has(rows, "Specializations  (the quests as on Wowhead's WoW Forever pages)"))
    check(has(rows, "Armorsmith | at 200, level 40") and has(rows, "Weaponsmith | at 200, level 40"))
    check(has(rows, "Quest: The Art of the Armorsmith - Grumnus Steelshaper, Ironforge") and not has(rows, "Okothos Ironrager"))

    -- a profession the character does not have: where to learn it
    tabs.tailoring:Click()
    card = ns.Window.lines[1]
    equal(Mock.plain(card.text), "Learn Tailoring"); equal(card.skill, "-")
    check(Mock.plain(card.right):find("Trainer: Georgio Bolero, Stormwind City, 10c", 1, true) == 1, Mock.plain(card.right))
    check(Mock.info():find("does not have Tailoring", 1, true), Mock.info())
    check(Mock.rowIndex("Linen Reagent Bag"), "the recipes of a profession the character lacks are not listed")
    equal(ns.cdb.options.prof, "tailoring")

    -- the Horde's side of the same ranks
    ns = start({ faction = "Horde" }, function(state)
        state.skill = { level = 130, max = 150 }
    end)
    ns.Window:Show()
    equal(Mock.plain(ns.Window.lines[1].right), "Book: Expert Cookbook - Wulan, Desolace") -- a book: no trainer's price
    -- a price read in a trainer's own window wins, as for recipes
    equal(ns.Lookup.RankCost({ spell = 3101, cost = 500 }), 500)
    ns.db.trainerCosts[3101] = { cost = 475, at = 1 }
    local cost, seen = ns.Lookup.RankCost({ spell = 3101, cost = 500 })
    equal(cost, 475); equal(seen, true)
    equal(ns.Lookup.RankCost({ spell = 3413 }), nil, "no price known: none shown")
    equal(ns.Lookup.RankCost(nil), nil)
    -- every profession has its four ranks, in order, each with a way to it
    for _, key in ipairs(KEYS) do
        local training = ns.Lookup.Training(key)
        check(training and #training.ranks == 4, key .. ": four ranks")
        local cap = 0
        for _, rank in ipairs(training.ranks) do
            check(rank.cap > cap, key .. ": the ranks' caps rise"); cap = rank.cap
            check(rank.trainers or rank.book or rank.quests, key .. " " .. rank.name .. ": no way to it")
            -- a rank a trainer teaches has its price; a book or a quest has none
            check((type(rank.cost) == "number" and rank.cost > 0) == (rank.trainers ~= nil and not rank.book and not rank.quests),
                key .. " " .. rank.name .. ": a trainer's rank has a price, a book's or a quest's has none")
        end
        equal(cap, 300)
    end
    check(ns.Lookup.Training("mining").ranks[3].unsure, "Mining's Expert trainers were not read: it has to say so")
    equal(#ns.Lookup.Training("engineering").specs, 2); equal(#ns.Lookup.Training("leatherworking").specs, 3)
end)

scenario("a recipe of a specialization carries its tag and says what it needs", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skills[ENGINEERING] = { level = 300, max = 300 }
    end)
    Mock.slash("show all")
    ns.Window.widgets.tabs.engineering:Click()
    local gnomish
    for _, recipe in ipairs(ns.Lookup.Recipes("engineering")) do
        if recipe.spec == "Gnomish" and not gnomish then gnomish = recipe end
    end
    check(gnomish, "no Gnomish recipe in the table")
    local card = cardNamed(ns, gnomish.name)
    check(Mock.plain(card.tags):find("Gnomish", 1, true), Mock.plain(card.tags))
    card.click()
    check(has(Mock.rows(), "Needs the Gnomish Engineering specialization."))
    ns.Window.open = {}
    ns.Window.widgets.search:SetText("goblin")
    local tagged, total = 0, 0
    for _, recipe in ipairs(ns.Lookup.Recipes("engineering")) do
        if recipe.spec == "Goblin" then total = total + 1 end
    end
    for _, entry in ipairs(ns.Window.lines) do
        if entry.card and Mock.plain(entry.tags):find("Goblin", 1, true) then tagged = tagged + 1 end
    end
    check(total >= 5, "the Goblin recipes in the table: " .. total)
    equal(tagged, total, "the search for 'goblin' lists every Goblin recipe")
    check(not ns.Lookup.Matches({ name = "x", spec = "Gnomish" }, "goblin"), "a Gnomish recipe matched 'goblin'")
end)

scenario("a recipe whose item needs a reputation standing says so: the tag, the card's line, the opened card, the search", function()
    -- the user, 2026-11-20: "sometimes a BOP vendor recipe requires a rep level and we aren't representing that at all"
    local ns = start({ faction = "Alliance" }, function(state)
        state.skills[TAILORING] = { level = 300, max = 300 }
    end)
    Mock.slash("show all")
    local function recipeNamed(prof, name)
        for _, recipe in ipairs(ns.Lookup.Recipes(prof)) do
            if recipe.name == name then return recipe end
        end
        error("no recipe " .. name)
    end
    -- the client's item table: Pattern: Sylvan Vest "Requires Cenarion Circle - Revered"
    local rep = ns.Lookup.Rep(recipeNamed("tailoring", "Sylvan Vest"))
    check(rep, "no standing on the Sylvan Vest's pattern")
    equal(rep.name, "Cenarion Circle"); equal(rep.standing, 6); equal(rep.word, "Revered")
    equal(ns.Lookup.RepWords(rep), "Cenarion Circle - Revered")
    equal(ns.Lookup.Rep(recipeNamed("tailoring", "Linen Reagent Bag")), nil, "a pattern anybody can buy")
    equal(ns.Lookup.Rep({ name = "x" }), nil, "a trainer's recipe has no item to need anything")
    equal(ns.Lookup.Rep(nil), nil)

    ns.Window.widgets.tabs.tailoring:Click()
    local card = cardNamed(ns, "Sylvan Vest")
    check(Mock.plain(card.tags):find("Revered", 1, true), Mock.plain(card.tags))
    equal(Mock.plain(card.right), "Cenarion Circle: Mishta, Silithus - needs Revered")
    card.click()
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: below that the recipe can be neither bought nor learned."), table.concat(Mock.rows(), "\n"))
    -- a pattern without the need says nothing of the kind
    ns.Window.open = {}
    card = cardNamed(ns, "Linen Reagent Bag")
    check(not Mock.plain(card.right):find("needs", 1, true), Mock.plain(card.right))
    card.click()
    for _, row in ipairs(Mock.rows()) do
        check(not row:find("Requires", 1, true), row)
    end
    -- the search: the faction, the standing, or "rep"
    check(ns.Lookup.Matches(recipeNamed("tailoring", "Sylvan Vest"), "cenarion"), "the faction's name")
    check(ns.Lookup.Matches(recipeNamed("tailoring", "Sylvan Vest"), "revered"), "the standing")
    check(ns.Lookup.Matches(recipeNamed("tailoring", "Sylvan Vest"), "rep"), "'rep' lists everything that needs a standing")
    check(not ns.Lookup.Matches(recipeNamed("tailoring", "Sylvan Vest"), "honored"), "another standing")
    check(not ns.Lookup.Matches(recipeNamed("tailoring", "Linen Reagent Bag"), "reputation"), "a pattern without the need")
    check(not ns.Lookup.Matches(recipeNamed("tailoring", "Linen Reagent Bag"), "revered"), "a pattern without the need")
    -- every standing in the tables is one the game has a word for, on a faction with a name
    local total = 0
    for _, prof in ipairs({ "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring", "cooking", "firstaid", "mining" }) do
        for _, recipe in ipairs(ns.Lookup.Recipes(prof)) do
            local need = ns.Lookup.Rep(recipe)
            if need then
                total = total + 1
                check(type(need.name) == "string" and need.name ~= "", recipe.name .. ": a faction without a name")
                check(need.standing >= 4 and need.standing <= 7 and need.word, recipe.name .. ": standing " .. tostring(need.standing))
                -- ... and one the character's standing is read for (Lookup.RepFactions)
                equal(ns.Lookup.RepFactions()[need.faction], need.name, recipe.name .. ": a faction no standing is read for")
            end
        end
    end
    check(total >= 150, "recipes that need a standing: " .. total)
end)

scenario("a reputation recipe's vendor goes by the faction's name: on the tag and on the card's line, in place of 'Vendor'", function()
    -- the user, 2026-11-20: "instead of "Vendor" can we put the rep name for those items (of course they come
    -- from a vendor if it's faction based)" - asked which of the two, the tag or the line: both
    local ns = start({ faction = "Alliance" }, function(state)
        state.skills[TAILORING] = { level = 300, max = 300 }
        state.skills[BLACKSMITHING] = { level = 300, max = 300 }
        state.skills[ALCHEMY] = { level = 300, max = 300 }
    end)
    Mock.slash("show all")
    local tabs = ns.Window.widgets.tabs
    local function card(tab, name)
        tabs[tab]:Click()
        ns.Window.open = {}
        ns.Window:Render()
        return cardNamed(ns, name)
    end
    -- the faction where "Vendor" stood, in the vendor tag's colour, its standing right after it; the line
    -- starts with the faction and so names it once: only the standing is left at its end
    local vest = card("tailoring", "Sylvan Vest")
    equal(Mock.plain(vest.tags), "Cenarion Circle  Revered   BoP")
    check(vest.tags:find("|cffe6cc80Cenarion Circle|r  |cff33c9a7Revered|r", 1, true), vest.tags)
    equal(Mock.plain(vest.right), "Cenarion Circle: Mishta, Silithus - needs Revered")
    -- the opened card lists every way to get it, under its "Requires" line: the vendor is a vendor there
    vest.click()
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered"), table.concat(Mock.rows(), "\n"))
    check(has(Mock.rows(), "Vendor: Mishta, Silithus"), table.concat(Mock.rows(), "\n"))
    -- "vendor" in the search box still lists it
    local pattern
    for _, recipe in ipairs(ns.Lookup.Recipes("tailoring")) do
        if recipe.name == "Sylvan Vest" then pattern = recipe end
    end
    check(ns.Lookup.Matches(pattern, "vendor"), "a faction's vendor is still a vendor to the search")
    -- several vendors: the first, and how many more
    local essence = card("alchemy", "Essence of Fire")
    equal(Mock.plain(essence.tags), "Argent Dawn  Honored   BoP")
    equal(Mock.plain(essence.right), "Argent Dawn: Quartermaster Miranda Breechlock, Eastern Plaguelands  (+2 more) - needs Honored")
    -- a specialization's recipe: the faction and its standing stay together, the specialization after them
    local bracers = card("blacksmithing", "Dark Iron Bracers")
    equal(Mock.plain(bracers.tags), "Thorium Brotherhood  Friendly  Armorsmith   BoP")
    equal(Mock.plain(bracers.right), "Thorium Brotherhood: Lokhtos Darkbargainer, Blackrock Depths - needs Friendly")
    -- a recipe that needs a standing but is not a vendor's: nothing took the faction's name, so the line's
    -- end still says it
    local shoulders = card("blacksmithing", "Dawnbringer Shoulders")
    equal(Mock.plain(shoulders.tags), "Drop  Armorsmith  Revered   BoE")
    equal(Mock.plain(shoulders.right), "Drop: Hive'Zora Tunneler, Silithus  (+1 more) - needs Argent Dawn Revered")
    local icebane = card("blacksmithing", "Icebane Bracers")
    equal(Mock.plain(icebane.tags), "Revered   BoP")
    equal(Mock.plain(icebane.right), "Source unknown - needs Hydraxian Waterlords Revered")
    -- a vendor's recipe without a standing: a vendor, as before
    local bag = card("tailoring", "Linen Reagent Bag")
    check(Mock.plain(bag.tags):find("Vendor", 1, true) == 1, Mock.plain(bag.tags))
    check(Mock.plain(bag.right):find("Vendor: ", 1, true) == 1, Mock.plain(bag.right))
end)

local CENARION, TIMBERMAW = 609, 576
local HONORED, REVERED, FRIENDLY, NEUTRAL = 6, 7, 5, 4 -- as the client counts a reaction: 1 Hated .. 8 Exalted
local SYLVAN_VEST_PATTERN = 22774 -- "Requires Cenarion Circle - Revered"; the Sylvan Shoulders' asks for Friendly

scenario("a character's own standing against what a recipe needs: the tag's colour, the gold rim, the card's line, the opened card", function()
    -- asked "Also show each character's own standing against the requirement?", the user, 2026-11-20: "Yes, add standing"
    local ns, state = start({ faction = "Alliance" }, function(state)
        state.skills[TAILORING] = { level = 300, max = 300 }
        state.rep[CENARION] = { reaction = HONORED, into = 3200 }
    end)
    -- kept on the character as the item table counts standings: 4 Friendly .. 7 Exalted
    local saved = ns.cdb.rep[CENARION]
    equal(saved.s, 5); equal(saved.v, 3200); equal(saved.m, 12000)
    equal(saved.a, 12200, "the reputation itself, as the client counts it from Neutral 0")
    check(ns.cdb.repAt, "when the standings were read")
    Mock.slash("show all")
    ns.Window.widgets.tabs.tailoring:Click()
    -- the standing is short: no gold rim (the skill alone would learn it), the tag orange, and how much
    -- reputation is still to earn - the user, 2026-11-20: "instead of showing like neutral/honored can we
    -- just show exactly how many reputation points you need to earn to get to that goal?"
    local vest = cardNamed(ns, "Sylvan Vest")
    equal(vest.state, "later", "Tailoring 300 but Honored: not learnable now")
    check(vest.tags:find("|cffff9040Revered|r", 1, true), vest.tags)
    equal(Mock.plain(vest.right), "Cenarion Circle: Mishta, Silithus - 8,800 rep to Revered")
    vest.click()
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: 8,800 reputation to go. Below Revered the recipe can be neither bought nor learned."),
        table.concat(Mock.rows(), "\n"))
    -- the standing is there: gold rim, the tag green, the card's line no longer says what it needs
    ns.Window.open = {}
    ns.Window:Render()
    local shoulders = cardNamed(ns, "Sylvan Shoulders")
    equal(shoulders.state, "now")
    check(shoulders.tags:find("|cff60ff60Friendly|r", 1, true), shoulders.tags)
    equal(Mock.plain(shoulders.right), "Cenarion Circle: Mishta, Silithus")
    shoulders.click()
    check(has(Mock.rows(), "Requires Cenarion Circle - Friendly: you have it."), table.concat(Mock.rows(), "\n"))
    for _, row in ipairs(Mock.rows()) do
        check(not row:find("neither bought", 1, true), row)
    end
    -- the standing moves while the window is open: heard, and the card follows
    ns.Window.open = {}
    Mock.standing(CENARION, REVERED, 0)
    equal(ns.cdb.rep[CENARION].s, 6)
    vest = cardNamed(ns, "Sylvan Vest")
    equal(vest.state, "now")
    check(vest.tags:find("|cff60ff60Revered|r", 1, true), vest.tags)
    equal(Mock.plain(vest.right), "Cenarion Circle: Mishta, Silithus")
    -- two standings short: the whole way, over the standing between (Friendly at 4,200 of Revered's 21,000)
    Mock.standing(CENARION, FRIENDLY, 1200)
    vest = cardNamed(ns, "Sylvan Vest")
    equal(vest.state, "later")
    equal(Mock.plain(vest.right), "Cenarion Circle: Mishta, Silithus - 16,800 rep to Revered")
    vest.click()
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: 16,800 reputation to go. Below Revered the recipe can be neither bought nor learned."),
        table.concat(Mock.rows(), "\n"))
    -- from below Neutral too: Unfriendly at -2,000
    Mock.standing(CENARION, 3, 1000)
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: 23,000 reputation to go."), table.concat(Mock.rows(), "\n"))
    -- a faction whose standings are not the ordinary size (the client's own numbers for the standing it is
    -- in say so): no sum over standings nobody gave a size for - where it is, in the client's numbers
    Mock.standing(CENARION, FRIENDLY, 1200, 0, 8000)
    equal(Mock.plain(cardNamed(ns, "Sylvan Vest").right), "Cenarion Circle: Mishta, Silithus - needs Revered")
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: you are Friendly 1200/8000. Below Revered the recipe can be neither bought nor learned."),
        table.concat(Mock.rows(), "\n"))
    -- ... but into the very next standing the client's own numbers are the answer, whatever the size
    Mock.standing(CENARION, HONORED, 100, 8000, 10000)
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: 1,900 reputation to go."), table.concat(Mock.rows(), "\n"))
    -- the sum itself
    equal(ns.Known.PointsTo({ s = 5, v = 3200, m = 12000, a = 12200 }, 6), 8800)
    equal(ns.Known.PointsTo({ s = 5, v = 3200, m = 12000, a = 12200 }, 7), 29800, "Honored to Exalted")
    equal(ns.Known.PointsTo({ s = 5, v = 3200, m = 12000 }, 6), 8800, "kept before the reputation itself was: the next standing still")
    equal(ns.Known.PointsTo({ s = 4, v = 0, m = 6000 }, 6), nil, "... and no further")
    equal(ns.Known.PointsTo({ s = 6, v = 0, m = 21000, a = 21000 }, 6), nil, "there already")
    equal(ns.Known.PointsTo({ s = 4 }, 5), nil, "the client gave no numbers")
    equal(ns.Known.PointsTo({ s = 4, v = 1200, m = 6000, a = 1200 }, 6), nil, "Friendly of the ordinary size, starting elsewhere")
    equal(ns.Known.PointsTo({ s = 4, v = 1200, m = 8000, a = 4200 }, 6), nil, "Friendly starting where it does, of another size")
    equal(ns.Known.StandingText({ s = 5, v = 1, m = 2 }), "Honored 1/2"); equal(ns.Known.StandingText({ s = 6 }), "Revered")
    equal(ns.Known.StandingText({ s = 7, v = 0, m = 999 }), "Exalted"); equal(ns.Known.StandingText(false), nil)
    equal(ns.Known.PointsTo(false, 5), nil); equal(ns.Known.PointsTo(nil, 5), nil)
    equal(ns.Known.Grouped(900), "900"); equal(ns.Known.Grouped(0), "0")
    equal(ns.Known.Grouped(123456), "123,456"); equal(ns.Known.Grouped(1234567), "1,234,567")
    -- a faction the character never met (the client answers for another, and nothing for this one)
    state.rep[TIMBERMAW] = { reaction = NEUTRAL, into = 10 }
    Mock.standing(CENARION, nil)
    equal(ns.cdb.rep[CENARION], false)
    equal(cardNamed(ns, "Sylvan Vest").state, "later")
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: you have not met them yet. Below Revered the recipe can be neither bought nor learned."),
        table.concat(Mock.rows(), "\n"))
    -- a burst of UPDATE_FACTION (every kill says it) is one read
    local before = state.calls.rep
    for _ = 1, 20 do Mock.fire("UPDATE_FACTION") end
    Mock.advance(3)
    equal(state.calls.rep - before, 9, "one pass over the nine factions")
    -- a standing's change is no news for the guild or friends (KNOWN_CHANGED has them say hello), and a
    -- read that finds nothing new redraws nothing
    local known, moved = 0, 0
    ns:Listen("KNOWN_CHANGED", function() known = known + 1 end)
    ns:Listen("STANDING_CHANGED", function() moved = moved + 1 end)
    Mock.standing(TIMBERMAW, NEUTRAL, 20)
    equal(known, 0); equal(moved, 1)
    Mock.standing(TIMBERMAW, NEUTRAL, 20)
    equal(moved, 1, "nothing moved")
    equal(#Mock.errors, 0, Mock.errors[1])
end)

scenario("standings are only written when the client answers: no such call, secrets, an error, an empty list - what was read before stays", function()
    -- a client without the calls: the card is as it was before standings were read at all
    local ns, state = start({ faction = "Alliance", noReputation = true }, function(state)
        state.skills[TAILORING] = { level = 300, max = 300 }
    end)
    equal(ns.cdb.rep, nil); equal(ns.cdb.repAt, nil)
    Mock.slash("show all")
    ns.Window.widgets.tabs.tailoring:Click()
    local vest = cardNamed(ns, "Sylvan Vest")
    equal(vest.state, "now", "nothing known of the standing: the skill decides")
    check(vest.tags:find("|cff33c9a7Revered|r", 1, true), vest.tags)
    equal(Mock.plain(vest.right), "Cenarion Circle: Mishta, Silithus - needs Revered")
    vest.click()
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: below that the recipe can be neither bought nor learned."), table.concat(Mock.rows(), "\n"))
    for _, row in ipairs(Mock.rows()) do
        check(not row:find("log it in", 1, true), "the one logged in is not told to log in: " .. row)
    end
    equal(ns.Known:Describe().rep.raw.answered, "no such call")

    -- the reputation list has factions, none of them one a recipe asks for: that is an answer - never met
    ns, state = start({ faction = "Alliance" }, function(state)
        state.skills[TAILORING] = { level = 300, max = 300 }
        state.rep[72] = { reaction = FRIENDLY, into = 0 } -- Stormwind
    end)
    equal(ns.cdb.rep[CENARION], false)
    check(ns.cdb.repAt, "read")

    -- the reputation list is empty and no faction answers (a login too early): nothing is written
    ns, state = start({ faction = "Alliance" }, function(state)
        state.skills[TAILORING] = { level = 300, max = 300 }
    end)
    equal(ns.cdb.rep, nil); equal(ns.cdb.repAt, nil)
    -- then it answers
    Mock.standing(CENARION, HONORED, 3200)
    equal(ns.cdb.rep[CENARION].s, 5)
    equal(ns.cdb.rep[TIMBERMAW], false, "the client answered, and has nothing on Timbermaw Hold")
    -- secrets, a secret field, an error: the standing read before stays, nothing is raised
    for _, mode in ipairs({ "secret", "secretField", "error" }) do
        state.repMode = mode
        state.rep[CENARION] = { reaction = REVERED, into = 0 }
        Mock.fire("UPDATE_FACTION")
        Mock.advance(3)
        equal(ns.cdb.rep[CENARION].s, 5, mode)
        equal(ns.cdb.rep[CENARION].v, 3200, mode)
    end
    equal(ns.cdb.rep[TIMBERMAW], false, "an unanswered pass does not make a faction met or unmet")
    -- the list went empty with nothing answering (logging out): what was read stays
    state.repMode, state.rep, state.repCount = "ok", {}, 0
    Mock.fire("UPDATE_FACTION")
    Mock.advance(3)
    equal(ns.cdb.rep[CENARION].s, 5)
    -- /akr diag keeps what the client said, faction by faction
    state.repCount, state.rep[CENARION] = nil, { reaction = REVERED, into = 15 }
    Mock.fire("UPDATE_FACTION")
    Mock.advance(3)
    local diag = ns.Known:Describe().rep
    equal(diag.raw[CENARION], "7 15/21000")
    equal(diag.raw[TIMBERMAW], "nil")
    check(diag.reads >= 2, "reads: " .. tostring(diag.reads))
    equal(ns.cdb.rep[CENARION].s, 6)
    equal(#Mock.errors, 0, Mock.errors[1])
end)

scenario("your other characters' standings: kept from their own login, on the card when viewed and on the recipe item's tooltip", function()
    local db = { schema = 2, chars = {
        -- Revered: read at its own login
        ["Purr Smith - ClassicBetaPvE"] = { learned = {}, skills = { tailoring = { skill = 300, max = 300 } }, profs = { tailoring = true }, side = "A", options = {},
            rep = { [CENARION] = { s = 6, v = 100, m = 21000 } }, repAt = 5 },
        -- not logged in since standings are read
        ["Purr Know - ClassicBetaPvE"] = { learned = {}, skills = { tailoring = { skill = 300, max = 300 } }, profs = { tailoring = true }, side = "A", options = {} },
        -- the skill and the standing both short
        ["Purr Low - ClassicBetaPvE"] = { learned = {}, skills = { tailoring = { skill = 20, max = 75 } }, profs = { tailoring = true }, side = "A", options = {},
            rep = { [CENARION] = { s = 4, v = 0, m = 6000, a = 3000 } }, repAt = 5 },
        -- never met the Cenarion Circle
        ["Purr New - ClassicBetaPvE"] = { learned = {}, skills = { tailoring = { skill = 300, max = 300 } }, profs = { tailoring = true }, side = "A", options = {},
            rep = { [CENARION] = false }, repAt = 5 },
    } }
    local ns = start({ db = db, tooltips = true, faction = "Alliance" }, function(state)
        state.skills[TAILORING] = { level = 300, max = 300 } -- Purr Gola, the one logged in
        state.rep[CENARION] = { reaction = HONORED, into = 3200 }
    end)
    -- the tooltip: who can learn it now first, then who lacks the standing, then who lacks the skill
    equal(Mock.showItem(SYLVAN_VEST_PATTERN), "Your characters: "
        .. "|   Purr Know: can learn it (Tailoring 300), if Cenarion Circle Revered "
        .. "|   Purr Smith: can learn it (Tailoring 300) "
        .. "|   Purr Gola: needs Cenarion Circle Revered (8,800 to go) "
        .. "|   Purr New: needs Cenarion Circle Revered (not met yet) "
        .. "|   Purr Low: Tailoring 20, needs 300 and Cenarion Circle Revered (18,000 to go)")
    local _, lines = Mock.showItem(SYLVAN_VEST_PATTERN)
    equal(string.format("%.2f %.2f %.2f", lines[3].r, lines[3].g, lines[3].b), "0.25 1.00 0.25", "can learn: green")
    equal(string.format("%.2f %.2f %.2f", lines[4].r, lines[4].g, lines[4].b), "1.00 0.50 0.25", "the standing is short: orange")
    -- the window, looking at the one who is Revered
    Mock.slash("show all")
    ns.Window.char = "Purr Smith - ClassicBetaPvE"
    ns.Window:SetProfession("tailoring")
    local vest = cardNamed(ns, "Sylvan Vest")
    equal(vest.state, "now")
    equal(Mock.plain(vest.right), "Cenarion Circle: Mishta, Silithus")
    vest.click()
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: you have it."), table.concat(Mock.rows(), "\n"))
    -- and at the one whose standings were never read: said so
    ns.Window.char = "Purr Know - ClassicBetaPvE"
    ns.Window:Render()
    vest = cardNamed(ns, "Sylvan Vest")
    equal(vest.state, "now")
    equal(Mock.plain(vest.right), "Cenarion Circle: Mishta, Silithus - needs Revered")
    check(has(Mock.rows(), "Requires Cenarion Circle - Revered: below that the recipe can be neither bought nor learned. This character's standing is not read yet - log it in once."),
        table.concat(Mock.rows(), "\n"))
    -- the one logged in reads its own standing; the others' are left alone
    equal(db.chars["Purr Smith - ClassicBetaPvE"].rep[CENARION].s, 6)
    equal(db.chars["Purr Know - ClassicBetaPvE"].rep, nil)
    equal(#Mock.errors, 0, Mock.errors[1])
end)

scenario("Leatherworking's and Blacksmithing's specializations: the tag, what it needs, and whose trainers teach it", function()
    -- the user, 2026-11-14: "it doesn't do a good job of showing specialties - like black dragonscale legs"
    local ns = start({ faction = "Alliance" }, function(state)
        state.skills[LEATHERWORKING] = { level = 300, max = 300 }
        state.skills[BLACKSMITHING] = { level = 300, max = 300 }
    end)
    Mock.slash("show all")
    local function recipeNamed(prof, name)
        for _, recipe in ipairs(ns.Lookup.Recipes(prof)) do
            if recipe.name == name then return recipe end
        end
        error("no recipe " .. name)
    end
    local legs = recipeNamed("leatherworking", "Black Dragonscale Leggings")
    equal(legs.spec, "Dragonscale")
    -- the specialization's whole name, for sentences
    equal(ns.Lookup.SpecName(legs), "Dragonscale Leatherworking")
    equal(ns.Lookup.SpecName({ spec = "Gnomish" }), "Gnomish Engineering")
    equal(ns.Lookup.SpecName({ spec = "Swordsmith" }), "Master Swordsmith")
    equal(ns.Lookup.SpecName({ spec = "Unheard Of" }), "Unheard Of", "a word the table lacks reads as itself")
    equal(ns.Lookup.SpecName({}), nil); equal(ns.Lookup.SpecName(nil), nil)

    -- a pattern that drops: the tag on the card, the sentence in the opened card
    ns.Window.widgets.tabs.leatherworking:Click()
    local card = cardNamed(ns, "Black Dragonscale Leggings")
    check(Mock.plain(card.tags):find("Dragonscale", 1, true), Mock.plain(card.tags))
    card.click()
    check(has(Mock.rows(), "Needs the Dragonscale Leatherworking specialization."))
    -- a specialization's trainer recipe: not "any trainer"
    ns.Window.open = {}
    card = cardNamed(ns, "Dragonscale Gauntlets")
    equal(Mock.plain(card.right), "Dragonscale Leatherworking trainers, 90s")
    card.click()
    check(has(Mock.rows(), "Only Dragonscale Leatherworking trainers teach it. | 90s"), table.concat(Mock.rows(), "\n", 1, 10))
    check(not has(Mock.rows(), "Any Leatherworking trainer teaches it."), "the opened card still says any trainer")

    -- Blacksmithing: Armorsmith, and a Weaponsmith's further specialization
    ns.Window.open = {}
    ns.Window.widgets.tabs.blacksmithing:Click()
    equal(recipeNamed("blacksmithing", "Truesilver Gauntlets").spec, "Armorsmith")
    card = cardNamed(ns, "Truesilver Gauntlets")
    check(Mock.plain(card.tags):find("Armorsmith", 1, true), Mock.plain(card.tags))
    equal(Mock.plain(card.right), "Armorsmith trainers, 1g")
    equal(recipeNamed("blacksmithing", "Dawn's Edge").spec, "Axesmith")
    card = cardNamed(ns, "Dawn's Edge")
    check(Mock.plain(card.tags):find("Axesmith", 1, true), Mock.plain(card.tags))
    card.click()
    check(has(Mock.rows(), "Needs the Master Axesmith specialization."))

    -- the search finds them by the short word and by the whole name
    check(ns.Lookup.Matches({ name = "x", spec = "Dragonscale" }, "dragonscale leatherworking"))
    check(ns.Lookup.Matches({ name = "x", spec = "Swordsmith" }, "Master Swordsmith"))
    check(not ns.Lookup.Matches({ name = "x", spec = "Tribal" }, "elemental"))
    -- every specialization in the tables is one the window has a tag and a name for
    local counts = {}
    for _, key in ipairs(KEYS) do
        for _, recipe in ipairs(ns.Lookup.Recipes(key) or {}) do
            if recipe.spec then
                counts[recipe.spec] = (counts[recipe.spec] or 0) + 1
                check(ns.Window.SpecTag(recipe.spec), key .. " " .. recipe.name .. ": no tag for " .. recipe.spec)
                check(ns.Lookup.SpecName(recipe) ~= recipe.spec or recipe.spec == "Armorsmith" or recipe.spec == "Weaponsmith",
                    recipe.name .. ": no whole name for " .. recipe.spec)
            end
        end
    end
    for _, spec in ipairs({ "Gnomish", "Goblin", "Dragonscale", "Elemental", "Tribal", "Armorsmith", "Weaponsmith", "Swordsmith", "Hammersmith", "Axesmith" }) do
        check((counts[spec] or 0) >= 3, spec .. ": " .. (counts[spec] or 0) .. " recipes in the tables")
    end
end)

scenario("the other professions' sources read in words: world drops, chests, trainers that sell, quests that teach, guesses", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 0, max = 0 }
        for _, line in ipairs({ BLACKSMITHING, ALCHEMY, ENGINEERING, LEATHERWORKING }) do
            state.skills[line] = { level = 300, max = 300 }
        end
    end)
    Mock.slash("show all")
    local tabs = ns.Window.widgets.tabs
    local function open(tab, name)
        tabs[tab]:Click()
        ns.Window.open = {}
        local entry = cardNamed(ns, name)
        entry.click()
        return cardNamed(ns, name), Mock.rows()
    end

    local vest, rows = open("blacksmithing", "Copper Chain Vest")
    check(Mock.plain(vest.right):find("Quest: Supplying the Front  (+", 1, true) == 1, Mock.plain(vest.right))
    equal(Mock.plain(vest.tags), "Quest  Drop   BoE")
    equal(Mock.plain(vest.desc), "Mail chest, level 5 - +1 Strength")
    check(has(rows, "World drop, creatures of level 5-25. | world drop"))
    check(has(rows, "Blacksmithing 30 to learn; it gives skill until 110.  You have 300."))
    check(has(rows, "Plans: Copper Chain Vest does not bind - it can be mailed, traded or auctioned. | BoE"))
    local worldOnly = ns.Lookup.Sources({ spell = 1, world = { 5, 25 } }, "A")
    check(worldOnly.any and not worldOnly.unknown, "a world drop is a source")
    equal(table.concat(ns.Lookup.Kinds(worldOnly), " "), "drop")
    equal(ns.Lookup.Summary({ spell = 1, world = { 5, 25 } }, "A"), "drop")
    -- a recipe that is a world drop and nothing else says so on its card
    for _, recipe in ipairs(ns.Lookup.Recipes("blacksmithing")) do
        if recipe.world and not recipe.vendors and not recipe.quests and not recipe.drops then
            local card = cardNamed(ns, recipe.name)
            equal(Mock.plain(card.right), "World drop, creatures of level " .. recipe.world[1] .. "-" .. recipe.world[2], recipe.name)
            break
        end
    end

    local belt
    belt, rows = open("blacksmithing", "Justicar's Belt")
    check(Mock.plain(belt.right):find("Sold by 12 Blacksmithing trainers", 1, true) == 1, Mock.plain(belt.right))
    check(Mock.plain(belt.tags):find("Vendor", 1, true) == 1)
    check(has(rows, "12 Blacksmithing trainers sell the recipe."))

    local stone
    stone, rows = open("blacksmithing", "Rough Sharpening Stone")
    equal(Mock.plain(stone.right), "Comes with Blacksmithing"); equal(Mock.plain(stone.tags), "Automatic")
    check(has(rows, "It comes by itself with Blacksmithing: nothing to buy or find. | automatic"))
    local mace
    mace, rows = open("blacksmithing", "Copper Mace")
    equal(Mock.plain(mace.right), "Any Blacksmithing trainer, 50c"); equal(Mock.plain(mace.tags), "Trainer")
    check(has(rows, "Any Blacksmithing trainer teaches it. | 50c"), "the trainer's price, from the tables")
    -- a trainer's own window: its price wins, for the whole account, and says so
    Mock.trainer({ { name = "Copper Mace", cost = 60 }, { name = "Battle Shout", cost = 100 } })
    mace, rows = open("blacksmithing", "Copper Mace")
    equal(Mock.plain(mace.right), "Any Blacksmithing trainer, 60c")
    check(has(rows, "Any Blacksmithing trainer teaches it. | 60c (seen at a trainer)"), table.concat(rows, "\n", 1, 8))
    equal(ns.db.trainerCosts[2737].cost, 60)
    equal(ns.Known.trainerPrices, 1, "a class spell's name is no recipe")

    local kit = open("leatherworking", "Forceful Medium Armor Kit")
    check(Mock.plain(kit.right):find("Sold in the capital cities", 1, true) == 1, Mock.plain(kit.right))

    local fuel
    fuel, rows = open("alchemy", "Goblin Rocket Fuel")
    check(Mock.plain(fuel.tags):find("Crafted", 1, true), Mock.plain(fuel.tags))
    check(has(rows, "Crafted by another profession: Goblin Rocket Fuel Recipe."))

    local force
    -- new in Forever, no recipe item: a guess - until a trainer's list was read with it in (Mana Well: Ainethil's)
    force, rows = open("alchemy", "Mana Well")
    equal(Mock.plain(force.right), "Any Alchemy trainer, 1s 5c")
    check(has(rows, "Any Alchemy trainer teaches it. | 1s 5c"))
    force, rows = open("alchemy", "Lesser Discolored Healing Potion")
    check(Mock.plain(force.right):find("Probably any Alchemy trainer", 1, true) == 1, Mock.plain(force.right))
    check(has(rows, "Probably any Alchemy trainer: no recipe item exists for it. (Not confirmed.)"))

    local recombobulator
    recombobulator, rows = open("engineering", "Major Recombobulator")
    check(has(rows, "Chest: Gordok Tribute, Dire Maul"), table.concat(rows, "\n", 1, 10))
    check(Mock.plain(recombobulator.tags):find("Drop", 1, true))

    local alarm
    alarm, rows = open("engineering", "Mobile Alarm")
    equal(Mock.plain(alarm.right), "Taught by a quest"); equal(Mock.plain(alarm.tags), "Quest")
    check(has(rows, "A quest teaches it. (Which one is not written down yet.) | quest"))
end)

scenario("sources the research found elsewhere say where they were found; a kind without a name says so", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 300, max = 300 }
        state.skills[BLACKSMITHING] = { level = 300, max = 300 }
    end)
    Mock.slash("show all")
    local tabs = ns.Window.widgets.tabs
    local function open(tab, name)
        tabs[tab]:Click()
        ns.Window.open = {}
        cardNamed(ns, name).click()
        return cardNamed(ns, name), Mock.rows()
    end
    -- one named creature, from Wowhead's list
    -- (Raptor Rouladen until the pages named its creature themselves, 2026-11-15)
    local frostguard, rows = open("blacksmithing", "Frostguard")
    equal(Mock.plain(frostguard.right), "Drop: Foreman Marcrid, Western Plaguelands")
    equal(Mock.plain(frostguard.tags), "Drop  Swordsmith   BoE"); equal(frostguard.state, "now")
    check(has(rows, "(Source found in Wowhead, not on the profession's page.)"))
    -- Questie's database: a creature and a chest
    local shoulders
    shoulders, rows = open("blacksmithing", "Dawnbringer Shoulders")
    check(has(rows, "(Source found in Questie, not on the profession's page.)"))
    check(has(rows, "Chest: Arena Treasure Chest, Stranglethorn Vale"), table.concat(rows, "\n", 1, 12))
    -- a recipe whose own Wowhead page named what its list only gave the kind of: a favor vendor per faction
    local hammer
    hammer, rows = open("blacksmithing", "Cracked Blacksmith Hammer")
    equal(Mock.plain(hammer.right), "Vendor: Stondry Darkhammer, Redridge Mountains, 30 Merchant's Favor")
    equal(Mock.plain(hammer.tags), "Vendor   BoP")
    check(not has(rows, "Gor'mak"), "the Horde's favor vendor is shown to the Alliance")
    -- raid bosses that share a drop are one line for the place
    tabs.cooking:Click()
    local recipes = ns.Lookup.Recipes("enchanting")
    local aq
    for _, recipe in ipairs(recipes) do
        if recipe.recipe and recipe.recipe.id == 20727 then aq = recipe end
    end
    check(aq and aq.drops[1].npc == "Bosses" and aq.drops[1].zone == "Ahn'Qiraj", "the Ahn'Qiraj formula lost its bosses")
    -- the kind is known, the name is not: a made-up recipe, since the research has named every real one
    table.insert(ns.Lookup.Recipes("cooking"), 1, { spell = 99999001, name = "Aaa Test Dish", icon = "inv_misc_food_15", prof = "cooking",
        learn = 1, yellow = 2, green = 3, grey = 4, recipe = { id = 99999002, name = "Recipe: Aaa Test Dish", bop = true }, somewhere = { vendor = true, drop = true } })
    ns.Window.open = {}
    ns.Window:Render()
    cardNamed(ns, "Aaa Test Dish").click()
    local dish = cardNamed(ns, "Aaa Test Dish")
    rows = Mock.rows()
    equal(Mock.plain(dish.right), "Sold by a vendor (not known which)  (+1 more)")
    equal(Mock.plain(dish.tags), "Vendor  Drop   BoP")
    check(dish.state ~= "unknown", "a recipe with a known kind of source is not 'source unknown'")
    check(has(rows, "Sold by a vendor. (Which one is not written down yet.) | vendor"))
    check(has(rows, "Dropped by creatures. (Which one is not written down yet.) | drop"))
    local somewhere = ns.Lookup.Sources({ spell = 1, somewhere = { drop = true } }, "A")
    check(somewhere.any and not somewhere.unknown)
    equal(table.concat(ns.Lookup.Kinds(somewhere), " "), "drop"); equal(ns.Lookup.Summary({ spell = 1, somewhere = { drop = true } }, "A"), "drop")
    -- a recipe that comes with the skill is a source too, and is never "unknown"
    local auto = ns.Lookup.Sources({ spell = 1, auto = true }, "A")
    check(auto.any and not auto.unknown); equal(table.concat(ns.Lookup.Kinds(auto), " "), "auto")
    -- every enchant has its spell now: the trainer's first enchant is in the table
    local found
    for _, recipe in ipairs(ns.Lookup.Recipes("enchanting")) do
        if recipe.name == "Enchant Bracer - Minor Deflect" then found = recipe end
    end
    check(found and found.spell == 7428, "the enchants the page named without a spell id are missing")
    -- and what nobody knows is still said plainly
    Mock.slash("find flank au poivre")
    check(printed("Flank au Poivre (Cooking 275, missing, BoP): source not known yet."), table.concat(Mock.printed, "\n"))
end)

scenario("Wowhead's lists read again (2026-11-16): a recipe that is fished says 'Fished in Mount Hyjal'; creatures, a vendor and a quest newly named; a chance only where enough were counted", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 300, max = 300 }
        state.skills[ALCHEMY] = { level = 300, max = 300 }
        state.skills[BLACKSMITHING] = { level = 300, max = 300 }
        state.skills[LEATHERWORKING] = { level = 300, max = 300 }
    end)
    Mock.slash("show all")
    local tabs = ns.Window.widgets.tabs
    local function open(tab, name)
        tabs[tab]:Click()
        ns.Window.open = {}
        cardNamed(ns, name).click()
        return cardNamed(ns, name), Mock.rows()
    end
    -- caught fishing: no creature to name, the waters instead (1 of 123 catches on Wowhead's Forever page)
    local draught, rows = open("alchemy", "Draught of Water Walking")
    equal(Mock.plain(draught.right), "Fished in Mount Hyjal, 0.81%")
    equal(Mock.plain(draught.tags), "Drop   BoE")
    check(has(rows, "Fished in Mount Hyjal | 0.81%"), table.concat(rows, "\n", 1, 14))
    check(not has(rows, "Drop: Fishing"), "a fished recipe is listed as a creature's drop")
    check(has(rows, "(Source found in Wowhead, not on the profession's page.)"))
    equal(ns.Lookup.Summary(ns.Lookup.BySpell(11447), "A"), "fished: Mount Hyjal")
    Mock.slash("find draught of water walking")
    check(printed("Draught of Water Walking (Alchemy 180, missing, BoE): fished in Mount Hyjal."), table.concat(Mock.printed, "\n"))
    -- no zone written down: just "Fished"
    table.insert(ns.Lookup.Recipes("alchemy"), 1, { spell = 99999003, name = "Aaa Test Potion", icon = "inv_potion_15", prof = "alchemy",
        learn = 1, yellow = 2, green = 3, grey = 4, recipe = { id = 99999004, name = "Recipe: Aaa Test Potion" }, drops = { { npc = "Fishing", fished = true } } })
    ns.Window.open = {}
    ns.Window:Render()
    equal(Mock.plain(cardNamed(ns, "Aaa Test Potion").right), "Fished")
    -- a quest neither Questie nor the quest pages know: its name alone
    local firewater
    firewater, rows = open("alchemy", "Distilled Firewater")
    equal(Mock.plain(firewater.right), "Quest: Running Firewater")
    -- a dungeon creature looted too few times for a chance (1 of 17): named, with its level, no number
    local machine
    machine, rows = open("leatherworking", "Sewing Machine")
    equal(Mock.plain(machine.right), "Drop: Vectus, Scholomance")
    check(has(rows, "Drop: Vectus (60), Scholomance"), table.concat(rows, "\n", 1, 14))
    -- looted often enough (3 of 23): the chance is said
    local helm
    helm, rows = open("leatherworking", "Black Dragonscale Helm")
    equal(Mock.plain(helm.right), "Drop: Blackhand Assassin, Blackrock Spire, 13.04%")
    check(has(rows, "Drop: Blackhand Assassin (60-61), Blackrock Spire | 13.04%"), table.concat(rows, "\n", 1, 14))
    -- two creatures of one camp
    local cloak
    cloak, rows = open("leatherworking", "Nightscape Cloak")
    check(has(rows, "Drop: Bristleback Skullcrusher (42-43), Shen'dralas | 1.46%") and has(rows, "Drop: Bristleback Nomad (42-43), Shen'dralas | 0.99%"))
    -- a vendor both factions can buy from; no price was read
    local carver
    carver, rows = open("blacksmithing", "Stormcarver")
    equal(Mock.plain(carver.right), "Timbermaw Hold: Meilosh, Felwood - needs Revered") -- the standing: 2026-11-20
    check(ns.Lookup.Sources(ns.Lookup.BySpell(1252366), "H").any, "Meilosh sells to the Horde too")
    -- the steak the tests used as "nobody knows" has its creature
    local steak = ns.Lookup.Sources(ns.Lookup.BySpell(1250149), "A")
    check(steak.any and not steak.unknown and steak.drops[1].npc == "Frostsaber Pride Watcher", "Swiftstrike Steak lost its drop")
end)

scenario("an Alliance character sees its own faction's sources and no recipe only the Horde can get", function()
    local ns = start({ faction = "Alliance" })
    Mock.slash("show all")
    check(Mock.rowIndex("Westfall Stew"))
    Mock.clickRow(Mock.rowIndex("Brilliant Smallfish"))
    local rows = Mock.rows()
    check(has(rows, "Vendor: Catherine Leland, Stormwind City | 40c"))
    check(not has(rows, "Sewa Mistrunner"), "a Thunder Bluff vendor is shown to the Alliance")
    check(has(rows, "Nyalah Brightfire"), "a vendor of no faction went missing")
    -- a recipe only the Horde's vendor sells, whose recipe item binds when picked up: not in the Alliance's list
    ns.Window.widgets.tabs.tailoring:Click()
    check(Mock.rowIndex("Azure Stormsewn Cowl"))
    check(not Mock.rowIndex("Cloudy Stormsewn Cowl"), "a Horde-only recipe that binds is listed for the Alliance")
    -- the Horde's list
    ns = start({ faction = "Horde" })
    Mock.slash("show all")
    check(Mock.rowIndex("Crispy Bat Wing"))
    ns.Window.widgets.tabs.tailoring:Click()
    check(Mock.rowIndex("Cloudy Stormsewn Cowl"))
    check(not Mock.rowIndex("Bright Yellow Shirt"), "an Alliance-only recipe that binds is listed for the Horde")
    local shirt = ns.Lookup.BySpell(BRIGHT_YELLOW_SHIRT)
    local forHorde = ns.Lookup.Sources(shirt, "H")
    check(forHorde.otherSide and not forHorde.any and forHorde.theirs == nil)
    check(not ns.Lookup.Sources(shirt, "A").otherSide)
    equal(ns.Lookup.Summary(shirt, "H"), "other faction")
end)

scenario("a recipe only the other faction sells or is rewarded, whose recipe item does not bind, is in the list under that faction's name", function()
    -- the user, 2026-11-15: "Yes, show them" - 35 recipes (Westfall Stew for the Horde, Crispy Bat Wing for
    -- the Alliance ...) that somebody of the other faction can pass on or auction
    local ns = start({ faction = "Horde" })
    Mock.slash("show all")
    local stew = ns.Lookup.BySpell(WESTFALL_STEW)
    local sources = ns.Lookup.Sources(stew, "H")
    check(not sources.otherSide and not sources.any and not sources.unknown, "the Horde has no source of its own, and it is not hidden")
    equal(sources.theirs.side, "A"); equal(sources.theirs.name, "Alliance")
    equal(#sources.theirs.vendors, 1); equal(#sources.theirs.quests, 1)
    equal(#sources.vendors, 0, "the Alliance's vendor is not the Horde's")
    equal(ns.Lookup.Sources(stew, "A").theirs, nil, "the Alliance has it itself")
    equal(ns.Lookup.Sources(stew, nil).theirs, nil, "no faction known: every source is usable")
    equal(ns.Lookup.Summary(stew, "H"), "Alliance vendor")
    -- the card: the faction's name on the source and as a tag
    local card = cardNamed(ns, "Westfall Stew")
    equal(Mock.plain(card.right), "Alliance vendor: Kendor Kabonka, Stormwind City, 2s  (+1 more)")
    equal(Mock.plain(card.tags), "Alliance   BoE")
    card.click()
    local rows = Mock.rows()
    check(has(rows, "Alliance vendor: Kendor Kabonka, Stormwind City | 2s"), table.concat(rows, "\n", 1, 14))
    check(has(rows, "Alliance quest: Westfall Stew | level 13"))
    check(has(rows, "Only the Alliance gets it there. It does not bind: one of them can trade or auction it."))
    check(not has(rows, "other faction"))
    -- a quest alone
    ns.Window.open = {}
    card = cardNamed(ns, "Kaldorei Spider Kabob")
    equal(Mock.plain(card.right), "Alliance quest: Recipe of the Kaldorei")
    equal(ns.Lookup.Summary(ns.Lookup.BySpell(6412), "H"), "Alliance quest")
    -- the search: the faction's name, and its vendors and quests
    check(ns.Lookup.Matches(stew, "alliance", "H") and ns.Lookup.Matches(stew, "Kendor", "H") and ns.Lookup.Matches(stew, "stormwind", "H"))
    check(not ns.Lookup.Matches(stew, "alliance", "A"), "the Alliance's own recipe is not 'alliance' to the Alliance")
    check(not ns.Lookup.Matches(stew, "horde", "H"))
    Mock.slash("find westfall stew")
    check(printed("Westfall Stew (Cooking 75, missing, BoE): Alliance vendor Kendor Kabonka, Stormwind City 2s; Alliance quest Westfall Stew."), table.concat(Mock.printed, "\n"))
    -- it counts as missing: part of the list's total
    local total = 0
    for _, recipe in ipairs(ns.Lookup.Recipes("cooking")) do
        if not ns.Lookup.Sources(recipe, "H").otherSide then total = total + 1 end
    end
    Mock.slash("show missing")
    check(Mock.info():find("0 of " .. total, 1, true), Mock.info())

    -- the other way round: the Horde's vendor, for the Alliance
    ns = start({ faction = "Alliance" })
    Mock.slash("show all")
    card = cardNamed(ns, "Crispy Bat Wing")
    equal(Mock.plain(card.right), "Horde vendor: Abigail Shiel, Tirisfal Glades, 25c")
    equal(Mock.plain(card.tags), "Horde   BoE")
    -- every recipe left out of a faction's list is one that cannot come across
    for _, side in ipairs({ "A", "H" }) do
        local hidden, theirs = 0, 0
        for _, key in ipairs(KEYS) do
            for _, recipe in ipairs(ns.Lookup.Recipes(key) or {}) do
                local s = ns.Lookup.Sources(recipe, side)
                check(not (s.otherSide and s.theirs), recipe.name .. ": hidden and listed")
                if s.otherSide then
                    hidden = hidden + 1
                    check(recipe.side or ns.Lookup.Bind(recipe) ~= "boe", recipe.name .. " does not bind and is hidden from " .. side)
                elseif s.theirs then
                    theirs = theirs + 1
                    check(#s.theirs.vendors + #s.theirs.quests > 0, recipe.name .. ": the other faction's, and no vendor or quest named")
                end
            end
        end
        check(hidden >= 8 and theirs >= 10, side .. ": " .. hidden .. " hidden, " .. theirs .. " the other faction's")
    end
end)

scenario("a Shift-click on a card links what it makes, a Shift-right-click the recipe item - into the open chat line, or a new one", function()
    -- the user, 2026-11-15: "be able to link both the finished product and the pattern (if applicable) from
    -- the interface"
    local STEW_ITEM, STEW_RECIPE = 733, 728
    local ns, state = start({ faction = "Alliance" })
    Mock.slash("show all")
    local function frameOf(name)
        local _, index = cardNamed(ns, name)
        return Mock.cards()[index].frame
    end
    local function link(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[item " .. id .. "]|h|r" end
    -- the links themselves
    equal(ns.Window.LinkFor("item", STEW_ITEM), link(STEW_ITEM))
    equal(ns.Window.LinkFor("spell", 7428), "|cff71d5ff|Hspell:7428|h[spell 7428]|h|r")
    equal(ns.Window.LinkFor("item", nil), nil); equal(ns.Window.LinkFor("nothing", 5), nil); equal(ns.Window.LinkFor(nil, nil), nil)

    -- a chat line is open: the link goes into it, and the card does not open
    state.shift, state.chatOpen = true, true
    frameOf("Westfall Stew"):Click("LeftButton")
    equal(#Mock.linked, 1); equal(Mock.linked[1], link(STEW_ITEM))
    equal(ns.Window.open[WESTFALL_STEW], nil, "a Shift-click opened the card")
    -- the recipe item: Shift-right-click, and the recipe is not hidden
    frameOf("Westfall Stew"):Click("RightButton")
    equal(#Mock.linked, 2); equal(Mock.linked[2], link(STEW_RECIPE))
    equal(ns.cdb.hidden and ns.cdb.hidden[WESTFALL_STEW], nil, "a Shift-right-click hid the recipe")
    -- no chat line open: one is opened with the link
    state.chatOpen = false
    frameOf("Westfall Stew"):Click("LeftButton")
    equal(#Mock.linked, 2); equal(#Mock.chatOpened, 1); equal(Mock.chatOpened[1], link(STEW_ITEM))

    -- a recipe a trainer teaches has no recipe item: said, nothing linked
    state.chatOpen = true
    Mock.printed = {}
    frameOf("Charred Wolf Meat"):Click("RightButton")
    equal(#Mock.linked, 2)
    check(printed("Charred Wolf Meat has no recipe item to link"), table.concat(Mock.printed, "\n"))
    equal(ns.cdb.hidden and ns.cdb.hidden[CHARRED_WOLF], nil)
    -- an item the client has not loaded yet: asked for, said, nothing linked
    state.uncached[STEW_ITEM] = true
    Mock.printed = {}
    frameOf("Westfall Stew"):Click("LeftButton")
    equal(#Mock.linked, 2); equal(Mock.loadAsked[#Mock.loadAsked], STEW_ITEM)
    check(printed("the game has not loaded that item yet - click again in a moment"), table.concat(Mock.printed, "\n"))
    state.uncached[STEW_ITEM] = nil

    -- an enchant makes no item: its spell is linked
    ns.Window.widgets.tabs.enchanting:Click()
    frameOf("Enchant Bracer - Minor Deflect"):Click("LeftButton")
    equal(Mock.linked[3], "|cff71d5ff|Hspell:7428|h[spell 7428]|h|r")

    -- without Shift nothing changes: a click opens, a right-click hides
    state.shift = false
    ns.Window.widgets.tabs.cooking:Click()
    frameOf("Westfall Stew"):Click("LeftButton")
    check(ns.Window.open[WESTFALL_STEW], "a plain click no longer opens the card")
    equal(#Mock.linked, 3)
    frameOf("Westfall Stew"):Click("RightButton")
    check(ns.cdb.hidden[WESTFALL_STEW], "a plain right-click no longer hides the recipe")
    -- a client without the chat functions: no error, and it says so
    state.shift = true
    _G.ChatEdit_InsertLink, _G.ChatFrame_OpenChat = nil, nil
    Mock.printed = {}
    frameOf("Charred Wolf Meat"):Click("LeftButton")
    check(printed("could not put a link into chat"), table.concat(Mock.printed, "\n"))
end)

scenario("the coloured bags have the slots and cost the cloth the game gives them now", function()
    -- the user, 2026-11-15: "recipes says green/black silk packs are 10 slots but they are actually 12 now"
    -- (the pages saved on 2026-11-10 were from before the change; saved again, with five bags different)
    local ns = start({ faction = "Alliance" })
    local wanted = {
        ["Green Woolen Bag"] = { "10 Slot Bag", 5 }, ["Red Woolen Bag"] = { "10 Slot Bag", 5 },
        ["Small Silk Pack"] = { "10 Slot Bag", 3 },
        ["Green Silk Pack"] = { "12 Slot Bag", 5 }, ["Black Silk Pack"] = { "12 Slot Bag", 6 },
        ["Mageweave Bag"] = { "12 Slot Bag", 4 }, ["Red Mageweave Bag"] = { "14 Slot Bag", 5 },
    }
    local seen = 0
    for _, recipe in ipairs(ns.Lookup.Recipes("tailoring")) do
        local want = wanted[recipe.name]
        if want then
            seen = seen + 1
            equal(recipe.kind, want[1], recipe.name)
            equal(recipe.reagents[1][2], want[2], recipe.name .. ": bolts of cloth")
        end
    end
    equal(seen, 7)
    Mock.slash("show all")
    ns.Window.widgets.tabs.tailoring:Click()
    cardNamed(ns, "Green Silk Pack").click()
    check(has(Mock.rows(), "12 Slot Bag"), table.concat(Mock.rows(), "\n", 1, 10))
end)

scenario("a recipe of the other faction that was learned anyway is in the list", function()
    local ns = start({ faction = "Horde" }, function(state)
        state.skills[TAILORING] = { level = 150, max = 150 }
        state.learned[BRIGHT_YELLOW_SHIRT] = true
    end)
    Mock.slash("show known")
    ns.Window.widgets.tabs.tailoring:Click()
    local index = Mock.rowIndex("Bright Yellow Shirt")
    check(index, "a learned recipe is hidden")
    Mock.clickRow(index)
    check(has(Mock.rows(), "other faction"))
    check(Mock.info():find("1 of ", 1, true), Mock.info())
end)

scenario("a recipe one faction's vendor sells and creatures drop is in the other faction's list, by its drop", function()
    -- the user, 2026-11-15: "when i'm on my alt, i cannot find the red whelp gloves recipe from the LW tab"
    -- (a Horde alt: the pages name the Alliance's vendor alone; Wowhead's Forever item page has the drop too)
    local ns = start({ faction = "Horde" }, function(state)
        state.skills[LEATHERWORKING] = { level = 150, max = 150 }
    end)
    Mock.slash("show all")
    ns.Window.widgets.tabs.leatherworking:Click()
    local card = cardNamed(ns, "Red Whelp Gloves")
    equal(Mock.plain(card.right), "Drop: Dragonmaw Scout, Wetlands, 0.81%")
    card.click()
    local rows = Mock.rows()
    check(has(rows, "Drop: Dragonmaw Scout (19-20), Wetlands | 0.81%"), table.concat(rows, "\n", 1, 12))
    check(not has(rows, "Wenna Silkbeard"), "the Alliance's vendor is shown to the Horde")
    check(not has(rows, "as in Classic"), "a drop counted on Forever reads as a Classic one")
    -- the Alliance has the vendor and the drop
    ns = start({ faction = "Alliance" }, function(state)
        state.skills[LEATHERWORKING] = { level = 150, max = 150 }
    end)
    Mock.slash("show all")
    ns.Window.widgets.tabs.leatherworking:Click()
    card = cardNamed(ns, "Red Whelp Gloves")
    equal(Mock.plain(card.right), "Vendor: Wenna Silkbeard, Wetlands  (+1 more)")
    -- the four the item pages had a drop for: none of them is the other faction's alone any more
    local wanted = { ["Red Whelp Gloves"] = "H", ["Herbalist's Gloves"] = "H", ["Raptor Hide Belt"] = "H", ["Enchant Chest - Lesser Intellect"] = "A" }
    local seen = 0
    for _, key in ipairs({ "leatherworking", "enchanting" }) do
        for _, recipe in ipairs(ns.Lookup.Recipes(key)) do
            local side = wanted[recipe.name]
            if side then
                seen = seen + 1
                local sources = ns.Lookup.Sources(recipe, side)
                check(not sources.otherSide and sources.any and #sources.drops == 1, recipe.name .. " is still hidden from " .. side)
            end
        end
    end
    equal(seen, 4)
end)

scenario("a recipe opens onto its trainer, vendors with prices, quests and drops", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 100, max = 150 }
    end)
    ns.Window:Show()
    Mock.clickRow(Mock.rowIndex("Westfall Stew"))
    local rows = Mock.rows()
    check(has(rows, "Vendor: Kendor Kabonka, Stormwind City | 2s"), table.concat(rows, "\n", 1, 12))
    check(has(rows, "Quest: Westfall Stew | level 13"))
    check(has(rows, "Cooking 75 to learn; it gives skill until"))
    check(has(rows, "You have 100"))
    Mock.clickRow(Mock.rowIndex("Westfall Stew")) -- and closes again
    check(not has(Mock.rows(), "Quest: Westfall Stew | level 13"))

    Mock.clickRow(Mock.rowIndex("Charred Wolf Meat"))
    check(has(Mock.rows(), "It comes by itself with Cooking: nothing to buy or find. | automatic"))
    Mock.clickRow(Mock.rowIndex("Spiced Wolf Meat"))
    check(has(Mock.rows(), "Any Cooking trainer teaches it."))
    Mock.clickRow(Mock.rowIndex("Peace Tea"))
    check(has(Mock.rows(), "Drop: Frostmane Seer, Dun Morogh | 7.29%"))
    Mock.clickRow(Mock.rowIndex("Venomous Smoothie"))
    check(has(Mock.rows(), "Vendor: Kalsey Sanden, Redridge Mountains | 30 Merchant's Favor"))
    Mock.clickRow(Mock.rowIndex("Goldthorn Tea"))
    check(has(Mock.rows(), "Taught by Henry Stern, Razorfen Downs."))
    check(has(Mock.rows(), "not confirmed for Forever"))
    equal(ns.Window.Money(12345), "1g 23s 45c"); equal(ns.Window.Money(0), "0c"); equal(ns.Window.Money(nil), nil)
end)

scenario("a card's third line says known, or the first source: gold when learnable now, grey when not yet, red when unknown", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 100, max = 150 }
        state.learned[CHARRED_WOLF] = true
    end)
    Mock.slash("show all")
    check(cardNamed(ns, "Charred Wolf Meat").right:find("|cff60ff60Known", 1, true), "known is green")
    local stew = cardNamed(ns, "Westfall Stew").right
    check(stew:find("|cffffd100Vendor: Kendor Kabonka, Stormwind City, 2s  (+1 more)", 1, true), "skill 100 can learn a 75 recipe: gold, " .. stew)
    check(cardNamed(ns, "Flank au Poivre").right:find("|cffff8080Source unknown", 1, true), "an unknown source is red")
    check(cardNamed(ns, "Monster Omelet").right:find("|cff9d9d9d", 1, true), "skill 100 cannot learn a 225 recipe: grey")
    check(Mock.info():find("Purr Gola: 1 of ", 1, true) and Mock.info():find("Cooking 100/150", 1, true), Mock.info())
end)

scenario("each recipe is a card with icon, description and skill; an opened card grows and pushes the rest down", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 100, max = 150 }
        state.learned[CHARRED_WOLF] = true
    end)
    Mock.slash("show all")
    local cards = Mock.cards()
    check(#cards > 80, "one card per recipe: " .. #cards)
    equal(cards[1].y, 0); equal(cards[1].height, 58); equal(cards[2].y, 60)
    local _, stewIndex = cardNamed(ns, "Westfall Stew")
    local stew = cards[stewIndex].frame
    equal(stew.icon.__texture, "Interface\\Icons\\inv_misc_bowl_01")
    check(Mock.plain(stew.effect:GetText()) ~= "", "the description line")
    equal(Mock.plain(stew.skill:GetText()), "75"); equal(Mock.plain(stew.skillLabel:GetText()), "Cooking")
    check(Mock.plain(stew.source:GetText()):find("Vendor: Kendor Kabonka", 1, true))
    equal(stew.__border[2], 0.82, "learnable now: a gold rim")
    local _, wolfIndex = cardNamed(ns, "Charred Wolf Meat")
    equal(cards[wolfIndex].frame.__border[2], 0.85, "known: a green rim")

    local below = cards[stewIndex + 1].y
    stew:Click()
    cards = Mock.cards()
    check(cards[stewIndex].height > 58 + 3 * 14, "an opened card is taller: " .. cards[stewIndex].height)
    equal(cards[stewIndex + 1].y, below + cards[stewIndex].height - 58, "the next card moves down by what the open one grew")
    local vendorLine
    for _, d in ipairs(stew.details) do
        if d.left:IsShown() and Mock.plain(d.left:GetText()):find("Vendor: Kendor Kabonka, Stormwind City", 1, true) then vendorLine = d end
    end
    check(vendorLine, "the vendor's line is not on the opened card")
    equal(Mock.plain(vendorLine.right:GetText()), "2s")
    stew:Click()
    cards = Mock.cards()
    equal(cards[stewIndex].height, 58); equal(cards[stewIndex + 1].y, below)
    check(not stew.details[2].left:IsShown(), "a closed card still shows its lines")
    -- nothing to list: a note, no cards
    ns.Window.widgets.search:SetText("zzz")
    equal(#Mock.cards(), 0)
    check(ns.Window.widgets.note:IsShown() and Mock.plain(ns.Window.widgets.note:GetText()):find("Nothing matches", 1, true))
    ns.Window.widgets.search:SetText("")
    check(not ns.Window.widgets.note:IsShown())
end)

scenario("an opened card replaces its summary lines: nothing is said twice, and stats are a line each", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 0, max = 0 }
        state.skills[BLACKSMITHING] = { level = 300, max = 300 }
        state.learned[SHARPENING_STONE] = true
    end)
    Mock.slash("show all")
    local entry, index = cardNamed(ns, "Dawnbringer Shoulders")
    local card = Mock.cards()[index].frame
    -- closed: one line of what it is and gives, one line of where it comes from
    check(card.effect:IsShown() and card.source:IsShown() and not card.hideButton:IsShown())
    equal(Mock.plain(card.effect:GetText()), "Plate shoulder, level 53 - +10 Spirit, +44 Healing, +15 Spell Damage")
    check(Mock.plain(card.source:GetText()):find("Drop: Hive'Zora Tunneler", 1, true) == 1, Mock.plain(card.source:GetText()))
    card:Click()
    entry = cardNamed(ns, "Dawnbringer Shoulders")
    -- open: the two summary lines are gone, the same things are below in full
    check(not card.effect:IsShown() and not card.source:IsShown(), "the summary lines stay on an opened card")
    local texts = {}
    for _, d in ipairs(entry.details) do
        texts[#texts + 1] = Mock.plain(d.text)
    end
    equal(texts[1], "Plate shoulder, level 53")
    equal(texts[2], "+10 Spirit"); equal(texts[3], "+44 Healing"); equal(texts[4], "+15 Spell Damage")
    for _, line in ipairs(texts) do
        check(not line:find("+10 Spirit, +44 Healing", 1, true), "the one-line description is repeated on the opened card: " .. line)
    end
    local dropLines = 0
    for _, line in ipairs(texts) do
        if line:find("Hive'Zora Tunneler", 1, true) then dropLines = dropLines + 1 end
    end
    equal(dropLines, 1, "the first source is said once")
    -- the first detail line sits where the description was
    local _, _, _, _, y = card.details[1].left:GetPoint(1)
    equal(y, -26)
    -- a known recipe says so on its opened card, where its "Known" line was
    cardNamed(ns, "Rough Sharpening Stone").click()
    equal(Mock.plain(cardNamed(ns, "Rough Sharpening Stone").details[1].text), "You know this recipe.")
    -- closing brings the summary back
    card:Click()
    check(card.effect:IsShown() and card.source:IsShown())
    -- food: its one effect is one line
    ns = start({ faction = "Alliance" })
    Mock.slash("show all")
    cardNamed(ns, "Westfall Stew").click()
    equal(Mock.plain(cardNamed(ns, "Westfall Stew").details[1].text), "Well fed: 15% movement speed while in Westfall")
end)

scenario("an opened card lists the reagents, how many of each you have, and how many crafts that is", function()
    local STRINGY, EYE, SNOUT = 729, 730, 731
    local ns, state = start({ faction = "Alliance" }, function(s)
        s.items[STRINGY], s.items[EYE] = 5, 2
    end)
    Mock.slash("show all")
    local reagents = ns.Lookup.Reagents(ns.Lookup.BySpell(WESTFALL_STEW))
    equal(#reagents, 3); equal(reagents[1].name, "Stringy Vulture Meat"); equal(reagents[1].count, 1); equal(reagents[1].icon, "inv_misc_food_16")
    cardNamed(ns, "Westfall Stew").click()
    local rows = Mock.rows()
    check(has(rows, "Reagents | not enough"), table.concat(rows, "\n", 1, 14))
    check(has(rows, "Stringy Vulture Meat | have 5/1"))
    check(has(rows, "Murloc Eye | have 2/1"))
    check(has(rows, "Goretusk Snout | have 0/1") and not has(rows, "1 x Goretusk Snout"))
    -- the reagent lines carry the item's icon, and green or red for enough or not
    local raw = Mock.rawRows()
    local function rawRow(words)
        for _, line in ipairs(raw) do
            if Mock.plain(line):find(words, 1, true) then return line end
        end
        error("no row " .. words)
    end
    check(rawRow("Stringy Vulture Meat"):find("|TInterface\\Icons\\inv_misc_food_16", 1, true), rawRow("Stringy Vulture Meat"))
    check(rawRow("Stringy Vulture Meat"):find("|cff60ff60have 5/1", 1, true) and rawRow("Goretusk Snout"):find("|cffff8080have 0/1", 1, true))
    -- the reagents come after what the dish gives and before where the recipe comes from
    local order = {}
    for index, row in ipairs(rows) do
        for _, words in ipairs({ "Well fed", "Reagents", "Cooking 75 to learn", "Stormwind City | 2s" }) do
            if row:find(words, 1, true) and not order[words] then order[words] = index end
        end
    end
    check(order["Well fed"] < order["Reagents"] and order["Reagents"] < order["Cooking 75 to learn"] and order["Cooking 75 to learn"] < order["Stormwind City | 2s"])
    -- the right-hand words end where the name's tags end: clear of the skill number and the card's edge
    local _, stewIndex = cardNamed(ns, "Westfall Stew")
    local stewCard = Mock.cards()[stewIndex].frame
    local _, _, _, tagsX = stewCard.tags:GetPoint(1)
    local _, _, _, rightX = stewCard.details[2].right:GetPoint(1)
    equal(rightX, tagsX); equal(rightX, -76)
    -- with the last reagent in the bags: enough for two
    state.items[SNOUT] = 3
    ns.Window:Render()
    check(has(Mock.rows(), "Reagents | enough for 2"), table.concat(Mock.rows(), "\n", 1, 14))
    -- a craft that gives several says for how many; a camp recipe names its camp object
    local several, station
    for _, key in ipairs(KEYS) do
        for _, recipe in ipairs(ns.Lookup.Recipes(key)) do
            local mine = key == "cooking" and not ns.Lookup.Sources(recipe, "A").otherSide
            if not several and mine and (recipe.makes or 1) > 1 and recipe.reagents then several = recipe end
            if not station and mine and recipe.station then station = recipe end
        end
    end
    ns.Window.open = { [several.spell] = true, [station.spell] = true }
    ns.Window:Render()
    check(has(Mock.rows(), "Reagents  for " .. several.makes), "a craft of several does not say so")
    check(has(Mock.rows(), "Made at a camp with: " .. ns.Lookup.ItemName(station.station)))
    -- the client silent about the bags: the list without counts, no error
    state.bagsSecret = true
    ns.Window.open = { [WESTFALL_STEW] = true }
    ns.Window:Render()
    rows = Mock.rows()
    check(has(rows, "1 x Stringy Vulture Meat") and not has(rows, "| have "), "a secret count was shown")
    state.bagsSecret = nil
    -- another character's card: its bags are not this character's
    ns = start({ db = AKForeverRecipesDB, first = "Alt", last = "Two", faction = "Alliance" }, function(s)
        s.items[STRINGY] = 9
    end)
    Mock.slash("show all")
    ns.Window.widgets.character:Click()
    cardNamed(ns, "Westfall Stew").click()
    check(has(Mock.rows(), "1 x Stringy Vulture Meat") and not has(Mock.rows(), "have 9"), "your bags are counted for another character's recipes")
    -- the search finds recipes by what they are made of
    ns.Window.open = {}
    ns.Window.widgets.search:SetText("murloc eye")
    rows = Mock.rows()
    check(#rows >= 1 and #rows < 10 and has(rows, "Westfall Stew"), "a reagent search: " .. #rows)
    -- every reagent of every recipe has a count, and nearly all a name
    local total, unnamed = 0, 0
    for _, key in ipairs(KEYS) do
        for _, recipe in ipairs(ns.Lookup.Recipes(key)) do
            for _, reagent in ipairs(ns.Lookup.Reagents(recipe)) do
                total = total + 1
                check(type(reagent.count) == "number" and reagent.count > 0, recipe.name .. ": a reagent without a count")
                if reagent.name:find("^item %d") then unnamed = unnamed + 1 end
            end
        end
    end
    check(total > 5000 and unnamed <= 5, total .. " reagents, " .. unnamed .. " without a name")
end)

scenario("a right-click or the Hide button hides a recipe from the lists and counts; the Hidden list brings it back", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.learned[CHARRED_WOLF] = true
    end)
    ns.Window:Show()
    local total = tonumber(Mock.info():match("of (%d+) Cooking"))
    check(Mock.info():find("right-click hides", 1, true) and not Mock.info():find("hidden", 1, true), Mock.info())
    local _, index = cardNamed(ns, "Westfall Stew")
    Mock.cards()[index].frame:Click("RightButton")
    check(not Mock.rowIndex("Westfall Stew"), "a hidden recipe is still listed as missing")
    equal(tonumber(Mock.info():match("of (%d+) Cooking")), total - 1, "a hidden recipe still counts")
    check(Mock.info():find("1 hidden", 1, true), Mock.info())
    check(ns.cdb.hidden[WESTFALL_STEW])
    -- not in All either, nor in a search
    ns.Window.widgets.filters.all:Click()
    check(not Mock.rowIndex("Westfall Stew"))
    ns.Window.widgets.search:SetText("westfall stew")
    check(has(Mock.rows(), "Nothing matches"))
    ns.Window.widgets.search:SetText("")
    -- the Hide button of an opened card does the same, for a known recipe too
    local wolf, wolfIndex = cardNamed(ns, "Charred Wolf Meat")
    wolf.click()
    local frame = Mock.cards()[wolfIndex].frame
    check(frame.hideButton:IsShown()); equal(frame.hideButton:GetText(), "Hide")
    frame.hideButton:Click()
    check(not Mock.rowIndex("Charred Wolf Meat"))
    check(Mock.info():find("Purr Gola: 0 of ", 1, true) and Mock.info():find("2 hidden", 1, true), Mock.info())
    -- the Hidden list: the two, and nothing else
    ns.Window.widgets.filters.hidden:Click()
    equal(#Mock.cards(), 2)
    local stew, stewIndex = cardNamed(ns, "Westfall Stew")
    stew.click()
    frame = Mock.cards()[stewIndex].frame
    equal(frame.hideButton:GetText(), "Show again")
    frame.hideButton:Click()
    equal(#Mock.cards(), 1); equal(ns.cdb.hidden[WESTFALL_STEW], nil)
    _, index = cardNamed(ns, "Charred Wolf Meat")
    Mock.cards()[index].frame:Click("RightButton") -- a right-click in the Hidden list brings it back
    equal(#Mock.cards(), 0)
    check(has(Mock.rows(), "Nothing is hidden."))
    ns.Window.widgets.filters.missing:Click()
    check(Mock.rowIndex("Westfall Stew"))
    equal(tonumber(Mock.info():match("of (%d+) Cooking")), total)
    -- hidden is the character's own and is remembered
    _, index = cardNamed(ns, "Westfall Stew")
    Mock.cards()[index].frame:Click("RightButton")
    ns = start({ db = AKForeverRecipesDB, faction = "Alliance" })
    ns.Window:Show()
    check(not Mock.rowIndex("Westfall Stew"), "what was hidden came back the next session")
    ns = start({ db = AKForeverRecipesDB, first = "Alt", last = "Two", faction = "Alliance" })
    ns.Window:Show()
    check(Mock.rowIndex("Westfall Stew"), "one character's hidden recipe is hidden for another")
end)

scenario("hovering a card shows the made item's tooltip in our own tooltip frame, an enchant's spell", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skills[333] = { level = 100, max = 150 }
    end)
    Mock.slash("show all")
    ns.Window.widgets.tabs.cooking:Click()
    local _, index = cardNamed(ns, "Westfall Stew")
    local card = Mock.cards()[index].frame
    equal(_G.GameTooltip, nil, "the test client has no GameTooltip: the addon must not need Blizzard's")
    card:Enter()
    local tip = ns.Window.tooltip
    check(tip and tip.__name == "AKForeverRecipesTooltip")
    equal(tip.__tip, "item:733"); equal(tip.__owner, card); equal(tip.__anchor, "ANCHOR_RIGHT"); check(tip:IsShown())
    card:Leave()
    check(not tip:IsShown())
    -- an enchant makes no item
    ns.Window.widgets.tabs.enchanting:Click()
    _, index = cardNamed(ns, "Enchant Bracer - Minor Deflect")
    Mock.cards()[index].frame:Enter()
    equal(tip.__tip, "spell:7428")
    -- closing the window takes the tooltip with it
    ns.Window:Close()
    check(not tip:IsShown())
end)

scenario("a card's tags say the kind of source and whether the recipe item is BoP or BoE", function()
    local ns = start({ faction = "Alliance" })
    Mock.slash("show all")
    local function tags(name)
        local entry = cardNamed(ns, name)
        return Mock.plain(entry.tags), entry.tags
    end
    equal(tags("Westfall Stew"), "Vendor  Quest   BoE")      -- sold and a quest reward, the item does not bind
    equal(tags("Charred Wolf Meat"), "Automatic")            -- it comes with the skill
    equal(tags("Spiced Wolf Meat"), "Trainer")               -- no recipe item: nothing binds
    equal(tags("Peace Tea"), "Drop   BoP")
    equal(tags("Venomous Smoothie"), "Vendor   BoP")
    equal(tags("Goldthorn Tea"), "Taught")
    equal(tags("Flank au Poivre"), "BoP")                 -- no source known, but the item is
    equal(tags("Kaldorei Spider Kabob"), "Quest   BoE")
    local _, raw = tags("Peace Tea")
    check(raw:find("|cffff6060BoP", 1, true) and raw:find("|cffc79cffDrop", 1, true), "the tags have their colours")
    equal(ns.Lookup.Bind(ns.Lookup.BySpell(WESTFALL_STEW)), "boe"); equal(ns.Lookup.Bind(ns.Lookup.BySpell(CHARRED_WOLF)), nil)
    equal(ns.Lookup.Bind({ recipe = { id = 1, name = "x", bind = "?" } }), nil, "an item nobody knows the binding of gets no tag")
    -- on the card itself, and in the opened card in words
    local _, index = cardNamed(ns, "Peace Tea")
    local card = Mock.cards()[index].frame
    equal(Mock.plain(card.tags:GetText()), "Drop   BoP")
    card:Click()
    check(has(Mock.rows(), "Recipe: Peace Tea binds when picked up - the character that gets it has to be the cook. | BoP"), table.concat(Mock.rows(), "\n", 1, 12))
    Mock.clickRow(Mock.rowIndex("Westfall Stew"))
    check(has(Mock.rows(), "Recipe: Westfall Stew does not bind - it can be mailed, traded or auctioned. | BoE"))
    -- the tags' own words search: every BoP recipe, every quest reward
    local bop, matched = 0, 0
    for _, recipe in ipairs(ns.Lookup.Recipes("cooking")) do
        if recipe.recipe and recipe.recipe.bop then bop = bop + 1 end
    end
    equal(bop, 46)
    ns.Window.open = {}
    ns.Window.widgets.search:SetText("bop")
    for _, row in ipairs(Mock.rows()) do
        check(row:find("BoP]", 1, true), "a card without the BoP tag matched 'bop': " .. row)
        matched = matched + 1
    end
    check(matched > 20 and matched <= 46, "the BoP recipes this faction can get: " .. matched)
    ns.Window.widgets.search:SetText("quest")
    check(#Mock.rows() >= 8)
    for _, row in ipairs(Mock.rows()) do
        check(row:find("Quest", 1, true), "a card with no quest matched 'quest': " .. row)
    end
end)

scenario("Missing, All and Known choose the list, the choice is remembered, and the search narrows it", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.learned[CHARRED_WOLF] = true
    end)
    ns.Window:Show()
    equal(ns:GetOption("filter"), "missing")
    check(not Mock.rowIndex("Charred Wolf Meat") and Mock.rowIndex("Westfall Stew"))
    ns.Window.widgets.filters.known:Click()
    equal(#Mock.cards(), 2); check(Mock.rowIndex("Charred Wolf Meat")) -- the training card and the one known recipe
    check(not ns.Window.widgets.filters.known:IsEnabled() and ns.Window.widgets.filters.all:IsEnabled())
    ns.Window.widgets.filters.all:Click()
    check(Mock.rowIndex("Charred Wolf Meat") and Mock.rowIndex("Westfall Stew"))
    equal(ns.cdb.options.filter, "all")

    ns.Window.widgets.search:SetText("stormwind")
    local rows = Mock.rows()
    check(#rows > 3 and #rows < 40, "a place search should narrow the list: " .. #rows)
    check(has(rows, "Westfall Stew") and not has(rows, "Charred Wolf Meat"))
    ns.Window.widgets.search:SetText("kendor")
    check(has(Mock.rows(), "Westfall Stew"))
    ns.Window.widgets.search:SetText("zzz")
    check(has(Mock.rows(), "Nothing matches"))
    ns.Window.widgets.search:SetText("")
    check(#Mock.rows() > 80)
end)

scenario("every character's recipes are kept and can be read from another character", function()
    start({ first = "Purr", last = "Gola", faction = "Alliance" }, function(state)
        state.learned[WESTFALL_STEW] = true
        state.learned[SHARPENING_STONE] = true
        state.skill = { level = 120, max = 150 }
        state.skills[BLACKSMITHING] = { level = 60, max = 75 }
    end)
    -- a character without a profession in between: it is not offered
    start({ db = AKForeverRecipesDB, first = "No", last = "Craft", faction = "Alliance" }, function(state)
        state.skill = { level = 0, max = 0 }
    end)
    local ns = start({ db = AKForeverRecipesDB, first = "Alt", last = "Two", faction = "Alliance" }, function(state)
        state.learned[CHARRED_WOLF] = true
        state.skill = { level = 40, max = 75 }
    end)
    equal(ns.characterKey, "Alt Two - ClassicBetaPvE")
    local characters = ns.Known:Characters()
    equal(#characters, 2); equal(characters[1], "Alt Two - ClassicBetaPvE"); equal(characters[2], "Purr Gola - ClassicBetaPvE")
    check(ns.Known:IsLearned(WESTFALL_STEW, "Purr Gola - ClassicBetaPvE") and not ns.Known:IsLearned(WESTFALL_STEW))

    Mock.slash("show all")
    check(ns.Window.widgets.character:IsShown())
    equal(ns.Window.widgets.tabs.blacksmithing:GetText(), "|cff808080BS|r", "a profession the alt lacks is dimmed")
    Mock.clickRow(Mock.rowIndex("Westfall Stew"))
    check(has(Mock.rows(), "Also known by: Purr Gola"))
    Mock.clickRow(Mock.rowIndex("Charred Wolf Meat"))
    check(has(Mock.rows(), "Also missing on: Purr Gola"))

    ns.Window.widgets.character:Click() -- on to Purr Gola: its tabs, still on Cooking
    equal(ns.Window.widgets.tabs.blacksmithing:GetText(), "BS"); equal(ns.Window.widgets.tabs.cooking:GetText(), "Cook")
    check(Mock.info():find("Purr Gola: 1 of ", 1, true) and Mock.info():find("Cooking 120/150", 1, true), Mock.info())
    equal(ns.Window.widgets.character:GetText(), "Purr Gola")
    check(Mock.plain(cardNamed(ns, "Westfall Stew").right) == "Known")
    ns.Window.widgets.tabs.blacksmithing:Click() -- the smith's other profession, from the alt
    check(Mock.info():find("Blacksmithing 60/75", 1, true), Mock.info())
    check(Mock.plain(cardNamed(ns, "Rough Sharpening Stone").right) == "Known")
    equal(ns.cdb.options.prof, nil, "looking at another character's profession does not change where your own window opens")
    -- a smith's recipe names no cook as "missing"
    Mock.clickRow(Mock.rowIndex("Rough Sharpening Stone"))
    check(not has(Mock.rows(), "Also missing on"), "a character without the profession is called missing the recipe")
    ns.Window.widgets.character:Click() -- round to the character logged in: the same profession, which it lacks
    check(Mock.info():find("Alt Two: 0 of %d+ Blacksmithing recipes known") and Mock.info():find("does not have Blacksmithing", 1, true), Mock.info())
    ns.Window.widgets.tabs.cooking:Click()
    check(Mock.info():find("Alt Two: 1 of %d+ Cooking recipes known"), Mock.info())
    -- alone, there is nobody to walk to
    ns = start()
    ns.Window:Show()
    check(not ns.Window.widgets.character:IsShown())
end)

scenario("a merchant selling a recipe nobody had a source for is written down for every character", function()
    local ns = start({ faction = "Alliance" })
    local ribs = ns.Lookup.BySpell(FLANK_AU_POIVRE)
    check(ns.Lookup.Sources(ribs, "A").unknown)
    ns.Window:Show()
    Mock.clickRow(Mock.rowIndex("Flank au Poivre"))
    check(has(Mock.rows(), "Nobody has written down yet where this comes from."))
    check(has(Mock.rows(), "A merchant selling Recipe: Flank au Poivre is noted"))

    Mock.merchant({ { id = 4540, price = 25 }, { id = FLANK_RECIPE, price = 12000 }, { secret = true } }, "Corporal Bluth", "Stranglethorn Vale")
    local rows = Mock.rows()
    check(has(rows, "Vendor: Corporal Bluth, Stranglethorn Vale  (seen by you) | 1g 20s"), table.concat(rows, "\n", 1, 20))
    check(not has(rows, "Nobody has written down"))
    equal(ns.db.vendors[FLANK_RECIPE]["Corporal Bluth"].side, "A")
    -- a vendor the table already names is not listed twice
    Mock.merchant({ { id = 728, price = 200 } }, "Kendor Kabonka", "Stormwind City")
    Mock.clickRow(Mock.rowIndex("Westfall Stew"))
    local count = 0
    for _, row in ipairs(Mock.rows()) do
        if row:find("Vendor: Kendor Kabonka", 1, true) == 1 then count = count + 1 end
    end
    equal(count, 1)
    -- the next session, another character of the same faction
    ns = start({ db = AKForeverRecipesDB, first = "Alt", last = "Two", faction = "Alliance" })
    equal(ns.Lookup.Summary(ns.Lookup.BySpell(FLANK_AU_POIVRE), "A"), "vendor: Stranglethorn Vale")
    check(not ns.Lookup.Sources(ns.Lookup.BySpell(FLANK_AU_POIVRE), "H").any, "an Alliance vendor is offered to the Horde")
end)

scenario("'/akr find' searches every profession and prints where the recipes come from", function()
    start({ faction = "Alliance" }, function(state)
        state.learned[WESTFALL_STEW] = true
    end)
    Mock.slash("find westfall stew")
    check(printed("Westfall Stew (Cooking 75, known, BoE): Kendor Kabonka, Stormwind City 2s; quest Westfall Stew."), table.concat(Mock.printed, "\n"))
    Mock.slash("find charred")
    check(printed("Charred Wolf Meat (Cooking 1, missing): comes with Cooking."), table.concat(Mock.printed, "\n"))
    Mock.slash("find spiced wolf")
    check(printed("Spiced Wolf Meat (Cooking 10, missing): any Cooking trainer."), table.concat(Mock.printed, "\n"))
    Mock.slash("find copper chain vest") -- a profession this character does not have
    check(printed("Copper Chain Vest (Blacksmithing 30, missing, BoE): quest Supplying the Front;") and printed("; world drop, creatures of level 5-25."), table.concat(Mock.printed, "\n"))
    Mock.slash("find nothing-like-this")
    check(printed("nothing in the tables by that name."))
    Mock.slash("find")
    check(printed("usage: /akr find"))
end)

scenario("'/akr' opens and closes the window and its place is remembered", function()
    local ns = start()
    Mock.slash("")
    check(ns.Window.window:IsShown())
    ns.Window.window:ClearAllPoints()
    ns.Window.window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -50)
    ns.Window.window:GetScript("OnDragStop")(ns.Window.window)
    equal(ns.cdb.options.window.x, 40); equal(ns.cdb.options.window.y, -50)
    Mock.slash("")
    check(not ns.Window.window:IsShown())
    ns = start({ db = AKForeverRecipesDB })
    Mock.slash("")
    local point, _, _, x, y = ns.Window.window:GetPoint(1)
    equal(point, "TOPLEFT"); equal(x, 40); equal(y, -50)
end)

scenario("the saved file of the cooking-only build is read: its one skill becomes Cooking's", function()
    local old = { schema = 1, loads = 3, vendors = {}, chars = {
        ["Purr Gola - ClassicBetaPvE"] = { options = { filter = "all" }, learned = { [WESTFALL_STEW] = 1700000000 }, skill = 150, skillMax = 225, side = "A" },
        ["Old Alt - ClassicBetaPvE"] = { options = {}, learned = { [CHARRED_WOLF] = 1700000000 }, skill = 60, skillMax = 75, side = "A" },
        ["No Cook - ClassicBetaPvE"] = { options = {}, learned = {} },
    } }
    local ns = start({ db = old }, function(state)
        state.skill = { secret = true } -- the client says nothing new this session
        state.infoMode, state.spellMode = "nil", "false"
    end)
    equal(ns.db.schema, 2)
    local skill, max = ns.Known:Skill(ns.cdb, "cooking")
    equal(skill, 150); equal(max, 225); equal(ns.cdb.skill, nil)
    check(ns.Known:Has(ns.cdb, "cooking") and ns.Known:IsLearned(WESTFALL_STEW))
    ns.Window:Show()
    check(Mock.info():find("Purr Gola: 1 of ", 1, true) and Mock.info():find("Cooking 150/225", 1, true), Mock.info())
    equal(ns:GetOption("filter"), "all")
    -- the alts of that file too, before they log in again
    equal(#ns.Known:Characters(), 2)
    ns.Window.widgets.character:Click()
    check(Mock.info():find("Old Alt: 1 of ", 1, true) and Mock.info():find("Cooking 60/75", 1, true), Mock.info())
end)

scenario("the report says which way the client answered and holds no secret", function()
    start(nil, function(state)
        state.learned[WESTFALL_STEW] = true
        state.skill = { level = 80, max = 150 }
    end)
    Mock.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "UNKNOWN()")
    Mock.slash("diag")
    local diag = AKForeverRecipesDB.diag
    check(diag and diag.asked)
    equal(diag.known.lastScan.infoLearned, 1); equal(diag.known.lastScan.spellLearned, 1); equal(diag.known.lastScan.skillLines, 9)
    equal(diag.client.tradeSkill.getRecipeInfo, true); equal(diag.client.faction, "Alliance")
    check(#diag.client.samples >= 3 and diag.client.samples[1].recipeInfo and diag.client.samples[1].prof == "cooking")
    equal(diag.known.chars["Purr Gola - ClassicBetaPvE"].skills.cooking.skill, 80)
    equal(diag.known.skillRaw.blacksmithing.line, 164); equal(diag.known.skillRaw.cooking.skill, 80)
    equal(diag.blockedActions[1].addon, "SomeOtherAddon"); equal(diag.blockedActions[1].ours, false)
    check(diag.data.recipes > 2000 and diag.data.built == 1 and diag.data.perProfession.cooking == 123)
    equal(diag.data.training, 9, "the report says whether the training table loaded")
    local function walk(value, path)
        check(value ~= Mock.SECRET, "a secret in the report at " .. path)
        if type(value) == "table" then
            for k, v in pairs(value) do
                walk(v, path .. "." .. tostring(k))
            end
        end
    end
    walk(AKForeverRecipesDB, "AKForeverRecipesDB")
    Mock.fire("PLAYER_LOGOUT")
    check(AKForeverRecipesDB.diagAtLogout, "the logout report goes beside the one asked for")
end)

scenario("one profile per character; the version is the packager's stamp, a working copy or a release tag", function()
    local ns = start()
    equal(ns.characterKey, "Purr Gola - ClassicBetaPvE")
    equal(ns.version, "0.1.0-test")
    ns = start({ version = "@project-version@" })
    equal(ns.version, "dev")
    ns = start({ version = "v0.1.0" })
    equal(ns.version, "0.1.0")
    Mock.slash("help")
    check(printed("commands:") and printed("/akr find") and printed("/akr diag"))
end)

------------------------------------------------------------------------
------------------------------------------------------------------------
-- The guild
------------------------------------------------------------------------
local GUILD = "Forever Friends"
local ME_A, ME_B = "Purr Gola - ClassicBetaPvE", "Thrall Smith - ClassicBetaPvE"

-- Purr Gola's client: a cook (Westfall Stew, Charred Wolf Meat) with a blacksmith alt; everything it says at
-- login and when asked for both characters. Gives back the texts it sent.
local function guildmateA(extra)
    local db = { schema = 2, chars = { ["Purr Smith - ClassicBetaPvE"] = {
        learned = { [SHARPENING_STONE] = 1 }, skills = { blacksmithing = { skill = 90, max = 150 } }, profs = { blacksmithing = true }, side = "A", options = {} } } }
    local ns = start({ guild = GUILD, db = db, roster = { { name = "Purr Gola", online = true } } }, function(state)
        state.learned[WESTFALL_STEW] = true
        state.learned[CHARRED_WOLF] = true
        for _, spell in ipairs(extra or {}) do state.learned[spell] = true end
        state.skill = { level = 120, max = 150 }
    end)
    Mock.advance(10)
    local hellos = Mock.sentTexts("H")
    for _, hello in ipairs(hellos) do
        local fp, key = hello:match("^H;1;([^;]+);(.+)$")
        Mock.hear("Q;" .. fp .. ";" .. key, "Thrall Smith")
    end
    Mock.advance(30)
    return Mock.sentTexts(), ns
end

local function guildmateB(roster)
    return start({ first = "Thrall", last = "Smith", guild = GUILD, roster = roster or {
        { name = "Thrall Smith", online = true }, { name = "Purr Gola", online = true } } })
end

scenario("guild: at login a roll call and a hello for each of your characters; asked, a character goes out to the guild in parts, each under 255 characters", function()
    local sent = guildmateA()
    equal(sent[1], "R;1", "a roll call first")
    local hellos, dumps = Mock.sentTexts("H"), Mock.sentTexts("D")
    equal(#hellos, 2, "the cook and the blacksmith alt")
    check(has(hellos, ";" .. ME_A) and has(hellos, ";Purr Smith - ClassicBetaPvE"))
    equal(#dumps, 4, "each character: its professions, then its recipes")
    check(has(dumps, ";1;2;" .. ME_A .. ";A,cooking:120:150"), table.concat(dumps, "\n"))
    -- paced: never two messages in the same second
    for index = 2, #Mock.sent do
        check(Mock.sent[index].at - Mock.sent[index - 1].at >= 1, "one message a second")
    end
    equal(Mock.state.prefix, "AKFR")
end)

scenario("guild: a guildmate's characters arrive - the card says who knows it, missing recipes are tagged Guild, the opened card lists them with skill and online", function()
    local sentA = guildmateA()
    local ns = guildmateB()
    Mock.advance(10)
    Mock.sent = {}
    for _, text in ipairs(sentA) do
        if text:sub(1, 2) == "H;" then Mock.hear(text, "Purr Gola") end
    end
    Mock.advance(5)
    equal(#Mock.sentTexts("Q"), 2, "both characters asked for")
    for _, text in ipairs(sentA) do
        if text:sub(1, 2) == "D;" then Mock.hear(text, "Purr Gola") end
    end
    equal(ns.Guild.stats.taken, 2); equal(ns.Guild.stats.badFingerprint, 0)
    ns.Window:Show()
    local stew = cardNamed(ns, "Westfall Stew")
    check(Mock.plain(stew.tags):find("^Guild"), "missing here, known in the guild: tagged Guild - " .. Mock.plain(stew.tags))
    equal(Mock.plain(stew.guild), "Guild: Purr Gola")
    stew.click()
    stew = cardNamed(ns, "Westfall Stew")
    local rows = Mock.rows()
    check(has(rows, "In your guild (1):"), table.concat(rows, "\n"))
    check(has(rows, "Purr Gola  Cooking 120 | online"), table.concat(rows, "\n"))
    -- the blacksmith alt, offline, on Purr Gola's account (nobody here smiths: its table is built on demand)
    ns.Lookup.BuildAll()
    local stone = ns.Guild:Who(ns.Lookup.BySpell(SHARPENING_STONE))
    equal(#stone, 1); equal(stone[1].name, "Purr Smith"); equal(ns.Guild.When(stone[1]), "online as Purr Gola")
    equal(stone[1].skill, 90)
    -- the same hello again: nothing asked
    Mock.sent = {}
    for _, text in ipairs(sentA) do
        if text:sub(1, 2) == "H;" then Mock.hear(text, "Purr Gola") end
    end
    Mock.advance(5)
    equal(#Mock.sentTexts("Q"), 0, "an unchanged character is not asked for again")
    -- remembered: a fresh login with the saved table still knows it, offline
    local saved = AKForeverRecipesDB
    ns = start({ first = "Thrall", last = "Smith", guild = GUILD, db = saved, roster = { { name = "Thrall Smith", online = true }, { name = "Purr Gola", online = false } } })
    Mock.fire("GUILD_ROSTER_UPDATE")
    local who = ns.Guild:Who(ns.Lookup.BySpell(WESTFALL_STEW))
    equal(#who, 1); check(ns.Guild.When(who[1]):find("^seen"), ns.Guild.When(who[1]))
    equal(#Mock.errors, 0)
end)

scenario("guild: more than three who know it - the card says how many, the opened card names them all", function()
    local sentA = guildmateA()
    local names = { "Aa Bee", "Cc Dee", "Ee Eff", "Gg Hh" }
    local roster = { { name = "Thrall Smith", online = true } }
    for _, name in ipairs(names) do roster[#roster + 1] = { name = name, online = false } end
    local ns = guildmateB(roster)
    for _, name in ipairs(names) do
        for _, text in ipairs(sentA) do
            if text:sub(1, 2) == "D;" and text:find(ME_A, 1, true) then
                Mock.hear((text:gsub(ME_A:gsub("%-", "%%-"), name .. " - ClassicBetaPvE")), name)
            end
        end
    end
    ns.Window:Show()
    local stew = cardNamed(ns, "Westfall Stew")
    equal(Mock.plain(stew.guild), "Guild: 4 can make this - open the card for who")
    stew.click()
    local rows = Mock.rows()
    check(has(rows, "In your guild (4):"))
    for _, name in ipairs(names) do
        check(has(rows, "   " .. name), name .. " listed")
    end
    -- three: names
    ns.Guild:Store()["Gg Hh - ClassicBetaPvE"] = nil
    ns:Fire("GUILD_CHANGED")
    ns.Window.open = {}
    ns.Window:Render()
    check(Mock.plain(cardNamed(ns, "Westfall Stew").guild):find("^Guild: %a+ %a+, %a+ %a+, %a+ %a+$"), Mock.plain(cardNamed(ns, "Westfall Stew").guild))
end)

scenario("guild: one request is enough - a request heard first is not sent again; a tampered or partial dump is not kept", function()
    local sentA = guildmateA()
    local ns = guildmateB()
    Mock.advance(10)
    Mock.sent = {}
    local hello = sentA[2]
    local fp, key = hello:match("^H;1;([^;]+);(.+)$")
    Mock.hear(hello, "Purr Gola")
    Mock.hear("Q;" .. fp .. ";" .. key, "Somebody Else") -- another guildmate asked before our wait was up
    Mock.advance(5)
    equal(#Mock.sentTexts("Q"), 0, "somebody asked already")
    -- the answer, with one recipe changed on the way: refused
    local dumps = {}
    for _, text in ipairs(sentA) do
        if text:sub(1, 2) == "D;" and text:find(";" .. key .. ";", 1, true) then dumps[#dumps + 1] = text end
    end
    local last = dumps[#dumps]
    Mock.hear(dumps[1], "Purr Gola")
    Mock.hear(last:sub(1, -2) .. (last:sub(-1) == "A" and "B" or "A"), "Purr Gola")
    equal(ns.Guild.stats.taken, 0); equal(ns.Guild.stats.badFingerprint, 1)
    -- only some parts: nothing kept yet
    Mock.hear(dumps[1], "Purr Gola")
    equal(ns.Guild.stats.taken, 0)
    Mock.hear(last, "Purr Gola")
    equal(ns.Guild.stats.taken, 1, "the right parts: kept")
end)

scenario("guild: a throttled message goes again later; our own echo and other prefixes are ignored; asked for an old copy we say what it is now", function()
    local ns = start({ guild = GUILD, roster = { { name = "Purr Gola", online = true } } }, function(state)
        state.learned[WESTFALL_STEW] = true
    end)
    Mock.sendResults = { 3 } -- the roll call is throttled once
    Mock.advance(9)
    equal(#Mock.sent, 0); equal(ns.Guild.stats.retried, 1)
    Mock.advance(6)
    equal(Mock.sent[1].text, "R;1", "sent again a moment later")
    Mock.advance(5)
    local heard = ns.Guild.stats.heard
    Mock.hear("R;1", "Purr Gola")
    Mock.hear("H;1;AAAAAAAA;Zz Top - ClassicBetaPvE", "Zz Top", "OTHER")
    equal(ns.Guild.stats.heard, heard, "our own words and another addon's are not ours to hear")
    Mock.sent = {}
    Mock.hear("Q;AAAAAAAA;" .. ME_A, "Thrall Smith")
    Mock.advance(3)
    equal(#Mock.sentTexts("D"), 0, "an old copy is not sent")
    equal(#Mock.sentTexts("H"), 1, "a hello with what it is now instead")
    equal(#Mock.errors, 0)
end)

scenario("guild: someone who left is dropped - but only when the roster is plainly ours; '/akr share off' sends nothing and shows nothing", function()
    local sentA = guildmateA()
    local ns, state = guildmateB({ { name = "Thrall Smith", online = true }, { name = "Purr Gola", online = true } })
    for _, text in ipairs(sentA) do
        if text:sub(1, 2) == "D;" then Mock.hear(text, "Purr Gola") end
    end
    equal(ns.Guild:Describe().characters, 2)
    -- a roster written in a way we do not recognise (our own name not in it): nothing dropped
    state.roster = { { name = "Somebody", online = true } }
    Mock.fire("GUILD_ROSTER_UPDATE")
    equal(ns.Guild:Describe().characters, 2, "not our roster's spelling: nothing dropped")
    -- Purr Gola left: both their characters go
    state.roster = { { name = "Thrall Smith-ClassicBetaPvE", online = true } }
    Mock.fire("GUILD_ROSTER_UPDATE")
    equal(ns.Guild:Describe().characters, 0, "left the guild: dropped")
    equal(ns.Guild.stats.pruned, 2)
    -- back in the guild; then share off
    state.roster = { { name = "Thrall Smith", online = true }, { name = "Purr Gola", online = true } }
    Mock.fire("GUILD_ROSTER_UPDATE")
    for _, text in ipairs(sentA) do
        if text:sub(1, 2) == "D;" then Mock.hear(text, "Purr Gola") end
    end
    Mock.slash("share off")
    equal(#ns.Guild:Who(ns.Lookup.BySpell(WESTFALL_STEW)), 0, "off: nothing shown")
    Mock.sent = {}
    Mock.hear("R;1", "Purr Gola")
    Mock.advance(20)
    equal(#Mock.sent, 0, "off: nothing sent")
    Mock.slash("share on")
    equal(#ns.Guild:Who(ns.Lookup.BySpell(WESTFALL_STEW)), 1, "on again: shown")
    Mock.slash("guild")
    check(printed("Purr Gola"), "'/akr guild' lists them")
    equal(#Mock.errors, 0)
end)

scenario("guild: no guild - nothing is sent, nothing breaks, the cards look as before", function()
    local ns = start(nil, function(state) state.learned[WESTFALL_STEW] = true end)
    Mock.advance(20)
    equal(#Mock.sent, 0)
    ns.Window:Show()
    equal(cardNamed(ns, "Charred Wolf Meat").guild, nil)
    equal(#Mock.errors, 0)
end)

------------------------------------------------------------------------
-- Friends
------------------------------------------------------------------------
-- Purr Gola's client, no guild, Thrall Smith on its friends list: what it says to Thrall when Thrall says R
-- and then asks for both characters. Gives back those texts.
local function friendA(how)
    local db = { schema = 2, chars = { ["Purr Smith - ClassicBetaPvE"] = {
        learned = { [SHARPENING_STONE] = 1 }, skills = { blacksmithing = { skill = 90, max = 150 } }, profs = { blacksmithing = true }, side = "A", options = {} } } }
    local ns = start({ db = db, friends = { { name = "Thrall Smith", online = true } } }, function(state)
        state.learned[WESTFALL_STEW] = true
        state.learned[CHARRED_WOLF] = true
        state.skill = { level = 120, max = 150 }
    end)
    Mock.advance(12)
    Mock.whisper("R;1", "Thrall Smith")
    Mock.advance(6)
    for _, hello in ipairs(Mock.sentTo("Thrall Smith", "H")) do
        local fp, key = hello:match("^H;1;([^;]+);(.+)$")
        Mock.whisper("Q;" .. fp .. ";" .. key, "Thrall Smith")
    end
    Mock.advance(30)
    return Mock.sentTo("Thrall Smith"), ns
end

scenario("friends: at login one 'R' to each friend online who is not in the guild - by hidden whisper, never to an offline friend; a stranger's whisper is ignored", function()
    local ns = start({ guild = GUILD, roster = { { name = "Thrall Smith", online = true }, { name = "Guild Mate", online = true } },
        friends = { { name = "Jaina Proud", online = true }, { name = "Sleepy Head", online = false }, { name = "Guild Mate", online = true } } })
    Mock.advance(12)
    equal(table.concat(Mock.sentTo("Jaina Proud"), "|"), "R;1", "the friend online")
    equal(#Mock.sentTo("Sleepy Head"), 0, "offline: no whisper (the client would complain in chat)")
    equal(#Mock.sentTo("Guild Mate"), 0, "in the guild: hears it there")
    for _, message in ipairs(Mock.sent) do
        if message.target == "Jaina Proud" then equal(message.channel, "WHISPER") end
    end
    Mock.whisper("H;1;AAAAAAAA;Evil Guy - ClassicBetaPvE", "Evil Guy")
    Mock.advance(5)
    equal(ns.Friends.stats.strangers, 1)
    equal(#Mock.sentTo("Evil Guy"), 0, "nothing back to a stranger")
    equal(#Mock.errors, 0)
end)

scenario("friends: a friend's characters arrive by whisper - tagged Friend, 'Friends: Purr Gola' on the card, 'Your friends (1)' in the opened card; both sides know each other after one R", function()
    local sentA = friendA()
    local hellosA = {}
    for _, text in ipairs(sentA) do if text:sub(1, 2) == "H;" then hellosA[#hellosA + 1] = text end end
    equal(#hellosA, 2, "Purr Gola's cook and blacksmith")
    local ns = start({ first = "Thrall", last = "Smith", friends = { { name = "Purr Gola", online = true } } })
    Mock.advance(12)
    Mock.sent = {}
    for _, text in ipairs(hellosA) do Mock.whisper(text, "Purr Gola") end
    Mock.advance(5)
    equal(#Mock.sentTo("Purr Gola", "Q"), 2, "both asked for, straight back")
    check(#Mock.sentTo("Purr Gola", "H") >= 1, "their first hello: ours go back to them")
    for _, text in ipairs(sentA) do if text:sub(1, 2) == "D;" then Mock.whisper(text, "Purr Gola") end end
    equal(ns.Friends.stats.taken, 2); equal(ns.Friends.stats.badFingerprint, 0)
    ns.Window:Show()
    local stew = cardNamed(ns, "Westfall Stew")
    check(Mock.plain(stew.tags):find("^Friend"), Mock.plain(stew.tags))
    equal(Mock.plain(stew.guild), "Friends: Purr Gola")
    stew.click()
    local rows = Mock.rows()
    check(has(rows, "Your friends (1):"), table.concat(rows, "\n"))
    check(has(rows, "Purr Gola  Cooking 120 | online"), table.concat(rows, "\n"))
    check(not has(rows, "In your guild"), "no guild section")
    -- off the friends list: dropped
    Mock.state.friends = {}
    Mock.fire("FRIENDLIST_UPDATE")
    equal(#ns.Friends:Who(ns.Lookup.BySpell(WESTFALL_STEW)), 1, "an empty list may be one not loaded yet: kept")
    Mock.state.friends = { { name = "Someone Else", online = false } }
    Mock.fire("FRIENDLIST_UPDATE")
    equal(#ns.Friends:Who(ns.Lookup.BySpell(WESTFALL_STEW)), 0, "no longer a friend: dropped")
    equal(#Mock.errors, 0)
end)

scenario("friends: a Battle.net friend - R and the answers go as game data to their game account; data from an account that is no friend is ignored", function()
    local sentA = friendA()
    local ns = start({ first = "Thrall", last = "Smith", bnFriends = { { tag = "Purr#1234", id = 77, character = "Purr Gola", online = true },
        { tag = "Away#1", id = 78, character = "Gone", online = false } } })
    Mock.advance(12)
    equal(table.concat(Mock.sentTo(77), "|"), "R;1", "to the game account")
    equal(#Mock.sentTo(78), 0, "not in the game: nothing")
    for _, message in ipairs(Mock.sent) do
        if message.target == 77 then equal(message.channel, "BN") end
    end
    Mock.sent = {}
    for _, text in ipairs(sentA) do if text:sub(1, 2) == "H;" then Mock.bnHear(text, 77) end end
    Mock.advance(5)
    equal(#Mock.sentTo(77, "Q"), 2)
    for _, text in ipairs(sentA) do if text:sub(1, 2) == "D;" then Mock.bnHear(text, 77) end end
    equal(ns.Friends.stats.taken, 2)
    equal(ns.Friends:Store()["Purr Gola - ClassicBetaPvE"].tag, "Purr#1234", "remembered by BattleTag")
    Mock.bnHear("R;1", 99)
    equal(ns.Friends.stats.strangers, 1)
    -- a friend who is in the guild too shows under the guild only
    equal(#ns.Friends:Who(ns.Lookup.BySpell(WESTFALL_STEW)), 1)
    equal(#Mock.errors, 0)
end)

scenario("friends: '/akr share off' sends nothing to friends and shows nothing; on again, the R goes out", function()
    local ns = start({ friends = { { name = "Jaina Proud", online = true } } }, function() end)
    Mock.slash("share off")
    Mock.advance(12)
    equal(#Mock.sentTo("Jaina Proud"), 0)
    Mock.whisper("R;1", "Jaina Proud")
    Mock.advance(6)
    equal(#Mock.sentTo("Jaina Proud"), 0, "off: no answer either")
    Mock.slash("share on")
    Mock.advance(2)
    equal(table.concat(Mock.sentTo("Jaina Proud"), "|"), "R;1")
    Mock.slash("friends")
    equal(#Mock.errors, 0)
end)

scenario("friends: a tampered dump from a friend is not kept", function()
    local sentA = friendA()
    local ns = start({ first = "Thrall", last = "Smith", friends = { { name = "Purr Gola", online = true } } })
    Mock.advance(12)
    for _, text in ipairs(sentA) do
        if text:sub(1, 2) == "D;" then
            Mock.whisper((text:gsub("cooking:120:150", "cooking:300:300")), "Purr Gola")
        end
    end
    equal(ns.Friends.stats.taken, 1, "only the untouched blacksmith")
    equal(ns.Friends.stats.badFingerprint, 1)
end)

------------------------------------------------------------------------
-- Lockpicking
------------------------------------------------------------------------
local function lockCard(ns, name)
    for _, entry in ipairs(ns.Window:Lines()) do
        if entry.card and Mock.plain(entry.text) == name then return entry end
    end
end

scenario("lockpicking: a rogue gets a Lockpicking tab - every lock by the skill it needs, which open now, how much more the others need; the other faction's quest chests left out", function()
    local ns = start({ class = "ROGUE" }, function(state) state.skills[633] = { level = 130, max = 150 } end)
    equal(ns.db.chars[ns.characterKey].lockpick.skill, 130, "the skill read and kept")
    ns.Window:Show()
    check(has(ns.Window.totals.offered, "lockpicking"), "the tab is offered")
    ns.Window:SetProfession("lockpicking")
    ns:SetOption("filter", "all")
    local iron, steel = lockCard(ns, "Iron Lockbox"), lockCard(ns, "Steel Lockbox")
    equal(Mock.plain(iron.right), "You can open it"); equal(iron.state, "known"); equal(iron.skill, 70)
    equal(Mock.plain(steel.right), "45 more skill"); equal(steel.state, "later")
    check(Mock.plain(steel.tags):find("as in Classic"), "Classic's number: said so")
    check(lockCard(ns, "Lucius's Lockbox") ~= nil, "an Alliance rogue's quest chest")
    check(lockCard(ns, "Gallywix's Lockbox") == nil, "the Horde one left out")
    local first, last = nil, nil
    for _, entry in ipairs(ns.Window:Lines()) do
        if entry.card then first = first or entry.skill; check(entry.skill >= (last or 0), "in skill order"); last = entry.skill end
    end
    equal(first, 1)
    -- opened: where, the key, the skill
    iron.click()
    iron = lockCard(ns, "Scarlet Monastery Armory Door")
    iron.click()
    local door = lockCard(ns, "Scarlet Monastery Armory Door")
    local text = {}
    for _, d in ipairs(door.details) do text[#text + 1] = Mock.plain(d.text) end
    check(has(text, "Or open it with: The Scarlet Key"), table.concat(text, "\n"))
    check(has(text, "Your skill: 130"))
    -- the filter: missing ones only
    ns:SetOption("filter", "missing")
    check(lockCard(ns, "Iron Lockbox") == nil and lockCard(ns, "Steel Lockbox") ~= nil, "missing: the ones it cannot open yet")
    equal(#Mock.errors, 0)
end)

scenario("lockpicking: the game's tooltip naming the skill wins over Classic's number; somebody who is no rogue gets no tab", function()
    local ns = start({ class = "ROGUE", tooltips = { [4634] = { "Iron Lockbox", "Locked", "Requires Lockpicking (80)" } } },
        function(state) state.skills[633] = { level = 75, max = 150 } end)
    ns.Window:Show()
    ns.Window:SetProfession("lockpicking")
    local iron = lockCard(ns, "Iron Lockbox")
    equal(iron.skill, 80, "read from the game")
    equal(Mock.plain(iron.right), "5 more skill")
    check(not Mock.plain(iron.tags):find("as in Classic"), Mock.plain(iron.tags))
    local mage = start({ class = "MAGE" })
    mage.Window:Show()
    check(not has(mage.Window.totals.offered, "lockpicking"), "no tab for a mage")
    equal(#Mock.errors, 0)
end)

scenario("training: a rank the character's level is too low for is not ready - 'and level 20', 'You are level 13'", function()
    local ns = start({ faction = "Alliance", level = 13 }, function(state)
        state.skill = { level = 130, max = 150 }
    end)
    Mock.slash("show all")
    ns.Window.widgets.tabs.cooking:Click()
    local card = ns.Window.lines[1]
    equal(Mock.plain(card.desc), "Your cap is 150 (Journeyman).  It can be learned at Cooking 125 and level 20.  You are level 13.")
    equal(card.state, "later", "skill enough, level not")
    card.click()
    local rows = {}
    for _, d in ipairs(ns.Window.lines[1].details) do rows[#rows + 1] = Mock.plain(d.text) end
    check(has(rows, "Needs character level 20 - you are level 13"), table.concat(rows, "\n"))
    check(has(rows, "Needs character level 35"), "Artisan too")
    Mock.state.level = 20
    Mock.fire("PLAYER_LEVEL_UP", 20)
    ns.Window:Render()
    equal(ns.Window.lines[1].state, "now", "level 20: ready")
    equal(#Mock.errors, 0)
end)

scenario("a recipe item's tooltip: which of your characters on the realm with the profession can learn it, need more skill, or know it", function()
    local RED_ROBE_PATTERN, RED_ROBE = 2598, 2389         -- Pattern: Red Linen Robe, learned at Tailoring 25
    local BLUE_VEST_PATTERN, BLUE_VEST = 6270, 7630       -- Pattern: Blue Linen Vest, 35
    local ELIXIR_RECIPE = 250380                          -- an Alchemy recipe: nobody here has Alchemy
    local db = { schema = 2, chars = {
        ["Purr Smith - ClassicBetaPvE"] = { learned = {}, skills = { tailoring = { skill = 20, max = 75 } }, profs = { tailoring = true }, side = "A", options = {} },
        ["Purr Know - ClassicBetaPvE"] = { learned = { [RED_ROBE] = 1 }, skills = { tailoring = { skill = 200, max = 225 } }, profs = { tailoring = true }, side = "A", options = {} },
        ["Purr Cook - ClassicBetaPvE"] = { learned = {}, skills = { cooking = { skill = 150, max = 225 } }, profs = { cooking = true }, side = "A", options = {} },
        ["Far Away - OtherRealm"] = { learned = {}, skills = { tailoring = { skill = 300, max = 300 } }, profs = { tailoring = true }, side = "A", options = {} },
    } }
    local ns = start({ db = db, tooltips = true }, function(state)
        state.skills[TAILORING] = { level = 120, max = 150 } -- Purr Gola, the one logged in
        state.learned[BLUE_VEST] = true
    end)
    equal(ns.Tip.hooked, true)
    local text, lines = Mock.showItem(RED_ROBE_PATTERN)
    equal(text, "Your characters: |   Purr Gola: can learn it (Tailoring 120) |   Purr Smith: Tailoring 20, needs 25 |   Purr Know: knows it")
    equal(string.format("%.2f %.2f %.2f", lines[2].r, lines[2].g, lines[2].b), "0.25 1.00 0.25", "can learn: green")
    equal(string.format("%.2f %.2f %.2f", lines[3].r, lines[3].g, lines[3].b), "1.00 0.50 0.25", "too low: orange")
    check(not text:find("Cook", 1, true) and not text:find("Far", 1, true), "no Tailoring / another realm: left out")
    -- known by the one logged in (the client said so at login)
    text = Mock.showItem(BLUE_VEST_PATTERN)
    equal(text, "Your characters: |   Purr Know: can learn it (Tailoring 200) |   Purr Smith: Tailoring 20, needs 35 |   Purr Gola: knows it")
    -- a chat link's tooltip too; a comparison tooltip and other frames not
    text = Mock.showItem(RED_ROBE_PATTERN, ItemRefTooltip)
    check(text:find("Purr Gola: can learn it", 1, true), text)
    equal(Mock.showItem(RED_ROBE_PATTERN, ShoppingTooltip1), "")
    -- nobody with the profession, or not a recipe at all: nothing
    equal(Mock.showItem(ELIXIR_RECIPE), "")
    equal(Mock.showItem(2589), "")
    -- a specialization's recipe says so
    local robe = ns.Lookup.ByRecipeItem(RED_ROBE_PATTERN)
    robe.spec = "Gnomish"
    check(Mock.showItem(RED_ROBE_PATTERN):find("Your characters - Gnomish Engineering only:", 1, true))
    robe.spec = nil
    robe.side = "H" -- every tailor here is Alliance: nobody, so not even the heading
    equal(Mock.showItem(RED_ROBE_PATTERN), "")
    robe.side = nil
    -- one faction's recipe: the other faction's characters are left out
    local who = ns.Tip.Who({ prof = "tailoring", spell = 1, learn = 1, side = "H" })
    equal(#who, 0, "a Horde recipe, Alliance characters")
    who = ns.Tip.Who({ prof = "tailoring", spell = 1, learn = 1, side = "A" })
    equal(#who, 3)
    -- no skill saved for a character: what it needs
    db.chars["Purr Smith - ClassicBetaPvE"].skills = {}
    check(Mock.showItem(RED_ROBE_PATTERN):find("Purr Smith: needs Tailoring 25", 1, true))
    -- /akr tooltip off
    Mock.slash("tooltip off")
    equal(Mock.showItem(RED_ROBE_PATTERN), "")
    Mock.slash("tooltip on")
    check(Mock.showItem(RED_ROBE_PATTERN) ~= "")
    equal(#Mock.errors, 0, Mock.errors[1])
end)

scenario("one faction's recipe: a Horde tailor who knows the Horde Faction Banner is not shown the Alliance one as missing", function()
    local HORDE_BANNER, ALLIANCE_BANNER = 1229504, 1263425
    local ns = start({ faction = "Horde" }, function(state)
        state.skills[197] = { level = 60, max = 75 }
        state.learned[HORDE_BANNER] = true
    end)
    ns.Lookup.BuildAll()
    check(ns.Lookup.Sources(ns.Lookup.BySpell(ALLIANCE_BANNER), "H").otherSide, "the Alliance banner is the other side's")
    check(not ns.Lookup.Sources(ns.Lookup.BySpell(HORDE_BANNER), "H").otherSide)
    check(ns.Lookup.Sources(ns.Lookup.BySpell(HORDE_BANNER), "A").otherSide, "and the other way round")
    Mock.slash("show all")
    ns.Window:SetProfession("tailoring")
    ns:SetOption("filter", "all")
    local banners = 0
    for _, entry in ipairs(ns.Window:Lines()) do
        if entry.card and Mock.plain(entry.text):find("^Faction Banner") then
            banners = banners + 1
            check(Mock.plain(entry.right) == "Known", "the one listed is the known one: " .. Mock.plain(entry.right))
        end
    end
    equal(banners, 1)
    equal(#Mock.errors, 0)
end)

------------------------------------------------------------------------
-- Cooldowns (the user, 2026-11-17: "track cooldowns like transmutes, mooncloth, refined deeprock salt per
-- character/acccount" - one Cooldowns tab for everything, a login line for the ready ones)
------------------------------------------------------------------------
local ARCANITE, AIR_TO_FIRE, IRON_TO_GOLD, MOONCLOTH, SALT_SHAKER = 17187, 17559, 11479, 18560, 15846
local TWO_DAYS, FOUR_DAYS, THREE_DAYS = 169200, 342000, 255600 -- Forever's: 47, 95 and 71 hours

-- Purr Gola as an alchemist who knows Transmute: Arcanite, Air to Fire and Iron to Gold
local function alchemist(state)
    state.skills[ALCHEMY] = { level = 300, max = 300 }
    state.learned[ARCANITE], state.learned[AIR_TO_FIRE], state.learned[IRON_TO_GOLD] = true, true, true
end

local function cdCard(ns, name, who)
    for _, entry in ipairs(ns.Window:Lines()) do
        if entry.card and Mock.plain(entry.text) == name and (not who or Mock.plain(entry.tags) == who) then return entry end
    end
end

local function cooldownTab(ns)
    ns.Window:Show()
    ns.Window:SetProfession("cooldowns")
end

-- the cooldowns' own row under the profession tabs: its words and the hint at its right end - nil while
-- it is not shown
local function strip(ns)
    local row = ns.Window.widgets.cooldowns
    if not row:IsShown() then return nil end
    return Mock.plain(row.words:GetText()), Mock.plain(row.hint:GetText())
end

-- how far under the window's top the list of cards starts
local function listTop(ns)
    local _, _, _, _, y = ns.Window.widgets.scroll:GetPoint(1)
    return -y
end

scenario("cooldowns: the table - every transmute is one shared cooldown, Iron to Gold, Mithril to Truesilver and Mooncloth have their own, the Salt Shaker is an item's use; every spell is a recipe of ours", function()
    local ns = start()
    ns.Lookup.BuildAll()
    local by = {}
    for _, group in ipairs(ns.Cooldowns.Groups()) do
        by[group.key] = group
        for _, entry in ipairs(group.spells or {}) do
            check(ns.Lookup.BySpell(entry.spell) ~= nil, entry.name .. " is no recipe of ours")
            check(entry.seconds >= 600, entry.name)
        end
    end
    equal(by.transmute.shared, true); equal(by.transmute.prof, "alchemy")
    check(#by.transmute.spells >= 10, "the transmutes")
    equal(by.transmute.spells[1].seconds, TWO_DAYS, "the longest first")
    equal(ns.Cooldowns.Length(by.transmute), TWO_DAYS)
    equal(by.s18560.name, "Mooncloth"); equal(by.s18560.prof, "tailoring"); equal(ns.Cooldowns.Length(by.s18560), FOUR_DAYS)
    equal(by.s11479.name, "Transmute: Iron to Gold"); equal(ns.Cooldowns.Length(by.s11479), 3600)
    equal(by.s11480.name, "Transmute: Mithril to Truesilver")
    equal(by.salt.item, SALT_SHAKER); equal(by.salt.seconds, THREE_DAYS); equal(by.salt.prof, "leatherworking")
    equal(ns.Cooldowns.Span(FOUR_DAYS), "3d 23h"); equal(ns.Cooldowns.Span(86400), "1d"); equal(ns.Cooldowns.Span(3600), "1h")
    equal(ns.Cooldowns.Span(3601), "1h 1m"); equal(ns.Cooldowns.Span(59), "1m"); equal(ns.Cooldowns.Span(0), "1m")
    equal(ns.Cooldowns.Short(51600), "14h"); equal(ns.Cooldowns.Short(51660), "14h"); equal(ns.Cooldowns.Short(2700), "45m")
    equal(ns.Cooldowns.Short(TWO_DAYS), "1d 23h")
end)

scenario("cooldowns: a transmute is read when the game says a cooldown moved, kept as the moment it is over, and counted down from there - whichever transmute was made", function()
    local ns, state = start(nil, alchemist)
    Mock.advance(10)
    local saved = ns.db.chars[ns.characterKey].cooldowns
    check(saved and saved.transmute and saved.transmute.ready <= time(), "read after login: the transmute is ready")
    check(saved.s11479 and saved.s11479.ready <= time(), "Iron to Gold, a cooldown of its own")
    equal(saved.s11480, nil, "Mithril to Truesilver is not known")
    equal(saved.s18560, nil, "no tailor"); equal(saved.salt, nil, "no Salt Shaker")
    local since = saved.transmute.ready

    -- an Arcanite Bar is made: the game puts 47 hours on every transmute - here it says so for another one
    local made = time()
    Mock.cooldown(AIR_TO_FIRE, TWO_DAYS, TWO_DAYS)
    Mock.advance(2)
    equal(saved.transmute.ready, made + TWO_DAYS, "the moment it is over, on the wall clock")
    equal(saved.s11479.ready, since, "Iron to Gold is untouched - and ready since when it was")

    cooldownTab(ns)
    equal((strip(ns)), "Cooldowns: 1 ready - next Transmute (Purr Gola) 1d 23h", "the row of its own says so")
    local card = cdCard(ns, "Transmute", "Purr Gola")
    equal(card.skill, "1d 23h"); equal(card.skillLabel, "left"); equal(card.state, "later")
    equal(Mock.plain(card.right), "Ready in 1d 23h")
    equal(Mock.plain(card.desc), "Alchemy - one cooldown for all 12 of them, up to 1d 23h")
    equal(card.item, 12360, "the tooltip of what the longest makes")
    local gold = cdCard(ns, "Transmute: Iron to Gold", "Purr Gola")
    equal(gold.skill, "Ready"); equal(gold.state, "known"); equal(Mock.plain(gold.right), "Ready"); equal(gold.skillLabel, "")
    equal(Mock.plain(gold.desc), "Alchemy - 1h")
    equal(Mock.info(), "Cooldowns of all your characters: 1 ready, 1 running   right-click hides")
    local lines = ns.Window:Lines()
    equal(Mock.plain(lines[1].text), "Transmute: Iron to Gold", "ready ones first")

    -- a day and a half on, nothing read in between: counted from the saved moment
    state.now = state.now + 36 * 3600
    card = cdCard(ns, "Transmute", "Purr Gola")
    equal(card.skill, "11h"); equal(Mock.plain(card.right), "Ready in 11h")
    state.now = state.now + 10 * 3600 + 1800
    equal(Mock.plain(cdCard(ns, "Transmute", "Purr Gola").right), "Ready in 30m")
    equal(cdCard(ns, "Transmute", "Purr Gola").skill, "30m")
    state.now = state.now + 1800
    card = cdCard(ns, "Transmute", "Purr Gola")
    equal(card.skill, "Ready"); equal(card.state, "known")

    -- opened: who, what starts it and for how long, when it was read
    card.click()
    card = cdCard(ns, "Transmute", "Purr Gola")
    local text = {}
    for _, d in ipairs(card.details) do text[#text + 1] = Mock.plain(d.text) .. " | " .. Mock.plain(d.right) end
    check(has(text, "Purr Gola: ready"), table.concat(text, "\n"))
    check(has(text, "Transmute: Arcanite | 1d 23h"), table.concat(text, "\n"))
    check(has(text, "Transmute: Air to Fire | 23h"))
    check(has(text, "Transmute: Elemental Fire | 10m"))
    check(has(text, "Read on Purr Gola 1d 23h ago"), table.concat(text, "\n"))
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: the other characters are shown from what was saved on them - the time left runs while you play someone else; one never read says so; a character with no cooldown is not listed", function()
    local now = 1700000000 + 1000 -- the mock's wall clock at login
    local db = { schema = 2, chars = {
        ["Purr Smith - ClassicBetaPvE"] = { learned = { [MOONCLOTH] = 1 }, skills = { tailoring = { skill = 290, max = 300 } }, profs = { tailoring = true },
            side = "A", options = {}, cooldowns = { s18560 = { ready = now + 30 * 3600, at = now - 500 } } },
        ["Purr Know - ClassicBetaPvE"] = { learned = { [ARCANITE] = 1 }, skills = { alchemy = { skill = 300, max = 300 } }, profs = { alchemy = true },
            side = "A", options = {} },
        ["Purr Salt - OtherRealm"] = { learned = {}, skills = {}, profs = { leatherworking = true }, side = "A", options = {},
            cooldowns = { salt = { ready = now - 50, at = now - 90000 } } },
        ["Purr Wait - ClassicBetaPvE"] = { learned = { [ARCANITE] = 1 }, skills = {}, profs = { alchemy = true }, side = "A", options = {},
            cooldowns = { transmute = { ready = now + 5 * 3600, at = now - 500 } } },
        ["Purr Cook - ClassicBetaPvE"] = { learned = { [WESTFALL_STEW] = 1 }, skills = {}, profs = { cooking = true }, side = "A", options = {} },
    } }
    local ns, state = start({ db = db })
    Mock.advance(10)
    cooldownTab(ns)
    local order = {}
    for _, entry in ipairs(ns.Window:Lines()) do
        order[#order + 1] = Mock.plain(entry.text) .. " [" .. Mock.plain(entry.tags) .. "] " .. tostring(entry.skill)
    end
    equal(table.concat(order, "; "), "Refined Deeprock Salt [Purr Salt] Ready; Transmute [Purr Wait] 5h; Mooncloth [Purr Smith] 1d 6h; Transmute [Purr Know] ?",
        "ready, then running with the soonest first, then not read - whatever realm")
    equal(Mock.plain(cdCard(ns, "Transmute", "Purr Know").right), "Not read yet - log in on Purr Know once")
    equal(cdCard(ns, "Transmute", "Purr Know").state, "plain")
    equal(Mock.plain(cdCard(ns, "Refined Deeprock Salt").desc), "Leatherworking - using the Salt Shaker, 2d 23h")
    equal(cdCard(ns, "Refined Deeprock Salt").item, 15409, "the salt's own tooltip")
    equal(Mock.plain(cdCard(ns, "Mooncloth").desc), "Tailoring - 3d 23h")
    equal(Mock.info(), "Cooldowns of all your characters: 1 ready, 2 running   1 not read yet   right-click hides")
    state.now = state.now + 29 * 3600
    equal(cdCard(ns, "Mooncloth", "Purr Smith").skill, "1h")
    equal(Mock.plain(cdCard(ns, "Mooncloth", "Purr Smith").right), "Ready in 1h")
    -- the search finds a cooldown by its name, its character or its profession
    ns.Window.query = "smith"
    equal(#ns.Window:Lines(), 1); check(cdCard(ns, "Mooncloth", "Purr Smith"))
    ns.Window.query = "leatherw"
    equal(#ns.Window:Lines(), 1); check(cdCard(ns, "Refined Deeprock Salt"))
    ns.Window.query = "zzz"
    equal(Mock.plain(ns.Window:Lines()[1].note), 'Nothing matches "zzz".')
    ns.Window.query = ""

    -- nobody on the account has a cooldown: no row, and the window is as it was
    local plain = start()
    Mock.advance(10)
    plain.Window:Show()
    equal(strip(plain), nil, "no row without a cooldown")
    equal(listTop(plain), 74, "and the list starts where it always did")
    plain.Window:SetProfession("cooldowns")
    check(plain.Window.totals.prof ~= "cooldowns", "and asking for it lands on a real tab")
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: the Salt Shaker - tracked for whoever owns one, read as the item's cooldown; sold, it is dropped", function()
    local ns, state = start(nil, function(state) state.items[SALT_SHAKER] = 1 end)
    Mock.advance(10)
    local saved = ns.db.chars[ns.characterKey].cooldowns
    check(saved.salt and saved.salt.ready <= time(), "owned and ready")
    local used = time()
    Mock.itemCooldown(SALT_SHAKER, THREE_DAYS, THREE_DAYS)
    Mock.advance(2)
    equal(saved.salt.ready, used + THREE_DAYS)
    cooldownTab(ns)
    equal(cdCard(ns, "Refined Deeprock Salt", "Purr Gola").skill, "2d 23h")
    -- the bags cannot be read: what is saved stays
    state.bagsSecret = true
    Mock.fire("BAG_UPDATE_COOLDOWN"); Mock.advance(2)
    equal(saved.salt.ready, used + THREE_DAYS)
    state.bagsSecret = false
    -- the shaker is gone
    state.items[SALT_SHAKER] = 0
    Mock.fire("BAG_UPDATE_COOLDOWN"); Mock.advance(2)
    equal(saved.salt, nil)
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: what the client will not say changes nothing - secret numbers, no answer, no such call, combat; a burst of events is one read", function()
    local ns, state = start(nil, alchemist)
    Mock.advance(10)
    local saved = ns.db.chars[ns.characterKey].cooldowns
    Mock.cooldown(ARCANITE, TWO_DAYS, TWO_DAYS)
    Mock.advance(2)
    local ready = saved.transmute.ready
    check(ready > time(), "running")
    -- the game then keeps the numbers to itself: the saved moment stays
    for _, mode in ipairs({ "secret", "nil" }) do
        state.cooldownMode = mode
        Mock.fire("SPELL_UPDATE_COOLDOWN"); Mock.advance(2)
        equal(saved.transmute.ready, ready, mode)
    end
    state.cooldownMode = "ok"
    -- in combat nothing is asked at all
    state.combat = true
    local asked = state.calls.cooldown
    Mock.fire("SPELL_UPDATE_COOLDOWN"); Mock.advance(2)
    equal(state.calls.cooldown, asked, "not asked in combat")
    state.combat = false
    -- twenty events in a moment: one read (three known spells asked once each)
    asked = state.calls.cooldown
    for _ = 1, 20 do Mock.fire("SPELL_UPDATE_COOLDOWN") end
    Mock.advance(2)
    equal(state.calls.cooldown, asked + 3, "one read")
    -- the game says it is over early (a reset): believed
    Mock.cooldown(ARCANITE, 0, 0)
    Mock.advance(2)
    check(saved.transmute.ready <= time(), "over")
    equal(Mock.errors[1], nil, "and none of that raised an error")

    -- a client without the calls: nothing kept, nothing breaks
    local bare = start({ noCooldowns = true }, alchemist)
    Mock.advance(10)
    equal(next(bare.db.chars[bare.characterKey].cooldowns or {}), nil, "nothing read, nothing kept")
    bare.Window:Show()
    equal((strip(bare)), "Cooldowns: 2 not read yet", "the row is there all the same: this character knows two transmutes with a cooldown each")
    bare.Window:SetProfession("cooldowns")
    equal(cdCard(bare, "Transmute", "Purr Gola").skill, "?")
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: a cooldown from before this session - the client's start time has wrapped round - is read right; the global cooldown is no cooldown", function()
    local ns, state = start(nil, function(state)
        state.skills[TAILORING] = { level = 300, max = 300 }
        state.learned[MOONCLOTH] = true
    end)
    Mock.advance(10)
    local saved = ns.db.chars[ns.characterKey].cooldowns
    -- Mooncloth was made 100,000 seconds ago, long before the client started: 242,000 seconds are left
    state.spellCooldowns[MOONCLOTH] = { state.now - 100000 + 4294967.296, FOUR_DAYS }
    local at = time()
    Mock.fire("SPELL_UPDATE_COOLDOWN"); Mock.advance(2)
    equal(saved.s18560.ready, at + 242000)
    -- the global cooldown and other short ones show on every spell: not a craft's cooldown
    state.spellCooldowns[MOONCLOTH] = { state.now, 30 }
    Mock.fire("SPELL_UPDATE_COOLDOWN"); Mock.advance(2)
    check(saved.s18560.ready <= time(), "ready, with 28 seconds of a short cooldown left")
    -- a number that makes no sense (more left than the cooldown is long) is cut to its length
    state.spellCooldowns[MOONCLOTH] = { state.now + 0.9, FOUR_DAYS }
    ns.Cooldowns:Read()
    equal(saved.s18560.ready, time() + FOUR_DAYS, "never longer than the cooldown")
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: one line at login when a long cooldown is ready on any character - the one-hour bars and hidden ones left out; nothing ready, nothing said; '/akr cd notice off' silences it for good", function()
    local now = 1700000000 + 1000
    local function account()
        return { schema = 2, chars = {
            ["Purr Smith - ClassicBetaPvE"] = { learned = { [MOONCLOTH] = 1 }, skills = {}, profs = { tailoring = true }, side = "A", options = {},
                cooldowns = { s18560 = { ready = now - 10, at = now - 500 } } },
            ["Purr Know - ClassicBetaPvE"] = { learned = { [ARCANITE] = 1 }, skills = {}, profs = { alchemy = true }, side = "A", options = {},
                cooldowns = { transmute = { ready = now - 10, at = now - 500 }, s11479 = { ready = now - 10, at = now - 500 } } },
            ["Purr Wait - ClassicBetaPvE"] = { learned = { [ARCANITE] = 1 }, skills = {}, profs = { alchemy = true }, side = "A", options = {},
                cooldowns = { transmute = { ready = now + 5000, at = now - 500 } } },
        } }
    end
    local ns = start({ db = account() }, alchemist)
    equal(printed("Ready:"), false, "not before the game was asked")
    Mock.advance(10)
    check(printed("AKForeverRecipes|r: Ready: Mooncloth (Purr Smith), Transmute (Purr Gola, Purr Know)"), table.concat(Mock.printed, " | "))
    local count = 0
    for _, line in ipairs(Mock.printed) do if line:find("Ready:", 1, true) then count = count + 1 end end
    equal(count, 1, "once")
    equal(printed("Iron to Gold"), false, "a one-hour cooldown is not worth a line")

    -- hidden on one character: left out for that character
    local db = account()
    db.chars["Purr Know - ClassicBetaPvE"].cooldownsHidden = { transmute = true }
    start({ db = db })
    Mock.advance(10)
    check(printed("Ready: Mooncloth (Purr Smith)"), table.concat(Mock.printed, " | "))
    equal(printed("Transmute"), false)

    -- nothing ready
    db = account()
    db.chars["Purr Smith - ClassicBetaPvE"].cooldowns.s18560.ready = now + 999
    db.chars["Purr Know - ClassicBetaPvE"].cooldowns.transmute.ready = now + 999
    start({ db = db })
    Mock.advance(10)
    equal(printed("Ready:"), false)

    -- silenced, and kept
    ns = start({ db = account() })
    Mock.slash("cd notice off")
    check(printed("the login line is off"), table.concat(Mock.printed, " | "))
    equal(ns.db.cooldownNotice, false)
    local again = start({ db = ns.db })
    Mock.advance(10)
    equal(printed("Ready:"), false, "off stays off")
    Mock.slash("cd notice on")
    check(printed("the login line is on"))
    equal(again.db.cooldownNotice, nil)
    Mock.slash("cd notice")
    equal(again.db.cooldownNotice, nil, "asking changes nothing")
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: '/akr cd' lists every character's cooldowns; a right-click hides one for that character - out of the tab, the list and the login line - and the Hidden list brings it back", function()
    local now = 1700000000 + 1000
    local db = { schema = 2, chars = {
        ["Purr Smith - ClassicBetaPvE"] = { learned = { [MOONCLOTH] = 1 }, skills = {}, profs = { tailoring = true }, side = "A", options = {},
            cooldowns = { s18560 = { ready = now + 7200 + 10, at = now - 500 } } },
    } }
    local ns = start({ db = db }, alchemist)
    Mock.advance(10)
    Mock.slash("cd")
    check(printed("cooldowns of all your characters:"), table.concat(Mock.printed, " | "))
    local text = Mock.plain(table.concat(Mock.printed, "\n"))
    check(text:find("Transmute - Purr Gola: ready", 1, true), text)
    check(text:find("Mooncloth - Purr Smith: in 2h", 1, true), text)
    check(Mock.slash("help") == nil and printed("/akr cd"), "the command is in the help")

    cooldownTab(ns)
    ns:SetOption("filter", "missing")
    check(cdCard(ns, "Mooncloth", "Purr Smith"), "whatever the filter, short of Hidden")
    cdCard(ns, "Mooncloth", "Purr Smith").hide()
    equal(cdCard(ns, "Mooncloth", "Purr Smith"), nil, "hidden")
    check(cdCard(ns, "Transmute", "Purr Gola"), "the others stay")
    equal(db.chars["Purr Smith - ClassicBetaPvE"].cooldownsHidden.s18560, true)
    check(Mock.info():find("1 hidden", 1, true), Mock.info())
    Mock.printed = {}
    Mock.slash("cd")
    equal(printed("Mooncloth"), false, "not in the list")
    ns:SetOption("filter", "hidden")
    local hidden = cdCard(ns, "Mooncloth", "Purr Smith")
    check(hidden and hidden.hidden == true, "in the Hidden list")
    equal(cdCard(ns, "Transmute", "Purr Gola"), nil)
    hidden.hide()
    equal(db.chars["Purr Smith - ClassicBetaPvE"].cooldownsHidden.s18560, nil, "shown again")
    equal(Mock.plain(ns.Window:Lines()[1].note), "Nothing is hidden here. A right-click hides a cooldown you do not care about.")
    ns:SetOption("filter", "all")
    check(cdCard(ns, "Mooncloth", "Purr Smith"))
    -- everything hidden: the tab says where they went
    for _, entry in ipairs(ns.Window:Lines()) do if entry.hide then entry.hide() end end
    equal(Mock.plain(ns.Window:Lines()[1].note), "Every cooldown is hidden - the Hidden list has them.")

    -- nobody has one
    start()
    Mock.advance(10)
    Mock.slash("cd")
    check(printed("no cooldown to watch on any of your characters yet"), table.concat(Mock.printed, " | "))
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: a row of their own under the profession tabs (the user, 2026-11-18: \"i was thinking CDs would be distinguished from the list maybe in its own row or a tab or something\") - how many are ready and the next one due, always in view; a click opens them all, a second click goes back; it is not one of the tabs", function()
    local now = 1700000000 + 1000
    local db = { schema = 2, chars = {
        ["Purr Smith - ClassicBetaPvE"] = { learned = { [MOONCLOTH] = 1 }, skills = {}, profs = { tailoring = true }, side = "A", options = {},
            cooldowns = { s18560 = { ready = now + 30 * 3600, at = now - 500 } } },
        ["Purr Know - ClassicBetaPvE"] = { learned = { [ARCANITE] = 1 }, skills = {}, profs = { alchemy = true }, side = "A", options = {} },
        ["Purr Salt - OtherRealm"] = { learned = {}, skills = {}, profs = { leatherworking = true }, side = "A", options = {},
            cooldowns = { salt = { ready = now - 50, at = now - 90000 } } },
        ["Purr Wait - ClassicBetaPvE"] = { learned = { [ARCANITE] = 1 }, skills = {}, profs = { alchemy = true }, side = "A", options = {},
            cooldowns = { transmute = { ready = now + 5 * 3600, at = now - 500 } } },
    } }
    local ns, state = start({ db = db })
    Mock.advance(10)
    ns.Window:Show()
    local before = ns.Window.totals.prof
    check(before ~= "cooldowns", "the window opens on a profession")
    local words, hint = strip(ns)
    equal(words, "Cooldowns: 1 ready - next Transmute (Purr Wait) 5h - 1 not read yet")
    equal(hint, "show all")
    check(not has(ns.Window.totals.offered, "cooldowns"), "not among the profession tabs")
    equal(ns.Window.widgets.tabs.cooldowns, nil, "and no tab button of that name")
    equal(listTop(ns), 93, "the cards start under the row")

    -- a click opens every cooldown; no profession tab is the pressed one; where the window opens next
    -- time stays a profession
    ns.Window.widgets.cooldowns:Click()
    equal(ns.Window.totals.prof, "cooldowns")
    check(cdCard(ns, "Mooncloth", "Purr Smith"), "the cards")
    words, hint = strip(ns)
    equal(words, "Cooldowns: 1 ready - next Transmute (Purr Wait) 5h - 1 not read yet", "the row stays")
    equal(hint, "back to " .. ns.Lookup.ProfessionName(before))
    for key, tab in pairs(ns.Window.widgets.tabs) do
        if tab:IsShown() then check(tab:IsEnabled(), key .. " can be clicked") end
    end
    check(ns.cdb.options.prof ~= "cooldowns", "not where the window opens next time")
    -- a second click goes back to where you were
    ns.Window.widgets.cooldowns:Click()
    equal(ns.Window.totals.prof, before)
    equal(select(2, strip(ns)), "show all")
    check(not ns.Window.widgets.tabs[before]:IsEnabled(), "its tab is the pressed one again")
    -- a profession's tab leaves the cooldowns just as well
    ns.Window.widgets.cooldowns:Click()
    ns.Window:SetProfession("alchemy")
    equal(ns.Window.totals.prof, "alchemy")
    equal(select(2, strip(ns)), "show all")
    ns.Window.widgets.cooldowns:Click()
    equal(select(2, strip(ns)), "back to Alchemy", "back is where you came from this time")
    ns.Window:SetProfession("cooldowns") -- asked for again while it is open: where you were is kept
    ns.Window.widgets.cooldowns:Click()
    equal(ns.Window.totals.prof, "alchemy")
    check(ns.Window.totals.offered[1] ~= "alchemy", "(not simply the first tab)")

    -- five hours on the transmute is over: the next one due is the Mooncloth
    state.now = state.now + 5 * 3600
    ns.Window:Render()
    equal((strip(ns)), "Cooldowns: 2 ready - next Mooncloth (Purr Smith) 1d 1h - 1 not read yet")
    -- hidden ones are not counted
    db.chars["Purr Salt - OtherRealm"].cooldownsHidden = { salt = true }
    db.chars["Purr Wait - ClassicBetaPvE"].cooldownsHidden = { transmute = true }
    ns.Window:Render()
    equal((strip(ns)), "Cooldowns: none ready - next Mooncloth (Purr Smith) 1d 1h - 1 not read yet")
    db.chars["Purr Smith - ClassicBetaPvE"].cooldownsHidden = { s18560 = true }
    ns.Window:Render()
    equal((strip(ns)), "Cooldowns: not read yet - log in on Purr Know once", "one character to visit: named")
    db.chars["Purr Know - ClassicBetaPvE"].cooldownsHidden = { transmute = true }
    ns.Window:Render()
    equal((strip(ns)), "Cooldowns: all hidden", "the row stays: the Hidden list is behind it")
    ns.Window.widgets.cooldowns:Click()
    equal(Mock.plain(ns.Window:Lines()[1].note), "Every cooldown is hidden - the Hidden list has them.")
    ns.Window.widgets.cooldowns:Click()
    db.chars["Purr Salt - OtherRealm"].cooldownsHidden = nil
    ns.Window:Render()
    equal((strip(ns)), "Cooldowns: 1 ready", "nothing running, nothing to visit")

    -- a window that the earlier build left on the cooldowns opens on them, and back is the first tab
    ns.Window.prof, ns.Window.before = nil, nil
    ns:SetOption("prof", "cooldowns")
    ns.Window:Render()
    equal(ns.Window.totals.prof, "cooldowns")
    equal(select(2, strip(ns)), "back")
    ns.Window.widgets.cooldowns:Click()
    equal(ns.Window.totals.prof, ns.Window.totals.offered[1])
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: transmutes the game answers for separately are shown separately (the user, 2026-11-18: \"i know legionite and arcanite have different cooldowns\" - \"Separate cooldowns\"; the client's tables say one shared cooldown) - each transmute is kept by itself, the ones with the same time are one card, and all ready they are one \"Transmute\" again", function()
    local LEGIONITE = 1317279
    local ns, state = start(nil, function(state)
        alchemist(state)
        state.learned[LEGIONITE] = true
    end)
    Mock.advance(10)
    cooldownTab(ns)
    local function names()
        local out = {}
        for _, entry in ipairs(ns.Window:Lines()) do
            if entry.card then out[#out + 1] = Mock.plain(entry.text) .. " [" .. tostring(entry.skill) .. "]" end
        end
        return table.concat(out, "; ")
    end
    equal(names(), "Transmute [Ready]; Transmute: Iron to Gold [Ready]", "all ready: one Transmute card, as before")
    local saved = ns.db.chars[ns.characterKey].cooldowns
    check(saved.transmute.each[ARCANITE] <= time() and saved.transmute.each[LEGIONITE] <= time() and saved.transmute.each[AIR_TO_FIRE] <= time(),
        "each known transmute is kept by itself")
    equal(saved.transmute.each[17560], nil, "not one that is not known")
    equal(saved.s11479.each, nil, "a cooldown of one spell needs none of that")

    -- an Arcanite Bar is made, and the game puts ONLY Arcanite on cooldown
    local made = time()
    Mock.cooldownAlone(ARCANITE, TWO_DAYS, TWO_DAYS)
    Mock.advance(2)
    equal(saved.transmute.each[ARCANITE], made + TWO_DAYS)
    check(saved.transmute.each[LEGIONITE] <= made, "Legionite is ready, since when it was")
    equal(saved.transmute.ready, made + TWO_DAYS, "the cooldown as a whole: its longest")
    equal(ns.Cooldowns:Describe().raw.transmute.disagree, true, "'/akr diag' says the transmutes did not answer as one")
    equal(ns.Cooldowns:Describe().raw.s11479.disagree, false, "a cooldown of one spell cannot")
    equal(names(), "Transmute: Iron to Gold [Ready]; Transmute: Legionite, Air to Fire [Ready]; Transmute: Arcanite [1d 23h]",
        "Arcanite by itself, the two that are ready together")
    equal((strip(ns)), "Cooldowns: 2 ready - next Transmute: Arcanite (Purr Gola) 1d 23h")
    local arcanite = cdCard(ns, "Transmute: Arcanite", "Purr Gola")
    equal(Mock.plain(arcanite.right), "Ready in 1d 23h"); equal(arcanite.item, 12360, "the Arcanite Bar's tooltip")
    equal(Mock.plain(arcanite.desc), "Alchemy - 1d 23h")
    local others = cdCard(ns, "Transmute: Legionite, Air to Fire", "Purr Gola")
    equal(others.state, "known"); equal(others.item, 251290, "the first of them")
    equal(Mock.plain(others.desc), "Alchemy - 2 crafts, up to 1d 23h")
    -- opened: only its own transmutes, and why it stands alone
    arcanite.click()
    arcanite = cdCard(ns, "Transmute: Arcanite", "Purr Gola")
    local text = {}
    for _, d in ipairs(arcanite.details) do text[#text + 1] = Mock.plain(d.text) .. " | " .. Mock.plain(d.right) end
    check(has(text, "Transmute: Arcanite | 1d 23h"), table.concat(text, "\n"))
    check(not has(text, "Transmute: Air to Fire | 23h") and not has(text, "Transmute: Legionite | 1d 23h"), "not the others': " .. table.concat(text, "\n"))
    check(has(text, "The game answers for this apart from your other transmutes. | "), table.concat(text, "\n"))
    check(not has(text, "Making any of these starts it, for that one's length: | "), "that is the shared cooldown's line")
    equal(cdCard(ns, "Transmute: Legionite, Air to Fire", "Purr Gola").details, nil, "the other card stays closed")
    arcanite.click()
    -- a change to one transmute that leaves the longest as it is redraws the window all the same
    Mock.cooldownAlone(AIR_TO_FIRE, 3600, 3600)
    Mock.advance(2)
    check(has(Mock.rows(), "Transmute: Air to Fire  1h"), table.concat(Mock.rows(), "\n"))
    Mock.cooldownAlone(AIR_TO_FIRE, 0, 0)
    Mock.advance(2)
    check(has(Mock.rows(), "Transmute: Legionite, Air to Fire  Ready"), table.concat(Mock.rows(), "\n"))

    -- three hours on a Legionite Bar is made too: three times, three cards, the soonest first
    Mock.advance(3 * 3600)
    Mock.cooldownAlone(LEGIONITE, TWO_DAYS, TWO_DAYS)
    Mock.advance(2)
    equal(names(), "Transmute: Air to Fire [Ready]; Transmute: Iron to Gold [Ready]; Transmute: Arcanite [1d 20h]; Transmute: Legionite [1d 23h]")
    equal((strip(ns)), "Cooldowns: 2 ready - next Transmute: Arcanite (Purr Gola) 1d 20h")
    Mock.printed = {}
    Mock.slash("cd")
    local report = Mock.plain(table.concat(Mock.printed, "\n"))
    check(report:find("Transmute: Arcanite - Purr Gola: in 1d 20h", 1, true) and report:find("Transmute: Legionite - Purr Gola: in 1d 23h", 1, true), report)
    check(report:find("Transmute: Air to Fire - Purr Gola: ready", 1, true), report)
    equal(ns.Cooldowns:ReadyWords(), "Ready: Transmute: Air to Fire (Purr Gola)", "the login line names the one that is ready")
    -- the search finds a part by its own name; a right-click hides the transmutes of that character as one
    ns.Window.query = "legionite"
    equal(names(), "Transmute: Legionite [1d 23h]")
    ns.Window.query = ""
    cdCard(ns, "Transmute: Legionite", "Purr Gola").hide()
    equal(names(), "Transmute: Iron to Gold [Ready]", "hidden together")
    ns.db.chars[ns.characterKey].cooldownsHidden = nil

    -- the game answering as one again (an essence transmute puts all three on 23 hours): one card
    Mock.advance(TWO_DAYS)
    equal(names(), "Transmute [Ready]; Transmute: Iron to Gold [Ready]", "all over: one Transmute card again")
    Mock.cooldown(AIR_TO_FIRE, 82800, 82800)
    Mock.advance(2)
    equal(names(), "Transmute: Iron to Gold [Ready]; Transmute [23h]")
    equal(ns.Cooldowns:Describe().raw.transmute.disagree, false)
    equal(Mock.plain(cdCard(ns, "Transmute", "Purr Gola").desc), "Alchemy - one cooldown for all 12 of them, up to 1d 23h")

    -- a part that is ready is named at login by its own length: a ten-minute transmute is not worth a line
    local short = start(nil, function(state)
        state.skills[ALCHEMY] = { level = 300, max = 300 }
        state.learned[ARCANITE], state.learned[25146] = true, true
    end)
    Mock.advance(10)
    Mock.cooldownAlone(ARCANITE, TWO_DAYS, TWO_DAYS)
    Mock.advance(2)
    equal(short.Cooldowns:ReadyWords(), nil, "Elemental Fire alone is ready: nothing to say")

    -- what an earlier build saved (no time per transmute) is one card until it is read again
    local now = time()
    local old = start({ db = { schema = 2, chars = {
        ["Purr Wait - ClassicBetaPvE"] = { learned = { [ARCANITE] = 1, [LEGIONITE] = 1 }, skills = {}, profs = { alchemy = true }, side = "A", options = {},
            cooldowns = { transmute = { ready = now + 5 * 3600, at = now - 500 } } },
    } } })
    Mock.advance(10)
    cooldownTab(old)
    check(cdCard(old, "Transmute", "Purr Wait"), "one card")
    equal(#Mock.errors, 0)
end)

scenario("the search box has an X that empties it (the user, 2026-11-18: \"can we also add an X to cancel/clear search on training/recipes\") - shown only while something is searched for; a click lists everything again", function()
    local ns = start()
    ns.Window:Show()
    local clear, search = ns.Window.widgets.clear, ns.Window.widgets.search
    check(clear and not clear:IsShown(), "nothing typed: no X")
    local all = #Mock.cards()
    check(all > 1, "cards to search")
    search:SetText("zzz")
    equal(#Mock.cards(), 0)
    check(clear:IsShown(), "typed: the X is there")
    clear:Click()
    equal(search:GetText(), "", "the box is empty")
    equal(ns.Window.query, "")
    equal(#Mock.cards(), all, "everything is listed again")
    check(not clear:IsShown(), "and the X is gone")
    check(not ns.Window.widgets.note:IsShown(), "no 'Nothing matches'")
    check(ns.Window.window:IsShown(), "the window stays open")
    -- a click with nothing typed changes nothing
    clear:Click()
    equal(#Mock.cards(), all)
    -- typing, emptying by hand: the X follows
    search:SetText("stew")
    check(clear:IsShown())
    search:SetText("")
    check(not clear:IsShown())
    equal(#Mock.errors, 0)
end)

scenario("cooldowns: the window follows - a cooldown read while the tab is open redraws it; the report for '/akr diag' holds what the client said", function()
    local ns, state = start(nil, alchemist)
    Mock.advance(10)
    cooldownTab(ns)
    equal(cdCard(ns, "Transmute", "Purr Gola").skill, "Ready")
    Mock.cooldown(ARCANITE, 82800, 82800)
    Mock.advance(2)
    check(has(Mock.rows(), "Transmute  23h"), table.concat(Mock.rows(), "\n"))
    local report = ns.Cooldowns:Describe()
    check(report.reads >= 2 and report.notice == true)
    equal(report.raw.transmute.answers[1].id, ARCANITE)
    equal(report.raw.transmute.answers[1].duration, 82800)
    equal(report.raw.transmute.disagree, false, "every transmute answered the same, as the client's tables have it")
    check(report.saved.transmute.ready > time())
    -- the other tabs are what they were
    ns.Window:SetProfession("alchemy")
    equal(ns.Window.totals.prof, "alchemy")
    check(Mock.info():find("Alchemy recipes known", 1, true), Mock.info())
    equal(#Mock.errors, 0)
end)

scenario("a recipe only some trainers teach names them: Red Mageweave Bag is the Master Tailors' and Meilosh's, not a city trainer's", function()
    local RED_BAG, MAGEWEAVE_BAG = 12079, 12065
    local function tailor(faction)
        local ns = start({ faction = faction }, function(state)
            state.skill = { level = 0, max = 0 }
            state.skills[TAILORING] = { level = 300, max = 300 }
        end)
        Mock.slash("show all")
        ns.Window.widgets.tabs.tailoring:Click()
        return ns
    end
    local function open(ns, name)
        ns.Window.open = {}
        cardNamed(ns, name).click()
        return cardNamed(ns, name), Mock.rows()
    end

    -- the Horde's Master Tailor, then Meilosh, who teaches both sides
    local ns = tailor("Horde")
    local bag, rows = open(ns, "Red Mageweave Bag")
    equal(Mock.plain(bag.right), "Trainer: Daryl Stack, Hillsbrad Foothills, 65s  (+1 more)")
    equal(Mock.plain(bag.tags), "Trainer")
    check(has(rows, "Not every Tailoring trainer teaches it - only these: | 65s"), table.concat(rows, "\n", 1, 10))
    check(has(rows, "Trainer: Daryl Stack, Hillsbrad Foothills | Master Tailor"))
    check(has(rows, "Trainer: Meilosh, Felwood | Timbermaw Hold"))
    check(not has(rows, "Timothy Worthington"), "the Alliance's Master Tailor is no use to the Horde")
    check(not has(rows, "Any Tailoring trainer teaches it."), "the card still says any trainer")
    equal(ns.Lookup.Summary(ns.Lookup.BySpell(RED_BAG), "H"), "trainer: Hillsbrad Foothills")
    -- a trainer's own window still gives the price
    Mock.trainer({ { name = "Red Mageweave Bag", cost = 6000 } })
    bag, rows = open(ns, "Red Mageweave Bag")
    equal(Mock.plain(bag.right), "Trainer: Daryl Stack, Hillsbrad Foothills, 60s  (+1 more)")
    check(has(rows, "Not every Tailoring trainer teaches it - only these: | 60s (seen at a trainer)"))
    -- the bag below it is everybody's
    bag, rows = open(ns, "Mageweave Bag")
    equal(Mock.plain(bag.right), "Any Tailoring trainer, 50s")
    check(has(rows, "Any Tailoring trainer teaches it. | 50s"))
    equal(ns.Lookup.Summary(ns.Lookup.BySpell(MAGEWEAVE_BAG), "H"), "trainer")
    -- the search finds it by a teacher's name, zone and title
    for _, words in ipairs({ "meilosh", "felwood", "master tailor", "daryl" }) do
        ns.Window.widgets.search:SetText(words)
        check(pcall(cardNamed, ns, "Red Mageweave Bag"), "searching " .. words .. " does not find the bag")
        check(not pcall(cardNamed, ns, "Linen Bag"), "searching " .. words .. " lists a recipe any trainer teaches")
    end
    ns.Window.widgets.search:SetText("timothy")
    check(not pcall(cardNamed, ns, "Red Mageweave Bag"), "the other side's trainer found it")
    ns.Window.widgets.search:SetText("")
    -- chat names them too
    Mock.printed = {}
    Mock.slash("find red mageweave bag")
    check(printed("only Daryl Stack, Hillsbrad Foothills or Meilosh, Felwood"), table.concat(Mock.printed, "\n"))

    -- the Alliance's
    ns = tailor("Alliance")
    bag, rows = open(ns, "Red Mageweave Bag")
    equal(Mock.plain(bag.right), "Trainer: Timothy Worthington, Dustwallow Marsh, 65s  (+1 more)")
    check(has(rows, "Trainer: Timothy Worthington, Dustwallow Marsh | Master Tailor"))
    check(has(rows, "Trainer: Meilosh, Felwood | Timbermaw Hold"))
    check(not has(rows, "Daryl Stack"))

    -- the table: the recipes a city's Artisan trainer lacks, each with somebody for either side
    local named, byProfession = {}, {}
    for _, key in ipairs(KEYS) do
        for _, recipe in ipairs(ns.Lookup.Recipes(key)) do
            if recipe.teachers then
                byProfession[key] = byProfession[key] or {}
                table.insert(byProfession[key], recipe.name)
                if key == "tailoring" then named[#named + 1] = recipe.name end
                check(recipe.trainer, recipe.name .. ": teachers without a trainer")
                for _, side in ipairs({ "A", "H" }) do
                    check(#ns.Lookup.Sources(recipe, side).teachers > 0, recipe.name .. ": nobody teaches the " .. side .. " side")
                end
                for _, teacher in ipairs(recipe.teachers) do
                    check(type(teacher.npc) == "string" and type(teacher.zone) == "string", recipe.name .. ": a teacher without a name or zone")
                end
            end
        end
    end
    table.sort(named)
    equal(table.concat(named, ", "), "Black Mageweave Boots, Black Mageweave Headband, Black Mageweave Shoulders, Bolt of Runecloth, "
        .. "Cindercloth Boots, Dreamweave Circlet, Red Mageweave Bag, Runecloth Belt, Simple Black Dress")
    equal(ns.Lookup.Sources(ns.Lookup.BySpell(MAGEWEAVE_BAG), "A").teachers, nil)
    -- Alchemy's, Blacksmithing's, Leatherworking's and Engineering's Master trainers have theirs; the professions not read yet have none
    table.sort(byProfession.alchemy); table.sort(byProfession.blacksmithing)
    equal(table.concat(byProfession.alchemy, ", "), "Arcane Elixir, Draught of Detect Demon, Draught of Detect Undead, Dreamless Sleep Potion, "
        .. "Elixir of Greater Agility, Elixir of Greater Intellect, Stonescale Oil")
    equal(table.concat(byProfession.blacksmithing, ", "), "Arcanite Rod, Arcanite Skeleton Key, Big Black Mace, Dense Grinding Stone, "
        .. "Dense Sharpening Stone, Dense Weightstone, Heavy Mithril Boots, Heavy Mithril Breastplate, Mithril Coif")
    table.sort(byProfession.leatherworking)
    equal(table.concat(byProfession.leatherworking, ", "), "Cured Rugged Hide, Nightscape Boots, Nightscape Pants, Rugged Armor Kit, Rugged Leather, "
        .. "Turtle Scale Helm, Turtle Scale Leggings")
    table.sort(byProfession.engineering)
    equal(table.concat(byProfession.engineering, ", "), "Dense Blasting Powder, Dense Dynamite, Green Lens, Hi-Explosive Bomb, Mithril Gyro-Shot, "
        .. "Rose Colored Goggles, Salt Shaker")
    -- Enchanting has three tiers: ten enchants are the Master's alone, 24 more the Artisan Enchanters' as well
    equal(#byProfession.enchanting, 34)
    equal(ns.Lookup.Sources(ns.Lookup.BySpell(13626), "A").teachers, nil, "Enchant Chest - Minor Stats is a city trainer's too")
    -- Mining and Cooking: a city's trainer has everything; First Aid's top bandages are the Triage doctors', as in Classic
    for _, key in ipairs({ "cooking", "mining" }) do
        equal(byProfession[key], nil, key .. ": every trainer teaches everything")
    end
    table.sort(byProfession.firstaid)
    equal(table.concat(byProfession.firstaid, ", "), "Heavy Mageweave Bandage, Heavy Runecloth Bandage, Runecloth Bandage")
    check(ns.Lookup.BySpell(18630).classic, "the doctors are Classic's: the card has to say so")
    check(not ns.Lookup.BySpell(12079).classic, "the Master Tailors were read for Forever")
    -- what a trainer's list was read to hold is no guess; what none holds still is
    for spell, guess in pairs({ [1230643] = false, [1230117] = false, [1249637] = false, [1244645] = true, [1247741] = true }) do
        equal(ns.Lookup.BySpell(spell).unsure == true, guess, "spell " .. spell)
    end
    local function names(spell, side)
        local list = {}
        for _, teacher in ipairs(ns.Lookup.Sources(ns.Lookup.BySpell(spell), side).teachers) do
            list[#list + 1] = teacher.npc .. " (" .. teacher.zone .. ", " .. (teacher.title or teacher.faction) .. ")"
        end
        return table.concat(list, "; ")
    end
    local STONESCALE_OIL, ARCANITE_ROD, RUGGED_LEATHER = 17551, 20201, 22331
    equal(names(18630, "H"), "Doctor Gregory Victor (Arathi Highlands, Trauma Surgeon)")
    equal(names(18630, "A"), "Doctor Gustaf VanHowzen (Dustwallow Marsh, Trauma Surgeon)")
    equal(names(17181, "A"), "Annora (Uldaman, Master Enchanter)") -- Enchanted Leather
    equal(names(17181, "H"), names(17181, "A"))
    equal(names(13693, "A"), "Kitta Firewind (Elwynn Forest, Artisan Enchanter); Annora (Uldaman, Master Enchanter)") -- Enchant Weapon - Striking
    equal(names(13693, "H"), "Hgarth (Stonetalon Mountains, Artisan Enchanter); Annora (Uldaman, Master Enchanter)")
    equal(names(19567, "A"), "Buzzek Bracketswing (Tanaris, Master Engineer); Kaylaena Springwhisper (Mount Hyjal, Cenarion Circle)") -- Salt Shaker
    equal(names(19567, "H"), names(19567, "A"), "both of Engineering's teach either side")
    equal(names(RUGGED_LEATHER, "H"), "Hahrana Ironhide (Feralas, Master Leatherworker)")
    equal(names(RUGGED_LEATHER, "A"), "Drakk Stonehand (The Hinterlands, Master Leatherworking Trainer)")
    equal(names(STONESCALE_OIL, "H"), "Rogvar (Swamp of Sorrows, Master Alchemist); Master Mycologist Shurome (Felwood, Emerald Circle)")
    equal(names(STONESCALE_OIL, "A"), "Kylanna Windwhisper (Feralas, Master Alchemist); Master Mycologist Shurome (Felwood, Emerald Circle)")
    equal(names(ARCANITE_ROD, "H"), "Brikk Keencraft (Stranglethorn Vale, Master Blacksmith)")
    equal(names(ARCANITE_ROD, "A"), names(ARCANITE_ROD, "H"), "Booty Bay's smith teaches both sides")
    -- one trainer alone: named, with nothing "more" behind him
    local smith = start({ faction = "Horde" }, function(state)
        state.skill = { level = 0, max = 0 }
        state.skills[BLACKSMITHING] = { level = 300, max = 300 }
    end)
    Mock.slash("show all")
    smith.Window.widgets.tabs.blacksmithing:Click()
    local rod, rodRows = open(smith, "Arcanite Rod")
    equal(Mock.plain(rod.right), "Trainer: Brikk Keencraft, Stranglethorn Vale, 1g")
    check(has(rodRows, "Not every Blacksmithing trainer teaches it - only these: | 1g"))
    check(has(rodRows, "Trainer: Brikk Keencraft, Stranglethorn Vale | Master Blacksmith"))
    ns = smith
    -- Meilosh teaches the rank Artisan as well
    local artisan = {}
    for _, trainer in ipairs(ns.Lookup.Training("tailoring").ranks[4].trainers) do
        artisan[#artisan + 1] = trainer.npc .. "/" .. trainer.zone .. "/" .. (trainer.side or "-")
    end
    equal(table.concat(artisan, " "), "Daryl Stack/Hillsbrad Foothills/H Timothy Worthington/Dustwallow Marsh/A Meilosh/Felwood/-")
    equal(#Mock.errors, 0)
end)

Mock.realPrint("")
Mock.realPrint(passed .. " passed, " .. #failures .. " failed")
if #failures > 0 then
    os.exit(1)
end
