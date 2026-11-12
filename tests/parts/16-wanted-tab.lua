-- The Wanted tab and the wanted-list messages between players.

local function newestWidget(value)
    for index = #widgets, 1, -1 do
        if widgets[index].text == value then return widgets[index] end
    end
    error("missing widget: " .. value)
end

local function firstWith(prefix)
    for index = #widgets, 1, -1 do
        local text = widgets[index].text
        if type(text) == "string" and text:sub(1, #prefix) == prefix then return widgets[index] end
    end
    error("missing widget starting " .. prefix)
end

test("everyone whose wanted cards are known, most useful first, never yourself, never anything unusable", function()
    local saved = { counts = { ["npc:589"] = 3, ["npc:590"] = 1, ["npc:639"] = 2 }, shiny = {}, wanted = {} }
    local keepSync, keepHeard = ACB.sync, ACB.heardWanted
    ACB.heardWanted = { ["carol-realmname"] = { at = 1, cards = { "npc:639", "npc:99999" }, total = 2 } }
    ACB.sync = { syncVersion = 1, acks = {}, wanted = {
        { name = "Bob-Realm Name", characters = { "bob-realmname" }, cards = { "npc:573", "npc:590" } }, -- nothing of theirs I have spare
        { name = "Dave-Realm Name", characters = { "dave-realmname" }, cards = { "npc:589", "npc:639", "npc:573" } }, -- two spares
        { name = "Alice-Realm Name", characters = { "alice-realmname" }, cards = { "npc:589" } }, -- me
        { name = "Erin-Realm Name", characters = { "erin-realmname" }, cards = {} }, -- an empty list
        { name = "Fay-Realm Name", characters = { "fay-realmname" }, cards = { "npc:99999" } }, -- only cards that do not exist
        "not a row", { name = 5 }, { name = "Gus-Realm Name", characters = "x", cards = { "npc:573" } },
    } }
    local rows = ACB.wantedRows(saved)
    local names = {}
    for _, row in ipairs(rows) do names[#names + 1] = row.name end
    -- Dave has two cards I could give; Carol (asked just now) and Bob each have one or none; Alice is me and is left out.
    equal(names[1], "Dave-Realm Name")
    equal(#rows[1].spares, 2)
    assert(not table.concat(names, ","):find("Alice"))
    assert(not table.concat(names, ","):find("Erin"))
    assert(not table.concat(names, ","):find("Fay"))
    assert(not table.concat(names, ","):find("not a row"))
    local carol
    for _, row in ipairs(rows) do if row.name == "carol-realmname" then carol = row end end
    assert(carol, "a player asked directly is listed")
    equal(carol.direct, true)
    equal(#carol.cards, 1, "the card that does not exist is dropped")
    equal(carol.spares[1], "npc:639")
    -- The text marks the spares and cuts a long list.
    local text = ACB.wantedText(rows[1])
    assert(text:find(ACB.cards["npc:589"].name .. " (you have a spare)", 1, true), text)
    local long = { cards = {}, spares = {} }
    for _, page in ipairs(ACB.pages) do for _, card in ipairs(page.cards) do if #long.cards < 9 then long.cards[#long.cards + 1] = card.key end end end
    assert(ACB.wantedText(long):find("and 3 more"), ACB.wantedText(long))
    ACB.sync, ACB.heardWanted = keepSync, keepHeard
end)

test("asking a player what they are looking for: paced, answered only when allowed, and only the answer to your own question counts", function()
    local clock, sent, said, timers = 100, {}, {}, {}
    local function after(delay, action) timers[#timers + 1] = { delay = delay, run = action } end
    local mine = { counts = {}, shiny = {}, wanted = { ["npc:639"] = true, ["npc:573"] = true } }
    ACB.initSocial(mine, function(peer, message) sent[#sent + 1] = peer .. " " .. message return true end, function() return clock end, after, function(text) said[#said + 1] = text end)
    ACB.heardWanted = {}
    -- Asking.
    equal(ACB.requestWanted("bob-realmname"), true)
    equal(sent[1], "bob-realmname L?")
    local ok, why = ACB.requestWanted("bob-realmname")
    equal(ok, false)
    assert(why:find("a moment ago"), why)
    equal(ACB.requestWanted(nil), false)
    -- No answer: the player is told, once the wait is over.
    timers[#timers].run()
    assert(said[#said]:find("No answer from bob%-realmname"), said[#said])
    -- An answer that was never asked for is ignored; one to our question is kept, with the total.
    ACB.receiveView("carol-realmname", "L|1|c639")
    equal(ACB.heardWanted["carol-realmname"], nil)
    clock = 120
    equal(ACB.requestWanted("bob-realmname"), true)
    ACB.receiveView("bob-realmname", "L|3|c639,c573,o1731,c99999,<bad>")
    equal(ACB.heardWanted["bob-realmname"], nil, "a malformed answer is not taken")
    ACB.receiveView("bob-realmname", "L|3|c639,c573,o1731,c99999")
    local heard = ACB.heardWanted["bob-realmname"]
    equal(heard.total, 3)
    equal(#heard.cards, 3, "a card that does not exist is dropped")
    assert(said[#said]:find("bob%-realmname is looking for 3 cards"), said[#said])
    ACB.receiveView("bob-realmname", "L|1|c639") -- a second answer nobody asked for
    equal(#ACB.heardWanted["bob-realmname"].cards, 3)
    -- An empty answer says so.
    clock = 200
    ACB.requestWanted("erin-realmname")
    ACB.receiveView("erin-realmname", "L|0|")
    assert(said[#said]:find("is not looking for any card"), said[#said])

    -- The other side: someone asks what you are looking for. You answer, but not too often, and not if you keep your binder private.
    local outgoing = {}
    ACB.initSocial(mine, function(peer, message) outgoing[#outgoing + 1] = message return true end, function() return clock end, after, ignore)
    clock = 300
    ACB.receiveView("dave-realmname", "L?")
    equal(#outgoing, 1)
    assert(outgoing[1]:find("^L|2|"), outgoing[1])
    assert(outgoing[1]:find("c573", 1, true) and outgoing[1]:find("c639", 1, true))
    ACB.receiveView("dave-realmname", "L?")
    equal(#outgoing, 1, "not again straight away")
    clock = 306
    ACB.receiveView("dave-realmname", "L?")
    equal(#outgoing, 2)
    mine.inspectable = false
    clock = 400
    ACB.receiveView("dave-realmname", "L?")
    equal(#outgoing, 2, "a private binder does not answer")
    mine.inspectable = nil
    -- A long list is cut to 24 cards, with the true total.
    mine.wanted = {}
    local count = 0
    for _, page in ipairs(ACB.pages) do
        for _, card in ipairs(page.cards) do
            if count < 40 and (card.id or 0) > 0 then mine.wanted[card.key] = true count = count + 1 end
        end
    end
    clock = 500
    ACB.receiveView("dave-realmname", "L?")
    local last = outgoing[#outgoing]
    assert(last:find("^L|40|"), last)
    assert(#last <= 250, "fits one whisper")
end)

test("the binder view also takes the wanted list that follows the binder, and shows it with what you could give", function()
    local clock = 100
    local shown = {}
    local mine = { counts = { ["npc:589"] = 3, ["npc:639"] = 2 }, shiny = {}, wanted = {} }
    ACB.initSocial(mine, function() return true end, function() return clock end, ignore, ignore)
    ACB.heardWanted = {}
    ACB.requestBinder("bob-realmname")
    ACB.receiveView("bob-realmname", "L|2|c589,c573")
    local heard = ACB.heardWanted["bob-realmname"]
    equal(#heard.cards, 2)
    local text = table.concat(ACB.inspectLines({ ["npc:573"] = 2 }, {}, mine.counts, mine.wanted, heard.cards), "\n")
    assert(text:find("They are looking for: " .. ACB.cards["npc:589"].name, 1, true), text)
    assert(text:find("You have a spare of: " .. ACB.cards["npc:589"].name, 1, true), text)
    -- Nothing wanted: no such lines.
    assert(not table.concat(ACB.inspectLines({}, {}, mine.counts, mine.wanted, {}), "\n"):find("looking for"))
end)

test("the Wanted tab shows your list, adds and removes cards, shows what others want and starts a trade from a click", function()
    local saved = AzerothCardBinderDB
    local keep = { saved.wanted, saved.counts["npc:639"], saved.counts["npc:589"], ACB.sync, ACB.heardWanted, ACB.prepareTrade, saved.counts["npc:573"], ACB.requestWanted }
    saved.wanted, saved.counts["npc:639"], saved.counts["npc:589"], saved.counts["npc:573"] = { ["npc:573"] = true }, nil, 3, nil
    ACB.heardWanted = {}
    ACB.sync = { syncVersion = 1, acks = {}, wanted = {
        { name = "Dave-Realm Name", characters = { "dave-realmname" }, cards = { "npc:589", "npc:639" } },
    } }
    local traded
    ACB.prepareTrade = function(peer) traded = peer end
    ACB.open("wanted")
    -- Your own list, with how to remove a card.
    newestWidget(ACB.cards["npc:573"].name .. "   (click to remove)")
    -- Others: Dave wants a card you have spare, so the summary says so.
    newestWidget("1 player is looking for cards you have spare. Click a name to offer a trade.")
    local row = firstWith("Dave-Realm Name: ")
    assert(row.text:find("(you have a spare)", 1, true), row.text)
    row.parent:OnClick()
    equal(traded, "dave-realmname")
    -- Adding a card by name, and the messages when it cannot be added.
    local entry
    for index = #widgets, 1, -1 do
        if widgets[index].OnEnterPressed and widgets[index].template == "InputBoxTemplate" and widgets[index].width == 220 then entry = widgets[index] break end
    end
    assert(entry, "the add box")
    entry:SetText("Edwin VanCleef")
    entry:OnEnterPressed()
    equal(saved.wanted["npc:639"], true)
    newestWidget("Edwin VanCleef is on your list. Other players see it once the companion app has shared it.")
    entry:SetText("zzzz no such card")
    entry:OnEnterPressed()
    newestWidget("There is no card with that name.")
    entry:SetText(ACB.cards["npc:589"].name)
    entry:OnEnterPressed()
    newestWidget("You already have " .. ACB.cards["npc:589"].name .. ".")
    -- Removing a card: click it.
    local removable = newestWidget(ACB.cards["npc:573"].name .. "   (click to remove)")
    removable.OnClick(removable)
    equal(saved.wanted["npc:573"], nil)
    -- Check my target: asks the player you target.
    local asked
    ACB.requestWanted = function(peer) asked = peer return true end
    local oldFull, oldPlayer = UnitFullName, UnitIsPlayer
    UnitIsPlayer = function() return true end
    UnitFullName = function(unit) if unit == "target" then return "Carol", "RealmName" end return "Alice", "Realm Name" end
    newestWidget("Check my target"):OnClick()
    equal(asked, "carol-realmname")
    newestWidget("Asked carol-realmname what they are looking for. Their list appears here.")
    UnitFullName, UnitIsPlayer = oldFull, oldPlayer
    ACB.open("collection")
    saved.wanted, saved.counts["npc:639"], saved.counts["npc:589"], ACB.sync, ACB.heardWanted, ACB.prepareTrade, saved.counts["npc:573"], ACB.requestWanted = unpack(keep, 1, 8)
end)

test("Wanted hides every previous page before refreshing its content", function()
    for _, destination in ipairs({ "trade", "settings", "achievements", "ladder", "collection", "index" }) do
        ACB.open(destination)
        local previous = {}
        for _, widget in ipairs(widgets) do
            if widget.parent == AzerothCardBinderWindow and widget.shown == true then previous[#previous + 1] = widget end
        end
        assert(#previous > 0)
        ACB.open("wanted")
        for _, widget in ipairs(previous) do equal(widget.shown, false, destination .. " content must be hidden") end
    end
    ACB.open("collection")
end)
