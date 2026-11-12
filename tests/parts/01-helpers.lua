local addon = "AzerothCardBinder"
local ACB = {}
local function loadAddon(file)
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end

local passed = 0
local function test(name, run)
    local ok, err = xpcall(run, debug.traceback)
    assert(ok, name .. ": " .. __where(tostring(err)))
    passed = passed + 1
    print("PASS " .. name)
end

local function equal(actual, expected)
    assert(actual == expected, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function guid(id, token, kind)
    return ("%s-0-session-36-4-%d-%s"):format(kind or "Creature", id, (token:gsub("-", "_")))
end

local function ignore() end
loadAddon("Catalog.lua")
loadAddon("CatalogForever.lua")
loadAddon("CatalogExtra.lua")
loadAddon("CatalogNodes.lua")
loadAddon("Lore.lua")
loadAddon("DropRates.lua")
loadAddon("Editions.lua")
loadAddon("Achievements.lua")
loadAddon("Hash.lua")
loadAddon("Ledger.lua")
loadAddon("Data/Sync.lua")
loadAddon("Tape.lua")
loadAddon("Collection.lua")
loadAddon("Trade.lua")
loadAddon("TradeSession.lua")
loadAddon("Range.lua")
