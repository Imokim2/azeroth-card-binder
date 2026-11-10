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

-- The saved-data version this build writes. Version 1 files (before the ledger) are upgraded in place:
-- nothing in them is removed, and the ledger and the new counters start empty.
ACB.schema = 2

local function isHash(value)
    return type(value) == "string" and #value == 32 and not value:find("[^0-9a-f]")
end

-- The ledger fields (schema 2). Events are left alone: any damage shows up when the chain is checked.
local function cleanLedgerFields(saved)
    saved.attempts = tableOrEmpty(saved.attempts)
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
