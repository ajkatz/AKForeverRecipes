-- Window: '/akr' - the recipes of one profession at a time, every one your faction can get, in the order
-- of the skill it needs, each a card like an achievement's: icon, name, what it is, where the recipe comes
-- from, the skill it needs - green when you have it - with tags for the kind of source and for BoP / BoE.
-- A card opens downwards: its two summary lines give way to the whole of it - what the made thing gives,
-- a line per stat, and every source - so that nothing is said twice. Hovering a card shows the made item's
-- own tooltip (in a tooltip frame of ours, not Blizzard's). A right-click, or the Hide button of an opened
-- card, hides a recipe you do not care about from this character's lists and counts; the Hidden list
-- brings it back. The tabs under the title are every profession, the viewed character's own first and the
-- others dimmed; the first card of a profession is its training: where the next rank (Journeyman, Expert,
-- Artisan) is learned - or the profession itself - and its specializations. Missing / All / Known / Hidden
-- choose what is listed, the box searches names, places and NPCs, and the name button walks through your
-- other characters.
--
-- The window is ours alone: a plain frame with Blizzard's tooltip backdrop, dragged anywhere, its place
-- remembered; the cards are plain buttons in a scroll frame. Nothing of Blizzard's is hooked or touched.
local _, ns = ...

local Window = {}
ns.Window = Window

local Lookup, Known = ns.Lookup, ns.Known

local WIDTH, HEIGHT, PAD = 640, 560, 12
local DEFAULT_POSITION = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 60 }
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local COLOUR = {
    known = "|cff60ff60", now = "|cffffd100", later = "|cff9d9d9d", plain = "|cffffffff", unknown = "|cffff8080",
    dim = "|cff808080", head = "|cffffd100", note = "|cffffb347",
}
-- The tags at the right of a card's name: what kind of source the recipe has, and how the recipe item
-- binds. BoP: only the character that buys, loots or is rewarded it can learn it. BoE (the players' word
-- for "does not bind"): it can be mailed to an alt, traded or bought at the auction house.
local TAG = {
    auto = "|cff80d0ffAutomatic|r", trainer = "|cff80d0ffTrainer|r", taught = "|cff80d0ffTaught|r", vendor = "|cffe6cc80Vendor|r",
    quest = "|cffffff00Quest|r", drop = "|cffc79cffDrop|r", made = "|cffff9d5cCrafted|r",
    bop = "|cffff6060BoP|r", boe = "|cff40e0d0BoE|r",
    Gnomish = "|cffd0a0ffGnomish|r", Goblin = "|cffd0a0ffGoblin|r",
    guild = "|cff40ff40Guild|r", -- a recipe you are missing that somebody in your guild knows
    friend = "|cff66ccffFriend|r", -- ... that a friend of yours knows
}
local BIND_WORDS = {
    bop = "binds when picked up - the character that gets it has to be the cook",
    boe = "does not bind - it can be mailed, traded or auctioned",
}
local FILTERS = { "missing", "all", "known", "hidden" }
local FILTER_LABEL = { missing = "Missing", all = "All", known = "Known", hidden = "Hidden" }

-- copper as the game writes it: 1g 2s 50c
local function money(copper)
    if type(copper) ~= "number" then
        return nil
    end
    local gold, silver, bronze = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if bronze > 0 or #parts == 0 then parts[#parts + 1] = bronze .. "c" end
    return table.concat(parts, " ")
end
Window.Money = money

local window, widgets, rows = nil, {}, {}
Window.open = {}  -- [recipe spell] = true: the recipes opened onto their sources
Window.query = ""
Window.char = nil -- the character whose recipes are shown; nil: the one logged in
Window.prof = nil -- the profession shown; nil: the first the viewed character has
Window.openTraining = {} -- [profession key] = true: its training card is open

------------------------------------------------------------------------
-- Building the frame
------------------------------------------------------------------------
local function savePosition()
    local point, _, relativePoint, x, y = window:GetPoint(1)
    if type(point) == "string" and type(x) == "number" and type(y) == "number" and ns.cdb then
        ns.cdb.options.window = { point = point, relativePoint = relativePoint or point, x = x, y = y }
    end
end

local function place()
    local saved = ns.cdb and ns.cdb.options and ns.cdb.options.window
    local position = (type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number") and saved or DEFAULT_POSITION
    window:ClearAllPoints()
    window:SetPoint(position.point or "CENTER", UIParent, position.relativePoint or position.point or "CENTER", position.x, position.y)
end

local function button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", function()
        ns.SafeCall(onClick)
    end)
    return b
end

local function text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH(justify or "LEFT")
    if type(fs.SetWordWrap) == "function" then
        fs:SetWordWrap(false)
    end
    return fs
end

local function build()
    if window then
        return
    end
    local template = (type(BackdropTemplateMixin) == "table") and "BackdropTemplate" or nil
    window = CreateFrame("Frame", "AKForeverRecipesWindow", UIParent, template)
    window:SetSize(WIDTH, HEIGHT)
    window:SetFrameStrata("MEDIUM")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.SafeCall(savePosition)
    end)
    if type(window.SetBackdrop) == "function" then
        window:SetBackdrop(BACKDROP)
        local c = TOOLTIP_DEFAULT_BACKGROUND_COLOR
        if c and type(c.r) == "number" then
            window:SetBackdropColor(c.r, c.g, c.b, 0.95)
        else
            window:SetBackdropColor(0.09, 0.09, 0.19, 0.95)
        end
    end
    place()

    local w = widgets
    w.title = text(window, "GameFontNormal")
    w.title:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -10)
    w.title:SetText("AKForeverRecipes")
    w.info = text(window, "GameFontHighlightSmall")
    w.info:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -28)
    w.info:SetPoint("RIGHT", window, "RIGHT", -30, 0)
    w.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    w.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
    w.close:SetScript("OnClick", function()
        ns.SafeCall(Window.Close, Window)
    end)

    w.scroll = CreateFrame("ScrollFrame", "AKForeverRecipesScroll", window, "UIPanelScrollFrameTemplate")
    -- one tab per profession; Render shows the viewed character's and lays them out in a row
    w.tabs = {}
    for _, key in ipairs(Lookup.Professions()) do
        w.tabs[key] = button(window, Lookup.ProfessionName(key), 100, function()
            Window:SetProfession(key)
        end)
        w.tabs[key]:Hide()
    end
    -- Lockpicking (Locks.lua): a tab of its own, offered to rogues
    w.tabs[ns.Locks.KEY] = button(window, ns.Locks.meta.name, 100, function()
        Window:SetProfession(ns.Locks.KEY)
    end)
    w.tabs[ns.Locks.KEY]:Hide()

    w.scroll:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -74)
    w.scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - 20, 44)
    w.content = CreateFrame("Frame", nil, w.scroll)
    w.content:SetSize(WIDTH - 2 * PAD - 24, 58)
    w.scroll:SetScrollChild(w.content)
    w.note = text(w.content, "GameFontHighlight")
    w.note:SetPoint("TOPLEFT", w.content, "TOPLEFT", 8, -10)
    w.note:Hide()

    w.filters = {}
    local previous
    for _, filter in ipairs(FILTERS) do
        local b = button(window, FILTER_LABEL[filter], 58, function()
            Window:SetFilter(filter)
        end)
        if previous then
            b:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            b:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PAD, 12)
        end
        w.filters[filter] = b
        previous = b
    end

    w.search = CreateFrame("EditBox", "AKForeverRecipesSearch", window, "InputBoxTemplate")
    w.search:SetSize(110, 20)
    w.search:SetPoint("LEFT", previous, "RIGHT", 14, 0)
    w.search:SetAutoFocus(false)
    w.search:SetScript("OnTextChanged", function(self)
        ns.SafeCall(function()
            local typed = self:GetText()
            if type(typed) == "string" and typed ~= Window.query then
                Window.query = typed
                Window:Render()
            end
        end)
    end)
    w.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    w.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    w.refresh = button(window, "Refresh", 70, function()
        Window:Refresh()
    end)
    w.refresh:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, 12)
    -- whose recipes: a click walks on to the next of your characters with a profession
    w.character = button(window, "", 130, function()
        Window:NextCharacter()
    end)
    w.character:SetPoint("RIGHT", w.refresh, "LEFT", -4, 0)

    Window.window, Window.widgets = window, widgets
end

------------------------------------------------------------------------
-- A card: one recipe as the achievement window draws an achievement - the icon at the left, the name over
-- what the food gives and where the recipe comes from, the skill it needs at the right; a click opens it
-- downwards onto every source. Known recipes are green, the ones your skill can learn now gold-rimmed.
------------------------------------------------------------------------
local CARD_W, CARD_H, CARD_GAP = WIDTH - 2 * PAD - 24, 58, 2
local TEXT_X, SKILL_W, DETAIL_ROW, DETAIL_RIGHT = 58, 64, 14, 130
-- the right-hand words of an opened card's lines (prices, "have 3/16", BoE, drop chances) end where the
-- name's tags end, clear of the skill number's column and the card's edge
local DETAIL_MARGIN = SKILL_W + 12
local CARD_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
-- [state] = { background r, g, b, border r, g, b, the colour of its words }
local CARD_LOOK = {
    known = { 0.04, 0.17, 0.05, 0.30, 0.85, 0.30, COLOUR.known },
    now = { 0.13, 0.10, 0.02, 1.00, 0.82, 0.00, COLOUR.now },
    later = { 0.06, 0.06, 0.08, 0.45, 0.45, 0.45, COLOUR.later },
    plain = { 0.06, 0.06, 0.08, 0.60, 0.60, 0.60, COLOUR.plain },
    unknown = { 0.10, 0.05, 0.05, 0.80, 0.35, 0.35, COLOUR.unknown },
}

local function row(index)
    local r = rows[index]
    if r then
        return r
    end
    local template = (type(BackdropTemplateMixin) == "table") and "BackdropTemplate" or nil
    r = CreateFrame("Button", nil, widgets.content, template)
    r:SetSize(CARD_W, CARD_H)
    if type(r.SetBackdrop) == "function" then
        r:SetBackdrop(CARD_BACKDROP)
    end
    if type(r.SetHighlightTexture) == "function" then
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(40, 40)
    r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 9, -9)
    if type(r.icon.SetTexCoord) == "function" then
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    r.title = text(r, "GameFontNormal")
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -9)
    -- the tags: Vendor / Quest / Drop / Trainer and BoP / BoE, at the right end of the name's line
    r.tags = text(r, "GameFontHighlightSmall", "RIGHT")
    r.tags:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(SKILL_W + 12), -10)
    r.title:SetPoint("RIGHT", r.tags, "LEFT", -8, 0)
    r.effect = text(r, "GameFontHighlightSmall")
    r.effect:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -26)
    r.effect:SetPoint("RIGHT", r, "RIGHT", -(SKILL_W + 12), 0)
    r.source = text(r, "GameFontHighlightSmall")
    r.source:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -40)
    r.source:SetPoint("RIGHT", r, "RIGHT", -(SKILL_W + 12), 0)
    -- who in the guild knows it (only when somebody does): the card grows a line
    r.guild = text(r, "GameFontHighlightSmall")
    r.guild:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -54)
    r.guild:SetPoint("RIGHT", r, "RIGHT", -(SKILL_W + 12), 0)
    -- the skill it needs, where an achievement has its points
    r.skill = text(r, "GameFontNormalLarge", "CENTER")
    r.skill:SetPoint("TOPRIGHT", r, "TOPRIGHT", -10, -12)
    r.skill:SetWidth(SKILL_W)
    r.skillLabel = text(r, "GameFontDisableSmall", "CENTER")
    r.skillLabel:SetPoint("TOPRIGHT", r, "TOPRIGHT", -10, -32)
    r.skillLabel:SetWidth(SKILL_W)
    r.details = {}
    if type(r.RegisterForClicks) == "function" then
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    r:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if self.hide then
                ns.SafeCall(self.hide) -- a right-click hides the recipe (in the Hidden list: brings it back)
            end
        elseif self.click then
            ns.SafeCall(self.click)
        end
    end)
    r:SetScript("OnEnter", function(self)
        ns.SafeCall(Window.ShowTooltip, Window, self)
    end)
    r:SetScript("OnLeave", function()
        ns.SafeCall(Window.HideTooltip, Window)
    end)
    -- on an opened card: Hide / Show again
    r.hideButton = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.hideButton:SetSize(96, 18)
    r.hideButton:SetScript("OnClick", function()
        if r.hide then
            ns.SafeCall(r.hide)
        end
    end)
    r.hideButton:Hide()
    rows[index] = r
    return r
end

-- the pair of texts of one line under an opened card
local function detailRow(r, index)
    local d = r.details[index]
    if d then
        return d
    end
    d = { left = text(r, "GameFontHighlightSmall"), right = text(r, "GameFontHighlightSmall", "RIGHT") }
    d.left:SetWidth(CARD_W - TEXT_X - DETAIL_RIGHT - DETAIL_MARGIN - 8)
    d.right:SetWidth(DETAIL_RIGHT)
    if type(d.left.SetJustifyV) == "function" then
        d.left:SetJustifyV("TOP")
    end
    r.details[index] = d
    return d
end

-- fills a card from its entry and gives back the height it takes
local function fillCard(r, entry)
    local look = CARD_LOOK[entry.state] or CARD_LOOK.plain
    if type(r.SetBackdropColor) == "function" then
        r:SetBackdropColor(look[1], look[2], look[3], 0.92)
    end
    if type(r.SetBackdropBorderColor) == "function" then
        r:SetBackdropBorderColor(look[4], look[5], look[6], 1)
    end
    r.icon:SetTexture(entry.icon and ("Interface\\Icons\\" .. entry.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.title:SetText(entry.text)
    r.tags:SetText(entry.tags or "")
    r.effect:SetText(entry.desc or "")
    r.source:SetText(entry.right)
    r.skill:SetText(look[7] .. entry.skill .. "|r")
    r.skillLabel:SetText(entry.skillLabel or "")
    r.click, r.hide, r.item, r.spell = entry.click, entry.hide, entry.item, entry.spell

    local height = CARD_H
    local used = 0
    -- an opened card says everything in full below its name: the two summary lines would only repeat it
    r.effect:SetShown(entry.details == nil)
    r.source:SetShown(entry.details == nil)
    r.guild:SetText(entry.guild or "")
    r.guild:SetShown(entry.details == nil and entry.guild ~= nil)
    if entry.details == nil and entry.guild ~= nil then
        height = CARD_H + 14
    end
    r.hideButton:SetShown(entry.details ~= nil and entry.hide ~= nil)
    if entry.details then
        local y = 26
        for index, detail in ipairs(entry.details) do
            local d = detailRow(r, index)
            used = index
            if type(d.left.SetWordWrap) == "function" then
                d.left:SetWordWrap(detail.wrap and true or false)
            end
            d.left:SetText(detail.text)
            d.right:SetText(detail.right or "")
            d.left:ClearAllPoints()
            d.left:SetPoint("TOPLEFT", r, "TOPLEFT", TEXT_X, -y)
            d.right:ClearAllPoints()
            d.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -DETAIL_MARGIN, -y)
            d.left:Show()
            d.right:Show()
            local lineHeight = DETAIL_ROW
            if detail.wrap and type(d.left.GetStringHeight) == "function" then
                local measured = d.left:GetStringHeight()
                if type(measured) == "number" and not ns.IsSecret(measured) and measured > lineHeight then
                    lineHeight = math.ceil(measured) + 2
                end
            end
            y = y + lineHeight
        end
        r.hideButton:SetText(entry.hidden and "Show again" or "Hide")
        r.hideButton:ClearAllPoints()
        r.hideButton:SetPoint("TOPRIGHT", r, "TOPRIGHT", -12, -(y + 4))
        height = math.max(CARD_H, y + 4 + 18 + 8)
    end
    for index = used + 1, #r.details do
        r.details[index].left:Hide()
        r.details[index].right:Hide()
    end
    r:SetHeight(height)
    return height
end

------------------------------------------------------------------------
-- Words
------------------------------------------------------------------------
local function detail(details, textValue, right, wrap)
    details[#details + 1] = { text = textValue, right = right or "", wrap = wrap }
end

local function levelsText(drop)
    if not drop.min then
        return ""
    end
    if drop.min == drop.max then
        return " (" .. drop.min .. ")"
    end
    return " (" .. drop.min .. "-" .. drop.max .. ")"
end

local function place2(npc, zone)
    return npc .. (zone and (", " .. zone) or "")
end

-- "Vendor  Quest   BoP": the kinds of source this side has, then how the recipe item binds
local function tagsText(recipe, sources)
    local parts = {}
    for _, kind in ipairs(Lookup.Kinds(sources)) do
        parts[#parts + 1] = TAG[kind]
    end
    if recipe.spec then
        parts[#parts + 1] = TAG[recipe.spec]
    end
    local tags = table.concat(parts, "  ")
    local bind = Lookup.Bind(recipe)
    if bind then
        tags = tags .. (tags ~= "" and "   " or "") .. TAG[bind]
    end
    return tags
end

local STAT_FITS = 70 -- characters of a stat or effect that fit on one line of an opened card

local function dropWords(drop)
    return (drop.object and "Chest: " or "Drop: ") .. drop.npc
end

local function worldWords(world)
    return "World drop, creatures of level " .. world[1] .. "-" .. world[2]
end

local function trainerWords(sources, profName)
    if sources.unsure then
        return "Probably any " .. profName .. " trainer"
    end
    return "Any " .. profName .. " trainer"
end

local SOMEWHERE = {
    vendor = "Sold by a vendor", quest = "Rewarded by a quest", drop = "Dropped by creatures",
}
local SOMEWHERE_ORDER = { "vendor", "quest", "drop" }

-- the kinds of source known to exist with no name to them, in order
local function somewhereKinds(sources)
    local list = {}
    for _, kind in ipairs(SOMEWHERE_ORDER) do
        if sources.somewhere and sources.somewhere[kind] then
            list[#list + 1] = kind
        end
    end
    return list
end

-- the card's third line: the first way to get the recipe, in full, and how many more there are
local function sourceLine(sources, profName)
    local first
    local unnamed = somewhereKinds(sources)
    local count = #unnamed + (sources.auto and 1 or 0) + (sources.trainer and 1 or 0) + (sources.byQuest and 1 or 0) + (sources.taught and 1 or 0) + #sources.vendors + #sources.quests
        + #sources.drops + (sources.world and 1 or 0) + ((sources.trainersSell or sources.capitals) and 1 or 0) + (sources.made and 1 or 0)
    if sources.auto then
        first = "Comes with " .. profName
    elseif sources.trainer then
        first = trainerWords(sources, profName)
    elseif sources.taught then
        first = "Taught by " .. place2(sources.taught.npc, sources.taught.zone)
    elseif #sources.vendors > 0 then
        local vendor = sources.vendors[1]
        local price = sources.favor and (sources.favor .. " Merchant's Favor") or money(vendor.price)
        first = "Vendor: " .. place2(vendor.npc, vendor.zone) .. (price and (", " .. price) or "")
    elseif sources.trainersSell then
        first = "Sold by " .. sources.trainersSell .. " " .. profName .. " trainers" .. (sources.favor and (", " .. sources.favor .. " Merchant's Favor") or "")
    elseif sources.capitals then
        first = "Sold in the capital cities"
    elseif #sources.quests > 0 then
        first = "Quest: " .. sources.quests[1].name .. (sources.quests[1].zone and (", " .. sources.quests[1].zone) or "")
    elseif sources.byQuest then
        first = "Taught by a quest"
    elseif #sources.drops > 0 then
        local drop = sources.drops[1]
        first = dropWords(drop) .. (drop.zone and (", " .. drop.zone) or "") .. (drop.chance and (", " .. drop.chance .. "%") or "")
    elseif sources.world then
        first = worldWords(sources.world)
    elseif sources.made then
        first = "Crafted: " .. sources.made[1]
    elseif #unnamed > 0 then
        first = SOMEWHERE[unnamed[1]] .. " (not known which)"
    elseif sources.otherSide then
        return "Other faction only"
    else
        return "Source unknown"
    end
    if count > 1 then
        first = first .. "  (+" .. (count - 1) .. " more)"
    end
    return first
end

-- "Guild: Thrall, Jaina" - or "Guild: 7 can make this" when more than three do; online names bright. Friends
-- the same after it on the one line: "Guild: Thrall   Friends: Jaina".
local function peoplePart(word, people)
    if #people == 0 then
        return nil, false
    end
    if #people > ns.Guild.SHOW_NAMES then
        return COLOUR.dim .. word .. ": |r" .. COLOUR.known .. #people .. " can make this|r", true
    end
    local names = {}
    for _, person in ipairs(people) do
        names[#names + 1] = ((person.online or person.viaOnline) and COLOUR.known or COLOUR.plain) .. person.name .. "|r"
    end
    return COLOUR.dim .. word .. ": |r" .. table.concat(names, COLOUR.dim .. ", |r"), false
end

local function guildLine(people, friends)
    local guildPart, guildCounted = peoplePart("Guild", people)
    local friendPart, friendCounted = peoplePart("Friends", friends or {})
    if not guildPart and not friendPart then
        return nil
    end
    local line = guildPart and friendPart and (guildPart .. "   " .. friendPart) or guildPart or friendPart
    if guildCounted or friendCounted then
        line = line .. COLOUR.dim .. " - open the card for who|r"
    end
    return line
end

-- the lines a card opens onto: the skill, every way to get it, your other characters
local function detailLines(recipe, sources, profile, viewedKey, learned)
    local details = {}
    local profName = Lookup.ProfessionName(recipe.prof)
    if learned then
        detail(details, COLOUR.known .. "You know this recipe.|r")
    end
    -- what the made thing is and gives: a line each, as its tooltip would list them
    if recipe.kind then
        detail(details, COLOUR.dim .. recipe.kind .. "|r")
    end
    for _, stat in ipairs(recipe.stats or {}) do
        detail(details, stat, nil, #stat > STAT_FITS)
    end
    -- what it is made of, a line per reagent; for the character logged in, how many of each there are
    local reagents = Lookup.Reagents(recipe)
    if #reagents > 0 then
        local own = viewedKey == ns.characterKey
        local crafts
        local lines = {}
        for _, reagent in ipairs(reagents) do
            local have = own and Known:ItemCount(reagent.id) or nil
            local right = ""
            if have then
                right = ((have >= reagent.count) and COLOUR.known or COLOUR.unknown) .. "have " .. have .. "/" .. reagent.count .. "|r"
                local possible = math.floor(have / reagent.count)
                crafts = (crafts == nil or possible < crafts) and possible or crafts
            end
            -- with a count of your own at the right ("have 3/16") the number needed is said there, once
            lines[#lines + 1] = { Lookup.IconText(reagent.icon, 14) .. (have and "" or (reagent.count .. " x ")) .. reagent.name, right }
        end
        local head = COLOUR.head .. "Reagents|r" .. ((recipe.makes or 1) > 1 and (COLOUR.dim .. "  for " .. recipe.makes .. "|r") or "")
        detail(details, head, crafts and (COLOUR.dim .. (crafts > 0 and ("enough for " .. crafts) or "not enough") .. "|r") or "")
        for _, l in ipairs(lines) do
            detail(details, l[1], l[2])
        end
    end
    if recipe.spec then
        detail(details, "Needs the " .. recipe.spec .. " Engineering specialization.")
    end
    local stationName = Lookup.ItemName(recipe.station)
    if stationName then
        detail(details, COLOUR.dim .. "Made at a camp with: |r" .. stationName)
    end
    local skill = Known:Skill(profile, recipe.prof)
    local have = ""
    if skill then
        have = "  You have " .. ((skill >= recipe.learn) and COLOUR.known or COLOUR.unknown) .. skill .. "|r" .. COLOUR.dim .. "."
    end
    detail(details, COLOUR.dim .. profName .. " " .. recipe.learn .. " to learn; it gives skill until " .. recipe.grey .. "." .. have .. "|r",
        recipe.level and (COLOUR.dim .. "needs level " .. recipe.level .. "|r") or "")
    local bind = Lookup.Bind(recipe)
    if bind then
        detail(details, recipe.recipe.name .. COLOUR.dim .. " " .. BIND_WORDS[bind] .. ".|r", TAG[bind], true)
    end

    if sources.auto then
        detail(details, "It comes by itself with " .. profName .. ": nothing to buy or find.", COLOUR.dim .. "automatic|r")
    end
    if sources.trainer then
        if sources.unsure then
            detail(details, "Probably any " .. profName .. " trainer: no recipe item exists for it." .. COLOUR.dim .. " (Not confirmed.)|r", COLOUR.dim .. "trainer|r", true)
        else
            detail(details, "Any " .. profName .. " trainer teaches it.", COLOUR.dim .. "trainer|r")
        end
    end
    if sources.byQuest then
        detail(details, "A quest teaches it." .. COLOUR.dim .. " (Which one is not written down yet.)|r", COLOUR.dim .. "quest|r")
    end
    if sources.trainersSell then
        detail(details, sources.trainersSell .. " " .. profName .. " trainers sell the recipe.", sources.favor and (sources.favor .. " Merchant's Favor") or "")
    end
    if sources.capitals then
        detail(details, "Sold in the capital cities.", sources.favor and (sources.favor .. " Merchant's Favor") or "")
    end
    if sources.taught then
        detail(details, "Taught by " .. place2(sources.taught.npc, sources.taught.zone) .. ".")
    end
    local favor = sources.favor and (sources.favor .. " Merchant's Favor") or nil
    for _, vendor in ipairs(sources.vendors) do
        local price = favor or money(vendor.price) or ""
        if vendor.limited then
            price = price .. (price ~= "" and ", " or "") .. "limited stock"
        end
        detail(details, "Vendor: " .. place2(vendor.npc, vendor.zone) .. (vendor.seen and (COLOUR.dim .. "  (seen by you)|r") or ""), price)
    end
    for _, quest in ipairs(sources.quests) do
        detail(details, "Quest: " .. quest.name .. (quest.zone and (", " .. quest.zone) or ""), quest.level and ("level " .. quest.level) or "")
    end
    for _, drop in ipairs(sources.drops) do
        detail(details, dropWords(drop) .. levelsText(drop) .. (drop.zone and (", " .. drop.zone) or ""), drop.chance and (drop.chance .. "%") or "")
    end
    if sources.world then
        detail(details, worldWords(sources.world) .. ".", COLOUR.dim .. "world drop|r")
    end
    for _, name in ipairs(sources.made or {}) do
        detail(details, "Crafted by another profession: " .. name .. ".")
    end
    for _, kind in ipairs(somewhereKinds(sources)) do
        detail(details, SOMEWHERE[kind] .. "." .. COLOUR.dim .. " (Which one is not written down yet.)|r", COLOUR.dim .. kind .. "|r")
    end
    if sources.via and sources.any then
        detail(details, COLOUR.dim .. "(Source found in " .. sources.via .. ", not on the profession's page.)|r")
    end
    if sources.unknown then
        detail(details, COLOUR.unknown .. "Nobody has written down yet where this comes from.|r")
        if recipe.recipe then
            detail(details, COLOUR.dim .. "A merchant selling " .. recipe.recipe.name .. " is noted the moment you open their window.|r", nil, true)
        end
    elseif sources.otherSide then
        detail(details, COLOUR.dim .. "Its known sources are the other faction's.|r")
    end
    if sources.classic and sources.any then
        detail(details, COLOUR.dim .. "(Source as in Classic - not confirmed for Forever yet.)|r")
    end

    local has, lacks = Known:Others(recipe, viewedKey)
    if #has > 0 then
        detail(details, COLOUR.dim .. "Also known by: |r" .. COLOUR.known .. table.concat(has, ", ") .. "|r", nil, true)
    end
    if #lacks > 0 then
        detail(details, COLOUR.dim .. "Also missing on: |r" .. table.concat(lacks, ", "), nil, true)
    end
    -- everyone in the guild who knows it, a line each: name and skill, online or when last seen
    local people = ns.Guild:Who(recipe)
    if #people > 0 then
        detail(details, COLOUR.head .. "In your guild (" .. #people .. "):|r")
        for _, person in ipairs(people) do
            local on = person.online or person.viaOnline
            detail(details, "   " .. (on and COLOUR.known or COLOUR.plain) .. person.name .. "|r"
                .. (person.skill and (COLOUR.dim .. "  " .. profName .. " " .. person.skill .. "|r") or ""),
                (on and COLOUR.known or COLOUR.dim) .. ns.Guild.When(person) .. "|r")
        end
    end
    -- and every friend who knows it, the same way
    local friends = ns.Friends and ns.Friends:Who(recipe) or {}
    if #friends > 0 then
        detail(details, COLOUR.head .. "Your friends (" .. #friends .. "):|r")
        for _, person in ipairs(friends) do
            local on = person.online or person.viaOnline
            detail(details, "   " .. (on and COLOUR.known or COLOUR.plain) .. person.name .. "|r"
                .. (person.skill and (COLOUR.dim .. "  " .. profName .. " " .. person.skill .. "|r") or ""),
                (on and COLOUR.known or COLOUR.dim) .. ns.Guild.When(person) .. "|r")
        end
    end
    return details
end

------------------------------------------------------------------------
-- The list
------------------------------------------------------------------------
function Window:ViewedKey()
    if Window.char and ns.db and type(ns.db.chars[Window.char]) == "table" then
        return Window.char
    end
    Window.char = nil
    return ns.characterKey
end

-- The cards, as plain data: { text (the name), tags, effect, right (the source line), skill, state, icon,
-- details = { { text, right, wrap } } when open, click } - or { note = "..." } when there is nothing to list.
-- the profession shown and the ones offered as tabs: the viewed character's - or, while nothing is known
-- of that character's professions, every one
function Window:ViewedProfession(profile)
    local offered = Known:ProfessionsOf(profile)
    local own = {}
    for _, key in ipairs(offered) do
        own[key] = true
    end
    if ns.Locks.Offered(profile) then
        offered[#offered + 1] = ns.Locks.KEY -- a rogue's Lockpicking, after its professions
        own[ns.Locks.KEY] = true
    end
    for _, key in ipairs(Lookup.Professions()) do
        if not own[key] then
            offered[#offered + 1] = key -- the professions the character does not have, after its own
        end
    end
    local wanted = Window.prof or ns:GetOption("prof")
    for _, key in ipairs(offered) do
        if key == wanted then
            Window.prof = key
            return key, offered
        end
    end
    Window.prof = offered[1]
    return Window.prof, offered
end

------------------------------------------------------------------------
-- The training card: the first card of a profession - where its next rank is learned (or the profession
-- itself, for a character without it), every later rank, and its specializations
------------------------------------------------------------------------
local TRAINERS_SHOWN = 6

-- the ways to a rank for one side, as lines { text, right }
local function rankWays(rank, side, profName)
    local ways = {}
    local trainers = Lookup.ForSide(rank.trainers, side)
    for index, trainer in ipairs(trainers) do
        if index <= TRAINERS_SHOWN then
            ways[#ways + 1] = { (rank.unsure and "Probably the trainer: " or "Trainer: ") .. place2(trainer.npc, trainer.zone), "" }
        end
    end
    if #trainers > TRAINERS_SHOWN or (rank.total and rank.total > #(rank.trainers or {})) then
        ways[#ways + 1] = { COLOUR.dim .. "and other " .. profName .. " trainers|r", "" }
    end
    if rank.book then
        local vendors = Lookup.ForSide(rank.book.vendors, side)
        if #vendors == 0 then
            ways[#ways + 1] = { "Book: " .. rank.book.name, "" }
        end
        for _, vendor in ipairs(vendors) do
            ways[#ways + 1] = { "Book: " .. rank.book.name .. " - " .. place2(vendor.npc, vendor.zone), COLOUR.dim .. "vendor|r" }
        end
    end
    for _, quest in ipairs(Lookup.ForSide(rank.quests, side)) do
        ways[#ways + 1] = { "Quest: " .. quest.name .. (quest.npc and (" - " .. place2(quest.npc, quest.zone)) or ""), quest.level and ("level " .. quest.level) or "" }
    end
    return ways
end

-- the character level a rank asks for, by the cap it gives - Classic's (Forever's are not written down)
local RANK_LEVEL = { [150] = 10, [225] = 20, [300] = 35 }

local function trainingCard(prof, profile, side)
    local training = Lookup.Training(prof)
    if not training then
        return nil
    end
    local meta = Lookup.Profession(prof)
    local profName = meta.name
    local has = Known:Has(profile, prof)
    local skill, max = Known:Skill(profile, prof)
    -- the rank reached and the next one: by the skill cap the client gave
    local reached, nextRank
    if max or not has then
        for _, rank in ipairs(training.ranks) do
            if (max or 0) >= rank.cap then
                reached = rank
            elseif not nextRank then
                nextRank = rank
            end
        end
    end
    local title, desc, right, state
    if not has then
        title = COLOUR.head .. "Learn " .. profName .. "|r"
        desc = COLOUR.dim .. "This character does not have " .. profName .. ".|r"
        state = "plain"
    elseif nextRank then
        title = COLOUR.head .. nextRank.name .. " " .. profName .. "|r" .. COLOUR.dim .. "  raises your skill cap to " .. nextRank.cap .. "|r"
        local level = type(profile.level) == "number" and profile.level or nil
        local needsLevel = RANK_LEVEL[nextRank.cap]
        local levelOK = not needsLevel or not level or level >= needsLevel
        local ready = skill and nextRank.needs and skill >= nextRank.needs and levelOK
        desc = COLOUR.dim .. "Your cap is " .. max .. (reached and (" (" .. reached.name .. ")") or "") .. "."
            .. (nextRank.needs and ("  It can be learned at " .. profName .. " " .. nextRank.needs
                .. (needsLevel and (" and level " .. needsLevel) or "") .. ".") or "") .. "|r"
            .. ((needsLevel and level and not levelOK) and (COLOUR.unknown .. "  You are level " .. level .. ".|r") or "")
        state = ready and "now" or "later"
    elseif max then
        title = COLOUR.known .. profName .. " training|r"
        desc = COLOUR.dim .. "Your cap is " .. max .. (reached and (" (" .. reached.name .. ")") or "") .. ": there is no further rank.|r"
        state = "known"
    else
        title = COLOUR.head .. profName .. " training|r"
        desc = COLOUR.dim .. "Your skill cap was not read: every rank is listed.|r"
        state = "plain"
    end
    if nextRank then
        local ways = rankWays(nextRank, side, profName)
        right = ways[1] and (ways[1][1] .. (#ways > 1 and (COLOUR.dim .. "  (+" .. (#ways - 1) .. " more)|r") or "")) or (COLOUR.unknown .. "Nobody has written down where|r")
    elseif training.specs then
        right = COLOUR.dim .. #training.specs .. " specializations - open for where|r"
    else
        right = ""
    end
    local entry = {
        card = true, training = true, icon = meta.icon, skill = max or "-", skillLabel = "skill cap", state = state,
        text = title, tags = "", desc = desc, right = (CARD_LOOK[state] or CARD_LOOK.plain)[7] .. right .. "|r",
        click = function()
            Window.openTraining[prof] = not Window.openTraining[prof] or nil
            Window:Render()
        end,
    }
    if Window.openTraining[prof] then
        local details = {}
        local done = {}
        for _, rank in ipairs(training.ranks) do
            if max and max >= rank.cap then
                done[#done + 1] = rank.name
            else
                local needsLevel = RANK_LEVEL[rank.cap]
                detail(details, COLOUR.head .. rank.name .. "|r" .. COLOUR.dim .. "  skill cap " .. rank.cap .. "|r",
                    rank.needs and (COLOUR.dim .. "at " .. profName .. " " .. rank.needs .. "|r") or "")
                -- the level it asks for, a line of its own (the user, 2026-11-12: not seen in an opened card
                -- when it rode on the rank's line)
                if needsLevel then
                    local level = type(profile.level) == "number" and profile.level or nil
                    local short = level and level < needsLevel
                    detail(details, (short and COLOUR.unknown or COLOUR.dim) .. "Needs character level " .. needsLevel
                        .. (short and (" - you are level " .. level) or "") .. "|r" .. COLOUR.dim .. "  (as in Classic)|r")
                end
                local ways = rankWays(rank, side, profName)
                for _, way in ipairs(ways) do
                    detail(details, way[1], way[2])
                end
                if #ways == 0 then
                    detail(details, COLOUR.unknown .. "Nobody has written down where this is learned.|r")
                end
            end
        end
        if #done > 0 then
            table.insert(details, 1, { text = COLOUR.known .. "Learned: " .. table.concat(done, ", ") .. "|r", right = "" })
        end
        if training.specs then
            detail(details, COLOUR.head .. "Specializations|r" .. COLOUR.dim .. "  (as in Classic - not confirmed for Forever)|r")
            for _, spec in ipairs(training.specs) do
                detail(details, spec.name, COLOUR.dim .. ((spec.needs and ("at " .. spec.needs) or "") .. (spec.level and (", level " .. spec.level) or "")) .. "|r")
                for _, quest in ipairs(Lookup.ForSide(spec.quests, side)) do
                    detail(details, "Quest: " .. quest.name .. (quest.npc and (" - " .. place2(quest.npc, quest.zone)) or ""))
                end
            end
        end
        entry.details = details
    end
    return entry
end

function Window:Lines()
    local lines = {}
    local key = self:ViewedKey()
    local profile = Known:Profile(key)
    local prof, offered = self:ViewedProfession(profile)
    if prof == ns.Locks.KEY then
        local filter = ns:GetOption("filter")
        Window.lockOpen = Window.lockOpen or {}
        local locks, totals = ns.Locks:Lines(profile, filter, Window.query, Window.lockOpen, COLOUR, function()
            Window:Render()
        end)
        Window.totals = { total = totals.total, known = totals.known, shown = totals.shown, hidden = 0, filter = filter,
            key = key, prof = prof, offered = offered, skill = totals.skill }
        if totals.shown == 0 then
            locks[#locks + 1] = { note = COLOUR.dim .. ((Window.query or "") ~= "" and ("Nothing matches \"" .. Window.query .. "\".")
                or filter == "missing" and "Every lock here opens for you." or filter == "known" and "No lock opens for you yet."
                or "Nothing is hidden here.") .. "|r" }
        end
        return locks
    end
    local profName = Lookup.ProfessionName(prof)
    local side, skill = profile.side, (Known:Skill(profile, prof))
    local filter = ns:GetOption("filter")
    local total, known, shown = 0, 0, 0

    local hiddenSet = type(profile.hidden) == "table" and profile.hidden or {}
    local hiddenCount = 0
    if filter ~= "hidden" and (Window.query or "") == "" then
        lines[#lines + 1] = trainingCard(prof, profile, side)
    end
    for _, recipe in ipairs(Lookup.Recipes(prof)) do
        local learned = Known:IsLearned(recipe.spell, key)
        local sources = Lookup.Sources(recipe, side)
        local isHidden = hiddenSet[recipe.spell] == true
        -- a recipe only the other faction can get is not part of the list - unless it was learned anyway
        if learned or not sources.otherSide then
            -- a hidden recipe is in the Hidden list alone, and in no count but its own
            if isHidden then
                hiddenCount = hiddenCount + 1
            else
                total = total + 1
                if learned then
                    known = known + 1
                end
            end
            local wanted
            if filter == "hidden" then
                wanted = isHidden
            else
                wanted = not isHidden and (filter == "all" or (filter == "known" and learned) or (filter == "missing" and not learned))
            end
            if wanted and Lookup.Matches(recipe, Window.query, side) then
                shown = shown + 1
                local state = "plain"
                if learned then
                    state = "known"
                elseif sources.unknown then
                    state = "unknown"
                elseif skill then
                    state = (skill >= recipe.learn) and "now" or "later"
                end
                local colour = CARD_LOOK[state][7]
                local spell = recipe.spell
                local people = ns.Guild:Who(recipe)
                local friends = ns.Friends and ns.Friends:Who(recipe) or {}
                local tags = tagsText(recipe, sources)
                if #friends > 0 and not learned then
                    tags = TAG.friend .. (tags ~= "" and "   " or "") .. tags
                end
                if #people > 0 and not learned then
                    tags = TAG.guild .. (tags ~= "" and "   " or "") .. tags
                end
                local entry = {
                    card = true, icon = recipe.icon, skill = recipe.learn, state = state, skillLabel = profName,
                    item = recipe.item, spell = spell, hidden = isHidden,
                    hide = function()
                        Window:SetHidden(key, spell, not isHidden)
                    end,
                    tags = tags, guild = guildLine(people, friends),
                    text = (learned and COLOUR.known or COLOUR.head) .. recipe.name .. "|r" .. (recipe.new and (COLOUR.note .. "  new in Forever|r") or ""),
                    desc = recipe.desc and (COLOUR.dim .. recipe.desc .. "|r") or "",
                    right = colour .. (learned and "Known" or sourceLine(sources, profName)) .. "|r",
                    click = function()
                        Window.open[spell] = not Window.open[spell] or nil
                        Window:Render()
                    end,
                }
                if Window.open[spell] then
                    entry.details = detailLines(recipe, sources, profile, key, learned)
                end
                lines[#lines + 1] = entry
            end
        end
    end

    Window.totals = { total = total, known = known, shown = shown, hidden = hiddenCount, filter = filter, key = key, prof = prof, offered = offered }
    if shown == 0 then
        if Window.query ~= "" then
            lines[#lines + 1] = { note = COLOUR.dim .. "Nothing matches \"" .. Window.query .. "\".|r" }
        elseif filter == "missing" and known > 0 then
            lines[#lines + 1] = { note = COLOUR.known .. "Every recipe is known.|r" }
        elseif filter == "hidden" then
            lines[#lines + 1] = { note = COLOUR.dim .. "Nothing is hidden. A right-click hides a recipe you do not care about.|r" }
        elseif filter == "known" then
            lines[#lines + 1] = { note = COLOUR.dim .. "No " .. profName .. " recipe read as known yet - open its window once, then Refresh.|r" }
        end
    end
    return lines
end

local function infoText()
    local totals = Window.totals or { total = 0, known = 0, shown = 0 }
    local key = totals.key
    local profile = Known:Profile(key)
    if totals.prof == ns.Locks.KEY then
        return COLOUR.head .. Known.ShortName(key) .. "|r: opens " .. COLOUR.known .. totals.known .. "|r of " .. totals.total .. " locks   "
            .. (totals.skill and ("Lockpicking " .. totals.skill) or (COLOUR.dim .. "Lockpicking skill not read yet|r"))
    end
    local profName = Lookup.ProfessionName(totals.prof)
    local parts = { COLOUR.head .. Known.ShortName(key) .. "|r: " .. COLOUR.known .. totals.known .. "|r of " .. totals.total .. " " .. profName .. " recipes known" }
    local skill, max = Known:Skill(profile, totals.prof)
    if skill then
        parts[#parts + 1] = profName .. " " .. skill .. (max and ("/" .. max) or "")
    elseif not Known:Has(profile, totals.prof) then
        parts[#parts + 1] = COLOUR.dim .. "does not have " .. profName .. "|r"
    end
    if (totals.hidden or 0) > 0 then
        parts[#parts + 1] = COLOUR.dim .. totals.hidden .. " hidden|r"
    end
    parts[#parts + 1] = COLOUR.dim .. "right-click hides|r"
    return table.concat(parts, "   ")
end

function Window:Render()
    if not window then
        return
    end
    local lines = self:Lines()
    Window.lines = lines
    local y, used = 0, 0
    local note
    for _, entry in ipairs(lines) do
        if entry.card then
            used = used + 1
            local r = row(used)
            local height = fillCard(r, entry)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", widgets.content, "TOPLEFT", 0, -y)
            r:Show()
            y = y + height + CARD_GAP
        else
            note = entry.note
        end
    end
    for index = used + 1, #rows do
        rows[index]:Hide()
    end
    widgets.note:SetText(note or "")
    widgets.note:ClearAllPoints()
    widgets.note:SetPoint("TOPLEFT", widgets.content, "TOPLEFT", 8, -(y + 10)) -- under the training card
    widgets.note:SetShown(note ~= nil)
    widgets.content:SetHeight(math.max(CARD_H, y))
    widgets.info:SetText(infoText())

    local filter = ns:GetOption("filter")
    for name, b in pairs(widgets.filters) do
        if type(b.SetEnabled) == "function" then
            b:SetEnabled(name ~= filter) -- the pressed-in one is where you are
        end
    end
    -- the tabs: the offered professions in a row, short names when the row would not fit
    local offered = Window.totals.offered or {}
    local offeredSet = {}
    local tabWidth = math.min(104, math.floor((WIDTH - 2 * PAD) / math.max(1, #offered)) - 2)
    local previous
    for _, key in ipairs(offered) do
        offeredSet[key] = true
        local tab = widgets.tabs[key]
        local meta = Lookup.Profession(key) or ns.Locks.meta
        tab:SetWidth(tabWidth)
        local label = tabWidth < 96 and meta.short or meta.name
        local viewed = Known:Profile(Window.totals.key)
        local has = key == ns.Locks.KEY or Known:Has(viewed, key)
        tab:SetText(has and label or (COLOUR.dim .. label .. "|r"))
        tab:ClearAllPoints()
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            tab:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -46)
        end
        if type(tab.SetEnabled) == "function" then
            tab:SetEnabled(key ~= Window.totals.prof)
        end
        tab:Show()
        previous = tab
    end
    for key, tab in pairs(widgets.tabs) do
        if not offeredSet[key] then
            tab:Hide()
        end
    end

    local characters = Known:Characters()
    widgets.character:SetText(Known.ShortName(self:ViewedKey()))
    widgets.character:SetShown(#characters > 1)
end

------------------------------------------------------------------------
-- Opening, closing, the buttons
------------------------------------------------------------------------
function Window:Show()
    ns.Guild:AskRoster() -- who in the guild is online now
    if ns.Friends then
        ns.Friends:ReadList() -- and which friends
    end
    build()
    window:Show()
    self:Render()
end

function Window:Close()
    if window then
        window:Hide()
    end
    self:HideTooltip()
end

function Window:Toggle()
    if window and window:IsShown() then
        self:Close()
    else
        self:Show()
    end
end

function Window:SetFilter(filter)
    if FILTER_LABEL[filter] then
        ns:SetOption("filter", filter)
        self:Render()
    end
end

-- a recipe hidden from (or brought back to) a character's lists
function Window:SetHidden(key, spell, hidden)
    local profile = Known:Profile(key)
    if type(profile.hidden) ~= "table" then
        profile.hidden = {}
    end
    profile.hidden[spell] = hidden and true or nil
    Window.open[spell] = nil
    self:Render()
end

-- The made item's tooltip beside the card under the mouse - in a tooltip frame of our own: Blizzard's
-- GameTooltip is never touched from addon code. An enchant makes no item: its spell's tooltip.
local tooltip
function Window:ShowTooltip(card)
    if not (card.item or card.spell) then
        return
    end
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "AKForeverRecipesTooltip", UIParent, "GameTooltipTemplate")
        Window.tooltip = tooltip
    end
    if type(tooltip.SetOwner) ~= "function" then
        return
    end
    tooltip:SetOwner(card, "ANCHOR_RIGHT")
    local shown = false
    if card.item and type(tooltip.SetItemByID) == "function" then
        shown = pcall(tooltip.SetItemByID, tooltip, card.item)
    elseif card.item and type(tooltip.SetHyperlink) == "function" then
        shown = pcall(tooltip.SetHyperlink, tooltip, "item:" .. card.item)
    elseif card.spell and type(tooltip.SetSpellByID) == "function" then
        shown = pcall(tooltip.SetSpellByID, tooltip, card.spell)
    end
    if shown then
        tooltip:Show()
    else
        tooltip:Hide()
    end
end

function Window:HideTooltip()
    if tooltip then
        tooltip:Hide()
    end
end

function Window:SetProfession(key)
    if Lookup.Profession(key) or key == ns.Locks.KEY then
        Window.prof = key
        if self:ViewedKey() == ns.characterKey then
            ns:SetOption("prof", key) -- where your own character's window opens next time
        end
        self:Render()
    end
end

-- the next of your characters with a profession, round and round
function Window:NextCharacter()
    local characters = Known:Characters()
    local current = self:ViewedKey()
    local nextIndex = 1
    for index, key in ipairs(characters) do
        if key == current then
            nextIndex = index % #characters + 1
        end
    end
    Window.char = characters[nextIndex]
    if Window.char == ns.characterKey then
        Window.char = nil
    end
    self:Render()
end

-- every profession asked again of the client (it answers for the character logged in only)
function Window:Refresh()
    Known:Scan(true)
    self:Render()
end

function Window:Describe()
    return { built = window ~= nil, shown = window and window:IsShown() or false, lines = Window.lines and #Window.lines or 0, query = Window.query,
        char = Window.char or false, prof = Window.prof or false, totals = Window.totals, filter = ns:GetOption("filter") }
end

for _, message in ipairs({ "KNOWN_CHANGED", "GUILD_CHANGED", "FRIENDS_CHANGED" }) do
    ns:Listen(message, function()
        if window and window:IsShown() then
            Window:Render()
        end
    end)
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns:RegisterCommand("show", "open the window ('/akr' alone does too); '/akr show all | known | missing | hidden' picks the list", function(rest)
    local filter = string.lower(rest or "")
    if FILTER_LABEL[filter] then
        ns:SetOption("filter", filter)
    end
    Window:Show()
end)

ns:RegisterCommand("find", "'/akr find <recipe, place or NPC>': the matching recipes of every profession and where they come from, printed to chat", function(rest)
    local wanted = string.gsub(rest or "", "^%s+", "")
    wanted = string.gsub(wanted, "%s+$", "")
    if wanted == "" then
        ns:Print("usage: /akr find <recipe, place or NPC>")
        return
    end
    local side = ns.cdb and ns.cdb.side
    local found = 0
    for _, prof in ipairs(Lookup.Professions()) do
        local profName = Lookup.ProfessionName(prof)
        for _, recipe in ipairs(Lookup.Recipes(prof)) do
            local sources = Lookup.Sources(recipe, side)
            if found < 8 and (Known:IsLearned(recipe.spell) or not sources.otherSide) and Lookup.Matches(recipe, wanted, side) then
                found = found + 1
                local parts = {}
                if sources.auto then parts[#parts + 1] = "comes with " .. profName end
                for _, kind in ipairs(somewhereKinds(sources)) do parts[#parts + 1] = string.lower(SOMEWHERE[kind]) .. " (not known which)" end
                if sources.trainer then parts[#parts + 1] = string.lower(string.sub(trainerWords(sources, profName), 1, 1)) .. string.sub(trainerWords(sources, profName), 2) end
                if sources.byQuest then parts[#parts + 1] = "a quest teaches it" end
                if sources.taught then parts[#parts + 1] = place2(sources.taught.npc, sources.taught.zone) end
                for index, vendor in ipairs(sources.vendors) do
                    if index <= 3 then
                        parts[#parts + 1] = place2(vendor.npc, vendor.zone) .. (money(vendor.price) and (" " .. money(vendor.price)) or "")
                    end
                end
                if #sources.vendors > 3 then parts[#parts + 1] = (#sources.vendors - 3) .. " more vendors" end
                if sources.trainersSell then parts[#parts + 1] = sources.trainersSell .. " " .. profName .. " trainers sell it" end
                for _, quest in ipairs(sources.quests) do parts[#parts + 1] = "quest " .. quest.name end
                for index, drop in ipairs(sources.drops) do
                    if index <= 2 then parts[#parts + 1] = "drops from " .. place2(drop.npc, drop.zone) end
                end
                if sources.world then parts[#parts + 1] = string.lower(string.sub(worldWords(sources.world), 1, 1)) .. string.sub(worldWords(sources.world), 2) end
                local bind = Lookup.Bind(recipe)
                ns:Print(recipe.name .. " (" .. profName .. " " .. recipe.learn .. ", " .. (Known:IsLearned(recipe.spell) and "known" or "missing") .. (bind and (", " .. (bind == "bop" and "BoP" or "BoE")) or "") .. "): "
                    .. (#parts > 0 and table.concat(parts, "; ") or "source not known yet") .. ".")
            end
        end
    end
    if found == 0 then
        ns:Print("nothing in the tables by that name.")
    end
end)
