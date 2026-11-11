local addonName, ACB = ...
local read = ACB.read
local events = CreateFrame("Frame")
local saved, collection, trade, kills
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
    if not ok or select("#", ...) == 0 then
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
            if guid:match("^Item%-") then snapshot.itemSource = true end
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

local function rollLoot(snapshot, event, readySlots, readyUnreadable)
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
    log(("%s: ready=%d slots=%d catalog=%d unreadable=%d other=%d"):format(
        event, readySlots, snapshot.slots, candidates, readyUnreadable + snapshot.unreadable, snapshot.other))
    ACB.refresh()
end

local function lootOpened(fromItem)
    local snapshot = readyLoot or newSnapshot()
    readyLoot = nil
    if fromItem ~= false then
        log("LOOT_OPENED: item container or unreadable origin")
        return
    end
    local readySlots, readyUnreadable = snapshot.slots or 0, snapshot.unreadable or 0
    scanLoot(snapshot)
    rollLoot(snapshot, "LOOT_OPENED", readySlots, readyUnreadable)
end

local function lootReady()
    local snapshot = newSnapshot()
    readyLoot = snapshot
    scanLoot(snapshot)
    log(("LOOT_READY: slots=%d unreadable=%d"):format(snapshot.slots, snapshot.unreadable))
    -- Auto-loot can supply sources here and never send LOOT_OPENED to the addon.
    -- Give the explicit origin flag a chance to arrive before using the ready snapshot.
    C_Timer.After(0.4, function()
        if readyLoot ~= snapshot then return end
        readyLoot = nil
        if snapshot.itemSource then
            log("LOOT_READY fallback: item container")
            return
        end
        rollLoot(snapshot, "LOOT_READY fallback", snapshot.slots, 0)
    end)
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

-- The name the game wants a whisper sent to: "First Second", as its own whisper box shows it (or "First-Second",
-- chosen with /acb whisperform hyphen if that turns out to be what a server needs).
local function whisperTarget(peer)
    if saved and saved.whisperForm == "hyphen" then return peer end
    local first, second = peer:match("^([^%-]+)%-(.+)$")
    if not first then return peer end
    return first:gsub("^%l", string.upper) .. " " .. second:gsub("^%l", string.upper)
end

local function sendAddon(prefix, peer, message)
    if apiValue("boolean", IsInInstance) ~= false or apiValue("boolean", InCombatLockdown) ~= false then
        return false, "Trading and sharing are available outdoors and out of combat."
    end
    if not C_ChatInfo or type(C_ChatInfo.SendAddonMessage) ~= "function"
        or apiValue("boolean", C_ChatInfo.IsAddonMessagePrefixRegistered, prefix) == false then
        return false, "Addon whisper registration is unavailable."
    end
    -- The addon whisper result is authoritative. The general chat flags can be unavailable.
    local target = whisperTarget(peer)
    local result = apiValue("number", C_ChatInfo.SendAddonMessage, prefix, message, "WHISPER", target)
    log(("whisper %s to %s (%s): result %s, restricted %s, registered %s"):format(prefix, target, tostring(message):sub(1, 12),
        tostring(result), tostring(apiValue("boolean", C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)),
        tostring(apiValue("boolean", C_ChatInfo.IsAddonMessagePrefixRegistered, prefix))))
    local codes = Enum and Enum.SendAddonMessageResult
    if result ~= nil and codes then
        if result == codes.Success then return true end
        if result == codes.AddOnMessageLockdown then return false, "Forever is blocking addon whispers right now." end
        if result == codes.TargetOffline then return false, "That player is offline or unavailable for addon whispers." end
        if result == codes.AddonMessageThrottle then return false, "Too many addon whispers. Try again in a moment." end
    end
    if apiValue("boolean", C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == true then
        return false, "This realm is blocking outgoing addon whispers."
    end
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

local function initialize()
    saved = ACB.tableOrEmpty(AzerothCardBinderDB)
    AzerothCardBinderDB = saved
    local _, upgraded = ACB.cleanSavedData(saved)
    local ledger = ACB.newLedger(saved, time, ACB.characterName)
    ledger:begin(upgraded)
    -- Events the server has stored are dropped, but never from a binder that fails its check.
    if ledger:check() then
        ledger:prune(ACB.sync and ACB.sync.acks)
        ACB.resumeRanked(saved, ledger)
        ACB.pruneReports(saved, ACB.sync and ACB.sync.reportsDone)
    end
    ACB.ledger = ledger
    collection = ACB.newCollection(saved, math.random, report, log, function(card, info)
        if ACB.showToast then ACB.showToast(card, info) end
        if ACB.refreshZoneBar then ACB.refreshZoneBar() end
    end, function(page, reward)
        if ACB.showSetToast then ACB.showSetToast(page, reward) end
        if ACB.refresh then ACB.refresh() end
    end, ledger)
    ACB.collection = collection
    -- Kills with nothing to loot (critters and the like): see Kills.lua.
    kills = ACB.newKillWatcher(collection, {
        now = GetTime, units = { "target", "mouseover", "focus" }, log = log,
        after = function(delay, action) if C_Timer then C_Timer.After(delay, action) end end,
        guidOf = function(unit)
            local guid = apiValue("string", UnitGUID, unit)
            if ACB.source(guid) then return guid end
        end,
        isDead = function(unit) return apiValue("boolean", UnitIsDeadOrGhost, unit) == true end,
        rank = function(unit) return apiValue("string", UnitClassification, unit) end,
        tapDenied = function(unit) return apiValue("boolean", UnitIsTapDenied, unit) == true end,
        inCombat = function() return apiValue("boolean", UnitAffectingCombat, "player") == true end,
        enabled = function() return ACB.settingOn(saved, "killRolls") end,
        refresh = function() if ACB.refresh then ACB.refresh() end end,
    })
    collection:restoreAchievements()
    if not ACB.isBinderTitle(saved.title) or not saved.titles[saved.title] then saved.title = nil end
    local sequence = 0
    trade = ACB.newTrade(saved.counts, GetTime, function()
        sequence = sequence + 1
        return ("%d-%d-%d"):format(time(), math.random(1, 999999), sequence)
    end, sendTrade, function(give, take, peer, tradeId)
        local done = collection:swap(give, take, peer, tradeId)
        if done then ACB.logTrade(saved, give, take, peer, time(), report) end
        ACB.refresh()
        return done
    end, function() return ACB.wantedCards(saved) end, function(peer) return ACB.tradeDistanceOk(saved, peer) end)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ACB.tradePrefix)
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ACB.viewPrefix)
    end
    for id, skill in pairs(gatherSpells) do
        local name = C_Spell and apiValue("string", C_Spell.GetSpellName, id)
        if name then gatherNames[name] = skill end
    end
    ACB.initUI(saved, trade)
    ACB.initPacks(saved, collection)
    ACB.initLauncher(saved)
    ACB.initToast(saved)
    ACB.initHints(saved)
    ACB.initZoneBar(saved)
    ACB.initSocial(saved, sendView, GetTime, function(delay, action)
        if delay <= 0 or not C_Timer then action() else C_Timer.After(delay, action) end
    end, report)
    ACB.initSlash(saved, { report = report, log = log, diagnostics = diagnostics, apiValue = apiValue })
end

local handlers = {
    LOOT_READY = lootReady,
    LOOT_OPENED = function(_, fromItem) lootOpened(read(fromItem, "boolean")) end,
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
    PLAYER_TARGET_CHANGED = function() watchBoss() if kills then kills:look() end end,
    PLAYER_REGEN_DISABLED = function() if kills then kills:combatChanged() end end,
    PLAYER_REGEN_ENABLED = function() if kills then kills:combatChanged() end end,
    UPDATE_MOUSEOVER_UNIT = watchBoss,
    PLAYER_FOCUS_CHANGED = watchBoss,
    PLAYER_ENTERING_WORLD = function()
        readyLoot, gather, pickpocketAt, encounter = nil, nil, nil, nil
        if kills then kills:reset() end
    end,
    CHAT_MSG_ADDON = function(prefix, message, channel, sender)
        local kind = read(prefix, "string")
        -- Any addon whisper is logged, ours or another addon's: it shows whether this game delivers them at all.
        if kind == ACB.tradePrefix or kind == ACB.viewPrefix or read(channel, "string") == "WHISPER" then
            log(("received %s on %s from %s: %s"):format(tostring(kind), tostring(read(channel, "string")),
                tostring(read(sender, "string")), tostring(read(message, "string")):sub(1, 12)))
        end
        if (kind ~= ACB.tradePrefix and kind ~= ACB.viewPrefix) or read(channel, "string") ~= "WHISPER" then return end
        if apiValue("boolean", IsInInstance) ~= false or apiValue("boolean", InCombatLockdown) ~= false then
            log("ignored: in an instance or in combat")
            return
        end
        if kind == ACB.tradePrefix then
            trade:receive(normalizePeer(sender), read(message, "string"))
            ACB.refresh()
        else
            ACB.receiveView(normalizePeer(sender), read(message, "string"))
        end
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
