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

function ACB.newCollection(saved, random, report, log)
    local collection = { saved = saved, rolled = {} }

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
        report("Card found: " .. card.name .. " (x" .. counts[card.key] .. ")")
        if card.page == 1 then
            for _, achievement in ipairs(ACB.achievements) do
                local owned, total = ACB.progress(counts, 1, achievement.bossesOnly)
                if owned == total and not saved.achievements[achievement.key] then
                    saved.achievements[achievement.key] = true
                    report("Binder achievement: " .. achievement.name)
                end
            end
        end
        return true
    end

    return collection
end
