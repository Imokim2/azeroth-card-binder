test("an invitation sends no join or acceptance until the player accepts it", function()
    local sent, applied, at = {}, 0, 10
    local trade = ACB.newTrade({}, function() return at end, function() return "invite-only" end,
        function(_, message) sent[#sent + 1] = message return true end,
        function() applied = applied + 1 return true end)
    assert(trade:receive("bob-realm", "I|invite-only|npc:639|g"))
    equal(#sent, 0)
    equal(trade:canAccept(), false)
    equal(trade:change("npc:589"), false)
    trade:confirm(); trade:step(3)
    trade:receive("bob-realm", "I|invite-only|npc:639|g")
    trade:receive("bob-realm", "A|invite-only|1|1|npc:639|0")
    equal(#sent, 0)
    equal(applied, 0)
    assert(trade:join())
    equal(#sent, 1)
    equal(sent[1], "U|invite-only|1|0")
    equal(trade.session.sentConfirm, nil, "joining does not accept the gift")
    equal(trade:canAccept(), true)
    trade:confirm()
    equal(#sent, 2)
    equal(applied, 0, "the other player must still accept and finish")
end)

test("declining or expiring an unopened invitation never sends an offer or moves an item", function()
    local sent, at = {}, 10
    local trade = ACB.newTrade({}, function() return at end, ignore,
        function(_, message) sent[#sent + 1] = message return true end,
        function() error("an invitation cannot transfer anything") end)
    assert(trade:receive("bob-realm", "I|decline-invite|npc:639|g"))
    trade:cancel()
    equal(sent[1], "K|decline-invite")
    trade:receive("bob-realm", "X|decline-invite")
    assert(trade.session.closed)
    trade:reset()
    at = at + 4
    assert(trade:receive("bob-realm", "I|expire-invite|npc:639|g"))
    at = at + 121
    equal(trade:active(), nil)
    equal(#sent, 1)
end)

test("the offer slot raises the binder, adds the selected exact edition, then closes only the binder", function()
    local saved, view = AzerothCardBinderDB, ACB.tradeView
    local key = "edition:6391"
    local previous = saved.counts[key]
    saved.counts[key] = 2
    view.controls.cancel:OnClick() -- discard a finished session from an earlier check
    ACB.open("trade")
    equal(view.parent, UIParent)
    equal(AzerothCardBinderWindow:IsShown(), false)
    local oldLevel = AzerothCardBinderWindow:GetFrameLevel()
    view.controls.slot:OnClick()
    equal(AzerothCardBinderWindow:IsShown(), true)
    equal(AzerothCardBinderWindow.strata, "FULLSCREEN_DIALOG")
    assert(AzerothCardBinderWindow:GetFrameLevel() > view:GetFrameLevel())
    ACB.openCard(key)
    local add = ACB.binderView.tradeButton
    equal(add:IsShown(), true)
    equal(add.enabled, true)
    add:OnClick()
    equal(AzerothCardBinderWindow:IsShown(), false)
    equal(AzerothCardBinderWindow.strata, "DIALOG")
    equal(AzerothCardBinderWindow:GetFrameLevel(), oldLevel)
    equal(view:IsShown(), true)
    equal(view.controls.mine.entry.key, key)
    equal(view.controls.mine.owned, 1)
    equal(saved.counts[key], 2, "adding an offer does not transfer or reserve every copy")
    equal(view.controls.accept.enabled, false, "choosing a card does not accept a trade")
    saved.counts[key] = previous
end)

test("missing cards cannot be added and closing the picker returns to the trade unchanged", function()
    local saved, view = AzerothCardBinderDB, ACB.tradeView
    local key = "edition:6392"
    local previous = saved.counts[key]
    saved.counts[key] = nil
    local offered = view.controls.mine.entry.key
    view.controls.choose:OnClick()
    ACB.openCard(key)
    equal(ACB.binderView.tradeButton.enabled, false)
    ACB.binderView.tradeButton:OnClick()
    equal(AzerothCardBinderWindow:IsShown(), true)
    equal(view.controls.mine.entry.key, offered)
    AzerothCardBinderWindow:Hide(); AzerothCardBinderWindow:OnHide()
    equal(view:IsShown(), true)
    equal(ACB.binderView.tradeButton:IsShown(), false)
    equal(view.controls.mine.entry.key, offered)
    saved.counts[key] = previous
end)
