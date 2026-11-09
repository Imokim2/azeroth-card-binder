local _, ACB = ...
local brass = { 0.88, 0.69, 0.40 }
local parchment = { 0.94, 0.88, 0.75 }
local muted = { 0.65, 0.61, 0.54 }

local function label(parent, font, x, y, color, value)
    local line = parent:CreateFontString(nil, "OVERLAY", font)
    line:SetPoint("TOPLEFT", x, -y)
    line:SetJustifyH("LEFT")
    line:SetTextColor(unpack(color))
    line:SetText(value or "")
    return line
end

local function button(parent, text, x, y, width, click)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetPoint("TOPLEFT", x, -y)
    control:SetSize(width, 26)
    control:SetText(text)
    control:SetScript("OnClick", click)
    return control
end

local function backdrop(frame, edge, size)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = edge, edgeSize = size })
end

local function window(name, width, height, title)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    backdrop(frame, "Interface\\DialogFrame\\UI-DialogBox-Border", 24)
    frame:SetBackdropColor(0.072, 0.057, 0.049, 0.99)
    frame:SetBackdropBorderColor(0.78, 0.63, 0.42)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 18, -14)
    header:SetPoint("TOPRIGHT", -42, -14)
    header:SetHeight(32)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    label(header, "GameFontNormalLarge", 2, 3, brass, title)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    table.insert(UISpecialFrames, name)
    frame:Hide()
    return frame
end

local CARD_PITCH_X, CARD_PITCH_Y = 146, 200

function ACB.initUI(saved, trade)
    local frame = window("AzerothCardBinderWindow", 928, 590, "Azeroth Card Binder")
    local page = 1
    local collectionView = CreateFrame("Frame", nil, frame)
    collectionView:SetAllPoints(frame)
    local tradeView = CreateFrame("Frame", nil, frame)
    tradeView:SetAllPoints(frame)
    local tabs = {}
    for index, entry in ipairs(ACB.pages) do
        tabs[index] = button(frame, entry.title, 24 + (index - 1) * 126, 48, 118, function()
            page = index
            ACB.refresh()
        end)
    end
    tabs[4] = button(frame, "Trade", 402, 48, 118, function()
        page = 4
        ACB.refresh()
    end)
    local subtitle = label(collectionView, "GameFontNormal", 26, 84, brass)
    local completion = label(collectionView, "GameFontHighlight", 740, 84, parchment)
    local slots = {}
    for index = 1, #ACB.pages[1].cards do
        local slot = ACB.createCard(collectionView)
        slot.frame:SetPoint("TOPLEFT", 26 + ((index - 1) % 6) * CARD_PITCH_X, -111 - math.floor((index - 1) / 6) * CARD_PITCH_Y)
        slots[index] = slot
    end
    local milestones = {}
    for index, achievement in ipairs(ACB.achievements) do
        milestones[index] = label(collectionView, "GameFontNormal", 26 + (index - 1) * 345, 530, brass, achievement.name)
    end
    label(frame, "GameFontHighlightSmall", 26, 558, muted,
        "FIRST EDITION  /  FOREVER                                     /acb diag  -  toggle diagnostics      /acb log  -  copy trace")

    label(tradeView, "GameFontNormal", 26, 86, brass, "SWAP PREVIEW  /  ONE DUPLICATE EACH")
    label(tradeView, "GameFontHighlight", 26, 111, parchment,
        "Both players open Trade and enter each other's name. One listens, the other sends an offer.")
    label(tradeView, "GameFontHighlightSmall", 26, 145, muted, "PARTNER  /  Name or Name-Realm")
    local partner = CreateFrame("EditBox", nil, tradeView, "InputBoxTemplate")
    partner:SetSize(235, 28)
    partner:SetPoint("TOPLEFT", 30, -162)
    partner:SetAutoFocus(false)
    partner:SetMaxLetters(100)
    partner:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    partner:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local selected
    local function choose(step)
        local options, current = {}, 0
        for _, entry in ipairs(ACB.pages) do
            for _, card in ipairs(entry.cards) do
                if (saved.counts[card.key] or 0) >= 2 then
                    options[#options + 1] = card.key
                    if selected == card.key then current = #options end
                end
            end
        end
        if #options == 0 then
            selected = nil
        else
            selected = options[((current == 0 and 0 or current - 1 + step) % #options) + 1]
        end
        ACB.refresh()
    end

    label(tradeView, "GameFontHighlightSmall", 321, 145, muted, "CHOOSE A DUPLICATE")
    local selectedText = label(tradeView, "GameFontNormal", 321, 170, parchment)
    local previous = button(tradeView, "<", 618, 161, 35, function() choose(-1) end)
    local nextCard = button(tradeView, ">", 658, 161, 35, function() choose(1) end)
    local function withPeer(action)
        local peer = ACB.tradePeer(partner:GetText())
        partner:ClearFocus()
        if peer then action(peer) else trade.status = "Enter your partner's character name." end
        ACB.refresh()
    end
    local listen = button(tradeView, "Listen", 26, 204, 105, function()
        withPeer(function(peer) trade:listen(peer) end)
    end)
    local offer = button(tradeView, "Send offer", 142, 204, 109, function()
        withPeer(function(peer) trade:offer(peer, selected) end)
    end)
    local reply = button(tradeView, "Send reply", 262, 204, 109, function()
        trade:reply(selected)
        ACB.refresh()
    end)
    local clear = button(tradeView, "Clear", 589, 204, 105, function()
        trade:reset()
        ACB.refresh()
    end)
    local you = label(tradeView, "GameFontNormalLarge", 26, 261, parchment)
    local them = label(tradeView, "GameFontNormalLarge", 361, 261, parchment)
    local yourConfirmation = label(tradeView, "GameFontHighlightSmall", 26, 287, muted)
    local theirConfirmation = label(tradeView, "GameFontHighlightSmall", 361, 287, muted)
    local status = label(tradeView, "GameFontHighlight", 26, 323, brass)
    status:SetWidth(666)
    local confirm = button(tradeView, "Confirm preview", 26, 365, 154, function()
        trade:confirm()
        ACB.refresh()
    end)
    local retry = button(tradeView, "Resend last step", 190, 365, 154, function()
        trade:retry()
        ACB.refresh()
    end)
    label(tradeView, "GameFontHighlightSmall", 26, 413, muted,
        "Outdoors and out of combat. The preview exchanges offers and confirmations. Your cards stay in the binder.")

    function ACB.refresh()
        if not frame:IsShown() then return end
        for index, tab in ipairs(tabs) do tab:SetEnabled(index ~= page) end
        local binderPage = ACB.pages[page]
        collectionView:SetShown(binderPage ~= nil)
        tradeView:SetShown(binderPage == nil)
        if binderPage then
            local owned, total = ACB.progress(saved.counts, page)
            subtitle:SetText(binderPage.subtitle)
            completion:SetText(("%d / %d cards collected"):format(owned, total))
            for index, slot in ipairs(slots) do
                local card = binderPage.cards[index]
                slot.frame:SetShown(card ~= nil)
                if card then slot:set(card, saved.counts[card.key] or 0, saved.levels and saved.levels[card.key]) end
            end
            for index, milestone in ipairs(milestones) do
                milestone:SetShown(page == 1)
                if page == 1 then
                    local achievement = ACB.achievements[index]
                    local have, needed = ACB.progress(saved.counts, 1, achievement.bossesOnly)
                    local progress = saved.achievements[achievement.key] and "Earned" or ("%d / %d"):format(have, needed)
                    milestone:SetText(achievement.name .. "   " .. progress)
                end
            end
            return
        end

        local session = trade:active()
        local give, take = session and ACB.cards[session.give], session and ACB.cards[session.take]
        selectedText:SetText(selected and ACB.cards[selected].name or "Use < or > to choose")
        partner:SetEnabled(not session)
        previous:SetEnabled(not give)
        nextCard:SetEnabled(not give)
        listen:SetEnabled(not session)
        offer:SetEnabled(not session and selected ~= nil)
        reply:SetEnabled(take ~= nil and not give and selected ~= nil)
        clear:SetEnabled(session ~= nil)
        you:SetText("You offer   " .. (give and give.name or "-"))
        them:SetText("They offer   " .. (take and take.name or "-"))
        yourConfirmation:SetText(session and session.sentConfirm and "Confirmed" or "Awaiting your confirmation")
        theirConfirmation:SetText(session and session.peerConfirmed and "Confirmed" or "Awaiting partner")
        confirm:SetEnabled(give ~= nil and take ~= nil and not session.sentConfirm)
        retry:SetEnabled(give ~= nil)
        status:SetText(session and session.sentConfirm and session.peerConfirmed
            and "Preview complete. Both players confirmed these cards." or trade.status)
    end

    function ACB.open(index)
        if index then page = index end
        frame:Show()
        ACB.refresh()
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
