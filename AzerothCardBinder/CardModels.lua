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

-- Retain one model per unique creature/node in the selected set. Clearing a
-- single scratch model immediately after loading let the client evict it again.
-- Four requests run together; completed frames keep their resources while hidden.
function ACB.createPortraitLoader(parent, paper)
    local driver = CreateFrame("Frame", nil, parent)
    driver.acbPortraitLoader, driver.models = true, {}
    driver:SetAllPoints(parent)
    driver:SetFrameLevel(parent:GetFrameLevel())
    driver:Hide()
    local source, queue, nextSlot, active = nil, {}, 1, 0
    local function ready(model)
        local file = ACB.read(safe(model.GetModelFileID, model), "number")
        return file and file > 0 and (not model.entry.profession or file == model.entry.model)
    end
    local function request(model)
        model.age, model.active = 0, true
        active = active + 1
        model:Show()
        loadModel(model, model.entry)
    end
    driver:SetScript("OnUpdate", function(_, elapsed)
        for _, model in ipairs(driver.models) do
            if model.active then
                model.age = model.age + elapsed
                if (ready(model) and model.age >= .2) or model.age >= 3 then
                    model.active = false
                    active = active - 1
                    model:Hide()
                    if not ready(model) and not model.retried then
                        model.retried = true
                        queue[#queue + 1] = model
                    end
                end
            end
        end
        while active < 4 and nextSlot <= #queue do
            local model = queue[nextSlot]
            nextSlot = nextSlot + 1
            request(model)
        end
        if active == 0 and nextSlot > #queue then driver:Hide() end
    end)
    return function(entries)
        if source == entries and entries then
            if nextSlot <= #queue or active > 0 then
                driver:Show()
                for _, model in ipairs(driver.models) do if model.active then model:Show() end end
            end
            return
        end
        driver:Hide()
        for _, model in ipairs(driver.models) do model:Hide() end
        if not entries then return end
        for _, model in ipairs(driver.models) do
            model.active = false
            safe(model.ClearModel, model)
        end
        source, queue, nextSlot, active = entries, {}, 1, 0
        local seen, count = {}, 0
        for _, entry in ipairs(entries) do
            local key = entry.profession and entry.model or ("npc:" .. entry.id)
            if key and not seen[key] then
                seen[key], count = true, count + 1
                local model = driver.models[count]
                if not model then
                    model = CreateFrame("PlayerModel", nil, driver)
                    model:SetSize(128, 104)
                    model:SetPoint("CENTER", paper)
                    -- Opaque parchment covers this normally rendered loader.
                    -- Near-zero alpha can prevent the engine from rendering/loading it.
                    model:SetFrameLevel(parent:GetFrameLevel())
                    safe(model.SetKeepModelOnHide, model, true)
                    driver.models[count] = model
                end
                model.entry, model.retried, model.active = entry, false, false
                queue[#queue + 1] = model
            end
        end
        if #queue > 0 then driver:Show() end
    end
end

-- Hidden pages and pack faces can receive their entry before the client starts
-- loading a model. Retry on visibility, with a bounded fallback for missed callbacks.
function ACB.watchCardModel(card, update, canLoad)
    local elapsed, attempts, key, settled, passes = 0, 0, nil, false, 0
    local function ready(model)
        local file = ACB.read(safe(model.GetModelFileID, model), "number")
        return file and file > 0 and (not card.entry.profession or file == card.entry.model)
    end
    safe(card.model.SetScript, card.model, "OnModelLoaded", function(model)
        update(model)
        elapsed, passes, settled = 0, 0, false
    end)
    local function resume(model)
        elapsed, attempts, key, settled, passes = 0, 0, card.modelFor, false, 0
        if not card.entry or card.entry.key ~= card.modelFor or not canLoad() then return end
        if not ready(model) then loadModel(model, card.entry) end
        update(model)
    end
    card.model:SetScript("OnShow", resume)
    card.model:SetScript("OnUpdate", function(model, dt)
        if not card.entry or not canLoad() then return end
        if key ~= card.modelFor then elapsed, attempts, key, settled, passes = 0, 0, card.modelFor, false, 0 end
        if settled or attempts >= 2 then return end
        elapsed = elapsed + dt
        if elapsed < (passes < 2 and .2 or 1) then return end
        elapsed = 0
        update(model)
        passes = passes + 1
        if ready(model) then settled = passes >= 2 return end
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
    local playing = false
    if supported and animate and presentation.animated and type(model.SetAnimation) == "function" then
        safe(model.SetPaused, model, false)
        playing = pcall(model.SetAnimation, model, animation, 0)
    end
    if not playing then
        if not (supported and pcall(model.FreezeAnimation, model, animation, 0, preset.frame)) then
            animation = STAND
            if not pcall(model.FreezeAnimation, model, STAND, 0, 0) then safe(model.SetPaused, model, true) end
        end
    end
    -- Pose first, then reset and apply the camera. Its bounds must come from the
    -- same frozen frame in both thumbnails and the detail, including late loads.
    safe(model.SetCamera, model, 0)
    safe(model.SetCamDistanceScale, model, 1.05)
    if not pcall(model.SetPortraitZoom, model, preset.zoom) then safe(model.SetCamDistanceScale, model, .8) end
    safe(model.SetPosition, model, preset.x or 0, preset.y or 0, preset.z or -.05)
    safe(model.SetFacing, model, facing)
    return playing, animation
end

ACB.loadCardModel, ACB.setModelFinish, ACB.poseCreature = loadModel, setModelFinish, poseCreature

-- The pose chosen for a creature (a few have their own).
function ACB.portraitPreset(entry)
    return portraitPresets[entry.id] or ACB.signaturePresentation(entry) or humanoid
end
