local _, ACB = ...

-- A card you find for the first time has a 1 in `shinyOdds` chance to be a shiny copy.
ACB.shinyOdds = 20
ACB.rates = { normal = 50, elite = 100, rare = 500, rareelite = 500, gathering = 50 }
ACB.pages = {
    { title = "Deadmines", group = "Dungeon", code = "DM", subtitle = "The Defias hideout", cards = {} },
    { title = "Westfall", group = "Zone", code = "WF", subtitle = "The fields beyond Sentinel Hill", cards = {} },
    { title = "Gathering", group = "Profession", code = "GA", subtitle = "Finds from the field", cards = {} },
}
ACB.cards, ACB.sources = {}, { Creature = {}, GameObject = {} }

-- Packaged portrait backdrops take priority, followed by client artwork and a fallback gradient.
ACB.zones = {
    deadmines = {
        backdrop = "Deadmines.tga",
        journal = 63, map = 55,
        paths = { "Interface\\Glues\\LoadingScreens\\LoadScreenDeadmines" },
        top = { 0.36, 0.22, 0.11 }, bottom = { 0.07, 0.04, 0.03 },
    },
    westfall = {
        backdrop = "Westfall.tga",
        map = 52,
        paths = { "Interface\\Glues\\LoadingScreens\\LoadScreenWestfall" },
        top = { 0.80, 0.64, 0.30 }, bottom = { 0.22, 0.30, 0.12 },
    },
    elwynn = {
        backdrop = "Elwynn.tga",
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

ACB.achievements = {
    { key = "crew", name = "The Defias Crew", bossesOnly = true },
    { key = "deadmines", name = "Down in the Deadmines" },
}
