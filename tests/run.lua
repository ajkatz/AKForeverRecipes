-- Scenario tests for AKForeverCookbook: lua tests/run.lua  (from the addon's folder)
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

-- a fresh client; prepare(state) sets the world up before the character logs in
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

local function recipeNamed(ns, name)
    for _, recipe in ipairs(ns.Lookup.Recipes()) do
        if recipe.name == name then
            return recipe
        end
    end
    error("no recipe named " .. name)
end

local WESTFALL_STEW, CHARRED_WOLF, CRISPY_BAT_WING, RAPTOR_RIBS, RAPTOR_RIBS_ITEM = 2543, 2538, 15935, 1250150, 250181

------------------------------------------------------------------------
Mock.realPrint("AKForeverCookbook scenarios")

scenario("the recipe table holds every recipe once, in skill order, each with a name and usable sources", function()
    local ns = start()
    local recipes = ns.Lookup.Recipes()
    equal(#recipes, 123)
    local spells, lastSkill = {}, 0
    for _, recipe in ipairs(recipes) do
        check(type(recipe.spell) == "number" and not spells[recipe.spell], "spell twice or missing: " .. tostring(recipe.name))
        spells[recipe.spell] = true
        check(type(recipe.name) == "string" and recipe.name ~= "", "a recipe without a name")
        check(recipe.learn >= lastSkill, recipe.name .. " is out of skill order")
        lastSkill = recipe.learn
        check(recipe.learn <= recipe.yellow and recipe.yellow <= recipe.green and recipe.green <= recipe.grey, recipe.name .. ": skill colours out of order")
        for _, vendor in ipairs(recipe.vendors or {}) do
            check(vendor.npc and vendor.npc ~= "", recipe.name .. ": a vendor without a name")
            check(vendor.side == nil or vendor.side == "A" or vendor.side == "H", recipe.name .. ": a vendor of no faction")
        end
        for _, quest in ipairs(recipe.quests or {}) do
            check(quest.name and quest.name ~= "", recipe.name .. ": a quest without a name")
        end
        for _, drop in ipairs(recipe.drops or {}) do
            check(drop.npc and drop.npc ~= "", recipe.name .. ": a drop without a creature")
        end
        if recipe.recipe then
            equal(ns.Lookup.ByRecipeItem(recipe.recipe.id), recipe, recipe.name .. ": two recipes share a recipe item")
        end
    end
    local counts = ns.Lookup.Counts()
    check(counts.trainer >= 8 and counts.withVendors >= 60 and counts.new >= 40, "the table lost a kind of source")
    equal(ns.Lookup.BySpell(WESTFALL_STEW).name, "Westfall Stew")
    equal(ns.Lookup.ByRecipeItem(728).name, "Westfall Stew")
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
    equal(ns.cdb.skill, 150); equal(ns.cdb.skillMax, 225); equal(ns.cdb.side, "A")
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
        equal(ns.cdb.skill, nil); equal(ns.cdb.side, nil)
        ns.Window:Show()
        check(#Mock.rows() > 100, mode .. ": with no faction known the whole book is listed")
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
    check(ns.Known:IsLearned(WESTFALL_STEW), "an unanswered pass emptied the book")
    -- and across sessions
    ns = start({ db = AKForeverCookbookDB }, function(s)
        s.infoMode, s.spellMode = "nil", "false"
    end)
    check(ns.Known:IsLearned(WESTFALL_STEW), "the saved book was not read back")
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
    -- a recipe of another profession is none of ours
    Mock.fire("NEW_RECIPE_LEARNED", 999999)
    equal(ns.Known:Count(ns.cdb), 1)
    -- a secret recipe id is not looked at
    Mock.fire("NEW_RECIPE_LEARNED", Mock.SECRET)
    equal(ns.Known:Count(ns.cdb), 1)
end)

scenario("a burst of trade skill events is one pass over the book, half a second later", function()
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

scenario("an Alliance character sees its own faction's sources and no recipe only the Horde can get", function()
    local ns = start({ faction = "Alliance" })
    Mock.slash("show all")
    check(Mock.rowIndex("Westfall Stew"))
    check(not Mock.rowIndex("Crispy Bat Wing"), "a Horde-only recipe is listed for the Alliance")
    Mock.clickRow(Mock.rowIndex("Brilliant Smallfish"))
    local rows = Mock.rows()
    check(has(rows, "Vendor: Catherine Leland, Stormwind City | 40c"))
    check(not has(rows, "Sewa Mistrunner"), "a Thunder Bluff vendor is shown to the Alliance")
    check(has(rows, "Nyalah Brightfire"), "a vendor of no faction went missing")
    -- the Horde's book
    ns = start({ faction = "Horde" })
    Mock.slash("show all")
    check(Mock.rowIndex("Crispy Bat Wing"))
    check(not Mock.rowIndex("Kaldorei Spider Kabob"), "an Alliance-only quest recipe is listed for the Horde")
    local stew = recipeNamed(ns, "Westfall Stew")
    check(ns.Lookup.Sources(stew, "H").otherSide and not ns.Lookup.Sources(stew, "A").otherSide)
end)

scenario("a recipe of the other faction that was learned anyway is in the book", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.learned[CRISPY_BAT_WING] = true
    end)
    Mock.slash("show known")
    local index = Mock.rowIndex("Crispy Bat Wing")
    check(index, "a learned recipe is hidden")
    Mock.clickRow(index)
    check(has(Mock.rows(), "other faction"))
    check(Mock.info():find("1 of ", 1, true), Mock.info())
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
    check(not has(Mock.rows(), "Kendor Kabonka"))

    Mock.clickRow(Mock.rowIndex("Charred Wolf Meat"))
    check(has(Mock.rows(), "Any Cooking trainer teaches it."))
    Mock.clickRow(Mock.rowIndex("Peace Tea"))
    check(has(Mock.rows(), "Drop: Frostmane Seer, Dun Morogh | 7.86%"))
    Mock.clickRow(Mock.rowIndex("Venomous Smoothie"))
    check(has(Mock.rows(), "Vendor: Kalsey Sanden, Redridge Mountains | 30 Merchant's Favor"))
    Mock.clickRow(Mock.rowIndex("Goldthorn Tea"))
    check(has(Mock.rows(), "Taught by Henry Stern, Razorfen Downs."))
    check(has(Mock.rows(), "not confirmed for Forever"))
    equal(ns.Window.Money(12345), "1g 23s 45c"); equal(ns.Window.Money(0), "0c"); equal(ns.Window.Money(nil), nil)
end)

scenario("the right-hand column says known, learnable now, or needs more skill", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.skill = { level = 100, max = 150 }
        state.learned[CHARRED_WOLF] = true
    end)
    Mock.slash("show all")
    local raw = Mock.rawRows()
    local function rawRow(name)
        for _, line in ipairs(raw) do
            if Mock.plain(line):find(name, 1, true) then
                return line
            end
        end
        error("no row " .. name)
    end
    check(rawRow("Charred Wolf Meat"):find("|cff60ff60known", 1, true), "known is green")
    check(rawRow("Westfall Stew"):find("|cffffd100vendor: Stormwind City", 1, true), "skill 100 can learn a 75 recipe: yellow")
    check(rawRow("Raging Raptor Ribs"):find("|cffff8080source unknown", 1, true), "an unknown source is red")
    check(rawRow("Monster Omelet"):find("|cff9d9d9d", 1, true), "skill 100 cannot learn a 225 recipe: grey")
    check(Mock.info():find("Purr Gola: 1 of ", 1, true) and Mock.info():find("Cooking 100/150", 1, true), Mock.info())
end)

scenario("Missing, All and Known choose the list, the choice is remembered, and the search narrows it", function()
    local ns = start({ faction = "Alliance" }, function(state)
        state.learned[CHARRED_WOLF] = true
    end)
    ns.Window:Show()
    equal(ns:GetOption("filter"), "missing")
    check(not Mock.rowIndex("Charred Wolf Meat") and Mock.rowIndex("Westfall Stew"))
    ns.Window.widgets.filters.known:Click()
    equal(#Mock.rows(), 1); check(Mock.rowIndex("Charred Wolf Meat"))
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

scenario("every character's book is kept and can be read from another character", function()
    start({ first = "Purr", last = "Gola", faction = "Alliance" }, function(state)
        state.learned[WESTFALL_STEW] = true
        state.skill = { level = 120, max = 150 }
    end)
    -- a character without Cooking in between: it is not offered
    start({ db = AKForeverCookbookDB, first = "No", last = "Cook", faction = "Alliance" })
    local ns = start({ db = AKForeverCookbookDB, first = "Alt", last = "Two", faction = "Alliance" }, function(state)
        state.learned[CHARRED_WOLF] = true
        state.skill = { level = 40, max = 75 }
    end)
    equal(ns.characterKey, "Alt Two - ClassicBetaPvE")
    local characters = ns.Known:Characters()
    equal(#characters, 2); equal(characters[1], "Alt Two - ClassicBetaPvE"); equal(characters[2], "Purr Gola - ClassicBetaPvE")
    check(ns.Known:IsLearned(WESTFALL_STEW, "Purr Gola - ClassicBetaPvE") and not ns.Known:IsLearned(WESTFALL_STEW))

    Mock.slash("show all")
    check(ns.Window.widgets.character:IsShown())
    Mock.clickRow(Mock.rowIndex("Westfall Stew"))
    check(has(Mock.rows(), "Also known by: Purr Gola"))
    Mock.clickRow(Mock.rowIndex("Charred Wolf Meat"))
    check(has(Mock.rows(), "Also missing on: Purr Gola"))

    ns.Window.widgets.character:Click() -- on to Purr Gola's book
    check(Mock.info():find("Purr Gola: 1 of ", 1, true) and Mock.info():find("Cooking 120/150", 1, true), Mock.info())
    equal(ns.Window.widgets.character:GetText(), "Purr Gola")
    local stew = Mock.rows()[Mock.rowIndex("Westfall Stew")]
    check(stew:find("| known", 1, true), stew)
    ns.Window.widgets.character:Click() -- and round to the character logged in
    check(Mock.info():find("Alt Two: 1 of ", 1, true), Mock.info())
    -- alone, there is nobody to walk to
    ns = start()
    ns.Window:Show()
    check(not ns.Window.widgets.character:IsShown())
end)

scenario("a merchant selling a recipe nobody had a source for is written down for every character", function()
    local ns = start({ faction = "Alliance" })
    local ribs = ns.Lookup.BySpell(RAPTOR_RIBS)
    check(ns.Lookup.Sources(ribs, "A").unknown)
    ns.Window:Show()
    Mock.clickRow(Mock.rowIndex("Raging Raptor Ribs"))
    check(has(Mock.rows(), "Nobody has written down yet where this comes from."))
    check(has(Mock.rows(), "A merchant selling Recipe: Raging Raptor Ribs is noted"))

    Mock.merchant({ { id = 4540, price = 25 }, { id = RAPTOR_RIBS_ITEM, price = 12000 }, { secret = true } }, "Corporal Bluth", "Stranglethorn Vale")
    local rows = Mock.rows()
    check(has(rows, "Vendor: Corporal Bluth, Stranglethorn Vale  (seen by you) | 1g 20s"), table.concat(rows, "\n", 1, 20))
    check(not has(rows, "Nobody has written down"))
    equal(ns.db.vendors[RAPTOR_RIBS_ITEM]["Corporal Bluth"].side, "A")
    -- a vendor the table already names is not listed twice
    Mock.merchant({ { id = 728, price = 200 } }, "Kendor Kabonka", "Stormwind City")
    Mock.clickRow(Mock.rowIndex("Westfall Stew"))
    local count = 0
    for _, row in ipairs(Mock.rows()) do
        if row:find("Kendor Kabonka", 1, true) then count = count + 1 end
    end
    equal(count, 1)
    -- the next session, another character of the same faction
    ns = start({ db = AKForeverCookbookDB, first = "Alt", last = "Two", faction = "Alliance" })
    equal(ns.Lookup.Summary(ns.Lookup.BySpell(RAPTOR_RIBS), "A"), "vendor: Stranglethorn Vale")
    check(not ns.Lookup.Sources(ns.Lookup.BySpell(RAPTOR_RIBS), "H").any, "an Alliance vendor is offered to the Horde")
end)

scenario("'/acb find' prints the matching recipes with where they come from", function()
    start({ faction = "Alliance" }, function(state)
        state.learned[WESTFALL_STEW] = true
    end)
    Mock.slash("find westfall stew")
    check(printed("Westfall Stew (75, known): Kendor Kabonka, Stormwind City 2s; quest Westfall Stew."), table.concat(Mock.printed, "\n"))
    Mock.slash("find charred")
    check(printed("Charred Wolf Meat (1, missing): any Cooking trainer."))
    Mock.slash("find nothing-like-this")
    check(printed("nothing in the book by that name."))
    Mock.slash("find")
    check(printed("usage: /acb find"))
end)

scenario("'/acb' opens and closes the window and its place is remembered", function()
    local ns = start()
    Mock.slash("")
    check(ns.Window.window:IsShown())
    ns.Window.window:ClearAllPoints()
    ns.Window.window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -50)
    ns.Window.window:GetScript("OnDragStop")(ns.Window.window)
    equal(ns.cdb.options.window.x, 40); equal(ns.cdb.options.window.y, -50)
    Mock.slash("")
    check(not ns.Window.window:IsShown())
    ns = start({ db = AKForeverCookbookDB })
    Mock.slash("")
    local point, _, _, x, y = ns.Window.window:GetPoint(1)
    equal(point, "TOPLEFT"); equal(x, 40); equal(y, -50)
end)

scenario("the report says which way the client answered and holds no secret", function()
    start(nil, function(state)
        state.learned[WESTFALL_STEW] = true
        state.skill = { level = 80, max = 150 }
    end)
    Mock.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "UNKNOWN()")
    Mock.slash("diag")
    local diag = AKForeverCookbookDB.diag
    check(diag and diag.asked)
    equal(diag.known.lastScan.infoLearned, 1); equal(diag.known.lastScan.spellLearned, 1)
    equal(diag.client.tradeSkill.getRecipeInfo, true); equal(diag.client.faction, "Alliance")
    check(#diag.client.samples >= 3 and diag.client.samples[1].recipeInfo)
    equal(diag.known.chars["Purr Gola - ClassicBetaPvE"].skill, 80)
    equal(diag.blockedActions[1].addon, "SomeOtherAddon"); equal(diag.blockedActions[1].ours, false)
    equal(diag.data.recipes, 123)
    local function walk(value, path)
        check(value ~= Mock.SECRET, "a secret in the report at " .. path)
        if type(value) == "table" then
            for k, v in pairs(value) do
                walk(v, path .. "." .. tostring(k))
            end
        end
    end
    walk(AKForeverCookbookDB, "AKForeverCookbookDB")
    Mock.fire("PLAYER_LOGOUT")
    check(AKForeverCookbookDB.diagAtLogout, "the logout report goes beside the one asked for")
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
    check(printed("commands:") and printed("/acb find") and printed("/acb diag"))
end)

------------------------------------------------------------------------
Mock.realPrint("")
Mock.realPrint(passed .. " passed, " .. #failures .. " failed")
if #failures > 0 then
    os.exit(1)
end
