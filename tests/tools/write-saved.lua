-- Plays a binder history through the real add-on code and writes it as the game would: a SavedVariables file
-- (AzerothCardBinderDB = { ... } in the game's layout: tabs, quoted keys, "-- [n]" list comments, decimal escapes).
-- Prints the same table as JSON so a test can compare what a JavaScript reader makes of the file.
--   luajit tests/tools/write-saved.lua <output file> [extra drops]
-- Run from the repository root.
local addon = "AzerothCardBinder"
local ACB = {}
for _, file in ipairs({ "Catalog.lua", "CatalogForever.lua", "CatalogExtra.lua", "CatalogNodes.lua", "Lore.lua", "DropRates.lua", "Editions.lua", "Achievements.lua",
    "Hash.lua", "Ledger.lua", "Data/Sync.lua", "Updates.lua", "Tape.lua", "Collection.lua", "Packs.lua", "SavedData.lua", "Reports.lua" }) do
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end
local clock = 1700000000
time = function() clock = clock + 5 return clock end

local saved = {}
-- Continue an existing fixture instead of inventing a second history against a later Sync.lua range.
if arg[4] == "resume" then
    assert(loadfile(arg[1]))()
    saved = assert(AzerothCardBinderDB)
    local last = saved.ledger and saved.ledger[#saved.ledger]
    clock = math.max(clock, last and last.t or 0)
end
local _, upgraded = ACB.cleanSavedData(saved)
local ledger = ACB.newLedger(saved, time, function() return "Alice-RealmName" end)
ledger:begin(upgraded)
local collection = ACB.newCollection(saved, function(low, high) return high == ACB.editionDenominator and 500 or low end, function() end, function() end, nil, nil, ledger)
local function guid(id, token) return ("Creature-0-session-36-4-%d-%s"):format(id, token) end
local function find(id, token) assert(collection:roll(guid(id, token), "loot")) end

if arg[3] then
    -- Ranked: Sync.lua (written by the app, with the tape) is loaded as the game would, and every kill rolls the tape.
    assert(loadfile(arg[3]))(addon, ACB)
    assert(ACB.setMode(saved, ledger, "ranked"))
    -- A 10% card, so a few drops come quickly; misses use tape entries too.
    -- WARCARDS_PACKS=1: packs are on, the kills stop at the first pack found, and that pack is opened.
    local packs = os.getenv("WARCARDS_PACKS") ~= nil
    collection.packsEnabled = packs
    for number = 1, tonumber(arg[2] or 60) do
        collection:roll(guid(573, (arg[4] == "resume" and "continued" or "ranked") .. number), "loot")
        if packs and next(saved.packs or {}) then break end
    end
    if packs then
        for zone in pairs(saved.packs or {}) do assert(collection:openPack(zone)) end
    end
else
    -- A different binder (a different first event, so a different chain from the very start): WARCARDS_VARIANT=other
    if os.getenv("WARCARDS_VARIANT") == "other" then find(589, "otherfirst") end
    find(639, "a"); find(639, "b")
    assert(collection:recycle("npc:639"))
    assert(collection:craft("npc:590"))
    for number = 1, 3 do find(589, "c" .. number) end
    assert(collection:swap("npc:589", "npc:573", "bob-realmname", "111-482910-1"))
    for number = 1, tonumber(arg[2] or 0) do find(589, "extra" .. number) end
end
-- Cards on the wanted list, for tests: WARCARDS_WANTED=npc:589,npc:639
for key in (os.getenv("WARCARDS_WANTED") or ""):gmatch("[^,]+") do saved.wanted = saved.wanted or {}; saved.wanted[key] = true end
-- Reports waiting to be sent, for tests: WARCARDS_REPORTS=bob-realmname:trading:a note,carl-realmname:cheating:
for entry in (os.getenv("WARCARDS_REPORTS") or ""):gmatch("[^,]+") do
    local peer, reason, note = entry:match("^([^:]+):([^:]+):(.*)$")
    assert(ACB.addReport(saved, peer, reason, note, time()))
end
saved.title = "Zul'Gurub \226\128\147 Ünïcöde" -- raw and escaped non-ASCII text, as a player's title could be

-- The game's serializer layout.
local function key(value)
    if type(value) == "number" then return "[" .. string.format("%.14g", value) .. "]" end
    return '["' .. tostring(value):gsub('[%c"\\]', function(c) return string.format("\\%d", c:byte()) end) .. '"]'
end
local function scalar(value)
    if type(value) == "string" then
        return '"' .. value:gsub('[%c"\\\128-\255]', function(c)
            if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
            return string.format("\\%d", c:byte())
        end) .. '"'
    end
    if type(value) == "number" then return string.format("%.14g", value) end
    return tostring(value)
end
local function write(value, depth, out)
    local pad = string.rep("\t", depth)
    out[#out + 1] = "{\n"
    local count = #value
    for index, inner in ipairs(value) do
        out[#out + 1] = pad .. "\t"
        if type(inner) == "table" then write(inner, depth + 1, out) else out[#out + 1] = scalar(inner) end
        out[#out + 1] = ", -- [" .. index .. "]\n"
    end
    local keys = {}
    for name in pairs(value) do
        if not (type(name) == "number" and name >= 1 and name <= count and name == math.floor(name)) then keys[#keys + 1] = name end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, name in ipairs(keys) do
        local inner = value[name]
        out[#out + 1] = pad .. "\t" .. key(name) .. " = "
        if type(inner) == "table" then write(inner, depth + 1, out) else out[#out + 1] = scalar(inner) end
        out[#out + 1] = ",\n"
    end
    out[#out + 1] = pad .. "}"
end
local out = { "\nAzerothCardBinderDB = " }
write(saved, 0, out)
out[#out + 1] = "\n"
local file = assert(io.open(arg[1], "wb"))
file:write(table.concat(out))
file:close()

-- The same table as JSON (ledger, head, counts, attempts, dust, sets, titles, mode, schema, title).
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
    for name in pairs(value) do keys[#keys + 1] = name end
    table.sort(keys)
    for _, name in ipairs(keys) do parts[#parts + 1] = quote(name) .. ":" .. encode(value[name]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
io.write(encode({
    ledger = saved.ledger, head = saved.head, counts = saved.counts, attempts = saved.attempts, dust = saved.dust,
    sets = saved.sets, titles = saved.titles, mode = saved.mode, schema = saved.schema, title = saved.title,
    tape = saved.tape,
}))
