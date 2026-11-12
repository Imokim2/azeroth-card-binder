local _, ACB = ...
local kit = ACB.uiKit
local brass = kit.brass
local parchment = kit.parchment
local muted = kit.muted
local label = kit.label
local button = kit.button
local window = kit.window
local tab = kit.tab

local BINDER_WIDTH, BINDER_HEIGHT = 940, 644

function ACB.initUI(saved, trade)
    local frame = window("AzerothCardBinderWindow", BINDER_WIDTH, BINDER_HEIGHT, "World of Warcards", true)
    local function fitWindow()
        local scale = math.min(1, (UIParent:GetWidth() - 24) / BINDER_WIDTH,
            (UIParent:GetHeight() - 24) / BINDER_HEIGHT)
        if scale > 0 then frame:SetScale(scale) end
    end
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:SetScript("OnEvent", fitWindow)
    local page = 1
    local mode = "collection"
    local collectionView = ACB.createFolio(frame, saved, function(setIndex) ACB.open(setIndex) end)
    local achievementView = ACB.createAchievements(frame, saved)
    local tradeView = ACB.createTradeView(frame, saved, trade)
    ACB.tradeView = tradeView
    local settingsView = ACB.createSettingsView(frame, saved)
    local ladderView = ACB.createLadderView(frame, saved)
    local wantedView = ACB.createWantedView(frame, saved)

    local tabs = {}
    for index, destination in ipairs({ "index", "collection", "trade", "achievements", "ladder", "wanted", "settings" }) do
        local caption = destination:sub(1, 1):upper() .. destination:sub(2)
        tabs[destination] = tab(frame, caption, index, function() ACB.open(destination) end)
    end
    -- Card packs: how many are held, and a way to open them (PackView.lua).
    local packButton = button(frame, "Packs", nil, nil, 110, function()
        if ACB.openSatchel then ACB.openSatchel() elseif ACB.openPacks then ACB.openPacks() end
    end)
    packButton:SetSize(110, 22)
    packButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -222, -24)
    function ACB.refreshPackButton()
        local _, total = ACB.packList(saved)
        packButton:SetText(total > 0 and ("Packs (%d)"):format(total) or "Packs")
    end
    ACB.refreshPackButton()
    local titleMark = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleMark:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -56, -54)
    titleMark:SetTextColor(unpack(brass))
    local regionMark = label(frame, "GameFontHighlightSmall", 34, 62, brass, "")
    regionMark:SetWidth(196)
    regionMark:SetJustifyH("LEFT")

    function ACB.refresh()
        ACB.refreshPackButton()
        if not frame:IsShown() then return end
        for destination, control in pairs(tabs) do
            local active = destination == mode
            control.frame:SetEnabled(not active)
            if active then
                control.frame:SetBackdropColor(0.82, 0.67, 0.43, 1)
                control.title:SetTextColor(0.22, 0.13, 0.07, 1)
            else
                control.frame:SetBackdropColor(0.20, 0.13, 0.09, 1)
                control.title:SetTextColor(unpack(parchment))
            end
        end
        titleMark:SetText(saved.title and ("Title: " .. saved.title) or "")
        local inTrade, inSettings = mode == "trade", mode == "settings"
        local inAchievements, inLadder, inWanted = mode == "achievements", mode == "ladder", mode == "wanted"
        collectionView:SetShown(not inTrade and not inSettings and not inAchievements and not inLadder and not inWanted)
        tradeView:SetShown(inTrade)
        settingsView:SetShown(inSettings)
        achievementView:SetShown(inAchievements)
        ladderView:SetShown(inLadder)
        wantedView:SetShown(inWanted)
        if inWanted then
            regionMark:SetText("BINDER  /  WANTED")
            wantedView:refresh()
            return
        end
        if inLadder then
            regionMark:SetText("BINDER  /  LADDER")
            ladderView:refresh()
            return
        end
        if inSettings then
            regionMark:SetText("BINDER  /  SETTINGS")
            settingsView:refresh()
            return
        elseif inAchievements then
            regionMark:SetText("BINDER  /  ACHIEVEMENTS")
            achievementView:refresh()
            return
        end
        if not inTrade then
            regionMark:SetText(mode == "index" and "BINDER  /  INDEX" or ("BINDER  /  %02d"):format(page))
            collectionView:showRegion(page, mode == "index")
            return
        end
        regionMark:SetText("BINDER  /  TRADE")

        tradeView:refresh()
    end

    function ACB.open(destination)
        if tabs[destination] then
            mode = destination
        elseif type(destination) == "number" and ACB.pages[destination] and #ACB.pages[destination].cards > 0 then
            page, mode = destination, "collection"
        end
        fitWindow()
        frame:Show()
        ACB.refresh()
    end

    -- Open the binder on one card's page with that card selected.
    function ACB.openCard(key)
        local card = ACB.cards[key]
        if not card or not collectionView:selectCard(card.page, key) then return false end
        ACB.open(card.page)
        return true
    end

    function ACB.toggle()
        if frame:IsShown() then frame:Hide() else ACB.open() end
    end

    local logWindow = window("AzerothCardBinderLog", 674, 373, "Binder diagnostics")
    label(logWindow, "GameFontHighlightSmall", 26, 47, muted,
        "Ctrl+A then Ctrl+C to copy. The trace covers this session and omits spawn identifiers.")
    local scroll = CreateFrame("ScrollFrame", nil, logWindow, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 26, -70)
    scroll:SetPoint("BOTTOMRIGHT", -43, 24)
    local logText = CreateFrame("EditBox", nil, scroll)
    logText:SetMultiLine(true)
    logText:SetAutoFocus(false)
    logText:SetFontObject(ChatFontNormal)
    logText:SetWidth(598)
    logText:SetScript("OnEscapePressed", function() logWindow:Hide() end)
    scroll:SetScrollChild(logText)

    function ACB.showLog(message, enabled)
        if message == "" then
            message = enabled and "No events recorded yet." or "Use /acb diag to start recording."
        end
        local _, newlines = message:gsub("\n", "")
        logText:SetHeight(math.max(275, (newlines + 1) * 24))
        logText:SetText(message)
        logWindow:Show()
        scroll:SetVerticalScroll(0)
        logText:SetFocus()
        logText:HighlightText()
    end
end
