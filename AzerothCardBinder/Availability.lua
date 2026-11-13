local _, ACB = ...

-- Cards held back for seasons (LaunchCollection.lua): when are they available, and which ones does a binder show?
--
-- A held-back card is available from the start of the first season that features it, and for good after that. The server tells the
-- add-on which are released (Data/Sync.lua, sync.seasonal.released). Until then such a card is not rolled for, not found in a pack, not
-- crafted, and not shown in a binder that does not already own it. A binder that owns a copy keeps it and sees it. The ledger records the
-- switch once (mode/launch1); from then on the server refuses what this file declines to do.

function ACB.isSeasonal(card)
    local base = card and ACB.baseCard(card)
    return base ~= nil and base.seasonal == true
end

local indexed, index = false, {}
local function released()
    local list = ACB.sync and ACB.sync.seasonal and ACB.sync.seasonal.released
    if list ~= indexed then
        indexed, index = list, {}
        if type(list) == "table" then
            for _, key in ipairs(list) do
                if type(key) == "string" then index[key] = true end
            end
        end
    end
    return index
end

-- May this card be found, rolled for or crafted now? (Cards that are not held back always may.)
function ACB.cardAvailable(card)
    local base = card and ACB.baseCard(card)
    if not base or not base.seasonal then return true end
    return released()[base.key] == true
end

local function same(first, second)
    if #first ~= #second then return false end
    for position = 1, #first do
        if first[position] ~= second[position] then return false end
    end
    return true
end

-- Rebuild what each page shows (page.cards, in place) from page.all: its launch cards, the held-back ones that have been released, and
-- any the binder already owns. True if anything changed.
function ACB.refreshVisibleCards(saved)
    local counts = saved and saved.counts or {}
    local changed = false
    for _, page in ipairs(ACB.pages) do
        if page.all then
            local visible = {}
            for _, card in ipairs(page.all) do
                if not card.seasonal or ACB.cardAvailable(card) or ACB.familyCount(counts, card) > 0 then visible[#visible + 1] = card end
            end
            if not same(page.cards, visible) then
                for position = #page.cards, 1, -1 do page.cards[position] = nil end
                for position, card in ipairs(visible) do page.cards[position] = card end
                changed = true
            end
        end
    end
    return changed
end
