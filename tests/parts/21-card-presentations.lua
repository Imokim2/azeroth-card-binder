test("high rarity signatures are deterministic artwork and never consume drop randomness", function()
    local random = math.random
    math.random = function() error("artwork must not consume a drop roll") end
    local ok, why = pcall(function()
        local seen, signatures = {}, {}
        for key, entry in pairs(ACB.cards) do
            local preset = ACB.portraitPreset(entry)
            signatures[key] = { preset.facing, preset.animation, preset.frame }
            if entry.rarity == "epic" or entry.rarity == "legendary" then
                local generated = ACB.signaturePresentation(entry)
                if generated then seen[generated.id] = true end
            end
        end
        for key, entry in pairs(ACB.cards) do
            local preset = ACB.portraitPreset(entry)
            equal(preset.facing, signatures[key][1])
            equal(preset.animation, signatures[key][2])
            equal(preset.frame, signatures[key][3])
        end
        equal(ACB.countKeys(seen), 4)
        equal(ACB.portraitPreset(ACB.cards["npc:639"]).facing, -0.47)
        equal(ACB.portraitPreset(ACB.cards["npc:573"]).facing, -0.34)
        equal(#ACB.cardPresentations(ACB.cards["npc:589"], ACB.portraitPreset(ACB.cards["npc:589"])), 1)
    end)
    math.random = random
    assert(ok, why)
end)

test("authored animated editions play only on an owned detail, and pause or fall back safely", function()
    local entry = ACB.cards["npc:639"]
    local card = ACB.createCard(UIParent, true, ignore)
    card:set(entry, 1)
    card.model.fileID, card.model.supportedAnimation = 1000, 17
    card.model:OnModelLoaded()
    equal(card.playing, false)
    card:setPresentation("vancleef-blades")
    equal(card.playing, true)
    equal(card.model.animation, 17)
    equal(card.model.frozen, nil)
    equal(card.facing, -0.66)
    card.frame:OnUpdate(3.3)
    equal(card.model.animation, 17)
    card.frame:OnMouseDown("RightButton")
    equal(card.playing, false)
    equal(card.model.frozen[1], 17)
    card.frame:OnMouseDown("RightButton")
    equal(card.playing, true)
    card:set(entry, 0)
    equal(card.playing, false)
    card:set(entry, 1)
    equal(card.playing, true)
    card.model.supportedAnimation = nil
    card:setMotionPaused(false)
    equal(card.playing, false)
    equal(card.model.frozen[1], 0)
    card.model.supportedAnimation = 17
    card.model.SetAnimation = false -- older clients may not expose playback
    card:setMotionPaused(false)
    equal(card.playing, false)
    equal(card.model.frozen[1], 17)
    local thumbnail = ACB.createCard(UIParent, true)
    thumbnail:set(entry, 1)
    thumbnail.model.fileID, thumbnail.model.supportedAnimation = 1000, 17
    thumbnail:setPresentation("vancleef-blades")
    equal(thumbnail.playing, false)
    equal(thumbnail.model.frozen[1], 17)
    card:set(ACB.cards["node:1731"], 1)
    equal(card.playing, false)
end)

test("native design previews keep all four frames usable for owned, missing and shiny cards", function()
    for _, design in ipairs(ACB.cardDesigns) do
        local card = ACB.createCard(UIParent, true, ignore, { design = design.id })
        equal(card.frame.width, 136)
        equal(card.frame.height, 190)
        equal(card.design.id, design.id)
        card:set(ACB.cards["npc:639"], 1, true)
        equal(card.foil:IsShown(), true)
        card:set(ACB.cards["npc:639"], 0, true)
        equal(card.foil:IsShown(), false)
        equal(card.veil:IsShown(), true)
        card:set(ACB.cards["node:1731"], 2)
        equal(card.count.text, "x2")
        equal(card.veil:IsShown(), false)
    end
end)

test("the design studio previews editions without granting cards or writing ledger events", function()
    local saved = AzerothCardBinderDB
    local counts, shiny, sequence, checksum = saved.counts, saved.shiny, #saved.ledger, saved.stateSum
    local before = ACB.sumValues(saved.counts)
    local gallery = ACB.openCardStudio(ACB.cards["npc:639"])
    equal(gallery:IsShown(), true)
    equal(#gallery.cards, 4)
    for _, widget in ipairs(widgets) do
        if widget.parent == gallery and widget.OnClick and widget.text and widget.text:find("Blades Drawn", 1, true) then
            widget:OnClick()
            break
        end
    end
    for _, card in ipairs(gallery.cards) do equal(card.presentation.id, "vancleef-blades") end
    equal(saved.counts, counts)
    equal(saved.shiny, shiny)
    equal(#saved.ledger, sequence)
    equal(saved.stateSum, checksum)
    equal(ACB.sumValues(saved.counts), before)
    gallery:Hide()
    SlashCmdList.AZEROTHCARDBINDER("studio")
    equal(gallery:IsShown(), true)
    gallery:Hide()
end)
