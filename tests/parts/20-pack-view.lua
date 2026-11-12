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
    ACB.refreshPackButton()
    assert(textOf("Packs (2)"), "the binder's button shows how many")
    ACB.packView:refreshList()
    assert(textOf(("%s Pack   x2"):format(ZONE_TITLE)), "the zone's pack is listed with its count")
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
    for index, slot in ipairs(view.slots) do
        equal(slot.card.entry, view.results[index].card, "the face is prepared before the shake")
        equal(slot.holder:IsShown(), true, "shown frames can load before a flip")
        assert(slot.holder.alpha <= 0.001, "prepared faces do not reveal the results early")
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
    run(view, 0.2)
    equal(view.slots[2].back:IsShown(), false, "past halfway the face takes over")
    equal(view.slots[2].holder:IsShown(), true)
    equal(view.slots[2].holder.alpha, 1)
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
    assert(textOf("That's all five. They are in your binder."), "told they are all in")
    -- Done goes back to the list, with the other pack still there.
    view:finish()
    equal(view.phase, "list")
    assert(textOf(("%s Pack   x1"):format(ZONE_TITLE)), "the remaining pack is listed")
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
    equal(saved.packs[ZONE_CODE], 1)
    assert(textOf("A Ranked pack needs 5 roll tape entries. Type /reload so the companion app can bring more, or switch to Casual."), "the reason is shown")
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
    equal(saved.packs[ZONE_CODE], 1)
    assert(textOf("Packs (1)"), "the count is on the button")
    assert(table.concat(lines, "\n"):find("Card pack found"), table.concat(lines, "\n"))
    saved.packs, saved.mode = keep[1], keep[2]
    ACB.refreshPackButton()
end)
