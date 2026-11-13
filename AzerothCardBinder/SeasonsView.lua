local _, ACB = ...
local ui = ACB.folioUi
local function dateText(at) return date and date("%d %b %H:%M", at) or tostring(at) end
local function rewardText(reward)
    local lines = {}
    if reward.title ~= "" then lines[#lines + 1] = "Title: " .. reward.title end
    for _, pack in ipairs(reward.packs) do
        local info = ACB.packInfo(pack.pack)
        lines[#lines + 1] = ("%d %s pack%s: %s"):format(pack.count, info and ACB.packTiers[info.tier].name or "", pack.count == 1 and "" or "s", info and info.page.title or pack.pack)
    end
    return #lines > 0 and table.concat(lines, "\n") or "No pack or title reward."
end

function ACB.createSeasonsView(parent, saved)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    local left, right = ui.paper(view, 20), ui.paper(view, 471, true)
    local preload = ACB.createPortraitLoader(view, left)
    local warmed
    view:SetScript("OnHide", function() preload(); warmed = nil end)
    local seasonIndex, leaf, selected = 1, 1, 1
    local label = ui.text(left, 23, 17, "SEASONAL COLLECTION", 10, ui.SEPIA, 390)
    local heading = ui.text(left, 23, 35, "Seasons", 29, ui.INK, 402, "LEFT", true)
    heading:SetWordWrap(false); heading:SetHeight(35)
    local timing = ui.text(left, 23, 76, "", 11, ui.SEPIA, 402)
    local bar = ui.progressBar(left, 23, 94, 402)
    local seasonName = ui.text(right, 23, 17, "RANKED / ALONGSIDE YOUR BINDER", 10, ui.SEPIA, 402)
    local name = ui.text(right, 23, 37, "", 24, ui.INK, 402, "LEFT", true)
    name:SetWordWrap(false); name:SetHeight(30)
    local status = ui.text(right, 23, 77, "", 12, ui.SEPIA, 402)
    local big = ui.mountCard(right, 30, 112, 1.55, function(entry) ACB.linkCard(saved, entry) end)
    local rewardScroll = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
    rewardScroll:SetPoint("TOPLEFT", 260, -116); rewardScroll:SetSize(148, 230)
    local rewardBody = CreateFrame("Frame", nil, rewardScroll)
    rewardBody:SetSize(148, 230); rewardScroll:SetScrollChild(rewardBody)
    local rewards = ui.text(rewardBody, 0, 0, "", 12, ui.INK, 148)
    rewards:SetWordWrap(true)
    local function setRewards(value)
        if rewards.value == value then return end
        rewards.value = value
        local _, lines = value:gsub("\n", "")
        local height = math.max(230, (math.ceil(#value / 17) + lines + 1) * 14)
        rewardBody:SetHeight(height); rewards:SetHeight(height); rewards:SetText(value)
        rewardScroll:SetVerticalScroll(0)
    end
    local explanation = ui.text(right, 24, 417, "", 11, ui.SEPIA, 401)
    explanation:SetHeight(35); explanation:SetWordWrap(true)
    local claim = ACB.uiKit.button(right, "Claim packs", 260, 360, 165, function()
        local amount = ACB.claimSeasonRewards(saved, ACB.ledger)
        if amount > 0 then
            if ACB.playSound then ACB.playSound("pack_found") end
        end
        view:refresh()
    end)
    local open = ACB.uiKit.button(right, "Open in binder", 30, 410, 211, function()
        local data = ACB.seasonData(saved)
        local season = data and data.seasons[seasonIndex]
        if season then ACB.openCard(season.cards[selected]) end
    end)
    -- Move the note below the preview action, keeping both clear of the page controls.
    explanation:ClearAllPoints(); explanation:SetPoint("TOPLEFT", right, "TOPLEFT", 24, -440); explanation:SetHeight(28)
    local pockets = {}
    for index = 1, 4 do
        local x, y = 23 + ((index - 1) % 2) * 205, 105 + math.floor((index - 1) / 2) * 168
        local pocket = ui.panel(left, "Button", x, y, 197, 159, ui.POCKET, ui.EDGE)
        local card = ui.mountCard(pocket, 58, 6, .60)
        local title = ui.text(pocket, 4, 124, "", 14, ui.INK, 189, "CENTER", true)
        local state = ui.text(pocket, 4, 143, "", 10, ui.SEPIA, 189, "CENTER")
        pocket:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        pocket:SetScript("OnClick", function() selected = (leaf - 1) * 4 + index; view:refresh() end)
        pockets[index] = { frame = pocket, card = card, title = title, state = state }
    end
    local previous = ui.turnButton(left, 23, "< Back", function() leaf = leaf - 1; selected = (leaf - 1) * 4 + 1; view:refresh() end)
    local nextPage = ui.turnButton(left, 353, "Next >", function() leaf = leaf + 1; selected = (leaf - 1) * 4 + 1; view:refresh() end)
    local page = ui.text(left, 103, 461, "", 11, ui.SEPIA, 240, "CENTER")
    local prevSeason = ACB.uiKit.button(right, "< Season", 24, 471, 105, function() seasonIndex = seasonIndex - 1; leaf, selected = 1, 1; view:refresh() end)
    local nextSeason = ACB.uiKit.button(right, "Season >", 320, 471, 105, function() seasonIndex = seasonIndex + 1; leaf, selected = 1, 1; view:refresh() end)
    local count = ui.text(right, 135, 477, "", 11, ui.SEPIA, 179, "CENTER")
    function view:refresh()
        ACB.seasonRewardTitles(saved)
        local data = ACB.seasonData(saved)
        local seasons = data and data.seasons or {}
        seasonIndex = math.max(1, math.min(#seasons, seasonIndex))
        local season = seasons[seasonIndex]
        for _, pocket in ipairs(pockets) do pocket.frame:SetShown(season ~= nil) end
        big.holder:SetShown(season ~= nil)
        claim:SetShown(season ~= nil); open:SetShown(season ~= nil)
        previous:SetShown(season ~= nil); nextPage:SetShown(season ~= nil)
        prevSeason:SetShown(#seasons > 1); nextSeason:SetShown(#seasons > 1)
        prevSeason:SetEnabled(seasonIndex > 1); nextSeason:SetEnabled(seasonIndex < #seasons)
        count:SetText(#seasons > 1 and (seasonIndex .. " / " .. #seasons) or "")
        if not season then
            heading:SetText("The next adventure")
            timing:SetText("No season is scheduled yet."); label:SetText("SEASONAL COLLECTION")
            name:SetText("A fresh hunt, together")
            status:SetText("Your normal binder keeps growing.")
            setRewards("Collect a shared list of cards before the deadline.\n\nFinish for rewards; place early for a bonus.")
            explanation:SetText(data and "New seasons appear after your companion syncs and you reload." or "Update the companion, sync your binder, then /reload to see seasons.")
            bar:set(0, 0); page:SetText(""); return
        end
        if warmed ~= season.id then
            local entries = {}
            for _, key in ipairs(season.cards) do if ACB.cards[key] then entries[#entries + 1] = ACB.cards[key] end end
            preload(entries); warmed = season.id
        end
        local have, pending, amount = ACB.seasonProgress(saved, season)
        local now = time()
        local phase = now < season.startsAt and "Starts " or now >= season.endsAt and "Ended " or "Ends "
        heading:SetText(season.title); timing:SetText(phase .. dateText(now < season.startsAt and season.startsAt or season.endsAt))
        label:SetText(("SEASONAL COLLECTION / %d OF %d VERIFIED"):format(amount, #season.cards)); bar:set(amount, #season.cards)
        leaf = math.max(1, math.min(math.ceil(#season.cards / 4), leaf))
        selected = math.max(1, math.min(#season.cards, selected))
        for index, pocket in ipairs(pockets) do
            local key = season.cards[(leaf - 1) * 4 + index]
            local entry = key and ACB.cards[key]
            pocket.frame:SetShown(entry ~= nil)
            if entry then
                ui.setCard(pocket.card, entry, have[key] and 1 or 0, saved.shiny[key])
                pocket.title:SetText(entry.name)
                pocket.state:SetText(have[key] and "Collected this season" or pending[key] and "Awaiting verification" or "Collect a new copy")
            end
        end
        local key = season.cards[selected]
        local entry = ACB.cards[key]
        big.holder:SetShown(entry ~= nil); open:SetEnabled(entry ~= nil)
        if entry then ui.setCard(big, entry, have[key] and 1 or 0, saved.shiny[key]) end
        name:SetText(entry and entry.name or "Update the addon for this card")
        status:SetText(season.place > 0 and ("Finished / place #" .. season.place) or (have[key] and "Verified for this season" or pending[key] and "Awaiting verification" or "Find or trade for a new copy"))
        local r = season.rewards
        setRewards("FOR FINISHING\n" .. rewardText(r.completion) .. (r.first.places > 0 and ("\n\nFIRST " .. r.first.places .. " FINISHERS\n" .. rewardText(r.first)) or ""))
        local ready = ACB.seasonRewardsReady(saved)
        claim:SetText(ready > 0 and ("Claim packs (" .. ready .. ")") or "No packs to claim")
        claim:SetEnabled(ready > 0 and ACB.ledger ~= nil and not ACB.ledger:backlogFull())
        explanation:SetText(saved.mode ~= "ranked" and "Seasons need a clean Ranked binder. Your Casual cards stay safe." or "New copies also join your normal binder. Sync before the deadline; trades wait for verification.")
        previous:SetEnabled(leaf > 1); nextPage:SetEnabled(leaf < math.ceil(#season.cards / 4))
        page:SetText(("Page %d / %d"):format(leaf, math.ceil(#season.cards / 4)))
        seasonName:SetText("RANKED / ALONGSIDE YOUR BINDER")
    end
    view:Hide()
    return view
end
