local _, ACB = ...
local ui, kit = ACB.folioUi, ACB.uiKit

function ACB.guildCardRows(saved, inventory, giving, spares, query)
    local rows = {}
    query = (query or ""):lower()
    for key, count in pairs(giving and (saved.counts or {}) or inventory) do
        local card = ACB.cards[key]
        if card and count > 0 and (not giving or not spares or count > 1)
            and (query == "" or card.name:lower():find(query, 1, true)) then
            rows[#rows + 1] = card
        end
    end
    table.sort(rows, function(a, b) return a.name == b.name and a.key < b.key or a.name < b.name end)
    return rows
end

function ACB.createGuildView(parent, saved)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    local left, right = ui.paper(view, 20), ui.paper(view, 471, true)
    ui.text(left, 23, 17, "YOUR GUILD'S COLLECTION", 10, ui.SEPIA, 402)
    local heading = ui.text(left, 23, 35, "Guild binder", 29, ui.INK, 402, "LEFT", true)
    heading:SetWordWrap(false); heading:SetHeight(36)
    local membership = ui.text(left, 23, 77, "", 11, ui.SEPIA, 402)
    local stats = {}
    for index, caption in ipairs({ "CARDS", "POINTS", "GUILD RANK" }) do
        local x = 23 + (index - 1) * 138
        ui.text(left, x, 106, caption, 9, ui.SEPIA, 126)
        stats[index] = ui.text(left, x, 121, "—", 20, ui.INK, 126, "LEFT", true)
    end
    ui.rule(left, 23, 148, 402)
    local giving, spares, leaf, selected = false, true, 1, nil
    local query, inventory, rows = "", {}, {}
    local browse = kit.button(left, "Guild collection", 23, 162, 195, function() giving = false; leaf = 1; view:refresh() end)
    local contribute = kit.button(left, "Donate cards", 230, 162, 195, function() giving = true; leaf = 1; view:refresh() end)
    local search = ui.panel(left, "EditBox", 23, 198, 290, 24, { .88, .80, .62 }, ui.EDGE)
    search:SetFontObject("GameFontHighlightSmall"); search:SetTextColor(unpack(ui.INK))
    search:SetTextInsets(7, 7, 0, 0); search:SetAutoFocus(false)
    local hint = ui.text(search, 7, 6, "Search cards…", 11, ui.SEPIA, 270)
    search:SetScript("OnTextChanged", function(self)
        query = self:GetText() or ""; hint:SetShown(query == ""); leaf = 1; view:refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local filter = kit.button(left, "Spare copies", 323, 198, 102, function() spares = not spares; leaf = 1; view:refresh() end)
    local slots = {}
    for index = 1, 8 do
        local row = ui.panel(left, "Button", 23, 231 + (index - 1) * 27, 402, 24, ui.POCKET, ui.EDGE)
        local title = ui.text(row, 7, 5, "", 12, ui.INK, 267)
        title:SetWordWrap(false)
        local count = ui.text(row, 277, 6, "", 10, ui.SEPIA, 118, "RIGHT")
        row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        row:SetScript("OnClick", function() selected = rows[(leaf - 1) * 8 + index].key; view:refresh() end)
        slots[index] = { frame = row, title = title, count = count }
    end
    local previous = ui.turnButton(left, 23, "Previous", function() leaf = leaf - 1; view:refresh() end)
    local nextPage = ui.turnButton(left, 353, "Next", function() leaf = leaf + 1; view:refresh() end)
    local page = ui.text(left, 103, 461, "", 11, ui.SEPIA, 240, "CENTER")
    local waiting = ui.text(left, 23, 486, "", 10, ui.SEPIA, 402)
    local empty = ui.text(left, 38, 270, "", 15, ui.INK, 372, "CENTER")
    empty:SetWordWrap(true); empty:SetHeight(130)
    ui.text(right, 23, 17, "A COLLECTION YOU BUILD TOGETHER", 10, ui.SEPIA, 402)
    local name = ui.text(right, 23, 37, "Guild binder", 25, ui.INK, 402, "LEFT", true)
    name:SetWordWrap(false); name:SetHeight(33)
    local note = ui.text(right, 23, 78, "", 11, ui.SEPIA, 402)
    local big = ui.mountCard(right, 30, 113, 1.55, function(entry) ACB.linkCard(saved, entry) end)
    ui.text(right, 260, 127, "IN YOUR GUILD", 10, ui.SEPIA, 165)
    local guildCount = ui.text(right, 260, 151, "—", 31, ui.INK, 165, "LEFT", true)
    ui.text(right, 260, 217, "IN YOUR BINDER", 10, ui.SEPIA, 165)
    local ownCount = ui.text(right, 260, 241, "—", 31, ui.INK, 165, "LEFT", true)
    local terms = ui.text(right, 260, 309, "Donated cards stay with the guild. Nobody can withdraw them.", 12, ui.SEPIA, 160)
    terms:SetWordWrap(true); terms:SetHeight(86)
    ui.rule(right, 23, 412, 402)
    local reason = ui.text(right, 23, 423, "", 11, ui.SEPIA, 402, "CENTER")
    reason:SetWordWrap(true); reason:SetHeight(30)
    local confirm = kit.window("AzerothCardBinderGuildConfirm", 460, 262, "Donate to your guild")
    confirm:SetFrameStrata("FULLSCREEN_DIALOG")
    local question = kit.label(confirm, "GameFontHighlight", 25, 57, kit.parchment, "")
    question:SetWidth(410); question:SetHeight(136); question:SetWordWrap(true)
    local pending
    local cancel = kit.button(confirm, "Keep card", 25, 212, 195, function() pending = nil; confirm:Hide() end)
    local accept = kit.button(confirm, "Donate one copy", 236, 212, 199, function()
        local choice = pending
        pending = nil; confirm:Hide()
        local guild = ACB.guildMembership(saved)
        if not choice or not guild or guild.id ~= choice.guild then
            ACB.say("Your guild changed. Select the card again before donating."); return
        end
        local ok, result = ACB.donateCard(saved, ACB.ledger, choice.key)
        ACB.say(ok and "Donation saved. Sync with the companion, then /reload to see it in the guild binder." or result)
        view:refresh()
    end)
    local donate = kit.button(right, "Donate one copy", 23, 460, 245, function()
        local ok, guild = ACB.canDonate(saved, ACB.ledger, selected)
        if not ok then ACB.say(guild); return end
        pending = { key = selected, guild = guild.id }
        local last = (saved.counts[selected] or 0) == 1
        question:SetText(("Give one %s to %s?\n\n%sThe card leaves your binder permanently. Nobody can take it out of the guild binder.")
            :format(ACB.cards[selected].name, guild.name, last and "This is your last copy.\n" or ""))
        confirm:Show()
    end)
    kit.button(right, "Wanted lists", 279, 460, 146, function() ACB.open("wanted") end)
    ui.text(right, 23, 488, "Save and sync, then /reload to refresh this page.", 10, ui.SEPIA, 402, "CENTER")
    view:SetScript("OnHide", function() pending = nil; confirm:Hide(); search:ClearFocus() end)
    function view:refresh()
        local data = ACB.guildData(saved)
        local guild, role = ACB.guildMembership(saved)
        local summary = guild and data and data.summary
        if summary and summary.guildId ~= guild.id then summary = nil end
        inventory = {}
        for _, entry in ipairs(summary and summary.inventory or {}) do inventory[entry.card] = entry.copies end
        heading:SetText(guild and guild.name or "Guild binder")
        heading:SetFont(ui.DISPLAY_FONT, guild and math.max(19, math.min(29, 630 / #guild.name)) or 29, "")
        membership:SetText(guild and (guild.realm .. "  /  " .. (role == "owner" and "Guild owner" or "Member")) or "Build a shared collection with your guild.")
        stats[1]:SetText(summary and tostring(summary.cards) or "—")
        stats[2]:SetText(summary and ACB.pointsText(summary.points) or "—")
        stats[3]:SetText(summary and summary.rank and ("#" .. summary.rank) or "—")
        local active = guild ~= nil and summary ~= nil
        browse:SetEnabled(active and giving); contribute:SetEnabled(active and not giving)
        search:SetShown(active); filter:SetShown(active and giving)
        filter:SetText(spares and "Spare copies" or "All owned")
        rows = active and ACB.guildCardRows(saved, inventory, giving, spares, query) or {}
        leaf = math.max(1, math.min(math.max(1, math.ceil(#rows / 8)), leaf))
        local found
        for _, entry in ipairs(rows) do if entry.key == selected then found = true end end
        if not found then selected = rows[(leaf - 1) * 8 + 1] and rows[(leaf - 1) * 8 + 1].key end
        for index, slot in ipairs(slots) do
            local entry = rows[(leaf - 1) * 8 + index]
            slot.frame:SetShown(entry ~= nil)
            if entry then
                slot.title:SetText(entry.name)
                slot.count:SetText(("%d guild / %d you"):format(inventory[entry.key] or 0, saved.counts[entry.key] or 0))
                slot.frame:SetBackdropColor(unpack(entry.key == selected and ui.SELECTED or ui.POCKET))
            end
        end
        previous:SetShown(active); nextPage:SetShown(active)
        previous:SetEnabled(leaf > 1); nextPage:SetEnabled(leaf * 8 < #rows)
        page:SetText(active and ("Page " .. leaf .. " / " .. math.max(1, math.ceil(#rows / 8))) or "")
        local pendingCount = ACB.pendingDonationCount(saved)
        waiting:SetText(pendingCount > 0 and ("%d donation%s waiting for sync"):format(pendingCount, pendingCount == 1 and "" or "s") or "")
        empty:SetShown(#rows == 0)
        local member = data and data.membership
        empty:SetText(not guild and (member and member.state == "pending" and "Your guild application is waiting for its owner.\n\nThe companion app will show the decision." or
            "Create or join a guild binder in the companion app.\n\nNew binders are ready straight away. Members are approved by their guild binder's owner.") or not summary and
            "Update and sync the companion, then /reload to load your guild's collection." or giving and
            "No cards match this list.\n\nChoose All owned to include your last copies, or change your search." or
            (query ~= "" and "No cards match this search.\n\nTry another card name." or "Your guild binder is waiting for its first card.\n\nChoose Donate cards to get it started."))
        local card = selected and ACB.cards[selected]
        big.holder:SetShown(card ~= nil)
        if card then ui.setCard(big, card, math.max(inventory[selected] or 0, saved.counts[selected] or 0), giving and saved.shiny[selected]) end
        name:SetText(card and card.name or "A shared collection")
        name:SetFont(ui.DISPLAY_FONT, card and math.max(17, math.min(25, 680 / #card.name)) or 25, "")
        note:SetText(giving and "Choose a card from your binder to donate." or "Cards your guild has collected together.")
        guildCount:SetText(active and tostring(inventory[selected] or 0) or "—")
        ownCount:SetText(card and tostring(saved.counts[selected] or 0) or "—")
        local ok, why = false, "Choose a card to donate."
        if card and active then ok, why = ACB.canDonate(saved, ACB.ledger, selected) end
        donate:SetEnabled(ok)
        reason:SetText(ok and ((saved.counts[selected] or 0) == 1 and "This is your last copy. Donating removes it from your binder." or "One copy will leave your binder permanently.") or why)
    end
    view.controls = { donate = donate, confirm = confirm, accept = accept, cancel = cancel, contribute = contribute, browse = browse, filter = filter, search = search }
    return view
end
