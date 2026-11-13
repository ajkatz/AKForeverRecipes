-- Stand-in for the WoW client, enough to run AKForeverRecipes under a plain Lua interpreter. Same design
-- as the other addons' mocks. What it models of Blizzard's side:
--
--  * widgets: frames, buttons, a scroll frame, an edit box, font strings - only the methods the addon uses;
--  * the trade skill API's recipe info (answering, not answering, or answering with secrets), the
--    spellbook's "is this spell known", the professions' skill lines;
--  * the player (name, surname, faction), a merchant's window with item ids and prices;
--  * events, the slash command table, saved variables, the clock, one-shot timers, secret values.
--
-- The addon's files run in an environment with the game's Lua 5.1 table library (no table.unpack, a
-- global unpack), so that a 5.4-only call fails here before it fails in the game.
-- Not loaded by the game (not in the .toc).
local Mock = {}

local REAL_PRINT = print
local ADDON = "AKForeverRecipes"
local FILES = { "Core.lua", "Data.lua", "Data/Training.lua", "Data/Alchemy.lua", "Data/Blacksmithing.lua", "Data/Enchanting.lua", "Data/Engineering.lua",
    "Data/Leatherworking.lua", "Data/Tailoring.lua", "Data/Cooking.lua", "Data/FirstAid.lua", "Data/Mining.lua",
    "Lookup.lua", "Known.lua", "Guild.lua", "Friends.lua", "Locks.lua", "Window.lua", "Diagnostics.lua" }

Mock.SECRET = setmetatable({}, { __tostring = function() return "<SECRET>" end })

local function isSecret(value)
    return value == Mock.SECRET
end

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
local methods = {}
local newWidget

function methods.GetObjectType(self) return self.__kind end
function methods.SetSize(self, w, h) self.__width, self.__height = w, h end
function methods.SetWidth(self, w) self.__width = w end
function methods.SetHeight(self, h) self.__height = h end
function methods.GetWidth(self) return self.__width or 0 end
function methods.GetHeight(self) return self.__height or 0 end
function methods.SetPoint(self, point, rel, relPoint, x, y) self.__points[#self.__points + 1] = { point, rel, relPoint, x, y } end
function methods.GetPoint(self, index)
    local p = self.__points[index or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function methods.ClearAllPoints(self) self.__points = {} end
function methods.Show(self) self.__shown = true end
function methods.Hide(self) self.__shown = false end
function methods.SetShown(self, shown) self.__shown = shown and true or false end
function methods.IsShown(self) return self.__shown end
function methods.SetEnabled(self, enabled) self.__enabled = enabled and true or false end
function methods.IsEnabled(self) return self.__enabled ~= false end
function methods.SetFrameStrata(self, s) self.__strata = s end
function methods.SetClampedToScreen(self) end
function methods.SetMovable(self) end
function methods.EnableMouse(self) end
function methods.RegisterForDrag(self) end
function methods.StartMoving(self) end
function methods.StopMovingOrSizing(self) end
function methods.SetBackdrop(self, b) self.__backdrop = b end
function methods.SetBackdropColor(self) end
function methods.SetHighlightTexture(self) end
function methods.SetAutoFocus(self) end
function methods.ClearFocus(self) end
function methods.SetJustifyH(self) end
function methods.SetWordWrap(self) end
function methods.SetJustifyV(self) end
function methods.SetBackdropBorderColor(self, r, g, b) self.__border = { r, g, b } end
function methods.SetTexture(self, t) self.__texture = t end
function methods.SetTexCoord(self) end
function methods.GetStringHeight(self) local _, n = tostring(self.__text or ""):gsub("\n", ""); return 12 * (n + 1) end
function methods.CreateTexture(self, name) return newWidget("Texture", name, self) end
function methods.SetScrollChild(self, child) self.__child = child end
function methods.SetScript(self, name, fn) self.__scripts[name] = fn end
function methods.GetScript(self, name) return self.__scripts[name] end
function methods.SetText(self, t)
    self.__text = t
    if self.__kind == "EditBox" and self.__scripts.OnTextChanged then
        self.__scripts.OnTextChanged(self)
    end
end
function methods.GetText(self) return self.__text or "" end
function methods.CreateFontString(self, name, layer, font)
    local fs = newWidget("FontString", name, self)
    fs.__font = font
    return fs
end
function methods.RegisterEvent(self, event)
    -- the client refuses these to addons with a popup, not an error: the mock makes it loud
    if event == "COMBAT_LOG_EVENT_UNFILTERED" or event == "COMBAT_LOG_EVENT" then
        error("forbidden event registered: " .. event)
    end
    self.__events[event] = true
end
function methods.Click(self, mouseButton)
    if self.__scripts.OnClick then
        self.__scripts.OnClick(self, mouseButton or "LeftButton")
    end
end
function methods.RegisterForClicks(self, ...) self.__clicks = { ... } end
-- a tooltip frame: what it was asked to show
function methods.SetOwner(self, owner, anchor) self.__owner, self.__anchor, self.__tip = owner, anchor, nil end
function methods.SetItemByID(self, id) self.__tip = "item:" .. tostring(id) end
function methods.SetSpellByID(self, id) self.__tip = "spell:" .. tostring(id) end
-- the mouse over a frame, and off it
function methods.Enter(self) if self.__scripts.OnEnter then self.__scripts.OnEnter(self) end end
function methods.Leave(self) if self.__scripts.OnLeave then self.__scripts.OnLeave(self) end end

function newWidget(kind, name, parent)
    local w = setmetatable({
        __kind = kind, __name = name, __parent = parent, __points = {}, __scripts = {}, __events = {}, __shown = true,
    }, { __index = methods })
    if name then
        _G[name] = w
        Mock.named[name] = true
    end
    Mock.frames[#Mock.frames + 1] = w
    return w
end

------------------------------------------------------------------------
-- Install: a fresh client. options: db (the saved table from an earlier session), first / last (the
-- character's name), faction, version, noRecipeInfo / noSkillInfo (the client lacks that function)
------------------------------------------------------------------------
function Mock.install(options)
    options = options or {}
    for name in pairs(Mock.named or {}) do
        _G[name] = nil
    end
    Mock.named = {}
    Mock.frames, Mock.printed, Mock.errors, Mock.timers = {}, {}, {}, {}
    Mock.state = {
        now = 1000, clock = 1700000000,
        first = options.first or "Purr", last = options.last or "Gola", faction = options.faction or "Alliance",
        realm = "ClassicBetaPvE", zone = "Stormwind City",
        learned = {},      -- [spell] = true: what the character has
        infoMode = "ok",   -- GetRecipeInfo: "ok" | "nil" (no data yet) | "secret" (a secret table) | "secretField" | "error"; options.noRecipeInfo: no such function
        spellMode = "ok",  -- IsSpellKnown / IsPlayerSpell: "ok" | "false" (always false) | "secret"
        skill = { level = 1, max = 75 }, -- Cooking (skill line 185); { secret = true }: every skill line answers with secrets
        skills = {},                     -- [skill line id] = { level, max }: the other professions (164 Blacksmithing, 197 Tailoring ...)
        merchant = {}, npc = nil, items = {},
        calls = { info = 0, spell = 0 },
    }
    local state = Mock.state

    for name in pairs(Mock.globals or {}) do
        _G[name] = nil
    end
    local G = {}
    local function global(name, value)
        G[name] = value
        _G[name] = value
    end
    Mock.globals = G

    global("print", function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
    end)
    global("issecretvalue", isSecret)
    global("GetTime", function() return state.now end)
    global("time", function() return state.clock + state.now end)
    global("date", function() return "2026-11-10 12:34:56" end)
    global("geterrorhandler", function() return function(err) Mock.errors[#Mock.errors + 1] = err end end)
    global("C_AddOns", { GetAddOnMetadata = function() return options.version or "0.1.0-test" end })
    global("GetBuildInfo", function() return "1.60.1", "70700", "Nov  9 2026", 16001 end)
    global("SlashCmdList", {})
    global("CreateFrame", function(kind, name, parent) return newWidget(kind, name, parent) end)
    global("UIParent", newWidget("Frame", "UIParent"))
    global("TOOLTIP_DEFAULT_BACKGROUND_COLOR", { r = 0.09, g = 0.09, b = 0.19 })
    global("GetZoneText", function() return state.zone end)
    global("GetRealZoneText", function() return state.zone end)
    global("GetNormalizedRealmName", function() return state.realm end)
    global("GetRealmName", function() return "Classic Beta PvE" end)
    global("InCombatLockdown", function() return false end)

    global("UnitName", function(token)
        if token == "player" then return state.first end
        if token == "npc" then return state.npc end
        return nil
    end)
    global("UnitFullName", function(token)
        if token ~= "player" then return nil end
        return state.first, state.last
    end)
    global("UnitFactionGroup", function(token)
        if token ~= "player" then return nil end
        if state.faction == "secret" then return Mock.SECRET end
        return state.faction, state.faction
    end)

    -- the class (options.class, a token like "ROGUE"); the game's item tooltips (options.tooltips =
    -- { [item id] = { "line", ... } })
    state.class, state.tooltips = options.class or "MAGE", options.tooltips or {}
    global("UnitClass", function(unit) return "Class", state.class, 1 end)
    state.level = options.level or 30
    global("UnitLevel", function(unit) return state.level end)
    global("C_TooltipInfo", { GetItemByID = function(id)
        local lines = {}
        for _, text in ipairs(state.tooltips[id] or { "Locked" }) do lines[#lines + 1] = { leftText = text } end
        return { lines = lines }
    end })

    -- the trade skill API
    local tradeSkill = {
    }
    if not options.noSkillInfo then
        tradeSkill.GetProfessionInfoBySkillLineID = function(lineID)
            if state.skill.secret then
                return { professionID = lineID, skillLevel = Mock.SECRET, maxSkillLevel = Mock.SECRET, professionName = Mock.SECRET }
            end
            local skill = lineID == 185 and state.skill or state.skills[lineID] or { level = 0, max = 0 }
            return { professionID = lineID, skillLevel = skill.level, maxSkillLevel = skill.max, professionName = "line " .. lineID }
        end
    end
    if not options.noRecipeInfo then
        tradeSkill.GetRecipeInfo = function(spell)
            state.calls.info = state.calls.info + 1
            if state.infoMode == "nil" then return nil end
            if state.infoMode == "secret" then return Mock.SECRET end
            if state.infoMode == "secretField" then return { recipeID = spell, learned = Mock.SECRET } end
            if state.infoMode == "error" then error("the trade skill is not ready") end
            return { recipeID = spell, name = "recipe " .. spell, learned = state.learned[spell] and true or false }
        end
    end
    global("C_TradeSkillUI", tradeSkill)
    local function spellKnown(spell)
        state.calls.spell = state.calls.spell + 1
        if state.spellMode == "false" then return false end
        if state.spellMode == "secret" then return Mock.SECRET end
        return state.learned[spell] and true or false
    end
    global("C_SpellBook", { IsSpellKnown = spellKnown })
    global("IsPlayerSpell", spellKnown)

    -- a merchant's wares: { { id, price (copper) } }
    global("GetMerchantNumItems", function() return #state.merchant end)
    global("GetMerchantItemID", function(index)
        local item = state.merchant[index]
        if not item then return nil end
        return item.secret and Mock.SECRET or item.id
    end)
    global("GetMerchantItemInfo", function(index)
        local item = state.merchant[index]
        if not item then return nil end
        return item.name or "an item", 134400, item.price or 0, 1, -1, true, true, nil
    end)

    -- the bags and bank: [item id] = how many
    global("C_Item", { GetItemCount = function(itemID, includeBank)
        if state.bagsSecret then return Mock.SECRET end
        return state.items[itemID] or 0
    end })
    global("C_Timer", { After = function(seconds, fn) Mock.timers[#Mock.timers + 1] = { at = state.now + seconds, fn = fn } end })

    -- the guild: options.guild = its name (nil: no guild); state.roster = { { name, online } }
    state.guild, state.roster = options.guild, options.roster or {}
    Mock.sent, Mock.sendResults = {}, {} -- what went out over GUILD; results to hand back first (3 = throttled)
    global("GetGuildInfo", function(token)
        if token ~= "player" then return nil end
        return state.guild, "Member", 3
    end)
    global("GetNumGuildMembers", function() return state.guild and #state.roster or 0 end)
    global("GetGuildRosterInfo", function(index)
        local member = state.roster[index]
        if not member then return nil end
        return member.name, "Member", 3, 30, "Mage", "Stormwind City", "", "", member.online
    end)
    global("C_GuildInfo", { GuildRoster = function()
        state.rosterAsked = (state.rosterAsked or 0) + 1
        Mock.fire("GUILD_ROSTER_UPDATE")
    end })
    global("C_ChatInfo", {
        RegisterAddonMessagePrefix = function(prefix) state.prefix = prefix; return true end,
        SendAddonMessage = function(prefix, text, channel, target)
            assert(#text <= 255, "an addon message over 255 characters: " .. #text)
            local result = table.remove(Mock.sendResults, 1)
            if result and result ~= 0 then
                return result
            end
            if channel == "GUILD" and not state.guild then
                return 10
            end
            Mock.sent[#Mock.sent + 1] = { prefix = prefix, text = text, channel = channel, target = target, at = state.now }
            return 0
        end,
    })

    -- friends: options.friends = { { name, online } } (the character list); options.bnFriends =
    -- { { tag, id, character, online } } (Battle.net friends; id = the game account, character = who they play)
    state.friends, state.bnFriends = options.friends or {}, options.bnFriends or {}
    global("C_FriendList", {
        GetNumFriends = function() return #state.friends end,
        GetFriendInfoByIndex = function(i)
            local friend = state.friends[i]
            return friend and { name = friend.name, connected = friend.online } or nil
        end,
        ShowFriends = function() state.friendsAsked = (state.friendsAsked or 0) + 1 end,
    })
    global("BNGetNumFriends", function() return #state.bnFriends end)
    global("BNConnected", function() return true end)
    global("BNET_CLIENT_WOW", "WoW")
    global("C_BattleNet", { GetFriendAccountInfo = function(i)
        local friend = state.bnFriends[i]
        if not friend then return nil end
        return { battleTag = friend.tag, gameAccountInfo = friend.online and { gameAccountID = friend.id,
            isOnline = true, clientProgram = "WoW", characterName = friend.character } or {} }
    end })
    global("BNSendGameData", function(id, prefix, text)
        assert(#text <= 255, "game data over 255 characters: " .. #text)
        Mock.sent[#Mock.sent + 1] = { prefix = prefix, text = text, channel = "BN", target = id, at = state.now }
    end)

    global("AKForeverRecipesDB", options.db)

    -- the addon's files, in the TOC's order, in a 5.1-shaped environment
    local ns = {}
    local root = options.root or "."
    local gameTable = {}
    for key, value in pairs(table) do
        gameTable[key] = value
    end
    gameTable.unpack, gameTable.pack = nil, nil
    local gameEnv = setmetatable({ table = gameTable, unpack = table.unpack }, {
        __index = _G,
        __newindex = function(_, key, value)
            _G[key] = value
        end,
    })
    for _, file in ipairs(FILES) do
        local chunk, err = loadfile(root .. "/" .. file, "t", gameEnv)
        if not chunk then
            error(err)
        end
        chunk(ADDON, ns)
    end
    Mock.ns = ns
    return ns, state
end

------------------------------------------------------------------------
-- Events and the world
------------------------------------------------------------------------
function Mock.fire(event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.__events[event] and frame.__scripts.OnEvent then
            frame.__scripts.OnEvent(frame, event, ...)
        end
    end
end

function Mock.login()
    Mock.fire("ADDON_LOADED", ADDON)
    Mock.fire("PLAYER_LOGIN")
end

function Mock.runTimers()
    local due = {}
    for index = #Mock.timers, 1, -1 do
        if Mock.timers[index].at <= Mock.state.now then
            table.insert(due, 1, table.remove(Mock.timers, index))
        end
    end
    for _, timer in ipairs(due) do
        timer.fn()
    end
end

function Mock.advance(seconds)
    local left = seconds
    while left > 0 do
        local step = math.min(1, left)
        Mock.state.now = Mock.state.now + step
        left = left - step
        Mock.runTimers()
    end
end

-- the character learns a recipe: the client names it in NEW_RECIPE_LEARNED
function Mock.learn(spell, silent)
    Mock.state.learned[spell] = true
    if not silent then
        Mock.fire("NEW_RECIPE_LEARNED", spell)
    end
end

-- a merchant's window opens with these wares: { { id = 728, price = 200 } }
function Mock.merchant(items, npcName, zone)
    local state = Mock.state
    state.merchant = items or {}
    state.npc = npcName or "Kendor Kabonka"
    state.zone = zone or state.zone
    Mock.fire("MERCHANT_SHOW")
end

-- an addon message heard over GUILD from somebody
function Mock.hear(text, sender, prefix)
    Mock.fire("CHAT_MSG_ADDON", prefix or "AKFR", text, "GUILD", sender)
end

-- an addon whisper from somebody; Battle.net game data from a game account
function Mock.whisper(text, sender, prefix)
    Mock.fire("CHAT_MSG_ADDON", prefix or "AKFR", text, "WHISPER", sender)
end
function Mock.bnHear(text, account, prefix)
    Mock.fire("BN_CHAT_MSG_ADDON", prefix or "AKFR", text, "WHISPER", account)
end

-- what went to one target (a name or a game account), as texts
function Mock.sentTo(target, kind)
    local list = {}
    for _, message in ipairs(Mock.sent) do
        if message.target == target and (not kind or message.text:sub(1, #kind + 1) == kind .. ";") then
            list[#list + 1] = message.text
        end
    end
    return list
end

-- what we sent, as texts; kind: only those starting with "H;" etc.
function Mock.sentTexts(kind)
    local list = {}
    for _, message in ipairs(Mock.sent) do
        if not kind or message.text:sub(1, #kind + 1) == kind .. ";" then
            list[#list + 1] = message.text
        end
    end
    return list
end

function Mock.slash(text)
    SlashCmdList.AKFOREVERRECIPES(text)
end

local function plain(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t ?", ""))
end
Mock.plain = plain

-- the window's cards flattened to lines: a card is "name  skill | its source line", each line of an
-- opened card "text | right", a note its words
local function flat()
    local list = {}
    for _, entry in ipairs(Mock.ns.Window.lines or {}) do
        if entry.card then
            list[#list + 1] = { text = tostring(entry.text) .. "  " .. tostring(entry.skill) .. "  [" .. tostring(entry.tags or "") .. "]", right = entry.right, click = entry.click, entry = entry }
            for _, detail in ipairs(entry.details or {}) do
                list[#list + 1] = { text = detail.text, right = detail.right }
            end
        else
            list[#list + 1] = { text = entry.note, right = "" }
        end
    end
    return list
end
Mock.flat = flat

-- as plain text, colours stripped
function Mock.rows()
    local list = {}
    for _, entry in ipairs(flat()) do
        local left, right = plain(entry.text), plain(entry.right or "")
        list[#list + 1] = left .. (right ~= "" and (" | " .. right) or "")
    end
    return list
end

-- as the font strings get them, colours included
function Mock.rawRows()
    local list = {}
    for _, entry in ipairs(flat()) do
        list[#list + 1] = tostring(entry.text) .. " | " .. tostring(entry.right or "")
    end
    return list
end

-- the card frames now on screen, top to bottom: { frame, y (its top, downwards), height }
function Mock.cards()
    local list = {}
    for _, frame in ipairs(Mock.frames) do
        if frame.__kind == "Button" and frame.details and frame.__shown then
            local _, _, _, _, y = frame:GetPoint(1)
            list[#list + 1] = { frame = frame, y = -(y or 0), height = frame:GetHeight() }
        end
    end
    table.sort(list, function(a, b) return a.y < b.y end)
    return list
end

-- the index of the first row whose text contains the words, or nil
function Mock.rowIndex(text)
    for index, line in ipairs(Mock.rows()) do
        if line:find(text, 1, true) then
            return index
        end
    end
    return nil
end

function Mock.clickRow(index)
    local entry = flat()[index]
    assert(entry and entry.click, "no clickable row " .. tostring(index))
    entry.click()
end

function Mock.info()
    return plain(Mock.ns.Window.widgets.info:GetText())
end

Mock.realPrint = REAL_PRINT

return Mock
