test("rarity silhouettes sit on the description divider and leave the name plate clear", function()
    local cases = { { "npc:589", "Circle" }, { "node:1731", "Square" }, { "npc:573", "Diamond" },
        { "npc:639", "Hexagon" }, { "edition:48322", "Star" } }
    for _, case in ipairs(cases) do
        local card = ACB.createCard(UIParent, true)
        card:set(ACB.cards[case[1]], 1)
        equal(card.rarityShape, case[2])
        equal(card.gem.point[4], 68)
        equal(card.gem.point[5], -140)
        equal(card.gemBezel.point[5], -140)
        assert(card.gem.texture:find(case[2] .. ".tga", 1, true))
        equal(card.ornament, nil)
    end
end)

test("eight dungeon bosses have two collectible editions outside ordinary set slots", function()
    local families, variants = 0, 0
    for _, family in pairs(ACB.editions) do
        families = families + 1
        equal(#family, 3)
        for index = 2, 3 do
            local card = family[index]
            variants = variants + 1
            equal(ACB.baseCard(card), family[1])
            equal(card.id, family[1].id)
            equal(card.presentation.animated, index == 3)
            for _, slot in ipairs(ACB.pages[card.page].cards) do assert(slot.key ~= card.key) end
        end
    end
    equal(families, 8)
    equal(variants, 16)
    equal(ACB.cards["edition:48322"].editionTitle, "Dream Eater")
    equal(ACB.cards["edition:48292"].editionTitle, "Threefold Fury")
end)

test("collectible editions record exact inventory, trade it and recycle only that edition's spare", function()
    local saved = ACB.cleanSavedData({})
    local ledger = newLedger(saved)
    ledger:begin(true)
    local artRoll = 100
    local collection = ACB.newCollection(saved, function(_, high)
        if high == ACB.editionDenominator then return artRoll end
        return high == ACB.shinyOdds and 2 or 1
    end, ignore, ignore, nil, nil, ledger)
    local function find(token) assert(collection:roll(guid(4832, token), "loot")) end
    find("still-1")
    artRoll = 175; find("animated-1")
    artRoll = 500; find("signature-1")
    equal(saved.counts["edition:48321"], 1)
    equal(saved.counts["edition:48322"], 1)
    equal(saved.counts["npc:4832"], 1)
    equal(ACB.familyCount(saved.counts, ACB.cards["npc:4832"]), 3)
    equal(ACB.familySpares(saved.counts, ACB.cards["npc:4832"]), 0)
    equal(saved.ledger[1].key, "editions1")
    equal(saved.ledger[2].key, "edition:48321")
    equal(collection:roll(guid(4832, "still-1"), "loot"), nil)
    equal(collection:recycle("edition:48321"), false)
    equal(collection:craft("edition:48292"), false)
    artRoll = 100; find("still-2")
    assert(collection:recycle("edition:48321"))
    equal(saved.counts["edition:48321"], 1)
    assert(collection:swap("edition:48321", "edition:48292", "bob-realm", "edition-test"))
    equal(saved.counts["edition:48321"], nil)
    equal(saved.counts["edition:48322"], 1)
    equal(saved.counts["edition:48292"], 1)
    equal(saved.counts["npc:4832"], 1)
    assert(ledger:verify())
    equal(ACB.shortKey(ACB.cards["edition:48292"]), "v48292")
    equal(ACB.longKey("v48292"), "edition:48292")
    equal(ACB.parseCardLink(ACB.cardLink(ACB.cards["edition:48292"], false):match("|H(.-)|h")).key, "edition:48292")
end)

test("edition buttons preview locked cards and exact links reopen the selected edition", function()
    local saved = { counts = { ["edition:48322"] = 2 } }
    local picked
    local strip = ACB.createEditionStrip(UIParent, saved, function(key) picked = key end)
    local selected = strip:select(ACB.cards["npc:4832"])
    equal(selected.key, "edition:48322")
    equal(strip.controls[1].count.text, "Locked")
    equal(strip.controls[3].count.text, "x2 *")
    strip.controls[1]:OnClick()
    equal(picked, "npc:4832")
    equal(saved.counts["npc:4832"], nil)
    assert(ACB.openCard("edition:48322"))
    equal(ACB.findAnyCard("Dream Eater").key, "edition:48322")
    strip:Hide()
end)
