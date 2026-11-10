local _, ACB = ...

-- A thin bar that shows how many cards of the place you are in are in your binder. It follows you: walking into a
-- new zone, or through a dungeon door, changes the place, and finding a card moves the bar.
-- It takes the honour bar's place above the experience bar: while it shows, the honour bar is made invisible (its
-- transparency only, so the game's own bar logic is never touched) and the bar sits exactly where it was. With the bar
-- switched off, or in a place with no set, the honour bar is back. With no honour bar to be found, it sits above the
-- experience bar. Shift-drag moves it somewhere else.

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

local BAR_FILL, BAR_DONE = { 0.20, 0.52, 0.58 }, { 1, 0.82, 0 }
local TRACKING_FRAMES = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "MainMenuExpBar", "MainMenuBar" }
-- The names the game's honour bar goes by in its different interface versions.
local HONOUR_FRAMES = { "HonorWatchBar", "HonorStatusBar", "HonorStatusTrackingBar", "StatusTrackingBarManagerHonorBar" }

-- The game's honour bar, if it can be found: by name, or in the tracking-bar manager's list of bars.
function ACB.honourBar()
    for _, name in ipairs(HONOUR_FRAMES) do
        local found = _G[name]
        if type(found) == "table" and found.SetAlpha then return found, name end
    end
    local manager, kinds = _G.StatusTrackingBarManager, Enum and Enum.StatusBarType
    if type(manager) == "table" and type(manager.bars) == "table" and kinds and kinds.Honor then
        for _, found in pairs(manager.bars) do
            if type(found) == "table" and found.SetAlpha and ACB.read(found.barIndex, "number") == kinds.Honor then
                return found, "a tracking bar"
            end
        end
    end
end

function ACB.initZoneBar(saved)
    if not UIParent then return end
    local bar = CreateFrame("StatusBar", "AzerothCardBinderZoneBar", UIParent, "BackdropTemplate")
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bar:SetBackdropColor(0.03, 0.03, 0.04, 0.85)
    bar:SetBackdropBorderColor(0, 0, 0, 1)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")

    -- Sit above the experience bar. A position the player has dragged to is kept instead.
    local function place(honour)
        bar:ClearAllPoints()
        local spot = saved.zoneBarSpot
        if type(spot) == "table" and type(spot.x) == "number" and type(spot.y) == "number" then
            bar:SetPoint("BOTTOM", UIParent, "BOTTOM", spot.x, spot.y)
            return
        end
        -- Exactly over the honour bar, when it has a size to copy.
        local wide = honour and ACB.read(honour:GetWidth(), "number")
        local tall = honour and ACB.read(honour:GetHeight(), "number")
        if wide and tall and wide > 100 and tall > 2 then
            bar:SetPoint("TOPLEFT", honour, "TOPLEFT", 0, 0)
            bar:SetPoint("BOTTOMRIGHT", honour, "BOTTOMRIGHT", 0, 0)
            return
        end
        for _, name in ipairs(TRACKING_FRAMES) do
            local anchor = _G[name]
            local width = anchor and anchor.GetWidth and ACB.read(anchor:GetWidth(), "number")
            if width and width > 100 then
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

    -- The honour bar is only made see-through while this bar is up, and given back otherwise.
    local taken
    local function takeHonour(honour)
        if taken and taken ~= honour then taken:SetAlpha(1) end
        taken = honour
        if honour then honour:SetAlpha(0) end
    end
    local function giveBackHonour()
        if taken then taken:SetAlpha(1) end
        taken = nil
    end

    -- Show the progress of the place the player is in, or hide when no set covers it or the bar is switched off.
    function ACB.refreshZoneBar()
        local index, owned, total = ACB.zoneProgress(saved)
        if not index or not ACB.settingOn(saved, "zoneBar") then
            bar:Hide()
            giveBackHonour()
            return
        end
        local honour = ACB.honourBar()
        takeHonour(honour)
        place(honour)
        bar:SetMinMaxValues(0, total)
        bar:SetValue(owned)
        local color = owned >= total and BAR_DONE or BAR_FILL
        bar:SetStatusBarColor(color[1], color[2], color[3])
        label:SetText(("%s   %d / %d"):format(ACB.pages[index].title, owned, total))
        bar:Show()
    end

    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED" }) do
        pcall(bar.RegisterEvent, bar, event)
    end
    bar:SetScript("OnEvent", function(_, event)
        ACB.refreshZoneBar()
        -- The zone name can still be empty while the game finishes loading; look again a moment later.
        if event == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then C_Timer.After(2, ACB.refreshZoneBar) end
    end)
    ACB.refreshZoneBar()
    return bar
end
