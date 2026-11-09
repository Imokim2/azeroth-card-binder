local _, ACB = ...
local brass = { 0.88, 0.69, 0.40 }
local parchment = { 0.94, 0.88, 0.75 }
local muted = { 0.65, 0.61, 0.54 }
local BINDER_WIDTH, BINDER_HEIGHT = 940, 644

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

local function window(name, width, height, title, folio)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if folio then
        frame:SetBackdrop({ bgFile = ACB.folioArt .. "Leather.tga" })
        frame:SetBackdropColor(1, 1, 1, 1)
    else
        backdrop(frame, "Interface\\DialogFrame\\UI-DialogBox-Border", 24)
        frame:SetBackdropColor(0.072, 0.057, 0.049, 0.99)
        frame:SetBackdropBorderColor(0.78, 0.63, 0.42)
    end
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 18, -14)
    header:SetPoint("TOPRIGHT", -42, -14)
    header:SetHeight(folio and 52 or 32)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    if folio then
        local seal = header:CreateTexture(nil, "ARTWORK")
        seal:SetTexture(ACB.folioArt .. "Launcher.tga")
        seal:SetSize(36, 36)
        seal:SetPoint("TOPLEFT", 8, -6)
        local heading = label(header, "GameFontNormalLarge", 55, 9, parchment, title)
        heading:SetFont("Fonts\\MORPHEUS.ttf", 33, "")
        local edition = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        edition:SetPoint("TOPRIGHT", -14, -20)
        edition:SetTextColor(unpack(brass))
        edition:SetText("F I R S T   E D I T I O N")
    else
        label(header, "GameFontNormalLarge", 2, 3, brass, title)
    end
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", folio and -16 or -6, folio and -14 or -6)
    table.insert(UISpecialFrames, name)
    frame:Hide()
    return frame
end

local function tab(parent, caption, index, open)
    local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", 30 + (index - 1) * 127, -76)
    frame:SetSize(116, 31)
    backdrop(frame, "Interface\\Buttons\\WHITE8X8", 1)
    frame:SetBackdropBorderColor(0.63, 0.46, 0.29, 1)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("CENTER")
    frame:SetFontString(title)
    frame:SetText(caption)
    frame:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    frame:SetScript("OnClick", open)
    return { frame = frame, title = title }
end

local gold, goldDark, green = { 1, 0.82, 0 }, { 0.42, 0.33, 0.14 }, { 0.2, 1, 0.3 }

local function centered(parent, font, y, color, width)
    local line = parent:CreateFontString(nil, "OVERLAY", font)
    line:SetPoint("TOP", parent, "TOP", 0, -y)
    line:SetWidth(width)
    line:SetJustifyH("CENTER")
    line:SetTextColor(unpack(color))
    return line
end

-- One side of the trade window: a header with the player's name, the offered card and an accepted line.
local function offerPanel(parent, x, y)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(290, 330)
    panel:SetPoint("TOPLEFT", x, -y)
    backdrop(panel, "Interface\\Tooltips\\UI-Tooltip-Border", 16)
    panel:SetBackdropColor(0.055, 0.05, 0.045, 0.96)
    panel:SetBackdropBorderColor(unpack(goldDark))
    local side = { frame = panel }
    side.header = centered(panel, "GameFontNormal", 14, gold, 260)
    side.card = ACB.createCard(panel)
    side.card.frame:SetPoint("TOP", panel, "TOP", 0, -40)
    side.hint = centered(panel, "GameFontHighlightSmall", 122, muted, 220)
    side.accepted = centered(panel, "GameFontNormal", 274, muted, 260)
    side.note = centered(panel, "GameFontHighlightSmall", 296, muted, 266)
    return side
end

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
    local tradeView = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    tradeView:SetPoint("TOPLEFT", 20, -109)
    tradeView:SetSize(900, 500)
    backdrop(tradeView, "Interface\\Buttons\\WHITE8X8", 1)
    tradeView:SetBackdropColor(0.13, 0.09, 0.07, 1)
    tradeView:SetBackdropBorderColor(0.58, 0.43, 0.27, 1)
    -- Settings: tick boxes for the switches that used to be slash commands only, and the title shown beside your name.
    local settingsView = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    settingsView:SetPoint("TOPLEFT", 20, -109)
    settingsView:SetSize(900, 500)
    backdrop(settingsView, "Interface\\Buttons\\WHITE8X8", 1)
    settingsView:SetBackdropColor(0.13, 0.09, 0.07, 1)
    settingsView:SetBackdropBorderColor(0.58, 0.43, 0.27, 1)
    label(settingsView, "GameFontNormalLarge", 32, 20, brass, "Settings")
    local checks = {}
    for index, setting in ipairs(ACB.settings) do
        local y = 62 + (index - 1) * 56
        local check = CreateFrame("CheckButton", nil, settingsView, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 30, -y)
        check:SetSize(30, 30)
        check:SetScript("OnClick", function(self)
            ACB.setSetting(saved, setting.key, self:GetChecked() == true)
            ACB.refresh()
        end)
        label(settingsView, "GameFontNormal", 70, y + 2, parchment, setting.name)
        label(settingsView, "GameFontHighlightSmall", 70, y + 20, muted, setting.note)
        checks[setting.key] = check
    end
    local titleY = 62 + #ACB.settings * 56 + 6
    label(settingsView, "GameFontNormal", 32, titleY + 6, parchment, "Title shown beside your name")
    button(settingsView, "Previous title", 290, titleY, 110, function()
        ACB.cycleTitle(saved, -1)
        ACB.refresh()
    end)
    local titleName = label(settingsView, "GameFontHighlight", 406, titleY + 6, gold, "")
    titleName:SetWidth(170)
    titleName:SetJustifyH("CENTER")
    button(settingsView, "Next title", 582, titleY, 110, function()
        ACB.cycleTitle(saved, 1)
        ACB.refresh()
    end)
    button(settingsView, "Test pop-up", 32, titleY + 48, 130, function() SlashCmdList.AZEROTHCARDBINDER("popup test") end)
    button(settingsView, "Open diagnostics log", 172, titleY + 48, 170, function() SlashCmdList.AZEROTHCARDBINDER("log") end)
    label(settingsView, "GameFontHighlightSmall", 32, titleY + 90, muted,
        "Everything here is also a slash command: /acb popup, hints, privacy, diag, boss and title.")

    local tabs = {}
    for index, destination in ipairs({ "index", "collection", "trade", "settings" }) do
        local caption = destination:sub(1, 1):upper() .. destination:sub(2)
        tabs[destination] = tab(frame, caption, index, function() ACB.open(destination) end)
    end
    local titleMark = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleMark:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -56, -54)
    titleMark:SetTextColor(unpack(brass))
    local regionMark = label(frame, "GameFontHighlightSmall", 713, 86, brass, "")
    regionMark:SetWidth(196)
    regionMark:SetJustifyH("RIGHT")

    -- The trade window: your offer on the left, your partner's on the right, buttons along the bottom.
    local box = CreateFrame("Frame", nil, tradeView)
    box:SetSize(640, 480)
    box:SetPoint("TOP", tradeView, "TOP", 0, -8)
    label(box, "GameFontHighlightSmall", 22, 17, muted, "TRADE WITH")
    local partner = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    partner:SetSize(235, 28)
    partner:SetPoint("TOPLEFT", 100, -8)
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

    local function withPeer(action)
        local peer = ACB.tradePeer(partner:GetText())
        partner:ClearFocus()
        if peer then action(peer) else trade.status = "Enter your partner's character name." end
        ACB.refresh()
    end
    local listen = button(box, "Listen", 346, 8, 84, function()
        withPeer(function(peer) trade:listen(peer) end)
    end)
    local offer = button(box, "Send offer", 436, 8, 90, function()
        withPeer(function(peer) trade:offer(peer, selected) end)
    end)
    local reply = button(box, "Send reply", 532, 8, 90, function()
        trade:reply(selected)
        ACB.refresh()
    end)

    local mine = offerPanel(box, 20, 52)
    local theirs = offerPanel(box, 330, 52)
    local previous = button(mine.frame, "<", 20, 236, 34, function() choose(-1) end)
    local nextCard = button(mine.frame, ">", 236, 236, 34, function() choose(1) end)
    local chooseText = centered(mine.frame, "GameFontHighlightSmall", 243, muted, 170)

    local status = centered(box, "GameFontHighlight", 384, gold, 600)
    local confirm = button(box, "Accept trade", 20, 414, 140, function()
        trade:confirm()
        ACB.refresh()
    end)
    local retry = button(box, "Resend last step", 166, 414, 140, function()
        trade:retry()
        ACB.refresh()
    end)
    local share = button(box, "Share lists", 312, 414, 120, function()
        trade:shareLists()
        ACB.refresh()
    end)
    local showHistory = false
    local historyButton = button(box, "History", 438, 414, 90, function()
        showHistory = not showHistory
        ACB.refresh()
    end)
    local clear = button(box, "Cancel", 534, 414, 86, function()
        trade:reset()
        ACB.refresh()
    end)
    local historyPanel = CreateFrame("Frame", nil, box, "BackdropTemplate")
    historyPanel:SetSize(600, 330)
    historyPanel:SetPoint("TOPLEFT", 20, -52)
    historyPanel:SetFrameLevel(box:GetFrameLevel() + 60)
    backdrop(historyPanel, "Interface\\Tooltips\\UI-Tooltip-Border", 16)
    historyPanel:SetBackdropColor(0.055, 0.05, 0.045, 0.99)
    historyPanel:SetBackdropBorderColor(unpack(goldDark))
    centered(historyPanel, "GameFontNormal", 14, gold, 560):SetText("Trade history")
    local historyText = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    historyText:SetPoint("TOPLEFT", 24, -44)
    historyText:SetWidth(552)
    historyText:SetJustifyH("LEFT")
    historyText:SetSpacing(6)
    historyText:SetTextColor(unpack(parchment))
    historyPanel:Hide()
    centered(box, "GameFontHighlightSmall", 452, muted, 600):SetText(
        "Outdoors and out of combat. Both players accept the same two cards and the swap then happens on both sides. It runs on trust.")

    function ACB.refresh()
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
        collectionView:SetShown(not inTrade and not inSettings)
        tradeView:SetShown(inTrade)
        settingsView:SetShown(inSettings)
        if inSettings then
            regionMark:SetText("BINDER  /  SETTINGS")
            for _, setting in ipairs(ACB.settings) do checks[setting.key]:SetChecked(ACB.settingOn(saved, setting)) end
            titleName:SetText(saved.title or "None earned yet")
            return
        end
        if not inTrade then
            regionMark:SetText(mode == "index" and "BINDER  /  INDEX" or ("BINDER  /  %02d"):format(page))
            collectionView:showRegion(page, mode == "index")
            return
        end
        regionMark:SetText("BINDER  /  TRADE")

        local session = trade:active()
        local live = session ~= nil and not session.applied -- a finished trade stays on screen but is over
        local give, take = session and ACB.cards[session.give], session and ACB.cards[session.take]
        local offering = give or (selected and ACB.cards[selected])
        local name = ACB.read(UnitName and UnitName("player"), "string") or "You"
        local partnerName = (partner:GetText() or ""):match("^%s*(.-)%s*$")
        partner:SetEnabled(not live)
        previous:SetEnabled(not (live and give))
        nextCard:SetEnabled(not (live and give))
        listen:SetEnabled(not live)
        offer:SetEnabled(not live and selected ~= nil)
        reply:SetEnabled(live and take ~= nil and not give and selected ~= nil)
        clear:SetEnabled(session ~= nil)
        share:SetEnabled(live)
        historyButton:SetText(showHistory and "Back" or "History")
        historyPanel:SetShown(showHistory)
        if showHistory then
            local lines = ACB.tradeHistory(saved)
            historyText:SetText(#lines > 0 and table.concat(lines, "\n") or "No trades yet. Finished swaps are listed here.")
        end
        confirm:SetEnabled(live and give ~= nil and take ~= nil and not session.sentConfirm)
        retry:SetEnabled(give ~= nil)

        mine.header:SetText(name)
        theirs.header:SetText(partnerName ~= "" and partnerName or "Partner")
        chooseText:SetText(offering and offering.name or "Choose a duplicate")
        local function fill(side, card, owned, shiny)
            side.card.frame:SetShown(card ~= nil)
            if card then side.card:set(card, owned, shiny) end
        end
        fill(mine, offering, offering and saved.counts[offering.key] or 0,
            offering and saved.shiny and saved.shiny[offering.key])
        fill(theirs, take, 1)
        -- What the partner shared, with the cards that matter to you picked out.
        local function names(keys, mark)
            local out = {}
            for _, key in ipairs(keys or {}) do
                if not mark or mark(key) then out[#out + 1] = ACB.cards[key].name end
            end
            return table.concat(out, ", ")
        end
        local sharedSpares, sharedWants = session and session.theirSpares, session and session.theirWants
        local needed = names(sharedSpares, function(key) return (saved.counts[key] or 0) == 0 end)
        if needed ~= "" then
            theirs.note:SetText("They have spares you need: " .. needed)
            theirs.note:SetTextColor(unpack(green))
        elseif sharedSpares then
            theirs.note:SetText(#sharedSpares > 0 and ("Their spares: " .. names(sharedSpares)) or "They have no spare cards.")
            theirs.note:SetTextColor(unpack(muted))
        else
            theirs.note:SetText(live and "Press Share lists to see their spares." or "")
            theirs.note:SetTextColor(unpack(muted))
        end
        local wantsFromMe = names(sharedWants, function(key) return (saved.counts[key] or 0) >= 2 end)
        if wantsFromMe ~= "" then
            mine.note:SetText("They want from you: " .. wantsFromMe)
            mine.note:SetTextColor(unpack(green))
        else
            mine.note:SetText(sharedWants and "They are not looking for your spares." or "")
            mine.note:SetTextColor(unpack(muted))
        end
        mine.hint:SetText(offering and "" or "Use < and > to pick one of your spare cards.")
        theirs.hint:SetText(take and "" or (session and "Waiting for their card." or "Their offer will appear here."))
        local function accepted(side, yes)
            side.accepted:SetText(yes and "Accepted" or "Not accepted")
            side.accepted:SetTextColor(unpack(yes and green or muted))
            side.frame:SetBackdropBorderColor(unpack(yes and green or goldDark))
        end
        accepted(mine, session and session.sentConfirm)
        accepted(theirs, session and session.peerConfirmed)
        status:SetText(trade.status)
    end

    -- Open the trade window with a partner's name already entered.
    function ACB.prepareTrade(name)
        if type(name) == "string" and name ~= "" then
            partner:SetText(name)
            trade.status = "Trading with " .. name .. ". Pick a spare card and Send offer, or Listen for theirs."
        end
        ACB.open("trade")
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
