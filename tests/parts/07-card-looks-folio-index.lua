test("a finished set shows its own pop-up with the title", function()
    local toast = ACB.toast
    if toast:IsShown() then toast.OnUpdate(toast, 100) end
    equal(toast:IsShown(), false)
    ACB.showSetToast(ACB.pages[2], "Westfall Warden")
    equal(toast:IsShown(), true)
    toast.OnUpdate(toast, 100)
    equal(toast:IsShown(), false)
    AzerothCardBinderDB.popups = false
    ACB.showSetToast(ACB.pages[2], "Westfall Warden")
    equal(toast:IsShown(), false)
    AzerothCardBinderDB.popups = nil
end)

test("card studs follow the rarity colour, sit above the text, and the serial number shows", function()
    local card = ACB.createCard(UIParent)
    card:set(ACB.cards["npc:639"], 1) -- legendary
    local legendary, epic = ACB.rarities.legendary.color, ACB.rarities.epic.color
    equal(#card.studs, 4)
    for _, stud in ipairs(card.studs) do
        equal(stud.vertex[1], legendary[1])
        equal(stud.vertex[2], legendary[2])
        equal(stud.vertex[3], legendary[3])
    end
    assert(card.studFrame.level > card.textBox.level, "studs sit above the text box")
    assert(card.studFrame.level > card.badges.level + 1, "studs sit above the name and count badges")
    equal(card.serial.text, "No. 000639")
    card:set(ACB.cards["npc:573"], 1) -- epic
    equal(card.studs[3].vertex[1], epic[1])
    equal(card.serial.text, "No. 000573")
    card:set(ACB.cards["node:1731"], 1)
    equal(card.serial.text, "No. N01731")
    card:set(ACB.cards["npc:639"], 0) -- missing cards use the same muted finish on the studs and gem
    for channel = 1, 3 do equal(card.studs[1].vertex[channel], card.gem.vertex[channel]) end
    assert(card.studs[1].vertex[1] < legendary[1])
    equal(card.serial.text, "No. 000639")
end)

test("sets are listed by level, then by name", function()
    local order = ACB.setOrder()
    equal(#order, #ACB.pages)
    local last, position = 0, {}
    for place, index in ipairs(order) do
        local page = ACB.pages[index]
        local low = page.levelMid or 1000
        assert(low >= last, page.title .. " is out of level order")
        last = low
        position[page.zone] = place
    end
    assert(position["elwynn-forest"] < position["deadmines"], "level 1 zones come before dungeons")
    assert(position["deadmines"] < position["blackrock-depths"])
    assert(position["westfall"] < position["blackrock-depths"])
    assert(position["blackrock-depths"] < position["molten-core"], "raids come last")
    -- Set numbers are untouched by the listing order.
    equal(ACB.pages[1].title, "Deadmines")
    equal(ACB.pages[2].title, "Westfall")
end)

test("owned cards show rarity tint and the moving foil only plays for shiny copies", function()
    local card = ACB.createCard(UIParent)
    card:set(ACB.cards["npc:639"], 1, true)
    equal(card.foil:IsShown(), true)
    equal(card.tint:IsShown(), true)
    local band
    for _, widget in ipairs(widgets) do
        if widget.parent == card.foil and widget.width and widget.height then band = widget end
    end
    assert(band)
    card.foil:OnUpdate(0.5)
    assert(band.point[4] > 0 and band.point[4] + band.width < card.model.width)
    assert(band.alpha > 0)
    card.foil:OnUpdate(1.5)
    equal(band.alpha, 0)
    card:set(ACB.cards["npc:639"], 1, false)
    equal(card.foil:IsShown(), false)
    equal(card.tint:IsShown(), true)
    card:set(ACB.cards["npc:639"], 0, true)
    equal(card.foil:IsShown(), false)
    equal(card.tint:IsShown(), false)
end)

test("pop-ups queue, fade away, play a sound and can be turned off", function()
    local saved = AzerothCardBinderDB
    local played = {}
    PlaySound = function(id) played[#played + 1] = id end
    SOUNDKIT = { UI_EPICLOOT_TOAST = 11, UI_LEGENDARY_LOOT_TOAST = 22, IG_QUEST_LIST_COMPLETE = 33 }
    local toast = ACB.toast
    equal(toast:IsShown(), false)
    ACB.showToast(ACB.cards["npc:589"], { count = 1, first = true, shiny = true })
    equal(toast:IsShown(), true)
    equal(played[1], 22) -- a shiny always gets the top sound
    ACB.showToast(ACB.cards["npc:589"], { count = 2 })
    equal(#played, 1) -- the second waits its turn
    clock = clock + 10 -- the sound clock advances with the simulated toast animation
    toast.OnUpdate(toast, 10)
    equal(toast:IsShown(), true)
    equal(played[2], 33) -- common cards use the plainest sound
    toast.OnUpdate(toast, 10)
    equal(toast:IsShown(), false)
    saved.popups = false
    ACB.showToast(ACB.cards["npc:639"], { first = true })
    equal(toast:IsShown(), false)
    saved.popups = nil
    SlashCmdList.AZEROTHCARDBINDER("popup test")
    equal(toast:IsShown(), true)
    toast.OnUpdate(toast, 10)
    PlaySound, SOUNDKIT = nil, nil
    equal(ACB.playToastSound("epic", false), nil) -- no sound system, nothing breaks
end)

test("cinematic detail sways, pauses for dragging and keeps the combat pose", function()
    local card = ACB.createCard(UIParent, true, ignore)
    card:set(ACB.cards["npc:639"], 0)
    equal(card.model.creature, 639)
    equal(card.model:IsShown(), true)
    equal(card.owned, 0)
    equal(card.model.frozen, nil)
    equal(card.art.base.texture, ACB.folioArt .. "Deadmines.tga")
    equal(card.art.base.desaturated, true)
    equal(card.veil:IsShown(), true)
    card.model.desaturation = nil -- Simulate the client completing a new load.
    card.model.fileID, card.model.supportedAnimation = 1000, 17
    card.model:OnModelLoaded()
    equal(card.model.desaturation, 1)
    equal(card.model.frozen[1], 17)
    equal(card.model.frozen[3], 24)
    local humanoidZoom = card.model.portraitZoom
    local defaultFacing = card.model.facing
    equal(defaultFacing, -0.47)
    card.frame:OnUpdate(2)
    local swing = card.model.facing - defaultFacing
    assert(swing > 0 and swing < math.rad(10))
    card.frame:OnUpdate(4)
    assert(math.abs(card.model.facing - (defaultFacing - swing)) < 0.0001)
    card.frame:OnUpdate(2)
    equal(card.model.facing, defaultFacing)

    card.model.mouseOver = false
    leftDown = true
    card.frame:OnMouseDown("LeftButton")
    cursorX = cursorX + 40
    card.frame:OnUpdate(0)
    equal(card.model.facing, defaultFacing)
    cursorX = cursorX - 40
    card.model.mouseOver = true
    card.frame:OnMouseDown("LeftButton")
    cursorX = cursorX + 40
    card.frame:OnUpdate(2)
    assert(math.abs(card.model.facing - 0.53) < 0.0001)
    equal(card.model.frozen[3], 24)
    leftDown = false
    cursorX = cursorX - 40
    card.frame:OnUpdate(2)
    assert(math.abs(card.model.facing - (0.53 + swing)) < 0.0001)

    card:set(ACB.cards["npc:573"], 0)
    card.model.fileID, card.model.supportedAnimation = 1001, nil
    card.model:OnModelLoaded()
    equal(card.model.frozen[1], 0)
    equal(card.model.facing, -0.34)
    assert(card.model.portraitZoom < humanoidZoom)
    equal(card.art.base.texture, ACB.folioArt .. "Westfall.tga")

    card:set(ACB.cards["node:1618"], 0)
    equal(card.model.fileID, ACB.cards["node:1618"].model)
    equal(card.model.frozen, nil)
    equal(card.node:IsShown(), false)
    equal(card.art.base.texture, ACB.folioArt .. "Elwynn.tga")
    card.frame:OnUpdate(2)
    assert(card.model.facing > 0.6)

    for _, entry in ipairs(ACB.pages[3].cards) do
        if not entry.model then
            card:set(entry, 0)
            equal(card.node:IsShown(), true)
            equal(card.node.desaturated, true)
            card.frame:OnUpdate(2)
            equal(card.model.facing, 0.6)
            card:set(entry, 1)
            equal(card.node:IsShown(), true)
            equal(card.node.desaturated, false)
            equal(card.veil:IsShown(), false)
            break
        end
    end

    local pocket = ACB.createCard(UIParent, false)
    pocket.art.base.rejectTexture = true
    pocket:set(ACB.cards["npc:639"], 0)
    equal(pocket.model:IsShown(), false)
    equal(pocket.model.creature, nil)
    equal(pocket.art.base.colorTexture, true)
end)

test("folio pages through all Deadmines cards and remembers selection per region", function()
    local function widgetWithText(value)
        for _, widget in ipairs(widgets) do
            if widget.text == value then return widget end
        end
        error("missing widget: " .. value)
    end
    local leaves = math.ceil(#ACB.pages[1].cards / 4)
    local westfallLeaves = math.ceil(#ACB.pages[2].cards / 4)
    assert(leaves >= 3, "Deadmines has at least the eight bosses and four mobs")
    AzerothCardBinderDB.counts["npc:639"] = 2
    ACB.open(1)
    local back = widgetWithText("< Back")
    local nextPage = widgetWithText("Next >")
    equal(back.enabled, false)
    widgetWithText("Page 1 of " .. leaves)
    nextPage:OnClick()
    widgetWithText("Page 2 of " .. leaves)
    widgetWithText("2 owned / 1 spare").parent:OnClick()
    widgetWithText("SELECTED CARD  /  DM 08")
    ACB.open(2)
    equal(nextPage.enabled, westfallLeaves > 1)
    widgetWithText("Page 1 of " .. westfallLeaves)
    ACB.open(1)
    widgetWithText("SELECTED CARD  /  DM 08")
    for _ = 1, leaves - 2 do nextPage:OnClick() end
    widgetWithText("Page " .. leaves .. " of " .. leaves)
    equal(nextPage.enabled, false)
    AzerothCardBinderDB.counts["npc:639"] = nil
end)

test("index searches categories and opens sets beyond the original tabs", function()
    local function findWidget(matches)
        for _, widget in ipairs(widgets) do
            if matches(widget) then return widget end
        end
        error("matching widget was not drawn")
    end
    local function button(label)
        return findWidget(function(widget) return widget.text == label and widget.OnClick end)
    end
    local function indexRow(title)
        local label = findWidget(function(widget)
            return widget.text == title and widget.parent and widget.parent.setIndex
        end)
        return label.parent
    end
    local base = #ACB.pages
    for index = 1, 9 do
        ACB.pages[base + index] = { title = ("Test Set %02d"):format(index + 3), group = "Dungeon",
            subtitle = "", cards = ACB.pages[2].cards }
    end

    button("Index"):OnClick()
    equal(button("More").enabled, true)
    local search = findWidget(function(widget) return widget.OnTextChanged ~= nil end)
    search:SetText("Test Set")
    search:OnTextChanged()
    equal(button("More").enabled, true)
    button("More"):OnClick()
    equal(indexRow("Test Set 12"):IsShown(), true)
    indexRow("Test Set 12"):OnClick()
    equal(button("Collection").enabled, false)
    button("Trade"):OnClick()
    equal(ACB.tradeView:IsShown(), true)
    equal(AzerothCardBinderWindow:IsShown(), false)
    button("Collection"):OnClick()
    findWidget(function(widget) return widget.text == ("SELECTED CARD  /  SET %02d 01"):format(base + 9) end)

    SlashCmdList.AZEROTHCARDBINDER("index")
    search = findWidget(function(widget) return widget.OnTextChanged ~= nil end)
    search:SetText(" ZoNe ")
    search:OnTextChanged()
    equal(button("More").enabled, true) -- many zones, listed over several pages
    search:SetText("Westfall")
    search:OnTextChanged()
    equal(indexRow("Westfall"):IsShown(), true)
    search:SetText("%")
    search:OnTextChanged()
    findWidget(function(widget) return widget.text == "No matching sets or cards" end)
    search:SetText(" eDwin VaNcleef ")
    search:OnTextChanged()
    local cardRow = findWidget(function(widget) return widget.cardKey == "npc:639" end)
    equal(cardRow:IsShown(), true)
    cardRow:OnClick()
    findWidget(function(widget) return widget.text == "SELECTED CARD  /  DM 08" end)
    SlashCmdList.AZEROTHCARDBINDER("index")
    search:SetText("Test Set 04")
    search:OnTextChanged()
    indexRow("Test Set 04"):OnClick()
    equal(button("Trade").enabled, true)
    findWidget(function(widget) return widget.text == ("SELECTED CARD  /  SET %02d 01"):format(base + 1) end)
    search:SetText("")
    search:OnTextChanged()
    for index = #ACB.pages, base + 1, -1 do ACB.pages[index] = nil end
    ACB.open(1)
end)

test("minimap launcher toggles the fitted window and saves its drag position", function()
    local window = AzerothCardBinderWindow
    local launcher = AzerothCardBinderMinimapButton
    equal(launcher.parent, Minimap)
    window:Hide()
    UIParent.width = 776
    launcher:OnClick()
    equal(window:IsShown(), true)
    assert(window.scale < 1)
    launcher:OnClick()
    equal(window:IsShown(), false)
    launcher:OnDragStart()
    launcher:OnUpdate()
    launcher:OnDragStop()
    equal(launcher.OnUpdate, nil)
    equal(AzerothCardBinderDB.minimapAngle, 90)
    equal(launcher.point[5], 73)
    UIParent.width = 1200
end)

test("a portrait assigned on a hidden page retries on show and tolerates a missed load callback", function()
    local card = ACB.createCard(UIParent, true)
    local entry = ACB.cards["npc:639"]
    card:set(entry, 1)
    card.model.creature, card.model.fileID = nil, nil
    card.model:OnShow()
    equal(card.model.creature, entry.id, "visibility retries an unstarted request")
    card.model.creature = nil
    card.model:OnUpdate(1.1)
    equal(card.model.creature, entry.id, "a slow request gets a bounded retry")
    card.model.fileID, card.model.supportedAnimation = 12345, 17
    card.model:OnUpdate(1.1)
    equal(card.model.frozen[1], 17, "polling applies the pose if the callback was missed")
    card.model.creature = nil
    card.model:OnUpdate(10)
    equal(card.model.creature, nil, "a loaded portrait is never requested again by the watcher")
end)

test("portrait warming retries failed models once, deduplicates editions and retains successful loads", function()
    local start = #widgets
    local warm = ACB.createPortraitLoader(UIParent, UIParent)
    local driver = widgets[start + 1]
    warm({ ACB.cards["npc:639"], ACB.cards["edition:6391"], ACB.cards["npc:573"] })
    driver:OnUpdate(.1)
    equal(#driver.models, 2, "editions share their creature resource")
    local loaded, unavailable = driver.models[1], driver.models[2]
    loaded.fileID = 12345
    driver:OnUpdate(.3)
    equal(loaded:IsShown(), false)
    equal(loaded.fileID, 12345)
    driver:OnUpdate(3.1)
    equal(unavailable.retried, true)
    equal(unavailable:IsShown(), true)
    driver:OnUpdate(3.1)
    equal(driver:IsShown(), false)
    equal(loaded.fileID, 12345)
end)
