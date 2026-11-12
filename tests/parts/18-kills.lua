-- Kills with nothing to loot: a creature you target, that dies in your fight, still gets its one roll.

-- A watcher over a fake world. `world.units` maps a unit token to { guid, dead, tapped }.
local function killWorld()
    local world = { clock = 100, timers = {}, units = {}, combat = true, enabled = true, log = {}, refreshed = 0 }
    local saved = {}
    local _, collection = open(saved)
    world.saved, world.collection = saved, collection
    world.watcher = ACB.newKillWatcher(collection, {
        now = function() return world.clock end, units = { "target", "mouseover", "focus" },
        after = function(delay, action) world.timers[#world.timers + 1] = { at = world.clock + delay, run = action } end,
        guidOf = function(unit) local entry = world.units[unit] return entry and entry.guid end,
        isDead = function(unit) local entry = world.units[unit] return entry ~= nil and entry.dead == true end,
        rank = function() return "normal" end,
        tapDenied = function(unit) local entry = world.units[unit] return entry ~= nil and entry.tapped == true end,
        inCombat = function() return world.combat end,
        enabled = function() return world.enabled end,
        refresh = function() world.refreshed = world.refreshed + 1 end,
        log = function(text) world.log[#world.log + 1] = text end,
    })
    -- Move time forward, running whatever falls due, in order.
    function world:advance(seconds)
        local target = self.clock + seconds
        while true do
            local nextIndex
            for index, timer in ipairs(self.timers) do
                if timer.at <= target and (not nextIndex or timer.at < self.timers[nextIndex].at) then nextIndex = index end
            end
            if not nextIndex then break end
            local timer = table.remove(self.timers, nextIndex)
            self.clock = math.max(self.clock, timer.at)
            timer.run()
        end
        self.clock = target
    end
    return world
end

local RABBIT, BOSS = guid(589, "rabbit"), guid(639, "boss")

test("a creature you target that dies in your fight gets its one roll after a short wait", function()
    local world = killWorld()
    world.units.target = { guid = RABBIT }
    world.watcher:look()
    world:advance(1) -- alive: nothing yet
    equal(world.saved.counts["npc:589"], nil)
    world.units.target.dead = true
    world:advance(1) -- seen dead: the wait for the loot window begins
    equal(world.saved.counts["npc:589"], nil)
    world:advance(3)
    equal(world.saved.counts["npc:589"], 1)
    assert(world.refreshed >= 1)
    equal(world.collection.rolled[RABBIT], true)
    -- Nothing keeps ticking once nothing is watched.
    equal(#world.timers, 0)
end)

test("the loot window gets there first: the creature is not rolled twice", function()
    local world = killWorld()
    world.units.target = { guid = RABBIT }
    world.watcher:look()
    world.units.target.dead = true
    world:advance(1)
    equal(world.collection:roll(RABBIT, "loot"), true) -- the corpse was looted within the wait
    world:advance(5)
    equal(world.saved.counts["npc:589"], 1)
end)

test("a kill that was not yours, or not in your fight, gives nothing", function()
    -- Tapped by someone else.
    local tapped = killWorld()
    tapped.units.target = { guid = RABBIT, tapped = true }
    tapped.watcher:look()
    tapped.units.target.dead = true
    tapped:advance(6)
    equal(tapped.saved.counts["npc:589"], nil)
    -- Not in combat, and not for a while.
    local idle = killWorld()
    idle.combat = false
    idle.units.target = { guid = RABBIT }
    idle.watcher:look()
    idle:advance(10)
    idle.units.target.dead = true
    idle:advance(6)
    equal(idle.saved.counts["npc:589"], nil)
    -- Already dead when first seen (someone else's corpse).
    local corpse = killWorld()
    corpse.units.target = { guid = RABBIT, dead = true }
    corpse.watcher:look()
    corpse:advance(6)
    equal(corpse.saved.counts["npc:589"], nil)
    equal(#corpse.timers, 0)
end)

test("a fight that has just ended still counts, and only a creature on your target is watched", function()
    local world = killWorld()
    world.units.target = { guid = RABBIT }
    world.watcher:look()
    world.combat = false
    world.watcher:combatChanged() -- the fight ended as it died
    world.units.target.dead = true
    world:advance(1)
    world:advance(4)
    equal(world.saved.counts["npc:589"], 1)
    -- A creature only under the mouse is not watched.
    local mouse = killWorld()
    mouse.units.mouseover = { guid = RABBIT }
    mouse.watcher:look()
    mouse.units.mouseover.dead = true
    mouse:advance(6)
    equal(mouse.saved.counts["npc:589"], nil)
end)

test("bosses, gathering nodes and the setting being off are left alone, and a watched creature is forgotten", function()
    local world = killWorld()
    world.units.target = { guid = BOSS }
    world.watcher:look()
    world.units.target.dead = true
    world:advance(6)
    equal(world.saved.counts["npc:639"], nil, "bosses keep their own rules")
    local node = killWorld()
    node.units.target = { guid = guid(1731, "ore", "GameObject") }
    node.watcher:look()
    equal(#node.timers, 0)

    local off = killWorld()
    off.enabled = false
    off.units.target = { guid = RABBIT }
    off.watcher:look()
    off.units.target.dead = true
    off:advance(6)
    equal(off.saved.counts["npc:589"], nil)

    -- Out of sight for too long: forgotten, so a later corpse is not credited.
    local gone = killWorld()
    gone.units.target = { guid = RABBIT }
    gone.watcher:look()
    gone.units.target = nil
    gone:advance(40)
    equal(#gone.timers, 0)
    gone.units.target = { guid = RABBIT, dead = true }
    gone:advance(6)
    equal(gone.saved.counts["npc:589"], nil)
end)

test("in Ranked a kill roll uses the tape like any other, and the ledger stays valid", function()
    local saved = {}
    local ledger, collection = open(saved)
    ACB.sync.tape = { start = 1, entries = { "0000000000000001" } }
    assert(ACB.setMode(saved, ledger, "ranked"))
    local clock, timers, dead = 100, {}, false
    local watcher = ACB.newKillWatcher(collection, {
        now = function() return clock end, units = { "target" },
        after = function(delay, action) timers[#timers + 1] = { at = clock + delay, run = action } end,
        guidOf = function() return RABBIT end, isDead = function() return dead end, rank = function() return "normal" end,
        tapDenied = function() return false end, inCombat = function() return true end, enabled = function() return true end,
        refresh = ignore, log = ignore,
    })
    watcher:look()
    dead = true
    for _ = 1, 20 do
        clock = clock + 1
        local due, later = {}, {}
        for _, timer in ipairs(timers) do if timer.at <= clock then due[#due + 1] = timer else later[#later + 1] = timer end end
        timers = later
        for _, timer in ipairs(due) do timer.run() end
    end
    equal(saved.counts["npc:589"], 1)
    equal(saved.ledger[#saved.ledger].kind, "drop")
    equal(saved.ledger[#saved.ledger].tape, 1)
    equal(ledger:verify(), true)
    ACB.sync.tape = nil
end)

test("the setting is listed, and on by default", function()
    local found
    for _, setting in ipairs(ACB.settings) do if setting.key == "killRolls" then found = setting end end
    equal(found, nil, "critter rolls are standard behaviour, outside Settings")
    equal(ACB.setSetting({}, "killRolls", false), false)
end)
