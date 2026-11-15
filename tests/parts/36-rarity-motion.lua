test("ordinary cards stay still without repeated facing calls but can be rotated by hand", function()
    local seen = {}
    shiftDown = false
    for _, entry in pairs(ACB.cards) do
        if not entry.baseKey and (not entry.profession or entry.model) and (entry.rarity == "common" or entry.rarity == "rare") then
            local card = ACB.createCard(UIParent, true, ignore)
            card:set(entry, 1)
            card.model.fileID = entry.model or 1000
            card.model:OnModelLoaded(); card.model:OnUpdate(.21)
            equal(card.presentation.motion, "still")
            equal(card.playing, false)
            local facing, writes = card.model.facing, 0
            card.model.SetFacing = function(self, value) self.facing = value; writes = writes + 1 end
            card.frame:OnUpdate(2); card.frame:OnUpdate(20)
            equal(card.model.facing, facing); equal(writes, 0)
            card.model.mouseOver, leftDown = true, true
            card.frame:OnMouseDown("LeftButton")
            cursorX = cursorX + 20
            card.frame:OnUpdate(.1)
            assert(writes > 0 and card.model.facing ~= facing, entry.name .. ": dragging must work without automatic motion")
            leftDown = false; cursorX = cursorX - 20
            card.frame:OnMouseUp("LeftButton")
            if entry.profession then
                card:set(entry, 0)
                equal(card.facing, 0.6); equal(card.model.facing, 0.6)
                card:set(entry, 1)
                equal(card.facing, 0.6); equal(card.model.facing, 0.6)
            end
            seen[entry.rarity] = true
            if entry.profession then seen.gathering = true end
            if seen.common and seen.rare and seen.gathering then break end
        end
    end
    assert(seen.common and seen.rare and seen.gathering, "coverage common=" .. tostring(seen.common) .. " rare=" .. tostring(seen.rare) .. " gathering=" .. tostring(seen.gathering))
end)

test("epic and legendary still portraits sway only on an owned detail and can pause", function()
    local checked = {}
    for _, entry in pairs(ACB.cards) do
        local presentation = ACB.cardPresentation(entry)
        if presentation.motion == "sway" and not checked[entry.rarity] then
            local card = ACB.createCard(UIParent, true, ignore)
            card:set(entry, 1)
            card.model.fileID = 1000
            card.model:OnModelLoaded(); card.model:OnUpdate(.21)
            local facing = card.model.facing
            card.frame:OnUpdate(2)
            assert(card.model.facing > facing)
            equal(card.playing, false, "a swaying card keeps its still action pose")
            card.frame:OnMouseDown("RightButton")
            local paused = card.model.facing
            card.frame:OnUpdate(2)
            equal(card.model.facing, paused)
            card.frame:OnMouseDown("RightButton")
            equal(card.motionPaused, false)
            card:set(entry, 0)
            card.frame:OnUpdate(2)
            equal(card.model.facing, card.facing, "missing cards do not autoplay")
            local small = ACB.createCard(UIParent, true)
            small:set(entry, 1)
            equal(small.frame.OnUpdate, nil, "previews remain still")
            checked[entry.rarity] = true
        end
    end
    assert(checked.epic and checked.legendary)
end)

test("VanCleef flexes on an owned detail, loops without sway and falls back to a still pose", function()
    local card = ACB.createCard(UIParent, true, ignore)
    local entry = ACB.cards["npc:639"]
    card:set(entry, 1)
    card.model.fileID, card.model.supportedAnimation = 1000, 82
    card.model:OnModelLoaded(); card.model:OnUpdate(.21)
    equal(card.presentation.motion, "animated"); equal(card.model.animation, 82); equal(card.playing, true)
    local facing, repeats = card.model.facing, 0
    card.model.SetAnimation = function(self, id) self.animation = id; repeats = repeats + 1 end
    card.frame:OnUpdate(card.presentation.duration + .1)
    equal(repeats, 1); equal(card.model.animation, 82); equal(card.model.facing, facing)
    card.frame:OnMouseDown("RightButton")
    equal(card.playing, false); equal(card.model.frozen[1], 82)
    card.frame:OnMouseDown("RightButton")
    equal(card.playing, true)
    card:set(entry, 0)
    equal(card.playing, false)
    card.model.supportedAnimation = 17
    card:set(entry, 1); card:setMotionPaused(false)
    equal(card.playing, false, "unsupported flex must not turn into a looping combat fallback")
    equal(card.model.frozen[1], 17); equal(card.model.frozen[3], 24)
end)

test("motion tiers are shared deterministic artwork and most launch cards are stationary", function()
    local total, still = 0, 0
    for _, page in ipairs(ACB.pages) do for _, entry in ipairs(page.cards) do
        local first, second = ACB.cardPresentation(entry), ACB.cardPresentation(entry)
        equal(first.motion, second.motion); equal(first.pose.animation, second.pose.animation)
        total = total + 1
        if first.motion == "still" then still = still + 1 end
        if entry.critter or entry.profession then equal(first.motion, "still") end
    end end
    assert(still > total * .5, "most of the collection must stay still")
    for _, family in pairs(ACB.editions) do for _, entry in ipairs(family) do
        if entry.baseKey and entry.presentation.animated then equal(ACB.cardPresentation(entry).motion, "animated") end
    end end
end)
