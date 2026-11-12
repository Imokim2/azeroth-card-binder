local _, ACB = ...
local ui = ACB.folioUi

function ACB.createEditionStrip(parent, saved, choose)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(201, 27)
    strip:SetPoint("TOPLEFT", 28, -379)
    local controls = {}
    for index = 1, 3 do
        local control = ui.panel(strip, "Button", (index - 1) * 68, 0, 65, 27, ui.POCKET, ui.EDGE)
        control.title = ui.text(control, 1, 3, "", 8, ui.INK, 63, "CENTER")
        control.count = ui.text(control, 1, 15, "", 8, ui.SEPIA, 63, "CENTER")
        control:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        control:SetScript("OnClick", function()
            if IsShiftKeyDown() then ACB.linkCard(saved, control.entry) else choose(control.entry.key) end
        end)
        controls[index] = control
    end
    function strip:select(base, key)
        local family = ACB.cardEditions(base)
        local selected = ACB.firstOwnedEdition(saved.counts, base)
        for _, entry in ipairs(family) do if entry.key == key then selected = entry end end
        self:SetShown(#family > 1)
        for index, control in ipairs(controls) do
            local entry = family[index]
            control:SetShown(entry ~= nil)
            if entry then
                control.entry = entry
                control.title:SetText(entry.editionTitle or "Signature")
                local count = saved.counts[entry.key] or 0
                control.count:SetText(count > 0 and ("x%d%s"):format(count, entry.baseKey and " *" or "") or "Locked")
                control:SetBackdropBorderColor(unpack(entry == selected and ui.INK or ui.EDGE))
                control:SetAlpha((entry == selected or count > 0) and 1 or .65)
            end
        end
        return selected, #family > 1
    end
    strip.controls = controls
    return strip
end
