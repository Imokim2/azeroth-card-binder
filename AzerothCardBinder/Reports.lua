local _, ACB = ...

-- Reports about other players: a suspected cheat, a trade that went wrong. The add-on cannot reach the server, so a
-- report waits in the saved file; the companion app sends it the next time it syncs and says which ones the server took
-- (`ACB.sync.reportsDone`), and they are dropped the next time the game loads. A report is a note for a person to read.
-- It does nothing to the player by itself; the server only opens a review once several different players report one.

-- The reasons and limits live in SavedData.lua, which cleans saved reports; they are read when used, not when this file loads.
local SAME_PLAYER_GAP = 86400 -- one report about the same player a day

-- Write a report. `peer` is the other player as "name-realmname", `now` the time in seconds. Returns true, or false and why.
function ACB.addReport(saved, peer, reason, note, now)
    if type(peer) ~= "string" or peer == "" then return false, "Target a player or give a player's name first." end
    if not ACB.reportReason[reason] then return false, "The reason is cheating, trading or other." end
    note = (note or ""):gsub("%c", " "):match("^%s*(.-)%s*$")
    if #note > ACB.maxReportNote then return false, ("Keep the note to %d characters."):format(ACB.maxReportNote) end
    saved.reports, saved.reportedAt = saved.reports or {}, saved.reportedAt or {}
    if saved.reportedAt[peer] and now - saved.reportedAt[peer] < SAME_PLAYER_GAP then
        return false, "You have already reported that player today."
    end
    if #saved.reports >= ACB.maxPendingReports then return false, "You have reports waiting to be sent. Reload the interface so the companion app can send them." end
    saved.reportedAt[peer] = now
    saved.reports[#saved.reports + 1] = {
        token = ("%x%06x"):format(now, math.random(0, 16777215)), target = peer, reason = reason, note = note, at = now,
    }
    return true
end

-- Forget the reports the server has taken. `done` is `ACB.sync.reportsDone`, a set of tokens. Returns how many were dropped.
function ACB.pruneReports(saved, done)
    if type(done) ~= "table" or type(saved.reports) ~= "table" then return 0 end
    local kept, removed = {}, 0
    for _, report in ipairs(saved.reports) do
        if done[report.token] == true then removed = removed + 1 else kept[#kept + 1] = report end
    end
    saved.reports = kept
    return removed
end

-- `/acb report <player|target> [cheating|trading|other] [note]`. Says what happened in chat.
function ACB.reportCommand(saved, text, say, now)
    local who, rest = text:match("^(%S+)%s*(.*)$")
    if not who then
        say("Report a player: /acb report <player or target> [cheating, trading or other] [a short note]. A person reads it; it does nothing to the player by itself.")
        return
    end
    local peer, why
    if who:lower() == "target" then peer, why = ACB.targetPeer() else peer = ACB.tradePeer(who) end
    if not peer then
        say(why or "Use the player's name as Name-Realm, or target them first.")
        return
    end
    local reason, note = "cheating", rest
    local first, tail = rest:match("^(%a+)%s*(.*)$")
    if first and ACB.reportReason[first:lower()] then reason, note = first:lower(), tail end
    local ok, problem = ACB.addReport(saved, peer, reason, note, now)
    say(ok and ("Report about %s saved (%s). The companion app sends it the next time it syncs."):format(peer, reason) or problem)
end
