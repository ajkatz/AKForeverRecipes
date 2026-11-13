-- Friends: who among your friends - everyone who has AKForeverRecipes too - knows a recipe.
--
-- WHY. The user, 2026-11-12: "can we make akforeverrecipes also share across friends". Chosen with the user:
--   * both kinds of friends: the character friends list and Battle.net friends in the game;
--   * friends get their own section in an opened card ("Your friends (N)") and their own tag ("Friend"),
--     apart from the guild;
--   * mutual only: we send to people on our friends list and take only from people on it - a stranger cannot
--     push anything in; '/akr share off' stops this too.
--
-- HOW. The guild's words (Guild.lua), one to one instead of to everybody, through Guild.lua's queue (one
-- message a second for all of it):
--   R;1      "here I am": sent at login to every friend online who is not in our guild (they hear it from
--            the guild already) - one message each, whether they have the addon or not
--   H;...    our characters' hellos: sent to a friend who said R, and to a friend whose first hello we hear
--            (so both sides end up knowing each other after one R)
--   Q;...    "send me that character", straight back to the one who said its hello
--   D;...    the character in parts, to the one who asked
-- A character friend is reached by a hidden addon whisper (same realm, only while online - a whisper to
-- somebody offline makes the client complain in chat), a Battle.net friend by BNSendGameData to the game
-- account they play on. Whether Battle.net game data gets through on Forever is not measured yet: /akr diag
-- counts what went each way.
local _, ns = ...

local Friends = {}
ns.Friends = Friends

local Guild = ns.Guild
local W = Guild.wire
local readable = ns.ReadableString

local START_AFTER = 10       -- seconds after login before the first word (the friends list loads)
local ANSWER_SPREAD = { 1, 4 }
local DUMP_COOLDOWN = 30     -- one character to one friend at most once in this long
local REQUEST_GIVE_UP = 60
local HELLO_AFTER_CHANGE = 30

Friends.stats = { rollCalls = 0, hellosSent = 0, requestsSent = 0, dumpsSent = 0, heard = 0, heardBN = 0,
    strangers = 0, taken = 0, badFingerprint = 0, pruned = 0 }

------------------------------------------------------------------------
-- The friends list
------------------------------------------------------------------------
-- [short name] = { online, char = on the character list, bn = game account id while in WoW, tag = BattleTag }
Friends.list = {}
Friends.byAccount = {} -- [game account id] = short name
Friends.tags = {}      -- [BattleTag] = true, every Battle.net friend (online or not)
Friends.charsLoaded, Friends.bnLoaded = false, false

local function field(info, name)
    if type(info) ~= "table" then
        return nil
    end
    local value = info[name]
    if ns.IsSecret(value) then
        return nil
    end
    return value
end

function Friends:ReadList()
    local list, byAccount, tags = {}, {}, {}
    local api = C_FriendList
    if type(api) == "table" and type(api.GetNumFriends) == "function" and type(api.GetFriendInfoByIndex) == "function" then
        local okCount, count = pcall(api.GetNumFriends)
        count = okCount and ns.ReadableNumber(count) or nil
        for i = 1, count or 0 do
            local ok, info = pcall(api.GetFriendInfoByIndex, i)
            local name = ok and W.short(readable(field(info, "name"))) or nil
            if name then
                list[name] = { online = field(info, "connected") == true, char = true }
            end
        end
        Friends.charsLoaded = count ~= nil and count > 0 -- (an empty list may be one not loaded yet)
    end
    local bn = C_BattleNet
    if type(BNGetNumFriends) == "function" and type(bn) == "table" and type(bn.GetFriendAccountInfo) == "function" then
        local okCount, count = pcall(BNGetNumFriends)
        count = okCount and ns.ReadableNumber(count) or nil
        for i = 1, count or 0 do
            local ok, account = pcall(bn.GetFriendAccountInfo, i)
            local tag = ok and readable(field(account, "battleTag")) or nil
            if tag then
                tags[tag] = true
            end
            local game = ok and field(account, "gameAccountInfo") or nil
            local id = field(game, "gameAccountID")
            local name = W.short(readable(field(game, "characterName")))
            local program = field(game, "clientProgram")
            if id and name and field(game, "isOnline") ~= false and (program == nil or program == (BNET_CLIENT_WOW or "WoW")) then
                local friend = list[name] or {}
                friend.online, friend.bn, friend.tag = true, id, tag
                list[name] = friend
                byAccount[id] = name
            end
        end
        local connected = type(BNConnected) ~= "function" or BNConnected()
        Friends.bnLoaded = count ~= nil and count > 0 and connected and true or false
    end
    Friends.list, Friends.byAccount, Friends.tags = list, byAccount, tags
    self:Prune()
end

-- in our guild: they hear everything over the guild already
local function inGuild(name)
    return Guild:Key() ~= nil and Guild.roster ~= nil and Guild.roster[name] ~= nil
end

-- a friend we can reach now, and how; nil when we cannot
local function route(name)
    local friend = Friends.list[name]
    if not friend or name == W.myName() then
        return nil
    end
    if friend.char and friend.online then
        return "WHISPER", name
    elseif friend.bn then
        return "BN", friend.bn
    end
    return nil
end

local function sendTo(name, text)
    local channel, target = route(name)
    if channel then
        Guild:SendTo(text, channel, target)
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Where we keep what friends shared: [character key] = { fp, side, skills, spells, via, tag, at, seen }
------------------------------------------------------------------------
function Friends:Store()
    if not ns.db then
        return nil
    end
    ns.db.friends = type(ns.db.friends) == "table" and ns.db.friends or {}
    ns.db.friends.chars = type(ns.db.friends.chars) == "table" and ns.db.friends.chars or {}
    return ns.db.friends.chars
end

local index = nil
local function changed()
    index = nil
    ns:Fire("FRIENDS_CHANGED")
end

-- drops the characters of people no longer on either friends list - only when that list has plainly loaded
function Friends:Prune()
    local store = self:Store()
    if not store or not Friends.charsLoaded then
        return
    end
    local dropped = 0
    for key, entry in pairs(store) do
        if type(entry) ~= "table" then
            store[key] = nil
        else
            local stillFriend
            if entry.tag then
                stillFriend = not Friends.bnLoaded or Friends.tags[entry.tag] == true
            else
                local friend = Friends.list[entry.via or ""]
                stillFriend = friend ~= nil and friend.char == true
            end
            if not stillFriend then
                store[key] = nil
                dropped = dropped + 1
            end
        end
    end
    if dropped > 0 then
        Friends.stats.pruned = Friends.stats.pruned + dropped
        changed()
    end
end

------------------------------------------------------------------------
-- What we say
------------------------------------------------------------------------
local helloed = {}  -- [name] = true: our hellos went to them this session
local lastDump = {} -- [character key .. "@" .. name] = when

local function sayAllTo(name)
    helloed[name] = true
    for _, key in ipairs(ns.Known:Characters()) do
        if #ns.Known:ProfessionsOf(ns.Known:Profile(key)) > 0 then
            local own = W.describeOwn(key)
            if own and sendTo(name, "H;" .. W.WIRE .. ";" .. own.fp .. ";" .. key) then
                Friends.stats.hellosSent = Friends.stats.hellosSent + 1
            end
        end
    end
end

local function sendCharacter(key, name)
    local own = W.describeOwn(key)
    if not own then
        return
    end
    local id, now = key .. "@" .. name, GetTime()
    if lastDump[id] and now - lastDump[id] < DUMP_COOLDOWN then
        return
    end
    lastDump[id] = now
    local payloads = { own.meta }
    local header = "D;" .. own.fp .. ";99;99;" .. key .. ";"
    local per = math.max(1, math.floor((W.MAX_MESSAGE - #header) / 4))
    local chunk = {}
    for _, spell in ipairs(own.spells) do
        chunk[#chunk + 1] = Guild.pack4(spell)
        if #chunk == per then
            payloads[#payloads + 1] = table.concat(chunk)
            chunk = {}
        end
    end
    if #chunk > 0 then
        payloads[#payloads + 1] = table.concat(chunk)
    end
    for i, payload in ipairs(payloads) do
        sendTo(name, "D;" .. own.fp .. ";" .. i .. ";" .. #payloads .. ";" .. key .. ";" .. payload)
    end
    Friends.stats.dumpsSent = Friends.stats.dumpsSent + 1
end

------------------------------------------------------------------------
-- What we hear
------------------------------------------------------------------------
local requests = {} -- [character key] = { fp, at }
local assembly = {} -- [character key .. ";" .. fp] = { n, parts, got, at }

local function take(key, fp, from, parts)
    local side, skills = W.readMeta(parts[1])
    local packed = table.concat(parts, "", 2)
    local spells = Guild.unpack4(packed)
    if not spells or W.fingerprint(spells, parts[1]) ~= fp then
        Friends.stats.badFingerprint = Friends.stats.badFingerprint + 1
        return
    end
    local store = Friends:Store()
    if not store then
        return
    end
    local entry = store[key] or {}
    entry.fp, entry.side, entry.skills, entry.spells = fp, side, skills, packed
    entry.via, entry.tag, entry.at, entry.seen = from, Friends.list[from] and not Friends.list[from].char and Friends.list[from].tag or nil, time(), time()
    store[key] = entry
    requests[key] = nil
    Friends.stats.taken = Friends.stats.taken + 1
    ns:Log("friend_taken", { key = key, from = from, recipes = #spells })
    changed()
end

local handlers = {}

handlers.R = function(fields, from)
    if fields[2] ~= W.WIRE then
        return
    end
    W.after(W.spread(ANSWER_SPREAD), function()
        sayAllTo(from)
    end)
end

handlers.H = function(fields, from)
    local wire, fp, key = fields[2], fields[3], fields[4]
    if wire ~= W.WIRE or not fp or not key then
        return
    end
    if not helloed[from] then
        sayAllTo(from) -- they have the addon: now they know ours too
    end
    local store = Friends:Store()
    local entry = store and store[key]
    if entry and entry.fp == fp then
        entry.via, entry.seen = from, time()
        return
    end
    local pending = requests[key]
    if pending and pending.fp == fp and GetTime() - pending.at < REQUEST_GIVE_UP then
        return
    end
    requests[key] = { fp = fp, at = GetTime() }
    if sendTo(from, "Q;" .. fp .. ";" .. key) then
        Friends.stats.requestsSent = Friends.stats.requestsSent + 1
    end
end

handlers.Q = function(fields, from)
    local fp, key = fields[2], fields[3]
    if not fp or not key or not ns.db.chars[key] then
        return
    end
    local own = W.describeOwn(key)
    if own and own.fp == fp then
        sendCharacter(key, from)
    elseif own then
        sendTo(from, "H;" .. W.WIRE .. ";" .. own.fp .. ";" .. key) -- an older copy: here is what it is now
    end
end

handlers.D = function(fields, from)
    local fp, i, n, key, payload = fields[2], tonumber(fields[3]), tonumber(fields[4]), fields[5], fields[6] or ""
    if not fp or not i or not n or not key or i < 1 or i > n or n > 200 then
        return
    end
    local store = Friends:Store()
    local entry = store and store[key]
    if entry and entry.fp == fp then
        return
    end
    local id = key .. ";" .. fp
    local job = assembly[id]
    if not job or job.n ~= n or GetTime() - job.at > REQUEST_GIVE_UP then
        job = { n = n, parts = {}, got = 0, at = GetTime() }
        assembly[id] = job
    end
    if job.parts[i] == nil then
        job.parts[i] = payload
        job.got = job.got + 1
    end
    if job.got == n then
        assembly[id] = nil
        take(key, fp, from, job.parts)
    end
end

local function handle(text, from)
    Friends.stats.heard = Friends.stats.heard + 1
    local fields = W.split(text)
    local kind = fields[1]
    local key = kind == "D" and fields[5] or kind == "H" and fields[4] or nil
    if key and ns.db.chars[key] then
        return -- a character of this account
    end
    local handler = handlers[kind]
    if handler then
        handler(fields, from)
    end
end

-- an addon whisper (CHAT_MSG_ADDON): only from somebody on our character friends list
function Friends:Hear(prefix, text, channel, sender)
    prefix, text, channel, sender = readable(prefix), readable(text), readable(channel), readable(sender)
    if prefix ~= W.PREFIX or channel ~= "WHISPER" or not text or not sender or not Guild:Sharing() then
        return
    end
    local from = W.short(sender)
    local friend = Friends.list[from]
    if not (friend and friend.char) then
        self:ReadList() -- (a friend added since we last looked)
        friend = Friends.list[from]
    end
    if not (friend and friend.char) then
        Friends.stats.strangers = Friends.stats.strangers + 1
        return
    end
    handle(text, from)
end

-- Battle.net game data (BN_CHAT_MSG_ADDON): only Battle.net friends can send it at all
function Friends:HearBN(prefix, text, _, account)
    prefix, text = readable(prefix), readable(text)
    if prefix ~= W.PREFIX or not text or account == nil or ns.IsSecret(account) or not Guild:Sharing() then
        return
    end
    local from = Friends.byAccount[account]
    if not from then
        self:ReadList()
        from = Friends.byAccount[account]
    end
    if not from then
        Friends.stats.strangers = Friends.stats.strangers + 1
        return
    end
    Friends.stats.heardBN = Friends.stats.heardBN + 1
    handle(text, from)
end

------------------------------------------------------------------------
-- Answers for the window
------------------------------------------------------------------------
local function buildIndex()
    index = {}
    local guildStore = Guild:Store() or {}
    for key, entry in pairs(Friends:Store() or {}) do
        -- a friend who is in the guild too shows under the guild
        if type(entry) == "table" and not ns.db.chars[key] and not guildStore[key] then
            for _, spell in ipairs(Guild.unpack4(entry.spells) or {}) do
                index[spell] = index[spell] or {}
                table.insert(index[spell], key)
            end
        end
    end
end

-- who among friends knows a recipe - shaped like Guild:Who (Guild.When reads it)
function Friends:Who(recipe)
    if not Guild:Sharing() then
        return {}
    end
    if not index then
        buildIndex()
    end
    local keys = index[recipe.spell]
    if not keys then
        return {}
    end
    local store, list = self:Store() or {}, {}
    for _, key in ipairs(keys) do
        local entry = store[key]
        if entry then
            local name = ns.Known.ShortName(key)
            local skill = type(entry.skills) == "table" and entry.skills[recipe.prof]
            local me, via = Friends.list[name], Friends.list[entry.via or ""]
            list[#list + 1] = {
                key = key, name = name, online = me ~= nil and me.online == true,
                via = entry.via, viaOnline = entry.via ~= name and via ~= nil and via.online == true,
                seen = entry.seen, skill = type(skill) == "table" and skill.skill or nil, max = type(skill) == "table" and skill.max or nil,
            }
        end
    end
    table.sort(list, function(a, b)
        local aOn, bOn = a.online or a.viaOnline, b.online or b.viaOnline
        if aOn ~= bOn then
            return aOn
        end
        if (a.skill or 0) ~= (b.skill or 0) then
            return (a.skill or 0) > (b.skill or 0)
        end
        return a.name < b.name
    end)
    return list
end

function Friends:Describe()
    local online, viaBN = 0, 0
    for _, friend in pairs(Friends.list) do
        if friend.online then online = online + 1 end
        if friend.bn then viaBN = viaBN + 1 end
    end
    local count, players = 0, {}
    for _, entry in pairs(self:Store() or {}) do
        count = count + 1
        if type(entry) == "table" and entry.via then players[entry.via] = true end
    end
    local playerCount = 0
    for _ in pairs(players) do playerCount = playerCount + 1 end
    return { sharing = Guild:Sharing(), friendsOnline = online, inWoWOnBattleNet = viaBN, characters = count,
        players = playerCount, charsLoaded = Friends.charsLoaded, bnLoaded = Friends.bnLoaded,
        hasBNSend = type(BNSendGameData) == "function", stats = Friends.stats }
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local started = false
function Friends:Start()
    if not Guild:Sharing() or not ns.characterKey then
        return
    end
    started = true
    self:ReadList()
    for name in pairs(Friends.list) do
        if route(name) and not inGuild(name) and not helloed[name] then
            if sendTo(name, "R;" .. W.WIRE) then
                Friends.stats.rollCalls = Friends.stats.rollCalls + 1
            end
        end
    end
end

ns:Listen("LOGIN", function()
    if C_FriendList and type(C_FriendList.ShowFriends) == "function" then
        pcall(C_FriendList.ShowFriends) -- asks the server for the list (FRIENDLIST_UPDATE)
    end
    W.after(START_AFTER, function()
        Friends:Start()
    end)
end)

for _, event in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED" }) do
    ns:On(event, function()
        Friends:ReadList()
    end)
end

ns:On("BN_CHAT_MSG_ADDON", function(_, prefix, text, channel, account)
    Friends:HearBN(prefix, text, channel, account)
end)

if type(C_ChatInfo) == "table" and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, W.PREFIX) -- (Guild.lua did already; harmless twice)
end

-- something of ours changed: the friends who know us hear it once things have settled
local helloToken = 0
ns:Listen("KNOWN_CHANGED", function()
    if not started or not ns.characterKey then
        return
    end
    helloToken = helloToken + 1
    local token = helloToken
    W.after(HELLO_AFTER_CHANGE, function()
        if token ~= helloToken then
            return
        end
        local own = W.describeOwn(ns.characterKey)
        if not own then
            return
        end
        for name in pairs(helloed) do
            sendTo(name, "H;" .. W.WIRE .. ";" .. own.fp .. ";" .. ns.characterKey)
        end
    end)
end)

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns:RegisterCommand("friends", "who among your friends shares recipes", function()
    if not Guild:Sharing() then
        ns:Print("sharing is off ('/akr share on').")
        return
    end
    local info = Friends:Describe()
    ns:Print(info.characters .. " character(s) of " .. info.players .. " friend(s) with AKForeverRecipes; "
        .. info.friendsOnline .. " friend(s) online now.")
    local lines = {}
    for key, entry in pairs(Friends:Store() or {}) do
        local profs = {}
        for prof, skill in pairs(type(entry.skills) == "table" and entry.skills or {}) do
            profs[#profs + 1] = ns.Lookup.ProfessionName(prof) .. " " .. tostring(skill.skill)
        end
        table.sort(profs)
        local name = ns.Known.ShortName(key)
        lines[#lines + 1] = name .. (entry.via and entry.via ~= name and (" (" .. entry.via .. ")") or "") .. ": "
            .. (#profs > 0 and table.concat(profs, ", ") or "no profession")
    end
    table.sort(lines)
    for _, line in ipairs(lines) do
        print("   " .. line)
    end
end)
