-- Run from the source folder with Lua 5.1: lua tests/run.lua
local addon = "AzerothCardBinder"
local ACB = {}
local function loadAddon(file)
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end

local passed = 0
local function test(name, run)
    local ok, err = xpcall(run, debug.traceback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end

local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function guid(id, token, kind)
    return ("%s-0-session-36-4-%d-%s"):format(kind or "Creature", id, (token:gsub("-", "_")))
end

local function ignore() end
loadAddon("Catalog.lua")
loadAddon("Collection.lua")
loadAddon("Trade.lua")

for _, rate in ipairs({
    { id = 589, limit = 50, rank = "normal" },
    { id = 639, limit = 100, rank = "elite" },
    { id = 573, limit = 500, rank = "rare" },
    { id = 3586, limit = 500, rank = "rareelite" },
}) do
    test(rate.rank .. " exact odds and no reroll after miss", function()
        local saved = { counts = {}, achievements = {} }
        local rolls, draws = 0, { rate.limit, rate.limit + 1 }
        local collection = ACB.newCollection(saved, function(min, max)
            equal(min, 1)
            equal(max, 10000)
            rolls = rolls + 1
            return draws[rolls]
        end, ignore, ignore)
        equal(collection:roll(guid(rate.id, "A"), "loot"), true)
        equal(collection:roll(guid(rate.id, "A"), "loot"), nil)
        equal(collection:roll(guid(rate.id, "B"), "loot"), false)
        equal(collection:roll(guid(rate.id, "B"), "loot"), nil)
        equal(rolls, 2)
        equal(saved.counts["npc:" .. rate.id], 1)
    end)
end

test("distinct NPC and object identities; only catalog sources roll", function()
    equal(ACB.source(guid(589, "A")).key, "npc:589")
    equal(ACB.source(guid(589, "B")).key, "npc:589")
    equal(ACB.source(guid(1731, "A", "GameObject")).key, "node:1731")
    equal(ACB.source(guid(589, "B", "Pet")), nil)
    equal(ACB.source(guid(589, "B", "GameObject")), nil)
    equal(ACB.source(guid(1, "A")), nil)
    equal(ACB.source("Creature-589"), nil)
end)

test("duplicates do not fill slots; both Deadmines achievements unlock once", function()
    local saved = { counts = {}, achievements = {} }
    local earned = 0
    local collection = ACB.newCollection(saved, function() return 1 end, function(message)
        if message:match("^Binder achievement") then earned = earned + 1 end
    end, ignore)
    for _, card in ipairs(ACB.pages[1].cards) do
        if card.boss then collection:roll(guid(tonumber(card.key:sub(5)), "A"), "loot") end
    end
    collection:roll(guid(639, "B"), "loot")
    local owned, total = ACB.progress(saved.counts, 1)
    equal(owned, 8)
    equal(total, 12)
    equal(saved.counts["npc:639"], 2)
    equal(saved.achievements.crew, true)
    equal(saved.achievements.deadmines, nil)
    for _, card in ipairs(ACB.pages[1].cards) do
        if not card.boss then collection:roll(guid(tonumber(card.key:sub(5)), "A"), "loot") end
    end
    collection:roll(guid(639, "C"), "loot")
    equal(saved.achievements.deadmines, true)
    equal(earned, 2)
end)

test("gathering nodes carry a model file", function()
    equal(ACB.cards["node:1731"].model, 219514)
    equal(ACB.cards["node:1618"].model, 219481)
    for _, card in pairs(ACB.cards) do
        if card.profession then equal(type(card.model), "number") end
    end
end)

test("rarity follows boss, elite, normal and profession rules", function()
    local expected = {
        ["npc:644"] = "legendary", ["npc:3586"] = "legendary", ["npc:639"] = "legendary",
        ["npc:657"] = "epic", ["npc:573"] = "epic", ["npc:589"] = "common",
        ["npc:114"] = "common", ["node:1731"] = "rare", ["node:1618"] = "rare",
    }
    for key, rarity in pairs(expected) do equal(ACB.cards[key].rarity, rarity) end
    for key, card in pairs(ACB.cards) do
        assert(ACB.rarities[card.rarity], key .. " has no rarity")
        assert(ACB.zones[card.zone], key .. " has no zone")
        assert(#card.lore > 0 and #card.lore <= 80, key .. " lore length " .. #card.lore)
    end
end)

test("capture stores only a readable monster level", function()
    local saved = { counts = {}, achievements = {} }
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore)
    collection:roll(guid(589, "A"), "loot", nil, 17)
    equal(saved.levels["npc:589"], 17)
    collection:roll(guid(589, "B"), "loot", nil, -1)
    equal(saved.levels["npc:589"], -1)
    collection:roll(guid(589, "C"), "loot", nil, 0)
    collection:roll(guid(589, "D"), "loot", nil, 2.5)
    collection:roll(guid(589, "E"), "loot", nil, "9")
    equal(saved.levels["npc:589"], -1)
    equal(saved.counts["npc:589"], 5)
end)

test("two peers confirm the exact immutable pair without mutating collection", function()
    local aCards, bCards = { ["npc:589"] = 2 }, { ["npc:639"] = 2 }
    local a, b
    local now, allow = 1, true
    a = ACB.newTrade(aCards, function() return now end, function() return "first-1" end, function(peer, msg)
        if not allow then return false, "Blocked" end
        equal(peer, "bob-realm")
        b:receive("alice-realm", msg)
        return true
    end)
    b = ACB.newTrade(bCards, function() return now end, function() return "second-1" end, function(peer, msg)
        equal(peer, "alice-realm")
        a:receive("bob-realm", msg)
        return true
    end)
    a:offer("bob-realm", "npc:639")
    equal(a.session, nil)
    b:listen("alice-realm")
    b:receive("uninvited-realm", "O|first-1|npc:589")
    equal(b.session.take, nil)
    b:receive("alice-realm", "O|first-1|npc:99999")
    equal(b.session.take, nil)
    allow = false
    a:offer("bob-realm", "npc:589")
    equal(a.status, "Blocked")
    equal(b.session.take, nil)
    allow = true
    a:retry()
    equal(b.session.take, "npc:589")
    b:receive("alice-realm", "O|first-1|npc:573")
    equal(b.session.take, "npc:589")
    b:reply("npc:639")
    equal(a.session.take, "npc:639")
    b:confirm()
    equal(a.session.peerConfirmed, true)
    equal(a.session.sentConfirm, nil)
    aCards["npc:589"] = 1
    a:confirm()
    equal(b.session.peerConfirmed, nil)
    aCards["npc:589"] = 2
    b:receive("alice-realm", "C|first-1|npc:589|npc:573")
    equal(b.session.peerConfirmed, nil)
    a:confirm()
    a:retry()
    equal(a.session.sentConfirm and b.session.sentConfirm and b.session.peerConfirmed, true)
    equal(aCards["npc:589"], 2)
    equal(bCards["npc:639"], 2)
    equal(aCards["npc:639"], nil)
    equal(bCards["npc:589"], nil)
    now = 122
    equal(a:active(), nil)
    equal(b:active(), nil)
    b:listen("alice-realm")
    b:receive("alice-realm", "O|first-1|npc:589")
    equal(b.session.take, nil)
end)

-- Load the actual UI and event handlers against small game API stand-ins.
local methods = {
    SetSize = ignore, SetPoint = ignore, SetFrameStrata = ignore, SetClampedToScreen = ignore,
    SetMovable = ignore, EnableMouse = ignore, SetBackdrop = ignore, SetBackdropColor = ignore,
    SetBackdropBorderColor = ignore, SetHeight = ignore, RegisterForDrag = ignore,
    SetJustifyH = ignore, SetTextColor = ignore, SetAllPoints = ignore, SetTexCoord = ignore,
    SetWidth = ignore, SetAutoFocus = ignore, SetMaxLetters = ignore, SetFocus = ignore,
    SetTexture = ignore, SetDesaturated = ignore, SetAlpha = ignore, SetMultiLine = ignore,
    SetFontObject = ignore, SetScrollChild = ignore, SetVerticalScroll = ignore, HighlightText = ignore,
    ClearFocus = ignore, SetClipsChildren = ignore, SetColorTexture = ignore, SetFont = ignore,
    SetVertexColor = ignore, SetFrameLevel = ignore, GetFrameLevel = function() return 1 end,
    SetWordWrap = ignore, SetRotation = ignore, SetShadowOffset = ignore, SetShadowColor = ignore, GetStringWidth = function() return 6 end, SetJustifyV = ignore, ClearAllPoints = ignore,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetShown = function(self, shown) self.shown = shown end,
    IsShown = function(self) return self.shown end,
    SetText = function(self, text) self.text = text end,
    GetText = function(self) return self.text or "" end,
    SetEnabled = function(self, enabled) equal(type(enabled), "boolean") end,
    SetScript = function(self, name, handler) self[name] = handler end,
    RegisterEvent = function(self, event)
        assert(not event:match("^COMBAT_LOG"))
        self[event] = true
    end,
    UnregisterEvent = function(self, event) self[event] = nil end,
}
local eventFrame, widgets = nil, {}
function CreateFrame(kind, name, parent)
    local frame = setmetatable({}, { __index = methods })
    if not eventFrame then eventFrame = frame end
    if name then _G[name] = frame end
    widgets[#widgets + 1] = frame
    return frame
end
methods.CreateFontString, methods.CreateTexture = CreateFrame, CreateFrame
methods.RegisterUnitEvent = methods.RegisterEvent
UISpecialFrames, SlashCmdList = {}, {}

local secret = setmetatable({}, { __tostring = function() error("secret value used") end })
function issecretvalue(value) return value == secret end
local clock, slots, rolls, draw, instance = 10, {}, 0, 1, 0
local target, dead, rank, playerDead, combat, locked, level
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
C_Spell = { GetSpellName = function(id) return (id == 2575 or id == 2576) and "Mining" or nil end }
C_ChatInfo = {
    RegisterAddonMessagePrefix = ignore, IsAddonMessagePrefixRegistered = function() return true end,
    AreOutgoingAddonChatMessagesRestricted = function() return false end,
    InChatMessagingLockdown = function() return locked or false end,
}
function GetBuildInfo() return "1.60.1", "70862", "Nov 4 2026", 16001 end
function GetTime() return clock end
function GetNumLootItems() return #slots end
function GetLootSourceInfo(index)
    if slots[index] == false then error("unavailable") end
    return unpack(slots[index])
end
function GetInstanceInfo() return "Map", "party", 1, "", 5, false, false, instance end
function UnitGUID(unit) if unit == "target" then return target end end
function UnitIsDeadOrGhost(unit)
    if unit == "player" then return playerDead or false end
    return dead
end
function UnitClassification() return rank end
function UnitLevel() return level end
function UnitFullName() return "Alice", "Realm Name" end
function GetNormalizedRealmName() return "RealmName" end
function IsInInstance() return instance ~= 0 end
function InCombatLockdown() return combat or false end
function time() return 111 end

local realPrint, realRandom = print, math.random
print = function(message)
    if not message:find("|cffe8bc6b", 1, true) then realPrint(message) end
end
math.random = function(min, max)
    if max == 10000 then rolls = rolls + 1 return draw end
    return realRandom(min, max)
end
AzerothCardBinderDB = { counts = { invalid = -1 }, diagnostics = true }
loadAddon("Cards.lua")
loadAddon("Binder.lua")
loadAddon("Forever.lua")

local function emit(event, ...)
    assert(eventFrame[event], "event not registered: " .. event)
    eventFrame:OnEvent(event, ...)
end

local function openLoot(...)
    slots = { ... }
    emit("LOOT_READY", false)
    emit("LOOT_OPENED", false, false)
end

local function cast(event, token, spell, unit)
    emit("UNIT_SPELLCAST_" .. event, unit or "player", token, spell)
end

test("UI and SavedVariables initialize through ADDON_LOADED", function()
    emit("ADDON_LOADED", addon)
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
end)

test("cards draw for missing, owned and gathering entries", function()
    AzerothCardBinderDB.counts["npc:639"] = 2
    AzerothCardBinderDB.counts["node:1731"] = 1
    AzerothCardBinderDB.levels["npc:639"] = 21
    ACB.open(1)
    ACB.open(2)
    ACB.open(3)
    AzerothCardBinderDB.counts["npc:639"], AzerothCardBinderDB.counts["node:1731"] = nil, nil
end)

test("loot slots dedup by source, including mixed sources and auto-loot close", function()
    local a, b = guid(589, "one"), guid(589, "two")
    slots = { { a, 2, b, 1 }, { a, 3 } }
    emit("LOOT_READY", true)
    slots = {}
    emit("LOOT_CLOSED")
    emit("LOOT_OPENED", true, false)
    for _, callback in ipairs(timers) do callback() end
    equal(rolls, 2)
    equal(AzerothCardBinderDB.counts["npc:589"], 2)
    openLoot({ a, 1 }, { b, 1 })
    equal(rolls, 2)
end)

test("secret, unknown, live, pickpocket and item-container sources are skipped", function()
    local before = rolls
    target, dead = guid(590, "live"), false
    openLoot({ secret, secret }, { target, 1 }, { guid(99999, "unknown"), 1 }, false)
    slots = { { guid(590, "container"), 1 } }
    emit("LOOT_READY", false)
    emit("LOOT_OPENED", false, true)
    emit("UNIT_SPELLCAST_SENT", "player", secret, secret, 921)
    openLoot({ guid(590, "pickpocket"), 1 })
    equal(rolls, before)
    clock = clock + 3
    target, dead, rank, level = guid(590, "rank"), true, "elite", 18
    draw = 100
    openLoot({ target, 1 })
    equal(rolls, before + 1)
    equal(AzerothCardBinderDB.counts["npc:590"], 1)
    equal(AzerothCardBinderDB.levels["npc:590"], 18)
    target, dead, rank, level, draw = nil, nil, nil, nil, 1
end)

test("gathering requires player success and an exact node source in either event order", function()
    local before = rolls
    local copper, bloom = guid(1731, "copper", "GameObject"), guid(1618, "bloom", "GameObject")
    openLoot({ copper, 1 })
    cast("START", "attempt-1", 2575)
    openLoot({ copper, 1 })
    cast("INTERRUPTED", "attempt-1", 2575)
    cast("SUCCEEDED", "attempt-1", 2575)
    equal(rolls, before)
    clock = clock + 4
    cast("START", "attempt-2", 2576)
    cast("SUCCEEDED", "attempt-2", 2576, "party1")
    openLoot({ copper, 1 })
    equal(rolls, before)
    cast("SUCCEEDED", "attempt-2", 2576)
    openLoot({ copper, 1 })
    equal(rolls, before + 1)
    equal(AzerothCardBinderDB.counts["node:1731"], 1)

    clock = clock + 4
    cast("START", "attempt-3", 2366)
    cast("SUCCEEDED", "attempt-3", 2366)
    openLoot({ guid(590, "gathered-corpse"), 1 }, { bloom, 1 })
    equal(rolls, before + 3)
    equal(AzerothCardBinderDB.counts["node:1618"], 1)
    equal(AzerothCardBinderDB.counts["npc:590"], 2)
    openLoot({ guid(1618, "different", "GameObject"), 1 })
    equal(rolls, before + 3)
end)

test("boss trial shares the loot roll in both orders and rejects missing evidence", function()
    local before = rolls
    local function start()
        dead = false
        emit("ENCOUNTER_START", 555, "Edwin VanCleef", 1, 5)
        dead = true
    end
    local function finish(result)
        emit("ENCOUNTER_END", 555, "Edwin VanCleef", 1, 5, result)
    end

    instance, target = 36, guid(639, "default")
    start()
    finish(1)
    equal(rolls, before)
    SlashCmdList.AZEROTHCARDBINDER("boss")
    target = guid(639, "end-first")
    start()
    finish(1)
    finish(1)
    openLoot({ target, 1 })
    equal(rolls, before + 1)

    target = guid(639, "loot-first")
    start()
    openLoot({ target, 1 })
    finish(1)
    equal(rolls, before + 2)

    target = guid(639, "wipe")
    start()
    finish(0)
    target = guid(639, "no-readable-corpse")
    start()
    target = secret
    finish(1)
    target = guid(639, "ghost")
    start()
    playerDead = true
    finish(1)
    playerDead = false
    equal(rolls, before + 2)
    instance, target = 0, nil
end)

test("Trade panel sends only supported outdoor whispers and filters incoming messages", function()
    local sent = {}
    Enum = { SendAddonMessageResult = { Success = 0 } }
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, peer)
        equal(prefix, ACB.tradePrefix)
        equal(channel, "WHISPER")
        equal(peer, "bob-realmname")
        sent[#sent + 1] = message
        return 0
    end
    local function click(text)
        for _, widget in ipairs(widgets) do
            if widget.text == text and widget.OnClick then widget:OnClick() return end
        end
        error("button not found: " .. text)
    end
    SlashCmdList.AZEROTHCARDBINDER("trade")
    for _, widget in ipairs(widgets) do
        if widget.OnEnterPressed then widget:SetText("Bob") break end
    end
    click(">")
    instance = 36
    click("Send offer")
    equal(#sent, 0)
    instance, combat = 0, true
    click("Resend last step")
    equal(#sent, 0)
    combat, locked = false, true
    click("Resend last step")
    equal(#sent, 0)
    locked = false
    click("Resend last step")
    equal(#sent, 1)
    local id, give = sent[1]:match("^O|([^|]+)|(.+)$")
    assert(id and give)
    emit("CHAT_MSG_ADDON", secret, secret, secret, secret)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "R|" .. id .. "|npc:573", "PARTY", "Bob")
    click("Confirm preview")
    equal(#sent, 1)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "R|" .. id .. "|npc:573", "WHISPER", "Bob")
    click("Confirm preview")
    equal(sent[2], "C|" .. id .. "|" .. give .. "|npc:573")
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "C|" .. id .. "|npc:573|" .. give, "WHISPER", "Bob-RealmName")
    local complete
    for _, widget in ipairs(widgets) do
        if widget.text == "Preview complete. Both players confirmed these cards." then complete = true end
    end
    equal(complete, true)
    equal(AzerothCardBinderDB.counts[give], 2)
    equal(AzerothCardBinderDB.counts["npc:573"], nil)
end)

print(("%d checks passed under %s"):format(passed, _VERSION))
