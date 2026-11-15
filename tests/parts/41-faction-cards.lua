-- Cards only one faction can win (catalog card.faction, ledger spec 10, docs/FACTION-CARDS.md): the creature is friendly to the other faction,
-- which cannot kill it. Such a card is available only to that faction's characters, is hidden from the other faction unless owned, and the
-- ledger says which faction each character is before it acquires one.

local function asFaction(group, check)
    local original = UnitFactionGroup
    UnitFactionGroup = function() return group, group end
    local ok, problem = pcall(check)
    UnitFactionGroup = original
    if not ok then error(problem, 0) end
end

local function factionCard(side)
    for _, page in ipairs(ACB.pages) do
        for _, card in ipairs(page.cards) do
            if card.faction == side and card.id and ACB.sources.Creature[card.id] == card and not card.baseKey then return card, page end
        end
    end
end

test("a card only one faction can win is a source and available only to that faction", function()
    local alliance, horde = factionCard("alliance"), factionCard("horde")
    assert(alliance and horde)
    equal(alliance.since, 10)
    asFaction("Alliance", function()
        equal(ACB.playerSide(), "alliance")
        equal(ACB.cardAvailable(alliance), true)
        equal(ACB.cardAvailable(horde), false)
        equal(ACB.source(guid(alliance.id, "mine")), alliance)
        equal(ACB.source(guid(horde.id, "theirs")), nil)
    end)
    asFaction("Horde", function()
        equal(ACB.cardAvailable(horde), true)
        equal(ACB.cardAvailable(alliance), false)
    end)
    asFaction(nil, function()
        equal(ACB.playerSide(), nil, "no faction from the game, no faction cards")
        equal(ACB.cardAvailable(alliance), false)
    end)
    equal(ACB.cardAvailable(ACB.cards["npc:639"]), true, "a card both factions can win is always available")
end)

test("a binder shows the other faction's cards only when it owns one", function()
    withLaunchCollection(function()
        local alliance, horde = factionCard("alliance"), factionCard("horde")
        local function shown(card)
            for _, page in ipairs(ACB.pages) do
                for _, visible in ipairs(page.cards) do if visible == card then return true end end
            end
            return false
        end
        local saved = ACB.cleanSavedData({})
        asFaction("Alliance", function()
            ACB.refreshVisibleCards(saved)
            equal(shown(alliance), true)
            equal(shown(horde), false, "a Horde creature's card is not shown to the Alliance")
            -- ... unless a copy arrived by trade.
            saved.counts[horde.key] = 1
            ACB.refreshVisibleCards(saved)
            equal(shown(horde), true)
        end)
        -- No page needs a card only one faction can win.
        for _, page in ipairs(ACB.pages) do
            for _, card in ipairs(page.required) do assert(not card.faction, card.name .. " is not required") end
        end
    end)
end)

test("each character writes its faction once, after faction1, and a card added in spec 10 is crafted only after the markers", function()
    local records = {}
    local ledger = { flushRun = function() records[#records + 1] = "flush" end, record = function(_, kind, key) records[#records + 1] = kind .. ":" .. key end }
    local saved = ACB.cleanSavedData({})
    asFaction("Horde", function()
        ACB.activateDropBalance(saved, ledger)
        equal(table.concat(records, " "), "flush mode:chase1 flush mode:chase2 flush mode:launch1 flush mode:faction1 flush mode:side:horde")
        ACB.activateDropBalance(saved, ledger)
        equal(#records, 10, "and never again for the same character")
    end)
    local before = #records
    local original = ACB.characterName
    ACB.characterName = function() return "Other-Realm" end
    asFaction("Alliance", function()
        ACB.activateDropBalance(saved, ledger)
        equal(table.concat(records, " ", before + 1), "flush mode:side:alliance", "a second character, its own faction")
    end)
    ACB.characterName = original
    equal(saved.factionLedger, true)

    -- Crafting a card added in spec 10 writes the markers first.
    local card
    for _, page in ipairs(ACB.pages) do
        for _, candidate in ipairs(page.cards) do
            if candidate.since and not candidate.faction and candidate.dropProfile and not candidate.dropProfile.noCraft and not card then card = candidate end
        end
    end
    assert(card, "a card added in spec 10 that both factions can win and craft")
    local crafted = {}
    local fresh = ACB.cleanSavedData({ dust = 100000 })
    local collection = ACB.newCollection(fresh, math.random, ignore, ignore, ignore, ignore, {
        flushRun = function() crafted[#crafted + 1] = "flush" end,
        record = function(_, kind, key) crafted[#crafted + 1] = kind .. ":" .. key end,
    })
    equal(collection:craft(card.key), true)
    assert(table.concat(crafted, " "):find("mode:faction1", 1, true), "the faction marker comes before the craft")
    equal(crafted[#crafted], "craft:" .. card.key)
end)
