local _, ACB = ...

-- Fit the whole title, shrinking first and using two lines for very long names.
function ACB.fitText(line, font, value, width, maxSize, minSize, flags)
    flags = flags or ""
    line:SetWordWrap(false)
    line:SetWidth(width)
    local size = maxSize
    for _ = 1, 8 do
        line:SetFont(font, size, flags)
        line:SetText(value)
        local used = ACB.read(line:GetStringWidth(), "number")
        if not used or used <= width then return size end
        if size <= minSize then break end
        size = math.max(minSize, math.floor(size * width / used * 4 - 0.5) / 4)
    end
    line:SetWordWrap(true)
    ACB.safe(line.SetMaxLines, line, 2)
    line:SetFont(font, size, flags)
    line:SetText(value)
    return size
end

function ACB.installCardTooltip(card, typeName, interactive)
    card.frame:SetScript("OnEnter", function(self)
        local entry = card.entry
        if not entry or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local rarity = ACB.rarities[entry.rarity]
        GameTooltip:AddLine(entry.name, unpack(rarity.color))
        GameTooltip:AddLine(rarity.name .. " " .. typeName(entry), 0.8, 0.8, 0.8)
        if card.shiny then GameTooltip:AddLine("Shiny", 0.55, 0.92, 1) end
        if card.presentation and card.presentation.animated and interactive then
            GameTooltip:AddLine("Right-click to pause or resume model animation.", 0.65, 0.61, 0.54, true)
        end
        GameTooltip:AddLine(ACB.discoveryText(entry), 0.65, 0.61, 0.54, true)
        if entry.baseKey then
            GameTooltip:AddLine("Special collectible edition", 0.65, 0.61, 0.54, true)
        end
        if card.owned > 0 then
            GameTooltip:AddLine(("Owned %d, spare %d"):format(card.owned, card.owned - 1), 0.54, 0.80, 0.61)
        else
            GameTooltip:AddLine("Not in your binder yet", 0.65, 0.61, 0.54)
            GameTooltip:AddLine(ACB.whereToFind(entry), 0.65, 0.61, 0.54, true)
        end
        GameTooltip:Show()
    end)
    card.frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
