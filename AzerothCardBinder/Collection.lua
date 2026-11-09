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

-- `found` is called with the card and what happened whenever a card is added to the binder.
function ACB.newCollection(saved, random, report, log, found)
    found = found or function() end
    local collection = { saved = saved, rolled = {} }

    local function checkAchievements(card)
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
        local dropped = random(1, 10000) <= threshold
        log(("%s: %s at %g%% (%s)"):format(origin, card.name, threshold / 100, dropped and "card" or "miss"))
        if not dropped then return false end

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
