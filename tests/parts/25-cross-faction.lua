-- Cross-faction trading: whispers do not cross factions, so messages to the other faction go through a quiet chat channel,
-- addressed to one player ("@name|message"), and come back the same way. Same-faction players are still whispered.

-- A fake game with a link channel, a target of a given faction, and a record of every addon message sent.
local function crossWorld(options)
    options = options or {}
    local world = { sent = {}, log = {}, joined = options.joined == true, joins = {}, results = { WHISPER = 0, CHANNEL = 0 }, faction = options.faction }
    local keep = {
        send = C_ChatInfo.SendAddonMessage, enum = Enum, full = UnitFullName, player = UnitIsPlayer, faction = UnitFactionGroup,
        channel = GetChannelName, join = JoinTemporaryChannel, prepare = ACB.prepareTrade, range = AzerothCardBinderDB.tradeRange,
        cross = AzerothCardBinderDB.crossFaction, owned = AzerothCardBinderDB.counts["npc:589"],
    }
    Enum = { SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11, TargetOffline = 12 } }
    C_ChatInfo.SendAddonMessage = function(prefix, message, distribution, target)
        world.sent[#world.sent + 1] = { prefix = prefix, message = message, distribution = distribution, target = target }
        return world.results[distribution]
    end
    UnitIsPlayer = function() return true end
    UnitFullName = function(unit) if unit == "target" then return "Bob", "RealmName" end return "Alice", "Realm Name" end
    UnitFactionGroup = function(unit) if unit == "player" then return "Horde" end return world.faction end
    GetChannelName = function(name) return name == ACB.linkChannel and world.joined and 7 or 0 end
    JoinTemporaryChannel = function(name) world.joins[#world.joins + 1] = name world.joined = true end
    ACB.prepareTrade = function() end
    AzerothCardBinderDB.tradeRange, AzerothCardBinderDB.crossFaction = false, nil
    AzerothCardBinderDB.counts["npc:589"] = 1
    clock = clock + 5 -- invitations are not accepted twice within three seconds
    ACB.initLink(AzerothCardBinderDB, function(line) world.log[#world.log + 1] = line end) -- forget what was learned about players in earlier tests
    -- Earlier parts replaced the viewer's sender with a stub: give it the real one, as the game does (Forever.lua).
    ACB.initSocial(AzerothCardBinderDB, function(peer, message) return ACB.sendLinked(ACB.viewPrefix, peer, message) end,
        GetTime, function(delay, action) if delay <= 0 then action() else timers[#timers + 1] = action end end, function() end)
    function world.last() return world.sent[#world.sent] end
    function world.finish()
        C_ChatInfo.SendAddonMessage, Enum, UnitFullName, UnitIsPlayer, UnitFactionGroup = keep.send, keep.enum, keep.full, keep.player, keep.faction
        GetChannelName, JoinTemporaryChannel, ACB.prepareTrade = keep.channel, keep.join, keep.prepare
        AzerothCardBinderDB.tradeRange, AzerothCardBinderDB.crossFaction, AzerothCardBinderDB.counts["npc:589"] = keep.range, keep.cross, keep.owned
        ACB.initLink(AzerothCardBinderDB)
    end
    return world
end

test("a player of the other faction is reached through the link channel, addressed to them", function()
    local world = crossWorld({ faction = "Alliance" })
    -- The link is not up yet: the first attempt joins the channel and says to try again.
    local sent, reason = ACB.requestBinder("bob-realmname")
    equal(sent, false)
    assert(reason:find("not connected yet", 1, true), reason)
    equal(world.joins[1], "WarcardsLink")
    equal(#world.sent, 0)
    -- Once joined, the request goes to the channel, with the player's name in front, and not as a whisper.
    equal(ACB.requestBinder("bob-realmname"), true)
    equal(#world.sent, 1)
    equal(world.last().prefix, ACB.viewPrefix)
    equal(world.last().distribution, "CHANNEL")
    equal(world.last().target, 7)
    equal(world.last().message, "@bob-realmname|Q")
    -- A trade offer goes the same way.
    ACB.startTrade("bob-realmname", "npc:589")
    equal(world.last().distribution, "CHANNEL")
    local id = world.last().message:match("^@bob%-realmname|I|([%w%-]+)|npc:589|t$")
    assert(id, world.last().message)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "@alice-realmname|K|" .. id, "CHANNEL", "Bob Realmname")
    equal(world.last().message, "@bob-realmname|X|" .. id) -- and the cancellation is answered the same way
    world.finish()
end)

test("a message from the channel is acted on only if it is for this player and from somebody else", function()
    local world = crossWorld({ joined = true })
    local invitation = "I|link-in-1|npc:639|g"
    -- Meant for Carol: ignored. From ourselves (a channel gives our own messages back): ignored.
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "@carol-realmname|" .. invitation, "CHANNEL", "Bob Realmname")
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "@alice-realmname|" .. invitation, "CHANNEL", "Alice Realmname")
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, invitation, "CHANNEL", "Bob Realmname") -- no address at all
    equal(#world.sent, 0)
    equal(#world.log, 0, "other players' channel traffic is not logged")
    -- Meant for us: the gift is offered, and the answer goes back by the channel, because that is how it came.
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "@alice-realmname|" .. invitation, "CHANNEL", "Bob Realmname")
    equal(world.last().distribution, "CHANNEL")
    equal(world.last().message, "@bob-realmname|U|link-in-1|1|0")
    assert(world.log[1]:find("received AzerothBinder1 on CHANNEL", 1, true), world.log[1])
    assert(world.log[1]:find("on CHANNEL from bob-realmname: I|link-in-1", 1, true), world.log[1])
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "@alice-realmname|X|link-in-1", "CHANNEL", "Bob Realmname")
    -- Another addon's message on the same channel, or ours in a group chat, is none of our business.
    local count = #world.sent
    emit("CHAT_MSG_ADDON", "SomeoneElse", "@alice-realmname|" .. invitation, "CHANNEL", "Bob Realmname")
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "@alice-realmname|I|link-in-2|npc:639|g", "PARTY", "Bob Realmname")
    equal(#world.sent, count)
    world.finish()
end)

test("a whisper still goes to the same faction, and falls back to the channel only if it could not be sent", function()
    local world = crossWorld({ joined = true, faction = "Horde" })
    ACB.requestBinder("bob-realmname")
    equal(#world.sent, 1)
    equal(world.last().distribution, "WHISPER")
    equal(world.last().target, "Bob Realmname")
    equal(world.last().message, "Q")
    -- A player we cannot see: whisper first; "offline" is a reason to try the channel, a lockdown is not.
    world.results.WHISPER = 12
    local told
    local line = said(function() told = ACB.sendLinked(ACB.viewPrefix, "dan-realmname", "Q") end)
    equal(told, true)
    -- Offline, or on the other side: the player is told which, instead of waiting in silence.
    assert(line:find("offline or unavailable for addon whispers. Trying the cross-faction link too.", 1, true), line)
    equal(said(function() ACB.sendLinked(ACB.viewPrefix, "dan-realmname", "Q") end), "") -- once in a while, not every message
    clock = clock + 61
    assert(said(function() ACB.sendLinked(ACB.viewPrefix, "dan-realmname", "Q") end):find("Trying the cross-faction link", 1, true))
    world.sent = {}
    world.results.WHISPER = 12
    ACB.sendLinked(ACB.viewPrefix, "dan-realmname", "Q")
    equal(world.sent[#world.sent - 1].distribution, "WHISPER")
    equal(world.last().distribution, "CHANNEL")
    equal(world.last().message, "@dan-realmname|Q")
    world.results.WHISPER = 11
    local count = #world.sent
    local ok, why = ACB.sendLinked(ACB.viewPrefix, "dan-realmname", "Q")
    equal(ok, false)
    equal(why, "Forever is blocking addon whispers right now.")
    equal(#world.sent, count + 1) -- only the whisper was tried
    -- Nothing is sent from an instance or in combat, by either route.
    instance = 36
    ok, why = ACB.sendLinked(ACB.viewPrefix, "dan-realmname", "Q")
    instance = 0
    equal(ok, false)
    equal(why, "Trading and sharing are available outdoors and out of combat.")
    equal(#world.sent, count + 1)
    world.finish()
end)

test("when nobody answers, the same message goes both ways for a while, and the second copy is ignored", function()
    local world = crossWorld({ joined = false })
    equal(ACB.forceLink("erin-realmname"), false) -- the link is not connected, so there is nothing to force
    world.joined = true
    equal(ACB.forceLink("erin-realmname"), true)
    equal(ACB.sendLinked(ACB.viewPrefix, "erin-realmname", "Q"), true)
    equal(#world.sent, 2)
    equal(world.sent[1].distribution, "WHISPER")
    equal(world.sent[2].distribution, "CHANNEL")
    -- The answer arrives by both routes: it counts once. A genuine repeat a little later counts again.
    equal(ACB.receiveLinked("erin-realmname", "N|wait", "WHISPER"), "N|wait")
    equal(ACB.receiveLinked("erin-realmname", "@alice-realmname|N|wait", "CHANNEL"), nil)
    clock = clock + 4
    equal(ACB.receiveLinked("erin-realmname", "N|wait", "WHISPER"), "N|wait")
    -- A whisper getting through proves they are on our side: back to whispers only.
    ACB.sendLinked(ACB.viewPrefix, "erin-realmname", "T?")
    equal(world.last().distribution, "WHISPER")
    equal(ACB.forceLink("erin-realmname"), false)
    world.finish()
end)

test("an invitation nobody answers is sent by the channel too, and so is a binder request", function()
    local world = crossWorld({ joined = true }) -- the target's faction is not known
    ACB.startTrade("bob-realmname", "npc:589")
    equal(world.last().distribution, "WHISPER")
    for _ = 1, 2 do eventFrame:OnUpdate(2.1) end
    equal(world.last().distribution, "WHISPER")
    eventFrame:OnUpdate(2.1) -- the third silent resend: try the channel as well
    equal(world.last().distribution, "CHANNEL")
    assert(world.last().message:find("^@bob%-realmname|I|"), world.last().message)
    local id = world.last().message:match("|I|([%w%-]+)|")
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "@alice-realmname|K|" .. id, "CHANNEL", "Bob Realmname")
    -- A binder request that is not answered is asked again, both ways, when the wait is over.
    local first = #timers + 1
    ACB.requestBinder("gina-realmname")
    local count = #world.sent
    for index = first, #timers do timers[index]() end
    equal(world.sent[count + 1].message, "Q")
    equal(world.sent[count + 1].distribution, "WHISPER")
    equal(world.sent[count + 2].distribution, "CHANNEL")
    equal(world.sent[count + 2].message, "@gina-realmname|Q")
    world.finish()
end)

test("with Cross-faction trading off everything stays on whispers, and /acb crossfaction flips the switch", function()
    local world = crossWorld({ joined = true, faction = "Alliance" })
    local saved = AzerothCardBinderDB
    equal(ACB.settingOn(saved, "crossFaction"), true) -- on until switched off
    SlashCmdList.AZEROTHCARDBINDER("crossfaction")
    equal(saved.crossFaction, false)
    assert(ACB.linkStatus():find("^off"), ACB.linkStatus())
    ACB.requestBinder("bob-realmname")
    equal(world.last().distribution, "WHISPER")
    equal(ACB.receiveLinked("bob-realmname", "@alice-realmname|N|wait", "CHANNEL"), nil)
    equal(ACB.forceLink("bob-realmname"), false)
    SlashCmdList.AZEROTHCARDBINDER("crossfaction")
    equal(saved.crossFaction, true)
    assert(ACB.linkStatus():find("connected (channel 7)", 1, true), ACB.linkStatus())
    ACB.requestBinder("bob-realmname")
    equal(world.last().distribution, "CHANNEL")
    world.finish()
end)

test("wanted lists, which now only travel in game, cross factions the same way", function()
    local world = crossWorld({ joined = true, faction = "Alliance" })
    local first = #world.sent
    equal(ACB.requestWanted("bob-realmname"), true)
    equal(#world.sent, first + 1)
    equal(world.last().distribution, "CHANNEL")
    equal(world.last().message, "@bob-realmname|L?")
    -- His answer comes back on the channel, addressed to us, and fills in what he is looking for.
    ACB.heardWanted["bob-realmname"] = nil
    emit("CHAT_MSG_ADDON", ACB.viewPrefix, "@alice-realmname|L|1|c589", "CHANNEL", "Bob Realmname")
    local heard = ACB.heardWanted["bob-realmname"]
    assert(heard, "his wanted list arrived by the channel")
    equal(heard.cards[1], "npc:589")
    -- And asking us works the other way: we answer on the channel.
    emit("CHAT_MSG_ADDON", ACB.viewPrefix, "@alice-realmname|L?", "CHANNEL", "Bob Realmname")
    equal(world.last().distribution, "CHANNEL")
    assert(world.last().message:find("^@bob%-realmname|L|%d+|"), world.last().message)
    ACB.heardWanted["bob-realmname"] = nil
    world.finish()
end)
