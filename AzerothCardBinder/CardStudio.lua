local _, ACB = ...
local kit = ACB.uiKit

-- A development gallery using the same card renderer as the binder. Previewing an
-- edition never changes SavedVariables or claims to unlock a collectible variant.
local studio
function ACB.openCardStudio(entry)
    if not studio then
        local frame = kit.window("AzerothCardBinderStudio", 1040, 680, "World of Warcards / Card design studio")
        local samples = { "npc:639", "npc:646", "npc:4275", "npc:3887", "npc:3976", "npc:3977", "npc:4832", "npc:4829", "npc:573" }
        local sample, edition, shiny, paused = 1, "signature", false, false
        local current, refresh
        local cards, editionButtons = {}, {}
        local info = kit.label(frame, "GameFontHighlightSmall", 32, 57, kit.muted,
            "Compare native addon frames. All cards below are artwork previews; nothing is added to your collection.")
        info:SetWidth(970)
        local sampleButton = kit.button(frame, "", 32, 86, 217, function()
            sample, edition = sample % #samples + 1, "signature"
            current = ACB.cards[samples[sample]]
            refresh()
        end)
        local finish = kit.button(frame, "Finish: Base", 269, 86, 180, function()
            shiny = not shiny
            refresh()
        end)
        local motion = kit.button(frame, "Pause animation", 465, 86, 180, function()
            paused = not paused
            refresh()
        end)
        kit.label(frame, "GameFontHighlightSmall", 664, 92, kit.muted, "Drag a portrait to turn it.")
        for index, design in ipairs(ACB.cardDesigns) do
            local x = 32 + (index - 1) * 247
            local title = kit.label(frame, "GameFontNormalLarge", x, 139, kit.brass, design.name)
            title:SetWidth(217)
            local holder = CreateFrame("Frame", nil, frame)
            holder:SetSize(ACB.cardWidth * 1.60, ACB.cardHeight * 1.60)
            holder:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -174)
            local card = ACB.createCard(holder, true, function() end, { design = design.id })
            card.frame:SetScale(1.60)
            card.frame:SetPoint("CENTER", holder, "CENTER")
            local note = kit.label(frame, "GameFontHighlightSmall", x, 493, kit.muted, design.note)
            note:SetWidth(217)
            note:SetHeight(40)
            note:SetWordWrap(true)
            cards[index] = card
        end
        kit.label(frame, "GameFontNormal", 32, 548, kit.brass, "Collectible edition previews")
        for index = 1, 3 do
            local choice = kit.button(frame, "", 32 + (index - 1) * 247, 574, 217, function()
                local presentations = ACB.cardPresentations(current, ACB.portraitPreset(current))
                edition = presentations[index].id
                refresh()
            end)
            editionButtons[index] = choice
        end
        local editionNote = kit.label(frame, "GameFontHighlightSmall", 32, 616, kit.muted, "")
        editionNote:SetWidth(970)
        function refresh()
            sampleButton:SetText(current.name .. "  >")
            finish:SetText(shiny and "Finish: Holographic" or "Finish: Base")
            local presentation = ACB.cardPresentation(current, edition)
            motion:SetEnabled(presentation.animated)
            motion:SetText(presentation.animated and (paused and "Resume animation" or "Pause animation") or "Still portrait")
            for _, card in ipairs(cards) do
                card:set(current, 1, shiny)
                card:setPresentation(edition)
                card:setMotionPaused(paused)
            end
            local presentations = ACB.cardPresentations(current, ACB.portraitPreset(current))
            for index, control in ipairs(editionButtons) do
                local choice = presentations[index]
                control:SetShown(choice ~= nil)
                if choice then control:SetText((choice.id == presentation.id and "[ " or "") .. choice.name ..
                    (choice.animated and " / Animated" or "") .. (choice.id == presentation.id and " ]" or "")) end
            end
            editionNote:SetText("PREVIEW ONLY / " .. presentation.name ..
                ". Gallery previews do not grant cards. Collectible editions are found in game; unsupported animations use a still pose.")
        end
        function frame:preview(cardEntry)
            current, edition = cardEntry or ACB.cards[samples[sample]], "signature"
            local width, height = UIParent:GetWidth(), UIParent:GetHeight()
            self:SetScale(math.min(1, (width - 30) / 1040, (height - 30) / 680))
            refresh()
            self:Show()
        end
        frame.cards = cards
        studio = frame
    end
    studio:preview(entry)
    return studio
end
