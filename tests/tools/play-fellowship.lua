-- Plays a Ranked binder through the real add-on code (no game): gifts received and given, a trade, and creature rolls at a camp with the campfire buff, each
-- earning a roll for a Fellowship card. The roll tape comes from the file named on the command line (one 16-hex entry a line), so a test can give it the
-- server's own entries. Prints the ledger, what the binder holds and the tape position it will use next, as JSON.
-- Run from the repository root: luajit tests/tools/play-fellowship.lua <tape file>
local addon = "AzerothCardBinder"
local ACB = {}
-- Campfire.lua makes a frame to watch for aura changes; there is no game here, so any frame is a blank one that accepts every call.
CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
for _, file in ipairs({ "Catalog.lua", "CatalogForever.lua", "CatalogExtra.lua", "CatalogNodes.lua", "CatalogFellowship.lua", "Lore.lua", "DropRates.lua", "Editions.lua",
    "Availability.lua", "Achievements.lua", "Hash.lua", "Ledger.lua", "Data/Sync.lua", "Updates.lua", "RankedAccess.lua", "Tape.lua", "Collection.lua", "Auras.lua",
    "Campfire.lua", "Fellowship.lua", "Trade.lua", "TradeSession.lua", "Seasons.lua", "SavedData.lua" }) do
    local chunk = assert(loadfile(addon .. "/" .. file))
    chunk(addon, ACB)
end
local entries = {}
for line in io.lines(arg[1]) do if #line == 16 then entries[#entries + 1] = line end end

local clock = 1700000000
time = function() clock = clock + 5 return clock end
GetTime = function() return 5000 + (clock - 1700000000) end -- the game's clock moves with the other one
UnitFactionGroup = function() return "Alliance", "Alliance" end
-- The campfire buff (the violet one, an hour and a half left), switched on for the last rolls.
local expires
UnitAura = function(unit, index, filter)
    if expires and filter == "HELPFUL" and index == 1 and expires > GetTime() then return "Campfire", 135805, 1, nil, 7200, expires, "player", false, false, 1289723 end
end
ACB.characterName = function() return "Alice-RealmName" end

local saved = {}
local _, upgraded = ACB.cleanSavedData(saved)
local ledger = ACB.newLedger(saved, time, ACB.characterName)
ledger:begin(upgraded)
local collection = ACB.newCollection(saved, function() error("Ranked mode must not use the computer's random numbers") end, function() end, function() end, nil, nil, ledger)
ACB.sync.tape = { start = 1, entries = entries }
assert(ACB.setMode(saved, ledger, "ranked"))
local function guid(id, token) return ("Creature-0-session-36-4-%d-%s"):format(id, token) end

assert(collection:swap(nil, "npc:589", "bob-realmname", "gift-in-1")) -- a gift received
assert(collection:swap(nil, "npc:590", "bob-realmname", "gift-in-2"))
assert(collection:swap("npc:589", "npc:573", "bob-realmname", "trade-1")) -- a trade
assert(collection:swap("npc:590", nil, "bob-realmname", "gift-out-1")) -- a gift given
expires = GetTime() + 5400 -- sit down at a camp: the buff has an hour and a half left
for number = 1, 4 do collection:roll(guid(589, "camp" .. number), "loot") end -- at a camp: the claim, and the roll it earns before the next attempt
ACB.settleFellowship(collection)
assert(ledger:verify())

local function quote(text)
    return '"' .. tostring(text):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end
local function encode(value)
    if type(value) == "string" then return quote(value) end
    if type(value) == "number" then return string.format("%.0f", value) end
    if type(value) == "boolean" then return tostring(value) end
    local keys, parts = {}, {}
    if #value > 0 then
        for _, inner in ipairs(value) do parts[#parts + 1] = encode(inner) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = quote(key) .. ":" .. encode(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
io.write(encode({ events = saved.ledger, head = saved.head, owed = saved.fellowOwed, tapeNext = saved.tape.next,
    snapshot = { counts = saved.counts, dust = saved.dust, sets = saved.sets } }))
