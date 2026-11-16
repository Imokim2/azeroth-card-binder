local _, ACB = ...

-- The Fellowship cards (CatalogFellowship.lua, docs/FELLOWSHIP.md, ledger spec 12). Completing an activity earns one roll, at one in a hundred (doubled at a
-- camp), for the card that belongs to it: a trade, a gift given or received, a donation to the guild binder, a camp with the campfire buff. Both sides of
-- a trade or a gift roll. The ledger keeps the same count the add-on does (mode/fellow1, then a roll earned by each activity event and spent by each
-- attempt), so the server can check that every attempt followed an activity.
--
-- The add-on keeps the rolls it owes in the saved file (`fellowOwed`) and pays them as soon as it can: at once after a trade, a gift or a donation, and
-- before the next creature roll for a camp (which is claimed in the middle of one). A Ranked roll needs an entry of the roll tape; with none, the roll
-- stays owed.

local ORDER = { "trade", "gift", "donate", "camp" }
local CAP = 50 -- rolls owed at one time; more than this are not kept, so a long wait on the tape cannot pile up
local settling = false

-- The rolls owed, as whole numbers for known activities.
function ACB.cleanFellowship(saved)
    local owed = type(saved.fellowOwed) == "table" and saved.fellowOwed or {}
    saved.fellowOwed = {}
    for _, kind in ipairs(ORDER) do
        local count = owed[kind]
        if type(count) == "number" and count >= 1 and count == math.floor(count) then saved.fellowOwed[kind] = math.min(count, CAP) end
    end
end

-- Write mode/fellow1 once, after the markers that come before it, so activities from now on earn rolls. It has to come before the activity's own event.
-- Returns whether the binder can earn rolls (it is on the current drop rules, its history verifies and it records every attempt).
function ACB.fellowshipMarker(saved, ledger)
    if not ledger or ledger.ok == false or not saved.balancedDrops then return false end
    if saved.mode == "ranked" and not saved.exactMode then return false end
    if saved.fellowLedger then return true end
    ACB.activateDropBalance(saved, ledger)
    if not saved.factionLedger or not (saved.sides and saved.sides[ACB.characterName()]) then return false end
    ledger:flushRun()
    ledger:record("mode", "fellow1")
    saved.fellowLedger = true
    return true
end

-- One roll more is owed for an activity just completed (its event is already in the ledger).
function ACB.fellowshipOwe(saved, kind)
    saved.fellowOwed = type(saved.fellowOwed) == "table" and saved.fellowOwed or {}
    saved.fellowOwed[kind] = math.min((saved.fellowOwed[kind] or 0) + 1, CAP)
end

-- Pay the rolls owed, one attempt each, stopping when one cannot be made (no roll tape left, or the binder is not ready).
function ACB.settleFellowship(collection)
    local saved = collection and collection.saved
    if settling or not saved or type(saved.fellowOwed) ~= "table" then return end
    settling = true
    local ok, problem = pcall(function() -- a roll that fails must not leave the rest of the add-on stuck: it is noted and the rolls stay owed
        for _, kind in ipairs(ORDER) do
            local card = ACB.activityCards[kind]
            while card and (saved.fellowOwed[kind] or 0) > 0 do
                if collection:roll(card.key, "activity") == nil then return end
                local left = saved.fellowOwed[kind] - 1
                saved.fellowOwed[kind] = left > 0 and left or nil
            end
        end
    end)
    settling = false
    if not ok then ACB.fellowshipProblem = tostring(problem) end
end

-- An activity was completed: owe its roll and pay it now.
function ACB.fellowshipEarn(saved, kind, collection)
    ACB.fellowshipOwe(saved, kind)
    ACB.settleFellowship(collection or (ACB.collection and ACB.collection.saved == saved and ACB.collection) or nil)
end
