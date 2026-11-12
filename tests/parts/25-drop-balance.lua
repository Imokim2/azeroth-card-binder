test("all balanced chance and weighted-pack vectors agree with the shared server contract", function()
    for _, item in ipairs(vectors.balance.chances) do
        local card = ACB.cards[item.key]
        equal(ACB.dropChance(card, item.misses, true), item.balanced)
        equal(ACB.dropChance(card, item.misses, false), item.legacy)
    end
    for _, item in ipairs(vectors.balance.packs) do equal(ACB.packPick(item.zone, item.entry, true), item.key) end
end)

test("critter portraits are separate rare collectibles and cannot be crafted or boosted by an observed rank", function()
    local critters = 0
    for _, card in pairs(ACB.cards) do if card.critter and not card.baseKey then
        critters = critters + 1
        local profile, family = card.dropProfile, ACB.editions[card.key]
        assert(profile.rate >= 2 and profile.rate <= 5)
        equal(profile.style, "chase")
        equal(ACB.dropChance(card, 10, true), profile.rate)
        equal(ACB.dropChance(card, math.ceil(10000 / profile.rate) - 1, true), 10000)
        equal(ACB.dropRate(card, true, "rareelite"), profile.rate)
        equal(#family, 2)
        assert(family[2].presentation.zoom >= .92 and not family[2].presentation.animated)
        equal(ACB.pickEdition(card, 250, true), family[2])
        equal(ACB.pickEdition(card, 251, true), card)
        equal(ACB.pickEdition(card, 1, false), card)
    end end
    equal(critters, 31)
    local saved = ACB.cleanSavedData({ dust = 100000 })
    local collection = ACB.newCollection(saved, math.random, ignore, ignore)
    equal(collection:craft("npc:721"), false)
    equal(saved.dust, 100000)
    equal(saved.counts["npc:721"], nil)
end)

test("balance activation preserves pity, flushes legacy misses first and is written just once", function()
    local saved, ledger, collection = rankedBinder({ MISS, DROP_PLAIN })
    collection:roll(guid(589, "before-policy"), "loot")
    equal(saved.run.n, 1)
    saved.balancedDrops = true
    collection:roll(guid(589, "after-policy"), "loot")
    ledger:flushRun()
    equal(saved.ledger[2].kind, "miss")
    equal(saved.ledger[3].key, "chase1")
    local markers = 0
    for _, event in ipairs(saved.ledger) do if event.key == "chase1" then markers = markers + 1 end end
    ACB.activateDropBalance(saved, ledger)
    equal(#saved.ledger, 4)
    equal(markers, 1)
    equal(saved.counts["npc:589"], 1)
    assert(ledger:verify())
    local carried = ACB.cleanSavedData({ misses = { ["npc:721"] = 50 } })
    ACB.activateDropBalance(carried)
    equal(carried.misses["npc:721"], 50)
end)
