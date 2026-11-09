local _, ACB = ...

ACB.folioArt = "Interface\\AddOns\\AzerothCardBinder\\Art\\"

local DISPLAY_FONT = "Fonts\\MORPHEUS.ttf"
local INK = { 0.21, 0.13, 0.08 }
local SEPIA = { 0.37, 0.25, 0.15 }
local EDGE = { 0.59, 0.44, 0.29 }
local POCKET = { 0.76, 0.64, 0.46 }
local SELECTED = { 0.79, 0.67, 0.47 }
local RARITY_INK = {
    common = INK,
    rare = { 0.16, 0.28, 0.46 },
    epic = { 0.35, 0.19, 0.48 },
    legendary = { 0.50, 0.25, 0.07 },
}
local PAPER_WIDTH, PAPER_HEIGHT = 449, 501
local CARDS_PER_LEAF = 4
local SETS_PER_INDEX_PAGE = 8

local function place(widget, x, y, width, height)
    widget:SetSize(width, height)
    widget:SetPoint("TOPLEFT", x, -y)
    return widget
end

local function panel(parent, kind, x, y, width, height, color, edge)
    local frame = place(CreateFrame(kind, nil, parent, "BackdropTemplate"), x, y, width, height)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(edge))
    return frame
end

local function text(parent, x, y, value, size, color, width, align, display)
    local line = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetPoint("TOPLEFT", x, -y)
    line:SetFont(display and DISPLAY_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    line:SetTextColor(unpack(color))
    line:SetShadowOffset(0, 0)
    line:SetJustifyH(align or "LEFT")
    line:SetWidth(width)
    line:SetText(value)
    return line
end

local function rule(parent, x, y, width)
    local line = place(parent:CreateTexture(nil, "ARTWORK"), x, y, width, 1)
    line:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.65)
end

local function paper(parent, x, mirror)
    local frame = place(CreateFrame("Frame", nil, parent), x, 109, PAPER_WIDTH, PAPER_HEIGHT)
    local skin = frame:CreateTexture(nil, "BACKGROUND")
    skin:SetAllPoints()
    skin:SetTexture(ACB.folioArt .. "Parchment.tga")
    if mirror then skin:SetTexCoord(1, 0, 0, 1) end
    return frame
end

-- A holder keeps both scaled card sizes aligned to the page's coordinates.
local function mountCard(parent, x, y, scale, isDetail)
    local holder = place(CreateFrame("Frame", nil, parent), x, y, ACB.cardWidth * scale, ACB.cardHeight * scale)
    local card = ACB.createCard(holder, isDetail)
    card.frame:SetScale(scale)
    card.frame:SetPoint("CENTER", holder, "CENTER")
    card.frame:EnableMouse(isDetail)
    return card
end

local function setCard(card, entry, count, shiny, wanted)
    shiny, wanted = shiny == true, wanted == true
    if card.entry ~= entry or card.owned ~= count or card.shiny ~= (count > 0 and shiny)
        or card.wantedFlag ~= wanted then
        card.wantedFlag = wanted
        card:set(entry, count, shiny, wanted)
    end
end

-- A thin progress bar. `bar:set(have, total)` fills it and turns it gold once the set is complete.
local function progressBar(parent, x, y, width)
    local bar = { width = width }
    local back = place(parent:CreateTexture(nil, "ARTWORK"), x, y, width, 5)
    back:SetColorTexture(0.40, 0.28, 0.17, 0.55)
    bar.fill = place(parent:CreateTexture(nil, "OVERLAY"), x, y, 1, 5)
    function bar:set(have, total)
        local fraction = total > 0 and math.min(1, have / total) or 0
        self.fill:SetWidth(math.max(1, self.width * fraction))
        self.fill:SetShown(have > 0)
        if total > 0 and have >= total then
            self.fill:SetColorTexture(0.85, 0.65, 0.12, 1)
        else
            self.fill:SetColorTexture(0.50, 0.33, 0.16, 1)
        end
    end
    return bar
end

local function turnButton(parent, x, caption, action)
    local control = panel(parent, "Button", x, 455, 72, 24, POCKET, EDGE)
    local captionText = text(control, 0, 5, caption, 11, INK, 72, "CENTER")
    control:SetFontString(captionText)
    control:SetText(caption)
    control:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    control:SetScript("OnClick", action)
    return control
end

local function createIndex(parent, saved, selectSet)
    local index = paper(parent, 20)
    text(index, 23, 17, "FIND A COLLECTION", 10, SEPIA, 403)
    text(index, 22, 33, "Collection Index", 35, INK, 403, "LEFT", true)
    text(index, 24, 73, "Search by set name or category", 11, SEPIA, 403)
    local search = panel(index, "EditBox", 23, 90, 402, 27, { 0.91, 0.84, 0.68 }, EDGE)
    search:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    search:SetTextColor(unpack(INK))
    search:SetTextInsets(9, 9, 0, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    index:SetScript("OnHide", function() search:ClearFocus() end)

    local resultCount = text(index, 24, 125, "", 10, SEPIA, 401)
    local rows = {}
    for position = 1, SETS_PER_INDEX_PAGE do
        local row = panel(index, "Button", 23, 144 + (position - 1) * 36, 402, 33, POCKET, EDGE)
        row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        rows[position] = {
            frame = row,
            title = text(row, 9, 3, "", 15, INK, 278, "LEFT", true),
            group = text(row, 10, 20, "", 9, SEPIA, 278),
            progress = text(row, 282, 11, "", 11, INK, 109, "RIGHT"),
            bar = progressBar(row, 9, 26, 380),
        }
        row:SetScript("OnClick", function(self)
            selectSet(self.setIndex)
        end)
    end

    rule(index, 23, 445, 402)
    local pageNumber, activeSet, pageCount = 1, 1, 1
    local function turn(step)
        pageNumber = math.max(1, math.min(pageCount, pageNumber + step))
        index:showSets(activeSet)
    end
    local back = turnButton(index, 23, "Previous", function() turn(-1) end)
    local more = turnButton(index, 353, "More", function() turn(1) end)
    local pageLabel = text(index, 105, 461, "", 12, SEPIA, 240, "CENTER")
    index:EnableMouseWheel(true)
    index:SetScript("OnMouseWheel", function(_, delta) turn(delta > 0 and -1 or 1) end)

    function index:showSets(current)
        activeSet = current
        local query = search:GetText():lower():match("^%s*(.-)%s*$")
        local results = {}
        for _, setIndex in ipairs(ACB.setOrder()) do
            local entry = ACB.pages[setIndex]
            local searchable = (entry.title .. " " .. (entry.group or "")):lower()
            if #entry.cards > 0 and searchable:find(query, 1, true) then results[#results + 1] = setIndex end
        end

        local total = #results
        pageCount = math.max(1, math.ceil(total / SETS_PER_INDEX_PAGE))
        pageNumber = math.min(pageNumber, pageCount)
        resultCount:SetText(total == 0 and "No matching sets" or ("%d %s"):format(total, total == 1 and "set" or "sets"))
        pageLabel:SetText(total > 0 and ("Sets  /  %d of %d"):format(pageNumber, pageCount) or "")
        back:SetEnabled(pageNumber > 1)
        more:SetEnabled(pageNumber < pageCount)
        back:SetAlpha(pageNumber > 1 and 1 or 0.45)
        more:SetAlpha(pageNumber < pageCount and 1 or 0.45)

        local first = (pageNumber - 1) * SETS_PER_INDEX_PAGE
        for position, row in ipairs(rows) do
            local setIndex = results[first + position]
            row.frame.setIndex = setIndex
            row.frame:SetShown(setIndex ~= nil)
            if setIndex then
                local entry = ACB.pages[setIndex]
                local collected, cards = ACB.progress(saved.counts, setIndex)
                local active = setIndex == activeSet
                row.frame:SetBackdropColor(unpack(active and SELECTED or POCKET))
                row.frame:SetBackdropBorderColor(unpack(active and INK or EDGE))
                row.title:SetText(entry.title)
                row.group:SetText((entry.group or "") .. (entry.levels and ("  /  Levels " .. entry.levels) or ""))
                row.progress:SetText(collected >= cards and "Complete" or ("%d / %d"):format(collected, cards))
                row.bar:set(collected, cards)
            end
        end
    end

    search:SetScript("OnTextChanged", function()
        pageNumber = 1
        index:showSets(activeSet)
    end)
    index:Hide()
    return index
end

function ACB.createFolio(parent, saved, selectSet)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    local left, right = paper(view, 20), paper(view, 471, true)
    local indexPage = createIndex(view, saved, selectSet)
    local region, state
    local byRegion = {}

    text(left, 23, 17, "REGION COLLECTION", 10, SEPIA, 180)
    local title = text(left, 22, 33, "", 35, INK, 280, "LEFT", true)
    local subtitle = text(left, 24, 77, "", 13, SEPIA, 390)
    local progress = text(left, 253, 42, "", 12, SEPIA, 171, "RIGHT")
    local setBar = progressBar(left, 23, 90, 402)
    rule(left, 23, 96, 402)

    local pockets = {}
    for index = 1, CARDS_PER_LEAF do
        local x = 23 + ((index - 1) % 2) * 205
        local y = 105 + math.floor((index - 1) / 2) * 168
        local pocket = panel(left, "Button", x, y, 197, 159, POCKET, EDGE)
        pocket:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        local empty = panel(pocket, "Frame", 58, 6, 81, 114, { 0.71, 0.60, 0.44 }, EDGE)
        local seal = empty:CreateTexture(nil, "ARTWORK")
        seal:SetSize(46, 46)
        seal:SetPoint("CENTER")
        seal:SetTexture(ACB.folioArt .. "Seal.tga")
        pockets[index] = {
            frame = pocket, empty = empty,
            miniature = mountCard(pocket, 58, 6, 0.60, false),
            number = text(pocket, 7, 7, "", 10, SEPIA, 35),
            name = text(pocket, 4, 124, "", 15, INK, 189, "CENTER", true),
            status = text(pocket, 4, 143, "", 10, SEPIA, 189, "CENTER"),
        }
        pocket:SetScript("OnClick", function()
            state.slot = (state.leaf - 1) * CARDS_PER_LEAF + index
            view:showRegion(region)
        end)
    end

    rule(left, 23, 445, 402)
    local prevLeaf = turnButton(left, 23, "< Back", function()
        state.leaf = state.leaf - 1
        state.slot = (state.leaf - 1) * CARDS_PER_LEAF + 1
        view:showRegion(region)
    end)
    local nextLeaf = turnButton(left, 353, "Next >", function()
        state.leaf = state.leaf + 1
        state.slot = (state.leaf - 1) * CARDS_PER_LEAF + 1
        view:showRegion(region)
    end)
    local leafLabel = text(left, 105, 461, "", 12, SEPIA, 240, "CENTER")
    -- Big sets run to many pages: the wheel turns one page, Shift turns ten.
    left:EnableMouseWheel(true)
    left:SetScript("OnMouseWheel", function(_, delta)
        local pages = math.max(1, math.ceil(#ACB.pages[region].cards / CARDS_PER_LEAF))
        local step = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1
        state.leaf = math.max(1, math.min(pages, state.leaf + (delta > 0 and -step or step)))
        state.slot = (state.leaf - 1) * CARDS_PER_LEAF + 1
        view:showRegion(region)
    end)

    local selected = text(right, 23, 17, "", 10, SEPIA, 250)
    local dustMark = text(right, 273, 17, "", 10, SEPIA, 150, "RIGHT")
    local name = text(right, 22, 37, "", 34, INK, 405, "LEFT", true)
    name:SetWordWrap(false)
    rule(right, 23, 96, 402)
    local detail = mountCard(right, 28, 117, 1.48, true)
    local stats = panel(right, "Frame", 247, 117, 174, 281, { 0.83, 0.72, 0.54 }, EDGE)
    local emblem = place(stats:CreateTexture(nil, "ARTWORK"), 66, 12, 42, 42)
    emblem:SetTexture(ACB.folioArt .. "Seal.tga")
    local rarity = text(stats, 0, 63, "", 13, INK, 174, "CENTER")
    local chance = text(stats, 0, 88, "", 45, INK, 174, "CENTER", true)
    text(stats, 0, 138, "DROP CHANCE", 10, SEPIA, 174, "CENTER")
    local luckText = text(stats, 0, 151, "", 9, SEPIA, 174, "CENTER")
    rule(stats, 15, 168, 144)
    local owned = text(stats, 16, 175, "", 26, INK, 60, "CENTER", true)
    text(stats, 87, 182, "Owned", 13, SEPIA, 75)
    local spare = text(stats, 16, 205, "", 26, INK, 60, "CENTER", true)
    text(stats, 87, 212, "Spare", 13, SEPIA, 75)
    local wantButton = panel(stats, "Button", 16, 236, 142, 20, POCKET, EDGE)
    local wantText = text(wantButton, 0, 4, "", 10, INK, 142, "CENTER")
    local dustButton = panel(stats, "Button", 16, 259, 142, 20, POCKET, EDGE)
    local dustText = text(dustButton, 0, 4, "", 10, INK, 142, "CENTER")
    dustButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    dustButton:SetScript("OnClick", function()
        local entry = ACB.pages[region].cards[state.slot]
        local collection = ACB.collection
        if not collection then return end
        local count = saved.counts[entry.key] or 0
        if count >= 2 then collection:recycle(entry.key) elseif count == 0 then collection:craft(entry.key) end
        view:showRegion(region)
    end)
    wantButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    wantButton:SetScript("OnClick", function()
        local entry = ACB.pages[region].cards[state.slot]
        if (saved.counts[entry.key] or 0) > 0 then
            ACB.linkCard(saved, entry)
            return
        end
        saved.wanted = saved.wanted or {}
        saved.wanted[entry.key] = not saved.wanted[entry.key] or nil
        view:showRegion(region)
    end)

    rule(right, 23, 412, 402)
    local detailNote = text(right, 26, 424, "", 12, SEPIA, 396, "CENTER")
    local milestones = {}
    for index, achievement in ipairs(ACB.achievements) do
        milestones[index] = text(right, 24, 455 + (index - 1) * 20, achievement.name, 11, INK, 400)
    end

    -- Turn to the page that holds a card and select it.
    function view:selectCard(index, key)
        for slot, card in ipairs(ACB.pages[index].cards) do
            if card.key == key then
                byRegion[index] = { leaf = math.ceil(slot / CARDS_PER_LEAF), slot = slot }
                return true
            end
        end
    end

    function view:showRegion(index, showIndex)
        local page = ACB.pages[index]
        local have, total = ACB.progress(saved.counts, index)
        region = index
        state = byRegion[index]
        if not state then
            state = { leaf = 1, slot = 1 }
            byRegion[index] = state
        end
        left:SetShown(not showIndex)
        indexPage:SetShown(showIndex == true)
        if showIndex then indexPage:showSets(index) end
        local leaves = math.ceil(total / CARDS_PER_LEAF)
        title:SetFont(DISPLAY_FONT, math.max(18, math.min(35, 280 / (0.52 * #page.title))), "")
        title:SetText(page.title)
        subtitle:SetText(page.subtitle)
        progress:SetText(("%d / %d collected"):format(have, total))
        setBar:set(have, total)
        leafLabel:SetText(("Page %d of %d"):format(state.leaf, leaves))
        prevLeaf:SetEnabled(state.leaf > 1)
        nextLeaf:SetEnabled(state.leaf < leaves)
        prevLeaf:SetAlpha(state.leaf > 1 and 1 or 0.45)
        nextLeaf:SetAlpha(state.leaf < leaves and 1 or 0.45)

        local first = (state.leaf - 1) * CARDS_PER_LEAF
        for position, pocket in ipairs(pockets) do
            local slot = first + position
            local entry = page.cards[slot]
            pocket.frame:SetShown(entry ~= nil)
            if entry then
                local count = saved.counts[entry.key] or 0
                local active = slot == state.slot
                pocket.frame:SetBackdropColor(unpack(active and SELECTED or POCKET))
                pocket.frame:SetBackdropBorderColor(unpack(active and INK or EDGE))
                pocket.number:SetText(("%02d"):format(slot))
                pocket.name:SetText(entry.name)
                local shiny = saved.shiny and saved.shiny[entry.key] == true
                pocket.status:SetText(count > 0 and ("%d owned / %d spare%s"):format(count, count - 1, shiny and " / Shiny" or "")
                    or (saved.wanted and saved.wanted[entry.key] and "Missing / Wanted" or "Missing"))
                pocket.empty:SetShown(count == 0)
                pocket.miniature.frame:SetShown(count > 0)
                if count > 0 then setCard(pocket.miniature, entry, count, shiny) end
            end
        end

        local entry = page.cards[state.slot]
        local count = saved.counts[entry.key] or 0
        local tier = ACB.rarities[entry.rarity]
        local code = page.code or ("SET %02d"):format(index)
        selected:SetText(("SELECTED CARD  /  %s %02d"):format(code, state.slot))
        name:SetText(entry.name)
        rarity:SetText(tier.name:upper())
        rarity:SetTextColor(unpack(RARITY_INK[entry.rarity] or INK))
        chance:SetText(("%g%%"):format(ACB.rates[entry.rank] / 100))
        local misses, limit = ACB.luck(saved, entry)
        local what = entry.profession and "Gathers" or "Kills"
        luckText:SetText(limit and ("%s since last drop: %d / %d"):format(what, misses, limit)
            or ("%s since last drop: %d"):format(what, misses))
        local dust = saved.dust or 0
        local yield, cost = ACB.dustFor(entry)
        dustMark:SetText(("Binder Dust: %d"):format(dust))
        if count >= 2 then
            dustText:SetText(("Recycle a spare: +%d dust"):format(yield))
        elseif count == 0 then
            dustText:SetText(dust >= cost and ("Craft this card: %d dust"):format(cost)
                or ("Craft: %d dust (have %d)"):format(cost, dust))
        else
            dustText:SetText("No spare to recycle")
        end
        local usable = count >= 2 or (count == 0 and dust >= cost)
        dustButton:SetEnabled(usable)
        dustButton:SetAlpha(usable and 1 or 0.55)
        owned:SetText(tostring(count))
        spare:SetText(tostring(math.max(0, count - 1)))
        detailNote:SetText(count > 0 and entry.lore or ("Missing from your binder. " .. ACB.whereToFind(entry)))
        local wanted = saved.wanted and saved.wanted[entry.key] == true
        wantText:SetText(count > 0 and "Link in chat" or (wanted and "On your wanted list" or "Add to wanted list"))
        setCard(detail, entry, count, saved.shiny and saved.shiny[entry.key], wanted)

        for slot, label in ipairs(milestones) do
            label:SetShown(index == 1)
            if index == 1 then
                local achievement = ACB.achievements[slot]
                local collected, needed = ACB.progress(saved.counts, 1, achievement.bossesOnly)
                local status = saved.achievements[achievement.key] and "Earned" or ("%d / %d"):format(collected, needed)
                label:SetText(("%s  /  %s"):format(achievement.name, status))
            end
        end
    end

    return view
end
