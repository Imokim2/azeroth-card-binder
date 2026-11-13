local _, ACB = ...
local kit = ACB.uiKit
local brass = kit.brass
local parchment = kit.parchment
local muted = kit.muted
local gold = kit.gold
local green = kit.green
local label = kit.label
local button = kit.button
local backdrop = kit.backdrop

-- The Wanted tab uses wanted lists shared directly in game, without a website or companion feed.

ACB.heardWanted = ACB.heardWanted or {} -- peer -> { at, cards, total }, from players asked directly this session

local MAX_NAMES = 6

-- A list of card keys, checked against the catalog.
local function validKeys(list)
    local keys = {}
    if type(list) ~= "table" then return keys end
    for _, key in ipairs(list) do
        if type(key) == "string" and ACB.cards[key] then keys[#keys + 1] = key end
    end
    return keys
end

-- Everyone whose wanted list is known, most useful first: the players who are looking for cards you have spare. Each row
-- is { name, peer, cards, spares, direct } where `spares` are the wanted cards you hold two or more of.
function ACB.wantedRows(saved)
    local rows, seen = {}, {}
    local function add(name, characters, cards, direct)
        local peer
        for _, character in ipairs(characters) do
            peer = peer or ACB.tradePeer(character)
        end
        peer = peer or ACB.tradePeer(name)
        if not peer or seen[peer] or #cards == 0 then return end -- yourself, a name that cannot be used, or an empty list
        seen[peer] = true
        local spares = {}
        for _, key in ipairs(cards) do
            if (saved.counts[key] or 0) >= 2 then spares[#spares + 1] = key end
        end
        rows[#rows + 1] = { name = name, peer = peer, cards = cards, spares = spares, direct = direct }
    end
    -- Players asked directly come first: what they said just now is the freshest.
    for peer, entry in pairs(ACB.heardWanted) do add(peer, { peer }, validKeys(entry.cards), true) end
    table.sort(rows, function(a, b)
        if #a.spares ~= #b.spares then return #a.spares > #b.spares end
        if a.direct ~= b.direct then return a.direct end
        return a.name:lower() < b.name:lower()
    end)
    return rows
end

-- A short text for a list of cards: the first few names, with the ones you have spare marked, and how many more.
function ACB.wantedText(row)
    local spare = {}
    for _, key in ipairs(row.spares) do spare[key] = true end
    local names = {}
    for index = 1, math.min(#row.cards, MAX_NAMES) do
        local key = row.cards[index]
        names[index] = ACB.cards[key].name .. (spare[key] and " (you have a spare)" or "")
    end
    local text = table.concat(names, ", ")
    if #row.cards > MAX_NAMES then text = text .. (" and %d more"):format(#row.cards - MAX_NAMES) end
    return text
end

local ROWS, ROW_HEIGHT = 30, 34

function ACB.createWantedView(frame, saved)
    local view = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    view:SetPoint("TOPLEFT", 20, -109)
    view:SetSize(900, 500)
    backdrop(view, "Interface\\Buttons\\WHITE8X8", 1)
    view:SetBackdropColor(0.13, 0.09, 0.07, 1)
    view:SetBackdropBorderColor(0.58, 0.43, 0.27, 1)
    label(view, "GameFontNormalLarge", 32, 20, brass, "Wanted cards")
    local summary = label(view, "GameFontHighlight", 32, 52, gold, "")
    summary:SetWidth(840)
    local status = label(view, "GameFontHighlightSmall", 32, 76, muted, "")
    status:SetWidth(840)

    -- Your own list, on the left.
    label(view, "GameFontNormal", 32, 104, brass, "You are looking for")
    local mineRows = {}
    for index = 1, 12 do
        local row = button(view, "", 32, 128 + (index - 1) * 26, 330, function() end)
        row:SetHeight(22)
        mineRows[index] = row
    end
    local entry = CreateFrame("EditBox", nil, view, "InputBoxTemplate")
    entry:SetSize(220, 24)
    entry:SetPoint("TOPLEFT", 40, -454)
    entry:SetAutoFocus(false)
    entry:SetMaxLetters(60)
    entry:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function addCard()
        local card = ACB.findAnyCard(entry:GetText())
        entry:ClearFocus()
        if not card then
            status:SetText("There is no card with that name.")
        elseif (saved.counts[card.key] or 0) > 0 then
            status:SetText("You already have " .. card.name .. ".")
        else
            saved.wanted = saved.wanted or {}
            saved.wanted[card.key] = true
            entry:SetText("")
            status:SetText(card.name .. " is on your list. Other players can ask to see it in game.")
        end
        view:refresh()
    end
    entry:SetScript("OnEnterPressed", addCard)
    button(view, "Add a card", 268, 452, 94, addCard)

    -- What others want, on the right.
    label(view, "GameFontNormal", 392, 104, brass, "Others are looking for")
    button(view, "Check my target", 700, 100, 150, function()
        local peer, why = ACB.targetPeer()
        local ok, reason
        if peer then ok, reason = ACB.requestWanted(peer) else reason = why end
        status:SetText(ok and ("Asked " .. peer .. " what they are looking for. Their list appears here.") or reason)
    end)
    local scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 392, -128)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(450, ROWS * ROW_HEIGHT)
    scroll:SetScrollChild(body)
    local others = {}
    local function otherRow(index)
        if others[index] then return others[index] end
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(448, ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", 4, -2)
        row.text:SetWidth(440)
        row.text:SetJustifyH("LEFT")
        row.text:SetJustifyV("TOP")
        others[index] = row
        return row
    end

    function view:refresh()
        local wanted = ACB.wantedCards(saved)
        for index, row in ipairs(mineRows) do
            local key = wanted[index]
            row:SetShown(key ~= nil)
            if key then
                row:SetText(ACB.cards[key].name .. "   (click to remove)")
                row.key = key
                row:SetScript("OnClick", function(self)
                    saved.wanted[self.key] = nil
                    view:refresh()
                end)
            end
        end
        if #wanted > #mineRows then status:SetText(("Showing %d of your %d wanted cards."):format(#mineRows, #wanted)) end
        local rows = ACB.wantedRows(saved)
        local useful = 0
        for _, row in ipairs(rows) do
            if #row.spares > 0 then useful = useful + 1 end
        end
        summary:SetText(#rows == 0 and "Nobody else's wanted cards are known yet. Target a player and choose Check my target."
            or useful > 0 and ("%d player%s looking for cards you have spare. Right-click a player to trade."):format(useful, useful == 1 and " is" or "s are")
            or ("%d player%s listed; none is looking for a card you have spare."):format(#rows, #rows == 1 and " is" or "s are"))
        for index = 1, math.max(#rows, #others) do
            local row, data = otherRow(index), rows[index]
            row:SetShown(data ~= nil)
            if data then
                row.peer = data.peer
                row.text:SetText(("%s%s: %s"):format(data.name, data.direct and " (just now)" or "", ACB.wantedText(data)))
                row.text:SetTextColor(unpack(#data.spares > 0 and green or parchment))
            end
        end
        body:SetHeight(math.max(ROW_HEIGHT, #rows * ROW_HEIGHT))
    end
    return view
end
