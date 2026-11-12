-- Trading between players: finding cards by name, swap suggestions, asking for a card, and the trading distance.

-- The newest widget with this text (the add-on was started earlier in the run and made its own).
local function widgetNamed(value)
    for index = #widgets, 1, -1 do
        if widgets[index].text == value then return widgets[index] end
    end
    error("missing widget: " .. value)
end

test("any card can be found by part of its name, and an exact name wins", function()
    local card = ACB.cards["npc:589"]
    equal(ACB.findAnyCard(card.name), card)
    equal(ACB.findAnyCard("  " .. card.name:upper() .. "  "), card)
    equal(ACB.findAnyCard(card.name:sub(1, 6)).name:lower():find(card.name:sub(1, 6):lower(), 1, true) ~= nil, true)
    equal(ACB.findAnyCard(""), nil)
    equal(ACB.findAnyCard("no such creature anywhere"), nil)
    equal(ACB.findAnyCard(nil), nil)
    -- A card you do not own is found too: this is for asking someone else for it.
    equal(ACB.findAnyCard("Edwin VanCleef").key, "npc:639")
end)

test("swap suggestions: what they have spare that you lack, what you have spare that they lack, wanted cards first", function()
    local mine = { ["npc:589"] = 3, ["npc:590"] = 1, ["npc:598"] = 2 }
    local theirs = { ["npc:639"] = 2, ["npc:573"] = 4, ["npc:589"] = 1, ["npc:590"] = 5 }
    local theyHave, iHave = ACB.swapSuggestions(mine, theirs)
    -- They have spare 639, 573 (590 they have spare but so do you own one: not needed) and I lack them.
    local function has(list, key) for _, entry in ipairs(list) do if entry == key then return true end end return false end
    equal(has(theyHave, "npc:639"), true)
    equal(has(theyHave, "npc:573"), true)
    equal(has(theyHave, "npc:590"), false, "I already own it")
    equal(has(iHave, "npc:598"), true, "I have two and they have none")
    equal(has(iHave, "npc:589"), false, "they own it already")
    -- Cards on the wanted list come first.
    local first = ACB.swapSuggestions(mine, theirs, { ["npc:573"] = true })
    equal(first[1], "npc:573")
    -- The lines for the binder window, with and without your own cards.
    local plain = table.concat(ACB.inspectLines(theirs, {}), "\n")
    assert(not plain:find("spares"))
    local lines = ACB.inspectLines(theirs, {}, mine, { ["npc:573"] = true })
    local text = table.concat(lines, "\n")
    assert(text:find("They have spares you need: " .. ACB.cards["npc:573"].name, 1, true), text)
    assert(text:find("You have spares they need: " .. ACB.cards["npc:598"].name, 1, true), text)
    assert(table.concat(ACB.inspectLines({}, {}, {}), "\n"):find("They have no spares you need."))
    assert(table.concat(ACB.inspectLines({}, {}, {}), "\n"):find("You have no spares they need."))
    -- A long list is cut at twelve names.
    local many = {}
    for index, key in ipairs({ "npc:589", "npc:590", "npc:598", "npc:639", "npc:573", "npc:114" }) do many[key] = 2 end
    local big = {}
    for _, page in ipairs(ACB.pages) do
        for _, card in ipairs(page.cards) do
            if #big < 20 then big[card.key] = 2 end
        end
    end
    assert(table.concat(ACB.inspectLines(big, {}, {}), "\n"):find("%(%+%d+ more%)"))
end)

test("the binder window of another player has a button that starts a trade with them", function()
    local opened
    local real = ACB.prepareTrade
    ACB.prepareTrade = function(peer) opened = peer end
    ACB.initSocial({ counts = {}, wanted = {} }, function() return true end, function() return 1 end, ignore)
    ACB.showInspect("bob-realmname", { ["npc:589"] = 1 }, {})
    widgetNamed("Offer a trade"):OnClick()
    equal(opened, "bob-realmname")
    ACB.prepareTrade = real
end)

test("asking for a card: the sender is held to a pace, the receiver is only told if they have it, and only once in a while", function()
    local clock, sent, said = 100, {}, {}
    local mine = { counts = {}, shiny = {} }
    ACB.initSocial(mine, function(peer, message) sent[#sent + 1] = { peer, message } return true end, function() return clock end, ignore, function(text) said[#said + 1] = text end)
    local card, other = ACB.cards["npc:589"], ACB.cards["npc:639"]
    equal(ACB.askForCard("bob-realmname", card), true)
    equal(sent[1][2], "A|npc:589")
    assert(said[#said]:find("Asked bob%-realmname for"), said[#said])
    -- Straight away again: wait. The same card to the same player: not for half a minute. Another card later: fine.
    local ok, why = ACB.askForCard("bob-realmname", other)
    equal(ok, false)
    assert(why:find("Wait a moment"), why)
    clock = 104
    ok, why = ACB.askForCard("bob-realmname", card)
    equal(ok, false)
    assert(why:find("a moment ago"), why)
    equal(ACB.askForCard("bob-realmname", other), true)
    clock = 140
    equal(ACB.askForCard("bob-realmname", card), true)
    -- Missing pieces are explained.
    clock = 200
    ok, why = ACB.askForCard(nil, card)
    equal(ok, false)
    assert(why:find("Target a player"))
    ok, why = ACB.askForCard("bob-realmname", nil)
    assert(why:find("no card with that name"))
    -- A message that cannot be sent leaves no cooldown behind.
    ACB.initSocial(mine, function() return false, "Trading and sharing are available outdoors and out of combat." end, function() return clock end, ignore, ignore)
    ok, why = ACB.askForCard("carol-realmname", card)
    equal(ok, false)
    assert(why:find("outdoors"))

    -- The receiving side: an ask for a card they own is told, with the counts and how to reply.
    local heard = {}
    local theirs = { counts = { ["npc:589"] = 3 }, shiny = {} }
    ACB.initSocial(theirs, function() return true end, function() return clock end, ignore, function(text) heard[#heard + 1] = text end)
    ACB.receiveView("bob-realmname", "A|npc:589")
    equal(#heard, 1)
    assert(heard[1]:find("bob%-realmname is looking for"), heard[1])
    assert(heard[1]:find("You have 3 %(2 spare%)"), heard[1])
    assert(heard[1]:find("/acb trade bob%-realmname"), heard[1])
    assert(heard[1]:find("Haddon:AzerothCardBinder:card:npc:589", 1, true), "the card is a link you can click")
    -- Again straight away from the same player: ignored; later: heard.
    ACB.receiveView("bob-realmname", "A|npc:589")
    equal(#heard, 1)
    clock = clock + 11
    ACB.receiveView("bob-realmname", "A|npc:589")
    equal(#heard, 2)
    -- A card they do not own, an unknown card, a malformed ask and a private binder are all quietly ignored.
    clock = clock + 11
    ACB.receiveView("carol-realmname", "A|npc:639")
    ACB.receiveView("carol-realmname", "A|npc:99999")
    ACB.receiveView("carol-realmname", "A|<script>")
    ACB.receiveView("carol-realmname", "A|npc:589" .. string.rep("x", 300))
    equal(#heard, 2)
    theirs.inspectable = false
    ACB.receiveView("dave-realmname", "A|npc:589")
    equal(#heard, 2)
end)

test("/acb ask finds the card and the player, by name or from your target", function()
    local clock, sent = 100, {}
    ACB.initSocial({ counts = {}, shiny = {} }, function(peer, message) sent[#sent + 1] = peer .. " " .. message return true end, function() return clock end, ignore, ignore)
    local slash = SlashCmdList.AZEROTHCARDBINDER
    slash("ask Bob " .. ACB.cards["npc:589"].name)
    equal(sent[1], "bob-realmname A|npc:589")
    -- Part of the name is enough, and the card need not be one you own.
    clock = 200
    slash("ask Bob Edwin VanC")
    equal(sent[2], "bob-realmname A|npc:639")
    -- A card that does not exist sends nothing.
    clock = 300
    slash("ask Bob zzzz no such card")
    equal(#sent, 2)
    -- "target" means whoever you are targeting.
    local oldFull, oldPlayer = UnitFullName, UnitIsPlayer
    UnitIsPlayer = function() return true end
    UnitFullName = function(unit) if unit == "target" then return "Carol", "RealmName" end return "Alice", "Realm Name" end
    clock = 400
    slash("ask target " .. ACB.cards["npc:590"].name)
    equal(sent[3], "carol-realmname A|npc:590")
    UnitFullName, UnitIsPlayer = oldFull, oldPlayer
end)

test("the trading distance: the partner must be targeted and within about 11 yards, unless the setting is off", function()
    local saved = { tradeRange = true }
    local oldFull, oldPlayer, oldNear = UnitFullName, UnitIsPlayer, CheckInteractDistance
    local who, near = "Bob", true
    UnitIsPlayer = function() return true end
    UnitFullName = function(unit)
        if unit == "player" then return "Alice", "Realm Name" end
        if unit == who:lower() then return who, "RealmName" end
        if unit == "target" then return who, "RealmName" end
    end
    CheckInteractDistance = function(unit, index)
        equal(index, 2, "the trade distance")
        return near
    end
    local ok, why = ACB.tradeDistanceOk(saved, "bob-realmname")
    equal(ok, true)
    -- Too far.
    near = false
    ok, why = ACB.tradeDistanceOk(saved, "bob-realmname")
    equal(ok, false)
    assert(why:find("too far away"), why)
    near = true
    -- Someone else is targeted, or nobody is.
    who = "Carol"
    ok, why = ACB.tradeDistanceOk(saved, "bob-realmname")
    equal(ok, false)
    assert(why:find("Target your trade partner first"), why)
    UnitFullName = function(unit) if unit == "player" then return "Alice", "Realm Name" end end
    ok = ACB.tradeDistanceOk(saved, "bob-realmname")
    equal(ok, false)
    -- You cannot trade with yourself by targeting yourself.
    UnitFullName = function(unit) return "Alice", "Realm Name" end
    equal(ACB.targetPeer(), nil)
    -- A focused or hovered partner counts, and the setting turns the whole rule off.
    UnitFullName = function(unit)
        if unit == "player" then return "Alice", "Realm Name" end
        if unit == "focus" then return "Bob", "RealmName" end
    end
    equal(ACB.partnerUnit("bob-realmname"), "focus")
    equal((ACB.tradeDistanceOk(saved, "bob-realmname")), true)
    saved.tradeRange = false
    UnitFullName = function(unit) if unit == "player" then return "Alice", "Realm Name" end end
    equal(ACB.tradeDistanceOk(saved, "bob-realmname"), true)
    -- If the game cannot say how far away someone is, the trade is allowed rather than blocked for no reason.
    saved.tradeRange = true
    UnitFullName = function(unit) if unit == "player" then return "Alice", "Realm Name" end return "Bob", "RealmName" end
    CheckInteractDistance = nil
    equal(ACB.tradeDistanceOk(saved, "bob-realmname"), true)
    UnitFullName, UnitIsPlayer, CheckInteractDistance = oldFull, oldPlayer, oldNear
end)

test("a trade asks the distance rule at every step and stops with the reason when it says no", function()
    local counts = { ["npc:589"] = 2, ["npc:590"] = 1 }
    local allow, reason, sent = true, "Your partner is too far away. Move within about 11 yards.", {}
    local trade = ACB.newTrade(counts, function() return 1 end, function() return "id-1" end, function(peer, message) sent[#sent + 1] = message return true end,
        function() return true end, nil, function(peer) return allow, (not allow) and reason or nil end)
    -- Offering: refused, nothing sent, no session.
    allow = false
    trade:offer("bob-realm", "npc:589")
    equal(#sent, 0)
    equal(trade.session, nil)
    equal(trade.status, reason)
    -- Allowed: it goes ahead. The partner then offers a card and we reply and accept.
    allow = true
    trade:listen("bob-realm")
    trade:receive("bob-realm", "O|first-1|npc:639")
    allow = false
    trade:reply("npc:589")
    equal(trade.session.give, nil)
    equal(trade.status, reason)
    allow = true
    trade:reply("npc:589")
    equal(trade.session.give, "npc:589")
    allow = false
    trade:confirm()
    equal(trade.session.sentConfirm, nil)
    equal(trade.status, reason)
    allow = true
    trade:confirm()
    equal(trade.session.sentConfirm, true)
end)

test("another player's binder opens as the binder's own pages, filled with their cards and read-only", function()
    local saved = AzerothCardBinderDB
    -- The first card of a page is on its first leaf, which is where the view opens.
    ACB.initSocial(saved, function() return true end, function() return 1 end, ignore)
    local key = ACB.pages[ACB.cards["npc:639"].page].cards[1].key
    local keep = saved.counts[key]
    saved.counts[key] = 1
    local function newest(value)
        for index = #widgets, 1, -1 do
            if widgets[index].text == value then return widgets[index] end
        end
    end
    local function newestStarting(prefix)
        for index = #widgets, 1, -1 do
            if type(widgets[index].text) == "string" and widgets[index].text:sub(1, #prefix) == prefix then return widgets[index] end
        end
    end
    ACB.heardWanted = { ["bob-realmname"] = { cards = { "npc:589" } } }
    ACB.showInspect("bob-realmname", { [key] = 3 }, { [key] = true })
    assert(newest("Bob Realmname's Binder"), "the title is the player's name, as the game writes it")
    assert(newest("3 owned / 2 spare / Shiny"), "their cards fill the pockets of the page")
    assert(newestStarting("1 of "), "how many cards they have, and what could be swapped")
    assert(newestStarting("You own: "), "and how many of the selected card you own")
    -- Nothing here can change your own binder.
    equal(newest("Ask target").parent.shown, false)
    equal(newest("Add to wanted list") == nil or newest("Add to wanted list").parent.shown == false, true)
    equal(newest("Recycle a spare: +" .. ACB.dustFor(ACB.cards[key])) == nil
        or newest("Recycle a spare: +" .. ACB.dustFor(ACB.cards[key])).parent.shown == false, true)
    saved.counts[key] = keep
    ACB.heardWanted = nil
    ACB.refresh()
end)

test("on a card they are looking for, Trade starts the swap: you pick a card from their binder and the offer is sent", function()
    local saved = AzerothCardBinderDB
    local keepCounts = { saved.counts["npc:589"], saved.tradeRange }
    saved.counts["npc:589"], saved.tradeRange = 2, false
    ACB.initSocial(saved, function() return true end, function() return 1 end, ignore)
    local theirKey = ACB.pages[ACB.cards["npc:639"].page].cards[1].key
    local wantedKey = theirKey == "npc:589" and "npc:590" or "npc:589"
    saved.counts[wantedKey] = saved.counts[wantedKey] or 1
    local function newest(value)
        for index = #widgets, 1, -1 do
            if widgets[index].text == value then return widgets[index] end
        end
    end
    local function newestStarting(prefix)
        for index = #widgets, 1, -1 do
            if type(widgets[index].text) == "string" and widgets[index].text:sub(1, #prefix) == prefix then return widgets[index] end
        end
    end
    local originalSend, originalCodes, sent = C_ChatInfo.SendAddonMessage, Enum.SendAddonMessageResult, {}
    Enum.SendAddonMessageResult = { Success = 0 }
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, peer)
        sent[#sent + 1] = { prefix = prefix, message = message, channel = channel, peer = peer }
        return 0
    end
    -- Bob has the first card of the page, and is looking for a card of mine.
    ACB.heardWanted = { ["bob-realmname"] = { cards = { wantedKey }, total = 1 } }
    ACB.showInspect("bob-realmname", { [theirKey] = 1 }, {})
    -- Nothing offers a trade from a card of his until one is picked from the Wanted tab.
    equal(newestStarting("Get this one for my ") == nil or newestStarting("Get this one for my ").parent.shown == false, true)
    newest("Wanted").OnClick(newest("Wanted"))
    assert(newest("Bob Realmname is looking for"), "the wanted list is titled with his name")
    local row = newestStarting(ACB.cards[wantedKey].name .. "    ")
    assert(row, "and names the card he is looking for")
    -- The Trade button on the row: you give that card, and his binder is shown to pick from.
    local trade
    for _, widget in ipairs(widgets) do
        if widget.text == "Trade" and widget.parent == row.parent and widget.OnClick then trade = widget end
    end
    assert(trade, "a Trade button sits on his wanted card")
    trade:OnClick()
    assert(newest("Cancel pick"), "the button now cancels the choice")
    local ask = newest("Get this one for my " .. ACB.cards[wantedKey].name)
    assert(ask and ask.parent.shown ~= false, "his selected card has a button that sends the offer")
    ask.parent:OnClick()
    local last = sent[#sent]
    assert(last, "an offer was sent")
    equal(last.prefix, ACB.tradePrefix)
    equal(last.channel, "WHISPER")
    equal(last.peer, "Bob Realmname")
    -- The trade opens on his side by itself, with the card you give (the card you picked is asked for in chat).
    assert(last.message:match("^I|[%w%-]+|" .. wantedKey .. "|t$"), last.message)
    -- Clean up: cancel the trade that is now open.
    for _, widget in ipairs(widgets) do
        if widget.text == "Cancel" and widget.OnClick then widget:OnClick() break end
    end
    C_ChatInfo.SendAddonMessage, Enum.SendAddonMessageResult = originalSend, originalCodes
    saved.counts["npc:589"], saved.tradeRange = keepCounts[1], keepCounts[2]
    ACB.heardWanted = nil
    ACB.refresh()
end)
