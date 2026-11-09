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

-- The cards a player is looking for: the missing cards they marked as wanted.
function ACB.wantedCards(saved)
    local marked = {}
    for key in pairs(saved.wanted or {}) do
        if ACB.cards[key] and (saved.counts[key] or 0) == 0 then marked[#marked + 1] = key end
    end
    table.sort(marked)
    return marked
end

-- Attempts without a drop so far, and the attempt that is guaranteed, for a catalog card.
function ACB.luck(saved, card)
    local rate = ACB.rates[card.rank]
    local limit = (ACB.pityFactor or 0) > 0 and math.ceil(ACB.pityFactor * 10000 / rate) or nil
    return (saved.misses and saved.misses[card.key]) or 0, limit
end

-- What a spare copy of the card recycles into, and what the card costs to craft, in Binder Dust.
function ACB.dustFor(card)
    return ACB.dust.recycle[card.rarity] or 0, ACB.dust.craft[card.rarity] or 0
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

    -- Turn one spare copy into Binder Dust. The last copy of a card can never be recycled.
    function collection:recycle(key)
        local card = ACB.cards[key]
        local count = saved.counts[key] or 0
        if not card or count < 2 then return false end
        local yield = ACB.dustFor(card)
        saved.counts[key] = count - 1
        saved.dust = (saved.dust or 0) + yield
        report(("Recycled a spare %s: +%d Binder Dust (%d in all)"):format(card.name, yield, saved.dust))
        return true
    end

    -- Spend dust on a card that is not in the binder yet. It is a plain copy, never shiny.
    function collection:craft(key)
        local card = ACB.cards[key]
        if not card or (saved.counts[key] or 0) > 0 then return false end
        local _, cost = ACB.dustFor(card)
        if (saved.dust or 0) < cost then return false end
        saved.dust = saved.dust - cost
        saved.counts[key] = 1
        if saved.misses then saved.misses[key] = nil end
        report(("Crafted %s for %d Binder Dust (%d left)"):format(card.name, cost, saved.dust))
        checkAchievements(card)
        found(card, { count = 1, first = true, crafted = true })
        return true
    end

    return collection
end
