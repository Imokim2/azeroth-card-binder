local _, ACB = ...

-- Artwork is shared content, not a roll made when a player opens the binder.
-- Keep this v1 pool and its order fixed. Add a card override to refine an existing
-- card, or a new versioned pool for future cards, rather than reshuffling v1.
local signatureV1 = {
    { id = "v1-guard", name = "The Sentinel", zoom = 0.56, facing = -0.48, animation = 25, frame = 12 },
    { id = "v1-strike", name = "The Challenge", zoom = 0.53, facing = 0.32, animation = 17, frame = 22 },
    { id = "v1-cast", name = "Arcane Moment", zoom = 0.57, facing = -0.28, animation = 32, frame = 20 },
    { id = "v1-living", name = "Living Portrait", zoom = 0.54, facing = 0.46, animation = 0, frame = 0, animated = true, duration = 4 },
}

local function seed(key)
    local value = 0
    for index = 1, #key do value = (value * 33 + key:byte(index)) % 65521 end
    return value
end

local function special(entry)
    return not entry.profession and (entry.rarity == "epic" or entry.rarity == "legendary")
end

-- Named alternates are presentation previews until collectible-edition rules are
-- defined. They do not grant cards, alter counts, or enter the collection ledger.
local alternates = {
    ["npc:639"] = {
        { id = "vancleef-defiant", name = "Defiant", zoom = 0.56, facing = 0.38, animation = 25, frame = 18 },
        { id = "vancleef-blades", name = "Blades Drawn", zoom = 0.52, facing = -0.66, animation = 17, frame = 24, animated = true, duration = 3.2 },
    },
    ["npc:573"] = {
        { id = "reaper-watch", name = "The Last Harvest", zoom = 0.31, facing = 0.42, animation = 16, frame = 14 },
        { id = "reaper-living", name = "Still Working", zoom = 0.28, facing = -0.34, animation = 0, frame = 0, animated = true, duration = 4 },
    },
}

function ACB.signaturePresentation(entry)
    if not special(entry) then return end
    return signatureV1[seed(entry.key) % #signatureV1 + 1]
end

-- The supplied base is the existing curated camera/pose when there is one.
function ACB.cardPresentations(entry, base)
    if entry.baseKey then
        return { { id = entry.presentationId, name = entry.editionTitle, pose = entry.presentation,
            animated = entry.presentation.animated == true, duration = entry.presentation.duration } }
    end
    local result = { { id = "signature", name = "Signature", pose = base, animated = base.animated == true, duration = base.duration } }
    if ACB.editions[entry.key] then
        for index = 2, #ACB.editions[entry.key] do
            local edition = ACB.editions[entry.key][index]
            result[#result + 1] = { id = edition.presentationId, name = edition.editionTitle, pose = edition.presentation,
                animated = edition.presentation.animated == true, duration = edition.presentation.duration }
        end
        return result
    end
    if not special(entry) then return result end
    for _, alternate in ipairs(alternates[entry.key] or {}) do
        result[#result + 1] = { id = alternate.id, name = alternate.name, pose = alternate, animated = alternate.animated == true, duration = alternate.duration }
    end
    return result
end

function ACB.cardPresentation(entry, id)
    local choices = ACB.cardPresentations(entry, ACB.portraitPreset(entry))
    for _, choice in ipairs(choices) do if choice.id == id then return choice end end
    return choices[1]
end

ACB.presentationSeed = seed
