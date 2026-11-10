-- Runs the app's Data/Sync.lua the way the game does and prints what the standings hold, with every text as hex so
-- the test can compare exact bytes. Run from the repository root: luajit tests/tools/read-sync.lua <Sync.lua>
local ACB = {}
assert(loadfile(arg[1]))("AzerothCardBinder", ACB)
local function hex(text) return (text:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local sync = ACB.sync
local out = {}
for index, row in ipairs(sync.leaderboard or {}) do
    out[#out + 1] = ("row %d %d %s %d %d %d"):format(index, row.rank, hex(row.name), row.score, row.cards, row.sets)
end
if sync.you then out[#out + 1] = ("you %d %d %d %d"):format(sync.you.rank, sync.you.score, sync.you.cards, sync.you.sets) end
local names = {}
for name in pairs(sync.verified or {}) do names[#names + 1] = hex(name) end
table.sort(names)
out[#out + 1] = "verified " .. table.concat(names, ",")
for index, row in ipairs(sync.firsts or {}) do
    out[#out + 1] = ("first %d %s %s %s %d"):format(index, hex(row.set), hex(row.title), hex(row.by), row.at)
end
out[#out + 1] = "globals " .. tostring(rawget(_G, "os") ~= nil and "os-present" or "none")
io.write(table.concat(out, "\n"))
