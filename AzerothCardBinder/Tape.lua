local _, ACB = ...

-- Ranked mode: the random numbers come from a "tape" the server issues and the companion app writes into
-- Data/Sync.lua, instead of from the player's own computer (docs/LEDGER-SPEC.md, section 8). Roll n uses tape entry n,
-- in order, win or lose, so the server can recompute every drop. An entry is 16 hex characters: the first 8 decide
-- the drop, the next 8 decide whether a first copy is shiny.

-- The roll, 1 to 10000. A drop needs a roll at or below the chance of the attempt: the card's rate (100 is 1%)
-- plus the stack from earlier misses.
function ACB.tapeRoll(entry)
    return tonumber(entry:sub(1, 8), 16) % 10000 + 1
end

-- The shiny roll, 1 to `odds`. A first copy is shiny when it is 1.
function ACB.tapeShiny(entry, odds)
    return tonumber(entry:sub(9, 16), 16) % odds + 1
end

-- Take the next unused tape entry, or nothing when the tape has run out or is missing. Returns the entry and its
-- position (counting from 1); the position is stored in the drop event. The entry is used up either way.
function ACB.takeTape(saved)
    saved.tape = type(saved.tape) == "table" and saved.tape or { next = 1 }
    local tape = ACB.sync and ACB.sync.tape
    if type(tape) ~= "table" or type(tape.entries) ~= "table" or type(tape.start) ~= "number" then return end
    local index = saved.tape.next
    if type(index) ~= "number" or index < tape.start then return end
    local entry = tape.entries[index - tape.start + 1]
    if type(entry) ~= "string" or #entry ~= 16 or entry:find("[^0-9a-f]") then return end
    saved.tape.next = index + 1
    return entry, index
end

-- How many tape entries are left, for the Settings tab and /acb verify.
function ACB.tapeLeft(saved)
    local tape = ACB.sync and ACB.sync.tape
    if type(tape) ~= "table" or type(tape.entries) ~= "table" or type(tape.start) ~= "number" then return 0 end
    local next = type(saved.tape) == "table" and saved.tape.next or 1
    return math.max(0, tape.start + #tape.entries - math.max(next, tape.start))
end

-- Switch between Casual and Ranked. The switch is written to the ledger so the server knows which rules apply to
-- the events that follow. Returns true, or false and the reason.
function ACB.setMode(saved, ledger, mode)
    if mode ~= "casual" and mode ~= "ranked" then return false, "The mode is casual or ranked." end
    if saved.mode == mode then return true end
    ledger:flushRun()
    if mode == "ranked" then
        if saved.legacy then
            return false, "Your binder holds cards from before the ledger, which the server cannot check. Ranked needs a fresh binder."
        end
        if not ledger:check() then
            return false, "Your binder is unverified, so it cannot play Ranked."
        end
    end
    saved.mode = mode
    if mode == "ranked" then
        -- Ranked writes down every attempt (docs/LEDGER-SPEC.md, section 8.1). The event names the last tape entry used so
        -- far, and every card starts its run of misses again, so the server can follow each chance from zero.
        saved.misses, saved.exactMode = {}, true
        ledger:record("mode", "ranked2", { tape = ACB.tapeUsed(saved) })
    else
        saved.exactMode = nil
        ledger:record("mode", mode)
    end
    return true
end

-- The last tape entry this binder has used (0 before the first).
function ACB.tapeUsed(saved)
    return (type(saved.tape) == "table" and saved.tape.next or 1) - 1
end

-- A binder that was already in Ranked when it loaded, from a version that did not write attempts down, starts doing so.
function ACB.resumeRanked(saved, ledger)
    if saved.mode ~= "ranked" or saved.exactMode then return end
    saved.misses, saved.exactMode = {}, true
    ledger:record("mode", "ranked2", { tape = ACB.tapeUsed(saved) })
end
