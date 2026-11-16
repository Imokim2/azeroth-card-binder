-- The campfire in the buff bar (docs/CAMPFIRE.md): Camp Benefits (1229741) is the game's own buff for a camp. Its tooltip gets a line saying the card rate is
-- doubled, where the game lets an add-on do that; the add-on's own icon shows until that line has been seen working, and can be dragged.

do
    local BENEFITS, WELCOMING, VIOLET = 1229741, 1229739, 1289723

    local function withBuffs(buffs, check)
        local keep = { UnitAura = UnitAura, C_UnitAuras = C_UnitAuras }
        C_UnitAuras = nil
        UnitAura = function(unit, index, filter)
            local buff = filter == "HELPFUL" and buffs[index]
            if not buff then return nil end
            return buff.name or "Camp Benefits", 135805, 1, nil, buff.duration or 3600, GetTime() + buff.remaining, "player", false, false, buff.spellId
        end
        local ok, problem = pcall(check)
        UnitAura, C_UnitAuras = keep.UnitAura, keep.C_UnitAuras
        if not ok then error(problem, 0) end
    end
    local function tip()
        local lines = { shown = 0 }
        function lines:AddLine(text) self[#self + 1] = text end
        function lines:Show() self.shown = self.shown + 1 end
        return lines
    end
    local function withSettings(settings, check)
        local keep = AzerothCardBinderDB
        AzerothCardBinderDB = settings
        local ok, problem = pcall(check)
        AzerothCardBinderDB = keep
        if not ok then error(problem, 0) end
    end

    test("Camp Benefits is the campfire buff, a welcoming or a violet one by its own length", function()
        withBuffs({ { spellId = BENEFITS, remaining = 3000, duration = 3600 } }, function()
            local camp = ACB.campfire()
            equal(camp.kind, "welcoming"); equal(camp.seconds, 3600); equal(camp.remaining, 3000); equal(camp.spellId, BENEFITS)
        end)
        withBuffs({ { spellId = BENEFITS, remaining = 7000, duration = 7200 } }, function()
            local camp = ACB.campfire()
            equal(camp.kind, "violet"); equal(camp.seconds, 7200); equal(camp.remaining, 7000)
        end)
        withBuffs({ { spellId = BENEFITS, remaining = 99999, duration = 3600 } }, function() equal(ACB.campfire().remaining, 3600, "never more than the buff lasts") end)
        -- With the other camp buffs it is the one with the most time left, whichever is which.
        withBuffs({ { spellId = WELCOMING, remaining = 900 }, { spellId = BENEFITS, remaining = 2000, duration = 3600 } }, function() equal(ACB.campfire().spellId, BENEFITS) end)
        withBuffs({ { spellId = BENEFITS, remaining = 2000, duration = 3600 }, { spellId = VIOLET, remaining = 6000, duration = 7200 } }, function() equal(ACB.campfire().kind, "violet") end)
    end)

    test("the line goes on the camp buff's tooltip only, only while the player has it, and once", function()
        withSettings({}, function()
            local plain, other = tip(), tip()
            withBuffs({ { spellId = BENEFITS, remaining = 3000, duration = 3600 } }, function()
                equal(ACB.campTooltip(plain, BENEFITS), true)
                equal(#plain, 1); assert(plain[1]:find("card drop chance doubled", 1, true), plain[1]); equal(plain.shown, 1, "the tooltip is shown again so it grows to fit")
                equal(AzerothCardBinderDB.campTooltipSeen, true)
                equal(ACB.campTooltip(plain, BENEFITS), false, "not twice in one moment")
                equal(#plain, 1)
                equal(ACB.campTooltip(other, 12345), false, "another spell")
                equal(ACB.campTooltip(other, nil), false); equal(ACB.campTooltip(other, "x"), false); equal(ACB.campTooltip(nil, BENEFITS), false)
                equal(#other, 0)
                equal(ACB.campTooltip(tip(), WELCOMING), true, "the camp's other auras get it too")
            end)
            withBuffs({}, function() equal(ACB.campTooltip(tip(), BENEFITS), false, "no buff: nothing to describe") end)
        end)
    end)

    test("the add-on's icon shows until the tooltip line has been seen working, unless it is set to on or off", function()
        withBuffs({ { spellId = BENEFITS, remaining = 3000, duration = 3600 } }, function()
            withSettings({}, function()
                ACB.refreshCampfire()
                equal(ACB.campfireShown(), true, "automatic: shown until the line has been seen")
                ACB.campTooltip(tip(), BENEFITS)
                equal(ACB.campfireShown(), false, "the game's own buff says it now")
                ACB.campfireCommand(AzerothCardBinderDB, "icon on", ignore)
                equal(ACB.campfireShown(), true, "on keeps it")
                ACB.campfireCommand(AzerothCardBinderDB, "icon off", ignore)
                equal(ACB.campfireShown(), false)
                local said = {}
                ACB.campfireCommand(AzerothCardBinderDB, "icon auto", function(text) said[#said + 1] = text end)
                equal(AzerothCardBinderDB.campTooltipSeen, nil, "automatic starts again"); equal(AzerothCardBinderDB.campfireIcon, nil)
                equal(ACB.campfireShown(), true)
                assert(said[1]:find("automatic", 1, true), said[1])
                -- The older settings still mean what they did.
                AzerothCardBinderDB.campfireIcon = false
                ACB.refreshCampfire(); equal(ACB.campfireShown(), false)
                AzerothCardBinderDB.campfireIcon = true
                ACB.refreshCampfire(); equal(ACB.campfireShown(), true)
            end)
        end)
    end)

    test("the tooltip is hooked the way the client allows: tooltip data and the older calls", function()
        local kinds = {}
        for _, hook in ipairs(auraCallbacks) do kinds[hook.kind] = hook.callback end
        local SPELL, UNIT_AURA = 3, 4 -- the fake game's tooltip data kinds (the hints take the unit and object ones)
        assert(kinds[UNIT_AURA] and kinds[SPELL], "both kinds of tooltip data are hooked")
        local keepTooltip, keepHook = GameTooltip, hooksecurefunc
        local calls = {}
        local game = tip()
        game.SetUnitAura, game.SetUnitBuff = function() end, function() end
        GameTooltip = game
        hooksecurefunc = function(target, name, hook) calls[name] = hook; return true end
        local ok, problem = pcall(function()
            ACB.installCampTooltip(true)
            assert(calls.SetUnitAura and calls.SetUnitBuff, "the older calls are hooked")
            equal(calls.SetUnitBuffByAuraInstanceID, nil, "a call this client does not have is not hooked")
            withSettings({}, function()
                withBuffs({ { spellId = 12345, remaining = 900 }, { spellId = BENEFITS, remaining = 3000, duration = 3600 } }, function()
                    local seen = tip()
                    calls.SetUnitAura(seen, "player", 1, "HELPFUL"); equal(#seen, 0, "the first buff is not the camp's")
                    calls.SetUnitAura(seen, "player", 2, "HELPFUL"); equal(#seen, 1, "the second is")
                    local again = tip()
                    calls.SetUnitBuff(again, "player", 2); equal(#again, 1)
                    local target = tip()
                    calls.SetUnitAura(target, "target", 2, "HELPFUL"); equal(#target, 0, "only the player's own buffs")
                    -- Tooltip data: the game's own tooltip, and what it says is the camp's buff.
                    kinds[UNIT_AURA](tip(), { id = BENEFITS }) -- not the game's own tooltip: left alone
                    equal(#game, 0)
                    kinds[UNIT_AURA](game, { id = BENEFITS })
                    equal(#game, 1)
                    kinds[SPELL](game, { id = 12345 }); equal(#game, 1)
                end)
            end)
        end)
        GameTooltip, hooksecurefunc = keepTooltip, keepHook
        if not ok then error(problem, 0) end
    end)

    test("the icon can be dragged, the place is remembered, and it can be put back", function()
        withSettings({}, function()
            withBuffs({ { spellId = BENEFITS, remaining = 3000, duration = 3600 } }, function()
                ACB.refreshCampfire()
                local frame = _G["AzerothCardBinderCampfire"]
                assert(frame.OnDragStart and frame.OnDragStop, "it has drag scripts")
                frame:OnDragStart()
                frame.point = { "TOPLEFT", UIParent, "TOPLEFT", 120, -80 }
                frame:OnDragStop()
                local at = AzerothCardBinderDB.campfirePos
                equal(at.point, "TOPLEFT"); equal(at.relativePoint, "TOPLEFT"); equal(at.x, 120); equal(at.y, -80)
                -- Put back where it was left, when the game next places it.
                frame.point = nil
                ACB.placeCampfire()
                equal(frame.point[1], "TOPLEFT"); equal(frame.point[3], "TOPLEFT"); equal(frame.point[4], 120); equal(frame.point[5], -80)
                -- A saved place that makes no sense is ignored.
                AzerothCardBinderDB.campfirePos = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = "far", y = 0 }
                ACB.placeCampfire()
                equal(frame.point[1], "TOPRIGHT", "beside the buff bar instead")
                AzerothCardBinderDB.campfirePos = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 99999, y = 0 }
                ACB.placeCampfire()
                equal(frame.point[1], "TOPRIGHT")
                -- /acb campfire reset forgets the place.
                AzerothCardBinderDB.campfirePos = at
                local said = {}
                ACB.campfireCommand(AzerothCardBinderDB, "reset", function(text) said[#said + 1] = text end)
                equal(AzerothCardBinderDB.campfirePos, nil); equal(frame.point[1], "TOPRIGHT")
                assert(said[1]:find("put back", 1, true), said[1])
            end)
        end)
    end)

    test("a Ranked attempt with Camp Benefits writes the claim under the buff's own length", function()
        local saved, ledger, collection
        do
            ACB.sync.rankedIssue = nil
            saved = {}
            local _, upgraded = ACB.cleanSavedData(saved)
            saved.tieredPacks = false
            ledger = newLedger(saved)
            ledger:begin(upgraded)
            collection = ACB.newCollection(saved, function() error("Ranked mode must not use the computer's random numbers") end, ignore, ignore, nil, nil, ledger)
            ACB.sync.tape = { start = 1, entries = { ("%08x"):format(9999) .. "00000015" } }
            assert(ACB.setMode(saved, ledger, "ranked"))
            ledger:check()
        end
        withBuffs({ { spellId = BENEFITS, remaining = 6500, duration = 7200 } }, function() collection:roll(guid(589, "a"), "loot") end)
        local claim
        for _, event in ipairs(saved.ledger) do if event.kind == "camp" then claim = event end end
        equal(claim.key, "violet"); equal(claim.count, 6500)
    end)
end
