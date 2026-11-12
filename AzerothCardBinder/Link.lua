local _, ACB = ...

-- Other players, and the ways a message can reach one: trades and binder views are addon messages (prefixes in Trade.lua
-- and Social.lua), and this file is where they are addressed, sent and received.
--
-- Whispers do not cross factions. So that Horde and Alliance can still trade, the add-on also joins a quiet chat channel
-- ("WarcardsLink") whose addon messages every player on the realm can receive, and addresses each message to one player
-- ("@name|message"); everyone else's add-on ignores it. A message goes by whisper unless:
--   * you can see they are the other faction (targeted, or focused, or under the mouse): then by the channel;
--   * their last message to you came by the channel: then it goes back the same way;
--   * the whisper failed in a way another route might get round: then by the channel instead;
--   * a trade invitation or a binder request has gone unanswered for a few seconds (ACB.forceLink): then both ways.
-- If a message arrives both ways it is acted on once. The switch is "Cross-faction trading" in Settings.
ACB.linkChannel = "WarcardsLink"
local FRESH, FORCED, DUPLICATE, JOIN_EVERY, JOIN_TRIES, TOLD_EVERY = 600, 300, 3, 10, 6, 60

local read = ACB.read
local saved
local log = function() end
local paths, recent, recentCount = {}, {}, 0 -- per player: how they last reached us, which side they are on; what arrived lately
local joinTries, joinedAt = 0, nil

local function apiValue(expectedType, func, ...)
    if type(func) ~= "function" then return end
    local ok, value = pcall(func, ...)
    if ok then return read(value, expectedType) end
end

local function now() return apiValue("number", GetTime) or 0 end
local function enabled() return saved ~= nil and ACB.settingOn(saved, "crossFaction") end
local function pathOf(peer)
    paths[peer] = paths[peer] or {}
    return paths[peer]
end

-- ---- Names ----

-- A name as used between players: "name-realmname", lower case, or nothing if it is not a character's name.
function ACB.normalizePeer(name)
    name = read(name, "string")
    if not name or #name > 100 then return end
    name = name:match("^%s*(.-)%s*$")
    -- Forever has no realms: a character has two names ("Filfred Whizzlebang"), which the game's own whisper box
    -- shows with a space. Both that and the "Name-Realm" form are accepted, and both become "name-realm" inside.
    local character, realm = name:match("^([^%-]+)%-(.+)$")
    if not character then character, realm = name:match("^(%S+)%s+(%S+)$") end
    if not character then
        character, realm = name, apiValue("string", GetNormalizedRealmName)
    end
    if not realm or character == "" or character:find("[%c%s%p%d]") or realm:find("[%c|]") then return end
    realm = realm:gsub("[%s'%-]", "")
    if realm == "" or realm:find("[%p]") then return end
    return (character .. "-" .. realm):lower()
end

-- This player's own name in the same form.
function ACB.ownPeer()
    local name, realm = UnitFullName("player")
    name, realm = read(name, "string"), read(realm, "string")
    return name and ACB.normalizePeer(realm and realm ~= "" and (name .. "-" .. realm) or name)
end

-- Another player's name, or nothing if the text is not a name or is this player's own.
function ACB.tradePeer(text)
    local peer, own = ACB.normalizePeer(text), ACB.ownPeer()
    if own and peer and peer ~= own then return peer end
end

-- The name the game wants a whisper sent to: "First Second", as its own whisper box shows it (or "First-Second",
-- chosen with /acb whisperform hyphen if that turns out to be what a server needs).
local function whisperTarget(peer)
    if saved and saved.whisperForm == "hyphen" then return peer end
    local first, second = peer:match("^([^%-]+)%-(.+)$")
    if not first then return peer end
    return first:gsub("^%l", string.upper) .. " " .. second:gsub("^%l", string.upper)
end

-- ---- Sending ----

-- What the game said about a send: true, or false and what to tell the player, and whether another route might work.
local function outcome(result)
    local codes = Enum and Enum.SendAddonMessageResult
    if result ~= nil and codes then
        if result == codes.Success then return true end
        if result == codes.AddOnMessageLockdown then return false, "Forever is blocking addon whispers right now." end
        if result == codes.TargetOffline then return false, "That player is offline or unavailable for addon whispers.", true end
        if result == codes.AddonMessageThrottle then return false, "Too many addon whispers. Try again in a moment." end
    end
    if apiValue("boolean", C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == true then
        return false, "This realm is blocking outgoing addon whispers."
    end
    return false, "Addon whisper could not be sent. Check the partner name and retry.", true
end

local function unavailable(prefix)
    if apiValue("boolean", IsInInstance) ~= false or apiValue("boolean", InCombatLockdown) ~= false then
        return "Trading and sharing are available outdoors and out of combat."
    end
    if not C_ChatInfo or type(C_ChatInfo.SendAddonMessage) ~= "function"
        or apiValue("boolean", C_ChatInfo.IsAddonMessagePrefixRegistered, prefix) == false then
        return "Addon whisper registration is unavailable."
    end
end

local function sendWhisper(prefix, peer, message)
    local why = unavailable(prefix)
    if why then return false, why end
    -- The addon whisper result is authoritative. The general chat flags can be unavailable.
    local target = whisperTarget(peer)
    local result = apiValue("number", C_ChatInfo.SendAddonMessage, prefix, message, "WHISPER", target)
    log(("whisper %s to %s (%s): result %s, restricted %s, registered %s"):format(prefix, target, tostring(message):sub(1, 12),
        tostring(result), tostring(apiValue("boolean", C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)),
        tostring(apiValue("boolean", C_ChatInfo.IsAddonMessagePrefixRegistered, prefix))))
    return outcome(result)
end

-- The number the game gave the link channel, once this player has joined it.
local function channelId()
    local id = apiValue("number", GetChannelName, ACB.linkChannel)
    if id and id > 0 then return id end
end

-- Join the link channel (once the game has finished joining the ordinary ones), and try again a few times if it
-- has not worked. It is a temporary channel: it is gone when the player logs out.
function ACB.joinLink()
    if not enabled() or channelId() or joinTries >= JOIN_TRIES or type(JoinTemporaryChannel) ~= "function" then return end
    if joinedAt and now() - joinedAt < JOIN_EVERY then return end
    joinTries, joinedAt = joinTries + 1, now()
    pcall(JoinTemporaryChannel, ACB.linkChannel)
    log("joining " .. ACB.linkChannel .. ", attempt " .. joinTries)
    if C_Timer and C_Timer.After then C_Timer.After(JOIN_EVERY + 1, ACB.joinLink) end
end

local function sendChannel(prefix, peer, message)
    local why = unavailable(prefix)
    if why then return false, why end
    local id = channelId()
    if not id then
        ACB.joinLink()
        return false, "The cross-faction link is not connected yet. Try again in a few seconds."
    end
    local wire = "@" .. peer .. "|" .. message
    if #wire > 255 then return false, "That message is too long for the cross-faction link." end
    local result = apiValue("number", C_ChatInfo.SendAddonMessage, prefix, wire, "CHANNEL", id)
    log(("link %s to %s (%s): result %s, channel %d"):format(prefix, peer, tostring(message):sub(1, 12), tostring(result), id))
    local ok, reason = outcome(result)
    return ok, reason and reason:gsub("whispers", "messages"):gsub("Addon whisper", "Cross-faction message")
end

-- Which side of the war a player is on, if the game will say ("same" or "opposite"); remembered once known.
local function sideOf(peer)
    local path = pathOf(peer)
    if path.side then return path.side end
    local unit = ACB.partnerUnit and ACB.partnerUnit(peer)
    if not unit then return end
    local theirs, mine = apiValue("string", UnitFactionGroup, unit), apiValue("string", UnitFactionGroup, "player")
    if theirs and mine then
        path.side = theirs == mine and "same" or "opposite"
        return path.side
    end
end

-- Send a trade or viewing message to a player by the route that should reach them (see the top of this file).
function ACB.sendLinked(prefix, peer, message)
    if not enabled() then return sendWhisper(prefix, peer, message) end
    local path, at = pathOf(peer), now()
    if sideOf(peer) == "opposite" or (path.inbound == "CHANNEL" and at - path.at < FRESH) then
        return sendChannel(prefix, peer, message)
    end
    if path.forced and at < path.forced then
        local whispered, reason = sendWhisper(prefix, peer, message)
        local linked = sendChannel(prefix, peer, message)
        if whispered or linked then return true end
        return false, reason
    end
    local ok, reason, other = sendWhisper(prefix, peer, message)
    if ok or not other then return ok, reason end
    if sendChannel(prefix, peer, message) then
        -- It may be somebody offline, or somebody on the other side: say what happened, once in a while.
        if not path.told or at - path.told > TOLD_EVERY then
            path.told = at
            ACB.say(reason .. " Trying the cross-faction link too.")
        end
        return true
    end
    return false, reason
end

-- Nothing has come back from this player: send to them both ways for a while. False if that cannot help
-- (the feature is off, the link is not connected, or they are plainly on our side and answering).
function ACB.forceLink(peer)
    if not enabled() or not channelId() then return false end
    local path = pathOf(peer)
    if sideOf(peer) == "same" or path.inbound then return false end
    path.forced = now() + FORCED
    return true
end

-- ---- Receiving ----

-- Every trade or viewing message that arrives goes through here, with how it arrived ("WHISPER" or "CHANNEL"). The
-- result is the message to act on, or nothing: a channel message for someone else, one from ourselves, or the second
-- copy of one that already came by the other route.
function ACB.receiveLinked(peer, message, route, prefix)
    if not peer or type(message) ~= "string" or peer == ACB.ownPeer() then return end
    if route == "CHANNEL" then
        local target, inner = message:match("^@([^|]+)|(.*)$")
        if not enabled() or not target or target ~= ACB.ownPeer() then return end
        message = inner
        -- Only what is addressed to us is logged: everyone else's traffic would push out the loot trace.
        log(("received %s on CHANNEL from %s: %s"):format(tostring(prefix), peer, message:sub(1, 12)))
    end
    local at, path = now(), pathOf(peer)
    path.inbound, path.at = route, at
    if route == "WHISPER" then path.side, path.forced = "same", nil end
    local key = peer .. "|" .. message
    local seen = recent[key]
    if seen and seen.route ~= route and at - seen.at < DUPLICATE then return end
    if recentCount >= 200 then recent, recentCount = {}, 0 end
    if not seen then recentCount = recentCount + 1 end
    recent[key] = { at = at, route = route }
    return message
end

-- ---- Setting up ----

-- A short summary for /acb crossfaction.
function ACB.linkStatus()
    if not enabled() then return "off. Trades and views use whispers only, so they stay on your own faction." end
    local id = channelId()
    return id and ("on, connected (channel " .. id .. ").") or "on, but not connected to the link channel yet."
end

function ACB.initLink(savedVariables, logger)
    saved, log = savedVariables, logger or log
    paths, recent, recentCount, joinTries, joinedAt = {}, {}, 0, 0, nil
    -- The channel's "you joined" notices would only puzzle people.
    local function hideNotice(_, _, ...)
        for index = 1, select("#", ...) do
            local text = read((select(index, ...)), "string")
            if text and text:find(ACB.linkChannel, 1, true) then return true end
        end
    end
    local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if addFilter then
        for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do addFilter(event, hideNotice) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(8, ACB.joinLink) end
end
