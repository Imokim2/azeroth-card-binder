local _, ACB = ...

-- Finding cards by name, and what a swap with another player could be built from. Used by the binder view of another
-- player, by the ask command and by the trade window.

-- Find any card in the catalog by part of its name, owned or not (an exact name wins).
function ACB.findAnyCard(text)
    text = (text or ""):lower():match("^%s*(.-)%s*$")
    if text == "" then return end
    local best
    for _, page in ipairs(ACB.pages) do
        for _, card in ipairs(page.cards) do
            local name = card.name:lower()
            if name == text then return card end
            if not best and name:find(text, 1, true) then best = card end
        end
    end
    return best
end

-- What a swap could be built from: cards they have spare (two or more) that you have none of, and the other way round.
-- Cards on your wanted list come first among the ones they have.
function ACB.swapSuggestions(mine, theirs, wanted)
    local theyHave, iHave = {}, {}
    for _, page in ipairs(ACB.pages) do
        for _, card in ipairs(page.cards) do
            local key = card.key
            local mineCount, theirCount = mine[key] or 0, theirs[key] or 0
            if theirCount >= 2 and mineCount == 0 then theyHave[#theyHave + 1] = key end
            if mineCount >= 2 and theirCount == 0 then iHave[#iHave + 1] = key end
        end
    end
    if wanted then
        local first, rest = {}, {}
        for _, key in ipairs(theyHave) do
            if wanted[key] then first[#first + 1] = key else rest[#rest + 1] = key end
        end
        for _, key in ipairs(rest) do first[#first + 1] = key end
        theyHave = first
    end
    return theyHave, iHave
end

function ACB.nameList(keys)
    local names = {}
    for index = 1, math.min(#keys, 12) do names[index] = ACB.cards[keys[index]].name end
    local text = table.concat(names, ", ")
    if #keys > 12 then text = text .. (" (+%d more)"):format(#keys - 12) end
    return text
end

-- Printable lines for someone's binder: totals, then one line for every set they have started, and, when your own
-- cards are given, what you could swap.
function ACB.inspectLines(counts, shiny, mine, wanted, theirWanted)
    local lines, owned, total, shinies = {}, 0, 0, 0
    local sets = {}
    for _, page in ipairs(ACB.pages) do
        local have = 0
        for _, card in ipairs(page.cards) do
            total = total + 1
            if (counts[card.key] or 0) > 0 then
                have, owned = have + 1, owned + 1
                if shiny[card.key] then shinies = shinies + 1 end
            end
        end
        if have > 0 then sets[#sets + 1] = ("%s   %d / %d"):format(page.title, have, #page.cards) end
    end
    lines[1] = ("%d of %d cards collected, %d shiny"):format(owned, total, shinies)
    lines[2] = ""
    for _, line in ipairs(sets) do lines[#lines + 1] = line end
    if #sets == 0 then lines[#lines + 1] = "No cards yet." end
    if mine then
        local theyHave, iHave = ACB.swapSuggestions(mine, counts, wanted)
        lines[#lines + 1] = ""
        lines[#lines + 1] = #theyHave > 0 and ("They have spares you need: " .. ACB.nameList(theyHave)) or "They have no spares you need."
        lines[#lines + 1] = #iHave > 0 and ("You have spares they need: " .. ACB.nameList(iHave)) or "You have no spares they need."
        -- What they said they are looking for, and which of those you could give.
        if theirWanted and #theirWanted > 0 then
            local give = {}
            for _, key in ipairs(theirWanted) do
                if (mine[key] or 0) >= 2 then give[#give + 1] = key end
            end
            lines[#lines + 1] = "They are looking for: " .. ACB.nameList(theirWanted)
            if #give > 0 then lines[#lines + 1] = "You have a spare of: " .. ACB.nameList(give) end
        end
    end
    return lines
end
