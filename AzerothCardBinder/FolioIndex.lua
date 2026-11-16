local _, ACB = ...
local ui = ACB.folioUi
local INK = ui.INK
local SEPIA = ui.SEPIA
local EDGE = ui.EDGE
local POCKET = ui.POCKET
local SELECTED = ui.SELECTED
local SETS_PER_INDEX_PAGE = ui.SETS_PER_INDEX_PAGE
local panel = ui.panel
local text = ui.text
local rule = ui.rule
local paper = ui.paper
local progressBar = ui.progressBar
local turnButton = ui.turnButton


-- The Index page of the binder: a searchable, paged list of every set.
local function createIndex(parent, saved, selectSet, openCard)
    local index = paper(parent, 20)
    text(index, 23, 17, "FIND A CARD OR COLLECTION", 10, SEPIA, 403)
    text(index, 22, 33, "Collection Index", 35, INK, 403, "LEFT", true)
    text(index, 24, 73, "Search by set, category or card name", 11, SEPIA, 403)
    local search = panel(index, "EditBox", 23, 90, 402, 27, { 0.91, 0.84, 0.68 }, EDGE)
    search:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    search:SetTextColor(unpack(INK))
    search:SetTextInsets(9, 9, 0, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    index:SetScript("OnHide", function() search:ClearFocus() end)

    local ownership = saved.indexOwnership
    if ownership ~= "owned" and ownership ~= "unowned" then ownership = "all" end
    local filters = {}
    for position, choice in ipairs({ { "all", "All" }, { "owned", "Owned" }, { "unowned", "Unowned" } }) do
        local control = panel(index, "Button", 23 + (position - 1) * 137, 125, 128, 24, POCKET, EDGE)
        control:SetFontString(text(control, 0, 5, choice[2], 11, INK, 128, "CENTER"))
        control:SetText(choice[2])
        control:SetScript("OnClick", function() index:setOwnership(choice[1]) end)
        filters[choice[1]] = control
    end
    local resultCount = text(index, 24, 157, "", 10, SEPIA, 401)
    local rows = {}
    for position = 1, SETS_PER_INDEX_PAGE do
        local row = panel(index, "Button", 23, 176 + (position - 1) * 33, 402, 32, POCKET, EDGE)
        row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        rows[position] = {
            frame = row,
            title = text(row, 9, 2, "", 14, INK, 278, "LEFT", true),
            group = text(row, 10, 18, "", 9, SEPIA, 278),
            progress = text(row, 282, 11, "", 11, INK, 109, "RIGHT"),
            bar = progressBar(row, 9, 27, 380),
        }
        row:SetScript("OnClick", function(self)
            if self.cardKey then (openCard or ACB.openCard)(self.cardKey) else selectSet(self.setIndex) end
        end)
    end

    rule(index, 23, 445, 402)
    local pageNumber, activeSet, pageCount = 1, 1, 1
    local function turn(step)
        pageNumber = math.max(1, math.min(pageCount, pageNumber + step))
        index:showSets(activeSet)
    end
    local back = turnButton(index, 23, "Previous", function() turn(-1) end)
    local more = turnButton(index, 353, "Next", function() turn(1) end)
    local pageLabel = text(index, 105, 461, "", 12, SEPIA, 240, "CENTER")
    function index:compactFooter()
        back:ClearAllPoints(); back:SetPoint("TOPLEFT", 23, -449)
        more:ClearAllPoints(); more:SetPoint("TOPLEFT", 353, -449)
        pageLabel:ClearAllPoints(); pageLabel:SetPoint("TOPLEFT", 105, -455)
    end
    index:EnableMouseWheel(true)
    index:SetScript("OnMouseWheel", function(_, delta) turn(delta > 0 and -1 or 1) end)

    function index:showSets(current)
        activeSet = current
        for key, control in pairs(filters) do
            control:SetEnabled(key ~= ownership)
            control:SetBackdropColor(unpack(key == ownership and SELECTED or POCKET))
            control:SetBackdropBorderColor(unpack(key == ownership and INK or EDGE))
        end
        local query = search:GetText():lower():match("^%s*(.-)%s*$")
        local exact, sets, matches = {}, {}, {}
        for _, setIndex in ipairs(ACB.setOrder()) do
            local entry = ACB.pages[setIndex]
            local searchable = (entry.title .. " " .. (entry.group or "")):lower()
            local setMatches = searchable:find(query, 1, true) ~= nil
            if ownership == "all" and #entry.cards > 0 and setMatches then sets[#sets + 1] = setIndex end
            if query ~= "" or ownership ~= "all" then
                for _, base in ipairs(entry.cards) do
                  for _, card in ipairs(ACB.cardEditions(base)) do
                    local name = card.name:lower()
                    local owned = (saved.counts[card.key] or 0) > 0
                    local allowed = ownership == "all" or (ownership == "owned" and owned) or (ownership == "unowned" and not owned)
                    if saved.indexCardFilter then allowed = allowed and saved.indexCardFilter(card) end
                    if allowed and (name:find(query, 1, true) or (ownership ~= "all" and setMatches)) then
                        local list = name == query and exact or matches
                        list[#list + 1] = card
                    end
                  end
                end
            end
        end
        local results = exact
        for _, setIndex in ipairs(sets) do results[#results + 1] = setIndex end
        for _, card in ipairs(matches) do results[#results + 1] = card end

        local total = #results
        pageCount = math.max(1, math.ceil(total / SETS_PER_INDEX_PAGE))
        pageNumber = math.min(pageNumber, pageCount)
        local noun = ownership ~= "all" and "card" or query == "" and "set" or "result"
        local empty = ownership == "all" and "No matching sets or cards" or ("No %s cards match"):format(ownership)
        resultCount:SetText(total == 0 and empty or ("%d %s%s"):format(total, noun, total == 1 and "" or "s"))
        pageLabel:SetText(total > 0 and ("Results  /  %d of %d"):format(pageNumber, pageCount) or "")
        back:SetEnabled(pageNumber > 1)
        more:SetEnabled(pageNumber < pageCount)
        back:SetAlpha(pageNumber > 1 and 1 or 0.45)
        more:SetAlpha(pageNumber < pageCount and 1 or 0.45)

        local first = (pageNumber - 1) * SETS_PER_INDEX_PAGE
        for position, row in ipairs(rows) do
            local result = results[first + position]
            local card = type(result) == "table" and result
            local setIndex = type(result) == "number" and result or nil
            row.frame.setIndex = setIndex
            row.frame.cardKey = card and card.key or nil
            row.frame:SetShown(result ~= nil)
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
            elseif card then
                local count = saved.counts[card.key] or 0
                row.frame:SetBackdropColor(unpack(POCKET))
                row.frame:SetBackdropBorderColor(unpack(EDGE))
                row.title:SetText(card.name)
                row.group:SetText(ACB.pages[card.page].title .. "  /  " .. ACB.rarities[card.rarity].name)
                row.progress:SetText(count > 0 and ("%d owned"):format(count) or "Missing")
                row.bar:set(count > 0 and 1 or 0, 1)
            end
        end
    end

    function index:setOwnership(choice)
        if choice ~= "all" and choice ~= "owned" and choice ~= "unowned" then return false end
        ownership, saved.indexOwnership, pageNumber = choice, choice, 1
        self:showSets(activeSet)
        return true
    end
    index.filters, index.search = filters, search
    search:SetScript("OnTextChanged", function()
        pageNumber = 1
        index:showSets(activeSet)
    end)
    index:Hide()
    return index
end

ACB.createFolioIndex = createIndex
