-- The Fellowship cards (docs/FELLOWSHIP.md, ledger spec 12): a trade, a gift given or received, a donation to the guild binder and a camp each earn one roll,
-- at one in a hundred, for the card that belongs to them. A Ranked roll uses the tape like any attempt; nothing else can drop these cards.

do
    local TRADER, GIFTER, BENEFACTOR, FIRESIDE = "npc:900000001", "npc:900000002", "npc:900000003", "npc:900000004"
    local function entryRolling(roll) return ("%08x"):format(roll - 1) .. "00000015" end -- not shiny, finds no pack
    local function kinds(saved, from)
        local list = {}
        for index = from or 1, #saved.ledger do
            local event = saved.ledger[index]
            list[#list + 1] = event.kind .. ":" .. event.key .. (event.partner ~= "" and event.kind ~= "tradeIn" and event.kind ~= "tradeOut" and ("@" .. event.partner) or "")
        end
        return table.concat(list, " ")
    end
    local function binder(options)
        options = options or {}
        local saved = ACB.cleanSavedData({ counts = options.counts or {} })
        if options.legacy then saved.balancedDrops = false end
        local ledger = ACB.newLedger(saved, function() return 100 end, function() return "Alice-RealmName" end)
        ledger:begin(false)
        local collection = ACB.newCollection(saved, options.random or function(low, high) if high == ACB.shinyOdds then return 2 end return 10000 end, ignore, ignore, nil, nil, ledger)
        if options.ranked then
            ACB.sync.rankedIssue = nil
            ACB.sync.tape = { start = 1, entries = options.entries }
            assert(ACB.setMode(saved, ledger, "ranked"))
        end
        return saved, ledger, collection
    end

    test("the Fellowship page has four icon cards, flat at one in a hundred, that cannot be crafted", function()
        local page
        for _, entry in ipairs(ACB.pages) do if entry.code == "FW" then page = entry end end
        assert(page, "the Fellowship page")
        equal(page.title, "Fellowship"); equal(page.group, "Social"); equal(#page.cards, 4); equal(page.reward, nil, "the achievement gives the title")
        for activity, key in pairs({ trade = TRADER, gift = GIFTER, donate = BENEFACTOR, camp = FIRESIDE }) do
            local card = ACB.cards[key]
            equal(card.activity, activity); equal(card.since, 12); equal(card.rarity, "rare"); equal(ACB.activityCards[activity], card)
            assert(card.icon:find("^Interface\\Icons\\"), card.icon)
            for _, balanced in ipairs({ false, true, 2 }) do
                for _, misses in ipairs({ 0, 1, 99, 5000 }) do equal(ACB.dropChance(card, misses, balanced), 100) end
            end
            equal(ACB.source(("Creature-0-x-36-4-%d-a"):format(card.id)), nil, "no creature drops it")
        end
        local saved = ACB.cleanSavedData({ dust = 100000 })
        local collection = ACB.newCollection(saved, math.random, ignore, ignore)
        equal(collection:craft(TRADER), false, "dust cannot buy one")
    end)

    test("a Casual trade earns a roll for The Trader, and a gift given or received one for The Gifter", function()
        local saved, ledger, collection = binder({ counts = { ["npc:589"] = 2 }, random = function(low, high)
            if high == ACB.shinyOdds then return 2 end
            return 1 -- a drop at any chance
        end })
        saved.stateSum = nil; ledger:begin(false)
        assert(collection:swap("npc:589", "npc:573", "bob-realm", "trade-1"))
        local text = kinds(saved)
        assert(text:find("mode:fellow1 tradeOut:npc:589 tradeIn:npc:573 drop:" .. TRADER, 1, true), text)
        equal(saved.counts[TRADER], 1); equal(saved.casualDrops, 1, "a Casual drop cannot be rechecked")
        equal(next(saved.fellowOwed), nil, "the roll was paid at once")
        assert(collection:swap("npc:589", nil, "bob-realm", "gift-1")) -- a gift given
        assert(kinds(saved):find("tradeOut:npc:589 drop:" .. GIFTER, 1, true), kinds(saved))
        assert(collection:swap(nil, "npc:590", "bob-realm", "gift-2")) -- a gift received: this side rolls too
        equal(saved.counts[GIFTER], 2)
        equal(ledger:check(), true)
        -- Misses in Casual are not written, and the roll is still spent.
        local missing, _, missCollection = binder({ counts = { ["npc:589"] = 1 } })
        assert(missCollection:swap("npc:589", nil, "bob-realm", "gift-3"))
        equal(missing.counts[GIFTER], nil); equal(next(missing.fellowOwed), nil)
        assert(not kinds(missing):find("miss", 1, true), kinds(missing))
    end)

    test("a Ranked trade rolls on the tape: the roll is written as a drop or a miss on the card, after the trade", function()
        local saved, ledger, collection = binder({ counts = {}, ranked = true, entries = { entryRolling(1), entryRolling(10000), entryRolling(1) } })
        assert(collection:swap(nil, "npc:589", "bob-realm", "gift-in"))
        local text = kinds(saved)
        assert(text:find("mode:fellow1 tradeIn:npc:589 drop:" .. GIFTER, 1, true), text)
        equal(saved.ledger[#saved.ledger].tape, 1); equal(saved.ledger[#saved.ledger].partner, "")
        assert(collection:swap("npc:589", nil, "bob-realm", "gift-out"))
        ledger:flushRun()
        assert(kinds(saved, #saved.ledger - 1):find("tradeOut:npc:589 miss:" .. GIFTER, 1, true), kinds(saved))
        equal(saved.ledger[#saved.ledger].tape, 2); equal(saved.tape.next, 3)
        equal(ledger:check(), true)
    end)

    test("with no tape left a roll stays owed, and is paid when the tape comes", function()
        local saved, ledger, collection = binder({ counts = {}, ranked = true, entries = {} })
        assert(collection:swap(nil, "npc:589", "bob-realm", "gift-in"))
        equal(saved.fellowOwed.gift, 1, "owed, not lost")
        equal(saved.counts[GIFTER], nil)
        ACB.sync.tape = { start = 1, entries = { entryRolling(1) } }
        ACB.settleFellowship(collection)
        equal(saved.counts[GIFTER], 1); equal(next(saved.fellowOwed), nil)
        equal(ledger:check(), true)
    end)

    test("a binder that is not on the current rules earns nothing, and owed rolls are cleaned", function()
        local saved, ledger, collection = binder({ counts = { ["npc:589"] = 1 }, legacy = true })
        assert(collection:swap("npc:589", nil, "bob-realm", "gift-1"))
        assert(not kinds(saved):find("fellow1", 1, true), kinds(saved))
        equal(next(saved.fellowOwed), nil)
        saved.fellowOwed = { trade = 3, gift = -1, donate = 1.5, camp = 999, bogus = 2 }
        ACB.cleanFellowship(saved)
        equal(saved.fellowOwed.trade, 3); equal(saved.fellowOwed.gift, nil); equal(saved.fellowOwed.donate, nil); equal(saved.fellowOwed.camp, 50); equal(saved.fellowOwed.bogus, nil)
        saved.fellowOwed = "junk"
        ACB.cleanFellowship(saved)
        equal(next(saved.fellowOwed), nil)
    end)

    test("a donation to the guild binder earns a roll for The Benefactor", function()
        local keep, keepCollection = ACB.sync, ACB.collection
        local saved, ledger, collection = binder({ counts = {}, ranked = true, entries = { entryRolling(1), entryRolling(1) } })
        saved.modeSetupID = ("c"):rep(32)
        assert(collection:swap(nil, "npc:589", "bob-realm", "gift-in")) -- a card to give, and the gift's own roll (entry 1)
        ACB.sync.guild = { binders = { saved.modeSetupID }, donations = { results = {}, refunds = {} },
            membership = { state = "active", role = "member", guild = { id = "01HF7YAT00QKSEP5RCNMPTQ3KN", name = "Knights", realm = "Realm", side = "alliance", members = 2 } } }
        ACB.collection = collection
        local before = #saved.ledger
        local ok = ACB.donateCard(saved, ledger, "npc:589")
        equal(ok, true)
        local text = kinds(saved, before + 1)
        assert(text:find("mode:guild1 donate:npc:589@01HF7YAT00QKSEP5RCNMPTQ3KN drop:" .. BENEFACTOR, 1, true), text)
        equal(saved.counts[BENEFACTOR], 1)
        equal(next(saved.fellowOwed), nil)
        equal(ledger:check(), true)
        ACB.sync, ACB.collection = keep, keepCollection
    end)

    test("owning all four earns the achievement and its title, once", function()
        local saved = ACB.cleanSavedData({})
        ACB.updateAchievements(saved)
        equal(saved.achievements.fellowship4, nil)
        for _, key in ipairs({ TRADER, GIFTER, BENEFACTOR }) do saved.counts[key] = 1 end
        ACB.updateAchievements(saved)
        equal(saved.achievements.fellowship4, nil, "three of four is not enough")
        saved.counts[FIRESIDE] = 1
        local said = {}
        ACB.updateAchievements(saved, function(text) said[#said + 1] = text end)
        equal(saved.achievements.fellowship4, true); equal(saved.titles["Fellow Traveler"], true)
        assert(said[1]:find("Better Together", 1, true) and said[1]:find("Fellow Traveler", 1, true), said[1])
        equal(ACB.isBinderTitle("Fellow Traveler"), true)
        ACB.updateAchievements(saved, function(text) said[#said + 1] = text end)
        equal(#said, 1, "announced once")
        local totals = ACB.achievementTotals(saved)
        equal(totals.fellowship, 4)
        local earned = ACB.earnedTitles(saved)
        local count = 0
        for _, title in ipairs(earned) do if title == "Fellow Traveler" then count = count + 1 end end
        equal(count, 1)
    end)

    test("a Fellowship card is drawn as an icon, with no model", function()
        local card = ACB.createCard(UIParent, true, ignore)
        card:set(ACB.cards[TRADER], 1)
        equal(card.model:IsShown(), false, "no creature model")
        equal(card.node:IsShown(), true); equal(card.node.texture, ACB.cards[TRADER].icon)
        card:set(ACB.cards[TRADER], 0)
        equal(card.node:IsShown(), true, "shown locked too, dimmed")
    end)
end
