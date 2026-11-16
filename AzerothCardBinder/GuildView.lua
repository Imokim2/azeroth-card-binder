local _, ACB = ...
local ui, kit = ACB.folioUi, ACB.uiKit

function ACB.createGuildView(parent, saved)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    local seen = { counts = {}, shiny = {}, wanted = {}, achievements = {}, attempts = {}, misses = {}, dust = 0 }
    local giving, spares, region, indexShown = false, true, 1, true
    local tray, guildID, reviewed = {}, nil, nil
    local confirmed, pending, folio, review = {}, {}, nil, nil
    local summary, active
    local function total()
        local count = 0
        for _, copies in pairs(tray) do count = count + copies end
        return count
    end
    local function available(key)
        return math.max(0, (saved.counts[key] or 0) - (spares and 1 or 0) - (tray[key] or 0))
    end
    local function allowed(key)
        return giving and active and available(key) > 0 and total() + ACB.pendingDonationCount(saved) < ACB.maxPendingDonations
            and ACB.canDonate(saved, ACB.ledger, key) == true
    end
    local function add(key, toggle)
        if toggle and tray[key] then tray[key] = nil
        elseif allowed(key) then tray[key] = (tray[key] or 0) + 1
        else return end
        view:refresh()
    end
    folio = ACB.createFolio(view, seen, function(setIndex)
        region, indexShown = setIndex, false; view:refresh()
    end, {
        mine = function() return saved.counts end,
        onOpenCard = function(card) region, indexShown = card.page, false end,
        progressCounts = function() return giving and saved.counts or confirmed end,
        ownedCount = function(card, count) return giving and count or (confirmed[card.key] or 0) end,
        collectionStatus = function(card, count)
            if giving then return count > 0 and "Collected" or "Undiscovered" end
            return (confirmed[card.key] or 0) > 0 and "Collected" or (pending[card.key] or 0) > 0 and "Pending" or "Undiscovered"
        end,
        heading = function()
            return giving and "YOUR BINDER  /  CHOOSE DONATIONS"
                or ("GUILD COLLECTION  /  %d CONFIRMED CARDS"):format(summary and summary.cards or 0)
        end,
        pickPocket = function(key) if giving then add(key, true) end end,
        pocketStatus = function(card, count)
            if giving then
                return tray[card.key] and ("%d selected / %d owned"):format(tray[card.key], saved.counts[card.key] or 0)
                    or (count > 0 and (spares and count == 1 and "Last copy / choose All owned" or ("%d owned / click to select"):format(count)) or "Missing")
            end
            local waiting, owned = ACB.familyCount(pending, card), ACB.familyCount(confirmed, card)
            return waiting > 0 and ("%d confirmed / %d waiting for sync"):format(owned, waiting)
                or (owned > 0 and ("%d in guild binder"):format(owned) or "Missing from guild binder")
        end,
        status = function(card)
            if giving then return ("%d selected / %d available"):format(tray[card.key] or 0, available(card.key)) end
            return ("%d confirmed / %d waiting\nYou own: %d"):format(confirmed[card.key] or 0, pending[card.key] or 0, saved.counts[card.key] or 0)
        end,
        note = function(card)
            if giving then return (tray[card.key] or 0) > 0 and "Selected only. Review the tray before anything leaves your binder."
                or "Click a card to select it. Add one copy below to select extra spares." end
            local donor
            for _, entry in ipairs(summary and summary.inventory or {}) do
                if entry.card == card.key and entry.donor and entry.donor ~= "" then donor = entry.donor end
            end
            if donor then return "Latest donation: " .. donor:gsub("|", ""):gsub("%-", " "):gsub("%a[%w']*", function(word) return word:sub(1, 1):upper() .. word:sub(2) end) end
            return (pending[card.key] or 0) > 0 and "Waiting for sync. These copies do not count towards confirmed guild progress yet."
                or ((confirmed[card.key] or 0) > 0 and card.lore or ("Missing from the guild binder. " .. ACB.whereToFind(card)))
        end,
    })
    local messageLeft, messageRight = ui.paper(view, 20), ui.paper(view, 471, true)
    ui.text(messageLeft, 23, 35, "Guild binder", 32, ui.INK, 402, "LEFT", true)
    local message = ui.text(messageLeft, 23, 112, "", 16, ui.INK, 402)
    message:SetWordWrap(true); message:SetHeight(230)
    ui.text(messageRight, 23, 35, "A collection together", 29, ui.INK, 402, "LEFT", true)
    local instructions = ui.text(messageRight, 23, 112, "Create or join a guild binder in the companion. New binders are ready immediately; the binder owner approves new members.\n\nBrowse the full collection or choose Donate cards. Select several cards and review them together.\n\nDonations are permanent. Nobody can withdraw them.", 14, ui.SEPIA, 402)
    instructions:SetWordWrap(true); instructions:SetHeight(280)
    folio:compactFooter()
    local selection = ui.text(view, 494, 566, "", 10, ui.SEPIA, 401, "RIGHT")
    local controls = {}
    controls.browse = kit.button(view, "Guild index", 250, 53, 120, function()
        tray, reviewed = {}, nil; review:Hide()
        giving, indexShown = false, true; folio:setIndexOwnership("all"); view:refresh()
    end)
    controls.contribute = kit.button(view, "Add cards", 382, 53, 120, function()
        giving, indexShown = true, false
        local focus
        local order = { region }
        for _, setIndex in ipairs(ACB.setOrder()) do if setIndex ~= region then order[#order + 1] = setIndex end end
        for _, setIndex in ipairs(order) do
            for _, base in ipairs(ACB.pages[setIndex].cards) do
                for _, card in ipairs(ACB.cardEditions(base)) do
                    if not focus and available(card.key) > 0 then focus = card end
                end
            end
            if focus then break end
        end
        if focus then region = focus.page; folio:selectCard(region, focus.key) end
        folio:setIndexOwnership("owned"); view:refresh()
    end)
    controls.index = kit.button(view, "Your card index", 382, 53, 120, function() indexShown = true; view:refresh() end)
    controls.stop = kit.button(view, "Cancel", 790, 53, 110, function()
        tray, reviewed, giving, indexShown = {}, nil, false, true
        review:Hide(); folio:setIndexOwnership("all"); view:refresh()
    end)
    controls.filter = kit.button(view, "Spare copies", 494, 584, 110, function() spares = not spares; view:refresh() end)
    local function openReview()
        local plan, why = ACB.guildBatchPlan(saved, ACB.ledger, tray, guildID)
        if not plan then ACB.say(why); return end
        reviewed = plan; review:present(plan)
    end
    controls.review = kit.button(view, "Review selected (0)", 646, 53, 132, openReview)
    controls.sync = kit.button(view, "Save & sync", 758, 584, 137, function()
        if total() == 0 and ACB.pendingDonationCount(saved) > 0 then saved.guildSyncHead = saved.head.hash; ReloadUI() end
    end)
    controls.wanted = kit.button(view, "Wanted lists", 43, 584, 106, function() ACB.open("wanted") end)
    for _, control in pairs(controls) do control:SetHeight(22) end
    review = ACB.createGuildReview(function(key)
        tray[key] = nil
        if total() > 0 then openReview() else reviewed = nil; review:Hide() end
        view:refresh()
    end, function()
        if not review:IsShown() then return end
        local choice = reviewed
        reviewed = nil; review:Hide()
        if not choice then return end
        local ok, why, done = ACB.donateGuildBatch(saved, ACB.ledger, choice)
        local left = done or 0
        for _, row in ipairs(choice.rows) do
            local used = math.min(left, row.count)
            if used > 0 then tray[row.key] = math.max(0, (tray[row.key] or 0) - used); if tray[row.key] == 0 then tray[row.key] = nil end end
            left = left - used
        end
        if ok then giving, indexShown = false, true; folio:setIndexOwnership("all") end
        ACB.say(why); view:refresh()
    end)
    review:SetScript("OnHide", function() reviewed = nil end)
    controls.confirm, controls.accept, controls.cancel = review, review.controls.accept, review.controls.cancel
    controls.donate, controls.rows, controls.warning = folio.tradeButton, review.controls.rows, review.controls.warning
    view.controls, view.folio = controls, folio
    function view:add(key) add(key) end
    function view:selection() return total(), tray end
    function view:open()
        tray, reviewed = {}, nil; review:Hide()
        giving, indexShown = false, true
        folio:setIndexOwnership("all")
    end
    function view:showCard(key)
        local card = ACB.cards[key]
        if card and folio:selectCard(card.page, key) then region, indexShown = card.page, false; self:refresh(); return true end
    end
    function view:refresh()
        local guild = ACB.guildMembership(saved)
        local currentID = guild and guild.id
        if currentID ~= guildID then tray, reviewed = {}, nil; review:Hide(); guildID = currentID end
        local data = ACB.guildData(saved)
        summary = data and data.summary
        if summary and summary.guildId ~= guildID then summary = nil end
        active = guild ~= nil and summary ~= nil
        local shown
        confirmed, pending, shown = ACB.guildInventoryView(saved, guildID)
        seen.counts, seen.shiny = giving and saved.counts or shown, giving and saved.shiny or {}
        seen.indexProgressCounts = giving and saved.counts or confirmed
        seen.indexCardStatus = not giving and function(card, count)
            local waiting = pending[card.key] or 0
            return waiting > 0 and ("%d + %d waiting"):format(count, waiting) or count > 0 and ("%d in guild"):format(count) or "Missing"
        end or nil
        seen.indexCardFilter = giving and function(card) return (saved.counts[card.key] or 0) > (spares and 1 or 0) end or nil
        folio:SetShown(active)
        messageLeft:SetShown(not active); messageRight:SetShown(not active)
        for _, name in ipairs({ "browse", "sync" }) do controls[name]:SetShown(active) end
        controls.contribute:SetShown(active and not giving)
        for _, name in ipairs({ "index", "review", "stop" }) do controls[name]:SetShown(active and giving) end
        controls.filter:SetShown(active and giving); controls.filter:SetText(spares and "Spare copies" or "All owned")
        local count, waiting = total(), ACB.pendingDonationCount(saved)
        controls.browse:SetEnabled(active and (giving or not indexShown)); controls.contribute:SetEnabled(active and not giving)
        controls.review:SetText(("Review selected (%d)"):format(count)); controls.review:SetEnabled(active and count > 0)
        controls.sync:SetEnabled(active and waiting > 0 and count == 0)
        local savedForSync = saved.guildSyncHead == saved.head.hash
        controls.sync:SetText(savedForSync and waiting > 0 and "Refresh after sync" or "Save & sync")
        selection:SetText(active and (count > 0 and ("%d selected. Review the tray before reloading."):format(count)
            or waiting > 0 and (savedForSync and "Saved. Allow the companion to sync, then refresh." or ("%d waiting. Keep the companion open, then Save & sync."):format(waiting))
            or ("%s  /  %s points  /  %s"):format(guild.name, ACB.pointsText(summary.points or 0), summary.rank and ("#" .. summary.rank) or "Unranked")) or "")
        if not active then
            message:SetText(guild and "Sync the companion and /reload to load your guild's collection." or data and data.membership and data.membership.state == "pending"
                and "Your application is waiting for the guild binder owner. Refresh in the companion after approval, then sync and /reload."
                or "You are not in a guild binder yet. Start or join one in the companion app.")
            return
        end
        local visible = {}
        for key, copies in pairs(saved.counts) do visible[key] = copies end
        for key, copies in pairs(shown) do visible[key] = math.max(visible[key] or 0, copies) end
        ACB.refreshVisibleCards({ counts = visible })
        folio:setTradePicker(giving and function(key) add(key) end or nil, allowed, "Add one copy to tray")
        folio:showRegion(region, indexShown)
    end
    view:SetScript("OnHide", function() tray, reviewed = {}, nil; review:Hide() end)
    return view
end
