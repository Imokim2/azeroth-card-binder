local addonName, ACB = ...
local read = ACB.read
local events = CreateFrame("Frame")
local saved, collection, trade
local readyLoot, gather, pickpocketAt, encounter
local diagnostics = {}
local units = { "target", "mouseover", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
local gatherSpells = { [2575] = "mining", [2366] = "herbalism" }
local gatherNames = {}

local function log(message)
    if not saved.diagnostics then return end
    if #diagnostics == 80 then table.remove(diagnostics, 1) end
    diagnostics[#diagnostics + 1] = ("%7.1f  %s"):format(GetTime(), message)
end

local function report(message)
    print("|cffe8bc6bWorld of Warcards|r  " .. message)
end

local function apiValue(expectedType, func, ...)
    if type(func) ~= "function" then return end
    local ok, value = pcall(func, ...)
    if ok then return read(value, expectedType) end
end

local function observeUnit(unit)
    local guid = apiValue("string", UnitGUID, unit)
    if not ACB.source(guid) then return end
    return guid, apiValue("boolean", UnitIsDeadOrGhost, unit), apiValue("string", UnitClassification, unit)
end

local function scanSlot(snapshot, ok, ...)
    if not ok then
        snapshot.unreadable = snapshot.unreadable + 1
        return
    end
    for index = 1, select("#", ...), 2 do
        local guid = read(select(index, ...), "string")
        local card = ACB.source(guid)
        if card then
            snapshot.sources[guid] = card
        elseif not guid then
            snapshot.unreadable = snapshot.unreadable + 1
        else
            snapshot.other = snapshot.other + 1
        end
    end
end

local function scanLoot(snapshot)
    snapshot.unreadable, snapshot.other = 0, 0
    snapshot.slots = apiValue("number", GetNumLootItems) or 0
    if type(GetLootSourceInfo) == "function" then
        for slot = 1, snapshot.slots do scanSlot(snapshot, pcall(GetLootSourceInfo, slot)) end
    end
    for _, unit in ipairs(units) do
        local guid, dead, rank = observeUnit(unit)
        if guid and snapshot.sources[guid] then
            if dead ~= nil then snapshot.dead[guid] = dead end
            if rank then snapshot.rank[guid] = rank end
        end
    end
end

local function newSnapshot()
    return { at = GetTime(), sources = {}, dead = {}, rank = {} }
end

local function finishGather()
    if not gather or not gather.finished or not gather.node or gather.used then return end
    if math.abs(gather.finished - gather.nodeAt) > 2 then return end
    gather.used = true
    collection:roll(gather.node, "gather")
    ACB.refresh()
end

local function matchGather(guid, card, at)
    if collection.rolled[guid] then
        log("Already rolled: " .. card.name .. " (gather)")
        return
    end
    if not gather or gather.skill ~= card.profession or at < gather.started or at - gather.started > 12 then
        log("Gathering skipped: no matching player cast for " .. card.name)
        return
    end
    if not gather.used and gather.node and gather.node ~= guid then
        gather.used = true
        log("Gathering skipped: multiple nodes for one cast")
        return
    end
    gather.node, gather.nodeAt = guid, at
    finishGather()
end

local function lootOpened(fromItem)
    local snapshot = readyLoot or newSnapshot()
    readyLoot = nil
    local readySlots, readyUnreadable = snapshot.slots or 0, snapshot.unreadable or 0
    scanLoot(snapshot)
    if fromItem ~= false then
        log("LOOT_OPENED: item container or unreadable origin")
        return
    end
    local candidates, node, nodeCount = 0, nil, 0
    local pickpocket = pickpocketAt and GetTime() - pickpocketAt < 2
    for guid, card in pairs(snapshot.sources) do
        candidates = candidates + 1
        if card.profession then
            node, nodeCount = guid, nodeCount + 1
        elseif not pickpocket and snapshot.dead[guid] ~= false then
            collection:roll(guid, "loot", snapshot.rank[guid])
        else
            log("Creature skipped: living source or recent Pick Pocket")
        end
    end
    if nodeCount == 1 then
        matchGather(node, snapshot.sources[node], snapshot.at)
    elseif nodeCount > 1 then
        log("Gathering skipped: multiple nodes in loot")
    end
    log(("LOOT_OPENED: ready=%d open=%d catalog=%d unreadable=%d other=%d"):format(
        readySlots, snapshot.slots, candidates, readyUnreadable + snapshot.unreadable, snapshot.other))
    ACB.refresh()
end

local function spellEvent(event, unit, castGUID, spellID)
    if read(unit, "string") ~= "player" then return end
    local spell = read(spellID, "number")
    if not spell then
        log(event .. ": unreadable player spell")
        return
    end
    if spell == 921 then
        if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_SENT" then pickpocketAt = GetTime() end
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then return end
    local name = not gatherSpells[spell] and C_Spell and apiValue("string", C_Spell.GetSpellName, spell)
    local skill = gatherSpells[spell] or (name and gatherNames[name])
    local cast = read(castGUID, "string")
    if not skill then return end
    log(("%s: %s (%d), cast token %s"):format(event, skill, spell, cast and "readable" or "unreadable"))
    if not cast then return end
    if event == "UNIT_SPELLCAST_START" then
        gather = { skill = skill, cast = cast, started = GetTime() }
    elseif gather and gather.cast == cast and gather.skill == skill then
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            gather.finished = GetTime()
            finishGather()
        else
            gather = nil
        end
    end
end

local function inDeadmines()
    if type(GetInstanceInfo) ~= "function" then return false end
    local ok, _, kind, _, _, _, _, _, id = pcall(GetInstanceInfo)
    return ok and read(kind, "string") == "party" and read(id, "number") == 36
end

local function watchBoss()
    if not encounter then return end
    for _, unit in ipairs(units) do
        local guid, dead, rank = observeUnit(unit)
        if dead == false and ACB.source(guid) == ACB.cards["npc:639"] then
            if encounter.guid and encounter.guid ~= guid then encounter.ambiguous = true end
            encounter.guid, encounter.rank = guid, rank or encounter.rank
        end
    end
end

local function encounterEvent(event, id, name, difficulty, success)
    if not inDeadmines() then encounter = nil return end
    id, name, difficulty, success = read(id, "number"), read(name, "string"),
        read(difficulty, "number"), read(success, "number")
    log(("%s: encounter=%s success=%s%s"):format(event, tostring(id), tostring(success),
        name == "Edwin VanCleef" and " (VanCleef)" or ""))
    if event == "ENCOUNTER_START" then
        encounter = nil
        if id and id > 0 and difficulty and name == "Edwin VanCleef" then
            encounter = { id = id, difficulty = difficulty }
            watchBoss()
        end
        return
    end
    local attempt = encounter
    encounter = nil
    if not attempt or id ~= attempt.id or difficulty ~= attempt.difficulty or name ~= "Edwin VanCleef" or success ~= 1 then
        return
    end
    local matchedCorpse = false
    if attempt.guid and not attempt.ambiguous then
        for _, unit in ipairs(units) do
            local guid, dead = observeUnit(unit)
            if guid == attempt.guid and dead == true then matchedCorpse = true break end
        end
    end
    if not matchedCorpse or apiValue("boolean", UnitIsDeadOrGhost, "player") ~= false then
        log("VanCleef completion skipped: no matching readable corpse or player dead")
    elseif saved.bossTrial then
        collection:roll(attempt.guid, "encounter", attempt.rank)
        ACB.refresh()
    else
        log("VanCleef completion eligible (trial disabled)")
    end
end

local function normalizePeer(name)
    name = read(name, "string")
    if not name or #name > 100 then return end
    name = name:match("^%s*(.-)%s*$")
    local character, realm = name:match("^([^%-]+)%-(.+)$")
    if not character then
        character, realm = name, apiValue("string", GetNormalizedRealmName)
    end
    if not realm or character == "" or character:find("[%c%s%p%d]") or realm:find("[%c|]") then return end
    realm = realm:gsub("[%s'%-]", "")
    if realm == "" or realm:find("[%p]") then return end
    return (character .. "-" .. realm):lower()
end

local function sendAddon(prefix, peer, message)
    if apiValue("boolean", IsInInstance) ~= false or apiValue("boolean", InCombatLockdown) ~= false then
        return false, "Trading and sharing are available outdoors and out of combat."
    end
    if not C_ChatInfo or apiValue("boolean", C_ChatInfo.IsAddonMessagePrefixRegistered, prefix) ~= true then
        return false, "Addon whisper registration is unavailable."
    end
    if (C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
        and apiValue("boolean", C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) ~= false)
        or (C_ChatInfo.InChatMessagingLockdown
        and apiValue("boolean", C_ChatInfo.InChatMessagingLockdown) ~= false) then
        return false, "The client is restricting outgoing addon messages."
    end
    local result = apiValue("number", C_ChatInfo.SendAddonMessage, prefix, message, "WHISPER", peer)
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
    if result ~= nil and result == success then return true end
    return false, "Addon whisper could not be sent. Check the partner name and retry."
end

local function sendTrade(peer, message) return sendAddon(ACB.tradePrefix, peer, message) end
local function sendView(peer, message) return sendAddon(ACB.viewPrefix, peer, message) end

function ACB.tradePeer(text)
    local peer = normalizePeer(text)
    local name, realm = UnitFullName("player")
    name, realm = read(name, "string"), read(realm, "string")
    local own = name and normalizePeer(realm and realm ~= "" and (name .. "-" .. realm) or name)
    if own and peer and peer ~= own then return peer end
end

local function tableOrEmpty(value)
    return type(value) == "table" and value or {}
end

local function initialize()
    saved = tableOrEmpty(AzerothCardBinderDB)
    AzerothCardBinderDB = saved
    saved.counts, saved.achievements = tableOrEmpty(saved.counts), tableOrEmpty(saved.achievements)
    saved.levels = nil -- levels were shown on cards in an earlier build and are no longer kept
    for key, count in pairs(saved.counts) do
        if type(count) ~= "number" or count < 1 or count > 1000000000 or count ~= math.floor(count) then
            saved.counts[key] = nil
        end
    end
    saved.misses = tableOrEmpty(saved.misses)
    for key, value in pairs(saved.misses) do
        if type(value) ~= "number" or value < 1 or value ~= math.floor(value) or not ACB.cards[key] then
            saved.misses[key] = nil
        end
    end
    saved.shiny = tableOrEmpty(saved.shiny)
    for key, value in pairs(saved.shiny) do
        if value ~= true or not ACB.cards[key] then saved.shiny[key] = nil end
    end
    saved.wanted, saved.history = tableOrEmpty(saved.wanted), tableOrEmpty(saved.history)
    for key, value in pairs(saved.wanted) do
        if value ~= true or not ACB.cards[key] then saved.wanted[key] = nil end
    end
    for index = #saved.history, 1, -1 do
        local entry = saved.history[index]
        if type(entry) ~= "table" or not ACB.cards[entry.give] or not ACB.cards[entry.take] then
            table.remove(saved.history, index)
        end
    end
    if type(saved.dust) ~= "number" or saved.dust < 0 or saved.dust ~= math.floor(saved.dust) then saved.dust = 0 end
    saved.sets, saved.titles = tableOrEmpty(saved.sets), tableOrEmpty(saved.titles)
    for key, value in pairs(saved.sets) do
        if value ~= true then saved.sets[key] = nil end
    end
    for key, value in pairs(saved.titles) do
        if value ~= true or type(key) ~= "string" then saved.titles[key] = nil end
    end
    if type(saved.title) ~= "string" or not saved.titles[saved.title] then saved.title = nil end
    collection = ACB.newCollection(saved, math.random, report, log, function(card, info)
        if ACB.showToast then ACB.showToast(card, info) end
    end, function(page, reward)
        if ACB.showSetToast then ACB.showSetToast(page, reward) end
        if ACB.refresh then ACB.refresh() end
    end)
    ACB.collection = collection
    local sequence = 0
    trade = ACB.newTrade(saved.counts, GetTime, function()
        sequence = sequence + 1
        return ("%d-%d-%d"):format(time(), math.random(1, 999999), sequence)
    end, sendTrade, function(give, take, peer)
        local done = collection:swap(give, take)
        if done then ACB.logTrade(saved, give, take, peer, time()) end
        ACB.refresh()
        return done
    end, function() return ACB.wantedCards(saved) end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ACB.tradePrefix)
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ACB.viewPrefix)
    end
    for id, skill in pairs(gatherSpells) do
        local name = C_Spell and apiValue("string", C_Spell.GetSpellName, id)
        if name then gatherNames[name] = skill end
    end
    ACB.initUI(saved, trade)
    ACB.initLauncher(saved)
    ACB.initToast(saved)
    ACB.initHints(saved)
    ACB.initSocial(saved, sendView, GetTime, function(delay, action)
        if delay <= 0 or not C_Timer then action() else C_Timer.After(delay, action) end
    end)
    SLASH_AZEROTHCARDBINDER1, SLASH_AZEROTHCARDBINDER2 = "/acb", "/cardbinder"
    SlashCmdList.AZEROTHCARDBINDER = function(message)
        local cmd = message:lower():match("^%s*(.-)%s*$")
        if cmd == "diag" then
            saved.diagnostics = not saved.diagnostics
            log("Diagnostics on. Client " .. (GetBuildInfo()))
            report("Diagnostics " .. (saved.diagnostics and "on. Use /acb log to copy." or "off."))
        elseif cmd == "log" then
            ACB.showLog(table.concat(diagnostics, "\n"), saved.diagnostics)
        elseif cmd == "boss" then
            saved.bossTrial = not saved.bossTrial
            report("VanCleef completion trial " .. (saved.bossTrial and "on." or "off."))
        elseif cmd == "title" or cmd:match("^title ") then
            local choice = cmd:match("^title%s+(.+)$")
            local earned = ACB.earnedTitles(saved)
            if choice == "off" then
                saved.title = nil
                report("Title cleared.")
            elseif choice and earned[tonumber(choice) or 0] then
                saved.title = earned[tonumber(choice)]
                report("Title set to " .. saved.title .. ".")
            elseif #earned == 0 then
                report("Finish a set to earn a title.")
            else
                for number, title in ipairs(earned) do
                    report(("%d. %s%s"):format(number, title, title == saved.title and " (shown)" or ""))
                end
                report("Use /acb title <number> to show one, or /acb title off.")
            end
            if ACB.refresh then ACB.refresh() end
        elseif cmd:match("^link%s+%S") then
            local card = ACB.findCard(saved, message:match("^%s*%S+%s+(.-)%s*$"))
            if card then ACB.linkCard(saved, card) else report("You do not own a card with that name.") end
        elseif cmd:match("^view%s+%S") then
            local peer = ACB.tradePeer(message:match("^%s*%S+%s+(%S+)"))
            local ok, reason = ACB.requestBinder(peer)
            report(ok and "Asked for their binder. It opens when they answer." or (reason or "Enter another player's name."))
        elseif cmd == "privacy" then
            saved.inspectable = saved.inspectable == false
            report("Other players " .. (saved.inspectable == false and "can no longer" or "can now") .. " view your binder.")
        elseif cmd == "hints" then
            saved.hints = saved.hints == false
            report("Tooltip hints " .. (saved.hints == false and "off." or "on."))
        elseif cmd == "dust" then
            report(("Binder Dust: %d. Open a card in the binder to recycle a spare or craft a missing card."):format(saved.dust or 0))
        elseif cmd == "settings" or cmd == "options" then
            ACB.open("settings")
        elseif cmd == "popup" then
            saved.popups = saved.popups == false
            report("Card pop-ups " .. (saved.popups == false and "off." or "on."))
        elseif cmd == "popup test" then
            local demo = ACB.cards["npc:639"]
            if saved.popups == false then
                report("Card pop-ups are off. Use /acb popup to turn them on.")
            else
                ACB.showToast(demo, { count = 1, first = true, shiny = true })
            end
        elseif cmd == "trade" or cmd == "index" then
            local unit = cmd == "trade" and apiValue("boolean", UnitIsPlayer, "target") == true
            local name, realm
            if unit then name, realm = UnitFullName("target") end
            name, realm = read(name, "string"), read(realm, "string")
            if name and ACB.prepareTrade then
                ACB.prepareTrade(realm and realm ~= "" and (name .. "-" .. realm) or name)
            else
                ACB.open(cmd)
            end
        elseif cmd:match("^trade%s+%S") then
            ACB.prepareTrade(message:match("^%s*%S+%s+(%S+)"))
        elseif cmd == "" then
            ACB.open()
        else
            report("/acb opens the binder. Options: index, trade, link, view, settings, dust, privacy, title, popup, popup test, hints, diag, log, boss.")
        end
        if ACB.refresh then ACB.refresh() end -- a switch may have changed on the Settings tab
    end
end

local handlers = {
    LOOT_READY = function()
        readyLoot = newSnapshot()
        scanLoot(readyLoot)
        log(("LOOT_READY: slots=%d unreadable=%d"):format(readyLoot.slots, readyLoot.unreadable))
    end,
    LOOT_OPENED = function(_, fromItem) lootOpened(read(fromItem, "boolean")) end,
    LOOT_CLOSED = function()
        local closing = readyLoot
        -- Autoloot can close the window before this frame receives LOOT_OPENED.
        C_Timer.After(0, function()
            if readyLoot == closing then readyLoot = nil end
        end)
    end,
    UNIT_SPELLCAST_SENT = function(unit, _, castGUID, spellID)
        spellEvent("UNIT_SPELLCAST_SENT", unit, castGUID, spellID)
    end,
    ENCOUNTER_START = function(id, name, difficulty) encounterEvent("ENCOUNTER_START", id, name, difficulty) end,
    ENCOUNTER_END = function(id, name, difficulty, _, success)
        encounterEvent("ENCOUNTER_END", id, name, difficulty, success)
    end,
    BOSS_KILL = function(id)
        if inDeadmines() then log("BOSS_KILL: encounter=" .. tostring(read(id, "number"))) end
    end,
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = watchBoss,
    PLAYER_TARGET_CHANGED = watchBoss,
    UPDATE_MOUSEOVER_UNIT = watchBoss,
    PLAYER_FOCUS_CHANGED = watchBoss,
    PLAYER_ENTERING_WORLD = function() readyLoot, gather, pickpocketAt, encounter = nil, nil, nil, nil end,
    CHAT_MSG_ADDON = function(prefix, message, channel, sender)
        local kind = read(prefix, "string")
        if (kind ~= ACB.tradePrefix and kind ~= ACB.viewPrefix) or read(channel, "string") ~= "WHISPER" then return end
        if apiValue("boolean", IsInInstance) ~= false or apiValue("boolean", InCombatLockdown) ~= false then return end
        if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
            and apiValue("boolean", C_ChatInfo.InChatMessagingLockdown) ~= false then return end
        if kind == ACB.tradePrefix then
            trade:receive(normalizePeer(sender), read(message, "string"))
        else
            ACB.receiveView(normalizePeer(sender), read(message, "string"))
        end
        ACB.refresh()
    end,
}
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    handlers[event] = function(...) spellEvent(event, ...) end
end

events:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if read((...), "string") ~= addonName then return end
        initialize()
        self:UnregisterEvent("ADDON_LOADED")
        for name in pairs(handlers) do
            local ok
            if name:match("^UNIT_SPELLCAST_") then
                ok = pcall(self.RegisterUnitEvent, self, name, "player")
            else
                ok = pcall(self.RegisterEvent, self, name)
            end
            if not ok then log("Event unavailable: " .. name) end
        end
        log("Loaded. Client " .. (GetBuildInfo()))
    else
        handlers[event](...)
    end
end)
events:RegisterEvent("ADDON_LOADED")
