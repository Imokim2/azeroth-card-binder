local _, ACB = ...

-- Sanitize every value from a game API before inspecting it.
function ACB.read(value, expectedType)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == expectedType then return value end
end

function ACB.source(guid)
    guid = ACB.read(guid, "string")
    if not guid then return end
    -- The numeric entry ID identifies the card. Treat the whole spawn token as opaque.
    local kind, id = guid:match("^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-[^%-]+$")
    local entries = kind and ACB.sources[kind]
    if entries then return entries[tonumber(id)], kind end
end

-- Remember finished trades, newest first.
function ACB.logTrade(saved, give, take, peer, when)
    saved.history = saved.history or {}
    table.insert(saved.history, 1, { give = give, take = take, peer = peer, time = when })
    while #saved.history > 20 do table.remove(saved.history) end
end

-- The trade history as printable lines.
function ACB.tradeHistory(saved)
    local lines = {}
    for _, entry in ipairs(saved.history or {}) do
        local out, into = ACB.cards[entry.give], ACB.cards[entry.take]
        if out and into then
            local stamp = entry.time and (date and date("%d %b %H:%M", entry.time) or tostring(entry.time)) or ""
            lines[#lines + 1] = ("%s   %s for %s   with %s"):format(stamp, out.name, into.name, entry.peer or "?")
        end
    end
    return lines
end

-- The cards a player is looking for: the ones they marked, or every card they are missing.
function ACB.wantedCards(saved)
    local marked, missing = {}, {}
    for _, page in ipairs(ACB.pages) do
        for _, card in ipairs(page.cards) do
            if (saved.counts[card.key] or 0) == 0 then
                missing[#missing + 1] = card.key
                if saved.wanted and saved.wanted[card.key] then marked[#marked + 1] = card.key end
            end
        end
    end
    return #marked > 0 and marked or missing
end

-- Attempts without a drop so far, and the attempt that is guaranteed, for a catalog card.
function ACB.luck(saved, card)
    local rate = ACB.rates[card.rank]
    local limit = (ACB.pityFactor or 0) > 0 and math.ceil(ACB.pityFactor * 10000 / rate) or nil
    return (saved.misses and saved.misses[card.key]) or 0, limit
end

function ACB.progress(counts, page, bossesOnly)
    local owned, total = 0, 0
    for _, card in ipairs(ACB.pages[page].cards) do
        if not bossesOnly or card.boss then
            total = total + 1
            if (counts[card.key] or 0) > 0 then owned = owned + 1 end
        end
    end
    return owned, total
end

-- `found` is called with the card and what happened whenever a card is added to the binder, and
-- `completed` with the set and its reward title the first time a set is finished.
function ACB.newCollection(saved, random, report, log, found, completed)
    found = found or function() end
    completed = completed or function() end
    local collection = { saved = saved, rolled = {} }

    -- The first time every card of a set is owned, record it and hand out the set's title.
    local function checkSet(card)
        local page = ACB.pages[card.page]
        local owned, total = ACB.progress(saved.counts, card.page)
        if not page or not page.code or total == 0 or owned < total then return end
        saved.sets = saved.sets or {}
        if saved.sets[page.code] then return end
        saved.sets[page.code] = true
        if page.reward then
            saved.titles = saved.titles or {}
            saved.titles[page.reward] = true
            saved.title = saved.title or page.reward
        end
        report(("Set complete: %s%s"):format(page.title, page.reward and (". Title earned: " .. page.reward) or ""))
        completed(page, page.reward)
    end

    local function checkAchievements(card)
        checkSet(card)
        if card.page ~= 1 then return end
        for _, achievement in ipairs(ACB.achievements) do
            local owned, total = ACB.progress(saved.counts, 1, achievement.bossesOnly)
            if owned == total and not saved.achievements[achievement.key] then
                saved.achievements[achievement.key] = true
                report("Binder achievement: " .. achievement.name)
            end
        end
    end

    function collection:roll(guid, origin, observedRank)
        local card = ACB.source(guid)
        if not card or (card.profession ~= nil) ~= (origin == "gather") then return end
        if origin == "encounter" and not card.boss then return end
        if self.rolled[guid] then
            log("Already rolled: " .. card.name .. " (" .. origin .. ")")
            return
        end

        self.rolled[guid] = true
        local threshold = ACB.rates[observedRank] or ACB.rates[card.rank]
        saved.misses = saved.misses or {}
        local misses = saved.misses[card.key] or 0
        local limit = (ACB.pityFactor or 0) > 0 and math.ceil(ACB.pityFactor * 10000 / threshold) or nil
        local guaranteed = limit ~= nil and misses + 1 >= limit
        local dropped = guaranteed or random(1, 10000) <= threshold
        log(("%s: %s at %g%% (%s)"):format(origin, card.name, threshold / 100,
            guaranteed and "card, bad-luck safety net" or dropped and "card" or "miss"))
        if not dropped then
            saved.misses[card.key] = misses + 1
            return false
        end
        saved.misses[card.key] = nil

        local counts = saved.counts
        counts[card.key] = (counts[card.key] or 0) + 1
        -- The shiny copy is a one-time bonus per card: once you own it, later finds are plain duplicates.
        saved.shiny = saved.shiny or {}
        local shiny = not saved.shiny[card.key] and random(1, ACB.shinyOdds) == 1
        if shiny then saved.shiny[card.key] = true end
        report(("%s: %s (x%d)"):format(shiny and "Shiny card found" or "Card found", card.name, counts[card.key]))
        checkAchievements(card)
        found(card, { count = counts[card.key], first = counts[card.key] == 1, shiny = shiny })
        return true
    end

    -- Hand over one spare copy of `give` in return for one copy of `take`. Returns false when the
    -- player no longer has a spare copy to give.
    function collection:swap(give, take)
        local counts = saved.counts
        local out, into = ACB.cards[give], ACB.cards[take]
        if not out or not into or (counts[give] or 0) < 2 then return false end
        counts[give] = counts[give] - 1
        counts[take] = (counts[take] or 0) + 1
        report(("Traded %s for %s (x%d)"):format(out.name, into.name, counts[take]))
        checkAchievements(into)
        found(into, { count = counts[take], first = counts[take] == 1, trade = true })
        return true
    end

    return collection
end
