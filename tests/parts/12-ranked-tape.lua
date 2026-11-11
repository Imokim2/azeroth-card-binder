-- Ranked mode: random numbers from the server's tape (docs/LEDGER-SPEC.md, section 8).

-- Entries made by hand: the first 8 hex characters give the roll, the next 8 the shiny roll.
local DROP_SHINY = "0000000000000000" -- roll 1 (a drop at any rate), shiny roll 1 (shiny)
local MISS = "0000270f00000001" -- roll 10000 (a miss), shiny roll 2
local DROP_PLAIN = "0000000000000001" -- roll 1, shiny roll 2 (not shiny)

local function rankedBinder(entries, start, report)
    local saved = {}
    local _, upgraded = ACB.cleanSavedData(saved)
    local ledger = newLedger(saved)
    ledger:begin(upgraded)
    local collection = ACB.newCollection(saved, function() error("Ranked mode must not use the computer's random numbers") end,
        report or ignore, ignore, nil, nil, ledger)
    ACB.sync.tape = { start = start or 1, entries = entries }
    assert(ACB.setMode(saved, ledger, "ranked"))
    return saved, ledger, collection
end

test("the Lua tape functions give exactly the roll and shiny values in the shared vectors", function()
    local tape = vectors.tape
    for _, case in ipairs(tape.cases) do
        equal(ACB.tapeRoll(case.entry), case.roll)
        equal(ACB.tapeShiny(case.entry, tape.shinyOdds), case.shiny)
        equal(ACB.tapeRoll(case.entry) <= 100, case.dropsAt100)
        equal(ACB.tapeRoll(case.entry) <= 1000, case.dropsAt1000)
        equal(ACB.tapeShiny(case.entry, tape.shinyOdds) == 1, case.firstCopyShiny)
    end
    equal(ACB.sha256(table.concat(tape.entries, "\n")), tape.commitment)
    equal(ACB.tapeRoll(DROP_SHINY), 1)
    equal(ACB.tapeRoll(MISS), 10000)
    equal(ACB.tapeShiny(MISS, 20), 2)
end)

test("Ranked rolls use the tape in order, win or lose, and write every attempt into the ledger", function()
    local saved, ledger, collection = rankedBinder({ MISS, DROP_SHINY, DROP_PLAIN })
    equal(saved.mode, "ranked")
    equal(saved.ledger[1].kind, "mode")
    equal(saved.ledger[1].key, "ranked2")
    equal(saved.ledger[1].tape, 0) -- no entry used yet
    equal(ACB.tapeLeft(saved), 3)
    equal(collection:roll(guid(589, "r1"), "loot"), false) -- entry 1: a miss, still used up
    equal(saved.tape.next, 2)
    equal(saved.attempts["npc:589"], 1)
    equal(saved.misses["npc:589"], 1)
    equal(#saved.ledger, 1) -- the miss is an open run, written once something else happens
    equal(saved.run.n, 1)
    equal(collection:roll(guid(589, "r2"), "loot"), true) -- entry 2: a shiny first copy
    equal(saved.run, nil)
    equal(saved.ledger[2].kind, "miss") -- the run that came before the drop
    equal(saved.ledger[2].key, "npc:589")
    equal(saved.ledger[2].count, 1)
    equal(saved.ledger[2].tape, 1)
    equal(saved.ledger[3].kind, "drop")
    equal(saved.ledger[3].tape, 2)
    equal(saved.ledger[3].shiny, 1)
    equal(collection:roll(guid(589, "r3"), "loot"), true) -- entry 3: a second copy
    equal(saved.ledger[4].tape, 3)
    equal(saved.ledger[4].shiny, 0)
    equal(saved.counts["npc:589"], 2)
    equal(saved.tape.next, 4)
    equal(ACB.tapeLeft(saved), 0)
    equal(ledger:verify(), true)
end)

test("with the tape used up, Ranked rolling pauses once with a message, loses nothing, and resumes after a refill", function()
    local lines = {}
    local saved, ledger, collection = rankedBinder({ DROP_SHINY }, 1, function(text) lines[#lines + 1] = text end)
    equal(collection:roll(guid(589, "p1"), "loot"), true)
    lines = {}
    equal(collection:roll(guid(589, "p2"), "loot"), nil)
    equal(collection:roll(guid(589, "p3"), "loot"), nil)
    equal(#lines, 1) -- told once, not on every kill
    assert(lines[1]:find("Ranked rolls are paused"), lines[1])
    equal(saved.counts["npc:589"], 1)
    equal(saved.attempts["npc:589"], 1) -- nothing was counted for the paused kills
    equal(#saved.ledger, 2) -- the switch into Ranked and the one drop
    -- A refill that starts where the old tape ended (the server sends the unused entries and new ones).
    ACB.sync.tape = { start = 2, entries = { DROP_PLAIN, DROP_PLAIN } }
    equal(collection:roll(guid(589, "p2"), "loot"), true) -- the same kill can still be rolled
    equal(saved.ledger[3].tape, 2)
    equal(ledger:verify(), true)
    -- A tape that starts after the next position, or is damaged, is not used.
    ACB.sync.tape = { start = 9, entries = { DROP_PLAIN } }
    equal(ACB.takeTape(saved), nil)
    ACB.sync.tape = { start = 1, entries = { "short", 5, "ZZZZZZZZZZZZZZZZ" } }
    equal(ACB.takeTape(saved), nil)
    ACB.sync.tape = nil
    equal(ACB.takeTape(saved), nil)
    equal(ACB.tapeLeft(saved), 0)
end)

test("Ranked stacks the chance after misses: a roll that lost at 1% wins once four misses have built it to 5%", function()
    local roll = "000001f300000001" -- a roll of 500
    local saved, ledger, collection = rankedBinder({ roll, roll, roll, roll, roll })
    for attempt = 1, 4 do equal(collection:roll(guid(589, "s" .. attempt), "loot"), false) end -- 1%, 2%, 3%, 4%
    equal(saved.misses["npc:589"], 4)
    equal(collection:roll(guid(589, "s5"), "loot"), true) -- 5% reaches the roll of 500
    equal(saved.ledger[#saved.ledger].tape, 5)
    equal(saved.ledger[#saved.ledger - 1].kind, "miss") -- the four misses are one run, using entries 1 to 4
    equal(saved.ledger[#saved.ledger - 1].count, 4)
    equal(saved.ledger[#saved.ledger - 1].tape, 4)
    equal(saved.misses["npc:589"], nil) -- and a drop starts the stack over
    equal(ledger:verify(), true)
end)

test("Ranked uses the card's listed rate and still honours the certain drop at the top of the stack", function()
    local saved, ledger, collection = rankedBinder({ "000001f300000001", "000001f300000001", "000001f300000001" })
    -- A roll of 500 beats a rare's 10% but not a normal card's 1%. The live creature's rank is ignored in Ranked.
    equal(ACB.tapeRoll("000001f300000001"), 500)
    equal(collection:roll(guid(589, "q1"), "loot", "rare"), false)
    saved.misses["npc:589"] = select(2, ACB.luck(saved, ACB.cards["npc:589"])) - 1
    equal(collection:roll(guid(589, "q2"), "loot"), true) -- the guarantee, using entry 2
    equal(saved.ledger[#saved.ledger].tape, 2)
    equal(saved.tape.next, 3)
    equal(ledger:verify(), true)
end)

test("a switch to Ranked needs a verified binder with no unchecked history, and every switch is on record", function()
    local saved, ledger = {}, nil
    ledger = open(saved)
    equal(select(2, ACB.setMode(saved, ledger, "wizard")), "The mode is casual or ranked.")
    equal(ACB.setMode(saved, ledger, "casual"), true) -- already casual: nothing to record
    equal(#saved.ledger, 0)
    equal(ACB.setMode(saved, ledger, "ranked"), true)
    equal(ACB.setMode(saved, ledger, "ranked"), true)
    equal(ACB.setMode(saved, ledger, "casual"), true)
    equal(#saved.ledger, 2)
    equal(saved.ledger[2].key, "casual")
    equal(ledger:verify(), true)

    -- A binder with cards from before the ledger cannot be replayed by the server.
    local old = assert(loadfile("tests/fixtures/saved-v1.lua"))()
    local oldLedger = open(old)
    equal(old.legacy, true)
    local ok, why = ACB.setMode(old, oldLedger, "ranked")
    equal(ok, false)
    assert(why:find("fresh binder"), why)
    equal(old.mode, "casual")
    -- A brand new binder is not legacy, and a reload keeps the flag.
    equal(saved.legacy, nil)
    local again = copy(old)
    ACB.cleanSavedData(again)
    equal(again.legacy, true)

    -- A binder that fails its check cannot play Ranked.
    local tampered = {}
    local tamperedLedger, collection = open(tampered)
    collection:roll(guid(589, "t1"), "loot")
    tampered.counts["npc:589"] = 50
    local allowed, reason = ACB.setMode(tampered, tamperedLedger, "ranked")
    equal(allowed, false)
    assert(reason:find("unverified"), reason)
    equal(tampered.mode, "casual")
end)

test("misses on different cards are separate runs, and a change of mode writes the open run first", function()
    local saved, ledger, collection = rankedBinder({ MISS, MISS, MISS, MISS, DROP_PLAIN, MISS })
    collection:roll(guid(589, "m1"), "loot")
    collection:roll(guid(589, "m2"), "loot") -- the same card again: one run of two
    collection:roll(guid(590, "m3"), "loot") -- another card: the first run is written, a new one opens
    equal(#saved.ledger, 2)
    equal(saved.ledger[2].kind, "miss")
    equal(saved.ledger[2].count, 2)
    equal(saved.ledger[2].tape, 2)
    equal(saved.run.key, "npc:590")
    collection:roll(guid(589, "m4"), "loot") -- back to the first card: a new run, not a continuation
    equal(saved.ledger[3].key, "npc:590")
    equal(saved.ledger[3].count, 1)
    equal(saved.ledger[3].tape, 3)
    equal(saved.run.last, 4)
    -- Leaving Ranked writes the open run before the mode event, and coming back names where the tape stands.
    assert(ACB.setMode(saved, ledger, "casual"))
    equal(saved.run, nil)
    equal(saved.ledger[4].kind, "miss")
    equal(saved.ledger[5].kind, "mode")
    equal(saved.ledger[5].key, "casual")
    saved.misses = { ["npc:589"] = 7 }
    assert(ACB.setMode(saved, ledger, "ranked"))
    equal(saved.ledger[6].key, "ranked2")
    equal(saved.ledger[6].tape, 4)
    equal(next(saved.misses), nil) -- every card starts its run of misses again
    equal(ledger:verify(), true)
end)

test("a binder that was already Ranked when it loaded starts writing attempts down, once", function()
    local saved = { mode = "ranked", tape = { next = 31 } }
    local _, upgraded = ACB.cleanSavedData(saved)
    local ledger = newLedger(saved)
    ledger:begin(upgraded)
    assert(ledger:check())
    saved.mode, saved.misses = "ranked", { ["npc:589"] = 3 }
    ACB.resumeRanked(saved, ledger)
    equal(saved.ledger[#saved.ledger].key, "ranked2")
    equal(saved.ledger[#saved.ledger].tape, 30)
    equal(saved.exactMode, true)
    equal(next(saved.misses), nil)
    local length = #saved.ledger
    ACB.resumeRanked(saved, ledger) -- already done: nothing more is written
    equal(#saved.ledger, length)
    -- Casual binders are left alone.
    local casual = {}
    ACB.cleanSavedData(casual)
    local casualLedger = newLedger(casual)
    casualLedger:begin(false)
    ACB.resumeRanked(casual, casualLedger)
    equal(#casual.ledger, 0)
end)

test("the open run in the saved file is kept when it is sound and dropped when it is not", function()
    local good = ACB.cleanSavedData({ run = { key = "npc:589", n = 3, last = 9 }, exactMode = true })
    equal(good.run.n, 3)
    equal(good.exactMode, true)
    for _, run in ipairs({ "x", { key = "npc:589", n = 0, last = 4 }, { key = "npc:589", n = 5, last = 4 }, { key = "npc:0", n = 1, last = 1 },
        { key = "npc:589", n = 1.5, last = 3 } }) do
        equal(ACB.cleanSavedData({ run = run }).run, nil)
    end
    equal(ACB.cleanSavedData({ exactMode = "yes" }).exactMode, nil)
end)

test("the tape position is cleaned: a damaged one starts again from 1", function()
    equal(ACB.cleanSavedData({ tape = { next = -5 } }).tape.next, 1)
    equal(ACB.cleanSavedData({ tape = { next = 2.5 } }).tape.next, 1)
    equal(ACB.cleanSavedData({ tape = "x" }).tape.next, 1)
    equal(ACB.cleanSavedData({ tape = { next = 42 } }).tape.next, 42)
end)

test("/acb mode reports the mode and the tape, refuses a bad mode, and the Settings tab offers the switch", function()
    ACB.sync.tape = nil -- earlier tests leave a tape behind
    local lines, realPrint = {}, print
    print = function(text) lines[#lines + 1] = text end
    SlashCmdList.AZEROTHCARDBINDER("mode")
    SlashCmdList.AZEROTHCARDBINDER("mode wizard")
    print = realPrint
    local joined = table.concat(lines, "\n")
    assert(joined:find("Mode: casual%. Roll tape entries left: 0"), joined)
    assert(joined:find("The mode is casual or ranked"), joined)
    ACB.open("settings")
    local found
    for _, widget in ipairs(widgets) do
        if widget.text == "Switch to Ranked" then found = widget end
    end
    assert(found, "the Settings tab has no mode button")
    -- A Ranked binder whose tape has run out says so on the Settings status line.
    local saved = {}
    local ledger = open(saved)
    ACB.sync.tape = { start = 1, entries = { DROP_PLAIN } }
    assert(ACB.setMode(saved, ledger, "ranked"))
    assert(not ledger:status():find("tape has run out"), ledger:status())
    ACB.takeTape(saved)
    assert(ledger:status():find("The roll tape has run out"), ledger:status())
    ACB.sync.tape = nil
end)
