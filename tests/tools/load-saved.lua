-- Loads a SavedVariables file the way the game does (by running it) and the add-on's Sync.lua, then does what the
-- add-on does at login: clean the data, start the ledger, check it, drop the events the server has acknowledged.
-- Prints what happened as JSON. Used to prove the app's Sync.lua is understood by the add-on.
--   luajit tests/tools/load-saved.lua <saved file> <Sync.lua file>
-- Run from the repository root.
local addon = "AzerothCardBinder"
local ACB = {}
for _, file in ipairs({ "Catalog.lua", "CatalogForever.lua", "CatalogExtra.lua", "CatalogNodes.lua", "Lore.lua", "DropRates.lua", "Editions.lua", "Achievements.lua",
    "Hash.lua", "Ledger.lua", "Updates.lua", "Tape.lua", "Collection.lua", "SavedData.lua" }) do
    assert(loadfile(addon .. "/" .. file))(addon, ACB)
end
-- The app's file replaces the add-on's stub, exactly as it does in the game folder.
assert(loadfile(arg[2]))(addon, ACB)

local environment = {}
local chunk = assert(loadfile(arg[1]))
setfenv(chunk, environment)
chunk()
local saved = environment.AzerothCardBinderDB
local _, upgraded = ACB.cleanSavedData(saved)
local ledger = ACB.newLedger(saved, function() return 1700001000 end, function() return "Alice-RealmName" end)
ledger:begin(upgraded)
local verified, detail = ledger:check()
local before = #saved.ledger
local removed = verified and ledger:prune(ACB.sync.acks) or 0
local afterCheck = ledger:verify()
io.write(string.format(
    '{"verified":%s,"detail":"%s","eventsBefore":%d,"removed":%d,"eventsAfter":%d,"verifiedAfter":%s,"headSeq":%d,"syncedAt":%d,"mode":"%s"}',
    tostring(verified), tostring(detail), before, removed, #saved.ledger, tostring(afterCheck), saved.head.seq,
    ACB.sync.syncedAt or 0, saved.mode))
