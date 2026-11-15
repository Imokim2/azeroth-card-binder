local _, ACB = ...

-- Cards whose creature cannot be killed, so the card can never be won by playing: companion pets are not attackable, and a few event
-- creatures (a portal, a totem, spirits) are placeholders. They are never released: they are held back for good, never part of finishing a
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
}

for key in pairs(ACB.unobtainableCards) do
    if ACB.cards[key] then ACB.cards[key].unobtainable = true end
end
