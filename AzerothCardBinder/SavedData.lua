local _, ACB = ...

-- Loading the saved variables safely. Anything in the file that is not the kind of value the add-on expects
-- is dropped, so a damaged or hand-edited file can never break the add-on or crash at login.

function ACB.tableOrEmpty(value)
    return type(value) == "table" and value or {}
end

local tableOrEmpty = ACB.tableOrEmpty

-- How many entries a table holds, and the sum of its numbers.
function ACB.countKeys(values)
    local total = 0
    for _ in pairs(values) do total = total + 1 end
    return total
end

function ACB.sumValues(values)
    local total = 0
    for _, value in pairs(values) do total = total + value end
    return total
end

-- Start a new binder (for the Ranked ladder, which only counts a binder that was Ranked from its first drop). Everything
-- in the saved data is erased except a copy of the old collection, kept as `lastBinder` in case it is wanted again, and
-- an empty binder with a new ledger takes its place; the add-on then reloads. Returns the copy.
function ACB.startNewBinder(saved)
    local backup = {
        at = time and time() or 0, counts = saved.counts, shiny = saved.shiny, dust = saved.dust, sets = saved.sets,
        titles = saved.titles, achievements = saved.achievements,
    }
    for key in pairs(saved) do saved[key] = nil end
    saved.lastBinder = backup
    -- An empty, valid binder straight away, so the open window never meets missing data before the reload.
    ACB.cleanSavedData(saved)
    -- A roll tape held in memory belonged to the old binder.
    if ACB.sync then ACB.sync.tape = nil end
    return backup
end

-- The saved-data version this build writes. Version 1 files (before the ledger) are upgraded in place:
-- nothing in them is removed, and the ledger and the new counters start empty.
ACB.schema = 2

local function isHash(value)
    return type(value) == "string" and #value == 32 and not value:find("[^0-9a-f]")
end

-- The ledger fields (schema 2). Events are left alone: any damage shows up when the chain is checked.
local function cleanLedgerFields(saved)
    saved.attempts = tableOrEmpty(saved.attempts)
    -- Drops rolled in Casual mode, which the server cannot recheck: any keeps this binder off the Ranked ladder.
    local casual = saved.casualDrops
    if type(casual) ~= "number" or casual < 0 or casual ~= math.floor(casual) then saved.casualDrops = 0 end
    for key, value in pairs(saved.attempts) do
        if type(value) ~= "number" or value < 1 or value ~= math.floor(value) or not ACB.cards[key] then
            saved.attempts[key] = nil
        end
    end
    saved.rolledGuids = tableOrEmpty(saved.rolledGuids)
    local ring = saved.rolledGuids
    for index = #ring, 1, -1 do
        if type(ring[index]) ~= "string" or #ring[index] > 200 or index > ACB.rolledMemory then table.remove(ring, index) end
    end
    -- While the ring is filling, the next slot is the one after the last; once full it can be any slot.
    local slot = saved.rolledNext
    if #ring < ACB.rolledMemory or type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1
        or slot > ACB.rolledMemory then
        saved.rolledNext = #ring % ACB.rolledMemory + 1
    end
    saved.mode = saved.mode == "ranked" and "ranked" or "casual"
    if saved.legacy ~= true then saved.legacy = nil end
    local tape = ACB.tableOrEmpty(saved.tape)
    local nextEntry = tape.next
    saved.tape = { next = (type(nextEntry) == "number" and nextEntry >= 1 and nextEntry == math.floor(nextEntry)) and nextEntry or 1 }
    -- The open run of misses that is not in the ledger yet (see ledger:flushRun), and whether Ranked is the kind that writes
    -- every attempt down.
    local run = saved.run
    local function count(value) return type(value) == "number" and value >= 1 and value == math.floor(value) end
    if type(run) == "table" and type(run.key) == "string" and ACB.cards[run.key] and count(run.n) and count(run.last) and run.last >= run.n then
        saved.run = { key = run.key, n = run.n, last = run.last }
    else
        saved.run = nil
    end
    saved.exactMode = saved.exactMode == true or nil
    saved.ledger = tableOrEmpty(saved.ledger)
    local head = saved.head
    if type(head) ~= "table" or type(head.seq) ~= "number" or head.seq < 0 or head.seq ~= math.floor(head.seq)
        or not isHash(head.hash) then
        saved.head = { seq = 0, hash = ACB.GENESIS }
    end
    local sum = saved.stateSum
    if type(sum) ~= "string" or #sum ~= 12 or sum:find("[^0-9a-f]") then saved.stateSum = nil end
end

-- Clean the saved variables in place and return them. Safe to run on every load. The second result is true
-- when the file came from an older version and was upgraded.
function ACB.cleanSavedData(saved)
    local upgraded = saved.schema ~= ACB.schema
    saved.schema = ACB.schema
    saved.counts, saved.achievements = tableOrEmpty(saved.counts), tableOrEmpty(saved.achievements)
    saved.levels = nil -- levels were shown on cards in an earlier build and are no longer kept
    for key, count in pairs(saved.counts) do
        if type(count) ~= "number" or count < 1 or count > 1000000000 or count ~= math.floor(count) then
            saved.counts[key] = nil
        end
    end
    saved.misses = tableOrEmpty(saved.misses)
    for key, value in pairs(saved.misses) do
        if type(value) ~= "number" or value < 1 or value ~= math.floor(value) or not ACB.cards[key] then
            saved.misses[key] = nil
        end
    end
    saved.shiny = tableOrEmpty(saved.shiny)
    for key, value in pairs(saved.shiny) do
        if value ~= true or not ACB.cards[key] then saved.shiny[key] = nil end
    end
    saved.wanted, saved.history = tableOrEmpty(saved.wanted), tableOrEmpty(saved.history)
    for key, value in pairs(saved.wanted) do
        if value ~= true or not ACB.cards[key] then saved.wanted[key] = nil end
    end
    for index = #saved.history, 1, -1 do
        local entry = saved.history[index]
        if type(entry) ~= "table" or not ACB.cards[entry.give] or not ACB.cards[entry.take] then
            table.remove(saved.history, index)
        end
    end
    if type(saved.dust) ~= "number" or saved.dust < 0 or saved.dust ~= math.floor(saved.dust) then saved.dust = 0 end
    local tradeCount = saved.tradeCount
    if type(tradeCount) ~= "number" or tradeCount < #saved.history or tradeCount > 1000000000
        or tradeCount ~= math.floor(tradeCount) then
        saved.tradeCount = #saved.history
    end
    saved.sets, saved.titles = tableOrEmpty(saved.sets), tableOrEmpty(saved.titles)
    for key, value in pairs(saved.sets) do
        if value ~= true then saved.sets[key] = nil end
    end
    for key, value in pairs(saved.titles) do
        if value ~= true or type(key) ~= "string" then saved.titles[key] = nil end
    end
    cleanLedgerFields(saved)
    return saved, upgraded
end
