local _, ACB = ...

-- A thin bar that shows how many cards of the place you are in are in your binder. It follows you: walking into a
-- new zone, or through a dungeon door, changes the place, and finding a card moves the bar.
-- It takes the reputation bar's place, the green bar stacked above the experience bar: while it shows, that bar is
-- made invisible (its transparency only, so the game's own bar logic is never touched) and this one, in the same
-- green, sits exactly where it was. With the bar switched off, or in a place with no set, the reputation bar is back.
-- With no bar to replace it sits above the experience bar. Shift-drag moves it somewhere else.

-- Names the game uses that differ from the set's title (the sets use the plain name; both sides lose a leading "The").
local aliases = {
    stockade = "stormwind-stockade",
    ["templeofatalhakkar"] = "sunken-temple",
    ["templeofahnqiraj"] = "ahnqiraj-temple",
    upperblackrockspire = "blackrock-spire", lowerblackrockspire = "blackrock-spire",
    ["blackrockspire"] = "blackrock-spire",
    ["diremaulnorth"] = "dire-maul", ["diremaulwest"] = "dire-maul", ["diremauleast"] = "dire-maul",
    ["scarletmonasterygraveyard"] = "scarlet-monastery", ["scarletmonasterylibrary"] = "scarlet-monastery",
    ["scarletmonasteryarmory"] = "scarlet-monastery", ["scarletmonasterycathedral"] = "scarlet-monastery",
}

-- "The Barrens", "the barrens" and "Barrens" are one name; so are names with and without punctuation.
local function simple(name)
    return (name:lower():gsub("^the%s+", ""):gsub("[^%w]", ""))
end

-- The set for a place name from the game, or nothing when no set covers it (a city, say).
function ACB.pageForName(name)
    name = ACB.read(name, "string")
    if not name or name == "" then return end
    local key = simple(name)
    local slug = aliases[key]
    for index, page in ipairs(ACB.pages) do
        if page.group ~= "Profession" and (slug and page.zone == slug or simple(page.title) == key) then return index end
    end
end

-- The name of the zone, or of the dungeon, raid or battleground, the player is in now.
function ACB.currentPlaceName()
    if ACB.read(ACB.safe(IsInInstance), "boolean") and GetInstanceInfo then
        local name = ACB.read(ACB.safe(GetInstanceInfo), "string")
        if name and name ~= "" then return name end
    end
    local zone = GetRealZoneText and ACB.read(ACB.safe(GetRealZoneText), "string")
    if not zone or zone == "" then zone = GetZoneText and ACB.read(ACB.safe(GetZoneText), "string") end
    return zone
end

-- What the bar shows for the place: the set's index, the cards owned and the cards in it, or nothing.
function ACB.zoneProgress(saved, name)
    local index = ACB.pageForName(name or ACB.currentPlaceName())
    if not index then return end
    local owned, total = ACB.progress(saved.counts, index)
    if total == 0 then return end
    return index, owned, total
end

-- The green of the reputation bar.
local BAR_FILL = { 0.10, 0.62, 0.12 }
local TRACKING_FRAMES = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "MainMenuExpBar", "MainMenuBar" }
-- The names the game's reputation bar goes by in its different interface versions, and the two stacked containers
-- that hold the tracking bars in the newer one.
local REPUTATION_FRAMES = { "ReputationWatchBar", "ReputationStatusBar", "StatusTrackingBarManagerReputationBar" }
local CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }

local function sized(frame)
    if not frame or not frame.GetWidth or not frame.GetHeight or not frame.SetAlpha then return false end
    local wide = ACB.read(ACB.safe(frame.GetWidth, frame), "number")
    local tall = ACB.read(ACB.safe(frame.GetHeight, frame), "number")
    local visible = frame.IsVisible or frame.IsShown
    local shown = not visible or ACB.read(ACB.safe(visible, frame), "boolean") ~= false
    local top = ACB.read(ACB.safe(frame.GetTop, frame), "number")
    local bottom = ACB.read(ACB.safe(frame.GetBottom, frame), "number")
    local screenHeight = UIParent:GetHeight()
    return shown and wide ~= nil and tall ~= nil and wide > 100 and tall > 2
        and (not top or top > 0) and (not bottom or bottom < screenHeight)
end

-- The kinds of tracking bar the manager knows, whichever table the interface keeps them in.
local function barKinds()
    local info = _G.StatusTrackingBarInfo
    return info and info.BarsEnum or (Enum and Enum.StatusBarType)
end

-- The bar this one stands in for: the reputation bar, the one stacked above the experience bar. Found by name, then
-- by kind among the tracking-bar manager's bars, then as the upper of the two tracking containers when both are in
-- use. Nothing when only one bar is showing (there is no reputation bar to replace, and the experience bar stays).
function ACB.replacedBar()
    for _, name in ipairs(REPUTATION_FRAMES) do
        if sized(_G[name]) then return _G[name], name end
    end
    local manager, kinds = _G.StatusTrackingBarManager, barKinds()
    if type(manager) == "table" and type(manager.bars) == "table" and kinds and kinds.Reputation then
        for _, found in pairs(manager.bars) do
            if sized(found) and ACB.read(found.barIndex, "number") == kinds.Reputation then return found, "a tracking bar" end
        end
    end
    local upper, upperName, count = nil, nil, 0
    for _, name in ipairs(CONTAINERS) do
        local container = _G[name]
        if sized(container) then
            count = count + 1
            local top = ACB.read(container:GetTop(), "number") or 0
            if not upper or top > (ACB.read(upper:GetTop(), "number") or 0) then upper, upperName = container, name end
        end
    end
    if count >= 2 then return upper, upperName end
end

function ACB.initZoneBar(saved)
    if not UIParent then return end
    local bar = CreateFrame("StatusBar", "AzerothCardBinderZoneBar", UIParent, "BackdropTemplate")
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bar:SetBackdropColor(0.03, 0.03, 0.04, 0.85)
    bar:SetBackdropBorderColor(0, 0, 0, 1)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")

    -- Sit over the reputation bar, or above the experience bar. A position the player has dragged to is kept instead.
    local function place(slot)
        bar:ClearAllPoints()
        local spot = saved.zoneBarSpot
        if type(spot) == "table" and type(spot.x) == "number" and type(spot.y) == "number" then
            local limit = math.max(0, (UIParent:GetWidth() - bar:GetWidth()) / 2)
            bar:SetPoint("BOTTOM", UIParent, "BOTTOM", math.max(-limit, math.min(limit, spot.x)),
                math.max(8, math.min(UIParent:GetHeight() - 24, spot.y)))
            return
        end
        -- Exactly over the reputation bar's place.
        if slot then
            bar:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
            bar:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
            return
        end
        for _, name in ipairs(TRACKING_FRAMES) do
            local anchor = _G[name]
            if sized(anchor) then
                local width = ACB.read(ACB.safe(anchor.GetWidth, anchor), "number")
                bar:SetWidth(math.min(width, 570))
                bar:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
                return
            end
        end
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 118)
    end
    bar:SetSize(400, 12)
    bar:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = ACB.read(self:GetCenter(), "number"), ACB.read(self:GetBottom(), "number")
        local midline = UIParent:GetWidth() / 2
        if x and y then saved.zoneBarSpot = { x = math.floor(x - midline + 0.5), y = math.floor(y + 0.5) } end
        place()
    end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and not IsShiftKeyDown() and ACB.toggle then ACB.toggle() end
    end)
    bar:SetScript("OnEnter", function(self)
        local index, owned, total = ACB.zoneProgress(saved)
        if not index or not GameTooltip then return end
        local page = ACB.pages[index]
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(page.title, 1, 0.82, 0)
        GameTooltip:AddLine(("%d of %d cards collected (%d%%)"):format(owned, total, math.floor(owned * 100 / total)), 1, 1, 1)
        local bossOwned, bossTotal = ACB.progress(saved.counts, index, true)
        if bossTotal > 0 then GameTooltip:AddLine(("Bosses: %d of %d"):format(bossOwned, bossTotal), 0.9, 0.85, 0.72) end
        GameTooltip:AddLine("Click to open the binder. Shift-drag to move.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- The bar being replaced is only made see-through while this bar is up, and given back otherwise.
    local taken
    local function takeSlot(slot)
        if taken and taken ~= slot then taken:SetAlpha(1) end
        taken = slot
        if slot then slot:SetAlpha(0) end
    end
    local function giveBackSlot()
        if taken then taken:SetAlpha(1) end
        taken = nil
    end

    -- Show the progress of the place the player is in, or hide when no set covers it or the bar is switched off.
    function ACB.refreshZoneBar()
        local index, owned, total = ACB.zoneProgress(saved)
        if not index or not ACB.settingOn(saved, "zoneBar") then
            bar:Hide()
            giveBackSlot()
            return
        end
        local slot = ACB.replacedBar()
        takeSlot(slot)
        bar:SetSize(400, 12)
        bar:SetFrameLevel(slot and slot.GetFrameLevel and slot:GetFrameLevel() + 5 or 10)
        place(slot)
        bar:SetMinMaxValues(0, total)
        bar:SetValue(owned)
        bar:SetStatusBarColor(BAR_FILL[1], BAR_FILL[2], BAR_FILL[3])
        label:SetText(("%s %d / %d"):format(ACB.pages[index].title, owned, total))
        bar:Show()
    end

    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED",
        "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "UPDATE_FACTION", "PLAYER_LEVEL_UP" }) do
        pcall(bar.RegisterEvent, bar, event)
    end
    bar:SetScript("OnEvent", function(_, event)
        ACB.refreshZoneBar()
        -- The zone name can still be empty while the game finishes loading; look again a moment later.
        if event == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then C_Timer.After(2, ACB.refreshZoneBar) end
    end)
    -- Use a separate shown watcher: the bar itself may be hidden while the zone
    -- name is unavailable, or before the game's tracking bars finish arranging.
    local watcher, elapsed = CreateFrame("Frame", nil, UIParent), 0
    watcher:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 2 then return end
        elapsed = 0
        ACB.refreshZoneBar()
    end)
    ACB.refreshZoneBar()
    return bar
end
