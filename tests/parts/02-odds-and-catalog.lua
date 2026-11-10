for _, rate in ipairs({
    { id = 589, limit = 100, rank = "normal" },
    { id = 639, limit = 200, rank = "elite" },
    { id = 573, limit = 1000, rank = "rare" },
    { id = 3586, limit = 1000, rank = "rareelite" },
    { id = 1731, limit = 100, rank = "gathering", kind = "GameObject" },
}) do
    test(rate.rank .. " exact odds and no reroll after miss", function()
        local saved = { counts = {}, achievements = {} }
        local rolls, draws = 0, { rate.limit, rate.limit + 1 }
        local collection = ACB.newCollection(saved, function(min, max)
            equal(min, 1)
            if max == ACB.shinyOdds then return 2 end -- not shiny
            equal(max, 10000)
            rolls = rolls + 1
            return draws[rolls]
        end, ignore, ignore)
        local first, second = guid(rate.id, "A", rate.kind), guid(rate.id, "B", rate.kind)
        local origin = rate.kind and "gather" or "loot"
        equal(collection:roll(first, origin), true)
        equal(collection:roll(first, origin), nil)
        equal(collection:roll(second, origin), false)
        equal(collection:roll(second, origin), nil)
        equal(rolls, 2)
        equal(saved.counts[ACB.source(first).key], 1)
    end)
end

test("distinct NPC and object identities; only catalog sources roll", function()
    equal(ACB.source(guid(589, "A")).key, "npc:589")
    equal(ACB.source(guid(589, "B")).key, "npc:589")
    equal(ACB.source(guid(1731, "A", "GameObject")).key, "node:1731")
    equal(ACB.source(guid(589, "B", "Pet")), nil)
    equal(ACB.source(guid(589, "B", "GameObject")), nil)
    equal(ACB.source(guid(1, "A")), nil)
    equal(ACB.source("Creature-589"), nil)
end)

test("duplicates do not fill slots; both Deadmines achievements unlock once", function()
    local saved = { counts = {}, achievements = {} }
    local earned = 0
    local collection = ACB.newCollection(saved, function() return 1 end, function(message)
        if message:match("^Binder achievement") then earned = earned + 1 end
    end, ignore)
    for _, card in ipairs(ACB.pages[1].cards) do
        if card.boss then collection:roll(guid(tonumber(card.key:sub(5)), "A"), "loot") end
    end
    collection:roll(guid(639, "B"), "loot")
    local bosses = 0
    for _, card in ipairs(ACB.pages[1].cards) do
        if card.boss then bosses = bosses + 1 end
    end
    assert(bosses >= 8, "the eight hand-made Deadmines bosses are all bosses")
    local owned, total = ACB.progress(saved.counts, 1)
    equal(owned, bosses)
    equal(total, #ACB.pages[1].cards)
    equal(saved.counts["npc:639"], 2)
    equal(saved.achievements.crew, true)
    equal(saved.achievements.deadmines, nil)
    for _, card in ipairs(ACB.pages[1].cards) do
        if not card.boss then collection:roll(guid(tonumber(card.key:sub(5)), "A"), "loot") end
    end
    collection:roll(guid(639, "C"), "loot")
    equal(saved.achievements.deadmines, true)
    equal(earned, 2)
end)

test("every card has lore that fits, is stable and says something about the card", function()
    local seen, count = {}, 0
    for _, page in ipairs(ACB.pages) do
        for _, card in ipairs(page.cards) do
            count = count + 1
            assert(type(card.lore) == "string" and #card.lore >= 12, "lore for " .. card.name)
            assert(#card.lore <= 80, ("lore too long for %s (%d): %s"):format(card.name, #card.lore, card.lore))
            assert(not card.lore:find("%%s") and not card.lore:find("nil"), "unfilled lore for " .. card.name .. ": " .. card.lore)
            seen[card.lore] = true
            if card.generated and not card.profession then equal(ACB.loreFor(card), card.lore) end
        end
    end
    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    assert(distinct > 1200, "lore should not be one line repeated, only " .. distinct .. " of " .. count .. " lines are different")
    -- Bosses, named groups, kinds of creature and nodes each get fitting lines.
    assert(ACB.cards["npc:15990"].lore:find("lich", 1, true)) -- Kel'Thuzad
    assert(ACB.cards["npc:639"].lore:find("Founder of the Defias", 1, true)) -- hand-made lore is kept
    local scarlet
    for _, card in ipairs(ACB.pages[ACB.pageForPlace["scarlet-monastery"] or 2].cards) do
        if card.name:find("Scarlet", 1, true) then scarlet = card break end
    end
    assert(scarlet and scarlet.lore:find("Scarlet Crusade", 1, true), "Scarlet creatures mention the Crusade")
    assert(ACB.cards["node:1617"].lore:find("silvery", 1, true)) -- Silverleaf
    assert(ACB.cards["node:1731"].lore:find("Reddish ore", 1, true)) -- the hand-made node keeps its line
end)

test("every gathering node is a card and all of its object ids find it", function()
    local nodes = 0
    for _, card in ipairs(ACB.pages[3].cards) do
        nodes = nodes + 1
        assert(card.profession == "mining" or card.profession == "herbalism", card.name)
        assert(card.skill and card.skill >= 1, card.name)
        for _, id in ipairs(card.ids) do equal(ACB.sources.GameObject[id], card) end
    end
    assert(nodes >= 39, "all 39 Forever node types, has " .. nodes)
    -- Several object ids, one card.
    equal(ACB.source(guid(3763, "a", "GameObject")).key, "node:1731")
    equal(ACB.source(guid(3724, "a", "GameObject")).key, "node:1618")
    equal(ACB.source(guid(175404, "a", "GameObject")).name, "Rich Thorium Vein")
    -- Creatures and objects have separate id spaces, so a creature never turns into a node card.
    local creature = ACB.source(guid(1731, "a", "Creature"))
    assert(creature == nil or not creature.profession)
    -- The original hand-made nodes keep their lore and model.
    equal(ACB.cards["node:1731"].model, 219514)
    assert(ACB.cards["node:1731"].lore:find("Reddish ore", 1, true))
    assert(ACB.cards["node:175404"].lore:find("thorium", 1, true))
    equal(ACB.cards["node:175404"].rarity, "rare")
end)

test("the generated catalog is large, consistent and fits the card", function()
    local count, codes, ids = 0, {}, {}
    for _, page in ipairs(ACB.pages) do
        assert(page.title and page.code and page.group, "every set has a title, code and group")
        assert(not codes[page.code], "duplicate set code " .. page.code)
        codes[page.code] = true
        assert(ACB.zones[page.zone], "every set has zone art settings: " .. page.title)
        for _, card in ipairs(page.cards) do
            count = count + 1
            assert(card.name ~= "" and #card.name <= 44, "card name fits: " .. card.name)
            assert(card.id and not ids[card.key], "unique card " .. card.key)
            ids[card.key] = true
            assert(ACB.sources[card.profession and "GameObject" or "Creature"][card.id] == card, "source index for " .. card.key)
        end
    end
    assert(count > 3000, "the catalog should hold thousands of cards, has " .. count)
    -- Only neutral and hostile creatures: nothing that is friendly to one faction, so no guards or faction leaders.
    equal(ACB.cards["npc:1423"], nil) -- Stormwind Guard
    equal(ACB.cards["npc:10162"], nil) -- Lord Victor Nefarius, friendly to both
    assert(ACB.cards["npc:639"], "hostile creatures stay")
    assert(#ACB.pages > 60, "sets for every dungeon, raid and zone with data")
    -- Hand-made cards keep their lore; new cards get a short generated line.
    assert(ACB.cards["npc:639"].lore:find("Founder of the Defias", 1, true))
    assert(ACB.cards["npc:157"].lore:find("The Barrens") == nil and #ACB.cards["npc:157"].lore > 0)
    equal(ACB.pageForPlace.deadmines, 1)
    equal(ACB.pageForPlace.westfall, 2)
end)

test("gathering nodes carry a model file", function()
    equal(ACB.cards["node:1731"].model, 219514)
    equal(ACB.cards["node:1618"].model, 219481)
    -- Most nodes have a mesh; the rest fall back to their icon, which every node card has.
    local withModel, total = 0, 0
    for _, card in pairs(ACB.cards) do
        if card.profession then
            total = total + 1
            assert(type(card.icon) == "string" and card.icon ~= "", card.name .. " needs an icon")
            if card.model then
                equal(type(card.model), "number")
                withModel = withModel + 1
            end
        end
    end
    assert(withModel >= 30 and withModel < total or withModel == total, "models for most of the " .. total .. " nodes")
end)

test("rarity follows boss, elite, normal and profession rules", function()
    local expected = {
        ["npc:644"] = "legendary", ["npc:3586"] = "legendary", ["npc:639"] = "legendary",
        ["npc:657"] = "epic", ["npc:573"] = "epic", ["npc:589"] = "common",
        ["npc:114"] = "common", ["node:1731"] = "rare", ["node:1618"] = "rare",
    }
    for key, rarity in pairs(expected) do equal(ACB.cards[key].rarity, rarity) end
    for key, card in pairs(ACB.cards) do
        assert(ACB.rarities[card.rarity], key .. " has no rarity")
        assert(ACB.zones[card.zone], key .. " has no zone")
        assert(#card.lore > 0 and #card.lore <= 80, key .. " lore length " .. #card.lore)
    end
end)
