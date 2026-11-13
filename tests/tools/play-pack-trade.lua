-- An actual two-accept Lua pack gift, then a Ranked pack reveal using the recipient's issued tape.
local addon, ACB = "AzerothCardBinder", {}
for _, file in ipairs({ "Catalog.lua", "CatalogForever.lua", "CatalogExtra.lua", "CatalogNodes.lua", "Lore.lua", "DropRates.lua", "Editions.lua", "Availability.lua",
    "Achievements.lua", "Hash.lua", "Ledger.lua", "Data/Sync.lua", "Updates.lua", "Tape.lua", "Collection.lua", "Packs.lua", "Trade.lua", "TradeSession.lua", "Seasons.lua", "SavedData.lua" }) do
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end
local function binder(name)
    local saved = ACB.cleanSavedData({})
    local ledger = ACB.newLedger(saved, function() return 1700000000 end, function() return name .. "-RealmName" end)
    ledger:begin(true)
    local collection = ACB.newCollection(saved, function(_, high)
        if high == 10000 then return 10000 end
        if high == 100 then return tonumber(arg[2]) or 1 end
        return 1
    end, function() end, function() end, nil, nil, ledger)
    return saved, ledger, collection
end
local aSaved, aLedger, aCollection = binder("Alice")
local bSaved, bLedger, bCollection = binder("Bob")
aCollection.packsEnabled = true
assert(aCollection:roll("Creature-0-session-36-4-589-one", "loot") == false)
local zone = ACB.packList(aSaved)[1].zone
assert(aSaved.packs[zone] == 1)
ACB.sync.tape = { start = 1, entries = assert(loadfile(arg[1]))() }
assert(ACB.setMode(bSaved, bLedger, "ranked"))
local a, b
a = ACB.newTrade(aSaved.counts, function() return 1 end, function() return "pack-gift-real" end,
    function(_, message) b:receive("alice-realmname", message) return true end,
    function(give, take, peer, id) return aCollection:swap(give, take, peer, id) end, nil, nil, aSaved)
b = ACB.newTrade(bSaved.counts, function() return 1 end, function() return "pack-gift-real" end,
    function(_, message) a:receive("bob-realmname", message) return true end,
    function(give, take, peer, id) return bCollection:swap(give, take, peer, id) end, nil, nil, bSaved)
a:start("bob-realmname", "pack:" .. zone, true)
assert(b:join())
a:confirm(); b:confirm()
assert(aSaved.packs[zone] == nil and bSaved.packs[zone] == 1)
assert(#bCollection:openPack(zone) == ACB.packInfo(zone).size)
assert(aLedger:verify()); assert(bLedger:verify())
local function json(value)
    if type(value) == "string" then return '"' .. value:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    local parts = {}
    if #value > 0 then for _, item in ipairs(value) do parts[#parts + 1] = json(item) end; return "[" .. table.concat(parts, ",") .. "]" end
    for key, item in pairs(value) do parts[#parts + 1] = json(key) .. ":" .. json(item) end
    table.sort(parts); return "{" .. table.concat(parts, ",") .. "}"
end
local function result(saved) return { events = saved.ledger, counts = saved.counts, packs = saved.packs, attempts = saved.attempts,
    dust = saved.dust, sets = saved.sets, tapeIndex = saved.tape and saved.tape.next or 0 } end
print(json({ giver = result(aSaved), recipient = result(bSaved), zone = zone }))
