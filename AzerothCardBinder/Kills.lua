local _, ACB = ...

-- Kills with nothing to loot. The add-on rolls a creature's card when its loot window opens, so a critter, or any creature
-- that drops nothing, could never give its card. This watches the creature you target: if it dies while you are in combat
-- and it was yours (not tapped by someone else), it gets its one roll after a short wait, unless the loot window got there
-- first. A creature is only ever rolled once, whichever way it happens (`collection.rolled`), so looting it as well gives
-- nothing extra. Bosses are left to their own rules, and only a creature seen alive on your target counts, so walking past a
-- corpse or standing near someone else's kill gives nothing.

local LOOT_WAIT = 2.5 -- seconds to let the loot window roll first
local TICK = 0.5
local FORGET_AFTER = 30 -- stop watching a creature that has not been seen for this long
local COMBAT_GRACE = 4 -- seconds after combat when a death still counts
local MAX_WATCHED = 20

-- `api` supplies the game: now() seconds; after(delay, action); units, the unit tokens to look at; guidOf(unit) the guid of a
-- catalog creature or nil; isDead(unit); rank(unit); tapDenied(unit); inCombat(); enabled(); refresh(); log(text).
function ACB.newKillWatcher(collection, api)
    local watcher = {}
    local watched, ticking, lastCombat = {}, false, -1000

    local function schedule()
        ticking = true
        api.after(TICK, function() watcher:tick() end)
    end

    local function credit(guid, entry)
        api.log("Kill seen on target: " .. guid)
        api.after(LOOT_WAIT, function()
            if collection.rolled[guid] then return end
            collection:roll(guid, "kill", entry.rank)
            api.refresh()
        end)
    end

    -- Combat started or ended: a death a moment later still counts as part of that fight.
    function watcher:combatChanged()
        lastCombat = api.now()
    end

    -- Start watching the creature on your target, if it is a catalog creature that is alive and not yet rolled.
    function watcher:look()
        if not api.enabled() then return end
        local at = api.now()
        if api.inCombat() then lastCombat = at end
        local guid = api.guidOf("target")
        local card = guid and ACB.source(guid)
        if card and not card.profession and not card.boss and not collection.rolled[guid] and not watched[guid] and not api.isDead("target") then
            local count, oldest = 0, nil
            for key, entry in pairs(watched) do
                count = count + 1
                if not oldest or entry.seen < watched[oldest].seen then oldest = key end
            end
            if count >= MAX_WATCHED and oldest then watched[oldest] = nil end
            watched[guid] = { seen = at, rank = api.rank("target") }
        end
        if next(watched) and not ticking then schedule() end
    end

    function watcher:tick()
        ticking = false
        local at = api.now()
        if api.inCombat() then lastCombat = at end
        for guid, entry in pairs(watched) do
            local token
            for _, unit in ipairs(api.units) do
                if api.guidOf(unit) == guid then token = unit break end
            end
            if token then
                entry.seen = at
                if api.isDead(token) then
                    watched[guid] = nil
                    if at - lastCombat <= COMBAT_GRACE and not api.tapDenied(token) then
                        credit(guid, entry)
                    else
                        api.log("Kill skipped: not in combat, or tapped by someone else: " .. guid)
                    end
                else
                    entry.rank = api.rank(token) or entry.rank
                end
            elseif at - entry.seen > FORGET_AFTER then
                watched[guid] = nil
            end
        end
        if next(watched) then schedule() end
    end

    function watcher:reset()
        watched, lastCombat = {}, -1000
    end

    return watcher
end
