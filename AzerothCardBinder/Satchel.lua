local _, ACB = ...
local kit = ACB.uiKit
local PAGE_SIZE, COLUMNS = 24, 6

-- Pack artwork is shared by both sides of a trade; it has no creature model.
function ACB.createPackItemView(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    kit.backdrop(frame, "Interface\\Buttons\\WHITE8X8", 2)
    frame:SetBackdropColor(.17, .11, .07, 1)
    frame:SetBackdropBorderColor(unpack(kit.brass))
    local mark = frame:CreateTexture(nil, "ARTWORK")
    mark:SetSize(48, 48)
    mark:SetPoint("CENTER")
    mark:SetTexture(ACB.folioArt .. "Seal.tga")
    local name = kit.centered(frame, "GameFontNormal", 16, kit.parchment, width - 14)
    name:SetHeight(48)
    name:SetWordWrap(true)
    local foot = kit.centered(frame, "GameFontHighlightSmall", height - 36, kit.brass, width - 12)
    foot:SetHeight(32)
    return { frame = frame, set = function(_, item)
        name:SetText(item.name)
        local tier = ACB.packTiers[item.tier]
        foot:SetText(("%s / %d card%s\nSealed"):format(tier.name, item.size, item.size == 1 and "" or "s"))
        frame:SetBackdropBorderColor(unpack(tier.color))
    end }
end

function ACB.createSatchel(saved)
    local frame = ACB.createSatchelWindow()
    local view = { frame = frame, slots = {}, page = 1 }
    local summary = kit.label(frame, "GameFontHighlightSmall", 20, 40, kit.muted, "")
    kit.label(frame, "GameFontHighlightSmall", 20, 253, kit.muted, "Right-click a pack to open it.")
    local selected, pages
    local pageText = kit.centered(frame, "GameFontHighlightSmall", 283, kit.muted, 100)
    local back, more, offer
    for index = 1, PAGE_SIZE do
        local slot = CreateFrame("Button", nil, frame, "BackdropTemplate")
        slot:SetSize(40, 40)
        slot:SetPoint("TOPLEFT", 20 + ((index - 1) % COLUMNS) * 46, -(65 + math.floor((index - 1) / COLUMNS) * 46))
        ACB.styleSatchelSlot(slot)
        slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetSize(36, 36)
        icon:SetTexture(ACB.satchelIcon)
        local count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -3, 3)
        local tag = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tag:SetPoint("TOPLEFT", 3, -3)
        tag:SetTextColor(unpack(kit.gold))
        slot.icon, slot.count, slot.tag = icon, count, tag
        slot:SetScript("OnClick", function(self, mouse)
            if not self.zone then return end
            selected = self.zone
            if mouse == "RightButton" and ACB.openPack then
                if GameTooltip then GameTooltip:Hide() end
                ACB.openPack(self.zone)
            end
            view:refresh()
        end)
        slot:SetScript("OnEnter", function(self)
            if not self.zone or not GameTooltip then return end
            local item = ACB.packItem("pack:" .. self.zone)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(item.name, 1, .82, 0)
            local tier = ACB.packTiers[item.tier]
            GameTooltip:AddLine(("%s / %d card%s from this zone"):format(tier.name, item.size, item.size == 1 and "" or "s"), unpack(tier.color))
            GameTooltip:AddLine("Right-click to open. Select, then Trade to offer one.", .65, .61, .54, true)
            if ACB.collection and ACB.collection:packAvailable(self.zone) < self.owned then
                GameTooltip:AddLine("One pack is reserved for your current trade.", 1, .65, .2, true)
            end
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        view.slots[index] = slot
    end
    back = ACB.satchelButton(frame, "Previous", 16, 276, 82, function() view.page = view.page - 1 view:refresh() end)
    more = ACB.satchelButton(frame, "Next", 222, 276, 82, function() view.page = view.page + 1 view:refresh() end)
    offer = ACB.satchelButton(frame, "Trade selected pack", 16, 309, 182, function()
        if selected and ACB.prepareTrade then ACB.prepareTrade(nil, "pack:" .. selected) end
    end)
    ACB.satchelButton(frame, "Binder", 208, 309, 96, function() ACB.open() end)
    function view:refresh()
        local list, total = ACB.packList(saved)
        pages = math.max(1, math.ceil(#list / PAGE_SIZE))
        self.page = math.max(1, math.min(pages, self.page))
        if selected and (not saved.packs or (saved.packs[selected] or 0) < 1) then selected = nil end
        summary:SetText(total == 0 and "Your satchel is empty." or ("%d sealed pack%s / %d stack%s"):format(total, total == 1 and "" or "s", #list, #list == 1 and "" or "s"))
        for index, slot in ipairs(self.slots) do
            local item = list[(self.page - 1) * PAGE_SIZE + index]
            slot.zone, slot.owned = item and item.zone, item and item.count or 0
            slot.icon:SetShown(item ~= nil)
            slot.count:SetText(item and tostring(item.count) or "")
            slot.tag:SetText(item and tostring(item.size) or "")
            slot.qualityBorder:SetShown(item ~= nil)
            if item then slot.qualityBorder:SetVertexColor(unpack(ACB.packTiers[item.tier].color)) end
            slot.selection:SetShown(item ~= nil and item.zone == selected)
        end
        pageText:SetText(("%d / %d"):format(self.page, pages))
        back:SetEnabled(self.page > 1)
        more:SetEnabled(self.page < pages)
        offer:SetEnabled(selected ~= nil)
    end
    frame:SetScript("OnShow", function() view:refresh() end)
    frame:SetScript("OnMouseWheel", function(_, delta) view.page = view.page + (delta < 0 and 1 or -1) view:refresh() end)
    frame:EnableMouseWheel(true)
    view.controls = { offer = offer, back = back, more = more }
    return view
end

function ACB.initSatchel(saved, collection, trade)
    if collection and trade then collection.packReserved = function(zone)
        local session = trade:active()
        return session and session.modern and not session.closed and not session.applied and session.give == "pack:" .. zone
    end end
    local view = ACB.createSatchel(saved)
    ACB.satchel = view
    function ACB.openSatchel() view:refresh(); view.frame:SetShown(not view.frame:IsShown()) end
    local launcher = CreateFrame("Button", "AzerothCardBinderSatchelButton", UIParent, "BackdropTemplate")
    launcher:SetSize(34, 34)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetNormalTexture(ACB.satchelIcon)
    local rim = launcher:CreateTexture(nil, "OVERLAY")
    rim:SetAllPoints(launcher)
    rim:SetTexture("Interface\\Common\\WhiteIconFrame")
    launcher:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    launcher:RegisterForClicks("LeftButtonUp")
    launcher:SetScript("OnClick", ACB.openSatchel)
    local count = launcher:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    launcher:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Warcards Satchel", 1, .82, 0)
        GameTooltip:AddLine("Your sealed card packs. Click to open.", .94, .88, .75)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local function position()
        local anchor
        for _, name in ipairs({ "KeyRingButton", "CharacterBag3Slot", "MainMenuBarBackpackButton" }) do
            if _G[name] and _G[name]:IsShown() then anchor = _G[name] break end
        end
        launcher:ClearAllPoints()
        if anchor then launcher:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 5)
        else launcher:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 68) end
    end
    launcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    launcher:RegisterEvent("UI_SCALE_CHANGED")
    launcher:SetScript("OnEvent", position)
    position()
    function ACB.refreshSatchel()
        local _, total = ACB.packList(saved)
        count:SetText(total > 0 and tostring(total) or "")
        if view.frame:IsShown() then view:refresh() end
    end
    ACB.refreshSatchel()
    return view
end
