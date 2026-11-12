local _, ACB = ...

-- Card packs (docs/LEDGER-SPEC.md, section 8.2). Any attempt on a creature can find a pack, 1 in 500, and a pack holds five
-- cards from the zone (a set of the catalog) it was found in. In Ranked both are decided by tape entries, so the server can
-- recheck them: a pack is found when the second half of the attempt's entry says so, and opening one spends the next five
-- entries, one card each. In Casual the computer's own random numbers are used, as for any Casual drop.
--
-- A tape entry is 16 hex characters: the first 8 give the roll (1 to 10000) and the next 8 are split two ways so that the
-- shiny roll and these draws do not depend on each other: `hex2 mod shinyOdds` is the shiny remainder, and
-- `floor(hex2 / shinyOdds)` is what is used here. The shared vectors (packs.json) check this against the server's code.

ACB.packOdds, ACB.packSize = 500, 5
-- Chance of each rarity out of 10000, before the rarities a zone has none of are left out.
local RARITIES = { { "common", 7000 }, { "rare", 2000 }, { "epic", 800 }, { "legendary", 200 } }

local byCode
-- The page (zone, dungeon or raid) of a set code.
function ACB.pageOfZone(zone)
    if not byCode then
        byCode = {}
        for _, page in ipairs(ACB.pages) do
            if page.code then byCode[page.code] = page end
        end
    end
    return byCode[zone]
end

local items = {}
ACB.packTiers = {
    common = { name = "Common", size = 1, color = { .72, .72, .72 } },
    rare = { name = "Rare", size = 3, color = { .26, .57, 1 } },
    epic = { name = "Epic", size = 5, color = { .72, .35, 1 } },
}
function ACB.packInfo(id)
    if type(id) ~= "string" then return end
    local zone, tier = id:match("^(%u[%u%d]*):(%l+)$")
    if not zone then zone, tier = id:match("^(%u[%u%d]*)$"), "epic" end
    if not zone or not ACB.packTiers[tier] or (tier == "epic" and id ~= zone) then return end
    local page = ACB.pageOfZone(zone)
    if page then return { id = id, zone = zone, tier = tier, size = ACB.packTiers[tier].size, page = page } end
end
function ACB.packItem(key)
    local id = type(key) == "string" and key:match("^pack:(.+)$")
    local info = ACB.packInfo(id)
    if not info then return end
    if not items[key] then items[key] = { key = key, zone = id, pack = true, tier = info.tier,
        size = info.size, name = "Pack: " .. info.page.title, page = info.page } end
    return items[key]
end


local function second(entry)
    return tonumber(entry:sub(9, 16), 16)
end

-- 1 when the attempt that used this entry found a pack.
function ACB.packValue(entry)
    return math.floor(second(entry) / ACB.shinyOdds) % ACB.packOdds + 1
end

function ACB.packTier(entry)
    local draw = math.floor(second(entry) / ACB.shinyOdds / ACB.packOdds) % 100
    return draw < 70 and "common" or draw < 95 and "rare" or "epic"
end
function ACB.packID(zone, tier) return tier == "epic" and zone or zone .. ":" .. tier end

-- The card key an entry gives from a zone's pack, or nil for an unknown zone.
function ACB.packPick(zone, entry, balanced)
    local page = ACB.pageOfZone(zone)
    if not page then return end
    local pools, total = {}, 0
    for _, rarity in ipairs(RARITIES) do
        local cards = {}
        for _, card in ipairs(page.cards) do
            if card.rarity == rarity[1] then cards[#cards + 1] = card.key end
        end
        table.sort(cards, function(a, b)
            local x, y = ACB.cards[a].id, ACB.cards[b].id
            if x ~= y then return x < y end
            return a < b
        end)
        if #cards > 0 then
            pools[#pools + 1] = { weight = rarity[2], cards = cards }
            total = total + rarity[2]
        end
    end
    if #pools == 0 then return end
    local scaled = (tonumber(entry:sub(1, 8), 16) % 10000) * total -- (roll - 1) * total
    local upTo, chosen = 0, pools[#pools]
    for _, pool in ipairs(pools) do
        upTo = upTo + pool.weight * 10000
        if scaled < upTo then chosen = pool break end
    end
    local draw = math.floor(second(entry) / ACB.shinyOdds)
    if not balanced then return chosen.cards[draw % #chosen.cards + 1] end
    local weight = 0
    for _, key in ipairs(chosen.cards) do weight = weight + ACB.cards[key].dropProfile.packWeight end
    draw = draw % weight
    for _, key in ipairs(chosen.cards) do
        draw = draw - ACB.cards[key].dropProfile.packWeight
        if draw < 0 then return key end
    end
end

-- An entry made from the computer's random numbers, for a Casual pack, in the same layout as a tape entry.
function ACB.randomEntry(random)
    return ("%08x%08x"):format(random(1, 10000) - 1, random(0, 65535) * 65536 + random(0, 65535))
end

-- How many packs of each zone, in a stable order (most first), and in all.
function ACB.packList(saved)
    local list, total = {}, 0
    for zone, count in pairs(saved.packs or {}) do
        local info = ACB.packInfo(zone)
        if info and type(count) == "number" and count >= 1 then
            list[#list + 1] = { zone = zone, count = count, page = info.page, tier = info.tier, size = info.size }
            total = total + count
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.page.title ~= b.page.title then return a.page.title < b.page.title end
        if a.size ~= b.size then return a.size > b.size end
        return a.zone < b.zone
    end)
    return list, total
end

-- Called when a collection is built. `ctx` holds what the collection keeps to itself: saved, random, report, ledger, record
-- (writes a ledger event) and checkAchievements. Packs stay off for a collection until `collection.packsEnabled` is set, so
-- code that builds a collection with its own scripted random numbers is not surprised by them.
function ACB.addPackMethods(collection, ctx)
    local saved, random, report, ledger, record = ctx.saved, ctx.random, ctx.report, ctx.ledger, ctx.record

    function collection:packAvailable(zone)
        return math.max(0, (saved.packs and saved.packs[zone] or 0) - (self.packReserved and self.packReserved(zone) and 1 or 0))
    end

    -- Does this attempt find a pack? `entry` is the tape entry in Ranked. Never for a gathering node.
    function collection:packRoll(card, entry)
        if not self.packsEnabled or card.profession then return false end
        if entry then return ACB.packValue(entry) == 1 end
        return random(1, ACB.packOdds) == 1
    end

    -- A pack was found on an attempt on `card`; `tapeIndex` is that attempt's entry (nil in Casual).
    function collection:addPack(card, tapeIndex, entry)
        local page = ACB.pages[card.page]
        local zone = page and page.code
        if not zone then return false end
        if saved.tieredPacks then
            if not saved.packTiersLedger then
                if ledger then ledger:flushRun() end
                record("mode", "packs2")
                saved.packTiersLedger = true
            end
            local draw = not entry and random(1, 100)
            local tier = entry and ACB.packTier(entry) or draw <= 70 and "common" or draw <= 95 and "rare" or "epic"
            zone = ACB.packID(zone, tier)
        end
        local item = ACB.packItem("pack:" .. zone)
        saved.packs = saved.packs or {}
        local count = (saved.packs[zone] or 0) + 1
        saved.packs[zone] = count
        record("packFind", zone, { count = count, tape = tapeIndex })
        if not tapeIndex or tapeIndex == 0 then saved.casualDrops = (saved.casualDrops or 0) + 1 end
        report(("Card pack found: %s (%s). Open your Warcards Satchel with /acb bag."):format(item.name, ACB.packTiers[item.tier].name))
        if self.onPack then self.onPack(page, count) end
        return true
    end

    -- Open one pack of a zone: five cards. Returns the five results { card, shiny, first, count }, or nil and why.
    function collection:openPack(zone)
        local info = ACB.packInfo(zone)
        local page = info and info.page
        local held = saved.packs and saved.packs[zone] or 0
        if not page or held < 1 then return nil, "You have no pack for that zone." end
        if self:packAvailable(zone) < 1 then return nil, "This pack is in your trade. Remove it or cancel the trade before opening it." end
        local ranked = saved.mode == "ranked"
        if ranked and not ACB.tapeHolds(saved, info.size) then
            return nil, ("A Ranked pack needs %d roll tape entries. Type /reload so the companion app can bring more, or switch to Casual."):format(info.size)
        end
        if ledger then ledger:flushRun() end
        ACB.activateDropBalance(saved, ledger)
        ACB.activateEditions(saved, ledger)
        saved.packs[zone] = held > 1 and held - 1 or nil
        record("packOpen", zone, { count = held - 1, tape = ranked and ACB.tapeUsed(saved) or 0 })
        saved.shiny = saved.shiny or {}
        local results, seen = {}, {}
        for index = 1, info.size do
            local entry, tapeIndex
            if ranked then entry, tapeIndex = ACB.takeTape(saved) else entry = ACB.randomEntry(random) end
            local key = ACB.packPick(info.zone, entry, saved.balancedDrops)
            if saved.editionDrops then key = ACB.pickEdition(ACB.cards[key], ACB.editionRoll(entry), saved.balancedDrops).key end
            local before = saved.counts[key] or 0
            saved.counts[key] = before + 1
            local shiny = not saved.shiny[key] and ACB.tapeShiny(entry, ACB.shinyOdds) == 1
            if shiny then saved.shiny[key] = true end
            record("packCard", key, { before = before, shiny = shiny, tape = tapeIndex })
            -- A Casual pack cannot be rechecked by the server, like any Casual drop.
            if not ranked then saved.casualDrops = (saved.casualDrops or 0) + 1 end
            results[index] = { card = ACB.cards[key], shiny = shiny, first = before == 0, count = saved.counts[key] }
            seen[#seen + 1] = results[index].card
        end
        -- Sets and titles are written once all five cards are down: nothing may come between a pack's cards.
        for _, card in ipairs(seen) do ctx.checkAchievements(card) end
        return results
    end

    return collection
end
