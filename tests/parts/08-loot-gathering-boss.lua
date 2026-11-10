test("loot slots dedup by source, including mixed sources and auto-loot close", function()
    local a, b = guid(589, "one"), guid(589, "two")
    slots = { { a, 2, b, 1 }, { a, 3 } }
    emit("LOOT_READY", true)
    slots = {}
    emit("LOOT_OPENED", true, false)
    for _, callback in ipairs(timers) do callback() end
    equal(rolls, 2)
    equal(AzerothCardBinderDB.counts["npc:589"], 2)
    openLoot({ a, 1 }, { b, 1 })
    equal(rolls, 2)
end)

test("ready-only loot advances the open binder's protection once per identified corpse", function()
    local saved = AzerothCardBinderDB
    local card, before = ACB.cards["npc:589"], rolls
    local spawn = guid(589, "ready-only")
    saved.misses[card.key] = nil
    draw = 10000
    ACB.openCard(card.key)
    slots = { { spawn, 1 } }
    emit("LOOT_READY", true)
    slots = {}
    timers[#timers]()
    equal(rolls, before + 1)
    equal(saved.misses[card.key], 1)
    local protection
    for _, widget in ipairs(widgets) do
        if widget.text == "Next attempt: 2%" then protection = widget end
    end
    assert(protection)
    openLoot({ spawn, 1 }) -- a later event or reopening the same corpse does not count again
    equal(rolls, before + 1)
    emit("LOOT_READY", true)
    slots = {}
    timers[#timers]()
    equal(rolls, before + 1)
    slots = { { "Item-1-00000001", 1, guid(589, "item-origin"), 1 } }
    emit("LOOT_READY", true)
    slots = {}
    timers[#timers]()
    equal(rolls, before + 1)
    saved.misses[card.key], draw = nil, 1
end)

test("secret, unknown, live, pickpocket and item-container sources are skipped", function()
    local before = rolls
    target, dead = guid(590, "live"), false
    openLoot({ secret, secret }, { target, 1 }, { guid(99999, "unknown"), 1 }, false)
    slots = { { guid(590, "container"), 1 } }
    emit("LOOT_READY", false)
    emit("LOOT_OPENED", false, true)
    emit("UNIT_SPELLCAST_SENT", "player", secret, secret, 921)
    openLoot({ guid(590, "pickpocket"), 1 })
    equal(rolls, before)
    clock = clock + 3
    target, dead, rank = guid(590, "rank"), true, "elite"
    draw = 200
    openLoot({ target, 1 })
    equal(rolls, before + 1)
    equal(AzerothCardBinderDB.counts["npc:590"], 1)
    target, dead, rank, draw = nil, nil, nil, 1
end)

test("gathering requires player success and an exact node source in either event order", function()
    local before = rolls
    local copper, bloom = guid(1731, "copper", "GameObject"), guid(1618, "bloom", "GameObject")
    openLoot({ copper, 1 })
    cast("START", "attempt-1", 2575)
    openLoot({ copper, 1 })
    cast("INTERRUPTED", "attempt-1", 2575)
    cast("SUCCEEDED", "attempt-1", 2575)
    equal(rolls, before)
    clock = clock + 4
    cast("START", "attempt-2", 2576)
    cast("SUCCEEDED", "attempt-2", 2576, "party1")
    openLoot({ copper, 1 })
    equal(rolls, before)
    cast("SUCCEEDED", "attempt-2", 2576)
    openLoot({ copper, 1 })
    equal(rolls, before + 1)
    equal(AzerothCardBinderDB.counts["node:1731"], 1)

    clock = clock + 4
    cast("START", "attempt-3", 2366)
    cast("SUCCEEDED", "attempt-3", 2366)
    openLoot({ guid(590, "gathered-corpse"), 1 }, { bloom, 1 })
    equal(rolls, before + 3)
    equal(AzerothCardBinderDB.counts["node:1618"], 1)
    equal(AzerothCardBinderDB.counts["npc:590"], 2)
    openLoot({ guid(1618, "different", "GameObject"), 1 })
    equal(rolls, before + 3)
end)

test("boss trial shares the loot roll in both orders and rejects missing evidence", function()
    local before = rolls
    local function start()
        dead = false
        emit("ENCOUNTER_START", 555, "Edwin VanCleef", 1, 5)
        dead = true
    end
    local function finish(result)
        emit("ENCOUNTER_END", 555, "Edwin VanCleef", 1, 5, result)
    end

    instance, target = 36, guid(639, "default")
    start()
    finish(1)
    equal(rolls, before)
    SlashCmdList.AZEROTHCARDBINDER("boss")
    target = guid(639, "end-first")
    start()
    finish(1)
    finish(1)
    openLoot({ target, 1 })
    equal(rolls, before + 1)

    target = guid(639, "loot-first")
    start()
    openLoot({ target, 1 })
    finish(1)
    equal(rolls, before + 2)

    target = guid(639, "wipe")
    start()
    finish(0)
    target = guid(639, "no-readable-corpse")
    start()
    target = secret
    finish(1)
    target = guid(639, "ghost")
    start()
    playerDead = true
    finish(1)
    playerDead = false
    equal(rolls, before + 2)
    instance, target = 0, nil
end)
