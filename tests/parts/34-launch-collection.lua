-- Cards held back for seasons (LaunchCollection.lua, Availability.lua): until a season releases one it is not rolled for, not found in
-- a pack, not crafted and not shown in a binder that does not own it; a page is finished by its launch cards; the ledger records the switch.

-- Run `check` with the list loaded (the other tests run with every card available), then put everything back as it was.
local function withLaunchCollection(check)
    assert(loadfile(addon .. "/LaunchCollection.lua"))(addon, ACB)
    local keepSync = ACB.sync
    local ok, problem = pcall(check)
    for _, page in ipairs(ACB.pages) do
        if page.all then
            for _, card in ipairs(page.all) do card.seasonal = nil end
            for position = #page.cards, 1, -1 do page.cards[position] = nil end
            for position, card in ipairs(page.all) do page.cards[position] = card end
        end
        page.all, page.required = nil, nil
    end
    ACB.seasonalCards, ACB.sync = nil, keepSync
    if not ok then error(problem, 0) end
end

-- A held-back creature card and a launch creature card, both with a catalog source, from a page that has both.
local function oneOfEach()
    for index, page in ipairs(ACB.pages) do
        local held, free
        for _, card in ipairs(page.all) do
            if card.id and ACB.sources.Creature[card.id] == card and not card.baseKey and not card.critter then
                if card.seasonal then held = held or card else free = free or card end
            end
        end
        if held and free then return held, free, index, page end
    end
end

test("a held-back card is not a source until a season has released it; launch cards always are", function()
    withLaunchCollection(function()
        local held, free = oneOfEach()
        assert(held and free)
        equal(ACB.cardAvailable(held), false)
        equal(ACB.cardAvailable(free), true)
        equal(ACB.source(guid(held.id, "before")), nil)
        equal(ACB.source(guid(free.id, "before")), free)
        ACB.sync = { seasonal = { released = { held.key } } }
        equal(ACB.cardAvailable(held), true)
        equal(ACB.source(guid(held.id, "after")), held)
        equal(ACB.source(guid(free.id, "after")), free)
        -- An unreadable list releases nothing.
        ACB.sync = { seasonal = { released = "everything" } }
        equal(ACB.cardAvailable(held), false)
    end)
end)

test("pages show launch cards, released cards and cards the binder owns; they are finished by the launch cards alone", function()
    withLaunchCollection(function()
        local held, free, index, page = oneOfEach()
        local total, extras = #page.required, #page.all - #page.required
        assert(extras > 0)
        local saved = { counts = {} }
        assert(ACB.refreshVisibleCards(saved) == true)
        equal(#page.cards, total, "only the launch cards are shown")
        equal(ACB.refreshVisibleCards(saved), false, "and nothing changes the second time")
        local owned, needed = ACB.progress({}, index)
        equal(owned, 0)
        equal(needed, total, "the page needs its launch cards, not the held-back ones")
        -- A copy the binder already owns stays on the page.
        saved.counts[held.key] = 1
        ACB.refreshVisibleCards(saved)
        equal(#page.cards, total + 1)
        local counts = {}
        for _, card in ipairs(page.required) do counts[card.key] = 1 end
        local done, wanted = ACB.progress(counts, index)
        equal(done, wanted)
        -- A release adds the card for everyone.
        saved.counts = {}
        ACB.sync = { seasonal = { released = { held.key } } }
        ACB.refreshVisibleCards(saved)
        equal(#page.cards, total + 1)
        equal(#page.all, total + extras, "page.all never changes")
    end)
end)

test("a pack leaves out held-back cards until they are released", function()
    withLaunchCollection(function()
        local held, _, _, page = oneOfEach()
        local sawHeld = false
        for draw = 1, 300 do
            local entry = ("%08x%08x"):format((draw * 2654435761) % 4294967296, (draw * 40503) % 4294967296)
            local key = ACB.packPick(page.code, entry, true, ACB.cardAvailable)
            assert(key and not ACB.cards[key].seasonal, "a held-back card came out of a pack")
            local unfiltered = ACB.packPick(page.code, entry, true)
            if ACB.cards[unfiltered].seasonal then sawHeld = true end
        end
        assert(sawHeld, "without the filter held-back cards do come out")
        ACB.sync = { seasonal = { released = { held.key } } }
        local nowFound = false
        for draw = 1, 600 do
            local entry = ("%08x%08x"):format((draw * 2654435761) % 4294967296, (draw * 40503) % 4294967296)
            if ACB.packPick(page.code, entry, true, ACB.cardAvailable) == held.key then nowFound = true end
        end
        assert(nowFound, "a released card can be found again")
    end)
end)

test("a held-back card cannot be crafted until it is released", function()
    withLaunchCollection(function()
        local held
        for _, page in ipairs(ACB.pages) do
            for _, card in ipairs(page.all) do
                if card.seasonal and not card.baseKey and card.dropProfile and not card.dropProfile.noCraft and not held then held = card end
            end
        end
        local saved = ACB.cleanSavedData({ dust = 100000 })
        local collection = ACB.newCollection(saved, math.random, ignore, ignore)
        equal(collection:craft(held.key), false)
        equal(saved.counts[held.key], nil)
        ACB.sync = { seasonal = { released = { held.key } } }
        equal(collection:craft(held.key), true)
        equal(saved.counts[held.key], 1)
    end)
end)

test("the launch collection is written to the ledger once, after the two drop generations", function()
    local records = {}
    local ledger = { flushRun = function() records[#records + 1] = "flush" end, record = function(_, kind, key) records[#records + 1] = kind .. ":" .. key end }
    local saved = ACB.cleanSavedData({})
    ACB.activateDropBalance(saved, ledger)
    equal(table.concat(records, " "), "flush mode:chase1 flush mode:chase2 flush mode:launch1")
    ACB.activateDropBalance(saved, ledger)
    equal(#records, 6, "and never again")
    equal(saved.launchLedger, true)
    -- A binder that already wrote the earlier markers writes only the new one.
    records = {}
    local older = ACB.cleanSavedData({ balanceLedger = true, balanceLedger2 = true })
    ACB.activateDropBalance(older, ledger)
    equal(table.concat(records, " "), "flush mode:launch1")
end)
