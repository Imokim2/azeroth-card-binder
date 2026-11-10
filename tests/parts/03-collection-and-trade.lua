test("a swap moves one spare copy and can finish a set", function()
    local saved = { counts = {}, achievements = {} }
    for _, card in ipairs(ACB.pages[1].cards) do saved.counts[card.key] = 1 end
    saved.counts["npc:639"] = nil
    saved.counts["npc:598"] = 2
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore)
    equal(collection:swap("npc:639", "npc:598"), false)
    equal(collection:swap("npc:589", "npc:639"), false)
    equal(collection:swap("npc:598", "npc:639"), true)
    equal(saved.counts["npc:598"], 1)
    equal(saved.counts["npc:639"], 1)
    equal(saved.achievements.crew, true)
    equal(saved.achievements.deadmines, true)
    equal(collection:swap("npc:598", "npc:639"), false)
end)

test("a lost confirmation is healed by re-sending, and nobody applies twice", function()
    local aCards, bCards = { ["npc:589"] = 2 }, { ["npc:639"] = 2 }
    local a, b
    local dropFromA = true
    local function swapper(counts)
        return function(give, take)
            counts[give] = counts[give] - 1
            counts[take] = (counts[take] or 0) + 1
            return true
        end
    end
    a = ACB.newTrade(aCards, function() return 1 end, function() return "id-1" end, function(peer, msg)
        if dropFromA and msg:sub(1, 1) == "C" then return true end -- sent, but never arrives
        b:receive("alice-realm", msg)
        return true
    end, swapper(aCards))
    b = ACB.newTrade(bCards, function() return 1 end, function() return "id-2" end, function(peer, msg)
        a:receive("bob-realm", msg)
        return true
    end, swapper(bCards))
    a:offer("bob-realm", "npc:589")
    b:listen("alice-realm")
    a:retry()
    b:reply("npc:639")
    a:confirm()
    b:confirm()
    -- Alice has both confirmations and has swapped; Bob never received hers.
    equal(aCards["npc:639"], 1)
    equal(bCards["npc:589"], nil)
    dropFromA = false
    b:retry()
    equal(bCards["npc:589"], 1)
    equal(bCards["npc:639"], 1)
    b:retry()
    b:retry()
    b:retry()
    equal(aCards["npc:589"], 1)
    equal(aCards["npc:639"], 1)
    equal(bCards["npc:589"], 1)
    equal(bCards["npc:639"], 1)
end)

test("every miss stacks the chance of the next attempt up to a certain drop, and a drop starts it over", function()
    local saved = { counts = {}, achievements = {} }
    local draws = 0
    local collection = ACB.newCollection(saved, function(min, max)
        if max == ACB.shinyOdds then return 2 end
        draws = draws + 1
        return 150 -- beats nothing at 1% but wins once the chance has stacked to 2%
    end, ignore, ignore)
    local misses, limit = ACB.luck(saved, ACB.cards["npc:589"])
    equal(misses, 0)
    equal(limit, 100) -- a 1% card is certain on its 100th attempt
    equal(select(2, ACB.luck(saved, ACB.cards["npc:639"])), 50) -- a 2% card
    equal(select(2, ACB.luck(saved, ACB.cards["npc:573"])), 10) -- a 10% card
    equal(select(2, ACB.luck(saved, ACB.cards["node:1731"])), 100)
    -- The chances, as numbers.
    equal(ACB.chanceAfter(100, 0), 100)
    equal(ACB.chanceAfter(100, 1), 200)
    equal(ACB.chanceAfter(100, 9), 1000)
    equal(ACB.chanceAfter(100, 99), 10000)
    equal(ACB.chanceAfter(100, 5000), 10000) -- never above certain
    equal(ACB.luckText(saved, ACB.cards["npc:589"], true), "Next attempt: 1%")
    equal(ACB.luckText(saved, ACB.cards["npc:589"]), nil) -- nothing to say before the first miss
    -- The first attempt faces 1% and misses; the second faces 2% against a roll of 150, and wins.
    equal(collection:roll(guid(589, "first"), "loot"), false)
    equal(saved.misses["npc:589"], 1)
    equal(ACB.luckText(saved, ACB.cards["npc:589"]), "Next attempt: 2%")
    equal(collection:roll(guid(589, "second"), "loot"), true)
    equal(saved.counts["npc:589"], 1)
    equal(saved.misses["npc:589"], nil)
    equal(ACB.luckText(saved, ACB.cards["npc:589"]), nil)
    -- A roll nothing can beat: a miss until the stack reaches certain, which needs no roll.
    collection = ACB.newCollection(saved, function(min, max)
        if max == ACB.shinyOdds then return 2 end
        draws = draws + 1
        return 10000
    end, ignore, ignore)
    for attempt = 1, limit - 1 do
        equal(collection:roll(guid(589, "miss" .. attempt), "loot"), false)
    end
    equal(ACB.luck(saved, ACB.cards["npc:589"]), limit - 1)
    equal(ACB.luckText(saved, ACB.cards["npc:589"]), "Next attempt guaranteed")
    local before = draws
    equal(collection:roll(guid(589, "lucky"), "loot"), true)
    equal(draws, before) -- a certain drop needs no roll
    equal(saved.counts["npc:589"], 2)
    equal(ACB.luck(saved, ACB.cards["npc:589"]), 0)
    saved.misses["npc:639"] = 51 -- misses banked before the stack was introduced
    equal(collection:roll(guid(639, "legacy"), "loot"), true)
    equal(ACB.luck(saved, ACB.cards["npc:639"]), 0)
    -- A factor of 0 is a flat chance with no stack.
    ACB.stackFactor = 0
    equal(ACB.chanceAfter(100, 99), 100)
    equal(select(2, ACB.luck(saved, ACB.cards["npc:589"])), nil)
    for attempt = 1, 300 do collection:roll(guid(589, "off" .. attempt), "loot") end
    equal(saved.counts["npc:589"], 2)
    ACB.stackFactor = 1
    -- Half the step makes the stack twice as slow.
    ACB.stackFactor = 0.5
    equal(ACB.chanceAfter(100, 4), 300)
    equal(select(2, ACB.luck(saved, ACB.cards["npc:589"])), 199)
    ACB.stackFactor = 1
end)

test("finishing a set earns its title once and announces it", function()
    -- A small set of its own, so the test does not depend on how big the real sets are.
    ACB.addPlace("test-place", "Test Place", "Zone", "", { { 900001, "Test One", "n", 5 }, { 900002, "Test Two", "n", 5 } })
    local index = ACB.pageForPlace["test-place"]
    local page = ACB.pages[index]
    equal(index, #ACB.pages)
    local saved = { counts = {}, achievements = {} }
    local done = {}
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, nil, function(set, reward)
        done[#done + 1] = { page = set.code, reward = reward }
    end)
    saved.counts["npc:900001"] = 1
    collection:roll(guid(900002, "last"), "loot")
    equal(#done, 1)
    equal(done[1].page, page.code)
    equal(done[1].reward, "Test Place Collector")
    equal(saved.sets[page.code], true)
    equal(saved.titles["Test Place Collector"], true)
    equal(saved.title, "Test Place Collector")
    collection:roll(guid(900002, "again"), "loot")
    equal(#done, 1) -- a set is only completed once
    table.remove(ACB.pages, index)
    ACB.pageForPlace["test-place"], ACB.zones["test-place"] = nil, nil
    for _, id in ipairs({ 900001, 900002 }) do
        ACB.cards["npc:" .. id], ACB.sources.Creature[id] = nil, nil
    end
end)

test("milestones use unique cards, backfill sets and keep a lifetime trade count", function()
    local saved = { counts = {}, shiny = {}, achievements = { crew = true }, history = {} }
    local westfall = ACB.pages[2]
    for index = 1, 9 do saved.counts[westfall.cards[index].key] = 5 end
    saved.shiny[westfall.cards[1].key] = true
    saved.shiny[westfall.cards[10].key] = true -- A shiny with no owned copy does not count.
    ACB.updateAchievements(saved)
    equal(ACB.achievementTotals(saved).cards, 9)
    equal(ACB.achievementTotals(saved).shiny, 1)
    equal(saved.achievements.cards10, nil)
    equal(saved.titles["Shiny Seeker"], true)
    equal(saved.titles["Defias Bane"], true)
    for _, card in ipairs(westfall.cards) do saved.counts[card.key] = 1 end
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore)
    collection:restoreAchievements()
    equal(saved.sets[westfall.code], true)
    equal(saved.titles["Card Seeker"], true)
    equal(saved.titles["Set Keeper"], true)
    equal(saved.titles[westfall.reward], true)
    equal(saved.title, nil)
    for i = 1, 20 do saved.history[i] = { give = "npc:589", take = "npc:639" } end
    local announcements = 0
    for i = 1, 6 do
        ACB.logTrade(saved, "npc:589", "npc:639", "bob-realm", i, function(message)
            if message:find("Spare for Spare", 1, true) then announcements = announcements + 1 end
        end)
    end
    equal(saved.tradeCount, 26)
    equal(#saved.history, 20)
    equal(saved.titles["Card Broker"], true)
    equal(announcements, 1)
end)

test("partners can share spares and wants, and trades are logged", function()
    local aCards, bCards = { ["npc:589"] = 2, ["npc:590"] = 3, ["npc:114"] = 1 }, { ["npc:639"] = 2 }
    local a, b
    local applied = {}
    a = ACB.newTrade(aCards, function() return 1 end, function() return "id-1" end, function(peer, msg)
        b:receive("alice-realm", msg)
        return true
    end, function(give, take, peer) applied[#applied + 1] = { give, take, peer } return true end,
        function() return { "npc:573", "npc:639" } end)
    b = ACB.newTrade(bCards, function() return 1 end, function() return "id-2" end, function(peer, msg)
        a:receive("bob-realm", msg)
        return true
    end, function() return true end, function() return {} end)
    a:shareLists() -- nothing started yet
    equal(a.status, "Start a trade first.")
    a:listen("bob-realm")
    b:listen("alice-realm")
    a:shareLists()
    equal(table.concat(b.session.theirSpares, ","), "npc:589,npc:590")
    equal(table.concat(b.session.theirWants, ","), "npc:573,npc:639")
    -- Unknown keys, bad characters and messages from other people are ignored.
    b:receive("alice-realm", "S|npc:589,npc:99999,node:1731")
    equal(table.concat(b.session.theirSpares, ","), "npc:589,node:1731")
    b:receive("alice-realm", "S|npc:589;drop")
    equal(table.concat(b.session.theirSpares, ","), "npc:589,node:1731")
    b:receive("mallory-realm", "S|npc:573")
    equal(table.concat(b.session.theirSpares, ","), "npc:589,node:1731")
    -- A long list is cut to fit one addon message and twelve cards.
    local saved = { counts = {}, achievements = {}, history = {} }
    ACB.logTrade(saved, "npc:589", "npc:639", "bob-realm", 100)
    ACB.logTrade(saved, "npc:590", "npc:573", "carol-realm", 200)
    equal(saved.history[1].peer, "carol-realm") -- newest first
    for index = 1, 30 do ACB.logTrade(saved, "npc:589", "npc:639", "x" .. index, index) end
    equal(#saved.history, 20)
    local lines = ACB.tradeHistory(saved)
    equal(#lines, 20)
    assert(lines[1]:find("Defias Pillager for Edwin VanCleef", 1, true))
    assert(lines[1]:find("with x30", 1, true))
    -- Only missing cards that were marked count as wanted.
    local mine = { counts = { ["npc:639"] = 1 }, wanted = {} }
    equal(#ACB.wantedCards(mine), 0)
    mine.wanted["npc:573"] = true
    equal(table.concat(ACB.wantedCards(mine), ","), "npc:573")
    mine.wanted["npc:639"] = true -- already owned, so not wanted
    equal(table.concat(ACB.wantedCards(mine), ","), "npc:573")
end)

test("a first copy can be shiny once per card and the pop-up hook hears about it", function()
    local saved = { counts = {}, achievements = {} }
    local shinyRolls, found = 0, {}
    local collection = ACB.newCollection(saved, function(min, max)
        if max == ACB.shinyOdds then shinyRolls = shinyRolls + 1 end
        return 1
    end, ignore, ignore, function(card, info) found[#found + 1] = { card = card, info = info } end)
    collection:roll(guid(589, "A"), "loot")
    equal(saved.shiny["npc:589"], true)
    equal(found[1].info.shiny, true)
    equal(found[1].info.first, true)
    collection:roll(guid(589, "B"), "loot")
    equal(shinyRolls, 1) -- an owned shiny is never rolled for again
    equal(found[2].info.shiny, false)
    equal(found[2].info.first, false)
    equal(found[2].info.count, 2)
    saved.counts["npc:590"] = 2
    collection:swap("npc:590", "npc:114")
    equal(found[3].card.key, "npc:114")
    equal(found[3].info.trade, true)
    equal(saved.shiny["npc:114"], nil) -- trades never hand out shiny copies
end)

test("two peers confirm the exact pair and each applies the swap once", function()
    local aCards, bCards = { ["npc:589"] = 2 }, { ["npc:639"] = 2 }
    local a, b
    local now, allow = 1, true
    local function swapper(counts)
        return function(give, take)
            if (counts[give] or 0) < 2 then return false end
            counts[give] = counts[give] - 1
            counts[take] = (counts[take] or 0) + 1
            return true
        end
    end
    a = ACB.newTrade(aCards, function() return now end, function() return "first-1" end, function(peer, msg)
        if not allow then return false, "Blocked" end
        equal(peer, "bob-realm")
        b:receive("alice-realm", msg)
        return true
    end, swapper(aCards))
    b = ACB.newTrade(bCards, function() return now end, function() return "second-1" end, function(peer, msg)
        equal(peer, "alice-realm")
        a:receive("bob-realm", msg)
        return true
    end, swapper(bCards))
    a:offer("bob-realm", "npc:639")
    equal(a.session, nil)
    b:listen("alice-realm")
    b:receive("uninvited-realm", "O|first-1|npc:589")
    equal(b.session.take, nil)
    b:receive("alice-realm", "O|first-1|npc:99999")
    equal(b.session.take, nil)
    allow = false
    a:offer("bob-realm", "npc:589")
    equal(a.status, "Blocked")
    equal(b.session.take, nil)
    allow = true
    a:retry()
    equal(b.session.take, "npc:589")
    b:receive("alice-realm", "O|first-1|npc:573")
    equal(b.session.take, "npc:589")
    b:reply("npc:639")
    equal(a.session.take, "npc:639")
    b:confirm()
    equal(a.session.peerConfirmed, true)
    equal(a.session.sentConfirm, nil)
    aCards["npc:589"] = 1
    a:confirm()
    equal(b.session.peerConfirmed, nil)
    aCards["npc:589"] = 2
    b:receive("alice-realm", "C|first-1|npc:589|npc:573")
    equal(b.session.peerConfirmed, nil)
    a:confirm()
    a:retry()
    equal(a.session.sentConfirm and b.session.sentConfirm and b.session.peerConfirmed, true)
    -- Each side applied the swap exactly once, even though a confirmation was sent again.
    equal(aCards["npc:589"], 1)
    equal(aCards["npc:639"], 1)
    equal(bCards["npc:639"], 1)
    equal(bCards["npc:589"], 1)
    now = 122
    equal(a:active(), nil)
    equal(b:active(), nil)
    b:listen("alice-realm")
    b:receive("alice-realm", "O|first-1|npc:589")
    equal(b.session.take, nil)
end)
