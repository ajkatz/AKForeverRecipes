-- Cooldowns: the crafts that can be made once every so often - transmutes, Mooncloth, the Salt Shaker's
-- Refined Deeprock Salt - for every character of the account, in one tab.
--
-- WHY. The user, 2026-11-17: "i'd like recipes to track cooldowns like transmutes, mooncloth, refined
-- deeprock salt per character/acccount" - chosen: ONE "Cooldowns" tab for everything, and one line in
-- chat at login when something is ready (ready ones only). 2026-11-18: "i was thinking CDs would be
-- distinguished from the list maybe in its own row or a tab or something" - so not one of the profession
-- tabs: a row of its own under them (Summary, drawn by Window), whose click opens the cards.
--
-- WHAT IS KNOWN. Which crafts have a cooldown and how long comes from the client's own tables
-- (Data/Cooldowns.lua, tools/gen_cooldowns.py). A group there is ONE cooldown: every transmute shares the
-- one "Transmute"; Iron to Gold and Mithril to Truesilver have their own hour; Mooncloth its own; the Salt
-- Shaker is an item's use and is tracked for whoever owns the item.
--
-- HOW IT IS READ. Only the character logged in can be asked: C_Spell.GetSpellCooldown for a recipe it
-- knows, C_Container.GetItemCooldown for the shaker - at login, and whenever the game says a cooldown
-- moved (SPELL_UPDATE_COOLDOWN / BAG_UPDATE_COOLDOWN; one read a moment later however many arrive, none
-- in combat, where the game keeps cooldowns secret). What is kept is the moment the cooldown is over, on
-- the wall clock (time()): from that, any other character of the account shows the time left without
-- being logged in. A character that has not logged in since this was added reads "not read yet".
--
-- UNPROVEN on Forever until seen in game: what GetSpellCooldown answers for a days-long cooldown after a
-- relog. Classic clients hand back a start time that wrapped round (2^32 ms) for a cooldown that began
-- before the session; that is undone here. '/akr diag' keeps the raw numbers (cooldowns.raw).
local _, ns = ...

local Cooldowns = {}
ns.Cooldowns = Cooldowns

Cooldowns.KEY = "cooldowns"
Cooldowns.meta = { key = "cooldowns", name = "Cooldowns", short = "CDs", icon = "inv_misc_pocketwatch_01" }
Cooldowns.raw = {} -- [group key] = what the client last said, for /akr diag

local NOT_A_COOLDOWN = 60   -- seconds: the global cooldown and the like are not a craft's cooldown
local WRAP = 4294967.296    -- 2^32 ms in seconds: the client's clock for a cooldown from before the session
local NOTICE_FROM = 20 * 3600 -- the login line names cooldowns of this length or more (not the one-hour bars)
local READ_DELAY, LOGIN_DELAY = 1.5, 6
local DISAGREE = 120        -- seconds: two spells of one cooldown this far apart are not one cooldown

local function groups()
    return type(ns.CooldownData) == "table" and ns.CooldownData.groups or {}
end

function Cooldowns.Groups()
    return groups()
end

-- the longest this cooldown can be, in seconds
function Cooldowns.Length(group)
    if group.seconds then
        return group.seconds
    end
    local longest = 0
    for _, entry in ipairs(group.spells) do
        longest = math.max(longest, entry.seconds)
    end
    return longest
end

------------------------------------------------------------------------
-- Words for a length of time
------------------------------------------------------------------------
-- "2d 3h", "14h 20m", "45m" - minutes rounded up, so that nothing reads as over before it is
function Cooldowns.Span(seconds)
    local minutes = math.ceil(seconds / 60)
    if minutes < 1 then
        minutes = 1
    end
    local days, hours = math.floor(minutes / 1440), math.floor(minutes % 1440 / 60)
    minutes = minutes % 60
    if days > 0 then
        return days .. "d" .. (hours > 0 and (" " .. hours .. "h") or "")
    elseif hours > 0 then
        return hours .. "h" .. (minutes > 0 and (" " .. minutes .. "m") or "")
    end
    return minutes .. "m"
end

-- the same for the card's corner: no minutes once there are hours
function Cooldowns.Short(seconds)
    local minutes = math.ceil(seconds / 60)
    if minutes >= 60 and minutes < 1440 then
        return math.floor(minutes / 60) .. "h"
    end
    return Cooldowns.Span(seconds)
end

------------------------------------------------------------------------
-- Asking the game (the character logged in)
------------------------------------------------------------------------
local function wallClock()
    local clock = type(time) == "function" and ns.ReadableNumber(time()) or nil
    return clock and math.floor(clock) or nil
end

-- seconds left of a cooldown the client describes by start and duration (its GetTime() clock)
local function leftOf(start, duration)
    if duration <= NOT_A_COOLDOWN then
        return 0
    end
    local now = GetTime()
    if start > now + 1 then
        start = start - WRAP -- it began before this session: the client's clock wrapped round
    end
    local left = start + duration - now
    if left <= 0 then
        return 0
    end
    return math.min(left, duration)
end

-- start, duration of a spell's cooldown - nil where the client does not say (no such call, an error, a
-- secret value)
local function spellCooldown(spell)
    local answer = ns.Readable(C_Spell and C_Spell.GetSpellCooldown, spell)
    local info = answer and answer[1]
    if type(info) == "table" then
        return ns.ReadableNumber(info.startTime), ns.ReadableNumber(info.duration)
    end
    if not answer then
        answer = ns.Readable(GetSpellCooldown, spell) -- the older call: start, duration, enabled
    end
    if answer and type(answer[1]) == "number" then
        return answer[1], ns.ReadableNumber(answer[2])
    end
    return nil
end

local function itemCooldown(item)
    local answer = ns.Readable(C_Container and C_Container.GetItemCooldown, item)
    if not answer then
        answer = ns.Readable(GetItemCooldown, item)
    end
    if answer and type(answer[1]) == "number" then
        return answer[1], ns.ReadableNumber(answer[2])
    end
    return nil
end

-- Does this cooldown belong to the character logged in? true / false; nil: the client does not say
local function mine(group)
    if group.item then
        local count = ns.Known:ItemCount(group.item)
        if count == nil then
            return nil
        end
        return count > 0
    end
    for _, entry in ipairs(group.spells) do
        if ns.Known:IsLearned(entry.spell) then
            return true
        end
    end
    return false
end

-- seconds left of a group's cooldown now (0: it is over), nil where the client said nothing
local function leftNow(group)
    local left, least, raw, each = nil, nil, {}, {}
    local function take(id, start, duration)
        raw[#raw + 1] = { id = id, start = start or false, duration = duration or false }
        if start and duration then
            local this = leftOf(start, duration)
            left = math.max(left or 0, this)
            least = math.min(least or this, this)
            each[id] = this
        end
    end
    if group.item then
        take(group.item, itemCooldown(group.item))
    else
        for _, entry in ipairs(group.spells) do
            if ns.Known:IsLearned(entry.spell) then
                take(entry.spell, spellCooldown(entry.spell))
            end
        end
    end
    -- disagree: the spells of ONE cooldown answered with different times left. The client's tables say
    -- every transmute shares one (Arcanite and Legionite both 47 hours: build 1.60.1.70959 and its
    -- hotfixes, read 2026-11-18); the user, that day: "i know legionite and arcanite have different
    -- cooldowns". Should the game ever answer so, '/akr diag' holds it here.
    Cooldowns.raw[group.key] = { at = GetTime(), left = left or false, answers = raw,
        disagree = (left ~= nil and left - least > DISAGREE) or false }
    return left, each
end

-- the moment on the wall clock a cooldown with this much left is over; one that was over already keeps
-- since when
local function moment(wall, left, was)
    if left == 0 and type(was) == "number" and was <= wall then
        return was
    end
    return wall + math.floor(left + 0.5)
end

-- Reads every cooldown of the character logged in and keeps the moment each is over. true when
-- something changed.
function Cooldowns:Read()
    local cdb, wall = ns.cdb, wallClock()
    if not cdb or not ns.characterKey or not wall then
        return false
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false -- (the game keeps cooldowns secret in combat, and nothing is crafted there)
    end
    cdb.cooldowns = type(cdb.cooldowns) == "table" and cdb.cooldowns or {}
    local changed = false
    for _, group in ipairs(groups()) do
        local owned = mine(group)
        local saved = cdb.cooldowns[group.key]
        if owned == false then
            if saved and group.item then
                cdb.cooldowns[group.key] = nil -- the shaker is gone
                changed = true
            end
        elseif owned then
            local left, each = leftNow(group)
            if left then
                local was = type(saved) == "table" and saved or {}
                local entry = { ready = moment(wall, left, was.ready), at = wall }
                if was.ready ~= entry.ready then
                    changed = true
                end
                if group.shared then
                    -- each spell of a shared cooldown by itself too: the client's tables say the
                    -- transmutes are one cooldown, the user (2026-11-18) that Legionite and Arcanite are
                    -- "separate cooldowns" - kept apart, they are shown as the game answers, whichever
                    local before = type(was.each) == "table" and was.each or {}
                    entry.each = {}
                    for spell, own in pairs(each) do
                        entry.each[spell] = moment(wall, own, before[spell])
                        if before[spell] ~= entry.each[spell] then
                            changed = true
                        end
                    end
                end
                cdb.cooldowns[group.key] = entry
            end
        end
    end
    Cooldowns.reads = (Cooldowns.reads or 0) + 1
    if changed then
        ns:Fire("COOLDOWNS_CHANGED")
    end
    return changed
end

-- one read a moment from now, however many times this is asked meanwhile
local pending = false

function Cooldowns:Queue()
    if pending then
        return
    end
    if C_Timer and type(C_Timer.After) == "function" then
        pending = true
        C_Timer.After(READ_DELAY, function()
            pending = false
            ns.SafeCall(Cooldowns.Read, Cooldowns)
        end)
    else
        Cooldowns:Read()
    end
end

------------------------------------------------------------------------
-- Every character's cooldowns
------------------------------------------------------------------------
local function knowsAny(profile, group)
    local learned = type(profile.learned) == "table" and profile.learned or {}
    for _, entry in ipairs(group.spells or {}) do
        if learned[entry.spell] ~= nil then
            return true
        end
    end
    return false
end

local function longest(spells)
    local seconds = 0
    for _, spell in ipairs(spells) do
        seconds = math.max(seconds, spell.seconds)
    end
    return seconds
end

-- A shared cooldown whose spells the game answered for with DIFFERENT times, as its parts:
-- { { left, spells (in the table's order) } }, the spells with the same time (within DISAGREE) together.
-- nil while they are one - all ready, all on the same time, or saved before each was kept.
local function parts(group, entry, wall)
    if not group.shared or type(entry.each) ~= "table" then
        return nil
    end
    local known = {}
    for index, spell in ipairs(group.spells) do
        local ready = entry.each[spell.spell]
        if type(ready) == "number" then
            known[#known + 1] = { spell = spell, index = index, left = math.max(0, ready - wall) }
        end
    end
    table.sort(known, function(a, b)
        if a.left ~= b.left then
            return a.left < b.left
        end
        return a.index < b.index
    end)
    local out = {}
    for _, item in ipairs(known) do
        local part = out[#out]
        if part and item.left - part.least <= DISAGREE then
            part.items[#part.items + 1] = item
            part.left = item.left
        else
            out[#out + 1] = { least = item.left, left = item.left, items = { item } }
        end
    end
    if #out < 2 then
        return nil
    end
    for _, part in ipairs(out) do
        table.sort(part.items, function(a, b)
            return a.index < b.index
        end)
        part.spells = {}
        for _, item in ipairs(part.items) do
            part.spells[#part.spells + 1] = item.spell
        end
    end
    return out
end

-- "Transmute: Arcanite" for one spell; "Transmute: Legionite, Air to Fire" for two; "Transmute: Legionite
-- + 3 more" beyond
local function partName(group, spells)
    if #spells == 1 then
        return spells[1].name
    end
    local prefix = group.name .. ": "
    local function short(name)
        return string.sub(name, 1, #prefix) == prefix and string.sub(name, #prefix + 1) or name
    end
    if #spells == 2 then
        return prefix .. short(spells[1].name) .. ", " .. short(spells[2].name)
    end
    return prefix .. short(spells[1].name) .. " + " .. (#spells - 1) .. " more"
end

-- { { key (the character), group, name, id (the group's key, or that and a spell for a part), spells,
-- split (a part of a shared cooldown the game answers for separately), left (seconds; 0 = ready; nil =
-- never read on that character), hidden } }: ready ones first, then the soonest, then the ones not read
-- yet; by name within each.
function Cooldowns:List()
    local list = {}
    local wall = wallClock() or 0
    for key, profile in pairs(ns.db and ns.db.chars or {}) do
        if type(profile) == "table" then
            local saved = type(profile.cooldowns) == "table" and profile.cooldowns or {}
            local hidden = type(profile.cooldownsHidden) == "table" and profile.cooldownsHidden or {}
            for _, group in ipairs(groups()) do
                local entry = saved[group.key]
                local known = type(entry) == "table" and type(entry.ready) == "number"
                if known or knowsAny(profile, group) then
                    local split = known and parts(group, entry, wall)
                    if split then
                        for _, part in ipairs(split) do
                            list[#list + 1] = { key = key, group = group, hidden = hidden[group.key] == true, left = part.left, at = entry.at,
                                name = partName(group, part.spells), id = group.key .. ":" .. part.spells[1].spell, spells = part.spells, split = true }
                        end
                    else
                        list[#list + 1] = { key = key, group = group, hidden = hidden[group.key] == true, name = group.name, id = group.key,
                            spells = group.spells, left = known and math.max(0, entry.ready - wall) or nil, at = known and entry.at or nil }
                    end
                end
            end
        end
    end
    local function rank(row)
        return (row.left == 0 and 1) or (row.left and 2) or 3
    end
    table.sort(list, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then
            return ra < rb
        end
        if ra == 2 and a.left ~= b.left then
            return a.left < b.left
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.key < b.key
    end)
    return list
end

-- the longest a row's cooldown can be, in seconds: a part's own spells', or the whole cooldown's
local function rowLength(row)
    return row.split and longest(row.spells) or Cooldowns.Length(row.group)
end

-- Is there anything to show - the window's cooldown row, and the cards behind it?
function Cooldowns.Offered()
    return #Cooldowns:List() > 0
end

-- "Ready: Transmute (Purr Gola, Purr Smith), Mooncloth (Purr Gola)" - the long cooldowns that are over on
-- any character and not hidden; nil when there is none
function Cooldowns:ReadyWords()
    local order, who = {}, {}
    for _, row in ipairs(self:List()) do
        if row.left == 0 and not row.hidden and rowLength(row) >= NOTICE_FROM then
            local name = row.name
            if not who[name] then
                who[name] = {}
                order[#order + 1] = name
            end
            table.insert(who[name], ns.Known.ShortName(row.key))
        end
    end
    if #order == 0 then
        return nil
    end
    local parts = {}
    for _, name in ipairs(order) do
        parts[#parts + 1] = name .. " (" .. table.concat(who[name], ", ") .. ")"
    end
    return "Ready: " .. table.concat(parts, ", ")
end

-- The words of the window's own row for cooldowns: "1 ready - next Transmute (Purr Wait) 5h - 1 not read
-- yet". Hidden ones are not counted; nil when no character has a cooldown at all.
function Cooldowns:Summary(colour)
    local total, ready, unread, hiddenCount = 0, 0, 0, 0
    local due, visit
    for _, row in ipairs(self:List()) do
        total = total + 1
        if row.hidden then
            hiddenCount = hiddenCount + 1
        elseif row.left == 0 then
            ready = ready + 1
        elseif row.left then
            due = due or row -- the list has the soonest first
        else
            unread = unread + 1
            visit = visit or row
        end
    end
    if total == 0 then
        return nil
    end
    if hiddenCount == total then
        return colour.dim .. "all hidden|r"
    end
    local parts = {}
    if ready > 0 then
        parts[#parts + 1] = colour.known .. ready .. " ready|r"
    elseif due then
        parts[#parts + 1] = "none ready"
    end
    if due then
        parts[#parts + 1] = "next " .. due.name .. " (" .. ns.Known.ShortName(due.key) .. ") " .. Cooldowns.Span(due.left)
    end
    if unread > 0 then
        if #parts == 0 and unread == 1 then
            parts[#parts + 1] = colour.dim .. "not read yet - log in on " .. ns.Known.ShortName(visit.key) .. " once|r"
        else
            parts[#parts + 1] = colour.dim .. unread .. " not read yet|r"
        end
    end
    return table.concat(parts, " - ")
end

function Cooldowns.NoticeOn()
    return not ns.db or ns.db.cooldownNotice ~= false
end

function Cooldowns:Notice()
    local words = Cooldowns.NoticeOn() and self:ReadyWords()
    if words then
        ns:Print(words)
    end
end

------------------------------------------------------------------------
-- The cards
------------------------------------------------------------------------
local function matches(row, query)
    if not query or query == "" then
        return true
    end
    query = string.lower(query)
    return string.find(string.lower(row.name), query, 1, true) ~= nil
        or string.find(string.lower(ns.Known.ShortName(row.key)), query, 1, true) ~= nil
        or string.find(string.lower(ns.Lookup.ProfessionName(row.group.prof) or ""), query, 1, true) ~= nil
end

local function about(row)
    local group = row.group
    local prof = ns.Lookup.ProfessionName(group.prof) or group.prof
    if row.split then
        return prof .. " - " .. (#row.spells == 1 and Cooldowns.Span(row.spells[1].seconds)
            or (#row.spells .. " crafts, up to " .. Cooldowns.Span(longest(row.spells))))
    elseif group.item then
        return prof .. " - using the " .. group.itemName .. ", " .. Cooldowns.Span(group.seconds)
    elseif group.shared then
        return prof .. " - one cooldown for all " .. #group.spells .. " of them, up to " .. Cooldowns.Span(Cooldowns.Length(group))
    end
    return prof .. " - " .. Cooldowns.Span(Cooldowns.Length(group))
end

-- cards for Window (its entry shape) and the totals; open: [character .. group key] = true for the
-- opened cards. The filter only tells hidden ones from the rest.
function Cooldowns:Lines(filter, query, open, colour, render)
    local lines = {}
    local ready, running, unread, hiddenCount, shown = 0, 0, 0, 0, 0
    for _, row in ipairs(self:List()) do
        local group = row.group
        if row.hidden then
            hiddenCount = hiddenCount + 1
        elseif row.left == 0 then
            ready = ready + 1
        elseif row.left then
            running = running + 1
        else
            unread = unread + 1
        end
        if (filter == "hidden") == row.hidden and matches(row, query) then
            shown = shown + 1
            local who = ns.Known.ShortName(row.key)
            local id = row.key .. "|" .. row.id
            local first = row.spells and row.spells[1]
            local right, corner, state, label
            if row.left == 0 then
                right, corner, state, label = colour.known .. "Ready|r", "Ready", "known", ""
            elseif row.left then
                right, corner, state, label = "Ready in " .. Cooldowns.Span(row.left), Cooldowns.Short(row.left), "later", "left"
            else
                right, corner, state, label = colour.dim .. "Not read yet - log in on " .. who .. " once|r", "?", "plain", ""
            end
            local profile = ns.db.chars[row.key]
            local entry = {
                card = true, icon = group.icon or (first and first.icon), state = state, skill = corner, skillLabel = label,
                text = colour.head .. row.name .. "|r", tags = "|cffffffff" .. who .. "|r",
                desc = colour.dim .. about(row) .. "|r", right = right,
                item = group.makes or (first and tonumber(first.item)) or nil,
                hidden = row.hidden,
                click = function()
                    open[id] = not open[id] or nil
                    render()
                end,
                hide = function()
                    profile.cooldownsHidden = type(profile.cooldownsHidden) == "table" and profile.cooldownsHidden or {}
                    profile.cooldownsHidden[group.key] = not row.hidden or nil
                    render()
                end,
            }
            if open[id] then
                local details = {}
                details[#details + 1] = { text = colour.dim .. who .. ": |r" .. (row.left == 0 and "ready"
                    or row.left and ("ready in " .. Cooldowns.Span(row.left)) or "not read yet - log in on that character once"), right = "" }
                if group.item then
                    details[#details + 1] = { text = colour.dim .. "From using the |r" .. group.itemName, right = Cooldowns.Span(group.seconds) }
                else
                    if row.split then
                        details[#details + 1] = { text = colour.dim .. "The game answers for " .. (#row.spells == 1 and "this" or "these")
                            .. " apart from your other " .. string.lower(group.name) .. "s.|r", right = "" }
                    elseif group.shared then
                        details[#details + 1] = { text = colour.dim .. "Making any of these starts it, for that one's length:|r", right = "" }
                    end
                    for _, spell in ipairs(row.spells) do
                        details[#details + 1] = { text = spell.name, right = Cooldowns.Span(spell.seconds) }
                    end
                end
                if row.at then
                    local age = math.max(0, (wallClock() or row.at) - row.at)
                    details[#details + 1] = { text = colour.dim .. "Read on " .. who .. " "
                        .. (age < 60 and "just now" or (Cooldowns.Span(age) .. " ago")) .. "|r", right = "" }
                end
                entry.details = details
            end
            lines[#lines + 1] = entry
        end
    end
    return lines, { total = ready + running + unread, ready = ready, running = running, unread = unread, hidden = hiddenCount, shown = shown }
end

-- '/akr cd': every character's cooldowns as lines of text
function Cooldowns:Report()
    local out = {}
    for _, row in ipairs(self:List()) do
        if not row.hidden then
            out[#out + 1] = row.name .. " - " .. ns.Known.ShortName(row.key) .. ": "
                .. (row.left == 0 and "|cff60ff60ready|r" or row.left and ("in " .. Cooldowns.Span(row.left)) or "not read yet")
        end
    end
    return out
end

function Cooldowns:Describe()
    return { reads = Cooldowns.reads or 0, notice = Cooldowns.NoticeOn(), raw = Cooldowns.raw,
        saved = ns.cdb and ns.cdb.cooldowns or false }
end

------------------------------------------------------------------------
-- Events and the command
------------------------------------------------------------------------
for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN" }) do
    ns:On(event, function()
        Cooldowns:Queue()
    end)
end

ns:Listen("LOGIN", function()
    local function first()
        Cooldowns:Read()
        Cooldowns:Notice()
    end
    -- a little after the recipes were read, and after the game has its cooldowns
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(LOGIN_DELAY, function()
            ns.SafeCall(first)
        end)
    else
        first()
    end
end)

ns:RegisterCommand("cd", "every character's profession cooldowns; '/akr cd notice off' silences the login line", function(rest)
    local word, value = string.match(string.lower(rest or ""), "^(%S*)%s*(%S*)")
    if word == "notice" then
        if value == "off" then
            ns.db.cooldownNotice = false
        elseif value == "on" then
            ns.db.cooldownNotice = nil
        end
        ns:Print("cooldowns: the login line is " .. (Cooldowns.NoticeOn() and "on" or "off") .. ". |cffffd100/akr cd notice on|r or |cffffd100off|r.")
        return
    end
    Cooldowns:Read()
    local lines = Cooldowns:Report()
    if #lines == 0 then
        ns:Print("no cooldown to watch on any of your characters yet - a character that knows a transmute or Mooncloth, or owns a Salt Shaker, shows here after its next login.")
        return
    end
    ns:Print("cooldowns of all your characters:")
    for _, line in ipairs(lines) do
        print("   " .. line)
    end
end)
