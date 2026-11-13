local _, ACB = ...

ACB.seasonKnownTitles = {}
function ACB.cleanSeasonData(saved)
    saved.seasonClaims = type(saved.seasonClaims) == "table" and saved.seasonClaims or {}
    saved.seasonTitles = type(saved.seasonTitles) == "table" and saved.seasonTitles or {}
    for id, value in pairs(saved.seasonClaims) do
        if type(id) ~= "string" or #id ~= 32 or id:find("[^0-9a-f]") or value ~= true then saved.seasonClaims[id] = nil end
    end
    for title, value in pairs(saved.seasonTitles) do
        if type(title) ~= "string" or #title > 80 or title:find("[|%c]") or value ~= true then saved.seasonTitles[title] = nil
        else ACB.seasonKnownTitles[title] = true end
    end
end

function ACB.seasonTitleKnown(title)
    if ACB.seasonKnownTitles[title] then return true end
    for _, known in ipairs(ACB.sync and ACB.sync.seasonal and ACB.sync.seasonal.knownTitles or {}) do if known == title then return true end end
    for _, season in ipairs(ACB.sync and ACB.sync.seasonal and ACB.sync.seasonal.seasons or {}) do
        for _, reward in pairs(season.rewards or {}) do if reward.title == title and title ~= "" then return true end end
    end
    return false
end

function ACB.seasonData(saved)
    local data = ACB.sync and ACB.sync.seasonal
    if type(data) ~= "table" then return end
    for _, id in ipairs(data.binders or {}) do if id == saved.modeSetupID then return data end end
end

function ACB.seasonProgress(saved, season)
    local have, pending, amount = {}, {}, 0
    for _, key in ipairs(season.collected or {}) do have[key] = true end
    if saved.mode == "ranked" and (saved.casualDrops or 0) == 0 then
        for _, event in ipairs(saved.ledger or {}) do
            if event.t >= season.startsAt and event.t < season.endsAt and
                (((event.kind == "drop" or event.kind == "packCard") and event.tape > 0) or event.kind == "tradeIn") then
                if not have[event.key] then pending[event.key] = true end
            end
        end
    end
    for _, key in ipairs(season.cards) do if have[key] then amount = amount + 1 end end
    return have, pending, amount
end

function ACB.seasonRewardTitles(saved)
    local data = ACB.seasonData(saved)
    if not data then return end
    ACB.cleanSeasonData(saved)
    for _, title in ipairs(data.titles or {}) do
        saved.seasonTitles[title], saved.titles[title], ACB.seasonKnownTitles[title] = true, true, true
    end
    for _, season in ipairs(data.seasons or {}) do
        for _, title in ipairs(season.titles or {}) do
            saved.seasonTitles[title], saved.titles[title], ACB.seasonKnownTitles[title] = true, true, true
        end
    end
end

function ACB.seasonRewardsReady(saved)
    local count, data = 0, ACB.seasonData(saved)
    for _, grant in ipairs(data and data.grants or {}) do if not (saved.seasonClaims or {})[grant.id] then count = count + 1 end end
    return count
end

-- A reward is an ordinary pack in the satchel. Its grant id is recorded once in the normal ledger;
-- the server accepts only grants issued to this account and redeems them in the upload transaction.
function ACB.claimSeasonRewards(saved, ledger)
    local data = ACB.seasonData(saved)
    if not data or not ledger or not ledger:check() or ledger:backlogFull() then return 0 end
    ledger:flushRun()
    if ledger:backlogFull() then return 0 end
    ACB.cleanSeasonData(saved)
    local count = 0
    for _, grant in ipairs(data.grants or {}) do
        if not saved.seasonClaims[grant.id] and ACB.packInfo(grant.pack) and not ledger:backlogFull() then
            saved.packs[grant.pack] = (saved.packs[grant.pack] or 0) + 1
            ledger:record("seasonReward", grant.pack, { count = saved.packs[grant.pack], trade = grant.id })
            saved.seasonClaims[grant.id], count = true, count + 1
        end
    end
    ACB.seasonRewardTitles(saved)
    if count > 0 and ACB.refreshSatchel then ACB.refreshSatchel() end
    return count
end
