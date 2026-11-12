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

-- Reuse one portrait behind the parchment. Keeping it shown lets the client load
-- later portraits without allocating a model frame for every card in the set.
function ACB.createPortraitLoader(parent, paper)
    local model = CreateFrame("PlayerModel", nil, parent)
    model:SetSize(128, 104)
    model.acbPortraitLoader = true
    model:SetAlpha(0.001)
    model:SetPoint("CENTER", paper)
    model:SetFrameLevel(parent:GetFrameLevel())
    model:Hide()
    safe(model.SetKeepModelOnHide, model, true)

    local warmed = {}
    local cards, sourceCards, pending, nextSlot, remaining, retries, retryCards
    local elapsedSinceRequest = 0
    local function idle()
        pending = nil
        model:Hide()
        safe(model.ClearModel, model)
    end

    model:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRequest = elapsedSinceRequest + elapsed
        if not cards or elapsedSinceRequest < 0.08 then return end
        if pending then
            local file = ACB.read(safe(model.GetModelFileID, model), "number")
            if file and file > 0 and (not pending.profession or file == pending.model) and elapsedSinceRequest >= 0.25 then
                warmed[pending.key] = true
            elseif elapsedSinceRequest < 3 then
                return
            elseif not retries[pending.key] then
                -- A slow or unavailable model gets one more turn after the rest of
                -- the set, instead of starving the queue or being cached as ready.
                retries[pending.key] = true
                retryCards[#retryCards + 1] = pending
            end
        end
        if remaining == 0 and #retryCards > 0 then
            cards, nextSlot, remaining = retryCards, 1, #retryCards
            retryCards = {}
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
        if sourceCards == entries and model:IsShown() then return end
        idle()
        cards, sourceCards = entries, entries
        if not cards then return end
        retries, retryCards = {}, {}
        first, last = first or 1, last or 0
        remaining = #cards - math.max(0, last - first + 1)
        if remaining <= 0 then return end
        nextSlot, elapsedSinceRequest = last % #cards + 1, 0
        model:Show()
    end
end

-- Hidden pages and pack faces can receive their entry before the client starts
-- loading a model. Retry on visibility, with a bounded fallback for missed callbacks.
function ACB.watchCardModel(card, update, canLoad)
    local elapsed, attempts, key, settled = 0, 0
    local function ready(model)
        local file = ACB.read(safe(model.GetModelFileID, model), "number")
        return file and file > 0 and (not card.entry.profession or file == card.entry.model)
    end
    safe(card.model.SetScript, card.model, "OnModelLoaded", function(model)
        update(model)
        settled = card.entry and ready(model)
    end)
    local function resume(model)
        elapsed, attempts, key, settled = 0, 0, card.modelFor, false
        if not card.entry or card.entry.key ~= card.modelFor or not canLoad() then return end
        if not ready(model) then loadModel(model, card.entry) end
        update(model)
        settled = ready(model)
    end
    card.model:SetScript("OnShow", resume)
    card.model:SetScript("OnUpdate", function(model, dt)
        if not card.entry or not canLoad() then return end
        if key ~= card.modelFor then elapsed, attempts, key, settled = 0, 0, card.modelFor, false end
        if settled or attempts >= 2 then return end
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        update(model)
        if ready(model) then settled = true return end
        attempts = attempts + 1
        loadModel(model, card.entry)
    end)
    return function() resume(card.model) end
end

local function setModelFinish(model, found)
    safe(model.SetDesaturation, model, found and 0 or 1)
    safe(model.SetModelAlpha, model, found and 1 or 0.68)
end

local function poseCreature(model, entry, facing, presentation, animate)
    presentation = presentation or ACB.cardPresentation(entry)
    local preset = presentation.pose
    if not pcall(model.SetPortraitZoom, model, preset.zoom) then
        safe(model.SetCamDistanceScale, model, 0.8)
    end
    safe(model.SetFacing, model, facing)
    safe(model.SetPosition, model, preset.x or 0, preset.y or 0, preset.z or -0.05)

    local animation = preset.animation
    local supported = ACB.read(safe(model.HasAnimation, model, animation), "boolean")
    if not supported then
        for _, alternative in ipairs(preset.fallbacks or {}) do
            if ACB.read(safe(model.HasAnimation, model, alternative), "boolean") then
                animation, supported = alternative, true
                break
            end
        end
    end
    if supported and animate and presentation.animated and type(model.SetAnimation) == "function" then
        safe(model.SetPaused, model, false)
        if pcall(model.SetAnimation, model, animation, 0) then return true, animation end
    end
    if supported and pcall(model.FreezeAnimation, model, animation, 0, preset.frame) then return false, animation end
    if not pcall(model.FreezeAnimation, model, STAND, 0, 0) then safe(model.SetPaused, model, true) end
    return false
end

ACB.loadCardModel, ACB.setModelFinish, ACB.poseCreature = loadModel, setModelFinish, poseCreature

-- The pose chosen for a creature (a few have their own).
function ACB.portraitPreset(entry)
    return portraitPresets[entry.id] or ACB.signaturePresentation(entry) or humanoid
end
