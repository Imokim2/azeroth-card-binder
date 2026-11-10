local _, ACB = ...

-- Loading the saved variables safely. Anything in the file that is not the kind of value the add-on expects
-- is dropped, so a damaged or hand-edited file can never break the add-on or crash at login.

function ACB.tableOrEmpty(value)
    return type(value) == "table" and value or {}
end

local tableOrEmpty = ACB.tableOrEmpty

-- Clean the saved variables in place and return them. Safe to run on every load.
function ACB.cleanSavedData(saved)
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
    return saved
end
