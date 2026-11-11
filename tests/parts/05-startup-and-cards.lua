test("UI and SavedVariables initialize through ADDON_LOADED", function()
    emit("ADDON_LOADED", addon)
    -- The older tests trade without standing next to anyone; the trading distance has its own tests (15-trading-social.lua).
    AzerothCardBinderDB.tradeRange = false
    equal(AzerothCardBinderDB.counts.invalid, nil)
    local slash = SlashCmdList.AZEROTHCARDBINDER
    slash("")
    equal(AzerothCardBinderWindow:IsShown(), true)
    slash("trade")
    slash("log")
    equal(AzerothCardBinderLog:IsShown(), true)
    equal(ACB.tradePeer("Bob"), "bob-realmname")
    equal(ACB.tradePeer("Alice"), nil)
    equal(ACB.tradePeer("Bob|malformed"), nil)
end)

test("the Achievements tab lists earned titles and lets the player equip and hide one", function()
    local saved = AzerothCardBinderDB
    local originalTitles, originalAchievements, originalHidden = saved.titles, saved.achievements, saved.titleHidden
    saved.titles, saved.achievements = { ["Card Trader"] = true }, { trades1 = true }
    for _, widget in ipairs(widgets) do
        if widget.text == "Achievements" and widget.OnClick then widget:OnClick() break end
    end
    local choose, hide, status
    for _, widget in ipairs(widgets) do
        if widget.title == "Card Trader" and widget.OnClick then choose = widget end
        if widget.text == "Hide title" then hide = widget.parent end
        if widget.text == "1 / 18 achievements earned" then status = widget end
    end
    assert(status and choose and hide)
    choose:OnClick()
    equal(saved.title, "Card Trader")
    hide:OnClick()
    equal(saved.title, nil)
    equal(saved.titleHidden, true)
    saved.titles, saved.achievements, saved.titleHidden = originalTitles, originalAchievements, originalHidden
    ACB.open(1)
end)

test("cards draw for missing, owned and gathering entries", function()
    AzerothCardBinderDB.counts["npc:639"] = 2
    AzerothCardBinderDB.counts["node:1731"] = 1
    ACB.open(1)
    ACB.open(2)
    ACB.open(3)
    AzerothCardBinderDB.counts["npc:639"], AzerothCardBinderDB.counts["node:1731"] = nil, nil
end)

test("opening a set queues later portraits and leaving the set stops the loader", function()
    local cards = ACB.pages[2].cards
    local loader
    for _, widget in ipairs(widgets) do
        if widget.width == 2 and widget.height == 2 and widget.OnUpdate then loader = widget break end
    end
    assert(loader)
    ACB.open("index")
    equal(loader:IsShown(), false)
    ACB.openCard(cards[1].key)
    equal(loader:IsShown(), true)
    equal(loader.creature, nil)
    loader:OnUpdate(0.08)
    equal(loader.creature, cards[5].id)
    loader:OnUpdate(0.2)
    equal(loader.creature, cards[5].id) -- still waiting on the first model
    loader.fileID = 123456
    loader:OnUpdate(0.08)
    equal(loader.creature, cards[6].id)
    loader:OnUpdate(1)
    equal(loader.creature, cards[7].id) -- one missing model cannot block the queue
    ACB.open("index")
    equal(loader:IsShown(), false)
    equal(loader.creature, nil)
    ACB.openCard(cards[1].key)
    loader:OnUpdate(0.08)
    equal(loader.creature, cards[6].id) -- card 5 already loaded, card 6 can retry
    loader.parent:OnHide() -- closing the binder dispatches this on the live client
    equal(loader:IsShown(), false)
end)

test("missing models appear in the pocket and detail and regain colour when collected", function()
    local saved = AzerothCardBinderDB
    local edwin = ACB.cards["npc:639"]
    ACB.openCard(edwin.key)
    local models = {}
    for _, widget in ipairs(widgets) do
        if widget.creature == edwin.id then
            local frame = widget.parent.parent
            if frame.scale == 0.60 or frame.scale == 1.48 then
                assert(frame.parent.parent:IsShown() ~= false)
                equal(frame.OnUpdate ~= nil, frame.scale == 1.48)
                models[frame.scale] = widget
                equal(widget:IsShown(), true)
                equal(widget.desaturation, 1)
                assert(widget.modelAlpha > 0 and widget.modelAlpha < 1)
            end
        end
    end
    assert(models[0.60] and models[1.48])
    saved.counts[edwin.key] = 1
    ACB.refresh()
    for _, model in pairs(models) do
        equal(model.creature, edwin.id)
        equal(model.desaturation, 0)
        equal(model.modelAlpha, 1)
    end
    saved.counts[edwin.key] = nil
    ACB.openCard(ACB.pages[1].cards[1].key)
end)
