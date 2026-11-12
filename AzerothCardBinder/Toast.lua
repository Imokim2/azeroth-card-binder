local _, ACB = ...

-- A pop-up that shows the card you just found, with a sound. Pop-ups queue up one after another,
-- pause while the mouse is over them, open the binder when clicked, and can be turned off with
-- /acb popup.
local WIDTH, HEIGHT = 176, 262
local FADE_IN, HOLD, FADE_OUT = 0.35, 4.6, 0.8
local MAX_QUEUE = 5
local FONT = "Fonts\\FRIZQT__.TTF"
local gold, goldDark = { 1, 0.82, 0 }, { 0.42, 0.33, 0.14 }
local SHINY = { 0.55, 0.92, 1 }

local function headline(info)
    if info.crafted then return "CRAFTED WITH DUST", gold end
    if info.trade then return "RECEIVED IN TRADE", gold end
    if info.shiny then return "SHINY CARD!", SHINY end
    if info.first then return "NEW CARD", gold end
    return ("DUPLICATE  x%d"):format(info.count or 2), { 0.54, 0.80, 0.61 }
end

function ACB.initToast(saved)
    ACB.initSounds(saved)
    local queue, current = {}, nil

    local frame = CreateFrame("Button", "AzerothCardBinderToast", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -130)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.045, 0.04, 0.035, 0.97)
    frame:Hide()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", frame, "TOP", 0, -12)
    header:SetFont(FONT, 13, "OUTLINE")

    local card = ACB.createCard(frame)
    card.frame:SetPoint("TOP", frame, "TOP", 0, -34)
    card.frame:EnableMouse(false) -- let the pop-up itself take the clicks

    -- A finished set has no card, so it gets its own text.
    local setName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setName:SetPoint("TOP", frame, "TOP", 0, -78)
    setName:SetWidth(WIDTH - 24)
    setName:SetFont(FONT, 20, "OUTLINE")
    setName:SetTextColor(gold[1], gold[2], gold[3])
    local setReward = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setReward:SetPoint("TOP", frame, "TOP", 0, -140)
    setReward:SetWidth(WIDTH - 24)
    setReward:SetFont(FONT, 13, "")
    setReward:SetTextColor(0.55, 0.92, 1)

    local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
    footer:SetFont(FONT, 10, "")
    footer:SetTextColor(0.78, 0.74, 0.66)

    local function finish()
        current = nil
        frame:Hide()
        local item = table.remove(queue, 1)
        if item then ACB.beginToast(item) end
    end

    function ACB.beginToast(item)
        if item.set then
            header:SetText("SET COMPLETE")
            header:SetTextColor(gold[1], gold[2], gold[3])
            frame:SetBackdropBorderColor(gold[1], gold[2], gold[3], 1)
            card.frame:Hide()
            setName:SetText(item.set.title)
            setReward:SetText(item.reward and ("Title earned:\n" .. item.reward) or "")
            footer:SetText(("%d cards collected"):format(item.total or 0))
            current = { elapsed = 0, item = item, paused = false }
            frame:SetAlpha(0)
            frame:SetScale(0.85)
            frame:Show()
            ACB.playSound("set_complete")
            return
        end
        card.frame:Show()
        setName:SetText("")
        setReward:SetText("")
        local entry, info = item.card, item.info
        local text, color = headline(info)
        local rarity = ACB.rarities[entry.rarity]
        local shiny = saved.shiny and saved.shiny[entry.key] == true
        header:SetText(text)
        header:SetTextColor(color[1], color[2], color[3])
        local edge = info.shiny and SHINY or rarity.color
        frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        card:set(entry, math.max(info.count or 1, 1), shiny)
        local page = ACB.pages[entry.page]
        footer:SetText(page and page.title or "")
        current = { elapsed = 0, item = item, paused = false }
        frame:SetAlpha(0)
        frame:SetScale(0.85)
        frame:Show()
        ACB.playCardSound(entry, info)
    end

    frame:SetScript("OnUpdate", function(self, delta)
        if not current or current.paused then return end
        current.elapsed = current.elapsed + delta
        local t = current.elapsed
        if t < FADE_IN then
            local progress = t / FADE_IN
            self:SetAlpha(progress)
            self:SetScale(0.85 + 0.15 * progress)
        elseif t < FADE_IN + HOLD then
            self:SetAlpha(1)
            self:SetScale(1)
        elseif t < FADE_IN + HOLD + FADE_OUT then
            self:SetAlpha(1 - (t - FADE_IN - HOLD) / FADE_OUT)
        else
            finish()
        end
    end)
    frame:SetScript("OnEnter", function(self)
        if current then
            current.paused = true
            self:SetAlpha(1)
            self:SetScale(1)
        end
    end)
    frame:SetScript("OnLeave", function()
        if current then current.paused = false end
    end)
    frame:SetScript("OnClick", function(_, button)
        if current and button ~= "RightButton" and ACB.open then ACB.open() end
        if current then finish() end
    end)

    -- Show a card that was just found. `info` says whether it is new, a duplicate, shiny or from a trade.
    function ACB.showToast(entry, info)
        if not entry then return end
        if saved.popups == false then ACB.playCardSound(entry, info) return end
        queue[#queue + 1] = { card = entry, info = info or {} }
        if current then
            if #queue > MAX_QUEUE then table.remove(queue, 1) end
        else
            ACB.beginToast(table.remove(queue, 1))
        end
    end

    -- Show that a whole set has been finished and which title it earned.
    function ACB.showSetToast(page, reward)
        if not page then return end
        if saved.popups == false then ACB.playSound("set_complete") return end
        queue[#queue + 1] = { set = page, reward = reward, total = #page.cards }
        if current then
            if #queue > MAX_QUEUE then table.remove(queue, 1) end
        else
            ACB.beginToast(table.remove(queue, 1))
        end
    end

    ACB.toast = frame
end
