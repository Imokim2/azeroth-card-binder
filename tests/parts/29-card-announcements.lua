-- Exercise real acquisition paths and the public chat boundary without sending game chat.
local function withAnnouncements(runTest)
    local oldGroup, oldRaid, oldSend, oldTimer, oldClock, oldLock = IsInGroup, IsInRaid,
        C_ChatInfo.SendChatMessage, C_Timer, GetTime, C_ChatInfo.InChatMessagingLockdown
    local oldGuild, oldGuildInfo = IsInGuild, GetGuildInfo
    local env = { stamp = 0, sent = {}, tasks = {}, group = "solo", locked = false }
    IsInGuild = function() return env.guild ~= nil end
    GetGuildInfo = function() return env.guild end
    IsInGroup = function(category) return category and env.group == "instance" or not category and env.group ~= "solo" end
    IsInRaid = function() return env.group == "raid" end
    GetTime = function() return env.stamp end
    C_ChatInfo.InChatMessagingLockdown = function() return env.locked end
    C_ChatInfo.SendChatMessage = function(message, destination)
        env.sent[#env.sent + 1] = { message = message, channel = destination, at = env.stamp }
    end
    C_Timer = { After = function(delay, action) env.tasks[#env.tasks + 1] = { at = env.stamp + delay, action = action } end }
    function env:advance(seconds)
        local untilTime = self.stamp + seconds
        while true do
            table.sort(self.tasks, function(a, b) return a.at < b.at end)
            if not self.tasks[1] or self.tasks[1].at > untilTime then break end
            local task = table.remove(self.tasks, 1)
            self.stamp = task.at
            task.action()
        end
        self.stamp = untilTime
    end
    local ok, why = pcall(runTest, env)
    IsInGroup, IsInRaid, C_ChatInfo.SendChatMessage, C_Timer, GetTime, C_ChatInfo.InChatMessagingLockdown =
        oldGroup, oldRaid, oldSend, oldTimer, oldClock, oldLock
    IsInGuild, GetGuildInfo = oldGuild, oldGuildInfo
    assert(ok, why)
end

test("dungeon chat lockdown offers an explicit share draft without attempting restricted sends", function()
    withAnnouncements(function(env)
        local oldInstance, oldFrame, oldChat, oldModern = IsInInstance, DEFAULT_CHAT_FRAME, ChatFrame_OpenChat, ChatFrameUtil and ChatFrameUtil.OpenChat
        local lines, prepared = {}, {}
        IsInInstance = function() return true, "party" end
        DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) lines[#lines + 1] = text end }
        ChatFrame_OpenChat = function(text) prepared[#prepared + 1] = text end
        if ChatFrameUtil then ChatFrameUtil.OpenChat = ChatFrame_OpenChat end
        local ok, why = pcall(function()
            env.group, env.locked = "party", true
            ACB.newCardAnnouncements({}):add(ACB.cards["npc:589"], {})
            equal(#env.sent, 0); equal(#lines, 1)
            local link = assert(lines[1]:match("|H(.-)|h"))
            ACB.openAnnouncementLink(link)
            equal(prepared[1], "/p World of Warcards: I just added 'Defias Pillager' to my binder.")
            equal(#env.sent, 0, "opening a draft must never send it")
            env.group = "solo"; ACB.openAnnouncementLink(link); equal(#prepared, 1)
            env:advance(65); equal(#env.sent, 0)
        end)
        IsInInstance, DEFAULT_CHAT_FRAME, ChatFrame_OpenChat = oldInstance, oldFrame, oldChat
        if ChatFrameUtil then ChatFrameUtil.OpenChat = oldModern end
        assert(ok, why)
    end)
end)

test("acquired cards use party, raid, instance or solo say with readable public wording", function()
    withAnnouncements(function(env)
        local card = ACB.cards["npc:589"]
        for _, pair in ipairs({ { "solo", "SAY" }, { "party", "PARTY" }, { "raid", "RAID" }, { "instance", "INSTANCE_CHAT" } }) do
            env.group = pair[1]
            local announcer = ACB.newCardAnnouncements({})
            announcer:add(card, {})
            local sent = env.sent[#env.sent]
            equal(sent.channel, pair[2])
            equal(sent.message, "World of Warcards: I just added 'Defias Pillager' to my binder.")
            assert(not sent.message:find("|H", 1, true))
        end
        ACB.newCardAnnouncements({}):add(card, { shiny = true })
        assert(env.sent[#env.sent].message:find("Defias Pillager (Shiny)", 1, true))
        for _, entry in pairs(ACB.cards) do
            assert(#("World of Warcards: I just added '" .. entry.name .. " (Shiny)' to my binder.") <= 255)
        end
    end)
end)

test("a real drop reports a private clickable link once and opening it uses the player's binder", function()
    withAnnouncements(function(env)
        local saved, lines = ACB.cleanSavedData({ popups = false }), {}
        local collection = ACB.newCollection(saved, function(_, high) return high == ACB.shinyOdds and 2 or 1 end,
            function(line) lines[#lines + 1] = line end, ignore)
        collection.announcements = ACB.newCardAnnouncements(saved)
        local source = guid(589, "announcement-drop")
        equal(collection:roll(source, "loot"), true)
        local link = assert(lines[1]:match("|H(.-)|h"))
        equal(ACB.parseCardLink(link).key, "npc:589")
        equal(#env.sent, 1)
        collection:roll(source, "loot")
        collection:restoreAchievements()
        equal(#env.sent, 1)
        AzerothCardBinderWindow:Hide()
        chatCallbacks.SetItemRef(link, lines[1], "LeftButton")
        equal(AzerothCardBinderWindow:IsShown(), true)
        equal(ACB.parseCardLink(link), ACB.cards["npc:589"])
        collection:roll(guid(589, "announcement-duplicate"), "loot")
        env:advance(2)
        equal(#env.sent, 2) -- duplicates are acquisitions too
    end)
end)

test("crafting and received gifts announce but failed actions and outgoing gifts do not", function()
    withAnnouncements(function(env)
        local saved, lines = ACB.cleanSavedData({ dust = 100000 }), {}
        local collection = ACB.newCollection(saved, function() return 1 end, function(line) lines[#lines + 1] = line end, ignore)
        collection.announcements = ACB.newCardAnnouncements(saved)
        equal(collection:craft("npc:589"), true)
        assert(lines[1]:find("|Haddon:AzerothCardBinder:card:npc:589:0|h", 1, true))
        equal(collection:craft("npc:589"), false)
        equal(collection:swap("npc:589", nil), true)
        equal(#env.sent, 1)
        equal(collection:swap(nil, "npc:639"), true)
        env:advance(2)
        equal(#env.sent, 2)
        local found
        for _, line in ipairs(lines) do if line:find("|Haddon:AzerothCardBinder:card:npc:639:0|h", 1, true) then found = true end end
        assert(found)
    end)
end)

test("pack notifications wait for reveals and closing early reports remaining cards exactly once", function()
    withAnnouncements(function(env)
        local oldCollection = ACB.collection
        local saved, lines = ACB.cleanSavedData({}), {}
        local zone = ACB.pages[ACB.cards["npc:589"].page].code
        saved.packs[zone] = 1
        local collection = ACB.newCollection(saved, function(_, high) return high end,
            function(line) lines[#lines + 1] = line end, ignore)
        collection.announcements = ACB.newCardAnnouncements(saved)
        ACB.collection = collection
        local view = ACB.createPackView(saved)
        view:openZone(zone)
        equal(#env.sent, 0)
        local results = view.results
        run(view, 3)
        equal(#env.sent, 0)
        view:flip(1)
        run(view, 1)
        equal(#env.sent, 1)
        view:finish()
        view:finish()
        env:advance(10)
        equal(#env.sent, 5)
        local private = 0
        for _, line in ipairs(lines) do if line:find("From the pack:", 1, true) then
            private = private + 1
            assert(ACB.parseCardLink(line:match("|H(.-)|h")))
        end end
        equal(private, 5)
        for _, result in ipairs(results) do equal(result.announced, true) end
        for index = 2, #env.sent do assert(env.sent[index].at - env.sent[index - 1].at >= 2) end
        ACB.collection = oldCollection
    end)
end)

test("muting clears queued announcements while private links remain and the slash toggle persists", function()
    withAnnouncements(function(env)
        local saved, lines = ACB.cleanSavedData({}), {}
        local collection = ACB.newCollection(saved, function() return 1 end, function(line) lines[#lines + 1] = line end, ignore)
        collection.announcements = ACB.newCardAnnouncements(saved)
        collection:cardAdded(ACB.cards["npc:589"], { count = 1 })
        collection:cardAdded(ACB.cards["npc:639"], { count = 1 })
        ACB.setSetting(saved, "announceCards", false)
        env:advance(5)
        collection:cardAdded(ACB.cards["npc:598"], { count = 1 })
        equal(#env.sent, 1)
        equal(#lines, 3)
        assert(lines[3]:find("|Haddon:", 1, true))
        ACB.cleanSavedData(saved)
        equal(ACB.settingOn(saved, "announceCards"), false)
        local was = AzerothCardBinderDB.announceCards
        AzerothCardBinderDB.announceCards = nil
        SlashCmdList.AZEROTHCARDBINDER("announce")
        equal(AzerothCardBinderDB.announceCards, false)
        SlashCmdList.AZEROTHCARDBINDER("announce")
        equal(AzerothCardBinderDB.announceCards, true)
        AzerothCardBinderDB.announceCards = was
    end)
end)

test("chat lockdown expires, channel changes discard stale messages, and refused sends never retry", function()
    withAnnouncements(function(env)
        local announcer, card = ACB.newCardAnnouncements({}), ACB.cards["npc:589"]
        env.locked = true
        announcer:add(card)
        env:advance(62)
        env.locked = false
        env:advance(2)
        equal(#env.sent, 0)
        announcer:add(card)
        announcer:add(card)
        env.group = "party"
        env:advance(3)
        equal(#env.sent, 1)
        local attempts, logs = 0, {}
        C_ChatInfo.SendChatMessage = function() attempts = attempts + 1 error("client denied") end
        announcer = ACB.newCardAnnouncements({}, function(line) logs[#logs + 1] = line end)
        announcer:add(card)
        env:advance(10)
        equal(attempts, 1)
        equal(#logs, 1)
        -- The legacy function is used only when the namespaced one is missing.
        local original = SendChatMessage
        C_ChatInfo.SendChatMessage = nil
        SendChatMessage = function(_, destination) equal(destination, "PARTY") attempts = attempts + 1 end
        ACB.newCardAnnouncements({}):add(card)
        equal(attempts, 2)
        SendChatMessage = original
    end)
end)

test("guild announcements are opt-in and the card rarity filter is independent of public chat", function()
    withAnnouncements(function(env)
        env.guild = "Test Guild"
        local cards = {}
        for _, card in pairs(ACB.cards) do cards[card.rarity] = card end
        local defaults = ACB.cleanSavedData({})
        local announcer = ACB.newCardAnnouncements(defaults)
        announcer:add(cards.legendary)
        env:advance(3)
        equal(#env.sent, 1); equal(env.sent[1].channel, "SAY")
        equal(ACB.settingOn(defaults, "guildCards"), false)
        equal(ACB.settingOn(defaults, "guildPacks"), false)
        equal(ACB.guildRarity(defaults).key, "epic")
        for _, case in ipairs({ { "common", 4 }, { "rare", 3 }, { "epic", 2 }, { "legendary", 1 }, { "bad value", 2 } }) do
            local saved = { announceCards = false, guildCards = true, guildMinRarity = case[1] }
            local before = #env.sent
            announcer = ACB.newCardAnnouncements(saved)
            for _, rarity in ipairs({ "common", "rare", "epic", "legendary" }) do announcer:add(cards[rarity]) end
            env:advance(10)
            equal(#env.sent - before, case[2])
            for index = before + 1, #env.sent do equal(env.sent[index].channel, "GUILD") end
        end
    end)
end)

test("guild queue rechecks membership, switches and rarity without cancelling other destinations", function()
    withAnnouncements(function(env)
        env.guild = "Old Guild"
        local saved = { guildCards = true, guildMinRarity = "common" }
        local announcer = ACB.newCardAnnouncements(saved)
        local common, legendary = ACB.cards["npc:589"], ACB.cards["npc:639"]
        announcer:add(legendary) -- public now, guild queued
        ACB.setSetting(saved, "announceCards", false)
        announcer:clear("announceCards")
        env:advance(2)
        equal(#env.sent, 2); equal(env.sent[2].channel, "GUILD")
        announcer:add(common)
        saved.guildMinRarity = "legendary"
        env:advance(2); equal(#env.sent, 2)
        announcer:add(legendary)
        announcer:add(legendary)
        env.guild = "New Guild"
        env:advance(3); equal(#env.sent, 3, "queued finds must not move to a new guild")
        announcer:add(legendary)
        announcer:add(legendary)
        ACB.setSetting(saved, "guildCards", false)
        env:advance(3); equal(#env.sent, 4)
        saved.guildCards, env.guild = true, nil
        announcer:add(legendary)
        env:advance(3); equal(#env.sent, 4, "unguilded players never send guild chat")
    end)
end)

test("a real pack find announces its zone and tier once without exposing unopened cards", function()
    withAnnouncements(function(env)
        env.guild = "Test Guild"
        local saved = ACB.cleanSavedData({ announceCards = false, guildPacks = true })
        local collection = ACB.newCollection(saved, function(_, high)
            if high == ACB.packOdds then return 1 end
            if high == 100 then return 85 end
            return high
        end, ignore, ignore)
        collection.packsEnabled = true
        collection.announcements = ACB.newCardAnnouncements(saved)
        local source = guid(589, "guild-pack-find")
        collection:roll(source, "loot")
        collection:roll(source, "loot")
        env:advance(10)
        equal(#env.sent, 1); equal(env.sent[1].channel, "GUILD")
        local zone = ACB.pages[ACB.cards["npc:589"].page].code
        local pack = ACB.packItem("pack:" .. ACB.packID(zone, "rare"))
        equal(saved.packs[pack.zone], 1)
        equal(env.sent[1].message, "World of Warcards: I just found '" .. pack.name .. "' (Rare).")
        equal(next(saved.counts), nil)
    end)
end)

test("guild card messages wait until pack reveals and remain private when guild sending is refused", function()
    withAnnouncements(function(env)
        env.guild = "Test Guild"
        local oldCollection = ACB.collection
        local saved, lines = ACB.cleanSavedData({ announceCards = false, guildCards = true, guildMinRarity = "common" }), {}
        local zone = ACB.pages[ACB.cards["npc:589"].page].code
        saved.packs[zone] = 1
        local collection = ACB.newCollection(saved, function(_, high) return high end, function(line) lines[#lines + 1] = line end, ignore)
        collection.announcements = ACB.newCardAnnouncements(saved)
        ACB.collection = collection
        local view = ACB.createPackView(saved)
        view:openZone(zone)
        env:advance(3); run(view, 3)
        equal(#env.sent, 0)
        view:flip(1); run(view, 1)
        equal(#env.sent, 1); equal(env.sent[1].channel, "GUILD")
        local attempts = 0
        C_ChatInfo.SendChatMessage = function(_, destination)
            equal(destination, "GUILD"); attempts = attempts + 1; return false
        end
        view:finish(); view:finish()
        env:advance(15)
        equal(attempts, 4)
        local private = 0
        for _, line in ipairs(lines) do if line:find("From the pack:", 1, true) then private = private + 1 end end
        equal(private, 5)
        ACB.collection = oldCollection
    end)
end)

test("Chat settings save independent switches and a rarity choice without touching the collection", function()
    local saved = ACB.cleanSavedData({ counts = { ["npc:589"] = 7 }, packs = { DM = 2 } })
    local view = ACB.createSettingsView(UIParent, saved)
    view:refresh()
    local controls = view.chatControls
    equal(controls.checks.guildCards.checked, false)
    equal(controls.checks.guildPacks.checked, false)
    equal(controls.rarity.enabled, false)
    equal(controls.rarity.text, "Epic and Legendary")
    controls.checks.guildCards.checked = true; controls.checks.guildCards:OnClick()
    equal(controls.rarity.enabled, true)
    controls.rarity:OnClick()
    equal(saved.guildMinRarity, "legendary")
    controls.checks.guildPacks.checked = true; controls.checks.guildPacks:OnClick()
    controls.checks.announceCards.checked = false; controls.checks.announceCards:OnClick()
    ACB.cleanSavedData(saved)
    equal(saved.guildCards, true); equal(saved.guildPacks, true)
    equal(saved.announceCards, false); equal(saved.guildMinRarity, "legendary")
    equal(saved.counts["npc:589"], 7); equal(saved.packs.DM, 2)
    local tabs = {}
    for _, widget in ipairs(widgets) do
        if widget.parent == view and widget.OnClick then tabs[widget.text] = widget end
    end
    tabs.Chat:OnClick()
    equal(controls.checks.guildCards.parent:IsShown(), true)
    tabs.Sounds:OnClick()
    equal(controls.checks.guildCards.parent:IsShown(), false)
    tabs.General:OnClick()
    equal(controls.checks.guildCards.parent:IsShown(), false)
    view:Hide()
end)
