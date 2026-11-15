local _, ACB = ...

-- Cards that can never be won by playing: companion pets are not attackable, a few event creatures (a portal, a totem, spirits) and some
-- friendly dungeon characters cannot be killed, and some creatures appear only once, through a quest or an event, so they cannot be
-- farmed. They are never released: they are held back for good, never part of finishing a
-- page, and a season cannot feature them. A card on this list can still be traded if someone owns a copy. Found by the scan in
-- docs/UNOBTAINABLE-CARDS.md (tools/scan-unkillable.js); the reason says how sure that scan is. When one is confirmed killable in the game,
-- delete its line, run `node tools/build-catalog-json.js` and `node tools/launch-collection.js --write`, and build again.
ACB.unobtainableCards = {
    -- The data says so: type "Non-combat Pet".
    ["npc:7381"] = "companion pet (Silver Tabby): cannot be attacked",
    ["npc:7382"] = "companion pet (Orange Tabby): cannot be attacked",
    ["npc:7384"] = "companion pet (Cornish Rex): cannot be attacked",
    ["npc:7385"] = "companion pet (Bombay): cannot be attacked",
    ["npc:7389"] = "companion pet (Senegal): cannot be attacked",
    ["npc:7390"] = "companion pet (Cockatiel): cannot be attacked",
    -- Very likely, from the data and the names; check each in the game.
    ["npc:11446"] = "Gordok Spirit: no health in the data (likely, check in game)",
    ["npc:15896"] = "C'Thun Portal: a portal, not a creature (likely, check in game)",
    ["npc:13916"] = "Dire Maul Crystal Totem: a level 1 totem placeholder (likely, check in game)",
    ["npc:15481"] = "Spirit of Azuregos: an event spirit with Azuregos's health and no loot (likely, check in game)",
    -- Dungeon creatures that cannot be fought. Every dungeon creature has a card, so these have one, but it cannot be won.
    ["npc:3678"] = "Disciple of Naralex: an escort ally in the Wailing Caverns event (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:3679"] = "Naralex: the druid the Wailing Caverns event is about, not a monster (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:7998"] = "Blastmaster Emi Shortfuse: a friendly Gnomeregan quest ally (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:8767"] = "Sah'rhee: a friendly spirit (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:9679"] = "Tobias Seecher: a friendly Blackrock Depths quest giver (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:10116"] = "Slave: a prisoner (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:10117"] = "Tortured Slave: a prisoner (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:10162"] = "Lord Victor Nefarius: the Blackwing Lair story NPC (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:11491"] = "Old Ironbark: a friendly Dire Maul NPC (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:12242"] = "Spirit of Maraudos: a friendly Maraudon spirit (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:12243"] = "Spirit of Veng: a friendly Maraudon spirit (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:14459"] = "Nefarian's Troops: a scripted placeholder, not a creature to fight (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    ["npc:16381"] = "Archmage Tarsis Kir-Moldir: a friendly Naxxramas quest NPC (a dungeon creature the data lists as friendly to both factions; likely, check in game)",
    -- One-off kills: no spawn point in the game database, so they appear only through a quest or an event and cannot be farmed.
    ["npc:1983"] = "Nightlash: summoned, has no spawn point, so it can only be killed once (one-off; cMaNGOS classic-db has no spawn for it)",
    ["npc:3395"] = "Verog the Dervish: summoned by a quest, has no spawn point, so it can only be killed once (one-off; cMaNGOS classic-db has no spawn for it)",
    ["npc:3475"] = "Echeyakee: summoned by a quest, has no spawn point, so it can only be killed once (one-off; cMaNGOS classic-db has no spawn for it)",
    ["npc:4093"] = "Galak Wrangler: appears only in an event, has no spawn point, so it can only be killed once (one-off; cMaNGOS classic-db has no spawn for it)",
    ["npc:4094"] = "Galak Scout: appears only in an event, has no spawn point, so it can only be killed once (one-off; cMaNGOS classic-db has no spawn for it)",
    ["npc:4096"] = "Galak Windchaser: appears only in an event, has no spawn point, so it can only be killed once (one-off; cMaNGOS classic-db has no spawn for it)",
    ["npc:9523"] = "Kolkar Stormseer: appears only in an event, has no spawn point, so it can only be killed once (one-off; cMaNGOS classic-db has no spawn for it)",
    ["npc:9524"] = "Kolkar Invader: appears only in an event, has no spawn point, so it can only be killed once (one-off; cMaNGOS classic-db has no spawn for it)",
}

for key in pairs(ACB.unobtainableCards) do
    if ACB.cards[key] then ACB.cards[key].unobtainable = true end
end
