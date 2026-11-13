-- Guild: who in your guild - everyone who has AKForeverRecipes too - knows a recipe.
--
-- WHY. The user, 2026-11-11: "make AKForeverRecipes work across your guild so it shows you who in the guild
-- (who also has AKForeverRecipes) has what stuff". Chosen with the user:
--   * a card says who in the guild knows it - their names, or how many when more than three ("if more than
--     like 3 people can make it just show how many"); the opened card lists everyone, with their skill and
--     whether they are online; a recipe you are missing that the guild knows is tagged "Guild";
--   * every character of yours is shared, not just the one logged in (your bank alt may be the crafter);
--   * what a guildmate shared is remembered, so offline people still show ("last seen"); somebody who
--     leaves the guild is dropped;
--   * on for everyone; '/akr share off' stops both sharing and seeing.
--
-- HOW. Addon messages over GUILD - measured on Forever (AKForeverSelfGrouper's probe, 2026-10-01): a guild
-- addon message comes back in 0.2-0.8 s. The wire (prefix AKFR, fields split by ';'):
--   R;1                         roll call: "say what you have" - sent once at login
--   H;1;<fp>;<character>        hello: a character of the sender's account and the fingerprint of its
--                               recipes and skills - one per character, at login, after a roll call, and
--                               when something changed
--   Q;<fp>;<character>          request: "send me that character" - from whoever's copy differs; one is
--                               enough, the others hear it and wait for the answer
--   D;<fp>;<i>;<n>;<character>;<payload>
--                               the character, in n parts to the whole guild: part 1 the faction and the
--                               professions with their skill ("A,cooking:184:225,..."), the others the
--                               recipe spell ids, 4 characters each
-- Nothing goes out faster than one message a second; a throttled or locked-down message waits and goes again.
-- The receiver checks the fingerprint of what it put together before keeping it.
--
-- FRIENDS (Friends.lua) speak the same words one to one; their messages go through this file's queue too, so
-- that the one-a-second pace holds for everything AKForeverRecipes sends.
local _, ns = ...

local Guild = {}
ns.Guild = Guild

local Lookup = ns.Lookup
local readable = ns.ReadableString

local PREFIX = "AKFR"
local WIRE = "1"
local SEND_GAP = 1.0          -- seconds between two messages of ours
local RETRY_AFTER = 5         -- a throttled / locked-down message goes again this much later
local START_AFTER = 8         -- seconds after login before the first word (the guild roster settles)
local ANSWER_SPREAD = { 2, 12 } -- a roll call is answered after a random wait in this range
local REQUEST_SPREAD = { 1, 4 } -- a request waits this long first: somebody else may ask
local DUMP_COOLDOWN = 30      -- one character is sent at most once in this long
local HELLO_AFTER_CHANGE = 30 -- a change is told this much later (changes come in bunches)
local REQUEST_GIVE_UP = 60    -- an unanswered request may be asked again after this
local MAX_MESSAGE = 250
local SHOW_NAMES = 3          -- more who know it than this: the card says how many

Guild.stats = { sent = 0, heard = 0, hellosSent = 0, requestsSent = 0, dumpsSent = 0, taken = 0, badFingerprint = 0,
    retried = 0, refused = 0, lastResult = "nothing sent yet", pruned = 0 }

------------------------------------------------------------------------
-- Packing
------------------------------------------------------------------------
local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
local VALUE = {}
for i = 1, #DIGITS do
    VALUE[string.sub(DIGITS, i, i)] = i - 1
end

local function pack4(number)
    local out = {}
    for i = 4, 1, -1 do
        local digit = number % 64
        out[i] = string.sub(DIGITS, digit + 1, digit + 1)
        number = math.floor(number / 64)
    end
    return table.concat(out)
end

-- the numbers in a string of 4-character groups; nil when it is not one
local function unpack4(text)
    if type(text) ~= "string" or #text % 4 ~= 0 then
        return nil
    end
    local list = {}
    for at = 1, #text, 4 do
        local number = 0
        for i = at, at + 3 do
            local digit = VALUE[string.sub(text, i, i)]
            if not digit then
                return nil
            end
            number = number * 64 + digit
        end
        list[#list + 1] = number
    end
    return list
end
Guild.pack4, Guild.unpack4 = pack4, unpack4

local function fingerprint(spells, meta)
    local hash = 5381
    for _, spell in ipairs(spells) do
        hash = (hash * 33 + spell) % 2147483647
    end
    for i = 1, #meta do
        hash = (hash * 33 + string.byte(meta, i)) % 2147483647
    end
    return pack4(hash % 16777216) .. pack4(#spells % 16777216)
end

-- a character of ours as the wire carries it: sorted spells, the meta part, the fingerprint
local function describeOwn(key)
    local profile = ns.db and ns.db.chars[key]
    if type(profile) ~= "table" then
        return nil
    end
    local spells = {}
    for spell in pairs(type(profile.learned) == "table" and profile.learned or {}) do
        if type(spell) == "number" and spell > 0 and spell < 16777216 then
            spells[#spells + 1] = spell
        end
    end
    table.sort(spells)
    local parts = { (profile.side == "A" or profile.side == "H") and profile.side or "-" }
    for _, prof in ipairs(Lookup.Professions()) do
        if type(profile.profs) == "table" and profile.profs[prof] then
            local skill = type(profile.skills) == "table" and profile.skills[prof] or nil
            local level = type(skill) == "table" and tonumber(skill.skill) or 0
            local max = type(skill) == "table" and tonumber(skill.max) or 0
            parts[#parts + 1] = prof .. ":" .. math.floor(level) .. ":" .. math.floor(max)
        end
    end
    local meta = table.concat(parts, ",")
    return { spells = spells, meta = meta, fp = fingerprint(spells, meta) }
end

-- "A,cooking:184:225" -> side, { [prof] = { skill, max } }
local function readMeta(meta)
    local side, skills = nil, {}
    for piece in string.gmatch(meta or "", "[^,]+") do
        if not side then
            side = piece
        else
            local prof, level, max = string.match(piece, "^([%a]+):(%d+):(%d+)$")
            if prof and Lookup.Profession(prof) then
                skills[prof] = { skill = tonumber(level), max = tonumber(max) }
            end
        end
    end
    return side, skills
end

------------------------------------------------------------------------
-- Where we are
------------------------------------------------------------------------
function Guild:Sharing()
    return not (ns.db and ns.db.share == false)
end

local function myName()
    return ns.characterKey and ns.Known.ShortName(ns.characterKey) or nil
end

-- "Name-Realm" or "Name" -> "Name"
local function short(name)
    if type(name) ~= "string" then
        return nil
    end
    return (string.gsub(name, "%-[^%s]*$", ""))
end

-- the guild's key ("Guild Name - Realm"), or nil out of a guild
function Guild:Key()
    if type(GetGuildInfo) ~= "function" or not ns.characterKey then
        return nil
    end
    local name = readable((GetGuildInfo("player")))
    if not name or name == "" then
        return nil
    end
    local realm = string.match(ns.characterKey, " %- (.+)$") or "?"
    return name .. " - " .. realm
end

-- the remembered characters of the guild we are in: [character key] = entry
function Guild:Store()
    local key = self:Key()
    if not key or not ns.db then
        return nil
    end
    ns.db.guilds = ns.db.guilds or {}
    local store = ns.db.guilds[key]
    if type(store) ~= "table" then
        store = { chars = {} }
        ns.db.guilds[key] = store
    end
    store.chars = type(store.chars) == "table" and store.chars or {}
    return store.chars
end

------------------------------------------------------------------------
-- Sending: one message a second, through a queue
------------------------------------------------------------------------
local queue, pumping, lastSent = {}, false, nil
local RESULT = { throttle = 3, channelThrottle = 8, notInGuild = 10, lockdown = 11 }
if type(Enum) == "table" and type(Enum.SendAddonMessageResult) == "table" then
    local e = Enum.SendAddonMessageResult
    RESULT.throttle = e.AddonMessageThrottle or RESULT.throttle
    RESULT.channelThrottle = e.ChannelThrottle or RESULT.channelThrottle
    RESULT.notInGuild = e.NotInGuild or RESULT.notInGuild
    RESULT.lockdown = e.AddOnMessageLockdown or RESULT.lockdown
end

local function after(seconds, fn)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(seconds, function()
            ns.SafeCall(fn)
        end)
    end
end

local function spread(range)
    return range[1] + math.random() * (range[2] - range[1])
end

-- drops the waiting messages that go to this channel
local function dropChannel(channel)
    local kept = {}
    for _, message in ipairs(queue) do
        if message.channel ~= channel then
            kept[#kept + 1] = message
        end
    end
    queue = kept
end

-- one message out: the client's result (0 = sent), or "raised" / "missing"
local function sendOne(message)
    if message.channel == "BN" then
        -- a Battle.net friend: no result comes back from this one
        if type(BNSendGameData) ~= "function" then
            return "missing"
        end
        local ok = pcall(BNSendGameData, message.target, PREFIX, message.text)
        return ok and 0 or "raised"
    end
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if type(send) ~= "function" then
        return "missing"
    end
    local ok, result = pcall(send, PREFIX, message.text, message.channel, message.target)
    return ok and result or "raised"
end

local function pump()
    local message = queue[1]
    if not message then
        pumping = false
        return
    end
    local result = sendOne(message)
    Guild.stats.lastResult = tostring(result)
    if result == "missing" then
        table.remove(queue, 1)
        after(0, pump)
        return
    end
    if result == RESULT.throttle or result == RESULT.channelThrottle or result == RESULT.lockdown or result == "raised" then
        Guild.stats.retried = Guild.stats.retried + 1
        message.tries = (message.tries or 0) + 1
        if message.tries > 6 then
            table.remove(queue, 1) -- (a friend who went offline meanwhile: let it go)
        end
        after(RETRY_AFTER, pump)
        return
    end
    table.remove(queue, 1)
    if result == RESULT.notInGuild and message.channel == "GUILD" then
        dropChannel("GUILD")
        Guild.stats.refused = Guild.stats.refused + 1
        if #queue == 0 then
            pumping = false
        else
            after(SEND_GAP, pump)
        end
        return
    end
    Guild.stats.sent = Guild.stats.sent + 1
    lastSent = GetTime()
    if #queue > 0 then
        after(SEND_GAP, pump)
    else
        pumping = false
    end
end

local function push(message)
    queue[#queue + 1] = message
    if not pumping then
        pumping = true
        local wait = lastSent and (lastSent + SEND_GAP - GetTime()) or 0
        if wait > 0 then
            after(wait, pump)
        else
            pump()
        end
    end
end

local function enqueue(text)
    if not Guild:Sharing() or not Guild:Key() then
        return
    end
    push({ text = text, channel = "GUILD" })
end

-- for Friends.lua: a message to one person - channel "WHISPER" (target: a name) or "BN" (target: a Battle.net
-- game account id)
function Guild:SendTo(text, channel, target)
    if not self:Sharing() or target == nil then
        return
    end
    push({ text = text, channel = channel, target = target })
end

------------------------------------------------------------------------
-- What we say
------------------------------------------------------------------------
local lastDump = {}   -- [character key] = when it was last sent
local dumpQueued = {} -- [character key] = true while its parts wait in the queue

function Guild:SayHello(key)
    local own = describeOwn(key)
    if own then
        enqueue("H;" .. WIRE .. ";" .. own.fp .. ";" .. key)
        Guild.stats.hellosSent = Guild.stats.hellosSent + 1
    end
end

-- every character of ours with a profession
function Guild:SayAll()
    for _, key in ipairs(ns.Known:Characters()) do
        if #ns.Known:ProfessionsOf(ns.Known:Profile(key)) > 0 then
            self:SayHello(key)
        end
    end
end

function Guild:SendCharacter(key)
    local own = describeOwn(key)
    if not own or dumpQueued[key] then
        return
    end
    local now = GetTime()
    if lastDump[key] and now - lastDump[key] < DUMP_COOLDOWN then
        return
    end
    lastDump[key] = now
    local payloads = { own.meta }
    local header = "D;" .. own.fp .. ";99;99;" .. key .. ";"
    local per = math.max(1, math.floor((MAX_MESSAGE - #header) / 4))
    local chunk = {}
    for _, spell in ipairs(own.spells) do
        chunk[#chunk + 1] = pack4(spell)
        if #chunk == per then
            payloads[#payloads + 1] = table.concat(chunk)
            chunk = {}
        end
    end
    if #chunk > 0 then
        payloads[#payloads + 1] = table.concat(chunk)
    end
    for index, payload in ipairs(payloads) do
        enqueue("D;" .. own.fp .. ";" .. index .. ";" .. #payloads .. ";" .. key .. ";" .. payload)
    end
    Guild.stats.dumpsSent = Guild.stats.dumpsSent + 1
    -- the parts are in the queue: a request heard meanwhile needs nothing more
    dumpQueued[key] = true
    after(#payloads * SEND_GAP + 1, function()
        dumpQueued[key] = nil
    end)
end

------------------------------------------------------------------------
-- What we hear
------------------------------------------------------------------------
local requests = {}  -- [character key] = { fp, at, asked }: a request waiting or sent
local assembly = {}  -- [character key .. fp] = { n, parts, got, from, at }
local index = nil    -- [spell] = { character keys } of the guild we are in, built when asked

local function changed()
    index = nil
    ns:Fire("GUILD_CHANGED")
end

local function wantCharacter(key, fp)
    local pending = requests[key]
    if pending and pending.fp == fp and GetTime() - pending.at < REQUEST_GIVE_UP then
        return -- asked already (by us or somebody else)
    end
    requests[key] = { fp = fp, at = GetTime() }
    local mine = requests[key]
    after(spread(REQUEST_SPREAD), function()
        if requests[key] ~= mine or mine.heard then
            return -- somebody asked first, or the answer is on its way
        end
        local store = Guild:Store()
        local entry = store and store[key]
        if entry and entry.fp == fp then
            return
        end
        mine.asked = true
        enqueue("Q;" .. fp .. ";" .. key)
        Guild.stats.requestsSent = Guild.stats.requestsSent + 1
    end)
end

local function take(key, fp, from, parts)
    local side, skills = readMeta(parts[1])
    local packed = table.concat(parts, "", 2)
    local spells = unpack4(packed)
    if not spells then
        Guild.stats.badFingerprint = Guild.stats.badFingerprint + 1
        return
    end
    if fingerprint(spells, parts[1]) ~= fp then
        Guild.stats.badFingerprint = Guild.stats.badFingerprint + 1
        return
    end
    local store = Guild:Store()
    if not store then
        return
    end
    local entry = store[key] or {}
    entry.fp, entry.side, entry.skills, entry.spells = fp, side, skills, packed
    entry.via, entry.at, entry.seen = from, time(), time()
    store[key] = entry
    requests[key] = nil
    Guild.stats.taken = Guild.stats.taken + 1
    ns:Log("guild_taken", { key = key, from = from, recipes = #spells })
    changed()
end

local handlers = {}

handlers.R = function(fields)
    if fields[2] ~= WIRE then
        return
    end
    after(spread(ANSWER_SPREAD), function()
        Guild:SayAll()
    end)
end

handlers.H = function(fields, from)
    local wire, fp, key = fields[2], fields[3], fields[4]
    if wire ~= WIRE or not fp or not key then
        return
    end
    local store = Guild:Store()
    if not store then
        return
    end
    local entry = store[key]
    if entry and entry.fp == fp then
        entry.via, entry.seen = from, time()
        return
    end
    wantCharacter(key, fp)
end

handlers.Q = function(fields)
    local fp, key = fields[2], fields[3]
    if not fp or not key then
        return
    end
    if ns.db.chars[key] then
        local own = describeOwn(key)
        if own and own.fp == fp then
            Guild:SendCharacter(key)
        elseif own then
            Guild:SayHello(key) -- they asked for an older copy: here is what it is now
        end
        return
    end
    -- somebody else asked for it: the answer will serve us too
    local pending = requests[key]
    if pending and pending.fp == fp then
        pending.heard = true
    elseif not pending then
        requests[key] = { fp = fp, at = GetTime(), heard = true }
    end
end

handlers.D = function(fields, from)
    local fp, i, n, key, payload = fields[2], tonumber(fields[3]), tonumber(fields[4]), fields[5], fields[6] or ""
    if not fp or not i or not n or not key or i < 1 or i > n or n > 200 then
        return
    end
    local pending = requests[key]
    if pending and pending.fp == fp then
        pending.heard = true
    end
    local store = Guild:Store()
    local entry = store and store[key]
    if entry and entry.fp == fp then
        return -- we have this one
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

-- "R;1" -> { "R", "1" }; the payload of a D is the sixth field and has no ';' in it
local function split(text)
    local fields = {}
    for field in string.gmatch(text .. ";", "([^;]*);") do
        fields[#fields + 1] = field
    end
    return fields
end

function Guild:Hear(prefix, text, channel, sender)
    prefix, text, channel, sender = readable(prefix), readable(text), readable(channel), readable(sender)
    if prefix ~= PREFIX or channel ~= "GUILD" or not text or not sender or not self:Sharing() then
        return
    end
    local from = short(sender)
    if from == myName() then
        return -- our own words come back to us
    end
    Guild.stats.heard = Guild.stats.heard + 1
    local fields = split(text)
    local key = fields[1] == "D" and fields[5] or fields[1] == "H" and fields[4] or fields[1] == "Q" and fields[3] or nil
    if key and ns.db.chars[key] and fields[1] ~= "Q" then
        return -- a character of this account: we know it better
    end
    local handler = handlers[fields[1]]
    if handler then
        handler(fields, from)
    end
end

------------------------------------------------------------------------
-- The roster: who is online, who is still in the guild
------------------------------------------------------------------------
Guild.roster = nil -- [short name] = online (true / false), nil before the first read

function Guild:ReadRoster()
    if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        return
    end
    local count = ns.ReadableNumber((GetNumGuildMembers()))
    if not count or count <= 0 then
        return
    end
    local roster = {}
    for i = 1, count do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = short(readable(name))
        if name then
            roster[name] = (not ns.IsSecret(online)) and online and true or false
        end
    end
    Guild.roster = roster
    self:Prune()
end

-- drops the characters of people no longer in the guild - only when the roster plainly is the guild's:
-- this character is in it (so its names are written the way ours are)
function Guild:Prune()
    local roster, store, me = Guild.roster, self:Store(), myName()
    if not roster or not store or not me or roster[me] == nil then
        return
    end
    local dropped = 0
    for key, entry in pairs(store) do
        local via = type(entry) == "table" and entry.via
        if roster[ns.Known.ShortName(key)] == nil and (not via or roster[via] == nil) then
            store[key] = nil
            dropped = dropped + 1
        end
    end
    if dropped > 0 then
        Guild.stats.pruned = Guild.stats.pruned + dropped
        changed()
    end
end

------------------------------------------------------------------------
-- Answers for the window
------------------------------------------------------------------------
local function buildIndex()
    index = {}
    local store = Guild:Store()
    for key, entry in pairs(store or {}) do
        if type(entry) == "table" and not ns.db.chars[key] then
            for _, spell in ipairs(unpack4(entry.spells) or {}) do
                local list = index[spell]
                if not list then
                    list = {}
                    index[spell] = list
                end
                list[#list + 1] = key
            end
        end
    end
end

-- who in the guild knows a recipe: { { key, name, online, via, viaOnline, seen, skill, max } }, online
-- first, then by skill
function Guild:Who(recipe)
    if not self:Sharing() then
        return {}
    end
    if not index then
        buildIndex()
    end
    local keys = index[recipe.spell]
    if not keys then
        return {}
    end
    local store, roster = self:Store() or {}, Guild.roster or {}
    local list = {}
    for _, key in ipairs(keys) do
        local entry = store[key]
        if entry then
            local name = ns.Known.ShortName(key)
            local skill = type(entry.skills) == "table" and entry.skills[recipe.prof]
            list[#list + 1] = {
                key = key, name = name, online = roster[name] == true,
                via = entry.via, viaOnline = entry.via ~= name and roster[entry.via] == true,
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

Guild.SHOW_NAMES = SHOW_NAMES

-- the wire, for Friends.lua
Guild.wire = { PREFIX = PREFIX, WIRE = WIRE, MAX_MESSAGE = MAX_MESSAGE, SEND_GAP = SEND_GAP, describeOwn = describeOwn,
    readMeta = readMeta, fingerprint = fingerprint, split = split, short = short, myName = myName, after = after,
    spread = spread }

-- "online", "online as Name", "seen 3 d ago"
function Guild.When(person)
    if person.online then
        return "online"
    end
    if person.viaOnline then
        return "online as " .. person.via
    end
    if type(person.seen) == "number" then
        local ago = time() - person.seen
        if ago < 3600 then
            return "seen " .. math.max(1, math.floor(ago / 60)) .. " min ago"
        elseif ago < 86400 then
            return "seen " .. math.floor(ago / 3600) .. " h ago"
        end
        return "seen " .. math.floor(ago / 86400) .. " d ago"
    end
    return "offline"
end

function Guild:Describe()
    local store, count, players = self:Store(), 0, {}
    for _, entry in pairs(store or {}) do
        count = count + 1
        if type(entry) == "table" and entry.via then
            players[entry.via] = true
        end
    end
    local playerCount = 0
    for _ in pairs(players) do
        playerCount = playerCount + 1
    end
    local rosterSize = 0
    for _ in pairs(Guild.roster or {}) do
        rosterSize = rosterSize + 1
    end
    return { guild = self:Key() or false, sharing = self:Sharing(), characters = count, players = playerCount,
        rosterSize = rosterSize, meInRoster = Guild.roster and myName() and Guild.roster[myName()] ~= nil or false,
        queue = #queue, stats = Guild.stats }
end

function Guild:QueueLength()
    return #queue
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

-- asks the client for a fresh roster (it answers with GUILD_ROSTER_UPDATE) and reads what it has now
function Guild:AskRoster()
    if not self:Key() then
        return
    end
    if C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" then
        pcall(C_GuildInfo.GuildRoster)
    end
    self:ReadRoster()
end

local started = false
local function start()
    if started or not Guild:Sharing() or not Guild:Key() then
        return
    end
    started = true
    Guild:AskRoster()
    enqueue("R;" .. WIRE)
    Guild:SayAll()
end

ns:Listen("LOGIN", function()
    after(START_AFTER, start)
end)

ns:On("PLAYER_GUILD_UPDATE", function()
    index = nil
    if ns.characterKey then
        after(2, start) -- joined a guild after login
    end
end)

ns:On("GUILD_ROSTER_UPDATE", function()
    Guild:ReadRoster()
end)

ns:On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    Guild:Hear(prefix, text, channel, sender)
    if ns.Friends then
        ns.Friends:Hear(prefix, text, channel, sender)
    end
end)

-- something of ours changed: told once things have settled
local helloToken = 0
ns:Listen("KNOWN_CHANGED", function()
    if not started or not ns.characterKey then
        return
    end
    helloToken = helloToken + 1
    local token = helloToken
    after(HELLO_AFTER_CHANGE, function()
        if token == helloToken then
            Guild:SayHello(ns.characterKey)
        end
    end)
end)

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns:RegisterCommand("share", "'/akr share on | off': share your characters' recipes with your guild and friends and see theirs (on by default)", function(rest)
    local word = string.lower(rest or "")
    if word == "off" then
        ns.db.share = false
        queue = {}
        changed()
        ns:Print("sharing is off: your recipes are not sent, and your guild's and friends' are not shown.")
    elseif word == "on" then
        ns.db.share = nil
        changed()
        start()
        if ns.Friends then
            ns.Friends:Start()
        end
        ns:Print("sharing is on (guild and friends).")
    else
        ns:Print("sharing is " .. (Guild:Sharing() and "on" or "off") .. ". '/akr share on' or '/akr share off'.")
    end
end)

ns:RegisterCommand("guild", "who in your guild shares recipes", function()
    local info = Guild:Describe()
    if not info.sharing then
        ns:Print("guild sharing is off ('/akr share on').")
        return
    end
    if not info.guild then
        ns:Print("you are not in a guild.")
        return
    end
    ns:Print(info.guild .. ": " .. info.characters .. " character(s) of " .. info.players .. " guildmate(s) with AKForeverRecipes.")
    local store, lines = Guild:Store() or {}, {}
    for key, entry in pairs(store) do
        local profs = {}
        for prof, skill in pairs(type(entry.skills) == "table" and entry.skills or {}) do
            profs[#profs + 1] = Lookup.ProfessionName(prof) .. " " .. tostring(skill.skill)
        end
        table.sort(profs)
        local name = ns.Known.ShortName(key)
        lines[#lines + 1] = name .. (entry.via and entry.via ~= name and (" (" .. entry.via .. ")") or "") .. ": " .. (#profs > 0 and table.concat(profs, ", ") or "no profession")
    end
    table.sort(lines)
    for _, line in ipairs(lines) do
        print("   " .. line)
    end
end)
