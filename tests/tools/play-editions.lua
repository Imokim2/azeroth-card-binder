-- Actual addon inventory/ledger scenario used by server edition integration tests.
local addon, ACB = "AzerothCardBinder", {}
for _, file in ipairs({ "Catalog.lua", "CatalogForever.lua", "CatalogExtra.lua", "CatalogNodes.lua", "Lore.lua", "DropRates.lua", "Editions.lua",
    "Achievements.lua", "Hash.lua", "Ledger.lua", "Data/Sync.lua", "Updates.lua", "Tape.lua", "Collection.lua", "Packs.lua", "Seasons.lua", "SavedData.lua" }) do
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end
local clock = 1700000000
local saved = ACB.cleanSavedData({})
saved.balancedDrops = false -- spec-4 legacy fixture; spec-5 has a separate real-addon scenario
local ledger = ACB.newLedger(saved, function() clock = clock + 1; return clock end, function() return "Alice-RealmName" end)
ledger:begin(true)
local collection = ACB.newCollection(saved, function(_, high)
    if high == ACB.editionDenominator then return 100 end
    return high == ACB.shinyOdds and 2 or 1
end, function() end, function() end, nil, nil, ledger)
local function find(id, token) return collection:roll(("Creature-0-session-36-4-%d-%s"):format(id, token), "loot") end
if arg[1] then
    ACB.sync.tape = { start = 1, entries = assert(loadfile(arg[1]))() }
    assert(ACB.setMode(saved, ledger, "ranked"))
    for attempt = 1, 160 do find(4832, "ranked" .. attempt) end
    ledger:flushRun()
else
    for _, id in ipairs({ 639, 646, 4275, 3887, 3976, 3977, 4832, 4829 }) do assert(find(id, "first")) end
    assert(find(4832, "spare"))
    assert(collection:recycle("edition:48321"))
    local page = ACB.pages[ACB.cards["npc:4832"].page]
    for _, card in ipairs(page.cards) do if ACB.familyCount(saved.counts, card) == 0 then assert(find(card.id, "set")) end end
end
assert(ledger:verify())
local function quote(text)
    return '"' .. tostring(text):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end
local function json(value)
    if type(value) == "string" then return quote(value) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    local parts = {}
    if #value > 0 then for _, item in ipairs(value) do parts[#parts + 1] = json(item) end; return "[" .. table.concat(parts, ",") .. "]" end
    for key, item in pairs(value) do parts[#parts + 1] = quote(key) .. ":" .. json(item) end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end
print(json({ events = saved.ledger, counts = saved.counts, attempts = saved.attempts, dust = saved.dust, sets = saved.sets,
    tapeIndex = saved.tape and saved.tape.next or 0 }))
