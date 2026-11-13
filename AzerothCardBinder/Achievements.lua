local _, ACB = ...

ACB.achievementTracks = {
    { label = "Cards collected", metric = "cards", entries = {
        { key = "cards10", goal = 10, name = "First Page", title = "Card Seeker" },
        { key = "cards50", goal = 50, name = "A Growing Collection", title = "Card Collector" },
        { key = "cards250", goal = 250, name = "Azeroth in Miniature", title = "Card Archivist" },
        { key = "cards1000", goal = 1000, name = "A Thousand Stories", title = "Grand Archivist" },
    } },
    { label = "Sets completed", metric = "sets", entries = {
        { key = "sets1", goal = 1, name = "The Final Pocket", title = "Set Keeper" },
        { key = "sets5", goal = 5, name = "Five Chapters", title = "Folio Curator" },
        { key = "sets15", goal = 15, name = "Across the Map", title = "Lore Collector" },
        { key = "sets30", goal = 30, name = "The Living Atlas", title = "Keeper of the Atlas" },
    } },
    { label = "Cards traded", metric = "trades", entries = {
        { key = "trades1", goal = 1, name = "A Fair Exchange", title = "Card Trader" },
        { key = "trades10", goal = 10, name = "Regular at the Market", title = "Deal Maker" },
        { key = "trades25", goal = 25, name = "Spare for Spare", title = "Card Broker" },
        { key = "trades100", goal = 100, name = "A Hundred Handshakes", title = "Master Broker" },
    } },
    { label = "Shiny cards", metric = "shiny", entries = {
        { key = "shiny1", goal = 1, name = "A Glint of Gold", title = "Shiny Seeker" },
        { key = "shiny5", goal = 5, name = "Caught the Light", title = "Foil Hunter" },
        { key = "shiny15", goal = 15, name = "All That Glitters", title = "Foil Curator" },
        { key = "shiny50", goal = 50, name = "A Dazzling Display", title = "Keeper of the Glint" },
    } },
    { label = "Deadmines", entries = ACB.achievements },
}

local milestoneTitles = {}
for _, track in ipairs(ACB.achievementTracks) do
    for _, entry in ipairs(track.entries) do milestoneTitles[entry.title] = true end
end

function ACB.isBinderTitle(title)
    if type(title) ~= "string" or #title > 100 then return false end
    if milestoneTitles[title] then return true end
    if ACB.seasonTitleKnown and ACB.seasonTitleKnown(title) then return true end
    for _, page in ipairs(ACB.pages) do
        if page.reward == title then return true end
    end
    return false
end

function ACB.earnedTitles(saved)
    local earned = {}
    local titles = saved.titles or {}
    -- Keep existing set titles in their original order for /acb title <number>.
    for _, page in ipairs(ACB.pages) do
        if page.reward and titles[page.reward] then earned[#earned + 1] = page.reward end
    end
    for _, track in ipairs(ACB.achievementTracks) do
        for _, entry in ipairs(track.entries) do
            if titles[entry.title] then earned[#earned + 1] = entry.title end
        end
    end
    local seasonal = {}
    for title in pairs(saved.seasonTitles or {}) do if titles[title] then seasonal[#seasonal + 1] = title end end
    table.sort(seasonal)
    for _, title in ipairs(seasonal) do
        local seen = false
        for _, existing in ipairs(earned) do if existing == title then seen = true end end
        if not seen then earned[#earned + 1] = title end
    end
    return earned
end

function ACB.selectTitle(saved, title)
    if title and not saved.titles[title] then return end
    saved.title, saved.titleHidden = title, title == nil or nil
end

function ACB.achievementTotals(saved)
    local totals = { cards = 0, sets = 0, trades = saved.tradeCount or 0, shiny = 0 }
    local creatures = {}
    for key, count in pairs(saved.counts) do
        if count > 0 and ACB.cards[key] then
            local base = ACB.baseCard(ACB.cards[key]).key
            if not creatures[base] then totals.cards = totals.cards + 1; creatures[base] = true end
            if saved.shiny and saved.shiny[key] then totals.shiny = totals.shiny + 1 end
        end
    end
    for _, page in ipairs(ACB.pages) do
        if saved.sets and saved.sets[page.code] then totals.sets = totals.sets + 1 end
    end
    return totals
end

function ACB.achievementProgress(saved, totals, track, entry)
    if track.metric then return totals[track.metric], entry.goal end
    return ACB.progress(saved.counts, 1, entry.bossesOnly)
end

function ACB.updateAchievements(saved, report)
    saved.achievements, saved.titles = saved.achievements or {}, saved.titles or {}
    local totals = ACB.achievementTotals(saved)
    for _, track in ipairs(ACB.achievementTracks) do
        for _, entry in ipairs(track.entries) do
            local have, goal = ACB.achievementProgress(saved, totals, track, entry)
            if not saved.achievements[entry.key] and goal > 0 and have >= goal then
                saved.achievements[entry.key] = true
                if report then
                    report((track.metric and "Milestone earned: " or "Binder achievement: ") .. entry.name
                        .. ". Title earned: " .. entry.title)
                end
            end
            if saved.achievements[entry.key] then saved.titles[entry.title] = true end
        end
    end
end
