-- Card packs: found on one attempt in 500, five cards from the zone, decided by the tape in Ranked.

local ZONE = ACB.pages[ACB.cards["npc:589"].page].code
local function entryOf(roll, second) return ("%08x%08x"):format(roll - 1, second) end

local function packBinder(entries, report)
    local saved, ledger, collection = rankedBinder(entries, 1, report)
    collection.packsEnabled = true
    return saved, ledger, collection
end

test("the Lua pack functions give exactly the answers in the shared vectors", function()
    local packs = vectors.packs
    equal(ACB.packOdds, packs.odds)
    equal(ACB.packSize, packs.size)
    equal(ACB.shinyOdds, packs.shinyOdds)
    for _, case in ipairs(packs.cases) do
        equal(ACB.packValue(case.entry), case.packValue)
        equal(ACB.packValue(case.entry) == 1, case.found)
        for _, zone in ipairs(packs.zones) do
            equal(ACB.packPick(zone, case.entry), case.picks[zone])
        end
    end
    equal(ACB.packPick("NOPE", entryOf(1, 0)), nil)
end)

test("a pack is found on the attempt whose entry says so, whether or not the card drops, and the event follows that attempt", function()
    local lines = {}
    local saved, ledger, collection = packBinder({ entryOf(10000, 20), entryOf(10000, 0), entryOf(1, 40), entryOf(10000, 7) }, function(text) lines[#lines + 1] = text end)
    local found = {}
    collection.onPack = function(page, count) found[#found + 1] = { page.code, count } end
    equal(collection:roll(guid(589, "a1"), "loot"), false) -- a miss, no pack: the second half is 20
    equal(saved.packs[ZONE], nil)
    equal(collection:roll(guid(589, "a2"), "loot"), false) -- a miss that finds a pack: the second half is 0
    equal(saved.packs[ZONE], 1)
    -- Two misses in a row are one run that ends with the attempt that found the pack, then the pack.
    equal(saved.ledger[#saved.ledger - 1].kind, "miss")
    equal(saved.ledger[#saved.ledger - 1].count, 2)
    equal(saved.ledger[#saved.ledger - 1].tape, 2)
    equal(saved.ledger[#saved.ledger].kind, "packFind")
    equal(saved.ledger[#saved.ledger].key, ZONE)
    equal(saved.ledger[#saved.ledger].count, 1)
    equal(saved.ledger[#saved.ledger].tape, 2)
    equal(saved.run, nil)
    assert(table.concat(lines, "\n"):find("Card pack found"), table.concat(lines, "\n"))
    equal(found[1][1], ZONE)
    -- A drop that finds a pack writes the drop, then the pack.
    equal(collection:roll(guid(589, "a3"), "loot"), true) -- entry 3: roll 1 wins; the second half 40 is 2 mod 500... not a pack
    equal(saved.packs[ZONE], 1)
    equal(ledger:verify(), true)
end)

test("a drop that finds a pack writes the drop and then the pack", function()
    local saved, ledger, collection = packBinder({ entryOf(1, 0) })
    equal(collection:roll(guid(589, "d1"), "loot"), true)
    equal(saved.ledger[#saved.ledger - 1].kind, "drop")
    equal(saved.ledger[#saved.ledger - 1].tape, 1)
    equal(saved.ledger[#saved.ledger].kind, "packFind")
    equal(saved.ledger[#saved.ledger].tape, 1)
    equal(saved.packs[ZONE], 1)
    equal(ledger:verify(), true)
end)

test("opening a pack spends the next five tape entries, one card each, as the entries say", function()
    local picks = { entryOf(1, 0), entryOf(7000, 21), entryOf(7500, 40), entryOf(9999, 123456), entryOf(10000, 7) }
    local entries = { entryOf(10000, 0) }
    for _, entry in ipairs(picks) do entries[#entries + 1] = entry end
    local saved, ledger, collection = packBinder(entries)
    equal(collection:roll(guid(589, "o1"), "loot"), false) -- a miss that finds a pack
    local owned = {}
    for key, count in pairs(saved.counts) do owned[key] = count end
    local results, why = collection:openPack(ZONE)
    equal(why, nil)
    equal(#results, 5)
    equal(saved.packs[ZONE], nil, "the pack is used up")
    local base = #saved.ledger - 5
    equal(saved.ledger[base].kind, "packOpen")
    equal(saved.ledger[base].key, ZONE)
    equal(saved.ledger[base].count, 0)
    equal(saved.ledger[base].tape, 1, "names the last entry used before it")
    for index, entry in ipairs(picks) do
        local event = saved.ledger[base + index]
        equal(event.kind, "packCard")
        equal(event.key, ACB.packPick(ZONE, entry))
        equal(event.tape, 1 + index)
        equal(results[index].card.key, event.key)
        equal(event.count, (owned[event.key] or 0) + 1 + (function() local n = 0 for earlier = 1, index - 1 do if saved.ledger[base + earlier].key == event.key then n = n + 1 end end return n end)())
    end
    equal(saved.ledger[base + 1].shiny, 1, "the first copy of a card is shiny when its entry says so")
    equal(results[1].shiny, true)
    equal(saved.tape.next, 7)
    equal(saved.casualDrops, 0, "Ranked cards are checked by the server")
    equal(ledger:verify(), true)
    -- Nothing else may be written between a pack's cards; a set finished by them comes after the fifth.
    for index = base, base + 5 do assert(saved.ledger[index].kind == "packOpen" or saved.ledger[index].kind == "packCard", saved.ledger[index].kind) end
end)

test("a Ranked pack needs five entries on the tape, and nothing is spent when they are not there", function()
    local saved, ledger, collection = packBinder({ entryOf(10000, 0), entryOf(1, 0) })
    collection:roll(guid(589, "t1"), "loot")
    local before = #saved.ledger
    local results, why = collection:openPack(ZONE)
    equal(results, nil)
    assert(why:find("needs 5 roll tape entries"), why)
    equal(#saved.ledger, before)
    equal(saved.packs[ZONE], 1, "the pack is kept")
    equal(saved.tape.next, 2)
    equal(select(2, collection:openPack("NOPE")), "You have no pack for that zone.")
    equal(ledger:verify(), true)
end)

test("in Casual a pack uses the computer's random numbers, and its cards count as Casual drops", function()
    local saved = {}
    local ledger, collection = open(saved, function(low) return low end)
    collection.packsEnabled = true
    equal(collection:roll(guid(589, "c1"), "loot"), true) -- the stub always draws the lowest: a drop and a pack
    equal(saved.packs[ZONE], 1)
    equal(saved.ledger[#saved.ledger].kind, "packFind")
    equal(saved.ledger[#saved.ledger].tape, 0)
    local drops = saved.casualDrops
    local results = collection:openPack(ZONE)
    equal(#results, 5)
    equal(saved.casualDrops, drops + 5)
    for _, event in ipairs({ unpack(saved.ledger, #saved.ledger - 5) }) do equal(event.tape, 0) end
    equal(ledger:verify(), true)
end)

test("packs are off for a collection until they are enabled, and gathering nodes never find one", function()
    local saved, ledger, collection = rankedBinder({ entryOf(10000, 0) }, 1)
    equal(collection:roll(guid(589, "e1"), "loot"), false)
    equal(next(saved.packs or {}), nil)
    for _, event in ipairs(saved.ledger) do assert(event.kind ~= "packFind") end
    collection.packsEnabled = true
    local node = ACB.cards["node:1731"]
    equal(collection:packRoll(node, entryOf(10000, 0)), false)
    equal(collection:packRoll(ACB.cards["npc:589"], entryOf(10000, 0)), true)
    equal(collection:packRoll(ACB.cards["npc:589"], entryOf(10000, 20)), false)
    equal(ledger:verify(), true)
end)

test("saved packs are cleaned: only whole counts of known zones are kept, and the list is ordered most first", function()
    local saved = { packs = { [ZONE] = 2, ZZZZ = 1, DM = 0, AHX = 1.5, WF2 = "x", [7] = 1 } }
    ACB.cleanSavedData(saved)
    local keep = {}
    for zone, count in pairs(saved.packs) do keep[#keep + 1] = zone .. "=" .. count end
    equal(table.concat(keep), ZONE .. "=2")
    saved.packs = { [ZONE] = 1, DM = 3 }
    local list, total = ACB.packList(saved)
    equal(total, 4)
    equal(list[1].zone, "DM")
    equal(list[2].zone, ZONE)
end)
