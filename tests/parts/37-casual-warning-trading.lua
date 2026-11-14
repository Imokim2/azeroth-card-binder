local function withCasualModeUI(run)
    local previousDB, previousSync = AzerothCardBinderDB, ACB.sync
    local keys = { "ensureCollectionMode", "chooseCollectionMode", "requestCollectionMode", "modeChoicePrompt",
        "warnCasualFind", "explainRankedTrading", "casualWarningPrompt" }
    local old = {}; for _, key in ipairs(keys) do old[key] = ACB[key] end
    local saved = ACB.cleanSavedData({ modeChoice = "casual" })
    local ledger = newLedger(saved); ledger:begin(false)
    AzerothCardBinderDB, ACB.sync = saved, {}
    local messages = {}
    ACB.initCollectionMode(saved, ledger, function(message) messages[#messages + 1] = message end)
    local ok, why = pcall(run, saved, ledger, messages)
    AzerothCardBinderDB, ACB.sync = previousDB, previousSync
    for _, key in ipairs(keys) do ACB[key] = old[key] end
    assert(ok, why)
end

test("the first committed Casual find warns once per binder even with card popups disabled", function()
    withCasualModeUI(function(saved, ledger, messages)
        saved.popups = false
        local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, nil, nil, ledger)
        equal(ACB.casualWarningPrompt:IsShown(), false)
        assert(collection:roll(guid(589, "casual-warning-first"), "loot"))
        equal(saved.casualWarningSeen, true)
        equal(ACB.casualWarningPrompt:IsShown(), true)
        equal(saved.counts["npc:589"], 1)
        assert(messages[#messages]:find("Trading and gifting are disabled", 1, true))
        ACB.casualWarningPrompt:Hide()
        assert(collection:roll(guid(589, "casual-warning-second"), "loot"))
        equal(ACB.casualWarningPrompt:IsShown(), false)
        ACB.cleanSavedData(saved)
        ACB.initCollectionMode(saved, ledger, ignore)
        assert(collection:roll(guid(589, "casual-warning-after-reload"), "loot"))
        equal(ACB.casualWarningPrompt:IsShown(), false)
        equal(saved.counts["npc:589"], 3, "acknowledging the warning never removes progress")
    end)
end)

test("a first Casual pack card warns at acquisition notification and Ranked notifications never warn", function()
    withCasualModeUI(function(saved, ledger)
        saved.packs.DM = 1
        local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, nil, nil, ledger)
        local results = assert(collection:openPack("DM"))
        equal(saved.casualWarningSeen, nil)
        for _, result in ipairs(results) do collection:cardAdded(result.card, result) end
        equal(saved.casualWarningSeen, true)
        ACB.casualWarningPrompt:Hide()
        saved.mode, saved.casualWarningSeen = "ranked", nil
        collection:cardAdded(ACB.cards["npc:589"], { count = 1 })
        equal(saved.casualWarningSeen, nil)
        equal(ACB.casualWarningPrompt:IsShown(), false)
    end)
end)

test("Casual card and pack trades, gifts and legacy listening are blocked without spending inventory", function()
    local saved = ACB.cleanSavedData({ counts = { ["npc:589"] = 2 }, packs = { DM = 1 } })
    local sent, moved = {}, 0
    local trade = ACB.newTrade(saved.counts, function() return 10 end, function() return "casual-trade" end,
        function(_, message) sent[#sent + 1] = message return true end, function() moved = moved + 1 return true end,
        nil, nil, saved)
    trade:start("bob-realm", "npc:589", false)
    trade:start("bob-realm", "pack:DM", true)
    trade:offer("bob-realm", "npc:589")
    equal(trade:listen("bob-realm"), false)
    equal(#sent, 0); equal(trade.session, nil)
    assert(trade.status:find("Download the companion", 1, true))
    equal(trade:receive("bob-realm", "I|casual-incoming|npc:639|g"), false)
    equal(sent[1], "N|casual-incoming")
    trade:confirm()
    equal(trade:canAccept(), false)
    equal(moved, 0); equal(saved.counts["npc:589"], 2); equal(saved.packs.DM, 1)
end)

test("Ranked gift senders get a refusal from Casual recipients before either side accepts", function()
    local aSaved = ACB.cleanSavedData({ mode = "ranked", counts = { ["npc:639"] = 1 } })
    local bSaved = ACB.cleanSavedData({})
    local a, b, moved = nil, nil, 0
    a = ACB.newTrade(aSaved.counts, function() return 1 end, function() return "ranked-to-casual" end,
        function(_, msg) b:receive("alice-realm", msg) return true end,
        function() moved = moved + 1 return true end, nil, nil, aSaved)
    b = ACB.newTrade(bSaved.counts, function() return 1 end, ignore,
        function(_, msg) a:receive("bob-realm", msg) return true end,
        function() moved = moved + 1 return true end, nil, nil, bSaved)
    a:start("bob-realm", "npc:639", true)
    equal(a.session, nil); equal(b.session, nil); equal(moved, 0)
    assert(a.status:find("other player needs the companion", 1, true))
    equal(aSaved.counts["npc:639"], 1)
end)

test("companion setup gates new Ranked selection and trading without downgrading existing Ranked binders", function()
    withCasualModeUI(function(saved, ledger)
        equal(ACB.setMode(saved, ledger, "ranked"), false)
        equal(saved.mode, "casual")
        ACB.sync = { companionReady = true, rankedSetups = { saved.modeSetupID } }
        assert(ACB.setMode(saved, ledger, "ranked"))
        ACB.sync = {}
        local ok, why = ACB.rankedTradeAllowed(saved, "bob-realm")
        equal(ok, false); assert(why:find("companion", 1, true))
        equal(saved.mode, "ranked"); equal(saved.casualDrops, 0)
        local trade = ACB.newTrade(saved.counts, function() return 1 end, function() return "mode-lock" end,
            function() return true end, ignore, nil, nil, saved)
        trade:start("bob-realm")
        equal(ACB.setMode(saved, ledger, "casual"), false, "do not change modes midway through a transfer")
        trade:cancel()
        equal(ACB.setMode(saved, ledger, "casual"), true)
    end)
end)
