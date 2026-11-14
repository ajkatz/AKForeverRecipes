-- AKForeverRecipes core: namespace, safe calls, event dispatch, message bus, saved variables, session
-- log and slash commands.
--
-- The mission of this addon family, built for the WoW: Forever game mode: minimalistic UI additions that
-- bring out the utility Blizzard's UI does not give - minimal in nature, no Lua errors, always smooth. So:
-- nothing runs on a timer of its own, every entry point goes through ns.SafeCall, and every error is kept
-- for /akr diag.
--
-- What this addon is for: Blizzard's profession windows list the recipes you have. This addon knows every
-- recipe of every crafting profession, which of them each of your characters has, and where the rest come
-- from.
--
-- House rules: it only READS - the client's answer to "is this recipe learned", the profession skills, a
-- merchant's wares while their window is open. Nothing of Blizzard's is hooked, re-parented or hidden; the
-- window is ours alone; whatever the client hands over may be a secret value and is checked before it is
-- looked at.
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (getMetadata and getMetadata(ADDON_NAME, "Version")) or "dev"
if string.find(ns.version, "@", 1, true) then
    ns.version = "dev" -- a working copy: the packager has not replaced the @project-version@ token
end
ns.version = (string.gsub(ns.version, "^v", ""))

local PRINT_PREFIX = "|cffffb347AKForeverRecipes|r: "

function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    print(PRINT_PREFIX .. table.concat(parts, " "))
end

------------------------------------------------------------------------
-- Secret values. WoW: Forever runs the Midnight-era API, where some values handed to addons may be
-- held but not inspected.
------------------------------------------------------------------------
local issecret = type(issecretvalue) == "function" and issecretvalue or nil

function ns.IsSecret(value)
    if issecret then
        return issecret(value) and true or false
    end
    return false
end

function ns.AnySecret(...)
    for i = 1, select("#", ...) do
        if ns.IsSecret((select(i, ...))) then
            return true
        end
    end
    return false
end

-- The results of a getter as a list - or nil when the call failed or any result is secret.
function ns.Readable(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok or ns.AnySecret(a, b, c, d, e, f) then
        return nil
    end
    return { a, b, c, d, e, f }
end

-- A string the addon may look at: not nil, not empty, not a secret value.
function ns.ReadableString(value)
    if ns.IsSecret(value) or type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

-- A number the addon may look at.
function ns.ReadableNumber(value)
    if ns.IsSecret(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

------------------------------------------------------------------------
-- Safe calls: every distinct error is kept for /akr diag.
------------------------------------------------------------------------
ns.errors = {}

local function onError(err)
    err = tostring(err)
    local seen = ns.errors[err]
    ns.errors[err] = (seen or 0) + 1
    if not seen then
        local handler = geterrorhandler and geterrorhandler()
        if handler then
            handler(err)
        end
    end
    return err
end

function ns.SafeCall(fn, ...)
    return xpcall(fn, onError, ...)
end

------------------------------------------------------------------------
-- Session log (ring buffer), saved with /akr diag and on logout
------------------------------------------------------------------------
local LOG_MAX = 80
ns.sessionLog = {}

function ns:Log(kind, data)
    local log = ns.sessionLog
    log[#log + 1] = {
        t = math.floor(GetTime() * 1000) / 1000,
        k = kind,
        d = data,
    }
    if #log > LOG_MAX then
        table.remove(log, 1)
    end
end

------------------------------------------------------------------------
-- Internal message bus
------------------------------------------------------------------------
local listeners = {}

function ns:Listen(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns:Fire(message, ...)
    local list = listeners[message]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], ...)
    end
end

------------------------------------------------------------------------
-- Game events: one frame, handlers per event, every handler in a SafeCall
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
ns.unknownEvents = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        ns.SafeCall(list[i], event, ...)
    end
end)

function ns:On(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            ns.unknownEvents[event] = true
        end
    end
    table.insert(eventHandlers[event], fn)
end

-- "Interface action failed because of an AddOn": whoever is named, it is written down (every addon hears
-- the event for every addon).
ns.blockedActions = {}
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    ns:On(event, function(_, addonName, functionName)
        local entry = {
            event = event,
            addon = ns.ReadableString(addonName) or "?",
            fn = ns.ReadableString(functionName) or "?",
            combat = type(InCombatLockdown) == "function" and InCombatLockdown() and true or false,
        }
        entry.ours = entry.addon == ADDON_NAME
        if #ns.blockedActions < 20 then
            ns.blockedActions[#ns.blockedActions + 1] = entry
        end
        ns:Log("action_blocked", entry)
    end)
end

------------------------------------------------------------------------
-- Saved variables: ONE account-wide table. What a character has learned lives under
-- db.chars["First Last - Realm"], so that any character's recipes can be read from any other; what
-- merchants were seen to sell is account-wide. The account-wide part is bound at ADDON_LOADED, the
-- character's profile at PLAYER_LOGIN, when the client knows the name (bindProfile).
------------------------------------------------------------------------
local OPTION_DEFAULTS = {
    filter = "missing", -- what the window lists: "missing" | "all" | "known"
    tooltip = true,     -- a recipe item's tooltip: which of your characters can use it
}

local function squeezeRealm(realm)
    return (string.gsub(realm, "[%s%-]", ""))
end

local readable = ns.ReadableString

local function realmName()
    local realm = GetNormalizedRealmName and readable(GetNormalizedRealmName())
    if not realm and GetRealmName then
        realm = readable(GetRealmName())
        realm = realm and squeezeRealm(realm)
    end
    return realm
end

-- "First Last - Realm": the character's full name and realm - or nil while the client does not know the
-- name yet. On WoW: Forever UnitFullName("player") answers the first name and the SURNAME (where other
-- clients put the realm): whatever sits in the second slot and is not the realm is the surname.
local function characterKey()
    local name, slot
    if UnitFullName then
        name, slot = UnitFullName("player")
    end
    name = readable(name) or (UnitName and readable((UnitName("player"))))
    if not name then
        return nil
    end
    local realm = realmName()
    slot = readable(slot)
    if slot and realm and squeezeRealm(slot) ~= realm then
        name = name .. " " .. slot
    elseif slot and not realm then
        realm = squeezeRealm(slot)
    end
    if not realm then
        return nil
    end
    return name .. " - " .. realm
end

-- Missing values in `target` are filled from `source`, down into nested tables.
local function fillGaps(target, source)
    for field, value in pairs(source) do
        local existing = target[field]
        if existing == nil then
            target[field] = value
        elseif type(existing) == "table" and type(value) == "table" then
            fillGaps(existing, value)
        end
    end
end

local function bindProfile()
    local key = characterKey()
    if not key then
        ns:Log("profile", { key = false, note = "the client did not give the character's name at login" })
        return
    end
    local chars = ns.db.chars
    local cdb = chars[key]
    if type(cdb) ~= "table" then
        cdb = {}
        chars[key] = cdb
    end
    if ns.cdb and ns.cdb ~= cdb then
        fillGaps(cdb, ns.cdb)
    end
    cdb.options = cdb.options or {}
    cdb.learned = cdb.learned or {} -- [recipe spell id] = when the client first said it is learned
    cdb.skills = cdb.skills or {}   -- [profession key] = { skill, max }
    cdb.profs = cdb.profs or {}     -- [profession key] = true: the professions this character has
    ns.characterKey, ns.cdb = key, cdb
end

local function initDB()
    if type(AKForeverRecipesDB) ~= "table" then
        AKForeverRecipesDB = {}
        ns.savedStateSource = "none (first run, or the client did not load it)"
    else
        ns.savedStateSource = "client"
    end
    local db = AKForeverRecipesDB

    -- schema 1 was the cooking-only build: one skill per character, every learned recipe a cooking recipe
    if (db.schema or 2) < 2 then
        for _, cdb in pairs(type(db.chars) == "table" and db.chars or {}) do
            if type(cdb) == "table" then
                cdb.skills, cdb.profs = cdb.skills or {}, cdb.profs or {}
                if type(cdb.skill) == "number" then
                    cdb.skills.cooking = cdb.skills.cooking or { skill = cdb.skill, max = cdb.skillMax }
                end
                if type(cdb.skill) == "number" or (type(cdb.learned) == "table" and next(cdb.learned) ~= nil) then
                    cdb.profs.cooking = true
                end
                cdb.skill, cdb.skillMax = nil, nil
            end
        end
    end
    db.schema = 2
    db.loads = (db.loads or 0) + 1
    db.chars = db.chars or {}
    db.vendors = db.vendors or {} -- [recipe item id] = { [npc name] = { zone, price, side, at } }: recipes seen in a merchant's window

    ns.db = db
    ns.cdb = { options = {}, learned = {}, skills = {}, profs = {} } -- a stand-in until bindProfile, at PLAYER_LOGIN
end

function ns:GetOption(key)
    local options = ns.cdb and ns.cdb.options
    local value = options and options[key]
    if value == nil then
        return OPTION_DEFAULTS[key]
    end
    return value
end

function ns:SetOption(key, value)
    ns.cdb.options[key] = value
    ns:Fire("OPTION_CHANGED", key, value)
end

------------------------------------------------------------------------
-- Slash commands: modules register their own sub-commands; '/akr' alone opens the window
------------------------------------------------------------------------
local commands, commandOrder = {}, {}

function ns:RegisterCommand(name, help, fn)
    commands[name] = { help = help, fn = fn }
    commandOrder[#commandOrder + 1] = name
end

SLASH_AKFOREVERRECIPES1 = "/akforeverrecipes"
SLASH_AKFOREVERRECIPES2 = "/akr"
SLASH_AKFOREVERRECIPES3 = "/recipes"
SlashCmdList["AKFOREVERRECIPES"] = function(message)
    local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    local command = commands[string.lower(name or "")]
    if command then
        ns.SafeCall(command.fn, rest or "")
        return
    end
    if (name or "") == "" and ns.Window then
        ns.SafeCall(ns.Window.Toggle, ns.Window)
        return
    end
    ns:Print("v" .. ns.version .. " commands:")
    for _, commandName in ipairs(commandOrder) do
        print("   |cffffd100/akr " .. commandName .. "|r - " .. commands[commandName].help)
    end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(_, addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    initDB()
end)

ns:On("PLAYER_LOGIN", function()
    bindProfile()
    ns:Log("login", {
        version = ns.version,
        character = ns.characterKey,
        loads = ns.db and ns.db.loads,
        savedState = ns.savedStateSource,
    })
    ns:Fire("LOGIN")
end)
