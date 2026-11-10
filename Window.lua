-- Window: '/acb' - every cooking recipe your faction can get, in the order of the skill it needs, coloured
-- by whether you have it; a recipe opens onto where it comes from: the trainer, the vendors with their
-- price, the quest, the creatures that drop it. Missing / All / Known choose what is listed, the box
-- searches names, places and NPCs, and the name button walks through your other characters' books.
--
-- The window is ours alone: a plain frame with Blizzard's tooltip backdrop, dragged anywhere, its place
-- remembered; rows are plain buttons in a scroll frame. Nothing of Blizzard's is hooked or touched.
local _, ns = ...

local Window = {}
ns.Window = Window

local Lookup, Known = ns.Lookup, ns.Known

local WIDTH, HEIGHT, PAD, ROW, RIGHT = 640, 480, 12, 18, 200
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
local FILTERS = { "missing", "all", "known" }
local FILTER_LABEL = { missing = "Missing", all = "All", known = "Known" }

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
Window.char = nil -- the character whose book is shown; nil: the one logged in

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
    window = CreateFrame("Frame", "AKForeverCookbookWindow", UIParent, template)
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
    w.title:SetText("AKForeverCookbook")
    w.info = text(window, "GameFontHighlightSmall")
    w.info:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -28)
    w.info:SetPoint("RIGHT", window, "RIGHT", -30, 0)
    w.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    w.close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -2, -2)
    w.close:SetScript("OnClick", function()
        ns.SafeCall(Window.Close, Window)
    end)

    w.scroll = CreateFrame("ScrollFrame", "AKForeverCookbookScroll", window, "UIPanelScrollFrameTemplate")
    w.scroll:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -48)
    w.scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD - 20, 44)
    w.content = CreateFrame("Frame", nil, w.scroll)
    w.content:SetSize(WIDTH - 2 * PAD - 24, ROW)
    w.scroll:SetScrollChild(w.content)

    w.filters = {}
    local previous
    for _, filter in ipairs(FILTERS) do
        local b = button(window, FILTER_LABEL[filter], 64, function()
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

    w.search = CreateFrame("EditBox", "AKForeverCookbookSearch", window, "InputBoxTemplate")
    w.search:SetSize(150, 20)
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
    -- whose book: a click walks on to the next of your characters with Cooking
    w.character = button(window, "", 130, function()
        Window:NextCharacter()
    end)
    w.character:SetPoint("RIGHT", w.refresh, "LEFT", -4, 0)

    Window.window, Window.widgets = window, widgets
end

local function row(index)
    local r = rows[index]
    if r then
        return r
    end
    r = CreateFrame("Button", nil, widgets.content)
    r:SetSize(WIDTH - 2 * PAD - 24, ROW)
    r:SetPoint("TOPLEFT", widgets.content, "TOPLEFT", 0, -(index - 1) * ROW)
    if type(r.SetHighlightTexture) == "function" then
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end
    r.left = text(r, "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.left:SetPoint("RIGHT", r, "RIGHT", -(RIGHT + 6), 0)
    r.right = text(r, "GameFontHighlightSmall", "RIGHT")
    r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.right:SetWidth(RIGHT)
    r:SetScript("OnClick", function(self)
        if self.click then
            ns.SafeCall(self.click)
        end
    end)
    rows[index] = r
    return r
end

------------------------------------------------------------------------
-- Words
------------------------------------------------------------------------
local function line(lines, textValue, indent, right, click)
    lines[#lines + 1] = { text = string.rep("    ", indent or 0) .. textValue, right = right or "", click = click }
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

-- the lines a recipe opens onto: what it gives, the skill, every way to get it, your other characters
local function detailLines(lines, recipe, sources, profile, viewedKey)
    if recipe.effect then
        line(lines, COLOUR.dim .. recipe.effect .. (recipe.level and ("  (food level " .. recipe.level .. ")") or "") .. "|r", 1)
    end
    local skill = profile.skill
    local have = ""
    if skill then
        have = "  You have " .. ((skill >= recipe.learn) and COLOUR.known or COLOUR.unknown) .. skill .. "|r" .. COLOUR.dim .. "."
    end
    line(lines, COLOUR.dim .. "Cooking " .. recipe.learn .. " to learn; it gives skill until " .. recipe.grey .. "." .. have .. "|r", 1)

    if sources.trainer then
        line(lines, "Any Cooking trainer teaches it.", 1, COLOUR.dim .. "trainer|r")
    end
    if sources.taught then
        line(lines, "Taught by " .. place2(sources.taught.npc, sources.taught.zone) .. ".", 1)
    end
    local favor = sources.favor and (sources.favor .. " Merchant's Favor") or nil
    for _, vendor in ipairs(sources.vendors) do
        local price = favor or money(vendor.price) or ""
        if vendor.limited then
            price = price .. (price ~= "" and ", " or "") .. "limited stock"
        end
        line(lines, "Vendor: " .. place2(vendor.npc, vendor.zone) .. (vendor.seen and (COLOUR.dim .. "  (seen by you)|r") or ""), 1, price)
    end
    for _, quest in ipairs(sources.quests) do
        line(lines, "Quest: " .. quest.name .. (quest.zone and (", " .. quest.zone) or ""), 1, quest.level and ("level " .. quest.level) or "")
    end
    for _, drop in ipairs(sources.drops) do
        line(lines, "Drop: " .. drop.npc .. levelsText(drop) .. (drop.zone and (", " .. drop.zone) or ""), 1, drop.chance and (drop.chance .. "%") or "")
    end
    if sources.unknown then
        line(lines, COLOUR.unknown .. "Nobody has written down yet where this comes from.|r", 1)
        if recipe.recipe then
            line(lines, COLOUR.dim .. "A merchant selling " .. recipe.recipe.name .. " is noted the moment you open their window.|r", 1)
        end
    elseif sources.otherSide then
        line(lines, COLOUR.dim .. "Its known sources are the other faction's.|r", 1)
    end
    if sources.classic and sources.any then
        line(lines, COLOUR.dim .. "(Source as in Classic - not confirmed for Forever yet.)|r", 1)
    end

    local has, lacks = Known:Others(recipe.spell, viewedKey)
    if #has > 0 then
        line(lines, COLOUR.dim .. "Also known by: |r" .. COLOUR.known .. table.concat(has, ", ") .. "|r", 1)
    end
    if #lacks > 0 then
        line(lines, COLOUR.dim .. "Also missing on: |r" .. table.concat(lacks, ", "), 1)
    end
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

function Window:Lines()
    local lines = {}
    local key = self:ViewedKey()
    local profile = Known:Profile(key)
    local side, skill = profile.side, profile.skill
    local filter = ns:GetOption("filter")
    local total, known, shown = 0, 0, 0

    for _, recipe in ipairs(Lookup.Recipes()) do
        local learned = Known:IsLearned(recipe.spell, key)
        local sources = Lookup.Sources(recipe, side)
        -- a recipe only the other faction can get is not part of this book - unless it was learned anyway
        if learned or not sources.otherSide then
            total = total + 1
            if learned then
                known = known + 1
            end
            local wanted = filter == "all" or (filter == "known" and learned) or (filter == "missing" and not learned)
            if wanted and Lookup.Matches(recipe, Window.query, side) then
                shown = shown + 1
                local open = Window.open[recipe.spell]
                local right
                if learned then
                    right = COLOUR.known .. "known|r"
                else
                    local colour = COLOUR.plain
                    if sources.unknown then
                        colour = COLOUR.unknown
                    elseif skill then
                        colour = (skill >= recipe.learn) and COLOUR.now or COLOUR.later
                    end
                    right = colour .. Lookup.Summary(recipe, side) .. "|r"
                end
                local head = (open and "- " or "+ ") .. Lookup.IconText(recipe.icon, 16) .. (learned and COLOUR.known or COLOUR.head) .. recipe.name .. "|r"
                    .. COLOUR.dim .. "  " .. recipe.learn .. "|r" .. (recipe.new and (COLOUR.note .. "  new|r") or "")
                local spell = recipe.spell
                line(lines, head, 0, right, function()
                    Window.open[spell] = not Window.open[spell] or nil
                    Window:Render()
                end)
                if open then
                    detailLines(lines, recipe, sources, profile, key)
                end
            end
        end
    end

    Window.totals = { total = total, known = known, shown = shown, filter = filter, key = key }
    if shown == 0 then
        if Window.query ~= "" then
            line(lines, COLOUR.dim .. "Nothing matches \"" .. Window.query .. "\".|r", 0)
        elseif filter == "missing" and known > 0 then
            line(lines, COLOUR.known .. "Every recipe is known.|r", 0)
        elseif filter == "known" then
            line(lines, COLOUR.dim .. "No recipe read as known yet - open your Cooking window once, then Refresh.|r", 0)
        end
    end
    return lines
end

local function infoText()
    local totals = Window.totals or { total = 0, known = 0, shown = 0 }
    local key = totals.key
    local profile = Known:Profile(key)
    local parts = { COLOUR.head .. Known.ShortName(key) .. "|r: " .. COLOUR.known .. totals.known .. "|r of " .. totals.total .. " recipes known" }
    if profile.skill then
        parts[#parts + 1] = "Cooking " .. profile.skill .. (profile.skillMax and ("/" .. profile.skillMax) or "")
    elseif totals.known == 0 then
        parts[#parts + 1] = COLOUR.dim .. "no Cooking read yet|r"
    end
    parts[#parts + 1] = COLOUR.dim .. "yellow: learnable now, grey: needs more skill|r"
    return table.concat(parts, "   ")
end

function Window:Render()
    if not window then
        return
    end
    local lines = self:Lines()
    Window.lines = lines
    for index, entry in ipairs(lines) do
        local r = row(index)
        r.left:SetText(entry.text)
        r.right:SetText(entry.right)
        r.click = entry.click
        r:Show()
    end
    for index = #lines + 1, #rows do
        rows[index]:Hide()
    end
    widgets.content:SetHeight(math.max(ROW, #lines * ROW))
    widgets.info:SetText(infoText())

    local filter = ns:GetOption("filter")
    for name, b in pairs(widgets.filters) do
        if type(b.SetEnabled) == "function" then
            b:SetEnabled(name ~= filter) -- the pressed-in one is where you are
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
    build()
    window:Show()
    self:Render()
end

function Window:Close()
    if window then
        window:Hide()
    end
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

-- the next of your characters with Cooking, round and round
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

-- the book asked again of the client (it answers for the character logged in only)
function Window:Refresh()
    Known:Scan()
    self:Render()
end

function Window:Describe()
    return { built = window ~= nil, shown = window and window:IsShown() or false, lines = Window.lines and #Window.lines or 0, query = Window.query,
        char = Window.char or false, totals = Window.totals, filter = ns:GetOption("filter") }
end

ns:Listen("KNOWN_CHANGED", function()
    if window and window:IsShown() then
        Window:Render()
    end
end)

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ns:RegisterCommand("show", "open the window ('/acb' alone does too); '/acb show all | known | missing' picks the list", function(rest)
    local filter = string.lower(rest or "")
    if FILTER_LABEL[filter] then
        ns:SetOption("filter", filter)
    end
    Window:Show()
end)

ns:RegisterCommand("find", "'/acb find <dish, place or NPC>': the matching recipes and where they come from, printed to chat", function(rest)
    local wanted = string.gsub(rest or "", "^%s+", "")
    wanted = string.gsub(wanted, "%s+$", "")
    if wanted == "" then
        ns:Print("usage: /acb find <dish, place or NPC>")
        return
    end
    local side = ns.cdb and ns.cdb.side
    local found = 0
    for _, recipe in ipairs(Lookup.Recipes()) do
        local sources = Lookup.Sources(recipe, side)
        if found < 8 and (Known:IsLearned(recipe.spell) or not sources.otherSide) and Lookup.Matches(recipe, wanted, side) then
            found = found + 1
            local parts = {}
            if sources.trainer then parts[#parts + 1] = "any Cooking trainer" end
            if sources.taught then parts[#parts + 1] = place2(sources.taught.npc, sources.taught.zone) end
            for index, vendor in ipairs(sources.vendors) do
                if index <= 3 then
                    parts[#parts + 1] = place2(vendor.npc, vendor.zone) .. (money(vendor.price) and (" " .. money(vendor.price)) or "")
                end
            end
            if #sources.vendors > 3 then parts[#parts + 1] = (#sources.vendors - 3) .. " more vendors" end
            for _, quest in ipairs(sources.quests) do parts[#parts + 1] = "quest " .. quest.name end
            for index, drop in ipairs(sources.drops) do
                if index <= 2 then parts[#parts + 1] = "drops from " .. place2(drop.npc, drop.zone) end
            end
            ns:Print(recipe.name .. " (" .. recipe.learn .. ", " .. (Known:IsLearned(recipe.spell) and "known" or "missing") .. "): "
                .. (#parts > 0 and table.concat(parts, "; ") or "source not known yet") .. ".")
        end
    end
    if found == 0 then
        ns:Print("nothing in the book by that name.")
    end
end)
