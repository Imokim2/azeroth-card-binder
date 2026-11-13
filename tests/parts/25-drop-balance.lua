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

test("the second drop generation: critters four times as likely, ordinary cards 20% more, limited chase cards unchanged", function()
    for _, item in ipairs(vectors.balance.chances) do
        local card = ACB.cards[item.key]
        equal(ACB.dropChance(card, item.misses, 2), item.balanced2)
        equal(ACB.dropChance(card, item.misses, true), item.balanced)
        equal(ACB.dropChance(card, item.misses, false), item.legacy)
    end
    local seen = { critter = 0, regular = 0, limited = 0, chase = 0 }
    for _, card in pairs(ACB.cards) do
        local p = not card.baseKey and card.dropProfile
        if p then
            if p.tier == "critter" then
                seen.critter = seen.critter + 1
                equal(p.rate2, p.rate * 4)
            elseif p.tier == "chase" and p.style ~= "chase" then
                seen.limited = seen.limited + 1
                equal(p.rate2, p.rate)
            else
                equal(p.rate2, math.floor(p.rate * 12 / 10 + 0.5))
                if p.tier == "chase" then seen.chase = seen.chase + 1 else seen.regular = seen.regular + 1 end
            end
            equal(ACB.dropRate(card, true), p.rate) -- the first generation is untouched
            equal(ACB.dropRate(card, 2), p.rate2)
        end
    end
    equal(seen.critter, 31)
    assert(seen.limited > 0 and seen.chase > 0 and seen.regular > 0)
    -- Casual's observed-rank rates follow the generation too, and a critter ignores the observed rank.
    local card = ACB.cards["npc:589"]
    equal(ACB.dropRate(card, 2, "elite"), ACB.rateV2(card.dropProfile, ACB.dropRate(card, true, "elite")))
    equal(ACB.dropRate(ACB.cards["npc:721"], 2, "rareelite"), ACB.cards["npc:721"].dropProfile.rate2)
    equal(ACB.cleanSavedData({}).balancedDrops, 2, "a binder is on the second generation from the moment this add-on loads it")
end)

test("chase2 is written once, right after chase1, with any run of misses flushed first at the old rates", function()
    local saved, ledger, collection = rankedBinder({ MISS, DROP_PLAIN })
    collection:roll(guid(589, "before-policy"), "loot")
    equal(saved.run.n, 1)
    saved.balancedDrops = 2
    collection:roll(guid(589, "after-policy"), "loot")
    ledger:flushRun()
    local at = {}
    for index, event in ipairs(saved.ledger) do
        if event.key == "chase1" or event.key == "chase2" then at[event.key] = (at[event.key] and -1) or index end
    end
    assert(at.chase1 and at.chase2 and at.chase1 > 1, "both markers, each once")
    equal(at.chase2, at.chase1 + 1)
    equal(saved.ledger[at.chase1 - 1].kind, "miss") -- the old run was written before the new rates began
    local before = #saved.ledger
    ACB.activateDropBalance(saved, ledger)
    equal(#saved.ledger, before, "nothing more is written")
    assert(ledger:verify())
end)

test("a binder that already wrote chase1 gets only chase2, and carried miss counts are kept", function()
    local saved, ledger, collection = rankedBinder({ DROP_PLAIN })
    saved.balanceLedger = true -- chase1 was written by an earlier version of the add-on
    saved.balancedDrops = 2
    saved.misses = { ["npc:721"] = 50 }
    collection:roll(guid(589, "first-after-upgrade"), "loot")
    ledger:flushRun()
    local chase1, chase2 = 0, 0
    for _, event in ipairs(saved.ledger) do
        if event.key == "chase1" then chase1 = chase1 + 1 end
        if event.key == "chase2" then chase2 = chase2 + 1 end
    end
    equal(chase1, 0)
    equal(chase2, 1)
    equal(saved.misses["npc:721"], 50)
    assert(ledger:verify())
end)
