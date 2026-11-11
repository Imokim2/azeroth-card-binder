-- Reports about other players: saved until the companion app sends them, pruned when the server has taken them.

local function newestWidget(value)
    for index = #widgets, 1, -1 do
        if widgets[index].text == value then return widgets[index] end
    end
    error("missing widget: " .. value)
end

test("a report is saved with a token, a reason and a short note, and cannot be spammed", function()
    local saved = {}
    equal(ACB.addReport(saved, "bob-realmname", "cheating", "  too lucky\n ", 1000), true)
    local report = saved.reports[1]
    assert(report.token:match("^[0-9a-z]+$") and #report.token >= 6, report.token)
    equal(report.target, "bob-realmname")
    equal(report.reason, "cheating")
    equal(report.note, "too lucky")
    equal(report.at, 1000)
    -- One report about a player a day.
    local ok, why = ACB.addReport(saved, "bob-realmname", "trading", "", 1000 + 3600)
    equal(ok, false)
    assert(why:find("already reported"), why)
    equal(ACB.addReport(saved, "bob-realmname", "trading", "", 1000 + 86400), true)
    equal(#saved.reports, 2)
    -- Other refusals.
    equal(select(2, ACB.addReport(saved, nil, "cheating", "", 1)), "Target a player or give a player's name first.")
    equal(select(2, ACB.addReport(saved, "carl-realmname", "rude", "", 1)), "The reason is cheating, trading or other.")
    assert(select(2, ACB.addReport(saved, "carl-realmname", "other", ("x"):rep(121), 1)):find("120 characters"))
    -- At most twenty wait to be sent.
    local full = {}
    for index = 1, 20 do equal(ACB.addReport(full, "p" .. index .. "-realmname", "other", "", 1), true) end
    local refused, reason = ACB.addReport(full, "p21-realmname", "other", "", 1)
    equal(refused, false)
    assert(reason:find("waiting to be sent"), reason)
end)

test("saved reports are cleaned: only exactly well-formed ones survive, at most twenty", function()
    local good = { token = "abc123", target = "bob-realmname", reason = "other", note = "hi", at = 5 }
    local saved = { reports = {
        good, "x", { token = "ABC", target = "a", reason = "other", note = "", at = 1 }, { token = "abc123", target = "a", reason = "rude", note = "", at = 1 },
        { token = "abc123", target = "a", reason = "other", note = ("x"):rep(121), at = 1 }, { token = "abc123", target = "a", reason = "other", note = "a\nb", at = 1 },
        { token = "abc123", target = 5, reason = "other", note = "", at = 1 },
    }, reportedAt = { ["bob-realmname"] = 5, [7] = 1, ["carl-realmname"] = "x" } }
    ACB.cleanSavedData(saved)
    equal(#saved.reports, 1)
    equal(saved.reports[1].token, "abc123")
    equal(saved.reportedAt["bob-realmname"], 5)
    equal(saved.reportedAt["carl-realmname"], nil)
    local many = { reports = {} }
    for index = 1, 30 do many.reports[index] = { token = "tok" .. (100000 + index), target = "p-r", reason = "other", note = "", at = index } end
    ACB.cleanSavedData(many)
    equal(#many.reports, 20)
    equal(ACB.cleanSavedData({ reports = "x" }).reports[1], nil)
end)

test("reports the server has taken are dropped, and nothing else is", function()
    local saved = { reports = {
        { token = "aaaaaa", target = "a-r", reason = "other", note = "", at = 1 }, { token = "bbbbbb", target = "b-r", reason = "other", note = "", at = 2 },
        { token = "cccccc", target = "c-r", reason = "other", note = "", at = 3 },
    } }
    equal(ACB.pruneReports(saved, nil), 0)
    equal(ACB.pruneReports(saved, "x"), 0)
    equal(ACB.pruneReports(saved, { bbbbbb = false, zzzzzz = true }), 0, "only a true entry for a token we hold counts")
    equal(ACB.pruneReports(saved, { aaaaaa = true, cccccc = true }), 2)
    equal(#saved.reports, 1)
    equal(saved.reports[1].token, "bbbbbb")
end)

test("/acb report saves a report about a named player, with an optional reason and note, and explains itself", function()
    local saved = AzerothCardBinderDB
    local keep, keepAt = saved.reports, saved.reportedAt
    saved.reports, saved.reportedAt = {}, {}
    local lines, realPrint = {}, print
    print = function(text) lines[#lines + 1] = text end
    SlashCmdList.AZEROTHCARDBINDER("report")
    SlashCmdList.AZEROTHCARDBINDER("report Bob-RealmName trading never gave the card")
    SlashCmdList.AZEROTHCARDBINDER("report Carl-RealmName kept getting epics")
    SlashCmdList.AZEROTHCARDBINDER("report Bob-RealmName")
    print = realPrint
    local joined = table.concat(lines, "\n")
    assert(joined:find("Report a player:", 1, true), joined)
    equal(#saved.reports, 2)
    equal(saved.reports[1].target, "bob-realmname")
    equal(saved.reports[1].reason, "trading")
    equal(saved.reports[1].note, "never gave the card")
    equal(saved.reports[2].reason, "cheating", "no reason named: cheating, and the words are the note")
    equal(saved.reports[2].note, "kept getting epics")
    assert(joined:find("already reported that player today"), joined)
    saved.reports, saved.reportedAt = keep, keepAt
end)

test("the Report button in a player's binder window needs a second click, and then files a cheating report", function()
    local saved = { counts = {}, shiny = {}, wanted = {} }
    local clock, told = 100, {}
    ACB.initSocial(saved, function() return true end, function() return clock end, ignore, function(text) told[#told + 1] = text end)
    ACB.showInspect("bob-realmname", {}, {})
    local button = newestWidget("Report")
    button:OnClick()
    equal(saved.reports, nil, "the first click only asks")
    newestWidget("Click to confirm")
    assert(told[#told]:find("Click Report again"), told[#told])
    button:OnClick()
    equal(#saved.reports, 1)
    equal(saved.reports[1].target, "bob-realmname")
    equal(saved.reports[1].reason, "cheating")
    equal(button.text, "Report")
    assert(told[#told]:find("saved"), told[#told])
    -- Clicking again straight away asks again, and is then refused: one report a day about a player.
    button:OnClick()
    button:OnClick()
    equal(#saved.reports, 1)
    assert(told[#told]:find("already reported"), told[#told])
end)
