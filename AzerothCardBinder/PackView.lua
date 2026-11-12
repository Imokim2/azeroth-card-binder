local _, ACB = ...
local kit = ACB.uiKit
local brass, parchment, muted, gold = kit.brass, kit.parchment, kit.muted, kit.gold
local label, button, backdrop = kit.label, kit.button, kit.backdrop

-- The card pack window: the packs you hold, and opening one. Opening is a short animation: the pack shakes, bursts, and five
-- face-down cards are dealt out; you click each one to flip it over and see what it is. The cards are in your binder as soon
-- as the pack is opened (Packs.lua writes them); the flipping is only how they are shown, and closing the window early prints
-- whatever was not flipped to chat so nothing is lost.
--
-- The animation is a small state machine driven by `view:step(seconds)`, which the window's OnUpdate calls every frame.

local WINDOW_W, WINDOW_H = 800, 560
local CARD_W, CARD_H = ACB.cardWidth, ACB.cardHeight
local GAP = 18
local SLOTS = 5
local SLOT_LEFT = (WINDOW_W - (SLOTS * CARD_W + (SLOTS - 1) * GAP)) / 2
local SLOT_TOP = 150
local MAX_ROWS = 6

local SHAKE, BURST = 1.0, 0.35 -- seconds the pack shakes, and takes to burst
local DEAL_STEP, DEAL_TIME = 0.12, 0.3 -- seconds between cards being dealt, and each one's slide
local FLIP = 0.5 -- seconds for a card to turn over
local FLIP_ALL_STEP = 0.18

local function clamp(value) return math.max(0, math.min(1, value)) end

function ACB.createPackView(saved)
    local frame = kit.window("AzerothCardBinderPacks", WINDOW_W, WINDOW_H, "Card packs", false)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    local view = { frame = frame, phase = "list", t = 0, slots = {}, results = nil }

    local status = label(frame, "GameFontHighlight", 40, 56, gold, "")
    status:SetWidth(720)

    -- ---- The list of packs ----
    local list = CreateFrame("Frame", nil, frame)
    list:SetAllPoints(frame)
    local note = label(list, "GameFontHighlightSmall", 40, 84, muted,
        "Any enemy you defeat has a 1 in 500 chance to drop a pack. A pack holds five cards from the zone it dropped in: common cards are common, rare ones rarer, legendary ones rarest.")
    note:SetWidth(720)
    local empty = label(list, "GameFontNormal", 40, 150, parchment, "")
    empty:SetWidth(720)
    local rows = {}
    for index = 1, MAX_ROWS do
        local y = 130 + (index - 1) * 52
        local row = { text = label(list, "GameFontNormalLarge", 60, y + 6, parchment, "") }
        row.text:SetWidth(520)
        row.button = button(list, "Open", 640, y, 110, function() view:openZone(row.zone) end)
        rows[index] = row
    end

    -- ---- The opening ----
    local stage = CreateFrame("Frame", nil, frame)
    stage:SetAllPoints(frame)
    stage:Hide()

    -- The pack itself, in the colours of its zone.
    local art = CreateFrame("Frame", nil, stage, "BackdropTemplate")
    art:SetSize(170, 232)
    art:SetPoint("CENTER", stage, "TOPLEFT", WINDOW_W / 2, -(SLOT_TOP + CARD_H / 2))
    backdrop(art, "Interface\\Buttons\\WHITE8X8", 2)
    art:SetBackdropColor(0.16, 0.11, 0.07, 1)
    art:SetBackdropBorderColor(0.88, 0.69, 0.40, 1)
    local artTitle = art:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    artTitle:SetPoint("TOP", art, "TOP", 0, -26)
    artTitle:SetWidth(150)
    artTitle:SetTextColor(unpack(gold))
    local artMark = art:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    artMark:SetPoint("CENTER", art, "CENTER", 0, 0)
    artMark:SetTextColor(unpack(brass))
    artMark:SetText("World of\nWarcards")
    local artFoot = art:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    artFoot:SetPoint("BOTTOM", art, "BOTTOM", 0, 22)
    artFoot:SetTextColor(unpack(parchment))
    artFoot:SetText("5 cards")
    art:Hide()

    local hint = label(stage, "GameFontHighlight", 0, 404, parchment, "")
    hint:SetWidth(WINDOW_W)
    hint:SetJustifyH("CENTER")

    for index = 1, SLOTS do
        local left = SLOT_LEFT + (index - 1) * (CARD_W + GAP)
        local slot = { index = index, state = "down", t = 0, delay = 0 }
        -- The face-down card.
        slot.back = CreateFrame("Button", nil, stage, "BackdropTemplate")
        slot.back:SetSize(CARD_W, CARD_H)
        slot.back:SetPoint("TOPLEFT", stage, "TOPLEFT", left, -SLOT_TOP)
        backdrop(slot.back, "Interface\\Buttons\\WHITE8X8", 3)
        slot.back:SetBackdropColor(0.20, 0.13, 0.09, 1)
        slot.back:SetBackdropBorderColor(0.78, 0.63, 0.42, 1)
        local mark = slot.back:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        mark:SetPoint("CENTER")
        mark:SetTextColor(unpack(brass))
        mark:SetText("Warcards")
        slot.back:SetScript("OnClick", function() view:flip(index) end)
        slot.back:Hide()
        -- The face: a card, in a frame that clips it so it can be uncovered from the middle outwards.
        slot.holder = CreateFrame("Frame", nil, stage)
        slot.holder:SetSize(CARD_W, CARD_H)
        slot.holder:SetPoint("TOP", stage, "TOPLEFT", left + CARD_W / 2, -SLOT_TOP)
        if slot.holder.SetClipsChildren then slot.holder:SetClipsChildren(true) end
        slot.card = ACB.createCard(slot.holder)
        slot.card.frame:SetPoint("CENTER", slot.holder, "CENTER", 0, 0)
        slot.card.frame:EnableMouse(false)
        slot.back:SetFrameLevel(slot.card.frame:GetFrameLevel() + 20)
        slot.holder:Hide()
        slot.caption = label(stage, "GameFontNormal", left, SLOT_TOP + CARD_H + 8, parchment, "")
        slot.caption:SetWidth(CARD_W)
        slot.caption:SetJustifyH("CENTER")
        view.slots[index] = slot
    end

    local flipAll = button(stage, "Flip all", 560, WINDOW_H - 70, 110, function() view:flipAll() end)
    local done = button(stage, "Done", 680, WINDOW_H - 70, 100, function() view:finish() end)

    -- ---- Showing the list ----
    function view:refreshList()
        local packs, total = ACB.packList(saved)
        empty:SetText(total == 0 and "You have no card packs." or "")
        for index, row in ipairs(rows) do
            local entry = packs[index]
            row.zone = entry and entry.zone
            row.text:SetText(entry and ("%s Pack   x%d"):format(entry.page.title, entry.count) or "")
            row.button:SetShown(entry ~= nil)
            row.text:SetShown(entry ~= nil)
        end
        if #packs > MAX_ROWS then status:SetText(("Showing %d of your %d zones of packs."):format(MAX_ROWS, #packs)) end
    end

    -- ---- The opening ----
    local function colors(page)
        local zone = ACB.zones and page and ACB.zones[page.zone]
        return zone and zone.top or { 0.36, 0.22, 0.11 }, zone and zone.bottom or { 0.07, 0.04, 0.03 }
    end

    function view:start(results, page)
        self.results, self.page, self.phase, self.t = results, page, "shake", 0
        local top = colors(page)
        art:SetBackdropColor(top[1] * 0.6 + 0.06, top[2] * 0.6 + 0.05, top[3] * 0.6 + 0.04, 1)
        artTitle:SetText(page.title .. " Pack")
        art:SetScale(1)
        art:SetAlpha(1)
        art:Show()
        for index, slot in ipairs(self.slots) do
            slot.state, slot.t, slot.delay = "down", 0, 0
            slot.back:Hide()
            slot.back:SetAlpha(0)
            -- Keep the actual faces shown and effectively transparent so the client can load them
            -- throughout the opening animation, before the player turns a card over.
            slot.holder:SetWidth(CARD_W)
            slot.holder:SetAlpha(0.001)
            slot.holder:Show()
            slot.back:SetWidth(CARD_W)
            local result = results[index]
            slot.card:set(result.card, result.count, result.shiny, false)
            slot.caption:SetText("")
            slot.back:SetBackdropBorderColor(0.78, 0.63, 0.42, 1)
        end
        hint:SetText("")
        status:SetText("")
        list:Hide()
        stage:Show()
        flipAll:Hide()
        done:Hide()
    end

    function view:flip(index)
        local slot = self.slots[index]
        if self.phase ~= "reveal" or not slot or slot.state ~= "down" then return false end
        slot.state, slot.t = "flipping", 0
        return true
    end

    function view:flipAll()
        local wait = 0
        for _, slot in ipairs(self.slots) do
            if slot.state == "down" then
                slot.delay = wait
                wait = wait + FLIP_ALL_STEP
            end
        end
        for _, slot in ipairs(self.slots) do
            if slot.state == "down" then self:flip(slot.index) end
        end
    end

    function view:flipped()
        local count = 0
        for _, slot in ipairs(self.slots) do
            if slot.state == "up" then count = count + 1 end
        end
        return count
    end

    local function caption(slot, result)
        if result.shiny then return "SHINY!", { 0.55, 0.92, 1 } end
        if result.first then return "NEW CARD", gold end
        return ("Duplicate  x%d"):format(result.count), { 0.54, 0.80, 0.61 }
    end

    -- Advance the animation by `dt` seconds.
    function view:step(dt)
        if self.phase == "list" then return end
        self.t = self.t + dt
        if self.phase == "shake" then
            local p = clamp(self.t / SHAKE)
            art:SetPoint("CENTER", stage, "TOPLEFT", WINDOW_W / 2 + math.sin(self.t * 55) * (2 + 9 * p), -(SLOT_TOP + CARD_H / 2) + math.sin(self.t * 43) * 2 * p)
            if self.t >= SHAKE then self.phase, self.t = "burst", 0 end
        elseif self.phase == "burst" then
            local p = clamp(self.t / BURST)
            art:SetScale(1 + 0.6 * p)
            art:SetAlpha(1 - p)
            if self.t >= BURST then
                art:Hide()
                self.phase, self.t = "deal", 0
                for _, slot in ipairs(self.slots) do slot.back:SetAlpha(0) slot.back:Show() end
            end
        elseif self.phase == "deal" then
            for index, slot in ipairs(self.slots) do
                local p = clamp((self.t - (index - 1) * DEAL_STEP) / DEAL_TIME)
                slot.back:SetAlpha(p)
                slot.back:SetPoint("TOPLEFT", stage, "TOPLEFT", SLOT_LEFT + (index - 1) * (CARD_W + GAP), -SLOT_TOP + (1 - p) * 40)
            end
            if self.t >= (SLOTS - 1) * DEAL_STEP + DEAL_TIME then
                self.phase, self.t = "reveal", 0
                hint:SetText("Click a card to turn it over.")
                flipAll:Show()
                done:Show()
            end
        else -- reveal: cards turning over
            for _, slot in ipairs(self.slots) do
                if slot.state == "flipping" then
                    slot.t = slot.t + dt
                    local p = clamp((slot.t - slot.delay) / FLIP)
                    if p < 0.5 then
                        slot.back:SetWidth(math.max(1, CARD_W * (1 - 2 * p)))
                    else
                        if slot.back:IsShown() then
                            slot.back:Hide()
                            slot.holder:SetAlpha(1)
                            slot.card:refreshPortrait()
                            slot.card.art:show(slot.card.entry.zone, true)
                        end
                        slot.holder:SetWidth(math.max(1, CARD_W * (2 * p - 1)))
                    end
                    if p >= 1 then
                        slot.state = "up"
                        slot.holder:SetWidth(CARD_W)
                        local result = self.results[slot.index]
                        local text, color = caption(slot, result)
                        slot.caption:SetText(text)
                        slot.caption:SetTextColor(unpack(color))
                        if ACB.playToastSound then ACB.playToastSound(result.card.rarity, result.shiny) end
                        if self:flipped() == SLOTS then
                            hint:SetText("That's all five. They are in your binder.")
                            flipAll:Hide()
                        end
                    end
                end
            end
        end
    end

    -- Open one pack of a zone and start showing it.
    function view:openZone(zone)
        if self.phase ~= "list" then return end
        local results, why = ACB.collection:openPack(zone)
        if not results then
            status:SetText(why or "That pack could not be opened.")
            return
        end
        self:start(results, ACB.pageOfZone(zone))
        if ACB.refresh then ACB.refresh() end
    end

    -- Back to the list. Cards that were never turned over are told to chat, so closing early loses nothing.
    function view:finish()
        if self.phase ~= "list" and self.results then
            local unseen = {}
            for index, slot in ipairs(self.slots) do
                if slot.state ~= "up" then unseen[#unseen + 1] = self.results[index] end
            end
            if #unseen > 0 and ACB.say then
                local names = {}
                for _, result in ipairs(unseen) do names[#names + 1] = result.card.name .. (result.shiny and " (shiny)" or "") end
                ACB.say("From the pack: " .. table.concat(names, ", ") .. ". They are in your binder.")
            end
            if ACB.refreshZoneBar then ACB.refreshZoneBar() end
        end
        self.phase, self.results = "list", nil
        stage:Hide()
        list:Show()
        status:SetText("")
        self:refreshList()
        if ACB.refresh then ACB.refresh() end
    end

    frame:SetScript("OnShow", function() if view.phase == "list" then view:refreshList() end end)
    frame:SetScript("OnHide", function() if view.phase ~= "list" then view:finish() end end)
    frame:SetScript("OnUpdate", function(_, dt) view:step(dt) end)
    return view
end

-- Create the window and the button that opens it, and turn packs on for the collection. Called once at load.
function ACB.initPacks(saved, collection)
    local view = ACB.createPackView(saved)
    ACB.packView = view
    function ACB.openPacks()
        view.frame:Show()
        view:refreshList()
    end
    collection.packsEnabled = true
    collection.onPack = function(page, count)
        if ACB.playToastSound then ACB.playToastSound("epic", false) end
        if ACB.refreshPackButton then ACB.refreshPackButton() end
        if view.frame:IsShown() and view.phase == "list" then view:refreshList() end
        if ACB.refresh then ACB.refresh() end
    end
    return view
end
