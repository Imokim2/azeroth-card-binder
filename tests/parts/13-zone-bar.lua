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
            if widget.text and widget.text:find("^Westfall ") then return widget.text end
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
    equal(label(), ("Westfall %d / %d"):format(owned, total))

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

test("the bar takes the reputation bar's place, gives it back when it is off or has nothing to show, and works without one", function()
    local saved = AzerothCardBinderDB
    local bar = AzerothCardBinderZoneBar
    local keep = { saved.zoneBar, saved.zoneBarSpot, GetRealZoneText }
    saved.zoneBar, saved.zoneBarSpot = nil, nil
    GetRealZoneText = function() return "Westfall" end

    -- No bar to replace: the bar sits above the experience bar.
    ACB.refreshZoneBar()
    equal(ACB.replacedBar(), nil)
    equal(bar.shown, true)

    -- The game's reputation bar appears: the zone bar sits exactly over it and the reputation bar goes see-through.
    local reputation = CreateFrame("StatusBar", "ReputationWatchBar", UIParent)
    reputation:SetSize(570, 12)
    equal(ACB.replacedBar(), reputation)
    ACB.refreshZoneBar()
    equal(reputation.alpha, 0)
    equal(bar.point[2], reputation)
    equal(bar.shown, true)

    -- A place with no set: the reputation bar is back, and returns to see-through when there is a set again.
    GetRealZoneText = function() return "Stormwind City" end
    bar.OnEvent(bar, "ZONE_CHANGED_NEW_AREA")
    equal(bar.shown, false)
    equal(reputation.alpha, 1)
    GetRealZoneText = function() return "Westfall" end
    bar.OnEvent(bar, "ZONE_CHANGED_NEW_AREA")
    equal(reputation.alpha, 0)

    -- Switched off, the reputation bar is given back; switched on, it is taken again.
    SlashCmdList.AZEROTHCARDBINDER("bar")
    equal(bar.shown, false)
    equal(reputation.alpha, 1)
    SlashCmdList.AZEROTHCARDBINDER("bar")
    equal(bar.shown, true)
    equal(reputation.alpha, 0)

    -- A bar the player dragged elsewhere stays where they put it.
    saved.zoneBarSpot = { x = 5, y = 60 }
    ACB.refreshZoneBar()
    equal(bar.point[1], "BOTTOM")
    equal(bar.point[2], UIParent)
    saved.zoneBarSpot = nil
    SlashCmdList.AZEROTHCARDBINDER("bar debug")

    -- With no bar by that name, the upper of two stacked tracking containers is the one: the lower is the experience bar.
    _G.ReputationWatchBar = nil
    ACB.refreshZoneBar()
    equal(reputation.alpha, 1)
    local main = CreateFrame("Frame", "MainStatusTrackingBarContainer", UIParent)
    main:SetSize(570, 14)
    main.top = 40
    equal(ACB.replacedBar(), nil) -- a single bar is the experience bar: nothing to replace
    local second = CreateFrame("Frame", "SecondaryStatusTrackingBarContainer", UIParent)
    second:SetSize(570, 14)
    second.top = 56
    equal(ACB.replacedBar(), second)
    ACB.refreshZoneBar()
    equal(second.alpha, 0)
    equal(main.alpha, nil)
    equal(bar.point[2], second)
    second.top, main.top = 40, 56 -- the other way up
    equal(ACB.replacedBar(), main)
    main.shown = false -- a hidden container is not a bar in use
    equal(ACB.replacedBar(), nil)

    saved.zoneBar, saved.zoneBarSpot, GetRealZoneText = unpack(keep, 1, 3)
    _G.MainStatusTrackingBarContainer, _G.SecondaryStatusTrackingBarContainer = nil, nil
    ACB.refreshZoneBar()
    equal(second.alpha, 1)
end)

test("the zone bar ignores hidden or collapsed trackers and recovers when the layout changes", function()
    local saved, bar = AzerothCardBinderDB, AzerothCardBinderZoneBar
    local keep = { saved.zoneBar, saved.zoneBarSpot, GetRealZoneText, _G.StatusTrackingBarManager, _G.MainMenuExpBar }
    saved.zoneBar, saved.zoneBarSpot = true, nil
    GetRealZoneText = function() return "Westfall" end
    local manager = CreateFrame("Frame", nil, UIParent)
    manager:SetSize(570, 0)
    local experience = CreateFrame("Frame", nil, UIParent)
    experience:SetSize(570, 12)
    experience:Hide()
    _G.StatusTrackingBarManager, _G.MainMenuExpBar = manager, experience
    ACB.refreshZoneBar()
    equal(bar.point[2], UIParent, "invisible tracking bars cannot swallow the card bar")
    equal(bar.point[5], 118)
    experience:Show()
    ACB.refreshZoneBar()
    equal(bar.point[2], experience, "a visible experience bar becomes the anchor")
    saved.zoneBarSpot = { x = 50000, y = -50000 }
    ACB.refreshZoneBar()
    assert(bar.point[4] <= UIParent:GetWidth() / 2 and bar.point[5] >= 8)
    saved.zoneBar = false
    SlashCmdList.AZEROTHCARDBINDER("bar reset")
    equal(saved.zoneBar, true, "reset also enables a previously disabled bar")
    equal(saved.zoneBarSpot, nil)
    saved.zoneBar, saved.zoneBarSpot, GetRealZoneText, _G.StatusTrackingBarManager, _G.MainMenuExpBar = unpack(keep, 1, 5)
    ACB.refreshZoneBar()
end)
