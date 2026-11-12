local _, ACB = ...
local kit = ACB.uiKit
local button, label, centered = kit.button, kit.label, kit.centered

local function side(parent, x, caption)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, -78)
    frame:SetSize(290, 310)
    kit.backdrop(frame, "Interface\\Buttons\\WHITE8X8", 1)
    frame:SetBackdropColor(0.055, 0.05, 0.045, 1)
    frame:SetBackdropBorderColor(unpack(kit.goldDark))
    centered(frame, "GameFontNormal", 12, kit.brass, 260):SetText(caption)
    local card = ACB.createCard(frame)
    card.frame:SetPoint("TOP", frame, "TOP", 0, -35)
    return { frame = frame, card = card,
        empty = centered(frame, "GameFontHighlight", 112, kit.muted, 244),
        accepted = centered(frame, "GameFontNormal", 267, kit.muted, 260),
        note = centered(frame, "GameFontHighlightSmall", 290, kit.muted, 266) }
end

function ACB.createTradeView(parent, saved, trade)
    local view = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    view:SetPoint("TOPLEFT", 20, -109)
    view:SetSize(900, 500)
    kit.backdrop(view, "Interface\\Buttons\\WHITE8X8", 1)
    view:SetBackdropColor(0.13, 0.09, 0.07, 1)
    view:SetBackdropBorderColor(0.58, 0.43, 0.27, 1)
    local box = CreateFrame("Frame", nil, view)
    box:SetSize(640, 480)
    box:SetPoint("TOP", view, "TOP", 0, -8)
    label(box, "GameFontHighlightSmall", 20, 14, kit.muted, "PLAYER")
    local partner = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    partner:SetPoint("TOPLEFT", 78, -4)
    partner:SetSize(238, 28)
    partner:SetAutoFocus(false)
    partner:SetMaxLetters(100)
    partner:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    partner:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local selected, gift, showHistory = nil, false, false
    local function refresh() view:refresh() end
    local useTarget = button(box, "Use target", 326, 4, 110, function()
        local peer, why = ACB.targetPeer()
        if peer then partner:SetText(peer) else trade.status = why end
        refresh()
    end)
    local start = button(box, "Start trade", 446, 4, 174, function()
        local peer = ACB.tradePeer(partner:GetText())
        partner:ClearFocus()
        if peer then trade:start(peer, selected, gift) else trade.status = "Enter a player's name, or use your target." end
        refresh()
    end)
    local function setMode(value)
        local s = trade:active()
        if s and s.closed then trade:reset() end
        gift = value
        refresh()
    end
    local tradeMode = button(box, "Trade cards", 20, 42, 140, function() setMode(false) end)
    local giftMode = button(box, "Gift a card", 168, 42, 140, function() setMode(true) end)
    local modeNote = label(box, "GameFontHighlightSmall", 324, 49, kit.muted, "")
    modeNote:SetWidth(296)
    local mine, theirs = side(box, 20, "YOU GIVE"), side(box, 330, "YOU RECEIVE")
    local function selectCard(key)
        local s = trade:active()
        if s and s.modern and not s.closed and not trade:change(key) then refresh() return end
        if s and s.closed then trade:reset() end
        selected = key
        refresh()
    end

    -- A searchable list replaces cycling through every owned card with arrows.
    local picker = kit.window("AzerothCardBinderTradeCards", 480, 420, "Choose a card", false)
    local search = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", 38, -56)
    search:SetSize(404, 26)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function() picker:Hide() end)
    local rows, page, pages = {}, 1, 1
    local empty = label(picker, "GameFontHighlight", 30, 94, kit.muted, "No matching cards.")
    local pageLabel = centered(picker, "GameFontHighlightSmall", 377, kit.muted, 160)
    local back, more
    local function listCards()
        local query, cards = search:GetText():lower(), {}
        for _, group in ipairs(ACB.inventoryPages()) do
            for _, card in ipairs(group.cards) do
                if (saved.counts[card.key] or 0) > 0 and card.name:lower():find(query, 1, true) then cards[#cards + 1] = card end
            end
        end
        table.sort(cards, function(a, b) return a.name == b.name and a.key < b.key or a.name < b.name end)
        pages = math.max(1, math.ceil(#cards / 9))
        page = math.max(1, math.min(pages, page))
        empty:SetShown(#cards == 0)
        for index, row in ipairs(rows) do
            local card = cards[(page - 1) * 9 + index]
            row.key = card and card.key
            row:SetShown(card ~= nil)
            if card then row:SetText(("%s   (%d owned)"):format(card.name, saved.counts[card.key])) end
        end
        pageLabel:SetText(("Page %d of %d"):format(page, pages))
        back:SetEnabled(page > 1)
        more:SetEnabled(page < pages)
    end
    for index = 1, 9 do
        local row = button(picker, "", 30, 94 + (index - 1) * 28, 420, function(self)
            selectCard(self.key)
            picker:Hide()
        end)
        rows[index] = row
    end
    back = button(picker, "Previous", 30, 370, 100, function() page = page - 1 listCards() end)
    more = button(picker, "Next", 350, 370, 100, function() page = page + 1 listCards() end)
    search:SetScript("OnTextChanged", function() page = 1 listCards() end)
    local choose = button(mine.frame, "Choose card", 30, 230, 145, function()
        page = 1
        search:SetText("")
        listCards()
        picker:Show()
        search:SetFocus()
    end)
    local remove = button(mine.frame, "Remove", 183, 230, 77, function() selectCard(nil) end)
    local status = centered(box, "GameFontHighlight", 394, kit.brass, 600)
    local accept = button(box, "Accept", 20, 426, 150, function() trade:confirm() refresh() end)
    local cancel = button(box, "Cancel", 180, 426, 120, function() trade:cancel() refresh() end)
    local history = button(box, "History", 510, 426, 110, function() showHistory = not showHistory refresh() end)
    centered(box, "GameFontHighlightSmall", 463, kit.muted, 600):SetText("Stay close and out of combat. No cards move until both players accept.")
    local historyPanel = CreateFrame("Frame", nil, box, "BackdropTemplate")
    historyPanel:SetPoint("TOPLEFT", 20, -78)
    historyPanel:SetSize(600, 310)
    historyPanel:SetFrameLevel(box:GetFrameLevel() + 60)
    kit.backdrop(historyPanel, "Interface\\Buttons\\WHITE8X8", 1)
    historyPanel:SetBackdropColor(0.055, 0.05, 0.045, 1)
    historyPanel:SetBackdropBorderColor(unpack(kit.goldDark))
    centered(historyPanel, "GameFontNormal", 14, kit.brass, 560):SetText("Recent trades and gifts")
    local historyText = label(historyPanel, "GameFontHighlightSmall", 24, 44, kit.parchment, "")
    historyText:SetWidth(552)
    historyText:SetSpacing(5)
    view:SetScript("OnHide", function() picker:Hide() end)

    function view:refresh()
        local s = trade:active()
        local live = s ~= nil and s.modern and not s.closed
        if s and s.modern then gift = s.gift end
        if not live and selected and (saved.counts[selected] or 0) == 0 then selected = nil end
        local give = selected
        if s then give = s.modern and s.give or nil end
        local take = s and s.modern and s.take
        partner:SetEnabled(not live)
        useTarget:SetEnabled(not live)
        start:SetText(live and "Trade open" or gift and "Send gift" or "Start trade")
        start:SetEnabled(not live and (not gift or selected ~= nil))
        local function mark(control, active)
            control:SetEnabled(not live and not active)
            control:SetAlpha(live and 0.6 or 1)
            control:SetBackdropColor(active and 0.82 or 0.20, active and 0.67 or 0.14, active and 0.43 or 0.09, 1)
            control.caption:SetTextColor(unpack(active and { 0.22, 0.13, 0.07 } or kit.parchment))
        end
        mark(tradeMode, not gift)
        mark(giftMode, gift)
        modeNote:SetText(gift and "One card. Nothing needed in return." or "Choose what each player gives.")
        local editable = not showHistory and (not live or (not s.sentConfirm and not s.cancelPending and not s.decision))
            and not (live and gift and not s.initiator)
        choose:SetEnabled(editable)
        choose:SetShown(not (live and gift and not s.initiator))
        remove:SetShown(not (live and gift and not s.initiator))
        remove:SetEnabled(editable and give ~= nil and not (live and gift))
        local function fill(panel, key, count, confirmed, emptyText)
            panel.card.frame:SetShown(key ~= nil)
            panel.empty:SetText(emptyText)
            panel.empty:SetShown(key == nil)
            if key then panel.card:set(ACB.cards[key], count, saved.shiny and saved.shiny[key] and panel == mine) end
            panel.accepted:SetText(confirmed and "Accepted" or "Not accepted")
            panel.accepted:SetTextColor(unpack(confirmed and kit.green or kit.muted))
            panel.frame:SetBackdropBorderColor(unpack(confirmed and kit.green or kit.goldDark))
        end
        -- The offer is one copy, even when the picker says several are owned.
        fill(mine, give, give and 1 or 0, live and s.sentConfirm or s and s.applied,
            live and gift and not s.initiator and "Nothing. This card is a gift to you." or "No card chosen.\nClick Choose card to add one.")
        fill(theirs, take, 1, live and s.peerConfirmed or s and s.applied,
            gift and "Nothing in return.\nThis is a gift." or "Nothing in return.\nNo card has been added.")
        mine.note:SetText(give and (saved.counts[give] == 1 and "Your last copy. Giving it removes it from your binder."
            or "You are giving 1 copy of this card.") or "")
        theirs.note:SetText(take and "You will receive 1 copy of this card." or "")
        status:SetText(trade.status)
        accept:SetText(s and s.sentConfirm and "Accepted" or "Accept")
        accept:SetEnabled(not showHistory and trade:canAccept())
        cancel:SetText(s and s.closed and "New trade" or "Cancel")
        cancel:SetEnabled(s ~= nil and not s.cancelPending and not (s.decision and not s.closed))
        history:SetText(showHistory and "Back to trade" or "History")
        historyPanel:SetShown(showHistory)
        if showHistory then
            local lines = ACB.tradeHistory(saved)
            historyText:SetText(#lines > 0 and table.concat(lines, "\n") or "Your completed trades and gifts appear here.")
        end
    end

    function ACB.prepareTrade(name)
        if type(name) == "string" and name ~= "" then partner:SetText(name:gsub("%-", " ")) end
        showHistory = false
        ACB.open("trade")
    end
    -- Exposed to the offline UI checks and the layout preview, not saved data.
    view.controls = { partner = partner, start = start, gift = giftMode, trade = tradeMode, choose = choose,
        accept = accept, cancel = cancel, search = search, rows = rows, picker = picker, mine = mine.card }
    return view
end
