local _, ACB = ...
local safe = ACB.safe

-- Putting a creature or object model into a card's portrait window: which way it faces, how close the camera
-- is, and which animation frame it is frozen on. Every game call is optional and guarded.

-- AnimationData IDs. Use the neutral frame when a model lacks its assigned combat animation.
local STAND, ATTACK_UNARMED, ATTACK_ONE_HAND, READY_UNARMED, READY_TWO_HAND, SPELL_CAST = 0, 16, 17, 25, 27, 32
local humanoid = { zoom = 0.57, facing = -0.40, animation = READY_UNARMED, frame = 12 }
local wide = { zoom = 0.28, facing = -0.34, animation = ATTACK_UNARMED, frame = 20 }
local portraitPresets = {
    [639] = { zoom = 0.60, facing = -0.47, animation = ATTACK_ONE_HAND, frame = 24 }, -- Edwin VanCleef
    [589] = { zoom = 0.54, facing = 0.36, animation = SPELL_CAST, frame = 20 }, -- Defias Pillager
    [646] = { zoom = 0.36, facing = -0.42, animation = READY_TWO_HAND, frame = 12 }, -- Mr. Smite
    [644] = wide, -- Rhahk'Zor
    [645] = wide, -- Cookie
    [642] = wide, -- Sneed's Shredder
    [114] = wide, -- Harvest Watcher
    [573] = wide, -- Foe Reaper 4000
}

local function loadModel(model, entry)
    if entry.profession then
        if entry.model then safe(model.SetModel, model, entry.model) end
    else
        safe(model.SetCreature, model, entry.id)
    end
end

-- Reuse one tiny model behind the parchment. Keeping it shown lets the client load
-- later portraits without allocating a model frame for every card in the set.
function ACB.createPortraitLoader(parent, paper)
    local model = CreateFrame("PlayerModel", nil, parent)
    model:SetSize(2, 2)
    model:SetPoint("CENTER", paper)
    model:SetFrameLevel(parent:GetFrameLevel())
    model:Hide()
    if not model.GetModelFileID or not model.ClearModel then return function() end end

    local warmed = {}
    local cards, pending, nextSlot, remaining
    local elapsedSinceRequest = 0
    local function idle()
        pending = nil
        model:Hide()
        safe(model.ClearModel, model)
    end

    model:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRequest = elapsedSinceRequest + elapsed
        if elapsedSinceRequest < 0.08 then return end
        if pending then
            local file = ACB.read(safe(model.GetModelFileID, model), "number")
            if file and file > 0 and (not pending.profession or file == pending.model) then
                warmed[pending.key] = true
            elseif elapsedSinceRequest < 1 then
                return
            end
        end
        while remaining > 0 do
            local entry = cards[nextSlot]
            nextSlot, remaining = nextSlot % #cards + 1, remaining - 1
            if not warmed[entry.key] and (not entry.profession or entry.model) then
                safe(model.ClearModel, model)
                pending, elapsedSinceRequest = entry, 0
                loadModel(model, entry)
                return
            end
        end
        idle()
    end)

    return function(entries, first, last)
        if cards == entries then return end
        idle()
        cards = entries
        if not cards then return end
        remaining = #cards - (last - first + 1)
        if remaining <= 0 then return end
        nextSlot, elapsedSinceRequest = last % #cards + 1, 0
        model:Show()
    end
end

local function setModelFinish(model, found)
    safe(model.SetDesaturation, model, found and 0 or 1)
    safe(model.SetModelAlpha, model, found and 1 or 0.68)
end

local function poseCreature(model, entry, facing)
    local preset = portraitPresets[entry.id] or humanoid
    if not pcall(model.SetPortraitZoom, model, preset.zoom) then
        safe(model.SetCamDistanceScale, model, 0.8)
    end
    safe(model.SetFacing, model, facing)
    safe(model.SetPosition, model, 0, 0, -0.05)

    local supported = ACB.read(safe(model.HasAnimation, model, preset.animation), "boolean")
    if supported and pcall(model.FreezeAnimation, model, preset.animation, 0, preset.frame) then return end
    if not pcall(model.FreezeAnimation, model, STAND, 0, 0) then safe(model.SetPaused, model, true) end
end

ACB.loadCardModel, ACB.setModelFinish, ACB.poseCreature = loadModel, setModelFinish, poseCreature

-- The pose chosen for a creature (a few have their own).
function ACB.portraitPreset(entry)
    return portraitPresets[entry.id] or humanoid
end
