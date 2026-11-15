local _, ACB = ...
local safe = ACB.safe

-- Model frames belong to visible windows, never to the background collection.
-- In particular, release engine resources before a world transition, not just
-- the Lua work that would otherwise run during it.
local modelUsers = {}
function ACB.registerCardModels(owner, release, refresh)
    modelUsers[owner] = { release = release, refresh = refresh }
end

function ACB.cardModelsEnabled()
    return not ACB.modelSettings or ACB.modelSettings.cardModels ~= false
end

function ACB.modelTransition()
    return ACB.worldChanging or ACB.loadingScreen or ACB.onTaxi
end

function ACB.modelsBlocked()
    return not ACB.cardModelsEnabled() or ACB.modelTransition()
end

function ACB.releaseCardModels()
    for _, user in pairs(modelUsers) do user.release() end
end

function ACB.refreshCardModels()
    for _, user in pairs(modelUsers) do if user.refresh then user.refresh() end end
end

function ACB.setModelWorldState(key, on)
    ACB[key] = on
    if on then ACB.releaseCardModels() end
    if not ACB.modelsBlocked() then ACB.refreshCardModels(); if ACB.refresh then ACB.refresh() end end
    if ACB.refreshToast then ACB.refreshToast() end
end

local taxiElapsed = 0
function ACB.updateModelTravel(elapsed)
    taxiElapsed = taxiElapsed + elapsed
    if not ACB.modelSettings or taxiElapsed < .25 then return end
    taxiElapsed = 0
    local onTaxi = ACB.read(safe(UnitOnTaxi, "player"), "boolean") == true
    if onTaxi ~= (ACB.onTaxi == true) then ACB.setModelWorldState("onTaxi", onTaxi) end
end

function ACB.createPortraitModel(window, inner, level, useModels)
    -- Callers can opt for a plain layout anchor without an engine model.
    local model = CreateFrame(useModels and "PlayerModel" or "Frame", nil, window)
    model:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    model:SetSize(inner.width, inner.height)
    model:SetFrameLevel(level + 3)
    model:EnableMouse(false) -- dragging and links belong to the card
    if useModels then safe(model.SetKeepModelOnHide, model, false) end
    return model
end

function ACB.bindCardModel(card, useModels, update, canLoad, release)
    if not useModels then return function() end end
    card.model:SetScript("OnHide", release)
    ACB.registerCardModels(card, function() card.model:Hide(); release() end, function()
        if card.entry then card:set(card.entry, card.owned, card.shiny, card.wantedFlag) end
    end)
    return ACB.watchCardModel(card, update, canLoad)
end

function ACB.createPortraitFallback(window, model, inner, level)
    local fallback = CreateFrame("Frame", nil, window)
    fallback:SetAllPoints(model)
    fallback:SetFrameLevel(level + 3)
    local icon = fallback:CreateTexture(nil, "ARTWORK")
    icon:SetSize(inner.width * 0.42, inner.width * 0.42)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return icon
end

-- Putting a creature or object model into a card's portrait window: which way it faces, how close the camera
-- is, and which animation frame it is frozen on. Every game call is optional and guarded.

-- AnimationData IDs. Use the neutral frame when a model lacks its assigned combat animation.
local STAND, ATTACK_UNARMED, ATTACK_ONE_HAND, READY_UNARMED, READY_TWO_HAND, SPELL_CAST = 0, 16, 17, 25, 27, 32
local humanoid = { zoom = 0.08, facing = -0.40, animation = READY_UNARMED, frame = 12 }
local wide = { zoom = 0, facing = -0.34, animation = ATTACK_UNARMED, frame = 20 }
local portraitPresets = {
    [639] = { zoom = 0.12, facing = -0.47, animation = ATTACK_ONE_HAND, frame = 24 }, -- Edwin VanCleef
    [589] = { zoom = 0.10, facing = 0.36, animation = SPELL_CAST, frame = 20 }, -- Defias Pillager
    [646] = { zoom = 0, facing = -0.42, animation = READY_TWO_HAND, frame = 12 }, -- Mr. Smite
    [644] = wide, -- Rhahk'Zor
    [645] = wide, -- Cookie
    [642] = wide, -- Sneed's Shredder
    [114] = wide, -- Harvest Watcher
    [573] = wide, -- Foe Reaper 4000
}

-- These hunched models need room above the shoulders. Keep this artwork-only:
-- editions inherit the lift without losing their separately authored action/crop.
local postureLift = {}
for _, id in ipairs({ 1057, 1034, 1035, 1036, 1037, 1038, 2102, 2103,
    435, 436, 437, 440, 485, 615, 4064, 4065, 4462, 4463, 4464,
    7025, 7026, 7027, 7028, 7029 }) do postureLift[id] = .12 end
for _, id in ipairs({ 11382, 14507, 11356, 14826, 11390, -- reported Zul'Gurub trolls
    781, 782, 783, 784, 669, 670, 672, -- Skullsplitter tribe
    587, 588, 595, 597, 660, 671, 694, 697, 699, 701, 702,
    11350, 11351, 11353, 11355, 11389, 14750 }) do postureLift[id] = .18 end

function ACB.cardModelReady(card, model)
    local file = ACB.read(safe(model.GetModelFileID, model), "number")
    if card.entry.profession then return file and file > 0 and file == card.entry.model end
    -- OnModelLoaded is authoritative even when the client's file ID is unavailable.
    return (file and file > 0) or card.modelLoadedFor == card.modelFor
end

local function loadModel(model, entry)
    if ACB.modelsBlocked() or not model:IsVisible() then return end
    if entry.profession then
        if entry.model then safe(model.SetModel, model, entry.model) end
    else
        safe(model.SetCreature, model, entry.id)
    end
end

-- Reuse at most four engine model frames per folio, regardless of set size.
-- ClearModel does not destroy its PlayerModel frame; render-target lifetime is
-- engine-managed. Creating one frame per NPC made scene allocation grow with
-- the largest visited set. Keep only the workers' most recent scenes cached.
ACB.portraitLoaderLimit = 4
function ACB.createPortraitLoader(parent, paper)
    local driver = CreateFrame("Frame", nil, parent)
    driver.acbPortraitLoader, driver.models = true, {}
    driver:SetAllPoints(parent)
    driver:SetFrameLevel(parent:GetFrameLevel())
    driver:Hide()
    local source, queue, nextSlot, active = nil, {}, 1, 0
    local function release()
        driver:Hide()
        source, queue, nextSlot, active = nil, {}, 1, 0
        for _, model in ipairs(driver.models) do
            model.active, model.entry, model.job = false, nil, nil
            model:Hide()
            safe(model.ClearModel, model)
        end
    end
    ACB.registerCardModels(driver, release)
    local function ready(model)
        local file = ACB.read(safe(model.GetModelFileID, model), "number")
        return file and file > 0 and (not model.entry.profession or file == model.entry.model)
    end
    local function idleModel()
        local spare
        for _, model in ipairs(driver.models) do
            if not model.active then
                if not model.entry then return model end
                spare = spare or model
            end
        end
        if #driver.models >= ACB.portraitLoaderLimit then return spare end
        local model = CreateFrame("PlayerModel", nil, driver)
        model:SetSize(128, 104)
        model:SetPoint("CENTER", paper)
        model:SetFrameLevel(parent:GetFrameLevel())
        safe(model.SetKeepModelOnHide, model, true)
        driver.models[#driver.models + 1] = model
        return model
    end
    local function request(model, job)
        safe(model.ClearModel, model)
        model.entry, model.job, model.retried = job.entry, job, job.retried
        model.age, model.active = 0, true
        active = active + 1
        model:Show()
        loadModel(model, model.entry)
    end
    driver:SetScript("OnUpdate", function(_, elapsed)
        if ACB.modelsBlocked() or not parent:IsVisible() then release() return end
        for _, model in ipairs(driver.models) do
            if model.active then
                model.age = model.age + elapsed
                local loaded = ready(model)
                if (loaded and model.age >= .2) or model.age >= 3 then
                    model.active = false
                    active = active - 1
                    model:Hide()
                    if not loaded then
                        if not model.job.retried then
                            model.job.retried = true
                            queue[#queue + 1] = model.job
                        end
                        model.entry = nil
                        safe(model.ClearModel, model)
                    end
                end
            end
        end
        while active < ACB.portraitLoaderLimit and nextSlot <= #queue do
            local model = idleModel()
            if not model then break end
            local job = queue[nextSlot]
            nextSlot = nextSlot + 1
            request(model, job)
        end
        if active == 0 and nextSlot > #queue then driver:Hide() end
    end)
    return function(entries)
        if not entries or ACB.modelsBlocked() or not parent:IsVisible() then release() return end
        if source == entries and entries then
            if nextSlot <= #queue or active > 0 then
                driver:Show()
                for _, model in ipairs(driver.models) do if model.active then model:Show() end end
            end
            return
        end
        release()
        source, queue, nextSlot, active = entries, {}, 1, 0
        local seen = {}
        for _, entry in ipairs(entries) do
            local key = entry.profession and entry.model or ("npc:" .. entry.id)
            if key and not seen[key] then
                seen[key] = true
                queue[#queue + 1] = { entry = entry, retried = false }
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
        return ACB.cardModelReady(card, model)
    end
    safe(card.model.SetScript, card.model, "OnModelLoaded", function(model)
        if ACB.modelsBlocked() or not model:IsVisible() or not canLoad() then return end
        if not card.entry or card.entry.key ~= card.modelFor then return end
        card.modelLoadedFor = card.modelFor
        -- The engine can deliver this callback inside SetCreature/SetModel.
        -- Camera and animation setters run on a later UI tick instead.
        elapsed, passes, settled = 0, 0, false
    end)
    local function resume(model)
        elapsed, attempts, key, settled, passes = 0, 0, card.modelFor, false, 0
        if ACB.modelsBlocked() or not model:IsVisible() or not card.entry or card.entry.key ~= card.modelFor or not canLoad() then return end
        if not ready(model) then loadModel(model, card.entry) end
        update(model)
    end
    card.model:SetScript("OnShow", resume)
    card.model:SetScript("OnUpdate", function(model, dt)
        if ACB.modelsBlocked() or not model:IsVisible() then return end
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
    if ACB.modelsBlocked() or not model:IsVisible() then return false end
    presentation = presentation or ACB.cardPresentation(entry)
    local preset = presentation.pose
    safe(model.SetPaused, model, false)
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
    if supported and animate and presentation.animated and (not preset.loopPrimaryOnly or animation == preset.animation)
        and type(model.SetAnimation) == "function" then
        safe(model.SetPaused, model, false)
        playing = pcall(model.SetAnimation, model, animation, 0)
    end
    if not playing then
        local frame = animation ~= preset.animation and preset.fallbackFrame or preset.frame
        if not (supported and pcall(model.FreezeAnimation, model, animation, 0, frame)) then
            animation = STAND
            if not pcall(model.FreezeAnimation, model, STAND, 0, 0) then safe(model.SetPaused, model, true) end
        end
    end
    -- Do not select the model's built-in face camera: hunched models can put only
    -- their hair in view, and a fixed camera can ignore the model's facing.
    -- PortraitZoom selects the normal adjustable camera; clear any old transform.
    safe(model.ClearTransform, model)
    safe(model.SetCamDistanceScale, model, 1.05)
    if not pcall(model.SetPortraitZoom, model, preset.zoom) then safe(model.SetCamDistanceScale, model, .8) end
    safe(model.SetPosition, model, preset.x or 0, preset.y or 0, (preset.z or -.05) + (postureLift[entry.id] or 0))
    safe(model.SetFacing, model, facing)
    return playing, animation
end

ACB.loadCardModel, ACB.setModelFinish, ACB.poseCreature = loadModel, setModelFinish, poseCreature

-- The pose chosen for a creature (a few have their own).
function ACB.portraitPreset(entry)
    return portraitPresets[entry.id] or (entry.critter and wide) or ACB.signaturePresentation(entry) or humanoid
end
