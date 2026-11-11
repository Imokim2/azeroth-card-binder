-- The Ladder tab: the standings the companion app writes into Data/Sync.lua.

local function widgetWithText(value)
    for _, widget in ipairs(widgets) do
        if widget.text == value then return widget end
    end
    error("missing widget: " .. value)
end

test("the ladder says where you stand, lists the top, who was first, and marks verified players", function()
    local saved = AzerothCardBinderDB
    local keep, mode, casual, legacy = ACB.sync, saved.mode, saved.casualDrops, saved.legacy
    saved.mode, saved.casualDrops, saved.legacy = "casual", 0, nil
    ACB.sync = { syncVersion = 1, acks = {} }
    assert(ACB.ladderStatus(saved):find("Switch to Ranked in Settings before your next drop"))
    -- Only Ranked counts: a binder with Casual drops, or from before the ledger, is told it cannot join.
    saved.casualDrops = 1
    assert(ACB.ladderStatus(saved):find("has 1 Casual drop, which cannot be checked"), ACB.ladderStatus(saved))
    saved.casualDrops = 3
    assert(ACB.ladderStatus(saved):find("has 3 Casual drops"))
    saved.casualDrops, saved.legacy = 0, true
    assert(ACB.ladderStatus(saved):find("from before the ledger"))
    saved.legacy = nil
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
    ACB.sync, saved.mode, saved.casualDrops, saved.legacy = keep, mode, casual, legacy
end)

test("only a drop rolled in Casual counts against the ladder: the add-on keeps the count, and Ranked drops do not add to it", function()
    local saved = { counts = {}, achievements = {} }
    ACB.cleanSavedData(saved)
    equal(saved.casualDrops, 0)
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore)
    equal(collection:roll(guid(589, "casual-1"), "loot"), true)
    equal(saved.casualDrops, 1)
    equal(collection:roll(guid(589, "casual-2"), "loot"), true)
    equal(saved.casualDrops, 2)
    -- A miss is not a drop.
    local misser = ACB.newCollection(saved, function() return 10000 end, ignore, ignore)
    equal(misser:roll(guid(590, "miss"), "loot"), false)
    equal(saved.casualDrops, 2)
    -- Ranked drops from the server's tape never add to it.
    local ranked, _, rankedCollection = rankedBinder({ "0000000000000001", "0000000000000001" })
    equal(rankedCollection:roll(guid(589, "r1"), "loot"), true)
    equal(rankedCollection:roll(guid(589, "r2"), "loot"), true)
    equal(ranked.casualDrops, 0)
    -- A damaged value is put right when the data is loaded.
    for _, bad in ipairs({ -1, 1.5, "many", true }) do
        local damaged = { counts = {}, achievements = {}, casualDrops = bad }
        ACB.cleanSavedData(damaged)
        equal(damaged.casualDrops, 0)
    end
end)

test("/acb newbinder asks first, then erases the binder, keeps a copy and reloads into an empty one", function()
    local saved = AzerothCardBinderDB
    local keep = {}
    for key, value in pairs(saved) do keep[key] = value end
    local oldSync, reloads = ACB.sync, 0
    local oldReload = ReloadUI
    ReloadUI = function() reloads = reloads + 1 end
    ACB.sync = { syncVersion = 1, acks = {}, tape = { start = 1, entries = { "0000000000000001" } } }
    saved.counts = { ["npc:589"] = 2, ["npc:639"] = 1 }
    saved.dust = 7
    local printed = {}
    local oldPrint = print
    print = function(message) printed[#printed + 1] = message end

    -- Without "confirm" it only explains, and nothing is erased.
    SlashCmdList.AZEROTHCARDBINDER("newbinder")
    equal(reloads, 0)
    equal(saved.counts["npc:589"], 2)
    assert(#printed >= 1)

    -- With it, the binder is wiped except for a copy, the stale tape is dropped and the interface reloads.
    SlashCmdList.AZEROTHCARDBINDER("newbinder confirm")
    equal(reloads, 1)
    equal(next(saved.counts), nil)
    equal(#saved.ledger, 0)
    equal(saved.lastBinder.counts["npc:589"], 2)
    equal(saved.lastBinder.dust, 7)
    equal(ACB.sync.tape, nil)

    -- What is there now, and loads next, is an empty, valid binder that is not marked as holding old, unchecked cards.
    equal(saved.casualDrops, 0)
    equal(saved.legacy, nil)
    ACB.cleanSavedData(saved)
    equal(next(saved.counts), nil)
    equal(saved.lastBinder.counts["npc:639"], 1, "the copy survives the clean-up")

    -- Put the shared test binder back as it was.
    for key in pairs(saved) do saved[key] = nil end
    for key, value in pairs(keep) do saved[key] = value end
    print, ReloadUI, ACB.sync = oldPrint, oldReload, oldSync
end)
