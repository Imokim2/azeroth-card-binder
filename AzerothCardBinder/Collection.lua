local _, ACB = ...

-- How many recently rolled sources are remembered in the saved file.
ACB.rolledMemory = 2000

-- Sanitize every value from a game API before inspecting it.
function ACB.read(value, expectedType)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == expectedType then return value end
end

-- Call a game API that may be missing or may refuse; returns nothing instead of raising an error.
function ACB.safe(fn, ...)
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

function ACB.source(guid)
    guid = ACB.read(guid, "string")
    if not guid then return end
    -- The numeric entry ID identifies the card. Treat the whole spawn token as opaque.
    local kind, id = guid:match("^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-[^%-]+$")
    local entries = kind and ACB.sources[kind]
    if entries then return entries[tonumber(id)], kind end
end

-- Remember finished trades, newest first.
function ACB.logTrade(saved, give, take, peer, when, report)
    saved.history = saved.history or {}
    saved.tradeCount = (saved.tradeCount or #saved.history) + 1
    table.insert(saved.history, 1, { give = give, take = take, peer = peer, time = when })
    while #saved.history > 20 do table.remove(saved.history) end
    ACB.updateAchievements(saved, report)
end

-- The trade history as printable lines.
function ACB.tradeHistory(saved)
    local lines = {}
    for _, entry in ipairs(saved.history or {}) do
        local out, into = ACB.cards[entry.give], ACB.cards[entry.take]
        if out or into then
            local stamp = entry.time and (date and date("%d %b %H:%M", entry.time) or tostring(entry.time)) or ""
            local action = out and into and (out.name .. " for " .. into.name)
                or out and ("Gifted " .. out.name) or ("Received " .. into.name .. " as a gift")
            lines[#lines + 1] = ("%s   %s   with %s"):format(stamp, action, entry.peer or "?")
        end
    end
    return lines
end

-- The cards a player is looking for: the missing cards they marked as wanted.
function ACB.wantedCards(saved)
    local marked = {}
    for key in pairs(saved.wanted or {}) do
        if ACB.cards[key] and (saved.counts[key] or 0) == 0 then marked[#marked + 1] = key end
    end
    table.sort(marked)
    return marked
end

-- The chance of an attempt (10000 is 100%) after `misses` attempts without a drop, for a card whose listed rate is `rate`.
function ACB.chanceAfter(rate, misses)
    return math.min(10000, rate + rate * (ACB.stackFactor or 0) * misses)
end

-- Attempts without a drop so far, and the attempt that is certain to drop, for a catalog card.
function ACB.luck(saved, card)
    card = ACB.baseCard(card)
    local rate = ACB.rates[card.rank]
    local factor = ACB.stackFactor or 0
    local limit = factor > 0 and 1 + math.ceil((10000 - rate) / (rate * factor)) or nil
    return (saved.misses and saved.misses[card.key]) or 0, limit
end

-- What a spare copy of the card recycles into, and what the card costs to craft, in Binder Dust.
function ACB.dustFor(card)
    return ACB.dust.recycle[card.rarity] or 0, ACB.dust.craft[card.rarity] or 0
end

function ACB.luckText(saved, card, showEmpty)
    local misses = ACB.luck(saved, card)
    if misses == 0 and not showEmpty then return end
    local chance = ACB.chanceAfter(ACB.rates[card.rank], misses)
    if chance >= 10000 then return "Next attempt guaranteed" end
    return ("Next attempt: %g%%"):format(chance / 100)
end

function ACB.progress(counts, page, bossesOnly)
    local owned, total = 0, 0
    for _, card in ipairs(ACB.pages[page].cards) do
        if not bossesOnly or card.boss then
            total = total + 1
            if ACB.familyCount(counts, card) > 0 then owned = owned + 1 end
        end
    end
    return owned, total
end

-- `found` is called with the card and what happened whenever a card is added to the binder, and
-- `completed` with the set and its reward title the first time a set is finished. `ledger` (optional)
-- receives an event for every change to the binder.
function ACB.newCollection(saved, random, report, log, found, completed, ledger)
    found = found or function() end
    completed = completed or function() end
    local collection = { saved = saved, rolled = {} }
    local function record(...)
        if ledger then return ledger:record(...) end
    end

    -- Sources already rolled stay rolled across a reload: the newest ones are kept in a ring in the saved file.
    local ring = saved.rolledGuids
    for _, guid in ipairs(ring or {}) do collection.rolled[guid] = true end
    local function remember(guid)
        collection.rolled[guid] = true
        if not ring then return end
        local slot = saved.rolledNext or 1
        ring[slot] = guid
        saved.rolledNext = slot % ACB.rolledMemory + 1
    end

    -- The first time every card of a set is owned, record it and hand out the set's title.
    local function checkSet(index, announce)
        local page = ACB.pages[index]
        if not page.code then return end
        saved.sets = saved.sets or {}
        local alreadyFinished = saved.sets[page.code]
        if not alreadyFinished then
            local owned, total = ACB.progress(saved.counts, index)
            if total == 0 or owned < total then return end
        end
        saved.sets[page.code] = true
        if page.reward then
            saved.titles = saved.titles or {}
            saved.titles[page.reward] = true
            if announce and not alreadyFinished and not saved.titleHidden then saved.title = saved.title or page.reward end
        end
        if announce and not alreadyFinished then
            record("set", page.code)
            report(("Set complete: %s%s"):format(page.title, page.reward and (". Title earned: " .. page.reward) or ""))
            completed(page, page.reward)
        end
    end

    function collection:restoreAchievements()
        for index in ipairs(ACB.pages) do checkSet(index, false) end
        ACB.updateAchievements(saved)
    end

    local function checkAchievements(card)
        checkSet(card.page, true)
        ACB.updateAchievements(saved, report)
    end

    function collection:roll(guid, origin, observedRank)
        local card = ACB.source(guid)
        if not card or (card.profession ~= nil) ~= (origin == "gather") then return end
        if origin == "encounter" and not card.boss then return end
        if self.rolled[guid] then
            log("Already rolled: " .. card.name .. " (" .. origin .. ")")
            return
        end
        if ACB.editions[card.key] then ACB.activateEditions(saved, ledger) end

        -- In Ranked mode every attempt uses the next entry of the server's tape. With none left, rolling pauses.
        local ranked = saved.mode == "ranked"
        local entry, tapeIndex
        if ranked then
            entry, tapeIndex = ACB.takeTape(saved)
            if not entry then
                if not self.pausedNotice then
                    self.pausedNotice = true
                    report("Ranked rolls are paused: the roll tape has run out. Type /reload so the companion app can refill it, or switch to Casual in Settings.")
                end
                return
            end
            self.pausedNotice = nil
        end
        remember(guid)
        -- Ranked uses the card's listed rate, so the server can recheck every drop without seeing the creature.
        local threshold = ranked and ACB.rates[card.rank] or ACB.rates[observedRank] or ACB.rates[card.rank]
        saved.misses = saved.misses or {}
        -- Every miss raises the chance of the next attempt, and a drop starts it over.
        local misses = ACB.luck(saved, card)
        local chance = ACB.chanceAfter(threshold, misses)
        local guaranteed = chance >= 10000
        -- A certain drop needs no roll; a Casual roll is drawn only when it is needed.
        local dropped = guaranteed or (ranked and ACB.tapeRoll(entry) or random(1, 10000)) <= chance
        -- Any attempt on a creature can find a card pack (see Packs.lua), whether or not the card drops.
        local packWin = self.packRoll and self:packRoll(card, ranked and entry or nil)
        if saved.attempts then saved.attempts[card.key] = (saved.attempts[card.key] or 0) + 1 end
        log(("%s: %s at %g%% (%s)"):format(origin, card.name, chance / 100,
            guaranteed and "card, certain by now" or dropped and "card" or "miss"))
        if not dropped then
            saved.misses[card.key] = misses + 1
            -- Ranked writes every attempt down: misses in a row on one card are one run, kept open until something else happens.
            if ranked and ledger then
                local run = saved.run
                if run and run.key == card.key and run.last == tapeIndex - 1 then
                    run.n, run.last = run.n + 1, tapeIndex
                else
                    ledger:flushRun()
                    saved.run = { key = card.key, n = 1, last = tapeIndex }
                end
            end
            if packWin then
                if ranked and ledger then ledger:flushRun() end -- the pack belongs to this attempt, so the run ends with it
                self:addPack(card, tapeIndex)
            end
            return false
        end
        saved.misses[card.key] = nil
        if ranked and ledger then ledger:flushRun() end

        if saved.editionDrops and ACB.editions[card.key] then
            card = ACB.pickEdition(card, ranked and ACB.editionRoll(entry) or random(1, ACB.editionDenominator))
        end

        local counts = saved.counts
        local before = counts[card.key] or 0
        counts[card.key] = before + 1
        -- The shiny copy is a one-time bonus per card: once you own it, later finds are plain duplicates.
        saved.shiny = saved.shiny or {}
        local shiny = false
        if not saved.shiny[card.key] then
            if ranked then shiny = ACB.tapeShiny(entry, ACB.shinyOdds) == 1 else shiny = random(1, ACB.shinyOdds) == 1 end
        end
        if shiny then saved.shiny[card.key] = true end
        record("drop", card.key, { before = before, shiny = shiny, tape = tapeIndex })
        if packWin then self:addPack(card, tapeIndex) end
        -- A drop rolled with this computer's own random numbers cannot be rechecked by the server.
        if not ranked then saved.casualDrops = (saved.casualDrops or 0) + 1 end
        report(("%s: %s (x%d)"):format(shiny and "Shiny card found" or "Card found", card.name, counts[card.key]))
        checkAchievements(card)
        found(card, { count = counts[card.key], first = counts[card.key] == 1, shiny = shiny })
        return true
    end

    -- Hand over one copy of `give` in return for one copy of `take`: any card in the binder, a last copy included.
    -- Returns false when the player no longer has the card to give.
    -- `partner` and `tradeId` identify the trade in the ledger; both players hold the same trade id.
    function collection:swap(give, take, partner, tradeId)
        local counts = saved.counts
        local out, into = ACB.cards[give], ACB.cards[take]
        if (not out and not into) or (give and not out) or (take and not into)
            or give == take or (out and (counts[give] or 0) < 1) then return false end
        if out then
            counts[give] = counts[give] - 1
            record("tradeOut", give, { before = counts[give] + 1, partner = partner, trade = tradeId })
            if counts[give] == 0 then counts[give] = nil end
        end
        if into then
            local before = counts[take] or 0
            counts[take] = before + 1
            record("tradeIn", take, { before = before, partner = partner, trade = tradeId })
            report(out and ("Traded %s for %s"):format(out.name, into.name) or ("Received %s as a gift."):format(into.name))
            checkAchievements(into)
            found(into, { count = counts[take], first = counts[take] == 1, trade = true })
        else
            report(("Gifted %s."):format(out.name))
        end
        return true
    end

    -- Turn one spare copy into Binder Dust. The last copy of a card can never be recycled.
    function collection:recycle(key)
        local card = ACB.cards[key]
        local count = saved.counts[key] or 0
        if not card or count < 2 then return false end
        local yield = ACB.dustFor(card)
        saved.counts[key] = count - 1
        saved.dust = (saved.dust or 0) + yield
        record("recycle", key, { before = count, dust = yield })
        report(("Recycled a spare %s: +%d Binder Dust (%d in all)"):format(card.name, yield, saved.dust))
        return true
    end

    -- Spend dust on a card that is not in the binder yet. It is a plain copy, never shiny.
    function collection:craft(key)
        local card = ACB.cards[key]
        if not card or card.baseKey or (saved.counts[key] or 0) > 0 then return false end
        local _, cost = ACB.dustFor(card)
        if (saved.dust or 0) < cost then return false end
        saved.dust = saved.dust - cost
        saved.counts[key] = 1
        record("craft", key, { before = 0, dust = -cost })
        if saved.misses then saved.misses[key] = nil end
        report(("Crafted %s for %d Binder Dust (%d left)"):format(card.name, cost, saved.dust))
        checkAchievements(card)
        found(card, { count = 1, first = true, crafted = true })
        return true
    end

    if ACB.addPackMethods then
        ACB.addPackMethods(collection, { saved = saved, random = random, report = report, ledger = ledger, record = record, checkAchievements = checkAchievements })
    end
    return collection
end
