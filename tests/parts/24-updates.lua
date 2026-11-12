-- Whether the add-on is out of date: the versions come from the companion app's file, and the add-on only says so.

local function said(action)
    local lines, realPrint = {}, print
    print = function(text) lines[#lines + 1] = text end
    action()
    print = realPrint
    return table.concat(lines, "\n")
end

test("versions compare as numbers, and anything that is not x.y.z is not a version", function()
    equal(ACB.compareVersions("0.4.0", "0.4.0"), 0)
    equal(ACB.compareVersions("0.4.0", "0.10.0"), -1)
    equal(ACB.compareVersions("1.0.0", "0.99.99"), 1)
    equal(ACB.compareVersions("0.4", "0.4.0"), nil)
    equal(ACB.compareVersions("0.4.0", nil), nil)
    equal(ACB.compareVersions("0.4.0-beta", "0.4.0"), nil)
end)

test("the add-on reads its own version from the game, and keeps nothing it cannot read as x.y.z", function()
    local keep = GetAddOnMetadata
    GetAddOnMetadata = function(name, field) return name == addon and field == "Version" and "0.4.2" or nil end
    equal(ACB.addonVersion(), "0.4.2")
    GetAddOnMetadata = function() return "<script>" end
    equal(ACB.addonVersion(), nil)
    GetAddOnMetadata = nil
    equal(ACB.addonVersion(), nil)
    GetAddOnMetadata = keep
end)

test("the notice says when an add-on is out of date, and says nothing when it is current or the app has not said", function()
    local current = { releases = { latestAddon = "0.4.2", minAddon = "0.4.0" } }
    equal(ACB.updateNotice("0.4.2", current), nil)
    equal(ACB.updateNotice("0.5.0", current), nil)
    assert(ACB.updateNotice("0.4.1", current):find("0.4.2 is available (you have 0.4.1)", 1, true), "an update is available")
    local old = ACB.updateNotice("0.3.9", current)
    assert(old:find("too old", 1, true) and old:find("oldest accepted is 0.4.0", 1, true), old)
    -- No file from the app, or no version of its own: nothing to say.
    equal(ACB.updateNotice("0.4.1", { syncVersion = 1 }), nil)
    equal(ACB.updateNotice("0.4.1", nil), nil)
    equal(ACB.updateNotice(nil, current), nil)
end)

test("/acb version says what is installed and what is newest", function()
    local keepSync, keep = ACB.sync, GetAddOnMetadata
    GetAddOnMetadata = function() return "0.4.1" end
    ACB.sync = {}
    local text = said(function() SlashCmdList.AZEROTHCARDBINDER("version") end)
    assert(text:find("Add-on 0.4.1.", 1, true) and text:find("has not said what the newest version is", 1, true), text)
    ACB.sync = { releases = { latestAddon = "0.4.2", minAddon = "0.4.0" } }
    text = said(function() SlashCmdList.AZEROTHCARDBINDER("version") end)
    assert(text:find("Newest: 0.4.2. Oldest accepted: 0.4.0.", 1, true) and text:find("is available", 1, true), text)
    GetAddOnMetadata = function() return "0.4.2" end
    text = said(function() SlashCmdList.AZEROTHCARDBINDER("version") end)
    assert(text:find("up to date", 1, true), text)
    ACB.sync, GetAddOnMetadata = keepSync, keep
end)

test("an add-on older than the server accepts rolls no Ranked cards, and says why; Casual is not affected", function()
    local saved = AzerothCardBinderDB
    local keep = { ACB.sync, GetAddOnMetadata, saved.mode, saved.tape }
    local entries = {}
    for index = 1, 40 do entries[index] = ("%016x"):format(index * 977) end
    ACB.sync = { tape = { start = 1, entries = entries }, releases = { latestAddon = "0.5.0", minAddon = "0.4.0" } }
    saved.tape = { next = 1 }
    -- Up to date: the tape is there to use.
    GetAddOnMetadata = function() return "0.4.0" end
    equal(ACB.addonTooOld(), false)
    equal(ACB.tapeLeft(saved), 40)
    assert(ACB.takeTape(saved), "an entry is handed out")
    equal(saved.tape.next, 2)
    -- Too old: nothing is handed out, nothing is used up, and the tape looks empty.
    GetAddOnMetadata = function() return "0.3.9" end
    equal(ACB.addonTooOld(), true)
    equal(ACB.takeTape(saved), nil)
    equal(saved.tape.next, 2, "no entry was used up")
    equal(ACB.tapeHolds(saved, 5), false)
    equal(ACB.tapeLeft(saved), 0)
    -- A version that is not known, or a file with no versions in it, never pauses anything.
    GetAddOnMetadata = nil
    equal(ACB.addonTooOld(), false)
    GetAddOnMetadata = function() return "0.3.9" end
    ACB.sync = { tape = { start = 1, entries = entries } }
    equal(ACB.addonTooOld(), false)
    ACB.sync, GetAddOnMetadata, saved.mode, saved.tape = keep[1], keep[2], keep[3], keep[4]
end)

test("a Ranked attempt on an old add-on is held back with its own message, and Casual still rolls", function()
    local saved = AzerothCardBinderDB
    local keep = { ACB.sync, GetAddOnMetadata, saved.mode, saved.tape }
    local entries = {}
    for index = 1, 40 do entries[index] = ("%016x"):format(index * 977) end
    ACB.sync = { tape = { start = 1, entries = entries }, releases = { latestAddon = "0.5.0", minAddon = "0.4.0" } }
    GetAddOnMetadata = function() return "0.3.9" end
    saved.tape = { next = 1 }
    local text = said(function()
        local collection = ACB.newCollection({ counts = {}, achievements = {}, mode = "ranked", tape = { next = 1 }, misses = {} },
            function() return 1 end, print, function() end)
        collection:roll("Creature-0-1-0-0-589-OLDADDON01", "loot")
    end)
    assert(text:find("older than the server accepts", 1, true), text)
    ACB.sync, GetAddOnMetadata, saved.mode, saved.tape = keep[1], keep[2], keep[3], keep[4]
end)
