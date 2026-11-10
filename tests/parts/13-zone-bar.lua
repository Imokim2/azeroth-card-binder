-- The zone card bar: it finds the set for the place you are in and follows you between zones and dungeons.

test("place names from the game find their set, with or without 'The', punctuation or a wing name", function()
    local function title(name)
        local index = ACB.pageForName(name)
        return index and ACB.pages[index].title
    end
    equal(title("The Deadmines"), "Deadmines")
    equal(title("Deadmines"), "Deadmines")
    equal(title("Westfall"), "Westfall")
    equal(title("westfall"), "Westfall")
    equal(title("Barrens"), "The Barrens")
    equal(title("The Barrens"), "The Barrens")
    equal(title("Zul'Gurub"), "Zul'Gurub")
    equal(title("Upper Blackrock Spire"), "Blackrock Spire")
    equal(title("The Stockade"), "Stormwind Stockade")
    equal(title("Zephras Isle"), "Zephras Isle")
    equal(title("Stormwind City"), nil) -- no set for a city
    equal(title("Gathering"), nil) -- the gathering set is not a place
    equal(title(""), nil)
    equal(title(nil), nil)
    equal(title(secret), nil) -- a value the game hides is never read
end)

test("the bar shows the cards owned in the place you are in and follows you from place to place", function()
    local saved = AzerothCardBinderDB
    local bar = AzerothCardBinderZoneBar
    assert(bar, "the add-on creates the bar")
    local keep = { saved.counts["npc:589"], saved.zoneBar, GetRealZoneText, GetInstanceInfo, instance }
    local function label()
        for _, widget in ipairs(widgets) do
            if widget.text and widget.text:find("^Westfall   ") then return widget.text end
        end
    end
    saved.zoneBar = nil
    local index = ACB.pageForName("Westfall")
    local owned, total = ACB.progress(saved.counts, index)

    -- Walking into Westfall.
    GetRealZoneText = function() return "Westfall" end
    bar.ZONE_CHANGED_NEW_AREA = true
    bar.OnEvent(bar, "ZONE_CHANGED_NEW_AREA")
    equal(bar.shown, true)
    equal(bar.high, total)
    equal(bar.value, owned)
    equal(label(), ("Westfall   %d / %d"):format(owned, total))

    -- Finding a card moves the bar.
    saved.counts["npc:589"] = (saved.counts["npc:589"] or 0) + 1
    local expected = select(2, ACB.progress(saved.counts, index))
    ACB.refreshZoneBar()
    equal(bar.value, (select(1, ACB.progress(saved.counts, index))))
    assert(expected == total)

    -- Into a city with no set: the bar goes away. Out of it again: it comes back.
    GetRealZoneText = function() return "Stormwind City" end
    bar.OnEvent(bar, "ZONE_CHANGED_NEW_AREA")
    equal(bar.shown, false)
    GetRealZoneText = function() return "Westfall" end
    bar.OnEvent(bar, "ZONE_CHANGED_NEW_AREA")
    equal(bar.shown, true)

    -- Through the door of a dungeon the bar changes to the dungeon's set.
    instance = 1
    GetInstanceInfo = function() return "The Deadmines", "party", 1, "", 5, false, false, 36 end
    bar.OnEvent(bar, "PLAYER_ENTERING_WORLD")
    equal(bar.shown, true)
    local dungeon = ACB.pageForName("Deadmines")
    equal(bar.high, (select(2, ACB.progress(saved.counts, dungeon))))
    equal(bar.value, (select(1, ACB.progress(saved.counts, dungeon))))

    -- Switched off in Settings or with /acb bar, it hides; /acb bar brings it back.
    SlashCmdList.AZEROTHCARDBINDER("bar")
    equal(saved.zoneBar, false)
    equal(bar.shown, false)
    SlashCmdList.AZEROTHCARDBINDER("bar")
    equal(saved.zoneBar, true)
    equal(bar.shown, true)

    -- A dragged position is kept, and /acb bar reset puts it back above the experience bar.
    saved.zoneBarSpot = { x = 10, y = 200 }
    ACB.refreshZoneBar()
    equal(bar.point[1], "BOTTOM")
    equal(bar.point[4], 10)
    SlashCmdList.AZEROTHCARDBINDER("bar reset")
    equal(saved.zoneBarSpot, nil)

    saved.counts["npc:589"], saved.zoneBar, GetRealZoneText, GetInstanceInfo, instance = unpack(keep, 1, 5)
    ACB.refreshZoneBar()
end)

test("the bar takes the honour bar's place, gives it back when it is off or has nothing to show, and works without one", function()
    local saved = AzerothCardBinderDB
    local bar = AzerothCardBinderZoneBar
    local keep = { saved.zoneBar, saved.zoneBarSpot, GetRealZoneText }
    saved.zoneBar, saved.zoneBarSpot = nil, nil
    GetRealZoneText = function() return "Westfall" end

    -- No honour bar: the bar sits above the experience bar, as before.
    ACB.refreshZoneBar()
    equal(ACB.honourBar(), nil)
    equal(bar.shown, true)

    -- The game's honour bar appears: the zone bar sits exactly over it and the honour bar goes see-through.
    local honour = CreateFrame("StatusBar", "HonorWatchBar", UIParent)
    honour:SetSize(570, 12)
    equal(ACB.honourBar(), honour)
    ACB.refreshZoneBar()
    equal(honour.alpha, 0)
    equal(bar.point[2], honour)
    equal(bar.shown, true)

    -- A place with no set: the honour bar is back, and returns to see-through when there is a set again.
    GetRealZoneText = function() return "Stormwind City" end
    bar.OnEvent(bar, "ZONE_CHANGED_NEW_AREA")
    equal(bar.shown, false)
    equal(honour.alpha, 1)
    GetRealZoneText = function() return "Westfall" end
    bar.OnEvent(bar, "ZONE_CHANGED_NEW_AREA")
    equal(honour.alpha, 0)

    -- Switched off, the honour bar is given back; switched on, it is taken again.
    SlashCmdList.AZEROTHCARDBINDER("bar")
    equal(bar.shown, false)
    equal(honour.alpha, 1)
    SlashCmdList.AZEROTHCARDBINDER("bar")
    equal(bar.shown, true)
    equal(honour.alpha, 0)

    -- A bar the player dragged elsewhere stays where they put it.
    saved.zoneBarSpot = { x = 5, y = 60 }
    ACB.refreshZoneBar()
    equal(bar.point[1], "BOTTOM")
    equal(bar.point[2], UIParent)

    SlashCmdList.AZEROTHCARDBINDER("bar debug")
    saved.zoneBar, saved.zoneBarSpot, GetRealZoneText = unpack(keep, 1, 3)
    _G.HonorWatchBar = nil
    ACB.refreshZoneBar()
    equal(honour.alpha, 1)
end)
