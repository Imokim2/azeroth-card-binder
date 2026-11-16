-- /acb auras: lists the player's buffs and debuffs, so the campfire buff can be identified in the real game. It only reads.

do
    local function withAuras(fakes, check)
        local saved = { UnitAura = UnitAura, C_UnitAuras = C_UnitAuras, issecretvalue = issecretvalue }
        UnitAura, C_UnitAuras, issecretvalue = fakes.UnitAura, fakes.C_UnitAuras, fakes.issecretvalue
        local ok, problem = pcall(check)
        UnitAura, C_UnitAuras, issecretvalue = saved.UnitAura, saved.C_UnitAuras, saved.issecretvalue
        if not ok then error(problem, 0) end
    end

    -- The older call: name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId.
    local function oldCall(buffs, debuffs)
        return function(unit, index, filter)
            equal(unit, "player")
            local row = (filter == "HELPFUL" and buffs or debuffs)[index]
            if not row then return nil end
            return row.name, 134400, row.count or 1, nil, row.duration, row.expires, row.source, false, false, row.spellId
        end
    end

    test("the older aura call is read with the time left, the spell id and the source", function()
        local now = GetTime()
        withAuras({ UnitAura = oldCall(
            { { name = "Mana Well", duration = 7200, expires = now + 7000, spellId = 777, source = "player" }, { name = "Mark of the Wild", duration = 0, expires = 0, spellId = 1126, count = 2 } },
            { { name = "Weakened Soul", duration = 15, expires = now + 9, spellId = 6788 } }) }, function()
            local list, api = ACB.playerAuras()
            equal(api, "UnitAura")
            equal(#list, 3)
            equal(list[1].kind, "BUFF"); equal(list[1].name, "Mana Well"); equal(list[1].spellId, 777)
            equal(list[1].duration, 7200); equal(list[1].remaining, 7000); equal(list[1].source, "player")
            equal(list[2].remaining, 0, "an aura with no timer has no time left"); equal(list[2].count, 2)
            equal(list[3].kind, "DEBUFF"); equal(list[3].remaining, 9)
            local text = ACB.auraText(list)
            assert(text:find("BUFF 1: Mana Well | spell id 777 | left 1h 56m of 2h 00m | from player", 1, true), text)
            assert(text:find("BUFF 2: Mark of the Wild | spell id 1126 | left no timer of no timer | x2", 1, true), text)
            assert(text:find("DEBUFF 1: Weakened Soul | spell id 6788 | left 0m 09s of 0m 15s", 1, true), text)
        end)
    end)

    test("the newer aura call is used when the game has it", function()
        local now = GetTime()
        local fake = { GetAuraDataByIndex = function(unit, index, filter)
            equal(unit, "player")
            if filter == "HELPFUL" and index == 1 then return { name = "Camp Chair", spellId = 4242, duration = 3600, expirationTime = now + 1800, applications = 0, sourceUnit = "party1" } end
        end }
        withAuras({ UnitAura = function() error("the older call must not be used") end, C_UnitAuras = fake }, function()
            local list, api = ACB.playerAuras()
            equal(api, "C_UnitAuras"); equal(#list, 1)
            equal(list[1].name, "Camp Chair"); equal(list[1].spellId, 4242); equal(list[1].remaining, 1800); equal(list[1].source, "party1")
        end)
    end)

    test("a value the game hides, a missing call and a call that fails are all survived", function()
        withAuras({ UnitAura = oldCall({ { name = "hidden", duration = 60, expires = GetTime() + 60, spellId = 5 } }, {}), issecretvalue = function(value) return value == "hidden" end }, function()
            local list = ACB.playerAuras()
            equal(list[1].name, nil)
            assert(ACB.auraText(list):find("(hidden)", 1, true))
        end)
        withAuras({ UnitAura = function() error("the game refused") end }, function()
            local list, api = ACB.playerAuras()
            equal(#list, 0)
            equal(api, nil, "nothing was read")
        end)
        local said
        withAuras({}, function() ACB.auraCommand(function(text) said = text end) end)
        equal(said, "This game does not give the add-on a way to read auras.")
    end)

    test("/acb auras says how many there are and opens the list to copy", function()
        local said = {}
        withAuras({ UnitAura = oldCall({ { name = "Mana Well", duration = 3600, expires = GetTime() + 3000, spellId = 777 } }, {}) }, function()
            ACB.auraCommand(function(text) said[#said + 1] = text end)
            SlashCmdList.AZEROTHCARDBINDER("auras")
        end)
        assert(said[1]:find("1 auras on your character (read with UnitAura)", 1, true), said[1])
        withAuras({ UnitAura = oldCall({}, {}) }, function()
            ACB.auraCommand(function(text) said[#said + 1] = text end)
        end)
        equal(said[#said], "No buffs or debuffs on your character.")
    end)
end
