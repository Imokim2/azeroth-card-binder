local _, ACB = ...

-- The campfire (docs/CAMPFIRE.md, ledger spec 12). Standing at a camp with its buff doubles the chance of a card drop. The buff is read from the
-- player's own auras, so its length is the game's: an hour, or two when the camp has been dusted with violet. A Ranked binder says so in its ledger
-- (mode/camp1 once, then a `camp` event whenever the buff reaches further than the last claim) and writes each boosted attempt with partner "camp", so the
-- server can recheck the rolls at the doubled chance. The server cannot see a camp: the claim is the player's word, like their faction.

ACB.campFactor = 2
-- The boost is for ordinary creatures: the cards of common and rare rarity. Elites, rare spawns and bosses (epic and legendary cards) are not boosted.
function ACB.campEligible(card) return card ~= nil and card.baseKey == nil and (card.rarity == "common" or card.rarity == "rare") end
-- The camp auras the game gives (found with /acb auras): the welcoming campfire, the same dusted with violet, and Camp Benefits, the buff that shows on the
-- buff bar. That one is a welcoming or a violet buff by its own length (an hour, or two with violet dust).
ACB.campAuras = {
    [1229739] = { kind = "welcoming", seconds = 3600 },
    [1289723] = { kind = "violet", seconds = 7200 },
    [1229741] = { kind = "benefits", seconds = 7200 },
}

-- The campfire buff on the player, or nil: { kind, seconds, remaining, icon, spellId }. With both on, the one with more time left.
function ACB.campfire()
    local found
    for _, aura in ipairs((ACB.playerAuras())) do
        local camp = aura.kind == "BUFF" and aura.spellId and ACB.campAuras[aura.spellId]
        if camp and aura.remaining > 0 then
            local kind, seconds = camp.kind, camp.seconds
            if kind == "benefits" then -- more than an hour in all: the violet one
                kind = (aura.duration or 0) > 3600 and "violet" or "welcoming"
                seconds = kind == "violet" and 7200 or 3600
            end
            if not found or aura.remaining > found.remaining then
                found = { kind = kind, seconds = seconds, remaining = math.min(aura.remaining, seconds), icon = aura.icon, spellId = aura.spellId }
            end
        end
    end
    return found
end

-- Before a Ranked attempt: write what the server needs to know about the camp, once, and say whether this attempt is boosted. A Casual attempt is
-- boosted too (nothing is written). `ranked` is whether the attempt uses the tape. Returns true when the chance should be doubled.
function ACB.campBoost(saved, ledger, ranked, card)
    if not ACB.campEligible(card) then return false end
    local camp = ACB.campfire()
    if not camp then return false end
    if not ranked then return true end
    -- Only a binder that records every attempt can be boosted on the record, and only while its history verifies and has room.
    if not ledger or not saved.exactMode or not saved.factionLedger or ledger.ok == false or ledger:backlogFull() then return false end
    local seconds = math.floor(camp.remaining)
    if seconds < 1 then return false end
    if not saved.campLedger then
        ledger:flushRun()
        ledger:record("mode", "camp1")
        saved.campLedger = true
    end
    -- A claim is written only when the buff reaches further than the last one did (a few seconds of difference is the clock, not a new buff).
    local now = time()
    if now + seconds > (saved.campEnd or 0) + 5 then
        ledger:flushRun()
        local fellow = ACB.fellowshipMarker and ACB.fellowshipMarker(saved, ledger) -- Fellowship.lua: a camp earns a roll once its marker is written
        local claim = ledger:record("camp", camp.kind, { count = seconds })
        saved.campEnd = claim.t + seconds -- the server reckons the window from the event's own time
        if fellow then ACB.fellowshipOwe(saved, "camp") end -- paid before the next creature roll: this claim is made in the middle of one
    end
    return now <= saved.campEnd
end
