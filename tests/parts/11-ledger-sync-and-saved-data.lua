-- Tests for the ledger, the saved-data upgrade, attempt counters, roll memory and pruning (roadmap Phase A).

local vectors = assert(loadfile("packages/shared/vectors/vectors.lua"))()

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, inner in pairs(value) do result[key] = copy(inner) end
    return result
end

local function newLedger(saved)
    return ACB.newLedger(saved, function() return 1000 end, function() return "Alice-RealmName" end)
end

-- Open a binder the way the add-on does on login: clean the file, start the ledger, build the collection.
local function open(saved, random)
    local _, upgraded = ACB.cleanSavedData(saved)
    saved.editionDrops = false -- preserve the legacy histories here; editions have dedicated coverage
    saved.balancedDrops = false -- retain pre-chase history fixtures; balanced rolls have their own coverage
    local ledger = newLedger(saved)
    ledger:begin(upgraded)
    local collection = ACB.newCollection(saved, random or function(low) return low end, ignore, ignore, nil, nil, ledger)
    return ledger, collection, upgraded
end

test("the Lua ledger code gives exactly the results in the shared test vectors", function()
    for _, side in ipairs({ vectors.gifts.giver, vectors.gifts.recipient }) do
        local valid, head = ACB.checkChain(side.events)
        equal(valid, true)
        equal(head.hash, side.head.hash)
    end
    for _, case in ipairs(vectors.sha256) do equal(ACB.sha256(case.input), case.hex) end
    local valid = vectors.valid
    for index, event in ipairs(valid.events) do
        equal(ACB.eventText(event), valid.texts[index])
        equal(ACB.eventProblem(event), nil)
    end
    local ok, head = ACB.checkChain(valid.events)
    equal(ok, true)
    equal(head.seq, valid.head.seq)
    equal(head.hash, valid.head.hash)
    for _, case in ipairs(vectors.invalid) do
        local good, errorName, index = ACB.checkChain(case.events, case.head)
        assert(good == false and errorName == case.error and index == case.index + 1,
            ("%s: expected %s at %d, got %s at %s"):format(case.name, case.error, case.index + 1,
                tostring(errorName), tostring(index)))
    end
end)

test("every drop, craft, recycle, trade and finished set is written to a chain that verifies", function()
    local saved = {}
    local ledger, collection = open(saved)
    equal(ledger:verify(), true)
    equal(saved.mode, "casual")

    -- Two finds of the same card: the first is shiny (the test's random numbers are always 1), the second is not.
    equal(collection:roll(guid(639, "a"), "loot"), true)
    equal(collection:roll(guid(639, "b"), "loot"), true)
    -- Enough spare commons to recycle into the dust a craft costs.
    local yield = ACB.dustFor(ACB.cards["npc:589"])
    local _, cost = ACB.dustFor(ACB.cards["npc:590"])
    local needed = math.ceil(cost / yield)
    for number = 1, needed + 2 do collection:roll(guid(589, "c" .. number), "loot") end
    for _ = 1, needed do assert(collection:recycle("npc:589")) end
    assert(collection:craft("npc:590"))
    assert(collection:swap("npc:589", "npc:573", "bob-realmname", "111-482910-1"))
    -- Finish the smallest all-creature set to get a "set" event.
    local smallest
    for _, page in ipairs(ACB.pages) do
        local plain = page.code ~= nil
        for _, card in ipairs(page.cards) do plain = plain and card.key:match("^npc:") ~= nil end
        if plain and (not smallest or #page.cards < #smallest.cards) then smallest = page end
    end
    for _, card in ipairs(smallest.cards) do
        if (saved.counts[card.key] or 0) == 0 then
            equal(collection:roll(guid(tonumber(card.key:match("%d+")), "set"), "loot"), true)
        end
    end

    local events = saved.ledger
    local kinds = {}
    for _, event in ipairs(events) do kinds[event.kind] = (kinds[event.kind] or 0) + 1 end
    for _, kind in ipairs({ "drop", "craft", "recycle", "tradeIn", "tradeOut", "set" }) do
        assert(kinds[kind], "no " .. kind .. " event was written")
    end
    equal(events[1].kind, "drop")
    equal(events[1].shiny, 1)
    equal(events[2].shiny, 0)
    equal(events[2].count, 2)
    equal(events[#events].kind, "set")
    equal(events[#events].key, smallest.code)
    local trades = {}
    for _, event in ipairs(events) do
        if event.kind == "craft" then equal(event.dust, -cost) end
        if event.kind == "recycle" then equal(event.dust, yield) end
        if event.kind == "tradeOut" or event.kind == "tradeIn" then trades[#trades + 1] = event end
        equal(event.char, "Alice-RealmName")
    end
    equal(#trades, 2)
    equal(trades[1].kind, "tradeOut")
    equal(trades[1].partner, "bob-realmname")
    equal(trades[1].trade, "111-482910-1")
    equal(trades[2].kind, "tradeIn")
    equal(trades[2].trade, "111-482910-1")
    -- The chain is valid under the shared checker, the head points at the last event, and the binder verifies.
    local ok, head = ACB.checkChain(events)
    equal(ok, true)
    equal(saved.head.seq, #events)
    equal(saved.head.hash, head.hash)
    equal(ledger:verify(), true)
    -- A reload starts from the same state and still verifies.
    equal(newLedger(copy(saved)):verify(), true)
end)

test("editing a count, an event or the history by hand marks the binder unverified and drops it to Casual", function()
    local saved = {}
    local _, collection = open(saved)
    for number = 1, 4 do collection:roll(guid(589, "t" .. number), "loot") end
    collection:recycle("npc:589")
    local function attempt(change)
        local edited = copy(saved)
        edited.mode = "ranked"
        change(edited)
        local ok, reason = newLedger(edited):check()
        equal(ok, false)
        equal(edited.mode, "casual")
        return reason
    end
    assert(attempt(function(edited) edited.counts["npc:589"] = 99 end):find("do not match"))
    assert(attempt(function(edited) edited.counts["npc:639"] = 1 end):find("do not match"))
    assert(attempt(function(edited) edited.dust = edited.dust + 50 end):find("do not match"))
    assert(attempt(function(edited) edited.ledger[2].count = 7 end):find("bad%-hash"))
    assert(attempt(function(edited) table.remove(edited.ledger, 2) end):find("gap"))
    assert(attempt(function(edited) table.remove(edited.ledger) end):find("does not match the saved head"))
    assert(attempt(function(edited) edited.stateSum = nil end):find("do not match"))
    assert(attempt(function(edited) edited.ledger[3].kind = "gift" end):find("bad%-field"))
    -- Untouched, the same file is fine and keeps its mode.
    local intact = copy(saved)
    intact.mode = "ranked"
    equal(newLedger(intact):check(), true)
    equal(intact.mode, "ranked")
end)

test("a version 1 saved file upgrades without losing anything, starts a verified ledger and loads again", function()
    local saved = assert(loadfile("tests/fixtures/saved-v1.lua"))()
    local original = copy(saved)
    local ledger, collection, upgraded = open(saved)
    equal(upgraded, true)
    equal(saved.schema, 2)
    for key, count in pairs(original.counts) do equal(saved.counts[key], count) end
    equal(saved.dust, 7)
    equal(saved.misses["npc:1763"], 12)
    equal(saved.shiny["npc:639"], true)
    equal(saved.tradeCount, 3)
    equal(saved.history[1].peer, "bob-realmname")
    equal(saved.title, "Defias Bane")
    equal(saved.popups, false)
    equal(saved.mode, "casual")
    equal(saved.head.seq, 0)
    equal(next(saved.attempts), nil)
    equal(ledger:verify(), true)
    -- Playing on continues the chain from the upgraded binder.
    equal(collection:roll(guid(589, "after"), "loot"), true)
    equal(saved.counts["npc:589"], 5)
    equal(saved.ledger[1].count, 5)
    equal(ledger:verify(), true)
    -- Loading the upgraded file again changes nothing and is not an upgrade.
    local again = copy(saved)
    local _, reopened = ACB.cleanSavedData(again)
    equal(reopened, false)
    equal(again.head.seq, 1)
    equal(newLedger(again):verify(), true)
    -- Editing the old binder after the upgrade is caught like any other edit.
    local edited = copy(saved)
    edited.counts["npc:573"] = 20
    equal(newLedger(edited):verify(), false)
    -- A binder with a history that lost its check value is not given a fresh one.
    local stripped = copy(saved)
    stripped.stateSum = nil
    local _, wasUpgraded = ACB.cleanSavedData(stripped)
    local strippedLedger = newLedger(stripped)
    strippedLedger:begin(wasUpgraded)
    equal(stripped.stateSum, nil)
    equal(strippedLedger:verify(), false)
end)

test("every attempt is counted apart from bad luck, and a reload cannot roll the same source again", function()
    local saved = {}
    local missing = function() return 10000 end
    local _, collection = open(saved, missing)
    local source = guid(589, "corpse")
    equal(collection:roll(source, "loot"), false)
    equal(saved.attempts["npc:589"], 1)
    equal(saved.misses["npc:589"], 1)
    equal(collection:roll(source, "loot"), nil) -- the same corpse in the same session
    equal(saved.attempts["npc:589"], 1)
    -- Reload: a new collection built from the saved file still knows that corpse.
    local reloaded = ACB.newCollection(saved, function(low) return low end, ignore, ignore)
    equal(reloaded:roll(source, "loot"), nil)
    equal(saved.attempts["npc:589"], 1)
    -- A new corpse rolls again, a win counts as an attempt too, and bad luck starts over.
    equal(reloaded:roll(guid(589, "second"), "loot"), true)
    equal(saved.attempts["npc:589"], 2)
    equal(saved.misses["npc:589"], nil)
    equal(saved.counts["npc:589"], 1)

    -- Only the newest sources are kept: the oldest one is forgotten once the memory is full.
    local keep = ACB.rolledMemory
    ACB.rolledMemory = 3
    local small = {}
    local _, rolling = open(small, missing)
    for number = 1, 4 do rolling:roll(guid(589, "n" .. number), "loot") end
    equal(#small.rolledGuids, 3)
    local later = ACB.newCollection(small, missing, ignore, ignore)
    equal(later.rolled[guid(589, "n1")], nil)
    equal(later.rolled[guid(589, "n2")], true)
    equal(later.rolled[guid(589, "n4")], true)
    ACB.rolledMemory = keep
end)

test("damaged ledger fields in the saved file are repaired or caught, never a crash", function()
    local saved = ACB.cleanSavedData({
        attempts = { ["npc:589"] = 3, ["npc:99999"] = 2, ["npc:590"] = -1, ["npc:573"] = "x" },
        rolledGuids = { "ok", 5, string.rep("x", 300), "fine" }, rolledNext = 99,
        mode = "wizard", ledger = "oops", head = { seq = -4, hash = "not a hash" }, stateSum = "zz",
    })
    equal(saved.attempts["npc:589"], 3)
    equal(saved.attempts["npc:99999"], nil)
    equal(saved.attempts["npc:590"], nil)
    equal(#saved.rolledGuids, 2)
    equal(saved.rolledNext, 3)
    equal(saved.mode, "casual")
    equal(type(saved.ledger), "table")
    equal(saved.head.seq, 0)
    equal(saved.head.hash, ACB.GENESIS)
    equal(saved.stateSum, nil)
    local again = ACB.cleanSavedData(saved)
    equal(#again.rolledGuids, 2)
end)

test("the Settings tab and /acb verify report whether the binder is verified", function()
    local original = ACB.ledger
    local saved = {}
    local ledger, collection = open(saved)
    collection:roll(guid(589, "status"), "loot")
    ACB.ledger = ledger
    local lines, realPrint = {}, print
    print = function(text) lines[#lines + 1] = text end
    SlashCmdList.AZEROTHCARDBINDER("verify")
    print = realPrint
    local joined = table.concat(lines, "\n")
    assert(joined:find("Binder verified: 1 changes on record"), joined)
    -- The counts line reads the add-on's own saved file (the one the slash command was set up with).
    assert(joined:find("Mode: %a+%. Cards owned: %d+%. Attempts counted: %d+"), joined)

    local function settingsLine()
        ACB.open("settings")
        for _, widget in ipairs(widgets) do
            if type(widget.text) == "string" and widget.text:find("^Binder ") and widget.text:find("/acb verify") then
                return widget.text
            end
        end
    end
    assert((settingsLine() or "none"):find("^Binder verified: 1 changes"), tostring(settingsLine()))
    saved.counts["npc:589"] = 50
    assert((settingsLine() or "none"):find("^Binder unverified: card counts or dust do not match the history"),
        tostring(settingsLine()))
    ACB.ledger = original
end)

test("events the server has stored are pruned, foreign or wrong acknowledgements are ignored, and the chain continues", function()
    local saved = {}
    local ledger, collection = open(saved)
    for number = 1, 6 do collection:roll(guid(589, "p" .. number), "loot") end
    local events = saved.ledger
    local third, sixth = events[3], events[6]
    equal(#events, 6)
    -- Not an ack for this binder: wrong hash, beyond the head, malformed.
    equal(ledger:prune({ { seq = 3, hash = string.rep("a", 32) }, { seq = 99, hash = sixth.h }, "junk", { seq = "x" } }), 0)
    equal(#saved.ledger, 6)
    equal(ledger:prune(nil), 0)
    -- An ack for another binder listed beside this one's is skipped; this one's is used.
    equal(ledger:prune({ { seq = 5, hash = string.rep("b", 32) }, { seq = 3, hash = third.h } }), 3)
    equal(#saved.ledger, 3)
    equal(saved.ledger[1].seq, 4)
    equal(ledger:verify(), true)
    equal(ledger:waiting(), 3)
    -- Pruning never touches the head, and new events carry on from it.
    equal(saved.head.seq, 6)
    collection:roll(guid(589, "after-prune"), "loot")
    equal(saved.ledger[#saved.ledger].seq, 7)
    equal(ledger:verify(), true)
    -- An ack that names the head itself clears everything.
    local headHash = saved.head.hash
    equal(ledger:prune({ { seq = 7, hash = headHash } }), 4)
    equal(#saved.ledger, 0)
    equal(ledger:verify(), true)
    collection:roll(guid(589, "empty"), "loot")
    equal(saved.ledger[1].seq, 8)
    equal(saved.ledger[1].prev, headHash)
    equal(ledger:verify(), true)
    -- Editing what is left is still caught after pruning.
    local edited = copy(saved)
    edited.ledger[1].count = 40
    equal(newLedger(edited):verify(), false)
end)

test("a Ranked binder with too many events waiting for the app is told so", function()
    local keep = ACB.backlogLimit
    ACB.backlogLimit = 4 -- the switch to Ranked is the first event, then two drops, then the third drop fills it
    local saved = {}
    local ledger, collection = open(saved)
    ACB.sync.tape = { start = 1, entries = { "0000000000000000", "0000000000000000", "0000000000000000" } }
    assert(ACB.setMode(saved, ledger, "ranked"))
    for number = 1, 2 do collection:roll(guid(589, "w" .. number), "loot") end
    equal(ledger:backlogFull(), false)
    assert(not ledger:status():find("paused"))
    collection:roll(guid(589, "w3"), "loot")
    equal(ledger:backlogFull(), true)
    assert(ledger:status():find("Ranked rolls are paused until the companion app syncs"), ledger:status())
    saved.mode = "casual"
    assert(not ledger:status():find("paused"))
    ACB.sync.syncedAt = 1700000000
    date = function() return "14 Nov 22:13" end -- the game provides date()
    assert(ledger:status():find("Last synced 14 Nov 22:13"), ledger:status())
    date, ACB.sync.syncedAt, ACB.sync.tape = nil, nil, nil
    ACB.backlogLimit = keep
end)
