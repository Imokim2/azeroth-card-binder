-- Plays a short binder history through the real add-on code (no game) and prints the resulting ledger and the
-- saved counts as JSON. tests/addon-ledger.test.js feeds that to the reference ledger and rules implementations,
-- which proves the events the add-on writes are the events the server accepts.
-- Run from the repository root: luajit tests/tools/play-ledger.lua
local addon = "AzerothCardBinder"
local ACB = {}
for _, file in ipairs({ "Catalog.lua", "CatalogForever.lua", "CatalogExtra.lua", "CatalogNodes.lua", "Lore.lua", "DropRates.lua", "Editions.lua", "Achievements.lua",
    "Hash.lua", "Ledger.lua", "Data/Sync.lua", "Tape.lua", "Collection.lua", "SavedData.lua" }) do
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end
local clock = 1700000000
time = function() clock = clock + 5 return clock end

local saved = {}
local _, upgraded = ACB.cleanSavedData(saved)
saved.balancedDrops = false -- preserve the pre-chase event fixture
local ledger = ACB.newLedger(saved, time, function() return "Alice-RealmName" end)
ledger:begin(upgraded)
-- Every roll is a drop, and every first copy is shiny, so each kind of event is easy to produce.
local collection = ACB.newCollection(saved, function(low, high) return high == ACB.editionDenominator and 500 or low end, function() end, function() end, nil, nil, ledger)
local function guid(id, token) return ("Creature-0-session-36-4-%d-%s"):format(id, token) end
local function find(id, token) assert(collection:roll(guid(id, token), "loot")) end

find(639, "a"); find(639, "b")
assert(collection:recycle("npc:639"))
local _, cost = ACB.dustFor(ACB.cards["npc:590"])
assert(saved.dust >= cost, "the sample needs a legendary recycle to pay for a common craft")
assert(collection:craft("npc:590"))
for number = 1, 3 do find(589, "c" .. number) end
assert(collection:swap("npc:589", "npc:573", "bob-realmname", "111-482910-1"))
local smallest
for _, page in ipairs(ACB.pages) do
    local plain = page.code ~= nil
    for _, card in ipairs(page.cards) do plain = plain and card.key:match("^npc:") ~= nil end
    if plain and (not smallest or #page.cards < #smallest.cards) then smallest = page end
end
for _, card in ipairs(smallest.cards) do
    if (saved.counts[card.key] or 0) == 0 then find(tonumber(card.key:match("%d+")), "set") end
end
assert(ledger:verify())

local function quote(text)
    return '"' .. tostring(text):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end
local function encode(value)
    if type(value) == "string" then return quote(value) end
    if type(value) == "number" then return string.format("%.0f", value) end
    if type(value) == "boolean" then return tostring(value) end
    local keys, parts = {}, {}
    local isList = #value > 0
    if isList then
        for _, inner in ipairs(value) do parts[#parts + 1] = encode(inner) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = quote(key) .. ":" .. encode(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
io.write(encode({ events = saved.ledger, head = saved.head, snapshot = { counts = saved.counts, dust = saved.dust, sets = saved.sets }, set = smallest.code }))
