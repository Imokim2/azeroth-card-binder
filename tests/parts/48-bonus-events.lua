do
    local function withBonus(check)
        local oldTime, oldSync, oldCamp = time, ACB.sync, ACB.campBoost
        local at = 1800000000
        time = function() return at end
        local nonce, card = string.rep("b",32), ACB.cards["npc:589"]
        local event = { id = "collectors-hour", title = "Collector's Hour", startsAt = at + 10, endsAt = at + 3610, percent = 200, sets = {}, effect = "card-drops" }
        ACB.sync = { companionReady = true, rankedSetups = { nonce }, bonuses = { at = at, events = { event }, binders = { nonce } } }
        local saved = ACB.cleanSavedData({ modeSetupID = nonce })
        saved.tieredPacks, saved.balancedDrops = false, 2
        local ledger = ACB.newLedger(saved, time, function() return "Filfred-Whizzlebang" end)
        ledger:begin(false)
        local rate = ACB.dropRate(card, 2)
        local function entry(roll) return ("%08x"):format(roll - 1) .. "00000015" end
        ACB.sync.tape = { start = 1, entries = { entry(rate + 1), entry(10000), entry(10000), entry(1) } }
        assert(ACB.setMode(saved, ledger, "ranked")); ledger:check()
        ACB.campBoost = function() return false end
        local collection = ACB.newCollection(saved, function() error("event must use Ranked tape") end, ignore, ignore, nil, nil, ledger)
        local ok, why = pcall(check, saved, ledger, collection, event, function(value) at = value end, card)
        time, ACB.sync, ACB.campBoost = oldTime, oldSync, oldCamp
        assert(ok, why)
    end
    test("scheduled bonuses start and end at exact boundaries, require pairing and use the strongest eligible scope", function()
        withBonus(function(saved, ledger, _, event, clock, card)
            equal(#ACB.activeBonuses(saved, event.startsAt-1), 0)
            equal(ACB.bonusBoost(saved, ledger, true, card, event.startsAt).id, event.id)
            equal(#ACB.activeBonuses(saved, event.endsAt), 0)
            local clone = {}; for key,value in pairs(event) do clone[key] = value end
            clone.id, clone.percent, clone.sets = "westfall-hour", 300, { ACB.pages[card.page].code }
            ACB.sync.bonuses = { events = { event, clone }, binders = { saved.modeSetupID } }
            equal(ACB.bonusBoost(saved, ledger, true, card, event.startsAt).percent, 300)
            saved.mode = "casual"; equal(#ACB.activeBonuses(saved,event.startsAt),0); saved.mode="ranked"
            ACB.sync.bonuses = { events = { event }, binders = { string.rep("f",32) } }
            equal(#ACB.activeBonuses(saved,event.startsAt),0)
            ACB.sync.bonuses = { events = { { id="bad" } } }
            equal(#ACB.activeBonuses(saved,event.startsAt),0); equal(#ACB.activeBonuses(saved,event.startsAt),0)
        end)
    end)
    test("a scheduled Ranked drop uses the bonus and records its original window without changing old inventory", function()
        withBonus(function(saved, ledger, collection, event, clock, card)
            clock(event.startsAt)
            equal(collection:roll(guid(589,"bonus-find"),"loot"),true)
            equal(saved.counts[card.key],1); equal(saved.counts["npc:721"],nil)
            local found; for _, row in ipairs(saved.ledger) do if row.kind=="drop" then found=row end end
            equal(found.partner,"bonus"); equal(found.trade,event.id..":"..event.startsAt..":"..event.startsAt)
            assert(ledger:verify())
        end)
    end)
    test("a saved boosted miss run retains attempt times and can flush after the event has ended", function()
        withBonus(function(saved, ledger, collection, event, clock, card)
            clock(event.startsAt); ACB.sync.tape.entries[1] = ACB.sync.tape.entries[2]
            equal(collection:roll(guid(589,"bonus-miss"),"loot"),false)
            local before = saved.run
            equal(before.bonus,event.id); equal(before.fromAt,event.startsAt)
            ACB.cleanSavedData(saved); equal(saved.run.bonus,event.id); equal(saved.run.untilAt,event.startsAt)
            clock(event.endsAt+100); ledger:flushRun()
            local row = saved.ledger[#saved.ledger]
            equal(row.kind,"miss"); equal(row.partner,"bonus"); equal(row.trade,event.id..":"..event.startsAt..":"..event.startsAt)
        end)
    end)
    test("the binder badge counts down and event notices are once-only, with an independent sound setting", function()
        withBonus(function(saved, ledger, collection, event, clock, card)
            local oldWatcher, oldFrame, oldSound = ACB.bonusWatcher, DEFAULT_CHAT_FRAME, ACB.playSound
            local lines, sounds = {}, 0
            ACB.bonusWatcher=nil; DEFAULT_CHAT_FRAME={ AddMessage=function(_,line) lines[#lines+1]=line end }
            ACB.playSound=function() sounds=sounds+1 end
            local ok,why=pcall(function()
                local badge=ACB.createBonusBadge(CreateFrame("Frame"),saved)
                ACB.initBonusEvents(saved,ledger); equal(#lines,0)
                clock(event.startsAt); ACB.bonusWatcher.update(); equal(#lines,1); equal(sounds,1)
                assert(badge:IsShown()); assert(badge.clock:GetText():find("1h 00m",1,true))
                ACB.bonusWatcher.update(); equal(#lines,1)
                clock(event.endsAt); ACB.bonusWatcher.update(); equal(#lines,2); equal(badge:IsShown(),false)
                clock(event.startsAt); ACB.bonusWatcher.update(); equal(sounds,1,"reload/clock changes must not repeat the cue")
            end)
            ACB.bonusWatcher, DEFAULT_CHAT_FRAME, ACB.playSound=oldWatcher,oldFrame,oldSound
            assert(ok,why)
        end)
    end)
end
