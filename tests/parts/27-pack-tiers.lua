test("pack tiers match shared boundary vectors and keep the Pack: Zone naming", function()
    for _, item in ipairs(vectors.satchel.tiers) do
        equal(ACB.packTier(item.entry), item.tier)
        equal(ACB.packValue(item.entry) == 1, item.found)
    end
    for tier, size in pairs({ common = 1, rare = 3, epic = 5 }) do
        local id = ACB.packID("WF", tier)
        local info, item = ACB.packInfo(id), ACB.packItem("pack:" .. id)
        equal(info.size, size)
        equal(item.name, "Pack: Westfall")
        equal(item.tier, tier)
        local saved = ACB.cleanSavedData({ packs = { [id] = 2 } })
        equal(saved.packs[id], 2)
    end
    equal(ACB.packItem("pack:WF:legendary"), nil)
    equal(ACB.packItem("pack:WF:epic"), nil, "epic packs keep the original inventory identity")
    equal(ACB.packItem("pack:NOZONE:rare"), nil)
end)

test("one and three card packs centre their real faces, preload them and leave unused slots hidden", function()
    local original = ACB.collection
    for tier, size in pairs({ common = 1, rare = 3, epic = 5 }) do
        local id = ACB.packID("WF", tier)
        local saved = ACB.cleanSavedData({ packs = { [id] = 1 } })
        local ledger = newLedger(saved); ledger:begin(true)
        ACB.collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, nil, nil, ledger)
        local view = ACB.createPackView(saved)
        view:openZone(id)
        equal(#view.results, size)
        equal(saved.packs[id], nil)
        for index, slot in ipairs(view.slots) do
            equal(slot.holder:IsShown(), index <= size)
            if index <= size then
                equal(slot.holder.alpha, 1)
                equal(slot.cover:IsShown(), true)
                equal(slot.card.concealed, true)
            end
        end
        run(view, 3)
        equal(view.phase, "reveal")
        if size < 5 then equal(view:flip(size + 1), false) end
        view:flipAll(); run(view, 3)
        equal(view:flipped(), size)
        for index = size + 1, 5 do equal(view.slots[index].back:IsShown(), false) end
        view:finish()
        assert(ledger:verify())
        view.frame:Hide()
    end
    ACB.collection = original
end)

test("a new Ranked pack tier is decided by its find entry and writes its marker before the pack", function()
    local saved, ledger, collection = rankedBinder({ entryOf(10000, 70 * ACB.shinyOdds * ACB.packOdds) })
    saved.tieredPacks = true
    collection.packsEnabled = true
    equal(collection:roll(guid(589, "rare-pack-find"), "loot"), false)
    equal(saved.packs[ZONE .. ":rare"], 1)
    local found = saved.ledger[#saved.ledger]
    equal(found.kind, "packFind")
    equal(saved.ledger[#saved.ledger - 1].key, "packs2")
    equal(found.key, ZONE .. ":rare")
    equal(found.tape, 1)
    equal(ledger:verify(), true)
end)
