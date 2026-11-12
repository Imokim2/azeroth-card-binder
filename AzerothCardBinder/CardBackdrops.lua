local _, ACB = ...

-- Shared environment paintings give every category a reliable scenic backdrop.
-- Hand-authored zone plates still take priority over these biome selections.
local scenes = {}
local groups = {
    Snow = { "dun-morogh", "alterac-valley", "alterac-mountains", "winterspring" },
    Desert = { "badlands", "durotar", "the-barrens", "thousand-needles", "desolace", "tanaris", "silithus",
        "ahnqiraj-temple", "ruins-of-ahnqiraj", "zulfarrak", "uldaman" },
    Swamp = { "wetlands", "swamp-of-sorrows", "dustwallow-marsh", "felwood", "tirisfal-glades", "silverpine-forest",
        "duskwood", "western-plaguelands", "eastern-plaguelands", "sunken-temple", "wailing-caverns",
        "razorfen-downs", "razorfen-kraul", "maraudon", "ungoro-crater" },
    Ruins = { "scarlet-monastery", "shadowfang-keep", "naxxramas", "stratholme", "scholomance", "stormwind-stockade", "deadwind-pass" },
    Volcano = { "blackwing-lair", "molten-core", "onyxias-lair", "blackrock-depths", "blackrock-spire", "ragefire-chasm",
        "searing-gorge", "burning-steppes", "blasted-lands" },
    Coast = { "blackfathom-deeps", "darkshore", "azshara", "zephras-isle" },
}
for scene, zones in pairs(groups) do for _, zone in ipairs(zones) do scenes[zone] = "Scenery\\" .. scene .. ".tga" end end
for _, zone in ipairs({ "arathi-highlands", "arathi-basin", "mulgore", "hillsbrad-foothills", "loch-modan", "redridge-mountains" }) do
    scenes[zone] = "Westfall.tga"
end
scenes.gnomeregan = "Deadmines.tga"

function ACB.cardBackdrop(zoneKey)
    local zone = ACB.zones[zoneKey]
    if not zone then return end
    return zone.backdrop or scenes[zoneKey] or "Elwynn.tga"
end
