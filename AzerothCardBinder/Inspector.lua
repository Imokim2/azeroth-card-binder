local _, ACB = ...

-- Another player's binder, read-only: the same pages as your own binder, filled from the cards they sent. The Wanted tab
-- lists what they are looking for; **Trade** on one of those cards (that you own) is how a swap starts: you give that
-- card, then pick the card you want in return from their binder, and they are sent the offer (Trade.lua).
function ACB.initInspector(saved, report, now, after)
    local kit = ACB.uiKit
    local inspector = kit.window("AzerothCardBinderInspect", 940, 644, "Binder", true)
    local seen = { counts = {}, shiny = {}, wanted = {}, achievements = {}, attempts = {}, misses = {}, dust = 0 }
    local currentSet, showingIndex = 1, false
    local picking -- { give = key } while you are choosing a card of theirs in return for one of yours
    local folio, tradeButton, summary, drawSummary, wantedPanel, highlight

    local function stopPicking()
        picking = nil
        if tradeButton then tradeButton:SetText("Offer a trade") end
    end

    -- "bob-realmname" is shown the way the game writes the name: "Bob Realmname".
    local function displayName(peer)
        return (peer:gsub("%-", " "):gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
    end

    folio = ACB.createFolio(inspector, seen, function(setIndex)
        currentSet, showingIndex = setIndex, false
        folio:showRegion(currentSet, false)
    end, {
        mine = function() return saved.counts end,
        -- While you are choosing, the selected card of theirs gets a button that sends the offer.
        buttonLabel = function()
            return picking and ("Get this one for my %s"):format(ACB.cards[picking.give].name) or nil
        end,
        offer = function(entry)
            if not (picking and inspector.peer and entry) then return end
            local peer, give = inspector.peer, picking.give
            stopPicking()
            -- The trade opens on their side by itself, giving your card; the card you picked is asked for in chat, so they
            -- know what you would like back.
            ACB.startTrade(peer, give)
            if ACB.askForCard then ACB.askForCard(peer, entry) end
            inspector:Hide()
            if ACB.prepareTrade then ACB.prepareTrade(peer) end
        end,
    })

    -- What they are looking for, as a list over the pages, each with a Trade button.
    wantedPanel = CreateFrame("Frame", nil, inspector, "BackdropTemplate")
    wantedPanel:SetPoint("TOPLEFT", 20, -109)
    wantedPanel:SetSize(900, 515)
    wantedPanel:SetFrameLevel(inspector:GetFrameLevel() + 30)
    wantedPanel:EnableMouse(true)
    kit.backdrop(wantedPanel, "Interface\\Buttons\\WHITE8X8", 1)
    wantedPanel:SetBackdropColor(0.13, 0.09, 0.07, 1)
    wantedPanel:SetBackdropBorderColor(0.58, 0.43, 0.27, 1)
    local wantedTitle = wantedPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    wantedTitle:SetPoint("TOPLEFT", 24, -20)
    wantedTitle:SetTextColor(unpack(kit.gold))
    local wantedNote = wantedPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wantedNote:SetPoint("TOPLEFT", 24, -52)
    wantedNote:SetWidth(850)
    wantedNote:SetJustifyH("LEFT")
    wantedNote:SetTextColor(unpack(kit.muted))
    local scroll = CreateFrame("ScrollFrame", nil, wantedPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -78)
    scroll:SetPoint("BOTTOMRIGHT", -44, 18)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(820, 100)
    scroll:SetScrollChild(body)
    wantedPanel:Hide()

    local ROW = 40
    local rows = {}
    local function startPicking(key)
        local peer = inspector.peer
        if not peer or (saved.counts[key] or 0) < 1 then return end
        local theirs = 0
        for _, count in pairs(seen.counts) do
            if count > 0 then theirs = theirs + 1 end
        end
        if theirs == 0 then
            report(displayName(peer) .. " has no cards in their binder to trade for.")
            return
        end
        picking = { give = key }
        tradeButton:SetText("Cancel pick")
        wantedPanel:Hide()
        showingIndex = false
        highlight("collection")
        drawSummary()
        folio:showRegion(currentSet, false)
        report(("Pick the card you want from %s's binder for your %s, then press the button on its panel."):format(
            displayName(peer), ACB.cards[key].name))
    end
    local function rowFor(index)
        local row = rows[index]
        if not row then
            row = {}
            row.text = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("TOPLEFT", 0, -(index - 1) * ROW - 9)
            row.text:SetWidth(690)
            row.text:SetJustifyH("LEFT")
            row.text:SetTextColor(unpack(kit.parchment))
            row.button = kit.button(body, "Trade", 700, (index - 1) * ROW + 2, 110, function() startPicking(row.key) end)
            rows[index] = row
        end
        return row
    end

    local function drawWanted()
        local peer = inspector.peer
        local heard = peer and ACB.heardWanted and ACB.heardWanted[peer]
        wantedTitle:SetText(peer and (displayName(peer) .. " is looking for") or "")
        local keys = {}
        for _, key in ipairs(heard and heard.cards or {}) do
            if ACB.cards[key] then keys[#keys + 1] = key end
        end
        wantedNote:SetText(#keys > 0 and "Press Trade on a card you own to give it, then pick a card of theirs in return."
            or heard and "They are not looking for any card."
            or "Their list has not arrived. Close this window and view their binder again in a few seconds.")
        for index, key in ipairs(keys) do
            local card, row = ACB.cards[key], rowFor(index)
            local mine = saved.counts[key] or 0
            local note = mine >= 2 and ("|cff33ff4dyou have a spare (%d)|r"):format(mine)
                or mine == 1 and "you have one" or "you do not have it"
            row.key = key
            row.text:SetText(("%s    %s, %s    (%s)"):format(card.name, ACB.pages[card.page].title,
                ACB.rarities[card.rarity].name, note))
            row.text:Show()
            row.button:Show()
            row.button:SetEnabled(mine >= 1)
        end
        for index = #keys + 1, #rows do
            rows[index].text:Hide()
            rows[index].button:Hide()
        end
        body:SetHeight(math.max(100, #keys * ROW))
        scroll:SetVerticalScroll(0)
    end

    -- The tabs are coloured like the binder's own: the open one is light, the others dark.
    local tabs = {}
    function highlight(open)
        for name, control in pairs(tabs) do
            local active = name == open
            control.frame:SetBackdropColor(unpack(active and { 0.82, 0.67, 0.43, 1 } or { 0.20, 0.13, 0.09, 1 }))
            control.title:SetTextColor(unpack(active and { 0.22, 0.13, 0.07, 1 } or kit.parchment))
        end
    end
    local function turnTo(index)
        showingIndex = index
        wantedPanel:Hide()
        highlight(index and "index" or "collection")
        folio:showRegion(currentSet, showingIndex)
    end
    tabs.index = kit.tab(inspector, "Index", 1, function() turnTo(true) end)
    tabs.collection = kit.tab(inspector, "Collection", 2, function() turnTo(false) end)
    tabs.wanted = kit.tab(inspector, "Wanted", 3, function()
        drawWanted()
        wantedPanel:Show()
        highlight("wanted")
    end)
    highlight("collection")

    -- Report this player for cheating. The second click, within a few seconds, is the one that counts, so one slip sends
    -- nothing; for another reason, or to add a note, use /acb report.
    local confirmUntil = 0
    local reportButton
    reportButton = kit.button(inspector, "Report", 30 + 3 * 127, 78, 116, function()
        if not inspector.peer then return end
        if now() > confirmUntil then
            confirmUntil = now() + 6
            reportButton:SetText("Click to confirm")
            after(6, function() if now() >= confirmUntil then reportButton:SetText("Report") end end)
            report(("Report %s for cheating? Click Report again within a few seconds. For another reason, type /acb report."):format(inspector.peer))
            return
        end
        confirmUntil = 0
        reportButton:SetText("Report")
        local ok, problem = ACB.addReport(saved, inspector.peer, "cheating", "", time())
        report(ok and ("Report about %s saved. The companion app sends it the next time it syncs."):format(inspector.peer) or problem)
    end)

    -- The trade window, with this player already entered (for a swap made by hand). While you are choosing a card, the
    -- same button cancels the choice.
    tradeButton = kit.button(inspector, "Offer a trade", 30 + 4 * 127, 78, 116, function()
        if picking then
            stopPicking()
            drawSummary()
            folio:showRegion(currentSet, showingIndex)
        elseif inspector.peer and ACB.prepareTrade then
            ACB.prepareTrade(inspector.peer)
            inspector:Hide()
        end
    end)

    -- How many cards they have, and what could be swapped.
    summary = inspector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", inspector, "TOPLEFT", 700, -80)
    summary:SetWidth(210)
    summary:SetJustifyH("RIGHT")
    summary:SetTextColor(unpack(kit.brass))
    function drawSummary()
        if picking then
            summary:SetText(("Giving your %s.\nPick a card of theirs."):format(ACB.cards[picking.give].name))
            return
        end
        local owned, total = 0, 0
        for index = 1, #ACB.pages do
            local have, cards = ACB.progress(seen.counts, index)
            owned, total = owned + have, total + cards
        end
        local theyHave, iHave = ACB.swapSuggestions(saved.counts, seen.counts, saved.wanted)
        summary:SetText(("%d of %d cards\n%d spares you need, %d of yours they need"):format(owned, total, #theyHave, #iHave))
    end

    local function firstStartedSet(counts)
        for index, page in ipairs(ACB.pages) do
            if #page.cards > 0 and ACB.progress(counts, index) > 0 then return index end
        end
        return 1
    end

    function ACB.showInspect(peer, counts, shiny)
        local sameBinder = inspector.peer == peer and inspector:IsShown()
        inspector.peer, seen.counts, seen.shiny = peer, counts, shiny
        local heard = ACB.heardWanted and ACB.heardWanted[peer]
        seen.wanted = {}
        for _, key in ipairs(heard and heard.cards or {}) do seen.wanted[key] = true end
        inspector.heading:SetText(displayName(peer) .. "'s Binder" .. (ACB.isVerified(peer) and " (verified)" or ""))
        if not sameBinder then
            currentSet, showingIndex = firstStartedSet(counts), false
            stopPicking()
            wantedPanel:Hide()
            highlight("collection")
        end
        drawSummary()
        local scale = math.min(1, (UIParent:GetWidth() - 24) / 940, (UIParent:GetHeight() - 24) / 644)
        if scale > 0 then inspector:SetScale(scale) end
        folio:showRegion(currentSet, showingIndex)
        if wantedPanel:IsShown() then drawWanted() end
        inspector:Show()
    end

    -- Draw the binder window again, if it is open for this player (their wanted list has just arrived).
    function ACB.refreshInspect(peer)
        if inspector:IsShown() and inspector.peer == peer and seen.counts then ACB.showInspect(peer, seen.counts, seen.shiny) end
    end
end
