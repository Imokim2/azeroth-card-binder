test("seasons require this binder's companion pairing and never count its existing inventory", function()
    local keep = ACB.sync
    local saved, ledger = modeBinder()
    saved.counts["npc:589"] = 7
    local season = { startsAt = 100, endsAt = 200, cards = { "npc:589" }, collected = {} }
    local data = { binders = { ("b"):rep(32) }, seasons = { season }, grants = {} }
    ACB.sync = { seasonal = data }
    equal(ACB.seasonData(saved), nil)
    data.binders[1] = saved.modeSetupID
    equal(ACB.seasonData(saved), data)
    local have, pending, amount = ACB.seasonProgress(saved, season)
    equal(amount, 0); equal(have["npc:589"], nil); equal(pending["npc:589"], nil)
    saved.mode = "ranked"
    saved.ledger = { { t = 110, kind = "drop", key = "npc:589", tape = 2 } }
    have, pending, amount = ACB.seasonProgress(saved, season)
    equal(amount, 0); equal(pending["npc:589"], true)
    season.collected = { "npc:589" }
    have, pending, amount = ACB.seasonProgress(saved, season)
    equal(amount, 1); equal(pending["npc:589"], nil)
    ACB.sync = keep
end)

test("legacy trade slash commands explain the player menu without opening a trade", function()
    ACB.tradeView:Hide()
    SlashCmdList.AZEROTHCARDBINDER("trade")
    equal(ACB.tradeView:IsShown(), false)
    SlashCmdList.AZEROTHCARDBINDER("trade Bob Realmname")
    equal(ACB.tradeView:IsShown(), false)
end)

test("season reward packs use the normal satchel, record a grant once and preserve normal cards", function()
    local keep = ACB.sync
    local saved, ledger = modeBinder()
    local grant = ("a"):rep(32)
    local zone = ACB.cards["npc:589"].page
    local pack = ACB.pages[zone].code
    ACB.sync = { seasonal = { binders = { saved.modeSetupID }, seasons = { { titles = { "Season Seeker" } } }, grants = { { id = grant, pack = pack } } } }
    local sum = saved.stateSum
    equal(ACB.claimSeasonRewards(saved, ledger), 1)
    equal(saved.packs[pack], 1); equal(saved.stateSum, sum)
    equal(saved.ledger[1].kind, "seasonReward"); equal(saved.ledger[1].trade, grant)
    equal(ACB.claimSeasonRewards(saved, ledger), 0); equal(saved.packs[pack], 1)
    equal(saved.titles["Season Seeker"], true)
    equal(ACB.isBinderTitle("Season Seeker"), true)
    local titles = ACB.earnedTitles(saved)
    equal(titles[#titles], "Season Seeker")
    equal(ledger:check(), true)
    ACB.cleanSavedData(saved)
    equal(saved.seasonClaims[grant], true); equal(saved.seasonTitles["Season Seeker"], true)
    saved.run = { key = "npc:589", n = 1, last = 1 }
    ACB.sync.seasonal.grants = { { id = ("b"):rep(32), pack = pack } }
    local before = #saved.ledger
    equal(ACB.claimSeasonRewards(saved, ledger), 1)
    equal(saved.run, nil)
    equal(saved.ledger[before + 1].kind, "miss", "pending misses stay ahead of a claimed reward")
    equal(saved.ledger[before + 2].kind, "seasonReward")
    equal(saved.packs[pack], 2)
    ACB.sync = keep
end)

test("the Seasons tab fits the binder and hides the normal collection and unwanted layers", function()
    ACB.open("seasons")
    local binder = _G["AzerothCardBinderWindow"]
    equal(binder:IsShown(), true)
    equal(ACB.binderView:IsShown(), false)
    local seasons
    for _, control in ipairs(widgets) do
        if control.parent == binder then
            assert(control.text ~= "Trade", "Trade must not be a binder tab")
            if control.text == "Seasons" then seasons = control end
        end
    end
    assert(seasons); equal(seasons.point[2], 284, "Seasons replaces the third tab")
    ACB.open("collection")
    equal(ACB.binderView:IsShown(), true)
end)
