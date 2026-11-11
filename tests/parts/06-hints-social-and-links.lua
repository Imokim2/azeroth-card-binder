test("tooltip hints say whether a card is owned and where to find it", function()
    local saved = AzerothCardBinderDB
    local card = ACB.cards["npc:589"]
    saved.counts["npc:589"], saved.misses["npc:589"] = nil, 120
    local lines = ACB.hintLines(saved, card)
    equal(lines[1][1], "Card: not in your binder yet (1% chance)")
    equal(lines[2][1], "Next attempt guaranteed")
    saved.counts["npc:589"] = 2
    equal(ACB.hintLines(saved, card)[1][1], "Card: in your binder (x2)")
    saved.counts["npc:589"], saved.misses["npc:589"] = nil, nil
    equal(ACB.whereToFind(card), "Defeat it in Westfall.")
    equal(ACB.whereToFind(ACB.cards["npc:639"]), "Defeat this boss in the Deadmines in Westfall.")
    equal(ACB.whereToFind(ACB.cards["node:1731"]), "Gather it in Elwynn Forest and other starting zones.")

    local added = {}
    local tip = { AddLine = function(_, text) added[#added + 1] = text end, Show = ignore }
    hintCallbacks[1](tip, { guid = guid(589, "tip") })
    equal(added[1], "Card: not in your binder yet (1% chance)")
    added = {}
    hintCallbacks[1](tip, { guid = guid(99999, "unknown") })
    hintCallbacks[1](tip, { guid = secret })
    equal(#added, 0) -- unknown and unreadable sources add nothing
    saved.hints = false
    hintCallbacks[1](tip, { guid = guid(589, "tip") })
    equal(#added, 0)
    saved.hints = nil
end)

test("player tooltip titles come from solicited replies and an equipped title can be hidden", function()
    local originalTooltip, originalUnitGUID, originalUnitFullName = GameTooltip, UnitGUID, UnitFullName
    local saved = AzerothCardBinderDB
    local peerGUID, currentGUID = "Player-1-00000001", "Player-1-00000001"
    local messages, lines, refreshes = {}, {}, 0
    GameTooltip = {
        GetUnit = function() return "Bob", "mouseover" end,
        GetPrimaryTooltipData = function() return { guid = currentGUID } end,
        IsShown = function() return true end,
        AddLine = function(_, line) lines[#lines + 1] = line end,
        RefreshDataNextUpdate = function() refreshes = refreshes + 1 end,
    }
    UnitGUID = function(unit)
        if unit == "mouseover" then return currentGUID end
        return originalUnitGUID(unit)
    end
    UnitFullName = function(unit)
        if unit == "mouseover" then return "Bob", "Realm Name" end
        return originalUnitFullName(unit)
    end
    Enum.SendAddonMessageResult = { Success = 0 }
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, peer)
        equal(prefix, ACB.viewPrefix)
        equal(channel, "WHISPER")
        -- Forever addresses a whisper as "First Second", as its own whisper box shows it (/acb whisperform hyphen undoes that).
        equal(peer, AzerothCardBinderDB.whisperForm == "hyphen" and "bob-realmname" or "Bob Realmname")
        messages[#messages + 1] = message
        return 0
    end
    local function receive(message, sender)
        emit("CHAT_MSG_ADDON", ACB.viewPrefix, message, "WHISPER", sender or "Bob-RealmName")
    end
    local function hover()
        hintCallbacks[1](GameTooltip, { guid = peerGUID })
    end
    receive("T|Card Trader")
    hintCallbacks[1](GameTooltip, { guid = secret })
    hover()
    hover()
    equal(#messages, 1)
    equal(messages[1], "T?")
    equal(#lines, 0)
    receive("T||Hspoof|h", "Bob-RealmName")
    receive("T|Card Trader", "Mallory-RealmName")
    equal(refreshes, 0)
    receive("T|Card Trader")
    equal(refreshes, 1)
    hover()
    equal(lines[1], "Binder title: Card Trader")
    equal(#messages, 1)

    local start = clock
    clock = clock + 46
    hover()
    equal(messages[2], "T?")
    currentGUID = "Player-1-00000002"
    receive("T|Foil Hunter")
    equal(refreshes, 1)
    saved.titles["Card Trader"] = true
    ACB.selectTitle(saved, "Card Trader")
    receive("T?")
    equal(messages[3], "T|Card Trader")
    receive("T?")
    equal(#messages, 3)
    clock = clock + 6
    ACB.selectTitle(saved)
    receive("T?")
    equal(messages[4], "T|")

    GameTooltip, UnitGUID, UnitFullName = originalTooltip, originalUnitGUID, originalUnitFullName
    saved.titles["Card Trader"], saved.titleHidden = nil, nil
    Enum.SendAddonMessageResult, C_ChatInfo.SendAddonMessage, clock = nil, nil, start
end)

test("binder requests use the addon whisper result when the general chat flags are unavailable", function()
    local originalSend, originalFlag = C_ChatInfo.SendAddonMessage, C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    local originalCodes = Enum.SendAddonMessageResult
    local result, sends = 0, 0
    Enum.SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11, TargetOffline = 12 }
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return secret end
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, peer)
        equal(prefix, ACB.viewPrefix)
        equal(message, "Q")
        equal(channel, "WHISPER")
        equal(peer, AzerothCardBinderDB.whisperForm == "hyphen" and "carol-realmname" or "Carol Realmname")
        sends = sends + 1
        return result
    end
    equal(ACB.requestBinder("carol-realmname"), true)
    result = 11
    local sent, reason = ACB.requestBinder("carol-realmname")
    equal(sent, false)
    equal(reason, "Forever is blocking addon whispers right now.")
    equal(sends, 2)
    C_ChatInfo.SendAddonMessage, C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = originalSend, originalFlag
    Enum.SendAddonMessageResult = originalCodes
end)

test("card links round-trip and unknown links are ignored", function()
    local saved = { counts = { ["npc:639"] = 1 }, shiny = { ["npc:639"] = true } }
    local link = ACB.cardLink(ACB.cards["npc:639"], true)
    assert(link:find("|Haddon:AzerothCardBinder:card:npc:639:1|h[Edwin VanCleef (Shiny)]|h", 1, true))
    local entry, shiny = ACB.parseCardLink("addon:AzerothCardBinder:card:npc:639:1")
    equal(entry.key, "npc:639")
    equal(shiny, true)
    equal(select(2, ACB.parseCardLink("addon:AzerothCardBinder:card:node:1731:0")), false)
    equal(ACB.parseCardLink("addon:AzerothCardBinder:card:npc:99999:0"), nil)
    equal(ACB.parseCardLink("addon:Other:card:npc:639:0"), nil)
    equal(ACB.parseCardLink("addon:AzerothCardBinder:card:npc:639:2"), nil)
    equal(ACB.parseCardLink(secret), nil)
    equal(ACB.findCard(saved, "edwin").key, "npc:639")
    equal(ACB.findCard(saved, "pillager"), nil) -- not owned
    equal(ACB.findCard(saved, ""), nil)
end)

test("shift-click drafts a link and the recipient opens the exact card with local counts", function()
    local saved = AzerothCardBinderDB
    local edwin = ACB.cards["npc:639"]
    ACB.openCard(edwin.key)
    local pocket, detail, stats
    for _, widget in ipairs(widgets) do
        if widget.text == edwin.name and widget.parent.OnClick then pocket = widget.parent end
        if widget.OnMouseUp and widget.OnMouseDown and widget.scale == 1.32 then detail = widget end
        if widget.text == "BASE DROP CHANCE" then stats = widget.parent end
    end
    assert(pocket and detail and stats)
    saved.counts[edwin.key], saved.shiny[edwin.key] = 1, true
    shiftDown = true
    pocket:OnClick()
    equal(draft, "[ACB:npc:639:1 Edwin VanCleef (Shiny)]")
    local sent = draft

    ACB.open("index")
    draft = "Look at "
    activeChat = { Insert = function(_, text) draft = draft .. text end, SetFocus = ignore }
    detail:OnMouseDown("LeftButton")
    detail:OnMouseUp("LeftButton")
    equal(draft, "Look at " .. sent)
    activeChat, shiftDown = nil, false

    local event = "CHAT_MSG_WHISPER"
    local filter = assert(chatFilters[event])
    equal(filter(nil, event, secret), nil)
    equal(filter(nil, event, "[ACB:npc:99999:1 Unknown]"), nil)
    local skip, rendered, sender = filter(nil, event, "Check " .. sent .. "!", "Bob")
    equal(skip, false)
    equal(rendered, "Check " .. ACB.cardLink(edwin, true) .. "!")
    equal(sender, "Bob")

    saved.counts[edwin.key], saved.shiny[edwin.key] = 3, nil
    ACB.open(2)
    AzerothCardBinderWindow:Hide()
    chatCallbacks.SetItemRef("item:1", "", "LeftButton")
    equal(AzerothCardBinderWindow:IsShown(), false)
    chatCallbacks.SetItemRef(rendered:match("|H(.-)|h"), rendered, "LeftButton")
    equal(AzerothCardBinderWindow:IsShown(), true)
    local found, counts = {}, {}
    for _, widget in ipairs(widgets) do
        found[widget.text or ""] = true
        if widget.parent == stats then counts[widget.text or ""] = true end
    end
    equal(found[("Page 2 of %d"):format(math.ceil(#ACB.pages[edwin.page].cards / 4))], true)
    equal(found["SELECTED CARD  /  DM 08"], true)
    equal(found["3 owned / 2 spare"], true)
    equal(counts["3"] and counts["2"], true)
    saved.counts[edwin.key] = nil
    ACB.openCard(ACB.pages[1].cards[1].key)
end)

test("a binder can be viewed read-only, only when asked for, and can be made private", function()
    local clock = 100
    local aSaved = { counts = {}, shiny = { ["npc:639"] = true } }
    for _, card in ipairs(ACB.pages[1].cards) do aSaved.counts[card.key] = 1 end
    aSaved.counts["npc:589"] = 3
    local messages = ACB.encodeBinder(aSaved)
    assert(#messages >= 2, "a full set needs more than one message")
    for _, message in ipairs(messages) do assert(#message <= 160, "message too long") end

    local timers, shown = {}, {}
    local function after(delay, action) timers[#timers + 1] = action end
    local sentToB, sentToA = {}, {}
    -- Bob asks Alice. Alice's add-on answers; Bob's add-on shows what arrives.
    local bobSend = function(peer, message) sentToA[#sentToA + 1] = message return true end
    local aliceSend = function(peer, message) sentToB[#sentToB + 1] = message return true end

    ACB.initSocial(aSaved, aliceSend, function() return clock end, after)
    ACB.receiveView("bob-realm", "Q")
    for _, run in ipairs(timers) do run() end
    equal(#sentToB, #messages + 1) -- the binder, then what this player is looking for
    assert(sentToB[#messages + 1]:find("^L|%d+|"), "the wanted list follows the binder")
    ACB.receiveView("bob-realm", "Q") -- asked again straight away
    equal(#timers, #messages + 1)
    clock = clock + 11
    aSaved.inspectable = false
    ACB.receiveView("carol-realm", "Q")
    equal(#timers, #messages + 1) -- private binders answer nobody
    aSaved.inspectable = nil

    -- Bob's side.
    local bSaved = { counts = {} }
    local reports = {}
    ACB.initSocial(bSaved, bobSend, function() return clock end, after, function(message) reports[#reports + 1] = message end)
    ACB.showInspect = function(peer, counts, shiny) shown[#shown + 1] = { peer = peer, counts = counts, shiny = shiny } end
    -- Alice told Bob to wait when he asked again, and told Carol her binder is private.
    equal(sentToB[#messages + 2], "N|wait")
    equal(sentToB[#messages + 3], "N|private")
    ACB.receiveView("alice-realm", sentToB[1]) -- nobody asked, so it is ignored
    equal(#shown, 0)
    equal(ACB.requestBinder("alice-realm"), true)
    equal(sentToA[#sentToA], "Q")
    ACB.receiveView("mallory-realm", sentToB[1])
    equal(#shown, 0) -- only the player asked answers
    equal(#sentToB, #messages + 3)
    ACB.receiveView("alice-realm", sentToB[1])
    ACB.receiveView("alice-realm", sentToB[1]) -- a repeated part changes nothing
    equal(#shown, 0)
    ACB.receiveView("alice-realm", sentToB[2] .. ",c99999=4") -- unknown cards are dropped
    equal(#shown, 1)
    equal(shown[1].peer, "alice-realm")
    equal(shown[1].counts["npc:589"], 3)
    equal(shown[1].shiny["npc:639"], true)
    equal(shown[1].counts["npc:99999"], nil)
    local lines = ACB.inspectLines(shown[1].counts, shown[1].shiny)
    local deadminesCards = #ACB.pages[1].cards
    assert(lines[1]:find(("^%d of %%d+ cards collected, 1 shiny$"):format(deadminesCards + 1)))
    local text = table.concat(lines, " ")
    assert(text:find(("Deadmines   %d / %d"):format(deadminesCards, deadminesCards), 1, true))
    assert(text:find("Westfall   1 / %d+"))
    -- Garbage is dropped.
    ACB.receiveView("alice-realm", "B|9/2|npc:589=2")
    ACB.receiveView("alice-realm", "B|1/2|<script>")
    ACB.receiveView("alice-realm", string.rep("x", 300))
    equal(#shown, 1)

    -- Being refused or ignored is explained to the player, not left silent.
    equal(ACB.requestBinder("alice-realm"), true)
    ACB.receiveView("alice-realm", "N|wait")
    assert(reports[#reports]:find("still on its way"), reports[#reports])
    ACB.receiveView("alice-realm", "N|private")
    assert(reports[#reports]:find("keeps their binder private"), reports[#reports])
    local spoken = #reports
    ACB.receiveView("alice-realm", "N|private") -- nothing was asked, so nothing is said
    equal(#reports, spoken)
    equal(ACB.requestBinder("dave-realm"), true)
    timers[#timers - 1]() -- the check for no answer at all
    assert(reports[#reports]:find("No answer from dave%-realm"), reports[#reports])
end)

test("binder parts go out at a pace the game accepts, and a part the game refuses is sent again", function()
    local full = { counts = {} }
    for key in pairs(ACB.cards) do full.counts[key] = 1 end
    local timers, delivered, refuse = {}, {}, 2
    ACB.initSocial(full, function(_, message)
        if refuse > 0 then refuse = refuse - 1 return false, "Too many addon whispers. Try again in a moment." end
        delivered[#delivered + 1] = message
        return true
    end, function() return 100 end, function(delay, action) timers[#timers + 1] = { delay = delay, run = action } end)
    ACB.receiveView("bob-realm", "Q")
    assert(#timers > 100)
    -- A quick start, then no faster than about one a second.
    equal(timers[1].delay, 0)
    assert(timers[8].delay < 3)
    for index = 9, #timers do assert(timers[index].delay - timers[index - 1].delay >= 1, "parts " .. index .. " are too close together") end
    -- The first part is refused twice; each time it is scheduled again, and the third try gets through.
    local first = timers[1]
    first.run()
    equal(#delivered, 0)
    equal(timers[#timers].delay, 1.3)
    timers[#timers].run()
    timers[#timers].run()
    equal(#delivered, 1)
    equal(delivered[1]:sub(1, 4), "B|1/")
end)

test("a fully collected binder fits the message limit and arrives within the request window", function()
    local full, timers = { counts = {}, shiny = {} }, {}
    for key in pairs(ACB.cards) do
        full.counts[key], full.shiny[key] = 99, true
    end
    local now, received, show
    now = 100
    ACB.initSocial(full, function(_, message)
        assert(#ACB.viewPrefix + 1 + #message <= 255, "addon whisper exceeds the message budget")
        received("alice-realm", message)
        return true
    end, function() return now end, function(delay, action)
        timers[#timers + 1] = { due = now + delay, run = action }
    end)
    local sendResponse = ACB.receiveView
    sendResponse("bob-realm", "Q")
    assert(#timers > 150)
    ACB.initSocial({ counts = {} }, function() return true end, function() return now end, ignore)
    received = ACB.receiveView
    ACB.showInspect = function(_, counts, shiny) show = { counts = counts, shiny = shiny } end
    assert(ACB.requestBinder("alice-realm"))
    for _, timer in ipairs(timers) do
        now = timer.due
        timer.run()
    end
    assert(show, "the last part arrived too late")
    for key in pairs(ACB.cards) do
        equal(show.counts[key], 99)
        equal(show.shiny[key], true)
    end
end)

test("player and enemy portrait menus offer the relevant binder actions", function()
    local callbacks = {}
    Menu = { ModifyMenu = function(tag, callback) callbacks[tag] = callback end }
    ACB.initSocial({ counts = {} }, function() return true end, function() return 1 end, function(_, action) action() end)
    Menu = nil
    local playerMenu = assert(callbacks.MENU_UNIT_PLAYER)
    local targetMenu = assert(callbacks.MENU_UNIT_TARGET)
    assert(callbacks.MENU_UNIT_FOCUS and callbacks.MENU_UNIT_BOSS)
    local buttons = {}
    local root = { CreateDivider = ignore, CreateButton = function(_, text, action) buttons[text] = action end }
    playerMenu(nil, root, { name = "Bob", server = "RealmName" })
    assert(buttons["Offer a card trade"] and buttons["View their binder"])
    AzerothCardBinderWindow:Hide()
    buttons["Offer a card trade"]()
    equal(AzerothCardBinderWindow:IsShown(), true)
    buttons = {}
    playerMenu(nil, root, { name = secret })
    playerMenu(nil, root, nil)
    equal(next(buttons), nil) -- unreadable or missing players get no entries
    target = secret
    targetMenu(nil, root, { unit = "target" })
    equal(next(buttons), nil)
    target = guid(639, "portrait")
    targetMenu(nil, root, { unit = "target" })
    assert(buttons["Open card in binder"])
    AzerothCardBinderWindow:Hide()
    buttons["Open card in binder"]()
    equal(AzerothCardBinderWindow:IsShown(), true)
    target = nil
    ACB.openCard(ACB.pages[1].cards[1].key)
end)
