local addonName, ACB = ...

-- Whether this add-on is out of date. The companion app writes the newest version and the oldest one the server accepts
-- into Data/Sync.lua (from the server); the add-on only says so, once, a few seconds after you log in, and on /acb version.
-- The version it runs as is also written into the saved data, so the companion app can tell when a newer one is installed
-- but the game has not loaded it yet. Nothing is paused or blocked because of an old version.

local function parts(text)
    local major, minor, patch = tostring(text):match("^(%d+)%.(%d+)%.(%d+)$")
    if major then return tonumber(major), tonumber(minor), tonumber(patch) end
end

-- -1, 0 or 1 for x.y.z compared with x.y.z; nil when either is not a version.
function ACB.compareVersions(a, b)
    local x, y = { parts(a) }, { parts(b) }
    if #x ~= 3 or #y ~= 3 then return end
    for index = 1, 3 do
        if x[index] ~= y[index] then return x[index] < y[index] and -1 or 1 end
    end
    return 0
end

-- The version in this add-on's .toc, or nil.
function ACB.addonVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(get) ~= "function" then return end
    local ok, value = pcall(get, addonName, "Version")
    if ok and type(value) == "string" and parts(value) then return value end
end

-- Is this add-on older than the oldest version the server accepts (as the companion app last wrote it into Data/Sync.lua)?
-- Ranked rolling pauses then (Tape.lua); Casual is never affected. With no word from the app, or no version of its own,
-- nothing is ever paused, so a missing file cannot lock anyone out.
function ACB.addonTooOld()
    local releases = ACB.sync and ACB.sync.releases
    if type(releases) ~= "table" then return false end
    return ACB.compareVersions(ACB.addonVersion() or "", releases.minAddon) == -1
end

-- What to tell the player, or nil: `mine` is this add-on's version, `sync` the companion app's file (ACB.sync).
function ACB.updateNotice(mine, sync)
    local releases = type(sync) == "table" and sync.releases
    if not mine or type(releases) ~= "table" then return end
    if ACB.compareVersions(mine, releases.minAddon) == -1 then
        return ("Add-on %s is too old (the oldest accepted is %s). Get %s from the Download page, then type /reload."):format(
            mine, tostring(releases.minAddon), tostring(releases.latestAddon))
    end
    if ACB.compareVersions(mine, releases.latestAddon) == -1 then
        return ("Add-on %s is available (you have %s). Get it from the Download page, then type /reload."):format(
            tostring(releases.latestAddon), mine)
    end
end

-- Said once per session, a few seconds after the first login, so it does not bury the game's own messages.
local announced = false
function ACB.announceUpdates(report)
    if announced then return end
    announced = true
    local function say()
        local notice = ACB.updateNotice(ACB.addonVersion(), ACB.sync)
        if notice then report(notice) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(6, say) else say() end
end

-- /acb version
function ACB.reportVersion(report)
    local mine, releases = ACB.addonVersion(), ACB.sync and ACB.sync.releases
    report(("Add-on %s."):format(mine or "version unknown"))
    if type(releases) ~= "table" then
        report("The companion app has not said what the newest version is. Run it, then type /reload.")
        return
    end
    report(("Newest: %s. Oldest accepted: %s."):format(tostring(releases.latestAddon), tostring(releases.minAddon)))
    report(ACB.updateNotice(mine, ACB.sync) or "This add-on is up to date.")
end
