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
loadAddon("Lore.lua")
loadAddon("Achievements.lua")
loadAddon("Collection.lua")
loadAddon("Trade.lua")

for _, rate in ipairs({
    { id = 589, limit = 100, rank = "normal" },
    { id = 639, limit = 200, rank = "elite" },
    { id = 573, limit = 1000, rank = "rare" },
    { id = 3586, limit = 1000, rank = "rareelite" },
    { id = 1731, limit = 100, rank = "gathering", kind = "GameObject" },
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
        local first, second = guid(rate.id, "A", rate.kind), guid(rate.id, "B", rate.kind)
        local origin = rate.kind and "gather" or "loot"
        equal(collection:roll(first, origin), true)
        equal(collection:roll(first, origin), nil)
        equal(collection:roll(second, origin), false)
        equal(collection:roll(second, origin), nil)
        equal(rolls, 2)
        equal(saved.counts[ACB.source(first).key], 1)
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

test("every card has lore that fits, is stable and says something about the card", function()
    local seen, count = {}, 0
    for _, page in ipairs(ACB.pages) do
        for _, card in ipairs(page.cards) do
            count = count + 1
            assert(type(card.lore) == "string" and #card.lore >= 12, "lore for " .. card.name)
            assert(#card.lore <= 80, ("lore too long for %s (%d): %s"):format(card.name, #card.lore, card.lore))
            assert(not card.lore:find("%%s") and not card.lore:find("nil"), "unfilled lore for " .. card.name .. ": " .. card.lore)
            seen[card.lore] = true
            if card.generated and not card.profession then equal(ACB.loreFor(card), card.lore) end
        end
    end
    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    assert(distinct > 1200, "lore should not be one line repeated, only " .. distinct .. " of " .. count .. " lines are different")
    -- Bosses, named groups, kinds of creature and nodes each get fitting lines.
    assert(ACB.cards["npc:15990"].lore:find("lich", 1, true)) -- Kel'Thuzad
    assert(ACB.cards["npc:639"].lore:find("Founder of the Defias", 1, true)) -- hand-made lore is kept
    local scarlet
    for _, card in ipairs(ACB.pages[ACB.pageForPlace["scarlet-monastery"] or 2].cards) do
        if card.name:find("Scarlet", 1, true) then scarlet = card break end
    end
    assert(scarlet and scarlet.lore:find("Scarlet Crusade", 1, true), "Scarlet creatures mention the Crusade")
    assert(ACB.cards["node:1617"].lore:find("silvery", 1, true)) -- Silverleaf
    assert(ACB.cards["node:1731"].lore:find("Reddish ore", 1, true)) -- the hand-made node keeps its line
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
    assert(ACB.cards["node:175404"].lore:find("thorium", 1, true))
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
    assert(count > 3000, "the catalog should hold thousands of cards, has " .. count)
    -- Only neutral and hostile creatures: nothing that is friendly to one faction, so no guards or faction leaders.
    equal(ACB.cards["npc:1423"], nil) -- Stormwind Guard
    equal(ACB.cards["npc:10162"], nil) -- Lord Victor Nefarius, friendly to both
    assert(ACB.cards["npc:639"], "hostile creatures stay")
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
    equal(limit, 100) -- a 1% card
    equal(select(2, ACB.luck(saved, ACB.cards["npc:639"])), 50) -- a 2% card
    equal(select(2, ACB.luck(saved, ACB.cards["npc:573"])), 10) -- a 10% card
    equal(select(2, ACB.luck(saved, ACB.cards["node:1731"])), 100)
    for attempt = 1, limit - 1 do
        equal(collection:roll(guid(589, "miss" .. attempt), "loot"), false)
    end
    equal(saved.counts["npc:589"], nil)
    equal(ACB.luck(saved, ACB.cards["npc:589"]), limit - 1)
    equal(ACB.luckText(saved, ACB.cards["npc:589"]), "Next attempt guaranteed")
    local before = draws
    equal(collection:roll(guid(589, "lucky"), "loot"), true)
    equal(draws, before) -- the guaranteed drop needs no roll
    equal(saved.counts["npc:589"], 1)
    equal(ACB.luck(saved, ACB.cards["npc:589"]), 0)
    equal(collection:roll(guid(589, "after"), "loot"), false)
    equal(ACB.luckText(saved, ACB.cards["npc:589"]), "Bad luck: 1%")
    saved.misses["npc:639"] = 51 -- misses banked before the new cap
    equal(collection:roll(guid(639, "legacy"), "loot", "normal"), true)
    equal(ACB.luck(saved, ACB.cards["npc:639"]), 0)
    ACB.pityFactor = 0 -- switched off
    for attempt = 1, 300 do collection:roll(guid(589, "off" .. attempt), "loot") end
    equal(saved.counts["npc:589"], 1)
    ACB.pityFactor = 1
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

test("milestones use unique cards, backfill sets and keep a lifetime trade count", function()
    local saved = { counts = {}, shiny = {}, achievements = { crew = true }, history = {} }
    local westfall = ACB.pages[2]
    for index = 1, 9 do saved.counts[westfall.cards[index].key] = 5 end
    saved.shiny[westfall.cards[1].key] = true
    saved.shiny[westfall.cards[10].key] = true -- A shiny with no owned copy does not count.
    ACB.updateAchievements(saved)
    equal(ACB.achievementTotals(saved).cards, 9)
    equal(ACB.achievementTotals(saved).shiny, 1)
    equal(saved.achievements.cards10, nil)
    equal(saved.titles["Shiny Seeker"], true)
    equal(saved.titles["Defias Bane"], true)
    for _, card in ipairs(westfall.cards) do saved.counts[card.key] = 1 end
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore)
    collection:restoreAchievements()
    equal(saved.sets[westfall.code], true)
    equal(saved.titles["Card Seeker"], true)
    equal(saved.titles["Set Keeper"], true)
    equal(saved.titles[westfall.reward], true)
    equal(saved.title, nil)
    for i = 1, 20 do saved.history[i] = { give = "npc:589", take = "npc:639" } end
    local announcements = 0
    for i = 1, 6 do
        ACB.logTrade(saved, "npc:589", "npc:639", "bob-realm", i, function(message)
            if message:find("Spare for Spare", 1, true) then announcements = announcements + 1 end
        end)
    end
    equal(saved.tradeCount, 26)
    equal(#saved.history, 20)
    equal(saved.titles["Card Broker"], true)
    equal(announcements, 1)
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
    SetDesaturated = function(self, desaturated) self.desaturated = desaturated end,
    SetAlpha = function(self, alpha) self.alpha = alpha end, SetMultiLine = ignore,
    SetFontObject = ignore, SetScrollChild = ignore, SetVerticalScroll = ignore, HighlightText = ignore,
    ClearFocus = ignore, SetClipsChildren = ignore,
    SetColorTexture = function(self) self.colorTexture = true end, SetFont = ignore, SetBlendMode = ignore,
    SetVertexColor = function(self, r, g, b) self.vertex = { r, g, b } end,
    SetFrameLevel = function(self, level) self.level = level end,
    GetFrameLevel = function(self) return self.level or 1 end, SetMaxLines = ignore,
    SetChecked = function(self, value) self.checked = value end, GetChecked = function(self) return self.checked end,
    SetWordWrap = ignore, SetRotation = ignore, SetShadowOffset = ignore, SetSpacing = ignore, SetShadowColor = ignore, GetStringWidth = function() return 6 end, SetJustifyV = ignore, ClearAllPoints = ignore,
    SetKeepModelOnHide = function(self, keep) self.keepModel = keep end,
    ClearModel = function(self) self.creature, self.fileID, self.frozen = nil, nil, nil end,
    SetCreature = function(self, creature) self.creature = creature end,
    SetModel = function(self, file) self.fileID = file end,
    GetModelFileID = function(self) return self.fileID end,
    SetDesaturation = function(self, strength) self.desaturation = strength end,
    SetModelAlpha = function(self, alpha) self.modelAlpha = alpha end,
    SetPortraitZoom = function(self, zoom) self.portraitZoom = zoom end,
    SetCamDistanceScale = ignore, SetFacing = function(self, facing) self.facing = facing end, SetPosition = ignore, SetPaused = ignore,
    HasAnimation = function(self, animation) return self.supportedAnimation == animation end,
    FreezeAnimation = function(self, animation, variation, frame) self.frozen = { animation, variation, frame } end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetShown = function(self, shown) self.shown = shown end,
    IsShown = function(self) return self.shown end,
    IsMouseOver = function(self) return self.mouseOver ~= false end,
    GetEffectiveScale = function(self) return self.scale or 1 end,
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
local cursorX, shiftDown, leftDown = 80, false, false
function GetCursorPosition() return cursorX, 140 end
function IsShiftKeyDown() return shiftDown end
function IsMouseButtonDown(button) return button == "LeftButton" and leftDown end

local chatFilters, chatCallbacks = {}, {}
local draft, activeChat
ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback) chatFilters[event] = callback end,
    OpenChat = function(message) draft = message end,
    GetActiveWindow = function() return activeChat end,
}
EventRegistry = {
    RegisterCallback = function(_, event, callback, owner)
        chatCallbacks[event] = function(...) callback(owner, ...) end
    end,
}

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
loadAddon("Settings.lua")
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

test("the Achievements tab lists earned titles and lets the player equip and hide one", function()
    local saved = AzerothCardBinderDB
    local originalTitles, originalAchievements, originalHidden = saved.titles, saved.achievements, saved.titleHidden
    saved.titles, saved.achievements = { ["Card Trader"] = true }, { trades1 = true }
    for _, widget in ipairs(widgets) do
        if widget.text == "Achievements" and widget.OnClick then widget:OnClick() break end
    end
    local choose, hide, status
    for _, widget in ipairs(widgets) do
        if widget.title == "Card Trader" and widget.OnClick then choose = widget end
        if widget.text == "Hide title" then hide = widget.parent end
        if widget.text == "1 / 18 achievements earned" then status = widget end
    end
    assert(status and choose and hide)
    choose:OnClick()
    equal(saved.title, "Card Trader")
    hide:OnClick()
    equal(saved.title, nil)
    equal(saved.titleHidden, true)
    saved.titles, saved.achievements, saved.titleHidden = originalTitles, originalAchievements, originalHidden
    ACB.open(1)
end)

test("cards draw for missing, owned and gathering entries", function()
    AzerothCardBinderDB.counts["npc:639"] = 2
    AzerothCardBinderDB.counts["node:1731"] = 1
    ACB.open(1)
    ACB.open(2)
    ACB.open(3)
    AzerothCardBinderDB.counts["npc:639"], AzerothCardBinderDB.counts["node:1731"] = nil, nil
end)

test("opening a set queues later portraits and leaving the set stops the loader", function()
    local cards = ACB.pages[2].cards
    local loader
    for _, widget in ipairs(widgets) do
        if widget.width == 2 and widget.height == 2 and widget.OnUpdate then loader = widget break end
    end
    assert(loader)
    ACB.open("index")
    equal(loader:IsShown(), false)
    ACB.openCard(cards[1].key)
    equal(loader:IsShown(), true)
    equal(loader.creature, nil)
    loader:OnUpdate(0.08)
    equal(loader.creature, cards[5].id)
    loader:OnUpdate(0.2)
    equal(loader.creature, cards[5].id) -- still waiting on the first model
    loader.fileID = 123456
    loader:OnUpdate(0.08)
    equal(loader.creature, cards[6].id)
    loader:OnUpdate(1)
    equal(loader.creature, cards[7].id) -- one missing model cannot block the queue
    ACB.open("index")
    equal(loader:IsShown(), false)
    equal(loader.creature, nil)
    ACB.openCard(cards[1].key)
    loader:OnUpdate(0.08)
    equal(loader.creature, cards[6].id) -- card 5 already loaded, card 6 can retry
    loader.parent:OnHide() -- closing the binder dispatches this on the live client
    equal(loader:IsShown(), false)
end)

test("missing models appear in the pocket and detail and regain colour when collected", function()
    local saved = AzerothCardBinderDB
    local edwin = ACB.cards["npc:639"]
    ACB.openCard(edwin.key)
    local models = {}
    for _, widget in ipairs(widgets) do
        if widget.creature == edwin.id then
            local frame = widget.parent.parent
            if frame.scale == 0.60 or frame.scale == 1.48 then
                assert(frame.parent.parent:IsShown() ~= false)
                equal(frame.OnUpdate ~= nil, frame.scale == 1.48)
                models[frame.scale] = widget
                equal(widget:IsShown(), true)
                equal(widget.desaturation, 1)
                assert(widget.modelAlpha > 0 and widget.modelAlpha < 1)
            end
        end
    end
    assert(models[0.60] and models[1.48])
    saved.counts[edwin.key] = 1
    ACB.refresh()
    for _, model in pairs(models) do
        equal(model.creature, edwin.id)
        equal(model.desaturation, 0)
        equal(model.modelAlpha, 1)
    end
    saved.counts[edwin.key] = nil
    ACB.openCard(ACB.pages[1].cards[1].key)
end)

test("tooltip hints say whether a card is owned and where to find it", function()
    local saved = AzerothCardBinderDB
    local card = ACB.cards["npc:589"]
    saved.counts["npc:589"], saved.misses["npc:589"] = nil, 120
    local lines = ACB.hintLines(saved, card)
    equal(lines[1][1], "Card: not in your binder yet (1% chance)")
    equal(lines[2][1], "Next attempt guaranteed")
    saved.counts["npc:589"] = 2
    equal(ACB.hintLines(saved, card)[1][1], "Card: in your binder (x2)")
    saved.counts["npc:589"], saved.misses["npc:589"] = nil, nil
    equal(ACB.whereToFind(card), "Defeat it in Westfall.")
    equal(ACB.whereToFind(ACB.cards["npc:639"]), "Defeat this boss in the Deadmines in Westfall.")
    equal(ACB.whereToFind(ACB.cards["node:1731"]), "Gather it in Elwynn Forest and other starting zones.")

    local added = {}
    local tip = { AddLine = function(_, text) added[#added + 1] = text end, Show = ignore }
    hintCallbacks[1](tip, { guid = guid(589, "tip") })
    equal(added[1], "Card: not in your binder yet (1% chance)")
    added = {}
    hintCallbacks[1](tip, { guid = guid(99999, "unknown") })
    hintCallbacks[1](tip, { guid = secret })
    equal(#added, 0) -- unknown and unreadable sources add nothing
    saved.hints = false
    hintCallbacks[1](tip, { guid = guid(589, "tip") })
    equal(#added, 0)
    saved.hints = nil
end)

test("player tooltip titles come from solicited replies and an equipped title can be hidden", function()
    local originalTooltip, originalUnitGUID, originalUnitFullName = GameTooltip, UnitGUID, UnitFullName
    local saved = AzerothCardBinderDB
    local peerGUID, currentGUID = "Player-1-00000001", "Player-1-00000001"
    local messages, lines, refreshes = {}, {}, 0
    GameTooltip = {
        GetUnit = function() return "Bob", "mouseover" end,
        GetPrimaryTooltipData = function() return { guid = currentGUID } end,
        IsShown = function() return true end,
        AddLine = function(_, line) lines[#lines + 1] = line end,
        RefreshDataNextUpdate = function() refreshes = refreshes + 1 end,
    }
    UnitGUID = function(unit)
        if unit == "mouseover" then return currentGUID end
        return originalUnitGUID(unit)
    end
    UnitFullName = function(unit)
        if unit == "mouseover" then return "Bob", "Realm Name" end
        return originalUnitFullName(unit)
    end
    Enum.SendAddonMessageResult = { Success = 0 }
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, peer)
        equal(prefix, ACB.viewPrefix)
        equal(channel, "WHISPER")
        equal(peer, "bob-realmname")
        messages[#messages + 1] = message
        return 0
    end
    local function receive(message, sender)
        emit("CHAT_MSG_ADDON", ACB.viewPrefix, message, "WHISPER", sender or "Bob-RealmName")
    end
    local function hover()
        hintCallbacks[1](GameTooltip, { guid = peerGUID })
    end
    receive("T|Card Trader")
    hintCallbacks[1](GameTooltip, { guid = secret })
    hover()
    hover()
    equal(#messages, 1)
    equal(messages[1], "T?")
    equal(#lines, 0)
    receive("T||Hspoof|h", "Bob-RealmName")
    receive("T|Card Trader", "Mallory-RealmName")
    equal(refreshes, 0)
    receive("T|Card Trader")
    equal(refreshes, 1)
    hover()
    equal(lines[1], "Binder title: Card Trader")
    equal(#messages, 1)

    local start = clock
    clock = clock + 46
    hover()
    equal(messages[2], "T?")
    currentGUID = "Player-1-00000002"
    receive("T|Foil Hunter")
    equal(refreshes, 1)
    saved.titles["Card Trader"] = true
    ACB.selectTitle(saved, "Card Trader")
    receive("T?")
    equal(messages[3], "T|Card Trader")
    receive("T?")
    equal(#messages, 3)
    clock = clock + 6
    ACB.selectTitle(saved)
    receive("T?")
    equal(messages[4], "T|")

    GameTooltip, UnitGUID, UnitFullName = originalTooltip, originalUnitGUID, originalUnitFullName
    saved.titles["Card Trader"], saved.titleHidden = nil, nil
    Enum.SendAddonMessageResult, C_ChatInfo.SendAddonMessage, clock = nil, nil, start
end)

test("binder requests use the addon whisper result when the general chat flags are unavailable", function()
    local originalSend, originalFlag = C_ChatInfo.SendAddonMessage, C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    local originalCodes = Enum.SendAddonMessageResult
    local result, sends = 0, 0
    Enum.SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11, TargetOffline = 12 }
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return secret end
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, peer)
        equal(prefix, ACB.viewPrefix)
        equal(message, "Q")
        equal(channel, "WHISPER")
        equal(peer, "carol-realmname")
        sends = sends + 1
        return result
    end
    equal(ACB.requestBinder("carol-realmname"), true)
    result = 11
    local sent, reason = ACB.requestBinder("carol-realmname")
    equal(sent, false)
    equal(reason, "Forever is blocking addon whispers right now.")
    equal(sends, 2)
    C_ChatInfo.SendAddonMessage, C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = originalSend, originalFlag
    Enum.SendAddonMessageResult = originalCodes
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

test("shift-click drafts a link and the recipient opens the exact card with local counts", function()
    local saved = AzerothCardBinderDB
    local edwin = ACB.cards["npc:639"]
    ACB.openCard(edwin.key)
    local pocket, detail, stats
    for _, widget in ipairs(widgets) do
        if widget.text == edwin.name and widget.parent.OnClick then pocket = widget.parent end
        if widget.OnMouseUp and widget.OnMouseDown and widget.scale == 1.48 then detail = widget end
        if widget.text == "BASE DROP CHANCE" then stats = widget.parent end
    end
    assert(pocket and detail and stats)
    saved.counts[edwin.key], saved.shiny[edwin.key] = 1, true
    shiftDown = true
    pocket:OnClick()
    equal(draft, "[ACB:npc:639:1 Edwin VanCleef (Shiny)]")
    local sent = draft

    ACB.open("index")
    draft = "Look at "
    activeChat = { Insert = function(_, text) draft = draft .. text end, SetFocus = ignore }
    detail:OnMouseDown("LeftButton")
    detail:OnMouseUp("LeftButton")
    equal(draft, "Look at " .. sent)
    activeChat, shiftDown = nil, false

    local event = "CHAT_MSG_WHISPER"
    local filter = assert(chatFilters[event])
    equal(filter(nil, event, secret), nil)
    equal(filter(nil, event, "[ACB:npc:99999:1 Unknown]"), nil)
    local skip, rendered, sender = filter(nil, event, "Check " .. sent .. "!", "Bob")
    equal(skip, false)
    equal(rendered, "Check " .. ACB.cardLink(edwin, true) .. "!")
    equal(sender, "Bob")

    saved.counts[edwin.key], saved.shiny[edwin.key] = 3, nil
    ACB.open(2)
    AzerothCardBinderWindow:Hide()
    chatCallbacks.SetItemRef("item:1", "", "LeftButton")
    equal(AzerothCardBinderWindow:IsShown(), false)
    chatCallbacks.SetItemRef(rendered:match("|H(.-)|h"), rendered, "LeftButton")
    equal(AzerothCardBinderWindow:IsShown(), true)
    local found, counts = {}, {}
    for _, widget in ipairs(widgets) do
        found[widget.text or ""] = true
        if widget.parent == stats then counts[widget.text or ""] = true end
    end
    equal(found[("Page 2 of %d"):format(math.ceil(#ACB.pages[edwin.page].cards / 4))], true)
    equal(found["SELECTED CARD  /  DM 08"], true)
    equal(found["3 owned / 2 spare"], true)
    equal(counts["3"] and counts["2"], true)
    saved.counts[edwin.key] = nil
    ACB.openCard(ACB.pages[1].cards[1].key)
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
    ACB.receiveView("alice-realm", sentToB[2] .. ",c99999=4") -- unknown cards are dropped
    equal(#shown, 1)
    equal(shown[1].peer, "alice-realm")
    equal(shown[1].counts["npc:589"], 3)
    equal(shown[1].shiny["npc:639"], true)
    equal(shown[1].counts["npc:99999"], nil)
    local lines = ACB.inspectLines(shown[1].counts, shown[1].shiny)
    local deadminesCards = #ACB.pages[1].cards
    assert(lines[1]:find(("^%d of %%d+ cards collected, 1 shiny$"):format(deadminesCards + 1)))
    local text = table.concat(lines, " ")
    assert(text:find(("Deadmines   %d / %d"):format(deadminesCards, deadminesCards), 1, true))
    assert(text:find("Westfall   1 / %d+"))
    -- Garbage is dropped.
    ACB.receiveView("alice-realm", "B|9/2|npc:589=2")
    ACB.receiveView("alice-realm", "B|1/2|<script>")
    ACB.receiveView("alice-realm", string.rep("x", 300))
    equal(#shown, 1)
end)

test("a fully collected binder fits the message limit and arrives within the request window", function()
    local full, timers = { counts = {}, shiny = {} }, {}
    for key in pairs(ACB.cards) do
        full.counts[key], full.shiny[key] = 99, true
    end
    local now, received, show
    now = 100
    ACB.initSocial(full, function(_, message)
        assert(#ACB.viewPrefix + 1 + #message <= 255, "addon whisper exceeds the message budget")
        received("alice-realm", message)
        return true
    end, function() return now end, function(delay, action)
        timers[#timers + 1] = { due = now + delay, run = action }
    end)
    local sendResponse = ACB.receiveView
    sendResponse("bob-realm", "Q")
    assert(#timers > 150)
    ACB.initSocial({ counts = {} }, function() return true end, function() return now end, ignore)
    received = ACB.receiveView
    ACB.showInspect = function(_, counts, shiny) show = { counts = counts, shiny = shiny } end
    assert(ACB.requestBinder("alice-realm"))
    for _, timer in ipairs(timers) do
        now = timer.due
        timer.run()
    end
    assert(show, "the last part arrived too late")
    for key in pairs(ACB.cards) do
        equal(show.counts[key], 99)
        equal(show.shiny[key], true)
    end
end)

test("player and enemy portrait menus offer the relevant binder actions", function()
    local callbacks = {}
    Menu = { ModifyMenu = function(tag, callback) callbacks[tag] = callback end }
    ACB.initSocial({ counts = {} }, function() return true end, function() return 1 end, function(_, action) action() end)
    Menu = nil
    local playerMenu = assert(callbacks.MENU_UNIT_PLAYER)
    local targetMenu = assert(callbacks.MENU_UNIT_TARGET)
    assert(callbacks.MENU_UNIT_FOCUS and callbacks.MENU_UNIT_BOSS)
    local buttons = {}
    local root = { CreateDivider = ignore, CreateButton = function(_, text, action) buttons[text] = action end }
    playerMenu(nil, root, { name = "Bob", server = "RealmName" })
    assert(buttons["Offer a card trade"] and buttons["View their binder"])
    AzerothCardBinderWindow:Hide()
    buttons["Offer a card trade"]()
    equal(AzerothCardBinderWindow:IsShown(), true)
    buttons = {}
    playerMenu(nil, root, { name = secret })
    playerMenu(nil, root, nil)
    equal(next(buttons), nil) -- unreadable or missing players get no entries
    target = secret
    targetMenu(nil, root, { unit = "target" })
    equal(next(buttons), nil)
    target = guid(639, "portrait")
    targetMenu(nil, root, { unit = "target" })
    assert(buttons["Open card in binder"])
    AzerothCardBinderWindow:Hide()
    buttons["Open card in binder"]()
    equal(AzerothCardBinderWindow:IsShown(), true)
    target = nil
    ACB.openCard(ACB.pages[1].cards[1].key)
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

test("card studs follow the rarity colour, sit above the text, and the serial number shows", function()
    local card = ACB.createCard(UIParent)
    card:set(ACB.cards["npc:639"], 1) -- legendary
    local legendary, epic = ACB.rarities.legendary.color, ACB.rarities.epic.color
    equal(#card.studs, 4)
    for _, stud in ipairs(card.studs) do
        equal(stud.vertex[1], legendary[1])
        equal(stud.vertex[2], legendary[2])
        equal(stud.vertex[3], legendary[3])
    end
    assert(card.studFrame.level > card.textBox.level, "studs sit above the text box")
    assert(card.studFrame.level > card.badges.level + 1, "studs sit above the name and count badges")
    equal(card.serial.text, "No. 000639")
    card:set(ACB.cards["npc:573"], 1) -- epic
    equal(card.studs[3].vertex[1], epic[1])
    equal(card.serial.text, "No. 000573")
    card:set(ACB.cards["node:1731"], 1)
    equal(card.serial.text, "No. N01731")
    card:set(ACB.cards["npc:639"], 0) -- missing cards use the same muted finish on the studs and gem
    for channel = 1, 3 do equal(card.studs[1].vertex[channel], card.gem.vertex[channel]) end
    assert(card.studs[1].vertex[1] < legendary[1])
    equal(card.serial.text, "No. 000639")
end)

test("sets are listed by level, then by name", function()
    local order = ACB.setOrder()
    equal(#order, #ACB.pages)
    local last, position = 0, {}
    for place, index in ipairs(order) do
        local page = ACB.pages[index]
        local low = page.levelMid or 1000
        assert(low >= last, page.title .. " is out of level order")
        last = low
        position[page.zone] = place
    end
    assert(position["elwynn-forest"] < position["deadmines"], "level 1 zones come before dungeons")
    assert(position["deadmines"] < position["blackrock-depths"])
    assert(position["westfall"] < position["blackrock-depths"])
    assert(position["blackrock-depths"] < position["molten-core"], "raids come last")
    -- Set numbers are untouched by the listing order.
    equal(ACB.pages[1].title, "Deadmines")
    equal(ACB.pages[2].title, "Westfall")
end)

test("owned cards show rarity tint and the moving foil only plays for shiny copies", function()
    local card = ACB.createCard(UIParent)
    card:set(ACB.cards["npc:639"], 1, true)
    equal(card.foil:IsShown(), true)
    equal(card.tint:IsShown(), true)
    local band
    for _, widget in ipairs(widgets) do
        if widget.parent == card.foil and widget.width and widget.height then band = widget end
    end
    assert(band)
    card.foil:OnUpdate(0.5)
    assert(band.point[4] > 0 and band.point[4] + band.width < card.model.width)
    assert(band.alpha > 0)
    card.foil:OnUpdate(1.5)
    equal(band.alpha, 0)
    card:set(ACB.cards["npc:639"], 1, false)
    equal(card.foil:IsShown(), false)
    equal(card.tint:IsShown(), true)
    card:set(ACB.cards["npc:639"], 0, true)
    equal(card.foil:IsShown(), false)
    equal(card.tint:IsShown(), false)
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

test("cinematic detail sways, pauses for dragging and keeps the combat pose", function()
    local card = ACB.createCard(UIParent, true, ignore)
    card:set(ACB.cards["npc:639"], 0)
    equal(card.model.creature, 639)
    equal(card.model:IsShown(), true)
    equal(card.owned, 0)
    equal(card.model.frozen, nil)
    equal(card.art.base.texture, ACB.folioArt .. "Deadmines.tga")
    equal(card.art.base.desaturated, true)
    equal(card.veil:IsShown(), true)
    card.model.desaturation = nil -- Simulate the client completing a new load.
    card.model.fileID, card.model.supportedAnimation = 1000, 17
    card.model:OnModelLoaded()
    equal(card.model.desaturation, 1)
    equal(card.model.frozen[1], 17)
    equal(card.model.frozen[3], 24)
    local humanoidZoom = card.model.portraitZoom
    local defaultFacing = card.model.facing
    equal(defaultFacing, -0.47)
    card.frame:OnUpdate(2)
    local swing = card.model.facing - defaultFacing
    assert(swing > 0 and swing < math.rad(10))
    card.frame:OnUpdate(4)
    assert(math.abs(card.model.facing - (defaultFacing - swing)) < 0.0001)
    card.frame:OnUpdate(2)
    equal(card.model.facing, defaultFacing)

    card.model.mouseOver = false
    leftDown = true
    card.frame:OnMouseDown("LeftButton")
    cursorX = cursorX + 40
    card.frame:OnUpdate(0)
    equal(card.model.facing, defaultFacing)
    cursorX = cursorX - 40
    card.model.mouseOver = true
    card.frame:OnMouseDown("LeftButton")
    cursorX = cursorX + 40
    card.frame:OnUpdate(2)
    assert(math.abs(card.model.facing - 0.53) < 0.0001)
    equal(card.model.frozen[3], 24)
    leftDown = false
    cursorX = cursorX - 40
    card.frame:OnUpdate(2)
    assert(math.abs(card.model.facing - (0.53 + swing)) < 0.0001)

    card:set(ACB.cards["npc:573"], 0)
    card.model.fileID, card.model.supportedAnimation = 1001, nil
    card.model:OnModelLoaded()
    equal(card.model.frozen[1], 0)
    equal(card.model.facing, -0.34)
    assert(card.model.portraitZoom < humanoidZoom)
    equal(card.art.base.texture, ACB.folioArt .. "Westfall.tga")

    card:set(ACB.cards["node:1618"], 0)
    equal(card.model.fileID, ACB.cards["node:1618"].model)
    equal(card.model.frozen, nil)
    equal(card.node:IsShown(), false)
    equal(card.art.base.texture, ACB.folioArt .. "Elwynn.tga")
    card.frame:OnUpdate(2)
    assert(card.model.facing > 0.6)

    for _, entry in ipairs(ACB.pages[3].cards) do
        if not entry.model then
            card:set(entry, 0)
            equal(card.node:IsShown(), true)
            equal(card.node.desaturated, true)
            card.frame:OnUpdate(2)
            equal(card.model.facing, 0.6)
            card:set(entry, 1)
            equal(card.node:IsShown(), true)
            equal(card.node.desaturated, false)
            equal(card.veil:IsShown(), false)
            break
        end
    end

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
    equal(button("More").enabled, true) -- many zones, listed over several pages
    search:SetText("Westfall")
    search:OnTextChanged()
    equal(indexRow("Westfall"):IsShown(), true)
    search:SetText("%")
    search:OnTextChanged()
    findWidget(function(widget) return widget.text == "No matching sets or cards" end)
    search:SetText(" eDwin VaNcleef ")
    search:OnTextChanged()
    local cardRow = findWidget(function(widget) return widget.cardKey == "npc:639" end)
    equal(cardRow:IsShown(), true)
    cardRow:OnClick()
    findWidget(function(widget) return widget.text == "SELECTED CARD  /  DM 08" end)
    SlashCmdList.AZEROTHCARDBINDER("index")
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
    emit("LOOT_OPENED", true, false)
    for _, callback in ipairs(timers) do callback() end
    equal(rolls, 2)
    equal(AzerothCardBinderDB.counts["npc:589"], 2)
    openLoot({ a, 1 }, { b, 1 })
    equal(rolls, 2)
end)

test("ready-only loot advances the open binder's protection once per identified corpse", function()
    local saved = AzerothCardBinderDB
    local card, before = ACB.cards["npc:589"], rolls
    local spawn = guid(589, "ready-only")
    saved.misses[card.key] = nil
    draw = 10000
    ACB.openCard(card.key)
    slots = { { spawn, 1 } }
    emit("LOOT_READY", true)
    slots = {}
    timers[#timers]()
    equal(rolls, before + 1)
    equal(saved.misses[card.key], 1)
    local protection
    for _, widget in ipairs(widgets) do
        if widget.text == "Bad luck: 1%" then protection = widget end
    end
    assert(protection)
    openLoot({ spawn, 1 }) -- a later event or reopening the same corpse does not count again
    equal(rolls, before + 1)
    emit("LOOT_READY", true)
    slots = {}
    timers[#timers]()
    equal(rolls, before + 1)
    slots = { { "Item-1-00000001", 1, guid(589, "item-origin"), 1 } }
    emit("LOOT_READY", true)
    slots = {}
    timers[#timers]()
    equal(rolls, before + 1)
    saved.misses[card.key], draw = nil, 1
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
    draw = 200
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
    local tradesBefore = AzerothCardBinderDB.tradeCount
    Enum = { SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11 } }
    C_ChatInfo.SendAddonMessage = function(prefix, message, channel, peer)
        equal(prefix, ACB.tradePrefix)
        equal(channel, "WHISPER")
        equal(peer, "bob-realmname")
        if locked then return Enum.SendAddonMessageResult.AddOnMessageLockdown end
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
    equal(AzerothCardBinderDB.tradeCount, tradesBefore)
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "C|" .. id .. "|npc:573|" .. give, "WHISPER", "Bob-RealmName")
    emit("CHAT_MSG_ADDON", ACB.tradePrefix, "C|" .. id .. "|npc:573|" .. give, "WHISPER", "Bob-RealmName")
    equal(AzerothCardBinderDB.tradeCount, tradesBefore + 1)
    equal(AzerothCardBinderDB.titles["Card Trader"], true)
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

test("binder dust recycles spares, keeps the last copy, and crafts a missing card once", function()
    for rarity, yield in pairs(ACB.dust.recycle) do
        equal(ACB.dust.craft[rarity], yield * 10) -- ten spares pay for one card of the same rarity
    end
    local saved = { counts = { ["npc:589"] = 3, ["npc:573"] = 2, ["npc:639"] = 1 }, achievements = {}, dust = 0 }
    local finds = {}
    local collection = ACB.newCollection(saved, function() return 10000 end, ignore, ignore, function(card, info)
        finds[#finds + 1] = { card = card, info = info }
    end)
    local common, epic = ACB.dustFor(ACB.cards["npc:589"]), ACB.dustFor(ACB.cards["npc:573"])
    equal(collection:recycle("npc:639"), false) -- the only copy stays
    equal(saved.counts["npc:639"], 1)
    equal(collection:recycle("npc:589"), true)
    equal(collection:recycle("npc:589"), true)
    equal(collection:recycle("npc:589"), false)
    equal(saved.counts["npc:589"], 1)
    equal(collection:recycle("npc:573"), true)
    equal(saved.dust, common * 2 + epic)
    equal(collection:recycle("npc:99999"), false)

    local missing = ACB.cards["npc:590"]
    local _, cost = ACB.dustFor(missing)
    saved.misses = { ["npc:590"] = 7 }
    equal(collection:craft("npc:590"), false) -- not enough dust yet
    equal(saved.counts["npc:590"], nil)
    saved.dust = cost + 3
    equal(collection:craft("npc:590"), true)
    equal(saved.counts["npc:590"], 1)
    equal(saved.dust, 3)
    equal(saved.misses["npc:590"], nil) -- the bad-luck counter starts again
    equal(saved.shiny, nil) -- a crafted card is never shiny
    equal(#finds, 1)
    equal(finds[1].info.crafted, true)
    equal(finds[1].info.first, true)
    equal(collection:craft("npc:590"), false) -- you already own it
    equal(saved.dust, 3)
end)

test("the folio shows kills since the last drop and a dust button that recycles and crafts", function()
    local function widgetWithText(value)
        for _, widget in ipairs(widgets) do
            if widget.text == value then return widget end
        end
        error("missing widget: " .. value)
    end
    local saved = AzerothCardBinderDB
    local keep = { saved.dust, saved.misses["npc:639"], saved.counts["npc:639"], saved.counts["npc:590"] }
    local entry = ACB.cards["npc:639"]
    local yield, cost = ACB.dustFor(entry)
    local _, limit = ACB.luck(saved, entry)

    saved.counts["npc:639"], saved.misses["npc:639"], saved.dust = 2, 37, 0
    assert(ACB.openCard("npc:639"))
    widgetWithText(("Loot attempts: %d / %d"):format(37, limit))
    widgetWithText("Binder Dust: 0")
    local recycle = widgetWithText(("Recycle a spare: +%d dust"):format(yield))
    equal(recycle.parent.enabled, true)
    recycle.parent:OnClick()
    equal(saved.counts["npc:639"], 1)
    equal(saved.dust, yield)
    local single = widgetWithText("No spare to recycle")
    equal(single.parent.enabled, false)
    widgetWithText(("Binder Dust: %d"):format(yield))

    saved.counts["npc:639"], saved.dust = nil, 0
    ACB.openCard("npc:639")
    local short = widgetWithText(("Craft: %d dust (have 0)"):format(cost))
    equal(short.parent.enabled, false)
    saved.dust = cost
    ACB.openCard("npc:639")
    local craft = widgetWithText(("Craft this card: %d dust"):format(cost))
    equal(craft.parent.enabled, true)
    craft.parent:OnClick()
    equal(saved.counts["npc:639"], 1)
    equal(saved.dust, 0)

    -- A gathering node counts gathers, not kills.
    ACB.openCard("node:1731")
    widgetWithText(("Gather attempts: %d / %d"):format(0, select(2, ACB.luck(saved, ACB.cards["node:1731"]))))
    equal(ACB.openCard("npc:99999"), false)
    saved.dust, saved.misses["npc:639"], saved.counts["npc:639"], saved.counts["npc:590"] = unpack(keep, 1, 4)
    ACB.open("collection")
end)

test("the settings tab lists every switch, with defaults, and keeps slash commands in step", function()
    local saved = AzerothCardBinderDB
    local keep = { saved.popups, saved.hints, saved.inspectable, saved.diagnostics, saved.bossTrial, saved.title, saved.titles }
    saved.popups, saved.hints, saved.inspectable, saved.diagnostics, saved.bossTrial = nil, nil, nil, nil, nil
    equal(ACB.settingOn(saved, "popups"), true) -- on until switched off
    equal(ACB.settingOn(saved, "diagnostics"), false) -- off until switched on
    equal(ACB.setSetting(saved, "nonsense", true), false)
    equal(ACB.setSetting(saved, "hints", false), true)
    equal(saved.hints, false)
    equal(ACB.settingOn(saved, "hints"), false)
    saved.hints = nil

    local checks = {}
    ACB.open("settings")
    for _, widget in ipairs(widgets) do
        if widget.template == "UICheckButtonTemplate" then checks[#checks + 1] = widget end
    end
    equal(#checks, #ACB.settings)
    for index, setting in ipairs(ACB.settings) do
        equal(checks[index].checked, setting.default)
    end
    equal(AzerothCardBinderWindow:IsShown(), true)

    -- Ticking a box changes the saved switch the game already reads.
    checks[1].checked = false
    checks[1]:OnClick()
    equal(saved.popups, false)
    checks[4].checked = true
    checks[4]:OnClick()
    equal(saved.diagnostics, true)
    -- The slash command flips the same switch and the open tab follows.
    SlashCmdList.AZEROTHCARDBINDER("hints")
    equal(saved.hints, false)
    equal(checks[2].checked, false)
    SlashCmdList.AZEROTHCARDBINDER("popup")
    equal(saved.popups, true)
    equal(checks[1].checked, true)

    -- Titles step through the earned ones, with none as the first stop.
    local first, second = ACB.pages[1].reward, ACB.pages[2].reward
    saved.titles, saved.title = { [first] = true, [second] = true }, nil
    equal(ACB.cycleTitle(saved, 1), first)
    equal(ACB.cycleTitle(saved, 1), second)
    equal(ACB.cycleTitle(saved, 1), nil)
    equal(ACB.cycleTitle(saved, -1), second)
    saved.titles, saved.title = {}, nil
    equal(ACB.cycleTitle(saved, 1), nil)
    saved.titles = { [first] = true }
    local function click(label)
        for _, widget in ipairs(widgets) do
            if widget.text == label and widget.OnClick then widget:OnClick() return end
        end
        error("button not found: " .. label)
    end
    click("Next title")
    equal(saved.title, first)
    click("Previous title")
    equal(saved.title, nil)
    click("Test pop-up")

    saved.popups, saved.hints, saved.inspectable, saved.diagnostics, saved.bossTrial, saved.title, saved.titles = unpack(keep, 1, 7)
    ACB.open("collection")
end)

test("artwork falls back from the journal to loading screens to the zone a dungeon sits in", function()
    local function artFor(slug)
        local entry = ACB.pages[ACB.pageForPlace[slug]].cards[1]
        local card = ACB.createCard(UIParent)
        card:set(entry, 1)
        return card.art
    end
    -- 1. The Dungeon Journal knows the place (listed with "The" in front).
    EJ_GetInstanceByIndex = function(position, raid)
        if position == 1 and raid == false then return 240, "The Wailing Caverns" end
    end
    EJ_GetInstanceInfo = function(id) return "name", "text", 9001 end
    equal(artFor("wailing-caverns").base.texture, 9001)
    EJ_GetInstanceByIndex, EJ_GetInstanceInfo = nil, nil

    -- 2. A loading screen named after the place.
    local asked = {}
    GetFileIDFromPath = function(path)
        asked[#asked + 1] = path
        if path == "Interface\\Glues\\LoadingScreens\\LoadScreenRazorfenKraul" then return 9002 end
    end
    equal(artFor("razorfen-kraul").base.texture, 9002)
    GetFileIDFromPath = nil

    -- 3. No picture of its own: the map of the zone it sits in (Maraudon is in Desolace).
    C_Map = {
        GetMapChildrenInfo = function() return { { name = "Desolace", mapID = 101 } } end,
        GetMapArtLayers = function(map) return map == 101 and { { layerWidth = 2, layerHeight = 1, tileWidth = 1, tileHeight = 1 } } or nil end,
        GetMapArtLayerTextures = function() return { 9003, 9004 } end,
    }
    local art = artFor("maraudon")
    C_Map = nil
    equal(art.tiles[1].texture, 9003)
    equal(art.tiles[2].texture, 9004)
    equal(ACB.zones.maraudon.parent, "Desolace")
    for slug in pairs(ACB.instanceZones) do assert(ACB.zones[slug], "every instance names a place that exists: " .. slug) end
end)

print(("%d checks passed under %s"):format(passed, _VERSION))
