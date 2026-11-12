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
    -- Forever has no realms: a character has two names, written with a space or a hyphen.
    equal(ACB.tradePeer("Filfred Whizzlebang"), "filfred-whizzlebang")
    equal(ACB.tradePeer("Filfred-Whizzlebang"), "filfred-whizzlebang")
    equal(ACB.tradePeer("  Filfred   Whizzlebang "), "filfred-whizzlebang")
    equal(ACB.tradePeer("A B C"), nil)
end)

test("/acb whisperform chooses how a name is addressed, and /acb view takes a two-word name", function()
    local saved = AzerothCardBinderDB
    local originalSend, originalCodes = C_ChatInfo.SendAddonMessage, Enum.SendAddonMessageResult
    local targets = {}
    Enum.SendAddonMessageResult = { Success = 0 }
    C_ChatInfo.SendAddonMessage = function(_, _, _, peer) targets[#targets + 1] = peer return 0 end
    SlashCmdList.AZEROTHCARDBINDER("view Filfred Whizzlebang")
    SlashCmdList.AZEROTHCARDBINDER("whisperform hyphen")
    equal(saved.whisperForm, "hyphen")
    SlashCmdList.AZEROTHCARDBINDER("view Filfred Whizzlebang")
    SlashCmdList.AZEROTHCARDBINDER("whisperform space")
    equal(saved.whisperForm, "space")
    equal(targets[1], "Filfred Whizzlebang")
    equal(targets[2], "filfred-whizzlebang")
    saved.whisperForm = nil
    C_ChatInfo.SendAddonMessage, Enum.SendAddonMessageResult = originalSend, originalCodes
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

test("opening a set preloads four portraits together, retains loaded models and stops outside the collection", function()
    local cards = ACB.pages[2].cards
    local driver
    for _, widget in ipairs(widgets) do if widget.acbPortraitLoader then driver = widget break end end
    assert(driver)
    ACB.openCard(cards[1].key)
    equal(driver:IsShown(), true)
    driver:OnUpdate(.1)
    for slot = 1, 4 do
        equal(driver.models[slot].creature, cards[slot].id)
        equal(driver.models[slot].keepModel, true)
        driver.models[slot].fileID = 1000 + slot
    end
    driver:OnUpdate(.25)
    for slot = 1, 4 do
        equal(driver.models[slot].fileID, 1000 + slot, "completed models are retained instead of cleared")
        equal(driver.models[slot]:IsShown(), false)
    end
    equal(driver.models[5].creature, cards[5].id)
    ACB.open("wanted"); driver.parent:OnHide()
    equal(driver:IsShown(), false)
    equal(driver.models[1].fileID, 1001, "closing the collection keeps loaded resources")
    ACB.openCard(cards[1].key)
    equal(driver:IsShown(), true)
    driver.parent:OnHide()
end)

test("missing models appear in the pocket and detail and regain colour when collected", function()
    local saved = AzerothCardBinderDB
    local edwin = ACB.cards["npc:639"]
    ACB.openCard(edwin.key)
    local models = {}
    for _, widget in ipairs(widgets) do
        if widget.creature == edwin.id then
            local frame = widget.parent.parent
            if frame.scale == 0.60 or frame.scale == 1.32 then
                assert(frame.parent.parent:IsShown() ~= false)
                equal(frame.OnUpdate ~= nil, frame.scale == 1.32)
                models[frame.scale] = widget
                equal(widget:IsShown(), true)
                equal(widget.desaturation, 1)
                assert(widget.modelAlpha > 0 and widget.modelAlpha < 1)
            end
        end
    end
    assert(models[0.60] and models[1.32])
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
