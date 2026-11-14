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

test("pickup popups never allocate or load a PlayerModel", function()
    local toast, oldPopups = ACB.toast, AzerothCardBinderDB.popups
    while toast:IsShown() do toast:OnUpdate(100) end
    AzerothCardBinderDB.popups = true
    local function inToast(widget)
        while widget do
            if widget == toast then return true end
            widget = widget.parent
        end
    end
    for _, widget in ipairs(widgets) do
        if inToast(widget) then assert(widget.kind ~= "PlayerModel", "a find cannot wake the 3D renderer") end
    end
    ACB.showToast(ACB.cards["npc:639"], { first = true, count = 1 })
    equal(toast:IsShown(), true)
    local named = false
    for _, widget in ipairs(widgets) do
        if inToast(widget) and widget.text == "Edwin VanCleef" then named = true end
    end
    assert(named, "the notification still identifies the card")
    toast:OnUpdate(100)
    AzerothCardBinderDB.popups = oldPopups
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
