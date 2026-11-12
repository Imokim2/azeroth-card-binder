local _, ACB = ...
local ui = ACB.folioUi
local DISPLAY_FONT = ui.DISPLAY_FONT
local INK = ui.INK
local SEPIA = ui.SEPIA
local MISSING_INK = ui.MISSING_INK
local EDGE = ui.EDGE
local POCKET = ui.POCKET
local SELECTED = ui.SELECTED
local RARITY_INK = ui.RARITY_INK
local CARDS_PER_LEAF = ui.CARDS_PER_LEAF
local place = ui.place
local panel = ui.panel
local text = ui.text
local rule = ui.rule
local paper = ui.paper
local mountCard = ui.mountCard
local setCard = ui.setCard
local progressBar = ui.progressBar
local turnButton = ui.turnButton

local createIndex = ACB.createFolioIndex

-- `viewing` (optional, { mine = function returning your counts }) makes the folio a read-only view of someone else's binder.
function ACB.createFolio(parent, saved, selectSet, viewing)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    local left, right = paper(view, 20), paper(view, 471, true)
    local openCard = viewing and function(key)
        local card = ACB.cards[key]
        if card and view:selectCard(card.page, key) then view:showRegion(card.page) end
    end
    local indexPage = createIndex(view, saved, selectSet, openCard)
    local preloadPortraits = ACB.createPortraitLoader(view, left)
    view:SetScript("OnHide", function() preloadPortraits() end)
    local region, state
    local byRegion = {}
    local function share(entry) if not viewing then ACB.linkCard(saved, entry) end end

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
        pockets[index] = {
            frame = pocket,
            miniature = mountCard(pocket, 58, 6, 0.60),
            number = text(pocket, 7, 7, "", 10, SEPIA, 35),
            name = text(pocket, 4, 124, "", 15, INK, 189, "CENTER", true),
            status = text(pocket, 4, 143, "", 10, SEPIA, 189, "CENTER"),
        }
        pocket:SetScript("OnClick", function()
            local slot = (state.leaf - 1) * CARDS_PER_LEAF + index
            local entry = ACB.pages[region].cards[slot]
            if IsShiftKeyDown() then
                share(ACB.firstOwnedEdition(saved.counts, entry))
                return
            end
            state.slot = slot
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
    local askButton = panel(right, "Button", 185, 11, 76, 20, POCKET, EDGE)
    text(askButton, 0, 4, "Ask target", 10, INK, 76, "CENTER")
    askButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    askButton:SetScript("OnClick", function()
        local entry = ACB.cards[state.edition] or ACB.pages[region].cards[state.slot]
        local peer, why = ACB.targetPeer()
        if peer then why = select(2, ACB.askForCard(peer, entry)) end
        if why then ACB.say(why) end
    end)
    local name = text(right, 22, 37, "", 34, INK, 405, "LEFT", true)
    name:SetWordWrap(false)
    rule(right, 23, 96, 402)
    local detail = mountCard(right, 28, 117, 1.48, share)
    local editionStrip = ACB.createEditionStrip(right, saved, function(key)
        state.edition = key
        view:showRegion(region, indexPage:IsShown())
    end)
    local stats = panel(right, "Frame", 247, 117, 174, 281, { 0.83, 0.72, 0.54 }, EDGE)
    local emblem = place(stats:CreateTexture(nil, "ARTWORK"), 66, 12, 42, 42)
    emblem:SetTexture(ACB.folioArt .. "Seal.tga")
    local rarity = text(stats, 0, 63, "", 13, INK, 174, "CENTER")
    local chance = text(stats, 0, 88, "", 45, INK, 174, "CENTER", true)
    text(stats, 0, 133, "BASE DROP CHANCE", 9, SEPIA, 174, "CENTER")
    local luckText = text(stats, 0, 145, "", 9, SEPIA, 174, "CENTER")
    local attemptsText = text(stats, 0, 156, "", 9, SEPIA, 174, "CENTER")
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
        local entry = ACB.cards[state.edition] or ACB.pages[region].cards[state.slot]
        local collection = ACB.collection
        if not collection then return end
        local count = saved.counts[entry.key] or 0
        if count >= 2 then collection:recycle(entry.key) elseif count == 0 then collection:craft(entry.key) end
        view:showRegion(region)
    end)
    wantButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    if viewing and viewing.offer then
        -- In someone else's binder this button asks for the selected card (see Inspector.lua).
        dustButton:SetScript("OnClick", function()
            viewing.offer(ACB.cards[state.edition] or ACB.pages[region].cards[state.slot])
        end)
    end
    wantButton:SetScript("OnClick", function()
        local entry = ACB.cards[state.edition] or ACB.pages[region].cards[state.slot]
        if (saved.counts[entry.key] or 0) > 0 then
            share(entry)
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
        local base = ACB.cards[key] and ACB.baseCard(ACB.cards[key]).key or key
        for slot, card in ipairs(ACB.pages[index].cards) do
            if card.key == base then
                byRegion[index] = { leaf = math.ceil(slot / CARDS_PER_LEAF), slot = slot, edition = key }
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
            if entry and not showIndex then
                local count = ACB.familyCount(saved.counts, entry)
                local active = slot == state.slot
                pocket.frame:SetBackdropColor(unpack(active and SELECTED or POCKET))
                pocket.frame:SetBackdropBorderColor(unpack(active and INK or EDGE))
                pocket.number:SetText(("%02d"):format(slot))
                ACB.fitText(pocket.name, DISPLAY_FONT, entry.name, 189, 15, 9, "")
                pocket.name:SetTextColor(unpack(count > 0 and INK or MISSING_INK))
                local shiny = saved.shiny and saved.shiny[entry.key] == true
                local wanted = saved.wanted and saved.wanted[entry.key] == true
                pocket.status:SetText(count > 0 and ("%d owned / %d spare%s"):format(count, ACB.familySpares(saved.counts, entry), shiny and " / Shiny" or "")
                    or (wanted and "Missing / Wanted" or "Missing"))
                local picture = ACB.firstOwnedEdition(saved.counts, entry)
                setCard(pocket.miniature, picture, saved.counts[picture.key] or 0, saved.shiny and saved.shiny[picture.key], wanted)
            end
        end

        local entry, hasEditions = editionStrip:select(page.cards[state.slot], state.edition)
        state.edition = entry.key
        local scale = hasEditions and 1.32 or 1.48
        detail.holder:SetSize(ACB.cardWidth * scale, ACB.cardHeight * scale)
        detail.frame:SetScale(scale)
        local count = saved.counts[entry.key] or 0
        local tier = ACB.rarities[entry.rarity]
        local code = page.code or ("SET %02d"):format(index)
        selected:SetText(("SELECTED CARD  /  %s %02d"):format(code, state.slot))
        ACB.fitText(name, DISPLAY_FONT, entry.name, 405, 34, 20, "")
        askButton:SetShown(count == 0 and not showIndex)
        rarity:SetText(tier.name:upper())
        rarity:SetTextColor(unpack(count == 0 and MISSING_INK or RARITY_INK[entry.rarity] or INK))
        chance:SetText(("%g%%"):format(ACB.rates[entry.rank] / 100))
        local misses, limit = ACB.luck(saved, entry)
        local what = entry.profession and "Gather attempts" or "Loot attempts"
        attemptsText:SetText(limit and ("%s: %d / %d"):format(what, misses, limit) or ("%s: %d"):format(what, misses))
        luckText:SetText(ACB.luckText(saved, entry, true) or "")
        local dust = saved.dust or 0
        local yield, cost = ACB.dustFor(entry)
        dustMark:SetText(("Binder Dust: %d"):format(dust))
        if entry.baseKey and count == 0 then
            dustText:SetText("Find or trade this edition")
        elseif count >= 2 then
            dustText:SetText(("Recycle a spare: +%d dust"):format(yield))
        elseif count == 0 then
            dustText:SetText(dust >= cost and ("Craft this card: %d dust"):format(cost)
                or ("Craft: %d dust (have %d)"):format(cost, dust))
        else
            dustText:SetText("No spare to recycle")
        end
        local usable = count >= 2 or (not entry.baseKey and count == 0 and dust >= cost)
        dustButton:SetEnabled(usable)
        dustButton:SetAlpha(usable and 1 or 0.55)
        owned:SetText(tostring(count))
        spare:SetText(tostring(math.max(0, count - 1)))
        detailNote:SetText(count > 0 and entry.lore or ("Missing from your binder. " .. ACB.whereToFind(entry)))
        local wanted = saved.wanted and saved.wanted[entry.key] == true
        wantText:SetText(count > 0 and "Link in chat" or (wanted and "On your wanted list" or "Add to wanted list"))
        setCard(detail, entry, count, saved.shiny and saved.shiny[entry.key], wanted)
        if viewing then
            -- Nothing here is theirs to change from your side: no dust, no wanted list, no asking.
            askButton:Hide()
            local buttonLabel = viewing.buttonLabel and viewing.buttonLabel()
            dustButton:SetShown(count > 0 and buttonLabel ~= nil)
            dustButton:SetEnabled(true)
            dustButton:SetAlpha(1)
            dustText:SetText(buttonLabel or "")
            wantButton:Hide()
            dustMark:SetText("")
            attemptsText:SetText("")
            local mine = viewing.mine and viewing.mine() or {}
            luckText:SetText(("You own: %d"):format(mine[entry.key] or 0))
            detailNote:SetText(count > 0 and entry.lore or ("Not in their binder. " .. ACB.whereToFind(entry)))
        end
        if showIndex then
            preloadPortraits(page.cards)
        else
            preloadPortraits(page.cards, first + 1, math.min(first + CARDS_PER_LEAF, total))
        end

        for slot, label in ipairs(milestones) do
            label:SetShown(index == 1 and not viewing)
            if index == 1 and not viewing then
                local achievement = ACB.achievements[slot]
                local collected, needed = ACB.progress(saved.counts, 1, achievement.bossesOnly)
                local status = saved.achievements[achievement.key] and "Earned" or ("%d / %d"):format(collected, needed)
                label:SetText(("%s  /  %s"):format(achievement.name, status))
            end
        end
    end

    return view
end

local function folioScroll(parent, y, height)
    local scroll = place(CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate"), 24, y, 374, height)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(374, height)
    scroll:SetScrollChild(body)
    return body
end

function ACB.createAchievements(parent, saved)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    local left, right = paper(view, 20), paper(view, 471, true)

    text(left, 24, 17, "BINDER RECORD", 10, SEPIA, 180)
    text(left, 22, 33, "Achievements", 35, INK, 400, "LEFT", true)
    local summary = text(left, 24, 78, "", 13, SEPIA, 390)
    rule(left, 23, 97, 402)
    local list = folioScroll(left, 107, 368)
    local rows, y = {}, 0
    for _, track in ipairs(ACB.achievementTracks) do
        text(list, 3, y + 4, track.label:upper(), 11, SEPIA, 350)
        y = y + 23
        for _, entry in ipairs(track.entries) do
            local row = panel(list, "Frame", 0, y, 372, 47, POCKET, EDGE)
            text(row, 9, 5, entry.name, 14, INK, 255, "LEFT", true)
            text(row, 9, 24, entry.title, 10, SEPIA, 252)
            rows[#rows + 1] = {
                track = track, entry = entry,
                status = text(row, 264, 7, "", 11, INK, 99, "RIGHT"),
                bar = progressBar(row, 267, 30, 96),
            }
            y = y + 52
        end
        y = y + 8
    end
    list:SetHeight(y)

    text(right, 24, 17, "TITLE COLLECTION", 10, SEPIA, 200)
    text(right, 22, 33, "Binder Titles", 35, INK, 400, "LEFT", true)
    text(right, 24, 78, "Your chosen title appears in player tooltips for other collectors.", 11, SEPIA, 400)
    rule(right, 23, 97, 402)
    local active = text(right, 24, 116, "", 17, INK, 270, "LEFT", true)
    local function choose(title)
        ACB.selectTitle(saved, title)
        ACB.refresh()
    end
    local hide = panel(right, "Button", 314, 109, 110, 27, POCKET, EDGE)
    text(hide, 0, 6, "Hide title", 12, INK, 110, "CENTER")
    hide:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    hide:SetScript("OnClick", function() choose(nil) end)
    rule(right, 23, 147, 402)
    local titles = folioScroll(right, 160, 315)
    local empty = text(titles, 4, 6, "Earn achievements and finish sets to unlock titles.", 12, SEPIA, 356)
    local titleRows = {}

    function view:refresh()
        local totals, earnedCount = ACB.achievementTotals(saved), 0
        for _, row in ipairs(rows) do
            local have, goal = ACB.achievementProgress(saved, totals, row.track, row.entry)
            local earned = saved.achievements[row.entry.key] == true
            if earned then earnedCount = earnedCount + 1 end
            row.status:SetText(earned and "Earned" or ("%d / %d"):format(have, goal))
            row.bar:set(earned and goal or have, goal)
        end
        summary:SetText(("%d / %d achievements earned"):format(earnedCount, #rows))
        active:SetText(saved.title or "No title equipped")
        hide:SetEnabled(saved.title ~= nil)
        local earned = ACB.earnedTitles(saved)
        empty:SetShown(#earned == 0)
        titles:SetHeight(math.max(315, #earned * 32))
        for index, title in ipairs(earned) do
            local row = titleRows[index]
            if not row then
                row = panel(titles, "Button", 0, (index - 1) * 32, 372, 28, POCKET, EDGE)
                row.name = text(row, 9, 5, "", 13, INK, 255)
                row.status = text(row, 270, 6, "", 10, SEPIA, 92, "RIGHT")
                row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
                row:SetScript("OnClick", function(self) choose(self.title) end)
                titleRows[index] = row
            end
            row.title = title
            row.name:SetText(title)
            local equipped = saved.title == title
            row.status:SetText(equipped and "Equipped" or "Equip")
            row:SetBackdropColor(unpack(equipped and SELECTED or POCKET))
            row:SetShown(true)
        end
        for index = #earned + 1, #titleRows do titleRows[index]:Hide() end
    end

    return view
end
