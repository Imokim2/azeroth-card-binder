local _, ACB = ...

-- Public chat is plain text, so players without the addon can read it too.
local function channel()
    local category = Enum and Enum.PartyCategory and Enum.PartyCategory.Instance or 2
    if ACB.read(ACB.safe(IsInGroup, category), "boolean") == true then return "INSTANCE_CHAT" end
    if ACB.read(ACB.safe(IsInRaid), "boolean") == true then return "RAID" end
    if ACB.read(ACB.safe(IsInGroup), "boolean") == true then return "PARTY" end
    return "SAY"
end

function ACB.newCardAnnouncements(saved, log)
    local queue, pending, nextSend = {}, false, 0
    log = log or function() end
    local function now() return ACB.read(ACB.safe(GetTime), "number") or 0 end
    local pump
    local function later(delay)
        if pending then return true end
        if not C_Timer or not C_Timer.After then return false end
        pending = true
        C_Timer.After(delay, function() pending = false pump() end)
        return true
    end
    pump = function()
        if not ACB.settingOn(saved, "announceCards") then queue = {} return end
        local stamp, destination = now(), channel()
        -- A queued find never follows the player into a different kind of chat.
        while queue[1] and (queue[1].expires < stamp or queue[1].channel ~= destination) do table.remove(queue, 1) end
        if not queue[1] then return end
        if stamp < nextSend then
            if not later(nextSend - stamp) then queue = {} end
            return
        end
        if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
            and ACB.read(ACB.safe(C_ChatInfo.InChatMessagingLockdown), "boolean") ~= false then
            if not later(2) then queue = {} end
            return
        end
        local item = table.remove(queue, 1)
        local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
        if type(send) ~= "function" then queue = {} log("Card announcement: chat API unavailable.") return end
        local ok, result = pcall(send, item.message, item.channel)
        -- Never retry a refused send or switch channels to get around a client restriction.
        if not ok or result == false then log("Card announcement: client refused public chat.") end
        nextSend = stamp + 2
        if queue[1] and not later(2) then queue = {} end
    end
    local announcer = {}
    function announcer:add(card, info)
        if not ACB.settingOn(saved, "announceCards") then queue = {} return end
        if not card or ACB.cards[card.key] ~= card then return end
        local name = card.name:gsub("[%c|]", "") .. (info and info.shiny and " (Shiny)" or "")
        local message = ("World of Warcards: I just added '%s' to my binder."):format(name)
        if #message > 255 or #queue >= 30 then log("Card announcement: queue or message limit reached.") return end
        queue[#queue + 1] = { message = message, channel = channel(), expires = now() + 60 }
        pump()
    end
    function announcer:clear() queue = {} end
    return announcer
end
