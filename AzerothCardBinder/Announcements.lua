local _, ACB = ...

-- Public chat is plain text, so players without the addon can read it too.
local function channel()
    local category = Enum and Enum.PartyCategory and Enum.PartyCategory.Instance or 2
    if ACB.read(ACB.safe(IsInGroup, category), "boolean") == true then return "INSTANCE_CHAT" end
    if ACB.read(ACB.safe(IsInRaid), "boolean") == true then return "RAID" end
    if ACB.read(ACB.safe(IsInGroup), "boolean") == true then return "PARTY" end
    return "SAY"
end

local drafts, order, serial, hooked = {}, {}, 0, false
local commands = { PARTY = "/p ", RAID = "/raid ", INSTANCE_CHAT = "/i ", GUILD = "/g ", SAY = "/s " }
function ACB.openAnnouncementLink(link)
    local id = type(link) == "string" and link:match("^addon:AzerothCardBinder:announce:(%d+)$")
    local draft = id and drafts[tonumber(id)]
    if not draft then return end
    local stamp = ACB.read(ACB.safe(GetTime), "number") or 0
    if stamp > draft.untilAt or (draft.channel ~= "GUILD" and channel() ~= draft.channel) then return end
    if draft.channel == "GUILD" and ACB.read(ACB.safe(GetGuildInfo, "player"), "string") ~= draft.guild then return end
    local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
    if type(open) == "function" then open(commands[draft.channel] .. draft.message) end
end
local function manual(item, stamp, log)
    if not DEFAULT_CHAT_FRAME or not DEFAULT_CHAT_FRAME.AddMessage then log("Card announcement: dungeon chat is restricted; use the card's chat link to share manually."); return end
    serial = serial + 1
    drafts[serial] = { message = item.message, channel = item.channel, guild = item.guild, untilAt = stamp + 900 }
    order[#order + 1] = serial
    if #order > 30 then drafts[table.remove(order, 1)] = nil end
    DEFAULT_CHAT_FRAME:AddMessage(("World of Warcards: Chat is restricted here. |cffffcf77|Haddon:AzerothCardBinder:announce:%d|h[Share this find in %s]|h|r"):format(serial, item.channel:lower()), 1, .82, .35)
end
local function hookDrafts()
    if hooked then return end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) ACB.openAnnouncementLink(link) end, ACB.openAnnouncementLink); hooked = true
    elseif hooksecurefunc then hooked = pcall(hooksecurefunc, "SetItemRef", ACB.openAnnouncementLink) end
end

local rarityRank = { common = 1, rare = 2, epic = 3, legendary = 4 }
local function guild()
    if ACB.read(ACB.safe(IsInGuild), "boolean") ~= true then return end
    return ACB.read(ACB.safe(GetGuildInfo, "player"), "string")
end

function ACB.newCardAnnouncements(saved, log)
    hookDrafts()
    local queue, pending, nextSend = {}, false, 0
    log = log or function() end
    local function now() return ACB.read(ACB.safe(GetTime), "number") or 0 end
    local pump
    local function eligible(item, stamp)
        if item.expires < stamp or not ACB.settingOn(saved, item.setting) then return false end
        if item.channel ~= "GUILD" then return item.channel == channel() end
        if not item.guild or item.guild ~= guild() then return false end
        return not item.rarity or (rarityRank[item.rarity] or 0) >= rarityRank[ACB.guildRarity(saved).key]
    end
    local function later(delay)
        if pending then return true end
        if not C_Timer or not C_Timer.After then return false end
        pending = true
        C_Timer.After(delay, function() pending = false pump() end)
        return true
    end
    pump = function()
        local stamp = now()
        -- A queued find never follows the player into a different kind of chat.
        while queue[1] and not eligible(queue[1], stamp) do table.remove(queue, 1) end
        if not queue[1] then return end
        if stamp < nextSend then
            if not later(nextSend - stamp) then queue = {} end
            return
        end
        if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
            and ACB.read(ACB.safe(C_ChatInfo.InChatMessagingLockdown), "boolean") ~= false then
            local inside, kind = ACB.safe(IsInInstance)
            kind = ACB.read(kind, "string")
            if ACB.read(inside, "boolean") == true and (kind == "party" or kind == "raid") then
                local item = table.remove(queue, 1)
                manual(item, stamp, log)
                if queue[1] and not later(2) then queue = {} end
                return
            end
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
    local function enqueue(message, destination, setting, rarity)
        if not ACB.settingOn(saved, setting) then return end
        local item = { message = message, channel = destination, setting = setting, rarity = rarity, expires = now() + 60 }
        if destination == "GUILD" then item.guild = guild() end
        if not eligible(item, now()) then return end
        if #message > 255 or #queue >= 30 then log("Card announcement: queue or message limit reached.") return end
        queue[#queue + 1] = item
    end
    function announcer:add(card, info)
        if not card or ACB.cards[card.key] ~= card then return end
        local name = card.name:gsub("[%c|]", "") .. (info and info.shiny and " (Shiny)" or "")
        local message = ("World of Warcards: I just added '%s' to my binder."):format(name)
        enqueue(message, channel(), "announceCards")
        enqueue(message, "GUILD", "guildCards", card.rarity)
        pump()
    end
    function announcer:addPack(item)
        if not item or ACB.packItem(item.key) ~= item then return end
        local name = item.name:gsub("[%c|]", "")
        enqueue(("World of Warcards: I just found '%s' (%s)."):format(name, ACB.packTiers[item.tier].name), "GUILD", "guildPacks")
        pump()
    end
    function announcer:clear(setting)
        for index = #queue, 1, -1 do
            if not setting or queue[index].setting == setting then table.remove(queue, index) end
        end
    end
    return announcer
end
