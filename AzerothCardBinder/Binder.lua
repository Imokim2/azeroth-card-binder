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
    local tradeView = ACB.createTradeView(UIParent, saved, trade)
    ACB.tradeView = tradeView
    ACB.binderView = collectionView
    local tradeSelection, endTradeSelection
    local returnToTrade = button(frame, "Back to trade", 726, 48, 180, function() endTradeSelection() end)
    returnToTrade:Hide()
    local settingsView = ACB.createSettingsView(frame, saved)
    local ladderView = ACB.createLadderView(frame, saved)
    local wantedView = ACB.createWantedView(frame, saved)
    local seasonsView = ACB.createSeasonsView(frame, saved)

    local invite = window("AzerothCardBinderTradeNotice", 360, 142, "Incoming trade")
    invite:ClearAllPoints()
    invite:SetPoint("TOP", UIParent, "TOP", 0, -95)
    invite:SetFrameStrata("FULLSCREEN_DIALOG")
    local inviteText = label(invite, "GameFontHighlight", 24, 49, parchment, "")
    inviteText:SetWidth(312)
    inviteText:SetHeight(36)
    inviteText:SetWordWrap(true)
    local invitePeer, inviteTime
    invite.accept = button(invite, "Accept invitation", 24, 100, 145, function()
        if ACB.prepareTrade(invitePeer, nil, true) ~= false then invite:Hide() end
    end)
    invite.decline = button(invite, "Decline", 183, 100, 145, function() trade:cancel(); invite:Hide(); ACB.refresh() end)
    function ACB.notifyTrade(peer, gift)
        invitePeer, inviteTime = peer, 0
        inviteText:SetText(peer .. (gift and " sent you a gift." or " wants to trade cards or packs."))
        if ACB.playSound then ACB.playSound("trade") end
        invite:Show()
    end
    invite:SetScript("OnUpdate", function(_, elapsed)
        inviteTime = (inviteTime or 0) + elapsed
        local session = trade:active()
        if inviteTime > 15 or not session or session.peer ~= invitePeer or session.closed or session.applied then invite:Hide() end
    end)

    local tabs = {}
    for index, destination in ipairs({ "index", "collection", "seasons", "achievements", "ladder", "wanted", "settings" }) do
        local caption = destination:sub(1, 1):upper() .. destination:sub(2)
        tabs[destination] = tab(frame, caption, index, function() ACB.open(destination) end)
    end
    local titleMark = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleMark:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -56, -54)
    titleMark:SetTextColor(unpack(brass))
    local regionMark = label(frame, "GameFontHighlightSmall", 34, 62, brass, "")
    regionMark:SetWidth(196)
    regionMark:SetJustifyH("LEFT")
    local collectionMode = label(frame, "GameFontHighlightSmall", 250, 62, brass, "")
    collectionMode:SetWidth(450)

    function ACB.refresh()
        if tradeView:IsShown() then tradeView:refresh() end
        if tradeSelection and not tradeSelection.allowed() then endTradeSelection() end
        if not frame:IsShown() then return end
        ACB.refreshVisibleCards(saved) -- cards held back for seasons appear once released, or once owned
        for destination, control in pairs(tabs) do
            local active = destination == mode
            control.frame:SetEnabled(not active and (not tradeSelection or destination == "index" or destination == "collection"))
            if active then
                control.frame:SetBackdropColor(0.82, 0.67, 0.43, 1)
                control.title:SetTextColor(0.22, 0.13, 0.07, 1)
            else
                control.frame:SetBackdropColor(0.20, 0.13, 0.09, 1)
                control.title:SetTextColor(unpack(parchment))
            end
        end
        titleMark:SetText(saved.title and ("Title: " .. saved.title) or "")
        collectionMode:SetText(ACB.collectionModeText(saved))
        titleMark:SetAlpha(tradeSelection and 0 or 1)
        local inTrade, inSettings = mode == "trade", mode == "settings"
        local inAchievements, inLadder, inWanted = mode == "achievements", mode == "ladder", mode == "wanted"
        collectionView:SetShown(not inTrade and not inSettings and not inAchievements and not inLadder and not inWanted and mode ~= "seasons")
        seasonsView:SetShown(mode == "seasons")
        settingsView:SetShown(inSettings)
        achievementView:SetShown(inAchievements)
        ladderView:SetShown(inLadder)
        wantedView:SetShown(inWanted)
        if mode == "seasons" then
            regionMark:SetText("BINDER  /  SEASONS")
            seasonsView:refresh()
            return
        end
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
        if destination == "trade" then
            local s = trade:active()
            if s and s.invited then inviteTime = 0 invite:Show() return end
            if tradeSelection then endTradeSelection() end
            frame:Hide()
            tradeView:SetScale(math.min(1, (UIParent:GetWidth() - 24) / 680, (UIParent:GetHeight() - 24) / 584))
            tradeView:Show()
            tradeView:refresh()
            return
        end
        if not frame:IsShown() and ACB.playSound then ACB.playSound("binder") end
        if tabs[destination] then
            mode = destination
        elseif type(destination) == "number" and ACB.pages[destination] and #ACB.pages[destination].cards > 0 then
            page, mode = destination, "collection"
        end
        fitWindow()
        frame:Show()
        ACB.refresh()
    end

    endTradeSelection = function()
        if not tradeSelection then return end
        local level = tradeSelection.level
        tradeSelection = nil
        collectionView:setTradePicker(nil)
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(level)
        returnToTrade:Hide()
        frame:Hide()
        tradeView:Show()
        tradeView:refresh()
    end
    frame:SetScript("OnHide", function() if tradeSelection then endTradeSelection() end end)

    function ACB.selectTradeCard(choose, allowed, key)
        if not allowed() then return false end
        if tradeSelection then endTradeSelection() end
        tradeSelection = { allowed = allowed, level = frame:GetFrameLevel() }
        collectionView:setTradePicker(function(cardKey)
            if not tradeSelection or not allowed() or (saved.counts[cardKey] or 0) == 0 then return false end
            if choose(cardKey) == false then return false end
            endTradeSelection()
            return true
        end, allowed)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(math.max(frame:GetFrameLevel(), tradeView:GetFrameLevel() + 100))
        returnToTrade:Show()
        if not key or not ACB.openCard(key) then ACB.open("index") end
        return true
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
