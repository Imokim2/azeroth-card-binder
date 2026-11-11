local _, ACB = ...

-- Inventory keys are immutable and use the existing signed card-key field.
-- Variants are outside page.cards so ordinary set completion never requires them.
ACB.editions, ACB.editionDenominator = {}, 1000
local content = {
    { 639, "Defiant", "Blades Drawn", .56, .38, 25, .52, -.66, 17 },
    { 646, "First Mate", "Hammerfall", .34, .36, 27, .30, -.55, 17 },
    { 4275, "Moonlit", "Dark Invocation", .55, .42, 25, .52, -.35, 32 },
    { 3887, "Restless", "Haunting", .52, -.40, 25, .49, .38, 0 },
    { 3976, "The Commander", "Scarlet Steel", .56, .36, 27, .52, -.50, 17 },
    { 3977, "Requiem", "Arise", .56, -.32, 25, .53, .38, 32 },
    { 4832, "Twilight Vigil", "Dream Eater", .55, -.38, 25, .51, .40, 32 },
    { 4829, "Ancient Depths", "Threefold Fury", .20, -.45, 0, .18, .35, 16 },
}
for _, row in ipairs(content) do
    local base = ACB.cards["npc:" .. row[1]]
    if base then
        local family = { base }
        for slot = 1, 2 do
            local entry = {}
            for key, value in pairs(base) do entry[key] = value end
            entry.baseKey, entry.editionTitle = base.key, row[slot + 1]
            entry.key = "edition:" .. (row[1] * 10 + slot)
            entry.presentationId = "boss-" .. row[1] .. "-" .. slot
            if row[1] == 639 then entry.presentationId = slot == 1 and "vancleef-defiant" or "vancleef-blades" end
            entry.name = base.name .. " (" .. entry.editionTitle .. ")"
            entry.serial = base.serial .. "/A" .. slot
            entry.editionWeight = slot == 1 and 150 or 50 -- 15% still, 5% animated, 80% Signature
            local offset = slot == 1 and 4 or 7
            entry.presentation = { zoom = row[offset], facing = row[offset + 1], animation = row[offset + 2], frame = 18,
                animated = slot == 2, duration = slot == 2 and 3.5 or nil }
            ACB.cards[entry.key] = entry
            family[#family + 1] = entry
        end
        ACB.editions[base.key] = family
    end
end

function ACB.baseCard(entry)
    return entry.baseKey and ACB.cards[entry.baseKey] or entry
end

function ACB.cardEditions(entry)
    local base = ACB.baseCard(entry)
    return ACB.editions[base.key] or { base }
end

function ACB.familyCount(counts, entry)
    local total = 0
    for _, edition in ipairs(ACB.cardEditions(entry)) do total = total + (counts[edition.key] or 0) end
    return total
end

function ACB.familySpares(counts, entry)
    local total = 0
    for _, edition in ipairs(ACB.cardEditions(entry)) do total = total + math.max(0, (counts[edition.key] or 0) - 1) end
    return total
end

function ACB.firstOwnedEdition(counts, entry)
    for _, edition in ipairs(ACB.cardEditions(entry)) do if (counts[edition.key] or 0) > 0 then return edition end end
    return ACB.baseCard(entry)
end

local inventory
function ACB.inventoryPages()
    if not inventory then
        local cards = {}
        for _, page in ipairs(ACB.pages) do
            for _, base in ipairs(page.cards) do
                for _, edition in ipairs(ACB.cardEditions(base)) do cards[#cards + 1] = edition end
            end
        end
        inventory = { { cards = cards } }
    end
    return inventory
end

-- A domain-separated digest keeps this draw independent of the existing drop,
-- shiny and pack calculations while using the exact same issued tape entry.
function ACB.editionRoll(entry)
    return tonumber(ACB.sha256("edition-v1|" .. entry):sub(1, 8), 16) % ACB.editionDenominator + 1
end

function ACB.pickEdition(card, roll)
    local base, upTo = ACB.baseCard(card), 0
    local family = ACB.editions[base.key]
    if not family then return base end
    for index = 2, #family do
        local edition = family[index]
        upTo = upTo + edition.editionWeight
        if roll <= upTo then return edition end
    end
    return base
end

function ACB.activateEditions(saved, ledger)
    if not saved.editionDrops or saved.editionLedger then return end
    if ledger then ledger:flushRun(); ledger:record("mode", "editions1") end
    saved.editionLedger = true
end
