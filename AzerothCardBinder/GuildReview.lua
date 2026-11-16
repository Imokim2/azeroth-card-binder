local _, ACB = ...
local ui, kit = ACB.folioUi, ACB.uiKit

function ACB.createGuildReview(remove, accept)
    local frame = kit.window("AzerothCardBinderGuildConfirm", 620, 530, "Review donation", true)
    frame.edition:Hide()
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    local body = ui.panel(frame, "Frame", 20, 78, 580, 370, { .88, .80, .62 }, ui.EDGE)
    local skin = body:CreateTexture(nil, "BACKGROUND")
    skin:SetAllPoints(); skin:SetTexture(ACB.folioArt .. "Parchment.tga")
    local heading = ui.text(body, 15, 16, "", 21, ui.INK, 550, "LEFT", true)
    local terms = ui.text(body, 15, 48, "Every copy leaves your binder permanently. Nobody can withdraw it from the guild.", 12, ui.SEPIA, 550)
    terms:SetWordWrap(true); terms:SetHeight(35)
    local scroll = ui.place(CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate"), 15, 91, 521, 211)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(521, 211); scroll:SetScrollChild(list)
    local rows = {}
    local warning = ui.text(body, 15, 315, "", 12, ui.INK, 550)
    warning:SetWordWrap(true); warning:SetHeight(44)
    local cancel = kit.button(frame, "Keep choosing", 25, 469, 270, function() frame:Hide() end)
    local donate = kit.button(frame, "Donate selected cards", 311, 469, 284, function() accept() end)
    ui.text(frame, 25, 504, "Your selection changes nothing until you confirm.", 11, kit.muted, 570, "CENTER")
    function frame:present(plan)
        heading:SetText(("%d copies for %s"):format(plan.total, plan.name))
        ACB.fitText(heading, ui.DISPLAY_FONT, heading:GetText(), 550, 21, 14, "")
        list:SetHeight(math.max(211, #plan.rows * 35))
        for index, entry in ipairs(plan.rows) do
            if not rows[index] then
                local row = { text = ui.text(list, 0, (index - 1) * 35 + 4, "", 12, ui.INK, 325),
                    flag = ui.text(list, 330, (index - 1) * 35 + 4, "", 10, ui.SEPIA, 97) }
                row.text:SetWordWrap(false)
                row.remove = kit.button(list, "Remove", 438, (index - 1) * 35, 78, function() remove(rows[index].key) end)
                rows[index] = row
            end
            local row = rows[index]
            row.key = entry.key
            row.text:SetText(("%dx %s"):format(entry.count, ACB.cards[entry.key].name))
            row.flag:SetText(entry.count == entry.before and "LAST COPY" or "")
            row.text:Show(); row.flag:Show(); row.remove:Show()
        end
        for index = #plan.rows + 1, #rows do rows[index].text:Hide(); rows[index].flag:Hide(); rows[index].remove:Hide() end
        warning:SetText(plan.lastCopies > 0 and ("LAST COPY WARNING: %d selected card%s will no longer be in your personal binder."):format(plan.lastCopies, plan.lastCopies == 1 and "" or "s")
            or "Only spare copies selected. Your personal binder keeps at least one of each card.")
        donate:SetText(("Donate %d %s"):format(plan.total, plan.total == 1 and "copy" or "copies"))
        scroll:SetVerticalScroll(0)
        frame:Show()
    end
    frame.controls = { accept = donate, cancel = cancel, rows = rows, warning = warning }
    return frame
end
