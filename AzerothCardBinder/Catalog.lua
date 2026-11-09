local _, ACB = ...

-- A card you find for the first time has a 1 in `shinyOdds` chance to be a shiny copy.
ACB.shinyOdds = 20
-- Bad-luck safety net: a card whose source has missed this many times its expected number of
-- attempts is guaranteed on the next one. A 0.5% card is guaranteed on the 500th attempt, 1% on the
-- 250th and 5% on the 50th. Set to 0 to switch the safety net off.
ACB.pityFactor = 2.5
ACB.rates = { normal = 50, elite = 100, rare = 500, rareelite = 500, gathering = 50 }
ACB.pages = {
    { title = "Deadmines", zone = "deadmines", group = "Dungeon", code = "DM", reward = "Defias Delver", subtitle = "The Defias hideout", cards = {} },
    { title = "Westfall", zone = "westfall", group = "Zone", code = "WF", reward = "Westfall Warden", subtitle = "The fields beyond Sentinel Hill", cards = {} },
    { title = "Gathering", zone = "elwynn", group = "Profession", code = "GA", reward = "Fieldhand", levelMin = 1, levelMax = 60, levelMid = 1, subtitle = "Finds from the field", cards = {} },
}
ACB.cards, ACB.sources = {}, { Creature = {}, GameObject = {} }

-- Packaged portrait backdrops take priority, followed by client artwork and a fallback gradient.
ACB.zones = {
    deadmines = {
        name = "Deadmines", kind = "Dungeon",
        backdrop = "Deadmines.tga", place = "the Deadmines in Westfall",
        journal = 63, map = 55,
        paths = { "Interface\\Glues\\LoadingScreens\\LoadScreenDeadmines" },
        top = { 0.36, 0.22, 0.11 }, bottom = { 0.07, 0.04, 0.03 },
    },
    westfall = {
        name = "Westfall", kind = "Zone",
        backdrop = "Westfall.tga", place = "Westfall",
        map = 52,
        paths = { "Interface\\Glues\\LoadingScreens\\LoadScreenWestfall" },
        top = { 0.80, 0.64, 0.30 }, bottom = { 0.22, 0.30, 0.12 },
    },
    gathering = {
        name = "Gathering", kind = "Profession", place = "zones across the world",
        top = { 0.42, 0.52, 0.34 }, bottom = { 0.10, 0.15, 0.09 },
    },
    elwynn = {
        backdrop = "Elwynn.tga", place = "Elwynn Forest and other starting zones",
        map = 37,
        paths = { "Interface\\Glues\\LoadingScreens\\LoadScreenElwynnForest" },
        top = { 0.45, 0.66, 0.78 }, bottom = { 0.12, 0.27, 0.12 },
    },
}

-- Gem colours follow the game's item quality colours.
ACB.rarities = {
    common = { name = "Common", color = { 1, 1, 1 } },
    rare = { name = "Rare", color = { 0, 0.44, 0.87 } },
    epic = { name = "Epic", color = { 0.64, 0.21, 0.93 } },
    legendary = { name = "Legendary", color = { 1, 0.50, 0 } },
}

-- Bosses are legendary, gathering nodes rare, ordinary enemies common and every other
-- elite or rare enemy epic.
local function rarityOf(entry)
    if entry.profession then return "rare" end
    if entry.boss then return "legendary" end
    if entry.rank == "normal" then return "common" end
    return "epic"
end

-- `model` is the file ID of a gathering node's 3D model (world/generic/passivedoodads/tradeskillnodes).
local function card(page, zone, id, name, rank, icon, lore, boss, profession, model)
    local kind = profession and "GameObject" or "Creature"
    local key = (profession and "node:" or "npc:") .. id
    local entry = {
        key = key, id = id, name = name, rank = rank, icon = "Interface\\Icons\\" .. icon,
        boss = boss, profession = profession, page = page, zone = zone, lore = lore, model = model,
        -- A stable serial number: the game's own id, with an N for nodes so it never clashes with a creature.
        serial = profession and ("N%05d"):format(id) or ("%06d"):format(id),
    }
    entry.rarity = rarityOf(entry)
    ACB.cards[key] = entry
    ACB.sources[kind][id] = entry
    table.insert(ACB.pages[page].cards, entry)
end

card(1, "deadmines", 644, "Rhahk'Zor", "elite", "INV_Hammer_09",
    "A hulking ogre hired to bar the Defias hideout.", true)
card(1, "deadmines", 643, "Sneed", "elite", "INV_Weapon_ShortBlade_02",
    "Foreman of the lumber works, he rides a giant Shredder.", true)
card(1, "deadmines", 3586, "Miner Johnson", "rareelite", "INV_Pick_02",
    "A lone Defias digger who guards his own rich tunnel.", true)
card(1, "deadmines", 1763, "Gilnid", "elite", "INV_Hammer_18",
    "Overseer of the foundry that smelts the gang's gold.", true)
card(1, "deadmines", 646, "Mr. Smite", "elite", "INV_Hammer_19",
    "First mate of the Defias fleet. His hammer ends arguments.", true)
card(1, "deadmines", 647, "Captain Greenskin", "elite", "INV_Sword_24",
    "Master of the ship moored beneath the mine.", true)
card(1, "deadmines", 645, "Cookie", "elite", "INV_Misc_Food_10",
    "The crew's cook. Nobody asks what is in the stew.", true)
card(1, "deadmines", 639, "Edwin VanCleef", "elite", "INV_Misc_Bandana_03",
    "Founder of the Defias Brotherhood, driven by a grudge against Stormwind.", true)
card(1, "deadmines", 598, "Defias Miner", "normal", "INV_Pick_01",
    "Digs for the Brotherhood's coffers.")
card(1, "deadmines", 657, "Defias Pirate", "elite", "INV_Weapon_ShortBlade_15",
    "A sea-hardened cutthroat of the Defias ship.")
card(1, "deadmines", 636, "Defias Blackguard", "elite", "Ability_Stealth",
    "A trained killer who strikes from the shadows.")
card(1, "deadmines", 642, "Sneed's Shredder", "elite", "INV_Misc_Gear_01",
    "A clanking timber machine turned war engine.")

card(2, "westfall", 589, "Defias Pillager", "normal", "Spell_Fire_FlameBolt",
    "Raids Westfall's farms for the Brotherhood.")
card(2, "westfall", 590, "Defias Looter", "normal", "INV_Misc_Bandana_01",
    "Takes what the farmers leave unguarded.")
card(2, "westfall", 114, "Harvest Watcher", "normal", "Ability_Repair",
    "A golem that patrols the fields it was built to tend.")
card(2, "westfall", 573, "Foe Reaper 4000", "rare", "Ability_Repair",
    "A harvester that learned to reap more than wheat.")

card(3, "elwynn", 1731, "Copper Vein", "gathering", "INV_Ore_Copper_01",
    "Reddish ore that every young miner swings a pick at first.", false, "mining", 219514) -- copper_miningnode_01.m2
card(3, "elwynn", 1618, "Peacebloom", "gathering", "INV_Misc_Flower_02",
    "A gentle bloom that grows wild across the green fields.", false, "herbalism", 219481) -- bush_peacebloom01.m2

-- ---- Places generated from data (CatalogForever.lua) ----
-- Every Forever creature the site knows is filed under the dungeon, raid or zone it lives in. The hand-made
-- Deadmines and Westfall pages keep their cards and lore and simply gain the rest.
local rankNames = { n = "normal", e = "elite", r = "rare", R = "rareelite", b = "elite" }
local pageForPlace = { deadmines = 1, westfall = 2 }
local usedCodes = { DM = true, WF = true, GA = true }
local backdrops = { ["elwynn-forest"] = "Elwynn.tga" }
ACB.pageForPlace = pageForPlace

local function hash(text)
    local value = 5381
    for index = 1, #text do value = (value * 33 + text:byte(index)) % 4294967296 end
    return value
end

local function hsl(hue, saturation, lightness)
    local function channel(n)
        local k = (n + hue * 12) % 12
        local a = saturation * math.min(lightness, 1 - lightness)
        return lightness - a * math.max(-1, math.min(k - 3, 9 - k, 1))
    end
    return { channel(0), channel(8), channel(4) }
end

-- A fallback colour pair for a place, steadier and darker for instances.
local function placeColors(slug, kind)
    local hue = (hash(slug) % 360) / 360
    local dark = kind == "Dungeon" or kind == "Raid"
    return hsl(hue, dark and 0.35 or 0.40, dark and 0.30 or 0.50), hsl(hue, 0.35, dark and 0.06 or 0.13)
end

local function uniqueCode(name)
    local initials = ""
    for word in name:gmatch("%a+") do
        if word:lower() ~= "the" and word:lower() ~= "of" then initials = initials .. word:sub(1, 1):upper() end
    end
    initials = (initials .. "XX"):sub(1, 3)
    local code, number = initials, 1
    while usedCodes[code] do
        number = number + 1
        code = initials .. number
    end
    usedCodes[code] = true
    return code
end

-- A short, plain description for creatures that have no hand-written lore.
function ACB.autoLore(rank, level, place)
    local at = level and level > 0 and (" at level " .. level) or ""
    if rank == "b" then return ("A boss of %s%s."):format(place, at) end
    if rank == "R" then return ("A rare elite prowling %s%s."):format(place, at) end
    if rank == "r" then return ("A rare find in %s%s."):format(place, at) end
    if rank == "e" then return ("An elite foe of %s%s."):format(place, at) end
    return ("Roams %s%s."):format(place, at)
end

-- Add one place (a zone, dungeon or raid) and its creatures. Each row is { npc id, name, rank, level }.
function ACB.addPlace(slug, name, kind, levels, rows)
    local index = pageForPlace[slug]
    if not index then
        ACB.pages[#ACB.pages + 1] = {
            title = name, zone = slug, group = kind, code = uniqueCode(name), reward = name .. " Collector",
            subtitle = levels ~= "" and ("Levels " .. levels) or kind, cards = {},
        }
        index = #ACB.pages
        pageForPlace[slug] = index
    end
    -- The levels a set is played at: the middle 80% of its ordinary creatures (or all of them when there are few).
    local page = ACB.pages[index]
    local normal, every = {}, {}
    local floor = (kind == "Dungeon" or kind == "Raid" or kind == "Battleground") and 8 or 1 -- no level 1 helpers in instances
    for _, row in ipairs(rows) do
        if row[4] and row[4] >= floor then
            every[#every + 1] = row[4]
            if row[3] == "n" then normal[#normal + 1] = row[4] end
        end
    end
    local pool = #normal >= 5 and normal or every
    table.sort(pool)
    if #pool > 0 and not page.levelMid then
        local low = pool[math.max(1, math.floor(#pool * 0.1) + 1)]
        local high = pool[math.min(#pool, math.ceil(#pool * 0.9))]
        page.levelMin, page.levelMax, page.levelMid = low, high, pool[math.ceil(#pool / 2)]
        page.levels = low == high and tostring(low) or (low .. "–" .. high)
    end
    if not ACB.zones[slug] then
        local top, bottom = placeColors(slug, kind)
        ACB.zones[slug] = { name = name, kind = kind, place = name, backdrop = backdrops[slug], top = top, bottom = bottom }
    end
    for _, row in ipairs(rows) do
        local id, creature, rank, level = row[1], row[2], row[3], row[4]
        if not ACB.cards["npc:" .. id] then
            card(index, slug, id, creature, rankNames[rank] or "normal", "INV_Misc_QuestionMark",
                ACB.autoLore(rank, level, name), rank == "b")
            ACB.cards["npc:" .. id].generated = true -- Lore.lua writes a better line for these
        end
    end
end

-- Add the gathering nodes (CatalogNodes.lua). A node has several object ids in the game, so every id finds the
-- same card. Each row is { profession, skill needed, name, model file id or 0, { object ids } }.
function ACB.addNodes(rows)
    for _, row in ipairs(rows) do
        local profession, skill, name, model, ids = row[1], row[2], row[3], row[4], row[5]
        local primary = ACB.cards["node:" .. ids[1]]
        if not primary then
            local text = profession == "mining" and ("An ore deposit that needs Mining skill %d."):format(skill)
                or ("A herb that needs Herbalism skill %d."):format(skill)
            card(3, skill <= 50 and "elwynn" or "gathering", ids[1], name, "gathering",
                profession == "mining" and "INV_Ore_Copper_01" or "INV_Misc_Flower_02", text, false, profession,
                model ~= 0 and model or nil)
            primary = ACB.cards["node:" .. ids[1]]
            primary.generated = true
        end
        primary.skill, primary.ids = skill, ids
        for index = 2, #ids do
            ACB.sources.GameObject[ids[index]] = ACB.sources.GameObject[ids[index]] or primary
        end
    end
end

-- The sets in the order they are listed: by the typical level of their creatures, then by where they start
-- and end, then by name.
-- Sets with no level information go last. Set numbers themselves never change.
function ACB.setOrder()
    local order = {}
    for index in ipairs(ACB.pages) do order[#order + 1] = index end
    table.sort(order, function(a, b)
        local first, second = ACB.pages[a], ACB.pages[b]
        local midA, midB = first.levelMid or 1000, second.levelMid or 1000
        if midA ~= midB then return midA < midB end
        local lowA, lowB = first.levelMin or 1000, second.levelMin or 1000
        if lowA ~= lowB then return lowA < lowB end
        local highA, highB = first.levelMax or 1000, second.levelMax or 1000
        if highA ~= highB then return highA < highB end
        local nameA, nameB = first.title:lower(), second.title:lower()
        if nameA ~= nameB then return nameA < nameB end
        return a < b
    end)
    return order
end

ACB.achievements = {
    { key = "crew", name = "The Defias Crew", bossesOnly = true },
    { key = "deadmines", name = "Down in the Deadmines" },
}
