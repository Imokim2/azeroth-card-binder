local _, ACB = ...

-- Authored catalog content: never reroll a profile when a player opens a card.
local function seed(key)
    local value = 0
    for i = 1, #key do value = (value * 33 + key:byte(i)) % 65521 end
    return value
end

-- Explicit IDs avoid turning hostile names such as Tunnel Rat into critters.
ACB.critterCards = {
    [721] = "Personal Space", [6271] = "Squeak Easy", [883] = "Oh Deer", [890] = "Baby Face",
    [4075] = "Whisker Business", [2110] = "Whisker Business", [1412] = "Nut Inspector",
    [5951] = "Hare's Looking at You", [2620] = "Prairie Stare", [10779] = "Nut Inspector",
    [10780] = "Oh Deer", [4166] = "Too Close", [12296] = "Too Close", [12298] = "Oh Deer",
    [3444] = "Whisker Business", [10016] = "Whisker Business", [13321] = "Ribbit Close",
    [1420] = "Ribbit Close", [3835] = "Ribbit Close", [3300] = "Hiss and Tell",
    [2914] = "Hiss and Tell", [4076] = "Bug Eyes", [10017] = "Bug Eyes", [15475] = "Bug Eyes",
    [9699] = "Bug Eyes", [9700] = "Claws for Concern", [16068] = "Too Close", [16030] = "Too Close",
    [14881] = "Eye Contact", [1933] = "Wool You Look at That", [2442] = "Moo-d Shot",
}

-- The second drop generation (ledger marker mode/chase2, docs/LEDGER-SPEC.md "Drop balance version 2"): critters are four times as
-- likely per attempt, other ordinary cards 20% more likely, and chase cards on limited sources (bosses, rares, gathering, epics) are unchanged.
-- Both generations stay in the catalog (dropProfile.rate and dropProfile.rate2), because a history is replayed at the rates it was rolled at.
function ACB.rateV2(profile, rate)
    if profile.tier == "critter" then return math.min(10000, rate * 4) end
    if profile.tier == "chase" and profile.style ~= "chase" then return rate end
    return math.min(10000, math.floor(rate * 12 / 10 + 0.5))
end

for _, card in pairs(ACB.cards) do
    local value = seed("distribution-v1|" .. card.key) % 1000
    local detail = seed("rate-v1|" .. card.key)
    local tier = value < 820 and "regular" or value < 970 and "uncommon" or "chase"
    local scale = tier == "regular" and (80 + detail % 46) or tier == "uncommon" and (35 + detail % 31) or (5 + detail % 8)
    local limited = card.boss or card.rarity == "epic" or card.rarity == "legendary"
        or card.profession or card.rank == "rare" or card.rank == "rareelite"
    if tier == "chase" and limited then scale = card.profession and (20 + detail % 21) or (40 + detail % 26) end
    local critter = not card.profession and ACB.critterCards[card.id] ~= nil
    card.critter = critter or nil
    card.dropScale = scale
    card.dropProfile = {
        rate = critter and (2 + detail % 4) or math.max(1, math.floor(ACB.rates[card.rank] * scale / 100)),
        style = (critter or (tier == "chase" and not limited)) and "chase" or "stack",
        packWeight = critter and 1 or tier == "chase" and 4 or tier == "uncommon" and 35 or 100,
        tier = critter and "critter" or tier, noCraft = critter or tier == "chase",
    }
    card.dropProfile.rate2 = ACB.rateV2(card.dropProfile, card.dropProfile.rate)
end

-- `balanced` is the drop generation: false (the original rank rates), true or 1 (mode/chase1), or 2 (mode/chase2, the current rates).
function ACB.dropRate(card, balanced, observedRank)
    if balanced and card.dropProfile then
        local second = balanced == 2
        if observedRank and ACB.rates[observedRank] and not card.critter then
            local rate = math.max(1, math.floor(ACB.rates[observedRank] * card.dropScale / 100))
            return second and ACB.rateV2(card.dropProfile, rate) or rate
        end
        return second and card.dropProfile.rate2 or card.dropProfile.rate
    end
    return ACB.rates[observedRank] or ACB.rates[card.rank]
end

function ACB.dropChance(card, misses, balanced, observedRank)
    local rate = ACB.dropRate(card, balanced, observedRank)
    if not balanced or not card.dropProfile or card.dropProfile.style ~= "chase" then
        return math.min(10000, rate + rate * (ACB.stackFactor or 0) * misses)
    end
    local limit = math.ceil(10000 / rate)
    local start = math.floor(limit * .75)
    if misses >= limit - 1 then return 10000 end
    if misses <= start then return rate end
    return rate + math.floor((10000 - rate) * (misses - start) / (limit - 1 - start))
end

-- Write the drop-generation markers once each, before the first roll that uses them: chase1 (per-card profiles), then chase2 (the
-- second set of rates). A run of misses is written down first so it stays at the rates it was rolled at; miss counts carry over.
function ACB.activateDropBalance(saved, ledger)
    if not saved.balancedDrops then return end
    if not saved.balanceLedger then
        if ledger then ledger:flushRun(); ledger:record("mode", "chase1") end
        saved.balanceLedger = true
    end
    if saved.balancedDrops == 2 and not saved.balanceLedger2 then
        if ledger then ledger:flushRun(); ledger:record("mode", "chase2") end
        saved.balanceLedger2 = true
    end
    -- The launch collection: from here on a card held back for seasons is not acquired until a season has released it (Availability.lua).
    if saved.balancedDrops == 2 and saved.balanceLedger2 and not saved.launchLedger then
        if ledger then ledger:flushRun(); ledger:record("mode", "launch1") end
        saved.launchLedger = true
    end
end

function ACB.discoveryText(card)
    local tier = card.dropProfile and card.dropProfile.tier
    if tier == "critter" then return "A tiny encounter. An extraordinary find." end
    if tier == "chase" then return "An elusive find for a patient collector." end
    if tier == "uncommon" then return "Some encounters take a little longer to remember." end
    return "Every encounter could hold your next discovery."
end
