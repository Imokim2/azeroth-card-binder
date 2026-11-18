local _, ACB = ...
local cached, definitions, cachedOkay
local function whole(value, low, high) return type(value) == "number" and value == math.floor(value) and value >= low and value <= high end
local function token(value) return type(value) == "string" and #value <= 32 and value:match("^[a-z0-9][a-z0-9%-]*$") end
function ACB.bonusReference(id, first, last)
    if token(id) and whole(first, 1, 4102444800) and whole(last, first, 4102444800) then return id .. ":" .. first .. ":" .. last end
end
local function schedule()
    local data = ACB.sync and ACB.sync.bonuses
    if data == cached then return definitions or {}, cachedOkay and data or nil end
    cached, definitions, cachedOkay = data, {}, false
    if type(data) ~= "table" or type(data.events) ~= "table" or #data.events > 64 or type(data.binders) ~= "table" or #data.binders > 100 then return definitions, nil end
    local sets = {}; for _, page in ipairs(ACB.pages) do if page.code then sets[page.code] = true end end
    local ids = {}
    for _, event in ipairs(data.events) do
        local valid = type(event) == "table" and token(event.id) and not ids[event.id] and type(event.title) == "string" and #event.title > 0 and #event.title <= 60 and not event.title:find("[%z\1-\31\127|]")
            and event.effect == "card-drops" and whole(event.percent, 101, 500) and whole(event.startsAt, 1, 4102444800) and whole(event.endsAt, 1, 4102444800)
            and event.endsAt - event.startsAt >= 300 and event.endsAt - event.startsAt <= 86400 and type(event.sets) == "table" and #event.sets <= 30
        local seen = {}
        if valid then for _, code in ipairs(event.sets) do if type(code) ~= "string" or not sets[code] or seen[code] then valid = false; break end; seen[code] = true end end
        if not valid then definitions = {}; return definitions, nil end
        ids[event.id] = true; definitions[#definitions + 1] = event
    end
    cachedOkay = true; return definitions, data
end
function ACB.activeBonuses(saved, at)
    local events, data = schedule()
    if saved.mode ~= "ranked" or saved.legacy or not data or not ACB.sync.companionReady then return {} end
    local paired
    for _, id in ipairs(data.binders) do if id == saved.modeSetupID then paired = true; break end end
    if not paired then return {} end
    local active = {}
    for _, event in ipairs(events) do if at >= event.startsAt and at < event.endsAt then active[#active + 1] = event end end
    table.sort(active, function(a,b) return a.percent == b.percent and a.id < b.id or a.percent > b.percent end)
    return active
end
function ACB.bonusBoost(saved, ledger, ranked, card, at)
    if not ranked or not ledger or not saved.exactMode or ledger.ok == false or ledger:backlogFull() then return end
    local base = ACB.baseCard(card); local code = ACB.pages[base.page].code
    for _, event in ipairs(ACB.activeBonuses(saved, at)) do
        if #event.sets == 0 then return event end
        for _, set in ipairs(event.sets) do if set == code then return event end end
    end
end
function ACB.bonusTime(seconds)
    seconds = math.max(0, math.ceil(seconds))
    if seconds >= 3600 then return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    return ("%02d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end
function ACB.bonusScope(event)
    if #event.sets == 0 then return "All card collections" end
    local names = {}
    for _, code in ipairs(event.sets) do for _, page in ipairs(ACB.pages) do if page.code == code then names[#names + 1] = page.name; break end end end
    return table.concat(names, ", ")
end
local badges = setmetatable({}, { __mode = "k" })
local function paint(badge, saved, now)
    local active = ACB.activeBonuses(saved, now)
    badge.active = active; badge:SetShown(#active > 0)
    if active[1] then
        badge.name:SetText(active[1].title)
        badge.clock:SetText(("%gx card drops / %s%s"):format(active[1].percent / 100, ACB.bonusTime(active[1].endsAt - now), #active > 1 and (" / +" .. (#active - 1)) or ""))
    end
end
function ACB.createBonusBadge(parent, saved)
    local badge = CreateFrame("Button", nil, parent)
    badge:SetPoint("TOPLEFT", 526, -22); badge:SetSize(194, 34)
    badge.name = ACB.uiKit.label(badge, "GameFontHighlightSmall", 0, 0, ACB.uiKit.brass, "")
    badge.name:SetWidth(194); badge.name:SetHeight(14)
    badge.name:SetWordWrap(false)
    badge.clock = ACB.uiKit.label(badge, "GameFontHighlightSmall", 0, 17, ACB.uiKit.parchment, "")
    badge.clock:SetWidth(194); badge.clock:SetHeight(14)
    badge.clock:SetWordWrap(false)
    badge:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        for _, event in ipairs(self.active or {}) do
            GameTooltip:AddLine(event.title, 1, .82, .35)
            GameTooltip:AddLine(("%gx card drops — %s left"):format(event.percent / 100, ACB.bonusTime(event.endsAt - time())), .95, .89, .75, true)
            GameTooltip:AddLine(ACB.bonusScope(event), .8, .75, .63, true)
        end
        GameTooltip:AddLine("The strongest eligible event applies to each card. Campfire bonuses also apply. Pack contents are unchanged.", .7, .7, .7, true)
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    badges[badge] = saved; paint(badge, saved, time()); parent.bonusBadge = badge
    return badge
end
function ACB.initBonusEvents(saved, ledger)
    if ACB.bonusWatcher then return end
    local watcher, elapsed, previous = CreateFrame("Frame"), 0, {}
    ACB.bonusWatcher = watcher
    saved.bonusNotices = type(saved.bonusNotices) == "table" and saved.bonusNotices or {}
    local function report(text) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("World of Warcards: " .. text, 1, .82, .35) end end
    local function update()
        local now, current = time(), {}
        for id, at in pairs(saved.bonusNotices) do if not token(id) or not whole(at, 1, 4102444800) or at < now - 7 * 86400 then saved.bonusNotices[id] = nil end end
        for _, event in ipairs(ACB.activeBonuses(saved, now)) do
            current[event.id] = event
            if not saved.bonusNotices[event.id] then
                saved.bonusNotices[event.id] = event.endsAt
                report(("%s is active! %gx card drops in %s for %s."):format(event.title, event.percent / 100, ACB.bonusScope(event), ACB.bonusTime(event.endsAt - now)))
                if ACB.settingOn(saved, "sounds") and ACB.settingOn(saved, "eventSounds") then ACB.playSound("rare", "events") end
            end
        end
        for id, event in pairs(previous) do if not current[id] then
            if ledger then ledger:flushRun() end
            report(event.title .. (now >= event.endsAt and " has ended." or " is no longer active for this binder."))
        end end
        previous = current
        for badge, owner in pairs(badges) do paint(badge, owner, now) end
    end
    watcher:SetScript("OnUpdate", function(_, dt) elapsed = elapsed + dt; if elapsed >= 1 then elapsed = 0; update() end end)
    watcher.update = update; update()
end
