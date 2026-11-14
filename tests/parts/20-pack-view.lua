-- The card pack window: the list of packs, and the opening animation with its card flips.

local ZONE_CODE = ACB.pages[ACB.cards["npc:589"].page].code
local ZONE_TITLE = ACB.pages[ACB.cards["npc:589"].page].title

local function textOf(value)
    for index = #widgets, 1, -1 do
        if widgets[index].text == value then return widgets[index] end
    end
end

-- Move the animation forward in small steps, as the game's frames would.
local function run(view, seconds, step)
    step = step or 0.05
    local elapsed = 0
    while elapsed < seconds do
        view:step(step)
        elapsed = elapsed + step
    end
end

test("the window lists the packs you hold, and says so when there are none", function()
    local saved = AzerothCardBinderDB
    local keep = { saved.packs, saved.mode }
    saved.packs, saved.mode = {}, "casual"
    ACB.openPacks()
    equal(AzerothCardBinderPacks:IsShown(), true)
    assert(textOf("You have no card packs."), "an empty list says so")
    saved.packs = { [ZONE_CODE] = 2 }
    ACB.refreshSatchel()
    ACB.packView:refreshList()
    assert(textOf(("Pack: %s  /  Epic  /  x2"):format(ZONE_TITLE)), "the zone's pack is listed with its count")
    saved.packs, saved.mode = keep[1], keep[2]
    ACB.packView.frame:Hide()
end)

test("opening a pack shakes it, bursts it, deals five cards face down, and each one flips over when clicked", function()
    local saved = AzerothCardBinderDB
    local keep = { saved.packs, saved.mode, saved.casualDrops }
    saved.packs, saved.mode = { [ZONE_CODE] = 2 }, "casual"
    local view = ACB.packView
    ACB.openPacks()
    view.rows = nil
    -- Click the Open button of the only row.
    local open
    for _, widget in ipairs(widgets) do
        if widget.text == "Open" and widget:IsShown() then open = widget end
    end
    assert(open, "an Open button")
    open:OnClick()
    equal(view.phase, "shake")
    equal(saved.packs[ZONE_CODE], 1, "one pack is used up as soon as it is opened")
    equal(#view.results, 5)
    ACB.loadingScreen = true
    run(view, 2)
    equal(view.phase, "shake", "loading cannot advance a pack reveal in the background")
    equal(view.t, 0)
    ACB.loadingScreen = false
    for index, slot in ipairs(view.slots) do
        equal(slot.card.entry, view.results[index].card, "the face is prepared before the shake")
        equal(slot.holder:IsShown(), true, "shown frames can load before a flip")
        equal(slot.holder.alpha, 1, "faces can load normally behind an opaque cover")
        equal(slot.cover:IsShown(), true)
        equal(slot.card.concealed, true)
        assert(slot.cover:GetFrameLevel() > slot.card.studFrame:GetFrameLevel())
        local opaque = false
        for _, widget in ipairs(widgets) do
            if widget.parent == slot.cover and widget.fillColor and widget.fillColor[4] == 1 then opaque = true end
        end
        assert(opaque, "every face is positively covered instead of relying on parent alpha")
        assert(slot.card.art.base.texture or slot.card.art.base.colorTexture, "background requested before reveal")
        if not slot.card.entry.profession then equal(slot.card.model.creature, slot.card.entry.id) end
    end
    -- The pack shakes, then bursts, then the cards are dealt.
    run(view, 0.5)
    equal(view.phase, "shake")
    run(view, 0.6)
    equal(view.phase, "burst")
    run(view, 0.4)
    equal(view.phase, "deal")
    equal(view.slots[1].back:IsShown(), true)
    run(view, 1.2)
    equal(view.phase, "reveal")
    assert(textOf("Click a card to turn it over."), "told what to do")
    -- Nothing is shown until a card is clicked; clicking turns that one over.
    for _, slot in ipairs(view.slots) do equal(slot.state, "down") end
    view.slots[2].back:OnClick()
    equal(view.slots[2].state, "flipping")
    run(view, 0.2)
    equal(view.slots[2].back:IsShown(), true, "the back is still turning")
    equal(view.slots[2].cover:IsShown(), true)
    run(view, 0.2)
    equal(view.slots[2].back:IsShown(), false, "past halfway the face takes over")
    equal(view.slots[2].holder:IsShown(), true)
    equal(view.slots[2].holder.alpha, 1)
    equal(view.slots[2].cover:IsShown(), false)
    equal(view.slots[2].card.concealed, false)
    equal(view.slots[1].cover:IsShown(), true, "another card remains concealed until its own flip")
    run(view, 0.3)
    equal(view.slots[2].state, "up")
    local result = view.results[2]
    assert(view.slots[2].caption.text == "NEW CARD" or view.slots[2].caption.text == "SHINY!" or view.slots[2].caption.text:find("Duplicate"), view.slots[2].caption.text)
    equal(view.slots[2].card.entry, result.card)
    -- Clicking a card that is already turned over, or one that is turning, does nothing more.
    equal(view:flip(2), false)
    -- Flip all turns the rest over, one after another.
    view:flipAll()
    run(view, 3)
    equal(view:flipped(), 5)
    assert(textOf("Added to your binder."), "told they are all in")
    -- Done goes back to the list, with the other pack still there.
    view:finish()
    equal(view.phase, "list")
    assert(textOf(("Pack: %s  /  Epic  /  x1"):format(ZONE_TITLE)), "the remaining pack is listed")
    saved.packs, saved.mode, saved.casualDrops = keep[1], keep[2], keep[3]
    view.frame:Hide()
end)

test("closing the window before every card is turned over tells chat what they were", function()
    local saved = AzerothCardBinderDB
    local keep = { saved.packs, saved.mode }
    saved.packs, saved.mode = { [ZONE_CODE] = 1 }, "casual"
    local view = ACB.packView
    ACB.openPacks()
    view:openZone(ZONE_CODE)
    run(view, 3)
    equal(view.phase, "reveal")
    view.slots[1].back:OnClick()
    run(view, 1)
    local lines, realPrint = {}, print
    print = function(text) lines[#lines + 1] = text end
    view.frame:Hide() -- closing counts as finishing; the game runs OnHide, the fake one does not
    view.frame.OnHide(view.frame)
    print = realPrint
    equal(view.phase, "list")
    local joined = table.concat(lines, "\n")
    assert(joined:find("From the pack:", 1, true), joined)
    saved.packs, saved.mode = keep[1], keep[2]
end)

test("a Ranked pack with too little tape says why and keeps the pack", function()
    local saved = AzerothCardBinderDB
    local keep = { saved.packs, saved.mode }
    saved.packs, saved.mode = { [ZONE_CODE] = 1 }, "ranked"
    local view = ACB.packView
    local keepTape = ACB.sync.tape
    ACB.sync.tape = nil
    ACB.openPacks()
    view:openZone(ZONE_CODE)
    equal(view.phase, "list")
    equal(ACB.packList(saved)[1].count, 1)
    assert(textOf("A Ranked pack needs 5 roll tape entries. Ranked rolls are paused: no Ranked supply is loaded. Keep the companion open, /reload, wait for it to sync, then /reload again."), "the reason is shown")
    ACB.sync.tape = keepTape
    saved.packs, saved.mode = keep[1], keep[2]
    view.frame:Hide()
end)

test("a pack found in the game raises the button's count and tells chat", function()
    local saved = AzerothCardBinderDB
    local keep = { saved.packs, saved.mode }
    saved.packs, saved.mode = {}, "casual"
    local lines, realPrint = {}, print
    print = function(text) lines[#lines + 1] = text end
    ACB.collection:addPack(ACB.cards["npc:589"], nil)
    print = realPrint
    equal(ACB.packList(saved)[1].count, 1)
    assert(table.concat(lines, "\n"):find("Card pack found"), table.concat(lines, "\n"))
    saved.packs, saved.mode = keep[1], keep[2]
    ACB.refreshSatchel()
end)

test("face-down pack cards cannot expose tooltip names, including on a reused opening", function()
    local oldTooltip = GameTooltip
    local lines = {}
    GameTooltip = { SetOwner = ignore, AddLine = function(_, text) lines[#lines + 1] = text end, Show = ignore, Hide = ignore }
    local saved = ACB.cleanSavedData({})
    local view = ACB.createPackView(saved)
    local entry = ACB.cards['npc:589']
    local results = { { card = entry, count = 1, first = true } }
    view:start(results, ACB.pages[entry.page])
    view.slots[1].card.frame:OnEnter()
    equal(#lines, 0)
    run(view, 3)
    equal(view.slots[1].cover:IsShown(), true)
    view:flip(1); run(view, .4)
    view.slots[1].card.frame:OnEnter()
    equal(lines[1], entry.name)
    view:finish()
    lines = {}
    view:start({ { card = ACB.cards['npc:639'], count = 1, first = true } }, ACB.pages[entry.page])
    equal(view.slots[1].cover:IsShown(), true)
    view.slots[1].card.frame:OnEnter()
    equal(#lines, 0, 'previous reveal state cannot leak the next card')
    view:finish(); view.frame:Hide()
    GameTooltip = oldTooltip
end)
