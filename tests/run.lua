-- The add-on's test runner. Run it from the repository root with LuaJIT or Lua 5.1:  luajit tests/run.lua
--
-- The tests live in tests/parts, one file per area, run in this order. They are joined into ONE chunk before
-- running, because the later parts use the fake game set up by the earlier ones (its frames, clock, loot slots
-- and so on) as shared local variables. A failure is reported with the file and line inside tests/parts.
-- Add a new part to this list; a part that is not listed does not run.
local parts = {
    "01-helpers",
    "02-odds-and-catalog",
    "03-collection-and-trade",
    "04-fake-game",
    "05-startup-and-cards",
    "06-hints-social-and-links",
    "07-card-looks-folio-index",
    "08-loot-gathering-boss",
    "09-trade-panel-dust-settings",
    "10-art-saved-data-size",
    "11-ledger-sync-and-saved-data",
    "12-ranked-tape",
    "13-zone-bar",
}

local source, ranges, line = {}, {}, 1
for _, name in ipairs(parts) do
    local file = assert(io.open("tests/parts/" .. name .. ".lua", "rb"), "missing test part " .. name)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    if text:sub(-1) ~= "\n" then text = text .. "\n" end
    ranges[#ranges + 1] = { first = line, name = name }
    source[#source + 1] = text
    for _ in text:gmatch("\n") do line = line + 1 end
end
source[#source + 1] = 'print(("%d checks passed under %s"):format(passed, _VERSION))\n'

-- Turn "TESTS:123:" in an error message into "tests/parts/<file>.lua:<line>:".
function __where(message)
    return (message:gsub("TESTS:(%d+):", function(number)
        number = tonumber(number)
        for index = #ranges, 1, -1 do
            if number >= ranges[index].first then
                return ("tests/parts/%s.lua:%d:"):format(ranges[index].name, number - ranges[index].first + 1)
            end
        end
    end))
end

local chunk = assert(loadstring(table.concat(source), "=TESTS"))
chunk()
