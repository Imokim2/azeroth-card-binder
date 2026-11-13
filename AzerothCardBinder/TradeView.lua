local _, ACB = ...
local kit = ACB.uiKit
local button, label, centered = kit.button, kit.label, kit.centered
local INK, SEPIA = ACB.folioUi.INK, ACB.folioUi.SEPIA
local function paperPanel(frame)
    frame:SetBackdrop({ bgFile = ACB.folioArt .. "Parchment.tga", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(1, 1, 1, 1)
    frame:SetBackdropBorderColor(0.58, 0.43, 0.27, 1)
end

local function side(parent, x, caption)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, -78)
    frame:SetSize(290, 310)
    paperPanel(frame)
    centered(frame, "GameFontNormal", 12, SEPIA, 260):SetText(caption)
    local card = ACB.createCard(frame)
    card.frame:SetPoint("TOP", frame, "TOP", 0, -35)
    local pack = ACB.createPackItemView(frame, ACB.cardWidth, ACB.cardHeight)
    pack.frame:SetPoint("TOP", frame, "TOP", 0, -35)
    pack.frame:Hide()
    return { frame = frame, card = card, pack = pack,
        empty = centered(frame, "GameFontHighlight", 112, SEPIA, 244),
        accepted = centered(frame, "GameFontNormal", 267, INK, 260),
        note = centered(frame, "GameFontHighlightSmall", 290, SEPIA, 266) }
end

function ACB.createTradeView(parent, saved, trade)
    local view = kit.window("AzerothCardBinderTradeWindow", 680, 584, "Card trade", true)
    local box = CreateFrame("Frame", nil, view)
    box:SetSize(640, 480)
    box:SetPoint("TOP", view, "TOP", 0, -64)
    label(box, "GameFontHighlightSmall", 20, 14, kit.muted, "PLAYER")
    local partner = label(box, "GameFontHighlight", 78, 12, kit.parchment, "")
    partner:SetWidth(350)
    local selected, gift, showHistory = nil, false, false
    local function refresh() view:refresh() end
    local start = button(box, "Start trade", 446, 4, 174, function()
        local peer = ACB.tradePeer(partner:GetText())
        if peer then trade:start(peer, selected, gift) else trade.status = "Right-click a player and choose Trade cards or packs." end
        refresh()
    end)
    local function setMode(value)
        local s = trade:active()
        if s and s.closed then trade:reset() end
        gift = value
        refresh()
    end
    local tradeMode = button(box, "Trade items", 20, 42, 140, function() setMode(false) end)
    local giftMode = button(box, "Send a gift", 168, 42, 140, function() setMode(true) end)
    local modeNote = label(box, "GameFontHighlightSmall", 324, 49, kit.muted, "")
    modeNote:SetWidth(296)
    local mine, theirs = side(box, 20, "YOU GIVE"), side(box, 330, "YOU RECEIVE")
    local function selectCard(key)
        local s = trade:active()
        if s and s.modern and not s.closed and not trade:change(key) then refresh() return false end
        if s and s.closed then trade:reset() end
        selected = key
        refresh()
        return true
    end

    -- Cards are chosen from the binder; sealed packs keep their own searchable list.
    local picker = kit.window("AzerothCardBinderTradeCards", 560, 450, "Choose a pack", true)
    picker.edition:Hide()
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    local search = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", 38, -76)
    search:SetSize(484, 26)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function() picker:Hide() end)
    local rows, page, pages = {}, 1, 1
    local empty = label(picker, "GameFontHighlight", 30, 112, kit.parchment, "No matching packs.")
    local pageLabel = centered(picker, "GameFontHighlightSmall", 408, kit.parchment, 160)
    local back, more
    local function listCards()
        local query, cards = search:GetText():lower(), {}
        for _, item in ipairs(ACB.packList(saved)) do
            local pack = ACB.packItem("pack:" .. item.zone)
            if (pack.name .. " " .. pack.page.title .. " pack " .. pack.tier):lower():find(query, 1, true) then cards[#cards + 1] = pack end
        end
        table.sort(cards, function(a, b) return a.name == b.name and a.key < b.key or a.name < b.name end)
        pages = math.max(1, math.ceil(#cards / 9))
        page = math.max(1, math.min(pages, page))
        empty:SetShown(#cards == 0)
        for index, row in ipairs(rows) do
            local card = cards[(page - 1) * 9 + index]
            row.key = card and card.key
            row:SetShown(card ~= nil)
            if card then row:SetText(("%s%s   (%d owned)"):format(card.name,
                card.pack and (" / " .. ACB.packTiers[card.tier].name) or "", ACB.itemCount(saved, card.key))) end
        end
        pageLabel:SetText(("Page %d of %d"):format(page, pages))
        back:SetEnabled(page > 1)
        more:SetEnabled(page < pages)
    end
    for index = 1, 9 do
        local row = button(picker, "", 30, 112 + (index - 1) * 28, 500, function(self)
            selectCard(self.key)
            picker:Hide()
        end)
        rows[index] = row
    end
    back = button(picker, "Previous", 30, 402, 100, function() page = page - 1 listCards() end)
    more = button(picker, "Next", 430, 402, 100, function() page = page + 1 listCards() end)
    search:SetScript("OnTextChanged", function() page = 1 listCards() end)
    local function editable()
        local s = trade:active()
        return not showHistory and (not s or s.closed or (s.modern and not s.invited and not s.sentConfirm
            and not s.cancelPending and not s.decision and not (s.gift and not s.initiator)))
    end
    local function chooseCard()
        if not editable() then return end
        local session = trade:active()
        if session and session.closed then trade:reset() session = nil end
        local function canPick() return editable() and trade:active() == session and (not session or not session.closed) end
        if ACB.selectTradeCard then ACB.selectTradeCard(selectCard, canPick, selected) end
    end
    local slot = CreateFrame("Button", nil, mine.frame)
    slot:SetPoint("TOPLEFT", 24, -35)
    slot:SetSize(242, 190)
    slot:SetFrameLevel(mine.frame:GetFrameLevel() + 40)
    slot:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    slot:SetScript("OnClick", chooseCard)
    local choose = button(mine.frame, "Choose card", 16, 230, 98, chooseCard)
    local choosePack = button(mine.frame, "Choose pack", 120, 230, 98, function()
        if not editable() then return end
        page = 1
        search:SetText("")
        listCards()
        picker:Show()
        search:SetFocus()
    end)
    local remove = button(mine.frame, "Clear", 224, 230, 54, function() if editable() then selectCard(nil) end end)
    local status = centered(box, "GameFontHighlight", 394, kit.brass, 600)
    local accept = button(box, "Accept", 20, 426, 150, function() trade:confirm() refresh() end)
    local cancel = button(box, "Cancel", 180, 426, 120, function()
        local s = trade:active()
        if s and s.closed then trade:reset(); partner:SetText(""); selected = nil; view:Hide() else trade:cancel(); refresh() end
    end)
    local history = button(box, "History", 510, 426, 110, function() showHistory = not showHistory refresh() end)
    centered(box, "GameFontHighlightSmall", 463, kit.muted, 600):SetText("Stay close and out of combat. Both players must accept before anything moves.")
    local historyPanel = CreateFrame("Frame", nil, box, "BackdropTemplate")
    historyPanel:SetPoint("TOPLEFT", 20, -78)
    historyPanel:SetSize(600, 310)
    historyPanel:SetFrameLevel(box:GetFrameLevel() + 60)
    paperPanel(historyPanel)
    centered(historyPanel, "GameFontNormal", 14, SEPIA, 560):SetText("Recent trades and gifts")
    local historyText = label(historyPanel, "GameFontHighlightSmall", 24, 44, INK, "")
    historyText:SetWidth(552)
    historyText:SetSpacing(5)
    view:SetScript("OnHide", function() picker:Hide() end)

    function view:refresh()
        local s = trade:active()
        local live = s ~= nil and s.modern and not s.closed
        if live then partner:SetText(s.peer:gsub("%-", " ")) end
        if s and s.modern then gift = s.gift end
        if not live and selected and ACB.itemCount(saved, selected) == 0 then selected = nil end
        local give = selected
        if s then give = s.modern and s.give or nil end
        local take = s and s.modern and s.take
        start:SetText(live and "Trade open" or gift and "Send gift" or "Start trade")
        start:SetEnabled(not live and not (s and s.closed) and partner:GetText() ~= "" and (not gift or selected ~= nil))
        local function mark(control, active)
            control:SetEnabled(not live and not active)
            control:SetAlpha(live and 0.6 or 1)
            control:SetBackdropColor(active and 0.82 or 0.20, active and 0.67 or 0.14, active and 0.43 or 0.09, 1)
            control.caption:SetTextColor(unpack(active and { 0.22, 0.13, 0.07 } or kit.parchment))
        end
        mark(tradeMode, not gift)
        mark(giftMode, gift)
        modeNote:SetText(gift and "One item. Nothing needed in return." or "Trade cards, packs, or one of each.")
        local canEdit = editable() == true
        slot:SetEnabled(canEdit)
        choose:SetEnabled(canEdit)
        choosePack:SetEnabled(canEdit)
        choosePack:SetShown(not (live and gift and not s.initiator))
        choose:SetShown(not (live and gift and not s.initiator))
        remove:SetShown(not (live and gift and not s.initiator))
        remove:SetEnabled(canEdit and give ~= nil and not (live and gift))
        local function fill(panel, key, count, confirmed, emptyText)
            local item = key and ACB.tradeItem(key)
            panel.card.frame:SetShown(item ~= nil and not item.pack)
            panel.pack.frame:SetShown(item ~= nil and item.pack == true)
            panel.empty:SetText(emptyText)
            panel.empty:SetShown(key == nil)
            if item then
                if item.pack then panel.pack:set(item)
                else panel.card:set(item, count, saved.shiny and saved.shiny[key] and panel == mine) end
            end
            panel.accepted:SetText(confirmed and "Accepted" or "Not accepted")
            panel.accepted:SetTextColor(unpack(confirmed and { 0.15, 0.36, 0.15 } or SEPIA))
            panel.frame:SetBackdropBorderColor(unpack(confirmed and kit.green or kit.goldDark))
        end
        -- The offer is one copy, even when the picker says several are owned.
        fill(mine, give, give and 1 or 0, live and s.sentConfirm or s and s.applied,
            live and gift and not s.initiator and "Nothing. This is a gift to you." or "Click here to choose a card.\nUse Choose pack for a sealed pack.")
        fill(theirs, take, 1, live and s.peerConfirmed or s and s.applied,
            gift and "Nothing in return.\nThis is a gift." or "Nothing has been added.")
        local pack = give and ACB.packItem(give)
        mine.note:SetText(give and (pack and "You are giving 1 sealed pack."
            or ACB.itemCount(saved, give) == 1 and "Your last copy. Giving it removes it from your binder."
            or "You are giving 1 copy of this card.") or "")
        theirs.note:SetText(take and (ACB.packItem(take) and "You will receive 1 sealed pack." or "You will receive 1 copy of this card.") or "")
        status:SetText(trade.status)
        accept:SetText(s and s.sentConfirm and "Accepted" or "Accept")
        accept:SetEnabled(not showHistory and trade:canAccept())
        cancel:SetText(s and s.closed and "Close" or "Cancel")
        cancel:SetEnabled(s ~= nil and not s.cancelPending and not (s.decision and not s.closed))
        history:SetText(showHistory and "Back to trade" or "History")
        historyPanel:SetShown(showHistory)
        if showHistory then
            local lines = ACB.tradeHistory(saved)
            historyText:SetText(#lines > 0 and table.concat(lines, "\n") or "Your completed trades and gifts appear here.")
        end
    end

    function ACB.prepareTrade(name, key, acceptInvitation)
        local s = trade:active()
        if s and s.closed then trade:reset(); selected = nil; s = nil end
        if s and s.invited then
            if not acceptInvitation then ACB.open("trade"); return false end
            if not trade:join() then return false end
        end
        if type(name) == "string" and name ~= "" then partner:SetText(name:gsub("%-", " ")) end
        if key and ACB.itemCount(saved, key) > 0 then selectCard(key) end
        showHistory = false
        ACB.open("trade")
    end
    -- Exposed to the offline UI checks and the layout preview, not saved data.
    view.controls = { partner = partner, start = start, gift = giftMode, trade = tradeMode, choose = choose, slot = slot, packs = choosePack,
        accept = accept, cancel = cancel, search = search, rows = rows, picker = picker, mine = mine.card,
        minePack = mine.pack, theirPack = theirs.pack }
    return view
end
