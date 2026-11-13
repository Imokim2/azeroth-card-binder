-- Real addon history crossing the legacy -> chase policy, using an issued server tape.
local addon, ACB = "AzerothCardBinder", {}
for _, file in ipairs({ "Catalog.lua", "CatalogForever.lua", "CatalogExtra.lua", "CatalogNodes.lua", "Lore.lua", "DropRates.lua", "Editions.lua", "Availability.lua",
    "Achievements.lua", "Hash.lua", "Ledger.lua", "Data/Sync.lua", "Updates.lua", "Tape.lua", "Collection.lua", "Packs.lua", "Seasons.lua", "SavedData.lua" }) do
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end
local saved = ACB.cleanSavedData({})
saved.balancedDrops = false
saved.tieredPacks = false -- retain this spec-5 pack fixture
local clock = 1700000000
local ledger = ACB.newLedger(saved, function() clock = clock + 1; return clock end, function() return "Alice-RealmName" end)
ledger:begin(true)
local collection = ACB.newCollection(saved, function() error("No local random in Ranked") end, function() end, function() end, nil, nil, ledger)
collection.packsEnabled = true
ACB.sync.tape = { start = 1, entries = assert(loadfile(arg[1]))() }
assert(ACB.setMode(saved, ledger, "ranked"))
local serial = 0
local function attempts(id, n)
    for _ = 1, n do
        serial = serial + 1
        collection:roll(("Creature-0-session-36-4-%d-%d"):format(id, serial), "loot")
    end
end
attempts(589, 30)
saved.balancedDrops = true
attempts(589, 300)
attempts(721, 150)
local chase
for _, page in ipairs(ACB.pages) do for _, card in ipairs(page.cards) do
    if not chase and card.dropProfile.tier == "chase" and card.dropProfile.style == "chase" then chase = card end
end end
assert(chase)
attempts(chase.id, 150)
attempts(4832, 120)
for _, item in ipairs(ACB.packList(saved)) do for _ = 1, item.count do assert(collection:openPack(item.zone)) end end
ledger:flushRun()
assert(ledger:verify())
local function json(value)
    if type(value) == "string" then return '"' .. value:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    local parts = {}
    if #value > 0 then for _, item in ipairs(value) do parts[#parts + 1] = json(item) end; return "[" .. table.concat(parts, ",") .. "]" end
    for key, item in pairs(value) do parts[#parts + 1] = json(key) .. ":" .. json(item) end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end
print(json({ events = saved.ledger, counts = saved.counts, attempts = saved.attempts, dust = saved.dust, sets = saved.sets,
    tapeIndex = saved.tape.next }))
