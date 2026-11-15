test("Casual finds explain Ranked ineligibility before companion setup without changing the collection", function()
    withCasualModeUI(function(saved, ledger, messages)
        local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, nil, nil, ledger)
        assert(collection:roll(guid(589, "casual-before-ranked-setup"), "loot"))
        local head, waiting = saved.head.hash, #saved.ledger
        ACB.requestCollectionMode("ranked")
        assert(messages[#messages]:find("contains Casual cards", 1, true))
        assert(not messages[#messages]:find("Download the companion", 1, true))
        equal(saved.mode, "casual"); equal(saved.counts["npc:589"], 1)
        equal(saved.head.hash, head); equal(#saved.ledger, waiting)
        ACB.sync = { companionReady = true, seasonal = { binders = { saved.modeSetupID } } }
        local ok, why = ACB.setMode(saved, ledger, "ranked")
        equal(ok, false); assert(why:find("contains Casual cards", 1, true))
    end)
end)

test("companion 1.0.1 keeps an established binder paired through its matching synced nonce", function()
    withCasualModeUI(function(saved, ledger)
        saved.mode, saved.counts["npc:639"] = "ranked", 1
        ACB.sync = { companionReady = true, rankedSetups = {}, seasonal = { binders = { saved.modeSetupID } } }
        equal(ACB.companionPaired(saved), true)
        ACB.sync.seasonal.binders = { string.rep("f", 32) }
        equal(ACB.companionPaired(saved), false)
        ACB.sync.seasonal.binders = { saved.modeSetupID }
        ACB.sync.companionReady = false
        equal(ACB.companionPaired(saved), false)
        equal(saved.mode, "ranked"); equal(saved.counts["npc:639"], 1)
    end)
end)

test("a synced empty Casual binder may explicitly choose Ranked without silently changing its mode", function()
    withCasualModeUI(function(saved, ledger)
        saved.modeChoice = "casual"
        ACB.sync = { companionReady = true, rankedSetups = {}, seasonal = { binders = { saved.modeSetupID } } }
        equal(ACB.defaultCollectionMode(saved, ledger), false)
        equal(saved.mode, "casual")
        equal(ACB.setMode(saved, ledger, "ranked"), true)
        equal(saved.mode, "ranked"); equal(saved.casualDrops, 0)
        ACB.sync = { companionReady = true, tape = { start = 1, entries = { MISS } } }
        equal(ACB.companionPaired(saved), false)
    end)
end)
