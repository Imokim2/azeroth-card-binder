test("the simple Trade panel filters whispers and moves cards only after both accept and finish", function()
    local saved, sent = AzerothCardBinderDB, {}
    local tradesBefore, range = saved.tradeCount, saved.tradeRange
    saved.tradeRange = false
    Enum = { SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11 } }
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, peer)
        equal(prefix, ACB.tradePrefix)
        equal(channel, "WHISPER")
        equal(peer, "Bob Realmname")
        if locked then return Enum.SendAddonMessageResult.AddOnMessageLockdown end
        sent[#sent + 1] = message
        return 0
    end
    ACB.open("trade")
    local c = ACB.tradeView.controls
    c.partner:SetText("Bob")
    c.choose:OnClick()
    c.search:SetText("Defias Pillager")
    c.search:OnTextChanged()
    local give = assert(c.rows[1].key)
    local before, takeBefore = saved.counts[give], saved.counts["npc:573"] or 0
    c.rows[1]:OnClick()
    instance = 36
    c.start:OnClick()
    equal(#sent, 0)
    instance, combat = 0, true
    eventFrame:OnUpdate(2.1)
    equal(#sent, 0)
    combat, locked = false, true
    eventFrame:OnUpdate(2.1)
    equal(#sent, 0)
    locked = false
    eventFrame:OnUpdate(2.1)
    equal(#sent, 1)
    local id, offered = sent[1]:match("^I|([^|]+)|([^|]+)|t$")
    equal(offered, give)
    emit("CHAT_MSG_ADDON", secret, secret, secret, secret)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "U|" .. id .. "|1|npc:573", "PARTY", "Bob")
    c.accept:OnClick()
    equal(#sent, 1)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "U|" .. id .. "|1|npc:573", "WHISPER", "Bob")
    c.accept:OnClick()
    equal(sent[2], "A|" .. id .. "|1|1|" .. give .. "|npc:573")
    equal(saved.tradeCount, tradesBefore)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "A|" .. id .. "|1|1|npc:573|" .. give, "WHISPER", "Bob-RealmName")
    equal(saved.tradeCount, tradesBefore, "commit must also be acknowledged")
    assert(sent[#sent]:find("^F|"))
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "D|" .. id, "WHISPER", "Bob-RealmName")
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "D|" .. id, "WHISPER", "Bob-RealmName")
    equal(saved.tradeCount, tradesBefore + 1)
    equal(saved.counts[give] or 0, before - 1)
    equal(saved.counts["npc:573"], takeBefore + 1)
    saved.tradeRange = range
end)

test("binder dust recycles spares, keeps the last copy, and crafts a missing card once", function()
    for rarity, yield in pairs(ACB.dust.recycle) do
        equal(ACB.dust.craft[rarity], yield * 10) -- ten spares pay for one card of the same rarity
    end
    local saved = { counts = { ["npc:589"] = 3, ["npc:573"] = 2, ["npc:639"] = 1 }, achievements = {}, dust = 0 }
    local finds = {}
    local collection = ACB.newCollection(saved, function() return 10000 end, ignore, ignore, function(card, info)
        finds[#finds + 1] = { card = card, info = info }
    end)
    local common, epic = ACB.dustFor(ACB.cards["npc:589"]), ACB.dustFor(ACB.cards["npc:573"])
    equal(collection:recycle("npc:639"), false) -- the only copy stays
    equal(saved.counts["npc:639"], 1)
    equal(collection:recycle("npc:589"), true)
    equal(collection:recycle("npc:589"), true)
    equal(collection:recycle("npc:589"), false)
    equal(saved.counts["npc:589"], 1)
    equal(collection:recycle("npc:573"), true)
    equal(saved.dust, common * 2 + epic)
    equal(collection:recycle("npc:99999"), false)

    local missing = ACB.cards["npc:590"]
    local _, cost = ACB.dustFor(missing)
    saved.misses = { ["npc:590"] = 7 }
    equal(collection:craft("npc:590"), false) -- not enough dust yet
    equal(saved.counts["npc:590"], nil)
    saved.dust = cost + 3
    equal(collection:craft("npc:590"), true)
    equal(saved.counts["npc:590"], 1)
    equal(saved.dust, 3)
    equal(saved.misses["npc:590"], nil) -- the bad-luck counter starts again
    equal(saved.shiny, nil) -- a crafted card is never shiny
    equal(#finds, 1)
    equal(finds[1].info.crafted, true)
    equal(finds[1].info.first, true)
    equal(collection:craft("npc:590"), false) -- you already own it
    equal(saved.dust, 3)
end)

test("the folio shows kills since the last drop and a dust button that recycles and crafts", function()
    local function widgetWithText(value)
        for _, widget in ipairs(widgets) do
            if widget.text == value then return widget end
        end
        error("missing widget: " .. value)
    end
    local saved = AzerothCardBinderDB
    local keep = { saved.dust, saved.misses["npc:639"], saved.counts["npc:639"], saved.counts["npc:590"] }
    local entry = ACB.cards["npc:639"]
    local yield, cost = ACB.dustFor(entry)
    local _, limit = ACB.luck(saved, entry)

    saved.counts["npc:639"], saved.misses["npc:639"], saved.dust = 2, 37, 0
    assert(ACB.openCard("npc:639"))
    widgetWithText("Collected")
    widgetWithText("Binder Dust: 0")
    local recycle = widgetWithText(("Recycle a spare: +%d dust"):format(yield))
    equal(recycle.parent.enabled, true)
    recycle.parent:OnClick()
    equal(saved.counts["npc:639"], 1)
    equal(saved.dust, yield)
    local single = widgetWithText("No spare to recycle")
    equal(single.parent.enabled, false)
    widgetWithText(("Binder Dust: %d"):format(yield))

    saved.counts["npc:639"], saved.dust = nil, 0
    ACB.openCard("npc:639")
    local short = widgetWithText(("Craft: %d dust (have 0)"):format(cost))
    equal(short.parent.enabled, false)
    saved.dust = cost
    ACB.openCard("npc:639")
    local craft = widgetWithText(("Craft this card: %d dust"):format(cost))
    equal(craft.parent.enabled, true)
    craft.parent:OnClick()
    equal(saved.counts["npc:639"], 1)
    equal(saved.dust, 0)

    -- A gathering node counts gathers, not kills.
    ACB.openCard("node:1731")
    widgetWithText("COLLECTION STATUS")
    equal(ACB.openCard("npc:99999"), false)
    saved.dust, saved.misses["npc:639"], saved.counts["npc:639"], saved.counts["npc:590"] = unpack(keep, 1, 4)
    ACB.open("collection")
end)

test("the settings tab lists every switch, with defaults, and keeps slash commands in step", function()
    local saved = AzerothCardBinderDB
    local keep = { saved.popups, saved.hints, saved.inspectable, saved.diagnostics, saved.bossTrial, saved.title, saved.titles }
    saved.popups, saved.hints, saved.inspectable, saved.diagnostics, saved.bossTrial = nil, nil, nil, nil, nil
    local keepRange = saved.tradeRange
    saved.tradeRange = nil
    equal(ACB.settingOn(saved, "popups"), true) -- on until switched off
    equal(ACB.settingOn(saved, "tradeRange"), true) -- the trading distance is on until switched off
    equal(ACB.settingOn(saved, "diagnostics"), false) -- off until switched on
    equal(ACB.setSetting(saved, "nonsense", true), false)
    equal(ACB.setSetting(saved, "hints", false), true)
    equal(saved.hints, false)
    equal(ACB.settingOn(saved, "hints"), false)
    saved.hints = nil

    local checks = {}
    ACB.open("settings")
    for _, widget in ipairs(widgets) do
        if widget.template == "UICheckButtonTemplate" then checks[#checks + 1] = widget end
    end
    equal(#checks, #ACB.settings)
    for index, setting in ipairs(ACB.settings) do
        equal(checks[index].checked, setting.default)
    end
    equal(AzerothCardBinderWindow:IsShown(), true)

    -- Ticking a box changes the saved switch the game already reads.
    checks[1].checked = false
    checks[1]:OnClick()
    equal(saved.popups, false)
    checks[5].checked = true
    checks[5]:OnClick()
    equal(saved.diagnostics, true)
    -- The slash command flips the same switch and the open tab follows.
    SlashCmdList.AZEROTHCARDBINDER("hints")
    equal(saved.hints, false)
    equal(checks[2].checked, false)
    SlashCmdList.AZEROTHCARDBINDER("popup")
    equal(saved.popups, true)
    equal(checks[1].checked, true)

    -- Titles step through the earned ones, with none as the first stop.
    local first, second = ACB.pages[1].reward, ACB.pages[2].reward
    saved.titles, saved.title = { [first] = true, [second] = true }, nil
    equal(ACB.cycleTitle(saved, 1), first)
    equal(ACB.cycleTitle(saved, 1), second)
    equal(ACB.cycleTitle(saved, 1), nil)
    equal(ACB.cycleTitle(saved, -1), second)
    saved.titles, saved.title = {}, nil
    equal(ACB.cycleTitle(saved, 1), nil)
    saved.titles = { [first] = true }
    local function click(label)
        for _, widget in ipairs(widgets) do
            if widget.text == label and widget.OnClick then widget:OnClick() return end
        end
        error("button not found: " .. label)
    end
    click("Next title")
    equal(saved.title, first)
    click("Previous title")
    equal(saved.title, nil)
    click("Test pop-up")

    saved.popups, saved.hints, saved.inspectable, saved.diagnostics, saved.bossTrial, saved.title, saved.titles = unpack(keep, 1, 7)
    saved.tradeRange = keepRange
    ACB.open("collection")
end)
