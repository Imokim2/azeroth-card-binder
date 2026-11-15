test("hidden cards do not request models and release their resources when hidden again", function()
    local parent = CreateFrame("Frame", nil, UIParent)
    parent:Hide()
    local card = ACB.createCard(parent, true, ignore)
    card:set(ACB.cards["npc:639"], 1)
    card.model:OnShow()
    card.model:OnUpdate(3)
    equal(card.model.creature, nil, "hidden ancestors block requests and retries")
    equal(card.model.keepModel, false)
    parent:Show()
    card.model:OnShow()
    equal(card.model.creature, 639)
    card.model.fileID = 12345
    card.model:OnModelLoaded()
    card.model:OnUpdate(.21)
    parent:Hide()
    card.model:OnHide() -- the game sends this to children when their parent hides
    equal(card.model.creature, nil)
    equal(card.model.fileID, nil)
    equal(card.modelLoadedFor, nil)
    card.model:OnUpdate(5)
    equal(card.model.creature, nil)
    parent:Show()
    card.model:OnShow()
    equal(card.model.creature, 639, "opening the window restores its portrait")
    parent:Hide(); card.model:OnHide()
end)

test("portrait preloading never grows its engine frame pool as larger sets are visited", function()
    local start = #widgets
    local warm = ACB.createPortraitLoader(UIParent, UIParent)
    local driver = widgets[start + 1]
    local entries, unique = {}, {}
    for _, page in ipairs(ACB.pages) do for _, card in ipairs(page.cards) do
        if not card.profession and not unique[card.id] and #entries < 200 then
            unique[card.id], entries[#entries + 1] = true, card
        end
    end end
    assert(#entries == 200)
    local seen = {}
    local function finishQueue()
        local ticks = 0
        while driver:IsShown() and ticks < 300 do
            driver:OnUpdate(.25)
            assert(#driver.models <= ACB.portraitLoaderLimit)
            for _, model in ipairs(driver.models) do
                if model.active then seen[model.entry.id] = true; model.fileID = model.entry.id + 10000 end
            end
            ticks = ticks + 1
        end
        assert(not driver:IsShown(), "the entire queue must finish within a bounded number of ticks")
    end
    warm(entries); finishQueue()
    equal(ACB.countKeys(seen), 200, "every unique NPC is still requested")
    equal(#driver.models, 4)
    local allocated = #widgets
    warm({ entries[2], entries[3] }); finishQueue()
    warm(entries); finishQueue()
    equal(#widgets, allocated, "reopening different sets cannot allocate additional engine frames")
    warm(nil)
    for _, model in ipairs(driver.models) do
        equal(model.creature, nil); equal(model.fileID, nil); equal(model.active, false)
    end
end)

test("pickup popups follow the 3D setting and release their model when dismissed", function()
    local toast, oldPopups = ACB.toast, AzerothCardBinderDB.popups
    local saved, oldModels = AzerothCardBinderDB, AzerothCardBinderDB.cardModels
    while toast:IsShown() do toast:OnUpdate(100) end
    AzerothCardBinderDB.popups = true
    local function inToast(widget)
        while widget do
            if widget == toast then return true end
            widget = widget.parent
        end
    end
    local model
    for _, widget in ipairs(widgets) do if inToast(widget) and widget.kind == "PlayerModel" then model = widget end end
    assert(model)
    ACB.setSetting(saved, "cardModels", true)
    ACB.showToast(ACB.cards["npc:639"], { first = true, count = 1 })
    equal(toast:IsShown(), true)
    model:OnShow() -- the game sends this after the toast's hidden parent is shown
    equal(model.creature, 639)
    equal(model.keepModel, false)
    ACB.setSetting(saved, "cardModels", false)
    equal(model.creature, nil)
    equal(model:IsShown(), false)
    equal(toast:IsShown(), true, "the 2D setting does not suppress the notification")
    ACB.setSetting(saved, "cardModels", true)
    model:OnShow()
    equal(model.creature, 639, "turning models back on restores the active popup")
    local named = false
    for _, widget in ipairs(widgets) do
        if inToast(widget) and widget.text == "Edwin VanCleef" then named = true end
    end
    assert(named, "the notification still identifies the card")
    toast:OnUpdate(100)
    model:OnHide()
    equal(model.creature, nil)
    equal(model.fileID, nil)
    ACB.setSetting(saved, "cardModels", oldModels ~= false)
    saved.cardModels = oldModels
    AzerothCardBinderDB.popups = oldPopups
end)

test("pickup popups wait through loading and taxi travel without losing queued finds", function()
    local toast, saved = ACB.toast, AzerothCardBinderDB
    local oldPopups, oldModels = saved.popups, saved.cardModels
    saved.popups = true
    while toast:IsShown() do toast:OnUpdate(100) end
    local model
    for _, widget in ipairs(widgets) do
        if widget.kind == "PlayerModel" then
            local parent = widget.parent
            while parent and parent ~= toast do parent = parent.parent end
            if parent == toast then model = widget end
        end
    end
    ACB.setSetting(saved, "cardModels", true)
    emit("PLAYER_LEAVING_WORLD"); emit("LOADING_SCREEN_ENABLED")
    ACB.showToast(ACB.cards["npc:639"], { count = 1 })
    ACB.showToast(ACB.cards["npc:589"], { count = 1 })
    equal(toast:IsShown(), false)
    model:OnShow(); model:OnUpdate(10); toast:OnUpdate(100)
    equal(model.creature, nil)
    emit("PLAYER_ENTERING_WORLD")
    equal(toast:IsShown(), false)
    emit("LOADING_SCREEN_DISABLED")
    equal(toast:IsShown(), true)
    model:OnShow()
    equal(model.creature, 639, "the first find resumes after loading")
    toast:OnEnter() -- hiding a hovered popup must not leave it paused after travel
    ACB.setModelWorldState("onTaxi", true)
    equal(toast:IsShown(), false)
    equal(model.creature, nil)
    toast:OnUpdate(100)
    ACB.setModelWorldState("onTaxi", false)
    model:OnShow()
    equal(model.creature, 639, "travel does not consume the popup's visible lifetime")
    toast:OnUpdate(100)
    model:OnShow()
    equal(model.creature, 589, "the queued second find follows")
    toast:OnUpdate(100); model:OnHide()
    equal(toast:IsShown(), false)
    ACB.setSetting(saved, "cardModels", false)
    ACB.showToast(ACB.cards["npc:639"], { count = 1 })
    equal(toast:IsShown(), true)
    equal(model:IsShown(), false)
    toast:OnUpdate(100)
    ACB.setSetting(saved, "cardModels", oldModels ~= false)
    saved.popups, saved.cardModels = oldPopups, oldModels
end)

test("world transitions release both displayed and retained warming models", function()
    local card = ACB.createCard(UIParent, true)
    card:set(ACB.cards["npc:639"], 1)
    local start = #widgets
    local warm = ACB.createPortraitLoader(UIParent, UIParent)
    local driver = widgets[start + 1]
    warm({ ACB.cards["npc:589"], ACB.cards["npc:573"] })
    driver:OnUpdate(.1)
    driver.models[1].fileID = 1111
    driver:OnUpdate(.3)
    equal(driver.models[1].fileID, 1111)
    emit("PLAYER_LEAVING_WORLD")
    equal(card.model.creature, nil)
    for _, model in ipairs(driver.models) do
        equal(model.creature, nil); equal(model.fileID, nil); equal(model.active, false)
    end
    emit("LOADING_SCREEN_ENABLED")
    card.model:OnUpdate(10)
    equal(card.model.creature, nil)
    emit("PLAYER_ENTERING_WORLD")
    equal(card.model.creature, nil)
    emit("LOADING_SCREEN_DISABLED")
    card.model:OnShow()
    equal(card.model.creature, 639)
    warm(nil)
end)

test("taxi travel and the 2D setting prevent model loads without changing ownership", function()
    local oldTaxi, oldSetting = UnitOnTaxi, AzerothCardBinderDB.cardModels
    local saved = AzerothCardBinderDB
    local counts, events, dust, packs = saved.counts, saved.events, saved.dust, saved.packs
    local card = ACB.createCard(UIParent, true)
    card:set(ACB.cards["npc:639"], 1)
    UnitOnTaxi = function() return true end
    eventFrame:OnUpdate(.3)
    equal(card.model.creature, nil)
    card:set(ACB.cards["npc:589"], 1)
    card.model:OnShow(); card.model:OnUpdate(10)
    equal(card.model.creature, nil)
    equal(card.node:IsShown(), true)
    UnitOnTaxi = function() return false end
    eventFrame:OnUpdate(.3)
    card.model:OnShow()
    equal(card.model.creature, 589)
    equal(ACB.setSetting(saved, "cardModels", false), true)
    equal(card.model.creature, nil)
    card:set(ACB.cards["npc:573"], 1)
    card.model:OnShow(); card.model:OnUpdate(10)
    equal(card.model.creature, nil)
    equal(card.node:IsShown(), true)
    equal(saved.counts, counts); equal(saved.events, events); equal(saved.dust, dust); equal(saved.packs, packs)
    ACB.setSetting(saved, "cardModels", true)
    card.model:OnShow()
    equal(card.model.creature, 573)
    saved.cardModels, UnitOnTaxi = oldSetting, oldTaxi
end)

test("model-loaded callbacks do not run pose setters inside an engine load callback", function()
    local card = ACB.createCard(UIParent, true)
    local loading, poses = false, 0
    card.model.SetCreature = function(self, id)
        self.creature = id
        loading = true
        self:OnModelLoaded()
        equal(poses, 0, "the callback only marks readiness")
        loading = false
    end
    card.model.FreezeAnimation = function()
        assert(not loading, "poses must wait until the engine load call returns")
        poses = poses + 1
    end
    card:set(ACB.cards["npc:639"], 1)
    assert(poses > 0, "the pose is still applied outside the callback")
end)
