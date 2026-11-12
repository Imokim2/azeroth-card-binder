test("satchel slots match native bag size and scale, and its launcher position persists until reset", function()
    local oldSlot, oldCombined = _G.ContainerFrame1Item1, _G.ContainerFrameCombinedBags
    _G.ContainerFrameCombinedBags = nil
    _G.ContainerFrame1Item1 = { GetWidth = function() return 38 end,
        GetEffectiveScale = function() return UIParent:GetEffectiveScale() * 1.25 end }
    local saved = ACB.cleanSavedData({})
    local view = ACB.initSatchel(saved)
    equal(view.slotSize, 47.5)
    equal(view.slots[1].width, 47.5)
    equal(view.slots[1].height, 47.5)
    assert(view.frame:GetFrameLevel() >= 300, "background and controls stay above every binder layer")
    shiftDown = true
    view.launcher:OnDragStart()
    view.launcher:OnDragStop()
    shiftDown = false
    assert(saved.satchelButtonPosition)
    equal(view.launcher.point[1], "CENTER")
    view.launcher:OnEvent()
    equal(view.launcher.point[1], "CENTER")
    ACB.resetSatchelButton()
    equal(saved.satchelButtonPosition, nil)
    _G.ContainerFrame1Item1, _G.ContainerFrameCombinedBags = oldSlot, oldCombined
end)

test("every live card category has a packaged scenic background with an existing file", function()
    for _, page in ipairs(ACB.pages) do for _, entry in ipairs(page.cards) do
        local file = ACB.cardBackdrop(entry.zone)
        assert(file, entry.zone)
        local handle = assert(io.open("AzerothCardBinder/Art/" .. file:gsub("\\", "/"), "rb"), file)
        handle:close()
    end end
end)

test("thumbnail and detail restore the same authored still composition after loading or revisiting", function()
    local entry = ACB.cards["edition:6391"]
    local thumbnail, detail = ACB.createCard(UIParent, true), ACB.createCard(UIParent, true, ignore)
    for _, card in ipairs({ thumbnail, detail }) do
        card:set(entry, 1)
        card.model.fileID, card.model.supportedAnimation = 12345, entry.presentation.animation
        card.model:OnModelLoaded()
        card.model:OnUpdate(.25); card.model:OnUpdate(.25)
    end
    equal(thumbnail.model.portraitZoom, detail.model.portraitZoom)
    equal(thumbnail.model.facing, detail.model.facing)
    equal(thumbnail.model.position[2], 0)
    detail.facing = 2
    detail.frame:OnHide()
    detail.model:OnShow()
    equal(detail.model.facing, thumbnail.model.facing)
    equal(detail.model.portraitZoom, thumbnail.model.portraitZoom)
end)

test("incoming trade notices show a sender and expire without accepting or moving a card", function()
    local saved = AzerothCardBinderDB
    local before = ACB.sumValues(saved.counts)
    ACB.notifyTrade("bob-realmname", true)
    equal(AzerothCardBinderTradeNotice:IsShown(), true)
    local found
    for _, widget in ipairs(widgets) do if widget.text == "bob-realmname sent you a gift." then found = true end end
    assert(found)
    AzerothCardBinderTradeNotice:OnUpdate(16)
    equal(AzerothCardBinderTradeNotice:IsShown(), false)
    equal(ACB.sumValues(saved.counts), before)
end)
