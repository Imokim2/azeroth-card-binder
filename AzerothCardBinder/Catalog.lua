local _, ACB = ...

ACB.rates = { normal = 50, elite = 100, rare = 500, rareelite = 500, gathering = 50 }
ACB.pages = {
    { title = "Deadmines", subtitle = "The Defias hideout", cards = {} },
    { title = "Westfall", subtitle = "The fields beyond Sentinel Hill", cards = {} },
    { title = "Gathering", subtitle = "Finds from the field", cards = {} },
}
ACB.cards, ACB.sources = {}, { Creature = {}, GameObject = {} }

local function card(page, id, name, rank, icon, boss, profession)
    local kind = profession and "GameObject" or "Creature"
    local key = (profession and "node:" or "npc:") .. id
    local entry = {
        key = key, name = name, rank = rank, icon = "Interface\\Icons\\" .. icon,
        boss = boss, profession = profession, page = page,
    }
    ACB.cards[key] = entry
    ACB.sources[kind][id] = entry
    table.insert(ACB.pages[page].cards, entry)
end

card(1, 644, "Rhahk'Zor", "elite", "INV_Hammer_09", true)
card(1, 643, "Sneed", "elite", "INV_Weapon_ShortBlade_02", true)
card(1, 3586, "Miner Johnson", "rareelite", "INV_Pick_02", true)
card(1, 1763, "Gilnid", "elite", "INV_Hammer_18", true)
card(1, 646, "Mr. Smite", "elite", "INV_Hammer_19", true)
card(1, 647, "Captain Greenskin", "elite", "INV_Sword_24", true)
card(1, 645, "Cookie", "elite", "INV_Misc_Food_10", true)
card(1, 639, "Edwin VanCleef", "elite", "INV_Misc_Bandana_03", true)
card(1, 598, "Defias Miner", "normal", "INV_Pick_01")
card(1, 657, "Defias Pirate", "elite", "INV_Weapon_ShortBlade_15")
card(1, 636, "Defias Blackguard", "elite", "Ability_Stealth")
card(1, 642, "Sneed's Shredder", "elite", "INV_Misc_Gear_01")

card(2, 589, "Defias Pillager", "normal", "Spell_Fire_FlameBolt")
card(2, 590, "Defias Looter", "normal", "INV_Misc_Bandana_01")
card(2, 114, "Harvest Watcher", "normal", "Ability_Repair")
card(2, 573, "Foe Reaper 4000", "rare", "Ability_Repair")

card(3, 1731, "Copper Vein", "gathering", "INV_Ore_Copper_01", false, "mining")
card(3, 1618, "Peacebloom", "gathering", "INV_Misc_Flower_02", false, "herbalism")

ACB.achievements = {
    { key = "crew", name = "The Defias Crew", bossesOnly = true },
    { key = "deadmines", name = "Down in the Deadmines" },
}
