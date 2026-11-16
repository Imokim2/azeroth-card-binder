-- The campfire (docs/CAMPFIRE.md, ledger spec 12): the welcoming campfire buff (1229739) and the violet one (1289723) double the chance of a card drop.
-- A Ranked binder writes mode/camp1, a camp claim and each boosted attempt (partner "camp") so the server can recheck the rolls; Casual just rolls.

do
    local WELCOMING, VIOLET = 1229739, 1289723

    -- The older aura call, with the buffs we are given: { spellId, remaining, duration }.
    local function withBuffs(buffs, check)
        local keep = { UnitAura = UnitAura, C_UnitAuras = C_UnitAuras }
        C_UnitAuras = nil
        UnitAura = function(unit, index, filter)
            local buff = filter == "HELPFUL" and buffs[index]
            if not buff then return nil end
            return buff.name or "Campfire", 135805, 1, nil, buff.duration or 3600, GetTime() + buff.remaining, "player", false, false, buff.spellId
        end
        local ok, problem = pcall(check)
        UnitAura, C_UnitAuras = keep.UnitAura, keep.C_UnitAuras
        if not ok then error(problem, 0) end
    end

    -- A Ranked binder on the current drop rules, with a tape of the given entries. The roll of an entry is its first eight hex digits plus one.
    local function entryRolling(roll) return ("%08x"):format(roll - 1) .. "00000015" end -- not shiny, finds no pack
    local function campBinder(entries)
        ACB.sync.rankedIssue = nil
        local saved = {}
        local _, upgraded = ACB.cleanSavedData(saved)
        saved.tieredPacks = false
        local ledger = newLedger(saved)
        ledger:begin(upgraded)
        local collection = ACB.newCollection(saved, function() error("Ranked mode must not use the computer's random numbers") end, ignore, ignore, nil, nil, ledger)
        ACB.sync.tape = { start = 1, entries = entries }
        assert(ACB.setMode(saved, ledger, "ranked"))
        ledger:check()
        return saved, ledger, collection
    end
    local function kinds(saved, from)
        local list = {}
        for index = from or 1, #saved.ledger do
            local event = saved.ledger[index]
            list[#list + 1] = event.kind .. ":" .. event.key .. (event.partner ~= "" and ("@" .. event.partner) or "")
        end
        return table.concat(list, " ")
    end
    local npc = ACB.cards["npc:589"]

    test("the campfire buff is read from the two spell ids, with the time left capped at what the buff can last", function()
        withBuffs({}, function() equal(ACB.campfire(), nil) end)
        withBuffs({ { spellId = 12345, remaining = 900 } }, function() equal(ACB.campfire(), nil, "another buff is not the campfire") end)
        withBuffs({ { spellId = WELCOMING, remaining = 3000 } }, function()
            local camp = ACB.campfire()
            equal(camp.kind, "welcoming"); equal(camp.seconds, 3600); equal(camp.remaining, 3000); equal(camp.icon, 135805); equal(camp.spellId, WELCOMING)
        end)
        withBuffs({ { spellId = VIOLET, remaining = 7000, duration = 7200 } }, function()
            local camp = ACB.campfire()
            equal(camp.kind, "violet"); equal(camp.seconds, 7200); equal(camp.remaining, 7000)
        end)
        withBuffs({ { spellId = WELCOMING, remaining = 900 }, { spellId = VIOLET, remaining = 5000 } }, function() equal(ACB.campfire().kind, "violet", "the one with more time left") end)
        withBuffs({ { spellId = WELCOMING, remaining = 99999 } }, function() equal(ACB.campfire().remaining, 3600, "never more than the buff lasts") end)
        withBuffs({ { spellId = WELCOMING, remaining = 0 } }, function() equal(ACB.campfire(), nil, "an expired buff is not a buff") end)
    end)

    test("a Casual roll is doubled at a camp, nothing is recorded, and without the buff nothing changes", function()
        local base = ACB.dropChance(npc, 0, 2)
        local function attempt(buffed)
            local saved = ACB.cleanSavedData({})
            local collection = ACB.newCollection(saved, function(min, max)
                if max == ACB.shinyOdds then return 2 end
                return base + 1 -- a miss at the plain chance, a drop at double it
            end, ignore, ignore)
            local result
            local function roll() result = collection:roll(guid(589, buffed and "camp" or "plain"), "loot") end
            if buffed then withBuffs({ { spellId = WELCOMING, remaining = 3000 } }, roll) else withBuffs({}, roll) end
            return result, saved
        end
        assert(base * 2 >= base + 1 and base < 10000)
        local plain = attempt(false)
        equal(plain, false)
        local buffed, saved = attempt(true)
        equal(buffed, true, "a roll between the plain chance and double it is a drop at a camp")
        equal(saved.counts["npc:589"], 1)
        equal(#saved.ledger, 0, "Casual writes no ledger")
    end)

    test("a Ranked attempt at a camp writes camp1, the claim and a boosted drop, once each", function()
        local base = ACB.dropChance(npc, 0, 2)
        -- The second entry is for the roll the camp earns (Fellowship), paid before the next creature roll; the third is that creature roll's.
        local saved, ledger, collection = campBinder({ entryRolling(base + 1), entryRolling(10000), entryRolling(base + 1) })
        withBuffs({ { spellId = VIOLET, remaining = 6000, duration = 7200 } }, function()
            equal(collection:roll(guid(589, "a"), "loot"), true, "boosted: a roll above the plain chance wins")
        end)
        local text = kinds(saved)
        assert(text:find("mode:faction1", 1, true), text)
        assert(text:find("mode:camp1 mode:fellow1 camp:violet drop:npc:589@camp", 1, true), text)
        local claim
        for _, event in ipairs(saved.ledger) do if event.kind == "camp" then claim = event end end
        equal(claim.count, 6000); equal(saved.campEnd, claim.t + 6000); equal(saved.campLedger, true)
        equal(ledger:check(), true)
        -- Another attempt inside the same buff writes no new claim.
        local before = #saved.ledger
        withBuffs({ { spellId = VIOLET, remaining = 5990, duration = 7200 } }, function() collection:roll(guid(589, "b"), "loot") end)
        equal(kinds(saved, before + 1), "miss:npc:900000004@camp drop:npc:589@camp", "the camp's own roll for Fireside Friend, boosted too, then the drop")
        equal(saved.ledger[#saved.ledger].count, 2)
        equal(ledger:check(), true)
    end)

    test("a run of boosted misses is written as boosted, and ends when the buff does", function()
        local saved, ledger, collection = campBinder({ entryRolling(10000), entryRolling(10000), entryRolling(10000) })
        withBuffs({ { spellId = WELCOMING, remaining = 3000 } }, function()
            equal(collection:roll(guid(589, "a"), "loot"), false)
            saved.fellowOwed = {} -- the camp's own roll (Fellowship) is tested above; this test is about runs of creature misses
            equal(collection:roll(guid(589, "b"), "loot"), false)
        end)
        equal(saved.run.n, 2); equal(saved.run.boost, true)
        -- The buff is gone: the next miss is a plain one, so the boosted run is written first and the new run starts unboosted.
        withBuffs({}, function() equal(collection:roll(guid(589, "c"), "loot"), false) end)
        local misses = {}
        for _, event in ipairs(saved.ledger) do if event.kind == "miss" then misses[#misses + 1] = event end end
        equal(#misses, 1); equal(misses[1].count, 2); equal(misses[1].partner, "camp")
        equal(saved.run.n, 1); equal(saved.run.boost, nil)
        ledger:flushRun()
        equal(saved.ledger[#saved.ledger].partner, "", "the plain run is written plain")
        equal(ledger:check(), true)
    end)

    test("a Ranked attempt with no buff, or on a binder that cannot record it, is not boosted", function()
        local base = ACB.dropChance(npc, 0, 2)
        local saved, ledger, collection = campBinder({ entryRolling(base + 1), entryRolling(base + 1) })
        withBuffs({}, function() equal(collection:roll(guid(589, "a"), "loot"), false) end)
        assert(not kinds(saved):find("camp", 1, true), kinds(saved))
        saved.exactMode = nil -- a binder that does not write every attempt down cannot claim the boost on the record
        withBuffs({ { spellId = WELCOMING, remaining = 3000 } }, function() equal(ACB.campBoost(saved, ledger, true), false) end)
        saved.exactMode = true
        ledger.ok = false
        withBuffs({ { spellId = WELCOMING, remaining = 3000 } }, function() equal(ACB.campBoost(saved, ledger, true), false, "a history that does not verify is not extended") end)
    end)

    test("an elite, a rare spawn or a boss is never boosted, whatever the buff", function()
        local elite, boss, rare = ACB.cards["npc:10000"], ACB.cards["npc:10162"], ACB.cards["npc:589"]
        equal(ACB.campEligible(elite), false); equal(ACB.campEligible(boss), false); equal(ACB.campEligible(rare), true)
        equal(ACB.campEligible(nil), false)
        local saved, ledger = campBinder({ entryRolling(5000) })
        withBuffs({ { spellId = WELCOMING, remaining = 3000 } }, function()
            equal(ACB.campBoost(saved, ledger, true, elite), false)
            equal(ACB.campBoost(saved, ledger, true, boss), false)
            equal(ACB.campBoost(saved, ledger, false, boss), false, "Casual neither")
            equal(ACB.campBoost(saved, ledger, false, rare), true)
        end)
        assert(not kinds(saved):find("camp", 1, true), "nothing was claimed for them: " .. kinds(saved))
    end)

    test("the icon follows the buff: shown with the time left, hidden when the buff ends or when switched off", function()
        local report = {}
        local function say(text) report[#report + 1] = text end
        withBuffs({ { spellId = WELCOMING, remaining = 3000 } }, function()
            ACB.refreshCampfire()
            local shown, kind = ACB.campfireShown()
            equal(shown, true); equal(kind, "welcoming")
            local frame = _G["AzerothCardBinderCampfire"]
            equal(frame.timer.text, "50m 00s"); equal(frame.texture.texture, 135805)
            ACB.campfireCommand({}, "", say)
            assert(report[1]:find("welcoming, 50m 00s left", 1, true) and report[1]:find("doubled", 1, true), report[1])
            AzerothCardBinderDB = AzerothCardBinderDB or {}
            local keep = AzerothCardBinderDB.campfireIcon
            ACB.campfireCommand(AzerothCardBinderDB, "icon", say)
            equal(AzerothCardBinderDB.campfireIcon, false); equal(ACB.campfireShown(), false, "hidden by the setting")
            ACB.campfireCommand(AzerothCardBinderDB, "icon", say)
            equal(AzerothCardBinderDB.campfireIcon, true); equal(ACB.campfireShown(), true)
            AzerothCardBinderDB.campfireIcon = keep
        end)
        withBuffs({ { spellId = VIOLET, remaining = 7000, duration = 7200 } }, function()
            ACB.refreshCampfire()
            equal(select(2, ACB.campfireShown()), "violet"); equal(_G["AzerothCardBinderCampfire"].timer.text, "1h 56m")
        end)
        withBuffs({}, function()
            ACB.refreshCampfire()
            equal(ACB.campfireShown(), false)
            report = {}
            ACB.campfireCommand({}, "", say)
            assert(report[1]:find("No campfire buff", 1, true), report[1])
        end)
    end)
end
