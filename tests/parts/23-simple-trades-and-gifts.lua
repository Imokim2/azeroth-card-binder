local function peers(aCounts, bCounts)
    local a, b, serial = nil, nil, 0
    local wireLog, drops, calls = {}, {}, { 0, 0 }
    local function apply(counts, index)
        return function(give, take)
            if give and (counts[give] or 0) == 0 then return false end
            calls[index] = calls[index] + 1
            if give then counts[give] = counts[give] - 1 if counts[give] == 0 then counts[give] = nil end end
            if take then counts[take] = (counts[take] or 0) + 1 end
            return true
        end
    end
    local function id() serial = serial + 1 return "simple-" .. serial end
    local function deliver(target, peer, message)
        wireLog[#wireLog + 1] = message
        if not drops[message:sub(1, 1)] then
            if target:receive(peer, message) then target:join() end -- simulate accepting the invitation
        end
        return true
    end
    a = ACB.newTrade(aCounts, function() return 1 end, id,
        function(_, msg) return deliver(b, "alice-realm", msg) end, apply(aCounts, 1))
    b = ACB.newTrade(bCounts, function() return 1 end, id,
        function(_, msg) return deliver(a, "bob-realm", msg) end, apply(bCounts, 2))
    return a, b, wireLog, drops, calls
end

test("a gift needs both accepts and transfers the last exact edition once, with nothing in return", function()
    local edition = ACB.editions["npc:639"][1].key
    local mine, theirs = { [edition] = 1 }, {}
    local a, b, messages, _, calls = peers(mine, theirs)
    a:start("bob-realm", edition, true)
    equal(b.session.gift, true)
    equal(b.session.take, edition)
    equal(b.session.give, nil)
    equal(b:change("npc:589"), false, "a gift recipient cannot add an unexpected return card")
    b:confirm()
    equal(calls[1] + calls[2], 0)
    a:confirm()
    equal(mine[edition], nil)
    equal(theirs[edition], 1)
    equal(calls[1], 1)
    equal(calls[2], 1)
    local again = {}
    for _, message in ipairs(messages) do again[#again + 1] = message end
    for _, message in ipairs(again) do
        a:receive("bob-realm", message)
        b:receive("alice-realm", message)
    end
    a:step(3) b:step(3)
    equal(calls[1] + calls[2], 2, "retries and replays never create a second gift")
end)

test("changing an offer clears both accepts and rejects an acceptance from the old revision", function()
    local mine, theirs = { ["npc:589"] = 1 }, { ["npc:639"] = 1, ["npc:573"] = 1 }
    local a, b, messages, _, calls = peers(mine, theirs)
    a:start("bob-realm", "npc:589", false)
    b:change("npc:639")
    a:confirm()
    local oldAccept = messages[#messages]
    equal(a:change(nil), false, "an accepted offer is locked")
    b:change("npc:573")
    equal(a.session.sentConfirm, nil)
    equal(b.session.peerConfirmed, nil)
    b:receive("alice-realm", oldAccept)
    equal(b.session.peerConfirmed, nil)
    b:confirm()
    equal(calls[1] + calls[2], 0)
    a:confirm()
    equal(mine["npc:573"], 1)
    equal(theirs["npc:589"], 1)
    equal(theirs["npc:639"], 1)
end)

test("lost completion acknowledgements retry without duplicating cards, even after another session opens", function()
    local mine, theirs = { ["npc:589"] = 1 }, {}
    local a, b, _, drops, calls = peers(mine, theirs)
    a:start("bob-realm", "npc:589", true)
    drops.D = true
    a:confirm() b:confirm()
    equal(calls[1], 0)
    equal(calls[2], 1)
    a:step(3)
    equal(calls[2], 1)
    drops.D = nil
    -- The recipient is allowed to open another trade; late commits still get their old acknowledgement.
    b:start("carol-realm", nil, false)
    a:step(3)
    equal(calls[1], 1)
    equal(calls[2], 1)
end)

test("cancelling an accepted gift before the final decision moves no cards and ignores delayed accepts", function()
    local mine, theirs = { ["npc:589"] = 1 }, {}
    local a, b, messages, drops, calls = peers(mine, theirs)
    a:start("bob-realm", "npc:589", true)
    drops.A = true
    b:confirm()
    local delayed = messages[#messages]
    b:cancel()
    equal(a.session.cancelled, true)
    equal(b.session.cancelled, true)
    drops.A = nil
    a:receive("bob-realm", delayed)
    a:confirm() b:confirm()
    equal(calls[1] + calls[2], 0)
    equal(mine["npc:589"], 1)
    equal(theirs["npc:589"], nil)
end)

test("a cancellation arriving after both accepts honours the already agreed commit", function()
    local mine, theirs = { ["npc:589"] = 1 }, {}
    local a, b, _, drops, calls = peers(mine, theirs)
    a:start("bob-realm", "npc:589", true)
    drops.F = true
    a:confirm() b:confirm()
    equal(a.session.decision, "commit")
    equal(calls[1] + calls[2], 0)
    drops.F = nil
    b:cancel()
    equal(calls[1], 1)
    equal(calls[2], 1)
end)

test("empty exchanges, unowned cards, foreign peers and old revisions cannot move cards", function()
    local a, b, _, _, calls = peers({}, {})
    a:start("bob-realm", "npc:589", true)
    equal(a.session, nil)
    a:start("bob-realm", nil, false)
    equal(a:canAccept(), false)
    equal(b:canAccept(), false)
    a:receive("mallory-realm", "U|simple-1|99|npc:639")
    a:receive("bob-realm", "U|simple-1|0|npc:639")
    a:receive("bob-realm", "U|simple-1|999999|npc:639")
    equal(a.session.take, nil)
    a:confirm() b:confirm()
    equal(calls[1] + calls[2], 0)
end)

test("gift inventory events contain only the real transfer and gift history survives cleaning", function()
    local saved = ACB.cleanSavedData({ counts = { ["npc:589"] = 1 } })
    local ledger = ACB.newLedger(saved, function() return 100 end, function() return "Alice-Realm" end)
    ledger:begin(false)
    local collection = ACB.newCollection(saved, function() return 10000 end, ignore, ignore, nil, nil, ledger)
    local before = #saved.ledger
    assert(collection:swap("npc:589", nil, "bob-realm", "gift-ledger"))
    equal(#saved.ledger, before + 1)
    equal(saved.ledger[#saved.ledger].kind, "tradeOut")
    equal(saved.ledger[#saved.ledger].key, "npc:589")
    assert(collection:swap(nil, "npc:573", "bob-realm", "gift-received"))
    equal(saved.ledger[#saved.ledger].kind, "tradeIn")
    equal(saved.shiny["npc:573"], nil)
    ACB.logTrade(saved, "npc:589", nil, "bob-realm", 100)
    ACB.logTrade(saved, nil, "npc:573", "bob-realm", 101)
    ACB.cleanSavedData(saved)
    equal(#saved.history, 2)
    local text = table.concat(ACB.tradeHistory(saved), "\n")
    assert(text:find("Gifted", 1, true) and text:find("as a gift", 1, true))
    local valid = ledger:check()
    equal(valid, true)
end)

test("incoming gifts wait for invitation acceptance before opening the trade or sending a reply", function()
    local realPrepare, realSend = ACB.prepareTrade, C_ChatInfo.SendAddonMessage
    local opened
    ACB.prepareTrade = function(peer, ...) opened = peer realPrepare(peer, ...) end
    C_ChatInfo.SendAddonMessage = function() return 0 end
    AzerothCardBinderWindow:Hide()
    ACB.tradeView:Hide()
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "I|incoming-gift-ui|npc:639|g", "WHISPER", "Harry Dexter")
    equal(opened, nil)
    equal(AzerothCardBinderWindow:IsShown(), false)
    equal(ACB.tradeView:IsShown(), false)
    equal(AzerothCardBinderTradeNotice:IsShown(), true)
    equal(ACB.tradeView.controls.accept.enabled, false)
    equal(realPrepare("harry-dexter"), false, "a player-menu click cannot accept a pending invitation")
    equal(ACB.tradeView:IsShown(), false)
    equal(AzerothCardBinderTradeNotice:IsShown(), true)
    local oldDistance = ACB.tradeDistanceOk
    ACB.tradeDistanceOk = function() return true end
    AzerothCardBinderTradeNotice.accept:OnClick()
    ACB.tradeDistanceOk = oldDistance
    equal(opened, "harry-dexter")
    equal(AzerothCardBinderWindow:IsShown(), false)
    equal(ACB.tradeView:IsShown(), true)
    equal(ACB.tradeView.controls.accept.enabled, true)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "X|incoming-gift-ui", "WHISPER", "Harry Dexter")
    ACB.prepareTrade, C_ChatInfo.SendAddonMessage = realPrepare, realSend
end)

test("the card slot opens a binder selection and the offered card represents just one copy", function()
    local saved = { counts = { ["npc:639"] = 3 }, shiny = {}, history = {} }
    local trade = ACB.newTrade(saved.counts, function() return 10 end, function() return "ui-picker" end,
        function() return true end, function() return true end)
    local realPrepare = ACB.prepareTrade
    local realPick, choose, canPick = ACB.selectTradeCard
    ACB.selectTradeCard = function(callback, allowed) choose, canPick = callback, allowed end
    local view = ACB.createTradeView(UIParent, saved, trade)
    local c = view.controls
    c.slot:OnClick()
    assert(choose and canPick())
    choose("npc:639")
    equal(c.mine.owned, 1, "the player is offering one copy, not every owned copy")
    equal(c.mine.countBadge:IsShown(), false)
    ACB.prepareTrade = realPrepare
    ACB.selectTradeCard = realPick
end)

test("a gift invitation opens the window with an empty local side and an Accept button", function()
    local saved = { counts = {}, shiny = {}, history = {} }
    local trade = ACB.newTrade(saved.counts, function() return 10 end, function() return "ui-gift" end,
        function() return true end, function() return true end)
    local view = ACB.createTradeView(UIParent, saved, trade)
    equal(trade:receive("harry-dexter", "I|ui-gift|npc:639|g"), true)
    assert(trade:join())
    view:refresh()
    equal(view.controls.choose.enabled, false)
    equal(view.controls.accept.enabled, true)
    equal(view.controls.accept.text, "Accept")
    view.controls.accept:OnClick()
    equal(view.controls.accept.text, "Accepted")
    view.controls.picker:Hide()
end)
