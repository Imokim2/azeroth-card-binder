local _, ACB = ...

-- Inventory keys are immutable and use the existing signed card-key field.
-- Variants are outside page.cards so ordinary set completion never requires them.
ACB.editions, ACB.editionDenominator = {}, 1000
local content = {
    { 639, "Defiant", "Blades Drawn",
        { zoom = .24, facing = 1.15, animation = 120, frame = 420, y = -.08, z = -.12,
            fallbacks = { 115, 75 }, composition = "Wide side-on stealth crouch" },
        { zoom = .34, facing = -1.65, animation = 126, frame = 650, y = .07, z = -.08,
            fallbacks = { 87, 85 }, duration = 1.65, composition = "Opposite-side spinning blade attack" } },
    { 646, "First Mate", "Hammerfall",
        { zoom = .72, facing = 1.25, animation = 74, frame = 700, y = -.06, z = .06,
            fallbacks = { 55, 28 }, composition = "Tight roaring profile" },
        { zoom = .12, facing = -1.50, animation = 58, frame = 550, y = .08, z = -.16,
            fallbacks = { 19, 18 }, duration = 2.1, composition = "Wide full-body hammer strike" } },
    { 4275, "Moonlit", "Dark Invocation",
        { zoom = .84, facing = 1.35, animation = 31, frame = 900, y = -.07, z = .06,
            fallbacks = { 51, 52 }, composition = "Tight side-on spell preparation" },
        { zoom = .22, facing = -1.40, animation = 53, frame = 650, y = .06, z = -.10,
            fallbacks = { 33, 54 }, duration = 2.6, composition = "Wide directed spell cast" } },
    { 3887, "Restless", "Haunting",
        { zoom = .20, facing = -1.20, animation = 115, frame = 500, y = .06, z = -.14,
            fallbacks = { 75, 66 }, composition = "Wide kneeling ghost portrait" },
        { zoom = .78, facing = 1.65, animation = 74, frame = 750, y = -.06, z = .06,
            fallbacks = { 55, 64 }, duration = 2.4, composition = "Tight spectral roar" } },
    { 3976, "The Commander", "Scarlet Steel",
        { zoom = .83, facing = 1.25, animation = 113, frame = 700, y = -.06, z = .05,
            fallbacks = { 66, 55 }, composition = "Close commanding salute" },
        { zoom = .23, facing = -1.60, animation = 58, frame = 600, y = .07, z = -.10,
            fallbacks = { 19, 57 }, duration = 1.9, composition = "Wide sweeping weapon attack" } },
    { 3977, "Requiem", "Arise",
        { zoom = .22, facing = -1.30, animation = 115, frame = 500, y = .07, z = -.12,
            fallbacks = { 75, 51 }, composition = "Wide kneeling prayer" },
        { zoom = .82, facing = 1.55, animation = 54, frame = 850, y = -.07, z = .06,
            fallbacks = { 125, 53 }, duration = 3.1, composition = "Tight arms-raised resurrection cast" } },
    { 4832, "Twilight Vigil", "Dream Eater",
        { zoom = .82, facing = -1.25, animation = 124, frame = 1100, y = .07, z = .05,
            fallbacks = { 52, 31 }, composition = "Close channeling profile" },
        { zoom = .20, facing = 1.65, animation = 125, frame = 950, y = -.07, z = -.12,
            fallbacks = { 33, 54 }, duration = 2.75, composition = "Wide all-direction ritual channel" } },
    { 4829, "Ancient Depths", "Threefold Fury",
        { zoom = .12, facing = -1.35, animation = 74, frame = 850, y = .08, z = -.10,
            fallbacks = { 55, 130 }, composition = "Side-on three-headed roar" },
        { zoom = .02, facing = 1.65, animation = 130, frame = 650, y = -.08, z = -.18,
            fallbacks = { 118, 16 }, duration = 2.8, composition = "Opposite wide creature-special attack" } },
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
            entry.presentation = row[slot + 3]
            entry.presentation.animated = slot == 2
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
