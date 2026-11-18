do
    local CARD, OTHER = "npc:589", "npc:590"
    local function binder(older)
        local saved, ledger = modeBinder()
        if older then saved.counts[CARD] = older; ledger:record("tradeIn", CARD, { before = 0, partner = "Old Collector", trade = "old-copy" }) end
        ACB.enableCardHistory(saved)
        local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, ignore, ignore, ledger)
        return saved, ledger, collection
    end
    local function find(saved, collection, suffix)
        assert(collection:roll(guid(589, suffix or "history"), "loot"))
        return assert(ACB.selectedCardCopy(saved, CARD))
    end
    local function origin(fn)
        local name, place, fullName = ACB.characterName, ACB.currentPlaceName, UnitFullName
        ACB.characterName, ACB.currentPlaceName = function() return "filfred-whizzlebang" end, function() return "Westfall" end
        UnitFullName = function() return "Filfred", "Whizzlebang" end
        local ok, why = pcall(fn); ACB.characterName, ACB.currentPlaceName, UnitFullName = name, place, fullName
        if not ok then error(why) end
    end
    local function connect(a, ca, b, cb, give, take, gift, lose, strictBudget)
        local t, queue, sent = 0, {}, {}
        local lastSent = {}
        local restoreA, restoreB = rankedTradeFixture(a), rankedTradeFixture(b)
        local alice, bob
        local function transmit(from, to, message)
            assert(#message <= 250, "history packet exceeds the client's limit")
            if strictBudget and lastSent[from] and t - lastSent[from] < 1 then return false end
            lastSent[from] = t
            sent[#sent + 1] = { from = from, message = message }
            if not lose or not lose(from, message) then queue[#queue + 1] = { from = from, to = to, message = message } end
            return true
        end
        alice = ACB.newTrade(a.counts, function() return t end, function() return "copy-history-trade" end,
            function(_, message) return transmit("alice-smith", "bob-jones", message) end,
            function(out, into, peer, id, context) return ca:swap(out, into, peer, id, context) end, nil, function() return true end, a)
        bob = ACB.newTrade(b.counts, function() return t end, function() return "unused-history" end,
            function(_, message) return transmit("bob-jones", "alice-smith", message) end,
            function(out, into, peer, id, context) return cb:swap(out, into, peer, id, context) end, nil, function() return true end, b)
        local function flush()
            local limit = 0
            while #queue > 0 do
                limit = limit + 1; assert(limit < 200, "protocol echo loop")
                local item = table.remove(queue, 1)
                local receiver = item.to == "alice-smith" and alice or bob
                receiver:receive(item.from, item.message)
            end
        end
        local function step(count)
            for _ = 1, count or 12 do t = t + 1.1; alice:step(1.1); bob:step(1.1); flush() end
        end
        alice:start("bob-jones", give, gift); flush(); bob:join(); flush()
        if take then bob:change(take); flush() end
        return alice, bob, flush, step, sent, function() restoreB(); restoreA() end
    end

    test("new finds keep a distinct copy origin without inventing history for older stock", function()
        origin(function()
            local saved, ledger, collection = binder(2)
            equal(select(2, ACB.cardCopyCounts(saved, CARD)), 2)
            local first = find(saved, collection, "history-a")
            local second = find(saved, collection, "history-b")
            -- The default remains the first tracked copy; the second has its own identity.
            local newest = assert(ACB.cardCopyAt(saved, CARD, 2))
            assert(first.id ~= newest.id); equal(second.id, first.id)
            equal(first.finder, "Filfred Whizzlebang"); equal(first.place, "Westfall"); assert(first.at > 0)
            equal(saved.counts[CARD], 4); equal(select(2, ACB.cardCopyCounts(saved, CARD)), 2)
            equal(ACB.cardCopyAt(saved, CARD, 3).source, "unknown")
            local encoded = ACB.encodeCardCopy(first)
            equal(ACB.encodeCardCopy(assert(ACB.decodeCardCopy(encoded, CARD))), encoded)
            equal(ACB.decodeCardCopy(encoded, OTHER), nil)
            equal(ACB.decodeCardCopy(encoded:gsub("Filfred", "changed"), OTHER), nil)
            equal(ACB.decodeCardCopy("return loadstring('bad')()"), nil)
            first.finder = "|Hbad|h"; equal(ACB.encodeCardCopy(first), nil)
            first.finder = string.char(255); equal(ACB.encodeCardCopy(first), nil, "malformed UTF-8 cannot reach tooltips")
            ACB.enableCardHistory(saved); equal(saved.counts[CARD], 4); equal(ledger:check(), true)
        end)
    end)

    test("a gifted copy keeps its original finder through a second trade and reload", function()
        origin(function()
            local a, la, ca = binder(); local original = find(a, ca)
            local b, lb, cb = binder()
            local ta, tb, flush, step, _, restore = connect(a, ca, b, cb, CARD, nil, true)
            assert(not ta:canAccept() and not tb:canAccept(), "accepting must wait for copy data")
            step(); assert(ta:canAccept() and tb:canAccept())
            ta:confirm(); tb:confirm(); flush()
            equal(a.counts[CARD], nil); equal(b.counts[CARD], 1)
            local gifted = assert(ACB.selectedCardCopy(b, CARD))
            equal(gifted.id, original.id); equal(gifted.finder, original.finder); equal(gifted.place, original.place)
            equal(gifted.at, original.at); equal(gifted.how, "gift"); equal(gifted.hops, 1)
            restore()
            local c, lc, cc = binder()
            c.counts[OTHER] = 1; lc:record("tradeIn", OTHER, { before = 0, partner = "Earlier Owner", trade = "seed-second" })
            ta, tb, flush, step, _, restore = connect(b, cb, c, cc, CARD, OTHER, false)
            step(); ta:confirm(); tb:confirm(); flush(); restore()
            ACB.enableCardHistory(c)
            local traded = assert(ACB.selectedCardCopy(c, CARD))
            equal(traded.id, original.id); equal(traded.finder, original.finder); equal(traded.place, original.place)
            equal(traded.at, original.at); equal(traded.hops, 2); equal(traded.how, "trade")
            assert(la:check() and lb:check() and lc:check())
        end)
    end)

    test("copy exchange retries lost chunks and acknowledgements; cancellation moves nothing", function()
        origin(function()
            local a, _, ca = binder(); local original = find(a, ca)
            local b, _, cb = binder()
            local lostChunk, lostAck = false, false
            local ta, tb, flush, step, _, restore = connect(a, ca, b, cb, CARD, nil, true, function(_, message)
                if not lostChunk and message:sub(1, 2) == "J|" then lostChunk = true; return true end
                if not lostAck and message:sub(1, 2) == "Y|" then lostAck = true; return true end
            end)
            step(30); assert(lostChunk and lostAck and ta:canAccept() and tb:canAccept())
            ta:confirm(); assert(ACB.cardCopyReserved(a, CARD, original.id))
            equal(ACB.spendCardCopy(a, CARD), false)
            ta:cancel(); flush(); restore()
            equal(a.counts[CARD], 1); equal(b.counts[CARD], nil)
            equal(ACB.selectedCardCopy(a, CARD).id, original.id)
            assert(not ACB.cardCopyReserved(a, CARD, original.id))
        end)
    end)

    test("changing the offered card requires a fresh revision-bound history exchange", function()
        origin(function()
            local a, la, ca = binder(); find(a, ca)
            a.counts[OTHER] = 1; la:record("tradeIn", OTHER, { before = 0, partner = "Old Owner", trade = "old-other" })
            local b, _, cb = binder()
            local ta, tb, flush, step, packets, restore = connect(a, ca, b, cb, CARD, nil, true)
            step(); assert(ta:canAccept() and tb:canAccept())
            local oldAck
            for _, item in ipairs(packets) do if item.from == "bob-jones" and item.message:sub(1, 2) == "Y|" then oldAck = item.message end end
            assert(ta:change(OTHER)); flush(); assert(not ta:canAccept())
            ta:receive("bob-jones", oldAck); assert(not ta:canAccept(), "old acknowledgement cannot accept a changed offer")
            step(); assert(ta:canAccept() and tb:canAccept())
            equal(tb:active().copyHistory.into.key, OTHER)
            ta:confirm(); tb:confirm(); flush(); restore()
            equal(b.counts[OTHER], 1); equal(a.counts[CARD], 1)
            equal(ACB.selectedCardCopy(b, OTHER).source, "unknown", "legacy origins stay unknown after gifting")
        end)
    end)

    test("history inspection is requested one copy at a time and respects privacy and cancellation", function()
        origin(function()
            local saved, _, collection = binder(); local original = find(saved, collection)
            local tasks, outgoing, received = {}, {}, nil
            local reader, owner
            local now = 100
            local function after(_, fn) tasks[#tasks + 1] = fn end
            reader = ACB.newCardHistoryRequests({}, function(_, message) outgoing[#outgoing + 1] = message; return true end, function() return now end, after)
            owner = ACB.newCardHistoryRequests(saved, function(_, message) reader:handle("owner-smith", message); return true end, function() return now end, after)
            local ticket = assert(reader:request("owner-smith", CARD, 1, function(copy) received = copy end))
            owner:handle("reader-jones", table.remove(outgoing, 1))
            -- Timeout callback belongs to the reader; deliver response callbacks first.
            for index = 2, #tasks do tasks[index]() end
            equal(received.id, original.id); equal(received.finder, original.finder); equal(received.place, original.place)
            tasks[1](); equal(received.id, original.id)
            now, tasks, received, saved.inspectable = 103, {}, nil, false
            assert(reader:request("owner-smith", CARD, 1, function(_, _, why) received = why end))
            owner:handle("reader-jones", table.remove(outgoing, 1)); equal(received, "This binder is private.")
            received, saved.inspectable, tasks, now = nil, true, {}, 106
            ticket = assert(reader:request("owner-smith", CARD, 1, function(copy) received = copy end))
            reader:cancel(ticket); owner:handle("reader-jones", table.remove(outgoing, 1))
            for index = 2, #tasks do tasks[index]() end
            equal(received, nil)
        end)
    end)

    test("copy history UI selects a particular duplicate without changing quantities", function()
        origin(function()
            local saved, _, collection = binder(1); find(saved, collection, "ui-first"); find(saved, collection, "ui-second")
            local view = ACB.openCardHistory(saved, CARD)
            view.next.OnClick(); local second = view.copy
            view.choose.OnClick(); equal(ACB.selectedCardCopy(saved, CARD).id, second.id)
            equal(saved.counts[CARD], 3)
            view:load(3); view.choose.OnClick(); equal(saved.cardCopyChoice[CARD], "older")
            equal(ACB.selectedCardCopy(saved, CARD), nil); equal(saved.counts[CARD], 3)
            view:Hide()
        end)
    end)

    test("recycling keeps the remaining origins, and crafting records creation rather than a find", function()
        origin(function()
            local saved, ledger, collection = binder(11)
            for _ = 1, 10 do assert(collection:recycle(CARD)) end
            assert(collection:craft(OTHER))
            local crafted = assert(ACB.selectedCardCopy(saved, OTHER))
            equal(crafted.source, "crafted"); equal(crafted.finder, "Filfred Whizzlebang"); equal(crafted.place, "Westfall")
            find(saved, collection, "kept-after-recycle")
            local kept = ACB.selectedCardCopy(saved, CARD)
            assert(collection:recycle(CARD)); equal(ACB.selectedCardCopy(saved, CARD).id, kept.id)
            equal(saved.counts[CARD], 1); equal(ledger:check(), true)
        end)
    end)

    test("donation refunds restore the exact original copy", function()
        origin(function()
            local saved, _, collection = binder(); local original = find(saved, collection)
            local operation = ("d"):rep(32)
            ACB.donateCardCopy(saved, CARD, operation); saved.counts[CARD] = nil
            assert(saved.cardHistoryDonations[operation]); equal(ACB.selectedCardCopy(saved, CARD), nil)
            saved.counts[CARD] = 1; ACB.returnCardCopy(saved, operation)
            local restored = assert(ACB.selectedCardCopy(saved, CARD))
            equal(restored.id, original.id); equal(restored.finder, original.finder); equal(restored.place, original.place)
            equal(restored.at, original.at); equal(restored.how, "returned")
            equal(saved.cardHistoryDonations[operation], nil)
            ACB.returnCardCopy(saved, operation); equal(#saved.cardCopies[CARD], 1)
        end)
    end)

    test("history preparation recovers an offer update under a one-message-per-second limit", function()
        origin(function()
            local a, la, ca = binder(); find(a, ca)
            a.counts[OTHER] = 1; la:record("tradeIn", OTHER, { before = 0, partner = "Old Owner", trade = "old-budget" })
            local b, _, cb = binder()
            local ta, tb, flush, step, _, restore = connect(a, ca, b, cb, CARD, nil, true, nil, true)
            step(24); assert(ta:canAccept() and tb:canAccept(), "paced preparation stalled")
            assert(ta:change(OTHER)); flush(); step(30)
            assert(ta:canAccept() and tb:canAccept(), "a throttled revision update stalled")
            equal(tb:active().copyHistory.into.key, OTHER)
            ta:cancel(); flush(); restore()
        end)
    end)

    test("every card opened from a pack gets a distinct recorded origin", function()
        origin(function()
            local id = ACB.packID("WF", "rare")
            local saved = ACB.cleanSavedData({ packs = { [id] = 1 } })
            local ledger = newLedger(saved); ledger:begin(true); ACB.enableCardHistory(saved)
            local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, ignore, ignore, ledger)
            local result = assert(collection:openPack(id)); equal(#result, 3)
            local ids, total = {}, 0
            for key, copies in pairs(saved.cardCopies) do for _, code in ipairs(copies) do
                local copy = assert(ACB.decodeCardCopy(code, key)); assert(not ids[copy.id]); ids[copy.id] = true
                equal(copy.source, "pack"); equal(copy.finder, "Filfred Whizzlebang"); equal(copy.place, "Westfall")
                total = total + 1
            end end
            equal(total, 3); equal(ledger:check(), true)
        end)
    end)

    test("card-history trades require the companion's safe-recovery capability", function()
        local saved = binder(1); local restore = rankedTradeFixture(saved)
        ACB.sync.copyHistoryReady = nil
        assert(ACB.tradeModeReason(saved):find("1.0.7", 1, true))
        equal(saved.counts[CARD], 1)
        ACB.sync.copyHistoryReady = true; equal(ACB.tradeModeReason(saved), nil)
        restore()
    end)

    test("a changed fingerprint or foreign peer cannot replace an offered copy's origin", function()
        origin(function()
            local a, _, ca = binder(); local original = find(a, ca)
            local b, _, cb = binder()
            local ta, tb, flush, step, _, restore = connect(a, ca, b, cb, CARD, nil, true)
            step(); assert(ta:canAccept() and tb:canAccept())
            local s = tb:active()
            local attack = table.concat({ "H", s.id, s.theirRevision, s.revision, 1, ("0"):rep(12), 1 }, "|")
            tb:receive("stranger-jones", attack); assert(tb:canAccept())
            tb:receive("alice-smith", attack); assert(not tb:canAccept())
            tb:confirm(); flush(); equal(a.counts[CARD], 1); equal(b.counts[CARD], nil)
            equal(ACB.selectedCardCopy(a, CARD).id, original.id)
            ta:cancel(); flush(); restore()
        end)
    end)
end
