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
    print("|cffe8bc6bAzeroth Card Binder|r  " .. message)
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

local function sendTrade(peer, message)
    if apiValue("boolean", IsInInstance) ~= false or apiValue("boolean", InCombatLockdown) ~= false then
        return false, "Trading is available outdoors and out of combat."
    end
    if not C_ChatInfo or apiValue("boolean", C_ChatInfo.IsAddonMessagePrefixRegistered, ACB.tradePrefix) ~= true then
        return false, "Addon whisper registration is unavailable."
    end
    if (C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
        and apiValue("boolean", C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) ~= false)
        or (C_ChatInfo.InChatMessagingLockdown
        and apiValue("boolean", C_ChatInfo.InChatMessagingLockdown) ~= false) then
        return false, "The client is restricting outgoing addon messages."
    end
    local result = apiValue("number", C_ChatInfo.SendAddonMessage, ACB.tradePrefix, message, "WHISPER", peer)
    local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
    if result ~= nil and result == success then return true end
    return false, "Addon whisper could not be sent. Check the partner name and retry."
end

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
    collection = ACB.newCollection(saved, math.random, report, log)
    local sequence = 0
    trade = ACB.newTrade(saved.counts, GetTime, function()
        sequence = sequence + 1
        return ("%d-%d-%d"):format(time(), math.random(1, 999999), sequence)
    end, sendTrade, function(give, take)
        local done = collection:swap(give, take)
        ACB.refresh()
        return done
    end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ACB.tradePrefix)
    end
    for id, skill in pairs(gatherSpells) do
        local name = C_Spell and apiValue("string", C_Spell.GetSpellName, id)
        if name then gatherNames[name] = skill end
    end
    ACB.initUI(saved, trade)
    ACB.initLauncher(saved)
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
        elseif cmd == "trade" or cmd == "index" then
            ACB.open(cmd)
        elseif cmd == "" then
            ACB.open()
        else
            report("/acb opens the binder. Options: index, trade, diag, log, boss.")
        end
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
        if read(prefix, "string") ~= ACB.tradePrefix or read(channel, "string") ~= "WHISPER" then return end
        if apiValue("boolean", IsInInstance) ~= false or apiValue("boolean", InCombatLockdown) ~= false then return end
        if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
            and apiValue("boolean", C_ChatInfo.InChatMessagingLockdown) ~= false then return end
        trade:receive(normalizePeer(sender), read(message, "string"))
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
