-- The Ladder tab: the standings the companion app writes into Data/Sync.lua.

local function widgetWithText(value)
    for _, widget in ipairs(widgets) do
        if widget.text == value then return widget end
    end
    error("missing widget: " .. value)
end

test("the ladder says where you stand, lists the top, who was first, and marks verified players", function()
    local saved = AzerothCardBinderDB
    local keep, mode = ACB.sync, saved.mode
    saved.mode = "casual"
    ACB.sync = { syncVersion = 1, acks = {} }
    assert(ACB.ladderStatus(saved):find("Switch to Ranked"))
    equal(#ACB.ladderRows(), 0)
    equal(#ACB.firstsLines(), 0)
    saved.mode = "ranked"
    assert(ACB.ladderStatus(saved):find("No standings yet"))

    ACB.sync = {
        syncVersion = 1, acks = {}, syncedAt = 1700000000,
        leaderboard = {
            { rank = 1, name = "Alice-RealmName", score = 1234, cards = 40, sets = 2 },
            { rank = 2, name = "Bob-RealmName", score = 125, cards = 12, sets = 0 },
            "not a row", { rank = "x", name = "Broken" }, { rank = 3, name = 7 },
        },
        you = { rank = 2, score = 125, cards = 12, sets = 0 },
        verified = { ["alice-realmname"] = true, ["bob-realmname"] = true },
        firsts = { { set = "DM", title = "Deadmines", by = "Alice-RealmName", at = 1700000000 }, { title = 5, by = "x" } },
    }
    equal(#ACB.ladderRows(), 2) -- the malformed rows are left out
    equal(ACB.pointsText(1234), "123.4")
    equal(ACB.pointsText(125), "12.5")
    equal(ACB.pointsText(nil), "0")
    equal(ACB.ladderStatus(saved), "You are number 2 with 12.5 points (12 cards, 0 sets).")
    equal(table.concat(ACB.firstsLines(), "|"), "Deadmines: Alice-RealmName")
    equal(ACB.isVerified("alice-realmname"), true)
    equal(ACB.isVerified("carol-realmname"), false)
    equal(ACB.isVerified(nil), false)

    -- The tab shows all of it.
    ACB.open("ladder")
    widgetWithText("You are number 2 with 12.5 points (12 cards, 0 sets).")
    widgetWithText("Alice-RealmName")
    widgetWithText("Bob-RealmName")
    widgetWithText("123.4")
    widgetWithText("Deadmines: Alice-RealmName")
    equal(widgetWithText("Alice-RealmName").shown, true)
    -- Another player's binder says when the server has checked them.
    ACB.showInspect("bob-realmname", {}, {})
    widgetWithText("bob-realmname's binder (verified)")
    ACB.showInspect("carol-realmname", {}, {})
    widgetWithText("carol-realmname's binder")
    ACB.open("collection")
    ACB.sync, saved.mode = keep, mode
end)
