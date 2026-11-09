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
loadAddon("CatalogForever.lua")
loadAddon("CatalogNodes.lua")
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
            if max == ACB.shinyOdds then return 2 end -- not shiny
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
    local bosses = 0
    for _, card in ipairs(ACB.pages[1].cards) do
        if card.boss then bosses = bosses + 1 end
    end
    assert(bosses >= 8, "the eight hand-made Deadmines bosses are all bosses")
    local owned, total = ACB.progress(saved.counts, 1)
    equal(owned, bosses)
    equal(total, #ACB.pages[1].cards)
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

test("every gathering node is a card and all of its object ids find it", function()
    local nodes = 0
    for _, card in ipairs(ACB.pages[3].cards) do
        nodes = nodes + 1
        assert(card.profession == "mining" or card.profession == "herbalism", card.name)
        assert(card.skill and card.skill >= 1, card.name)
        for _, id in ipairs(card.ids) do equal(ACB.sources.GameObject[id], card) end
    end
    assert(nodes >= 39, "all 39 Forever node types, has " .. nodes)
    -- Several object ids, one card.
    equal(ACB.source(guid(3763, "a", "GameObject")).key, "node:1731")
    equal(ACB.source(guid(3724, "a", "GameObject")).key, "node:1618")
    equal(ACB.source(guid(175404, "a", "GameObject")).name, "Rich Thorium Vein")
    -- Creatures and objects have separate id spaces, so a creature never turns into a node card.
    local creature = ACB.source(guid(1731, "a", "Creature"))
    assert(creature == nil or not creature.profession)
    -- The original hand-made nodes keep their lore and model.
    equal(ACB.cards["node:1731"].model, 219514)
    assert(ACB.cards["node:1731"].lore:find("Reddish ore", 1, true))
    assert(ACB.cards["node:175404"].lore:find("Mining skill 275", 1, true))
    equal(ACB.cards["node:175404"].rarity, "rare")
end)

test("the generated catalog is large, consistent and fits the card", function()
    local count, codes, ids = 0, {}, {}
    for _, page in ipairs(ACB.pages) do
        assert(page.title and page.code and page.group, "every set has a title, code and group")
        assert(not codes[page.code], "duplicate set code " .. page.code)
        codes[page.code] = true
        assert(ACB.zones[page.zone], "every set has zone art settings: " .. page.title)
        for _, card in ipairs(page.cards) do
            count = count + 1
            assert(card.name ~= "" and #card.name <= 44, "card name fits: " .. card.name)
            assert(card.id and not ids[card.key], "unique card " .. card.key)
            ids[card.key] = true
            assert(ACB.sources[card.profession and "GameObject" or "Creature"][card.id] == card, "source index for " .. card.key)
        end
    end
    assert(count > 3500, "the catalog should hold thousands of cards, has " .. count)
    assert(#ACB.pages > 60, "sets for every dungeon, raid and zone with data")
    -- Hand-made cards keep their lore; new cards get a short generated line.
    assert(ACB.cards["npc:639"].lore:find("Founder of the Defias", 1, true))
    assert(ACB.cards["npc:157"].lore:find("The Barrens") == nil and #ACB.cards["npc:157"].lore > 0)
    equal(ACB.pageForPlace.deadmines, 1)
    equal(ACB.pageForPlace.westfall, 2)
end)

test("gathering nodes carry a model file", function()
    equal(ACB.cards["node:1731"].model, 219514)
    equal(ACB.cards["node:1618"].model, 219481)
    -- Most nodes have a mesh; the rest fall back to their icon, which every node card has.
    local withModel, total = 0, 0
    for _, card in pairs(ACB.cards) do
        if card.profession then
            total = total + 1
            assert(type(card.icon) == "string" and card.icon ~= "", card.name .. " needs an icon")
            if card.model then
                equal(type(card.model), "number")
                withModel = withModel + 1
            end
        end
    end
    assert(withModel >= 30 and withModel < total or withModel == total, "models for most of the " .. total .. " nodes")
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

test("a swap moves one spare copy and can finish a set", function()
    local saved = { counts = {}, achievements = {} }
    for _, card in ipairs(ACB.pages[1].cards) do saved.counts[card.key] = 1 end
    saved.counts["npc:639"] = nil
    saved.counts["npc:598"] = 2
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore)
    equal(collection:swap("npc:639", "npc:598"), false)
    equal(collection:swap("npc:589", "npc:639"), false)
    equal(collection:swap("npc:598", "npc:639"), true)
    equal(saved.counts["npc:598"], 1)
    equal(saved.counts["npc:639"], 1)
    equal(saved.achievements.crew, true)
    equal(saved.achievements.deadmines, true)
    equal(collection:swap("npc:598", "npc:639"), false)
end)

test("a lost confirmation is healed by re-sending, and nobody applies twice", function()
    local aCards, bCards = { ["npc:589"] = 2 }, { ["npc:639"] = 2 }
    local a, b
    local dropFromA = true
    local function swapper(counts)
        return function(give, take)
            counts[give] = counts[give] - 1
            counts[take] = (counts[take] or 0) + 1
            return true
        end
    end
    a = ACB.newTrade(aCards, function() return 1 end, function() return "id-1" end, function(peer, msg)
        if dropFromA and msg:sub(1, 1) == "C" then return true end -- sent, but never arrives
        b:receive("alice-realm", msg)
        return true
    end, swapper(aCards))
    b = ACB.newTrade(bCards, function() return 1 end, function() return "id-2" end, function(peer, msg)
        a:receive("bob-realm", msg)
        return true
    end, swapper(bCards))
    a:offer("bob-realm", "npc:589")
    b:listen("alice-realm")
    a:retry()
    b:reply("npc:639")
    a:confirm()
    b:confirm()
    -- Alice has both confirmations and has swapped; Bob never received hers.
    equal(aCards["npc:639"], 1)
    equal(bCards["npc:589"], nil)
    dropFromA = false
    b:retry()
    equal(bCards["npc:589"], 1)
    equal(bCards["npc:639"], 1)
    b:retry()
    b:retry()
    b:retry()
    equal(aCards["npc:589"], 1)
    equal(aCards["npc:639"], 1)
    equal(bCards["npc:589"], 1)
    equal(bCards["npc:639"], 1)
end)

test("the bad-luck safety net guarantees a card after enough misses and then resets", function()
    local saved = { counts = {}, achievements = {} }
    local draws = 0
    local collection = ACB.newCollection(saved, function(min, max)
        if max == ACB.shinyOdds then return 2 end
        draws = draws + 1
        return 10000 -- always a miss unless the safety net steps in
    end, ignore, ignore)
    local misses, limit = ACB.luck(saved, ACB.cards["npc:589"])
    equal(misses, 0)
    equal(limit, 500) -- a 0.5% card
    equal(select(2, ACB.luck(saved, ACB.cards["npc:639"])), 250) -- a 1% card
    equal(select(2, ACB.luck(saved, ACB.cards["npc:573"])), 50) -- a 5% card
    for attempt = 1, limit - 1 do
        equal(collection:roll(guid(589, "miss" .. attempt), "loot"), false)
    end
    equal(saved.counts["npc:589"], nil)
    equal(ACB.luck(saved, ACB.cards["npc:589"]), limit - 1)
    local before = draws
    equal(collection:roll(guid(589, "lucky"), "loot"), true)
    equal(draws, before) -- the guaranteed drop needs no roll
    equal(saved.counts["npc:589"], 1)
    equal(ACB.luck(saved, ACB.cards["npc:589"]), 0)
    equal(collection:roll(guid(589, "after"), "loot"), false)
    ACB.pityFactor = 0 -- switched off
    for attempt = 1, 600 do collection:roll(guid(589, "off" .. attempt), "loot") end
    equal(saved.counts["npc:589"], 1)
    ACB.pityFactor = 2.5
end)

test("finishing a set earns its title once and announces it", function()
    -- A small set of its own, so the test does not depend on how big the real sets are.
    ACB.addPlace("test-place", "Test Place", "Zone", "", { { 900001, "Test One", "n", 5 }, { 900002, "Test Two", "n", 5 } })
    local index = ACB.pageForPlace["test-place"]
    local page = ACB.pages[index]
    equal(index, #ACB.pages)
    local saved = { counts = {}, achievements = {} }
    local done = {}
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, nil, function(set, reward)
        done[#done + 1] = { page = set.code, reward = reward }
    end)
    saved.counts["npc:900001"] = 1
    collection:roll(guid(900002, "last"), "loot")
    equal(#done, 1)
    equal(done[1].page, page.code)
    equal(done[1].reward, "Test Place Collector")
    equal(saved.sets[page.code], true)
    equal(saved.titles["Test Place Collector"], true)
    equal(saved.title, "Test Place Collector")
    collection:roll(guid(900002, "again"), "loot")
    equal(#done, 1) -- a set is only completed once
    table.remove(ACB.pages, index)
    ACB.pageForPlace["test-place"], ACB.zones["test-place"] = nil, nil
    for _, id in ipairs({ 900001, 900002 }) do
        ACB.cards["npc:" .. id], ACB.sources.Creature[id] = nil, nil
    end
end)

test("partners can share spares and wants, and trades are logged", function()
    local aCards, bCards = { ["npc:589"] = 2, ["npc:590"] = 3, ["npc:114"] = 1 }, { ["npc:639"] = 2 }
    local a, b
    local applied = {}
    a = ACB.newTrade(aCards, function() return 1 end, function() return "id-1" end, function(peer, msg)
        b:receive("alice-realm", msg)
        return true
    end, function(give, take, peer) applied[#applied + 1] = { give, take, peer } return true end,
        function() return { "npc:573", "npc:639" } end)
    b = ACB.newTrade(bCards, function() return 1 end, function() return "id-2" end, function(peer, msg)
        a:receive("bob-realm", msg)
        return true
    end, function() return true end, function() return {} end)
    a:shareLists() -- nothing started yet
    equal(a.status, "Start a trade first.")
    a:listen("bob-realm")
    b:listen("alice-realm")
    a:shareLists()
    equal(table.concat(b.session.theirSpares, ","), "npc:589,npc:590")
    equal(table.concat(b.session.theirWants, ","), "npc:573,npc:639")
    -- Unknown keys, bad characters and messages from other people are ignored.
    b:receive("alice-realm", "S|npc:589,npc:99999,node:1731")
    equal(table.concat(b.session.theirSpares, ","), "npc:589,node:1731")
    b:receive("alice-realm", "S|npc:589;drop")
    equal(table.concat(b.session.theirSpares, ","), "npc:589,node:1731")
    b:receive("mallory-realm", "S|npc:573")
    equal(table.concat(b.session.theirSpares, ","), "npc:589,node:1731")
    -- A long list is cut to fit one addon message and twelve cards.
    local saved = { counts = {}, achievements = {}, history = {} }
    ACB.logTrade(saved, "npc:589", "npc:639", "bob-realm", 100)
    ACB.logTrade(saved, "npc:590", "npc:573", "carol-realm", 200)
    equal(saved.history[1].peer, "carol-realm") -- newest first
    for index = 1, 30 do ACB.logTrade(saved, "npc:589", "npc:639", "x" .. index, index) end
    equal(#saved.history, 20)
    local lines = ACB.tradeHistory(saved)
    equal(#lines, 20)
    assert(lines[1]:find("Defias Pillager for Edwin VanCleef", 1, true))
    assert(lines[1]:find("with x30", 1, true))
    -- Only missing cards that were marked count as wanted.
    local mine = { counts = { ["npc:639"] = 1 }, wanted = {} }
    equal(#ACB.wantedCards(mine), 0)
    mine.wanted["npc:573"] = true
    equal(table.concat(ACB.wantedCards(mine), ","), "npc:573")
    mine.wanted["npc:639"] = true -- already owned, so not wanted
    equal(table.concat(ACB.wantedCards(mine), ","), "npc:573")
end)

test("a first copy can be shiny once per card and the pop-up hook hears about it", function()
    local saved = { counts = {}, achievements = {} }
    local shinyRolls, found = 0, {}
    local collection = ACB.newCollection(saved, function(min, max)
        if max == ACB.shinyOdds then shinyRolls = shinyRolls + 1 end
        return 1
    end, ignore, ignore, function(card, info) found[#found + 1] = { card = card, info = info } end)
    collection:roll(guid(589, "A"), "loot")
    equal(saved.shiny["npc:589"], true)
    equal(found[1].info.shiny, true)
    equal(found[1].info.first, true)
    collection:roll(guid(589, "B"), "loot")
    equal(shinyRolls, 1) -- an owned shiny is never rolled for again
    equal(found[2].info.shiny, false)
    equal(found[2].info.first, false)
    equal(found[2].info.count, 2)
    saved.counts["npc:590"] = 2
    collection:swap("npc:590", "npc:114")
    equal(found[3].card.key, "npc:114")
    equal(found[3].info.trade, true)
    equal(saved.shiny["npc:114"], nil) -- trades never hand out shiny copies
end)

test("two peers confirm the exact pair and each applies the swap once", function()
    local aCards, bCards = { ["npc:589"] = 2 }, { ["npc:639"] = 2 }
    local a, b
    local now, allow = 1, true
    local function swapper(counts)
        return function(give, take)
            if (counts[give] or 0) < 2 then return false end
            counts[give] = counts[give] - 1
            counts[take] = (counts[take] or 0) + 1
            return true
        end
    end
    a = ACB.newTrade(aCards, function() return now end, function() return "first-1" end, function(peer, msg)
        if not allow then return false, "Blocked" end
        equal(peer, "bob-realm")
        b:receive("alice-realm", msg)
        return true
    end, swapper(aCards))
    b = ACB.newTrade(bCards, function() return now end, function() return "second-1" end, function(peer, msg)
        equal(peer, "alice-realm")
        a:receive("bob-realm", msg)
        return true
    end, swapper(bCards))
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
    -- Each side applied the swap exactly once, even though a confirmation was sent again.
    equal(aCards["npc:589"], 1)
    equal(aCards["npc:639"], 1)
    equal(bCards["npc:639"], 1)
    equal(bCards["npc:589"], 1)
    now = 122
    equal(a:active(), nil)
    equal(b:active(), nil)
    b:listen("alice-realm")
    b:receive("alice-realm", "O|first-1|npc:589")
    equal(b.session.take, nil)
end)

-- Load the actual UI and event handlers against small game API stand-ins.
local methods = {
    SetSize = function(self, width, height) self.width, self.height = width, height end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    SetPoint = function(self, ...) self.point = { ... } end,
    SetFrameStrata = ignore, SetClampedToScreen = ignore,
    SetMovable = ignore, EnableMouse = ignore,
    SetBackdrop = function(self) equal(self.template, "BackdropTemplate") end,
    SetBackdropColor = ignore,
    SetBackdropBorderColor = ignore, SetHeight = ignore, RegisterForDrag = ignore,
    SetHighlightTexture = ignore, SetNormalTexture = ignore, RegisterForClicks = ignore,
    SetFontString = ignore, SetScale = function(self, scale) self.scale = scale end,
    SetTextInsets = ignore, EnableMouseWheel = ignore,
    SetJustifyH = ignore, SetTextColor = ignore, SetAllPoints = ignore, SetTexCoord = ignore,
    SetWidth = ignore, SetAutoFocus = ignore, SetMaxLetters = ignore, SetFocus = ignore,
    SetTexture = function(self, texture)
        if self.rejectTexture then return false end
        self.texture = texture
        return true
    end,
    SetDesaturated = ignore, SetAlpha = ignore, SetMultiLine = ignore,
    SetFontObject = ignore, SetScrollChild = ignore, SetVerticalScroll = ignore, HighlightText = ignore,
    ClearFocus = ignore, SetClipsChildren = ignore,
    SetColorTexture = function(self) self.colorTexture = true end, SetFont = ignore,
    SetVertexColor = ignore, SetFrameLevel = ignore, GetFrameLevel = function() return 1 end,
    SetWordWrap = ignore, SetRotation = ignore, SetShadowOffset = ignore, SetSpacing = ignore, SetShadowColor = ignore, GetStringWidth = function() return 6 end, SetJustifyV = ignore, ClearAllPoints = ignore,
    SetKeepModelOnHide = function(self, keep) self.keepModel = keep end,
    ClearModel = function(self) self.creature, self.fileID, self.frozen = nil, nil, nil end,
    SetCreature = function(self, creature) self.creature = creature end,
    SetModel = function(self, file) self.fileID = file end,
    GetModelFileID = function(self) return self.fileID end,
    SetPortraitZoom = function(self, zoom) self.portraitZoom = zoom end,
    SetCamDistanceScale = ignore, SetFacing = ignore, SetPosition = ignore, SetPaused = ignore,
    HasAnimation = function(self, animation) return self.supportedAnimation == animation end,
    FreezeAnimation = function(self, animation, variation, frame) self.frozen = { animation, variation, frame } end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetShown = function(self, shown) self.shown = shown end,
    IsShown = function(self) return self.shown end,
    SetText = function(self, text) self.text = text end,
    GetText = function(self) return self.text or "" end,
    SetEnabled = function(self, enabled) equal(type(enabled), "boolean"); self.enabled = enabled end,
    SetScript = function(self, name, handler) self[name] = handler end,
    RegisterEvent = function(self, event)
        assert(not event:match("^COMBAT_LOG"))
        self[event] = true
    end,
    UnregisterEvent = function(self, event) self[event] = nil end,
}
local eventFrame, widgets = nil, {}
function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({ parent = parent, template = template }, { __index = methods })
    if not eventFrame then eventFrame = frame end
    if name then _G[name] = frame end
    widgets[#widgets + 1] = frame
    return frame
end
methods.CreateFontString = function(self) return CreateFrame("FontString", nil, self) end
methods.CreateTexture = function(self) return CreateFrame("Texture", nil, self) end
methods.RegisterUnitEvent = methods.RegisterEvent
UISpecialFrames, SlashCmdList = {}, {}
UIParent = setmetatable({ width = 1200, height = 900 }, { __index = methods })
Minimap = setmetatable({
    width = 140, height = 140,
    GetCenter = function() return 100, 100 end,
    GetEffectiveScale = function() return 0.8 end,
}, { __index = methods })
function GetCursorPosition() return 80, 140 end

local secret = setmetatable({}, { __tostring = function() error("secret value used") end })
function issecretvalue(value) return value == secret end
local clock, slots, rolls, draw, instance = 10, {}, 0, 1, 0
local shinyDraw = 2 -- 1 would make the next find shiny
local target, dead, rank, playerDead, combat, locked
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
    if max == ACB.shinyOdds then return shinyDraw end
    if max == 10000 then rolls = rolls + 1 return draw end
    return realRandom(min, max)
end
AzerothCardBinderDB = { counts = { invalid = -1 }, diagnostics = true }
hintCallbacks = {}
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) hintCallbacks[#hintCallbacks + 1] = callback end }
Enum = { TooltipDataType = { Unit = 1, Object = 2 } }
loadAddon("Cards.lua")
loadAddon("Toast.lua")
loadAddon("Hints.lua")
loadAddon("Social.lua")
loadAddon("Folio.lua")
loadAddon("Binder.lua")
loadAddon("Minimap.lua")
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
    ACB.open(1)
    ACB.open(2)
    ACB.open(3)
    AzerothCardBinderDB.counts["npc:639"], AzerothCardBinderDB.counts["node:1731"] = nil, nil
end)

test("tooltip hints say whether a card is owned and where to find it", function()
    local saved = AzerothCardBinderDB
    local card = ACB.cards["npc:589"]
    saved.counts["npc:589"], saved.misses["npc:589"] = nil, 120
    local lines = ACB.hintLines(saved, card)
    equal(lines[1][1], "Card: not in your binder yet (0.5% chance)")
    equal(lines[2][1], "Bad-luck safety net: 120 / 500")
    saved.counts["npc:589"] = 2
    equal(ACB.hintLines(saved, card)[1][1], "Card: in your binder (x2)")
    saved.counts["npc:589"], saved.misses["npc:589"] = nil, nil
    equal(ACB.whereToFind(card), "Defeat it in Westfall.")
    equal(ACB.whereToFind(ACB.cards["npc:639"]), "Defeat this boss in the Deadmines in Westfall.")
    equal(ACB.whereToFind(ACB.cards["node:1731"]), "Gather it in Elwynn Forest and other starting zones.")

    local added = {}
    local tip = { AddLine = function(_, text) added[#added + 1] = text end, Show = ignore }
    hintCallbacks[1](tip, { guid = guid(589, "tip") })
    equal(added[1], "Card: not in your binder yet (0.5% chance)")
    added = {}
    hintCallbacks[1](tip, { guid = guid(99999, "unknown") })
    hintCallbacks[1](tip, { guid = secret })
    equal(#added, 0) -- unknown and unreadable sources add nothing
    saved.hints = false
    hintCallbacks[1](tip, { guid = guid(589, "tip") })
    equal(#added, 0)
    saved.hints = nil
end)

test("card links round-trip and unknown links are ignored", function()
    local saved = { counts = { ["npc:639"] = 1 }, shiny = { ["npc:639"] = true } }
    local link = ACB.cardLink(ACB.cards["npc:639"], true)
    assert(link:find("|Haddon:AzerothCardBinder:card:npc:639:1|h[Edwin VanCleef (Shiny)]|h", 1, true))
    local entry, shiny = ACB.parseCardLink("addon:AzerothCardBinder:card:npc:639:1")
    equal(entry.key, "npc:639")
    equal(shiny, true)
    equal(select(2, ACB.parseCardLink("addon:AzerothCardBinder:card:node:1731:0")), false)
    equal(ACB.parseCardLink("addon:AzerothCardBinder:card:npc:99999:0"), nil)
    equal(ACB.parseCardLink("addon:Other:card:npc:639:0"), nil)
    equal(ACB.parseCardLink("addon:AzerothCardBinder:card:npc:639:2"), nil)
    equal(ACB.parseCardLink(secret), nil)
    equal(ACB.findCard(saved, "edwin").key, "npc:639")
    equal(ACB.findCard(saved, "pillager"), nil) -- not owned
    equal(ACB.findCard(saved, ""), nil)
end)

test("a binder can be viewed read-only, only when asked for, and can be made private", function()
    local clock = 100
    local aSaved = { counts = {}, shiny = { ["npc:639"] = true } }
    for _, card in ipairs(ACB.pages[1].cards) do aSaved.counts[card.key] = 1 end
    aSaved.counts["npc:589"] = 3
    local messages = ACB.encodeBinder(aSaved)
    assert(#messages >= 2, "a full set needs more than one message")
    for _, message in ipairs(messages) do assert(#message <= 160, "message too long") end

    local timers, shown = {}, {}
    local function after(delay, action) timers[#timers + 1] = action end
    local sentToB, sentToA = {}, {}
    -- Bob asks Alice. Alice's add-on answers; Bob's add-on shows what arrives.
    local bobSend = function(peer, message) sentToA[#sentToA + 1] = message return true end
    local aliceSend = function(peer, message) sentToB[#sentToB + 1] = message return true end

    ACB.initSocial(aSaved, aliceSend, function() return clock end, after)
    ACB.receiveView("bob-realm", "Q")
    for _, run in ipairs(timers) do run() end
    equal(#sentToB, #messages)
    ACB.receiveView("bob-realm", "Q") -- asked again straight away
    equal(#timers, #messages)
    clock = clock + 11
    aSaved.inspectable = false
    ACB.receiveView("carol-realm", "Q")
    equal(#timers, #messages) -- private binders answer nobody
    aSaved.inspectable = nil

    -- Bob's side.
    local bSaved = { counts = {} }
    ACB.initSocial(bSaved, bobSend, function() return clock end, after)
    ACB.showInspect = function(peer, counts, shiny) shown[#shown + 1] = { peer = peer, counts = counts, shiny = shiny } end
    ACB.receiveView("alice-realm", sentToB[1]) -- nobody asked, so it is ignored
    equal(#shown, 0)
    equal(ACB.requestBinder("alice-realm"), true)
    equal(sentToA[#sentToA], "Q")
    ACB.receiveView("mallory-realm", sentToB[1])
    equal(#shown, 0) -- only the player asked answers
    equal(#sentToB, 2)
    ACB.receiveView("alice-realm", sentToB[1])
    ACB.receiveView("alice-realm", sentToB[1]) -- a repeated part changes nothing
    equal(#shown, 0)
    ACB.receiveView("alice-realm", "B|2/2|c99999=4,c589=3") -- unknown cards are dropped
    equal(#shown, 1)
    equal(shown[1].peer, "alice-realm")
    equal(shown[1].counts["npc:589"], 3)
    equal(shown[1].shiny["npc:639"], true)
    equal(shown[1].counts["npc:99999"], nil)
    local lines = ACB.inspectLines(shown[1].counts, shown[1].shiny)
    assert(lines[1]:find("^21 of %d+ cards collected, 1 shiny$"))
    local text = table.concat(lines, " ")
    assert(text:find("Deadmines   20 / %d+"))
    assert(text:find("Westfall   1 / %d+"))
    -- Garbage is dropped.
    ACB.receiveView("alice-realm", "B|9/2|npc:589=2")
    ACB.receiveView("alice-realm", "B|1/2|<script>")
    ACB.receiveView("alice-realm", string.rep("x", 300))
    equal(#shown, 1)
end)

test("right-clicking a player offers a trade and a binder view", function()
    local callbacks = {}
    Menu = { ModifyMenu = function(_, callback) callbacks[#callbacks + 1] = callback end }
    ACB.initSocial({ counts = {} }, function() return true end, function() return 1 end, function(_, action) action() end)
    Menu = nil
    equal(#callbacks, 5)
    local buttons = {}
    local root = { CreateDivider = ignore, CreateButton = function(_, text, action) buttons[text] = action end }
    callbacks[1](nil, root, { name = "Bob", server = "RealmName" })
    assert(buttons["Offer a card trade"] and buttons["View their binder"])
    AzerothCardBinderWindow:Hide()
    buttons["Offer a card trade"]()
    equal(AzerothCardBinderWindow:IsShown(), true)
    buttons = {}
    callbacks[1](nil, root, { name = secret })
    callbacks[1](nil, root, nil)
    equal(next(buttons), nil) -- unreadable or missing players get no entries
end)

test("a finished set shows its own pop-up with the title", function()
    local toast = ACB.toast
    if toast:IsShown() then toast.OnUpdate(toast, 100) end
    equal(toast:IsShown(), false)
    ACB.showSetToast(ACB.pages[2], "Westfall Warden")
    equal(toast:IsShown(), true)
    toast.OnUpdate(toast, 100)
    equal(toast:IsShown(), false)
    AzerothCardBinderDB.popups = false
    ACB.showSetToast(ACB.pages[2], "Westfall Warden")
    equal(toast:IsShown(), false)
    AzerothCardBinderDB.popups = nil
end)

test("shiny cards show the foil and plain or missing cards do not", function()
    local card = ACB.createCard(UIParent)
    card:set(ACB.cards["npc:639"], 1, true)
    equal(card.foil:IsShown(), true)
    card:set(ACB.cards["npc:639"], 1, false)
    equal(card.foil:IsShown(), false)
    card:set(ACB.cards["npc:639"], 0, true)
    equal(card.foil:IsShown(), false)
end)

test("pop-ups queue, fade away, play a sound and can be turned off", function()
    local saved = AzerothCardBinderDB
    local played = {}
    PlaySound = function(id) played[#played + 1] = id end
    SOUNDKIT = { UI_EPICLOOT_TOAST = 11, UI_LEGENDARY_LOOT_TOAST = 22, IG_QUEST_LIST_COMPLETE = 33 }
    local toast = ACB.toast
    equal(toast:IsShown(), false)
    ACB.showToast(ACB.cards["npc:589"], { count = 1, first = true, shiny = true })
    equal(toast:IsShown(), true)
    equal(played[1], 22) -- a shiny always gets the top sound
    ACB.showToast(ACB.cards["npc:589"], { count = 2 })
    equal(#played, 1) -- the second waits its turn
    toast.OnUpdate(toast, 10)
    equal(toast:IsShown(), true)
    equal(played[2], 33) -- common cards use the plainest sound
    toast.OnUpdate(toast, 10)
    equal(toast:IsShown(), false)
    saved.popups = false
    ACB.showToast(ACB.cards["npc:639"], { first = true })
    equal(toast:IsShown(), false)
    saved.popups = nil
    SlashCmdList.AZEROTHCARDBINDER("popup test")
    equal(toast:IsShown(), true)
    toast.OnUpdate(toast, 10)
    PlaySound, SOUNDKIT = nil, nil
    equal(ACB.playToastSound("epic", false), nil) -- no sound system, nothing breaks
end)

test("cinematic detail applies the pose after loading and falls back for unsupported animations", function()
    local card = ACB.createCard(UIParent, true)
    card:set(ACB.cards["npc:639"], 0)
    equal(card.model.creature, 639)
    equal(card.model:IsShown(), true)
    equal(card.owned, 0)
    equal(card.model.frozen, nil)
    equal(card.art.base.texture, ACB.folioArt .. "Deadmines.tga")
    card.model.fileID, card.model.supportedAnimation = 1000, 17
    card.model:OnModelLoaded()
    equal(card.model.frozen[1], 17)
    equal(card.model.frozen[3], 24)
    local humanoidZoom = card.model.portraitZoom

    card:set(ACB.cards["npc:573"], 0)
    card.model.fileID, card.model.supportedAnimation = 1001, nil
    card.model:OnModelLoaded()
    equal(card.model.frozen[1], 0)
    assert(card.model.portraitZoom < humanoidZoom)
    equal(card.art.base.texture, ACB.folioArt .. "Westfall.tga")

    card:set(ACB.cards["node:1618"], 0)
    equal(card.model.fileID, ACB.cards["node:1618"].model)
    equal(card.model.frozen, nil)
    equal(card.node:IsShown(), false)
    equal(card.art.base.texture, ACB.folioArt .. "Elwynn.tga")

    local pocket = ACB.createCard(UIParent, false)
    pocket.art.base.rejectTexture = true
    pocket:set(ACB.cards["npc:639"], 0)
    equal(pocket.model:IsShown(), false)
    equal(pocket.model.creature, nil)
    equal(pocket.art.base.colorTexture, true)
end)

test("folio pages through all Deadmines cards and remembers selection per region", function()
    local function widgetWithText(value)
        for _, widget in ipairs(widgets) do
            if widget.text == value then return widget end
        end
        error("missing widget: " .. value)
    end
    local leaves = math.ceil(#ACB.pages[1].cards / 4)
    local westfallLeaves = math.ceil(#ACB.pages[2].cards / 4)
    assert(leaves >= 3, "Deadmines has at least the eight bosses and four mobs")
    AzerothCardBinderDB.counts["npc:639"] = 2
    ACB.open(1)
    local back = widgetWithText("< Back")
    local nextPage = widgetWithText("Next >")
    equal(back.enabled, false)
    widgetWithText("Page 1 of " .. leaves)
    nextPage:OnClick()
    widgetWithText("Page 2 of " .. leaves)
    widgetWithText("2 owned / 1 spare").parent:OnClick()
    widgetWithText("SELECTED CARD  /  DM 08")
    ACB.open(2)
    equal(nextPage.enabled, westfallLeaves > 1)
    widgetWithText("Page 1 of " .. westfallLeaves)
    ACB.open(1)
    widgetWithText("SELECTED CARD  /  DM 08")
    for _ = 1, leaves - 2 do nextPage:OnClick() end
    widgetWithText("Page " .. leaves .. " of " .. leaves)
    equal(nextPage.enabled, false)
    AzerothCardBinderDB.counts["npc:639"] = nil
end)

test("index searches categories and opens sets beyond the original tabs", function()
    local function findWidget(matches)
        for _, widget in ipairs(widgets) do
            if matches(widget) then return widget end
        end
        error("matching widget was not drawn")
    end
    local function button(label)
        return findWidget(function(widget) return widget.text == label and widget.OnClick end)
    end
    local function indexRow(title)
        local label = findWidget(function(widget)
            return widget.text == title and widget.parent and widget.parent.setIndex
        end)
        return label.parent
    end
    local base = #ACB.pages
    for index = 1, 9 do
        ACB.pages[base + index] = { title = ("Test Set %02d"):format(index + 3), group = "Dungeon",
            subtitle = "", cards = ACB.pages[2].cards }
    end

    button("Index"):OnClick()
    equal(button("More").enabled, true)
    local search = findWidget(function(widget) return widget.OnTextChanged ~= nil end)
    search:SetText("Test Set")
    search:OnTextChanged()
    equal(button("More").enabled, true)
    button("More"):OnClick()
    equal(indexRow("Test Set 12"):IsShown(), true)
    indexRow("Test Set 12"):OnClick()
    equal(button("Collection").enabled, false)
    button("Trade"):OnClick()
    equal(button("Trade").enabled, false)
    button("Collection"):OnClick()
    findWidget(function(widget) return widget.text == ("SELECTED CARD  /  SET %02d 01"):format(base + 9) end)

    SlashCmdList.AZEROTHCARDBINDER("index")
    search = findWidget(function(widget) return widget.OnTextChanged ~= nil end)
    search:SetText(" ZoNe ")
    search:OnTextChanged()
    equal(indexRow("Westfall"):IsShown(), true)
    search:SetText("%")
    search:OnTextChanged()
    findWidget(function(widget) return widget.text == "No matching sets" end)
    search:SetText("Test Set 04")
    search:OnTextChanged()
    indexRow("Test Set 04"):OnClick()
    equal(button("Trade").enabled, true)
    findWidget(function(widget) return widget.text == ("SELECTED CARD  /  SET %02d 01"):format(base + 1) end)
    search:SetText("")
    search:OnTextChanged()
    for index = #ACB.pages, base + 1, -1 do ACB.pages[index] = nil end
    ACB.open(1)
end)

test("minimap launcher toggles the fitted window and saves its drag position", function()
    local window = AzerothCardBinderWindow
    local launcher = AzerothCardBinderMinimapButton
    equal(launcher.parent, Minimap)
    window:Hide()
    UIParent.width = 776
    launcher:OnClick()
    equal(window:IsShown(), true)
    assert(window.scale < 1)
    launcher:OnClick()
    equal(window:IsShown(), false)
    launcher:OnDragStart()
    launcher:OnUpdate()
    launcher:OnDragStop()
    equal(launcher.OnUpdate, nil)
    equal(AzerothCardBinderDB.minimapAngle, 90)
    equal(launcher.point[5], 73)
    UIParent.width = 1200
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
    target, dead, rank = guid(590, "rank"), true, "elite"
    draw = 100
    openLoot({ target, 1 })
    equal(rolls, before + 1)
    equal(AzerothCardBinderDB.counts["npc:590"], 1)
    target, dead, rank, draw = nil, nil, nil, 1
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
        if widget.OnEnterPressed and not widget.OnTextChanged then widget:SetText("Bob") break end
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
    click("Accept trade")
    equal(#sent, 1)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "R|" .. id .. "|npc:573", "WHISPER", "Bob")
    click("Accept trade")
    equal(sent[2], "C|" .. id .. "|" .. give .. "|npc:573")
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "C|" .. id .. "|npc:573|" .. give, "WHISPER", "Bob-RealmName")
    local complete
    for _, widget in ipairs(widgets) do
        if widget.text == ("Trade complete. You gave %s and received Foe Reaper 4000."):format(ACB.cards[give].name) then
            complete = true
        end
    end
    equal(complete, true)
    -- Neither side of the trade window shows a placeholder such as "?" for a received card.
    for _, widget in ipairs(widgets) do
        assert(widget.text ~= "?" and widget.text ~= "??", "placeholder text on screen")
    end
    equal(AzerothCardBinderDB.counts[give], 1)
    equal(AzerothCardBinderDB.counts["npc:573"], 1)
end)

print(("%d checks passed under %s"):format(passed, _VERSION))
