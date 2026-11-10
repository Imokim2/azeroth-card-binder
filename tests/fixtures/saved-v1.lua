-- A saved-data file as the add-on wrote it before the ledger existed (schema 1, build 0.2.x), shaped from
-- what SavedData.lua read at that time. It is a stand-in written by hand, not a copy of a player's file;
-- replace or add a real one whenever a player's file can be shared. Every future schema keeps loading this.
return {
    counts = { ["npc:639"] = 1, ["npc:589"] = 4, ["npc:573"] = 2, ["npc:590"] = 1 },
    misses = { ["npc:1763"] = 12 },
    shiny = { ["npc:639"] = true },
    wanted = { ["npc:1763"] = true },
    history = { { give = "npc:589", take = "npc:573", peer = "bob-realmname", time = 1699000000 } },
    tradeCount = 3,
    dust = 7,
    sets = {},
    titles = { ["Defias Bane"] = true },
    achievements = { trades1 = true },
    title = "Defias Bane",
    popups = false,
    inspectable = true,
}
