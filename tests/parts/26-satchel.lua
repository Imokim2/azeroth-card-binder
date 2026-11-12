test("pack gifts use both accepts, move one sealed pack once, and cannot spend an absent pack", function()
    local aSaved, bSaved = ACB.cleanSavedData({}), ACB.cleanSavedData({})
    aSaved.packs.DM = 2
    local aLedger, bLedger = newLedger(aSaved), newLedger(bSaved)
    aLedger:begin(true); bLedger:begin(true)
    local aCollection = ACB.newCollection(aSaved, math.random, ignore, ignore, nil, nil, aLedger)
    local bCollection = ACB.newCollection(bSaved, math.random, ignore, ignore, nil, nil, bLedger)
    local a, b
    a = ACB.newTrade(aSaved.counts, function() return 1 end, function() return "pack-gift-1" end,
        function(_, message) b:receive("alice-realm", message) return true end,
        function(give, take, peer, id) return aCollection:swap(give, take, peer, id) end, nil, nil, aSaved)
    b = ACB.newTrade(bSaved.counts, function() return 1 end, function() return "pack-gift-2" end,
        function(_, message) a:receive("bob-realm", message) return true end,
        function(give, take, peer, id) return bCollection:swap(give, take, peer, id) end, nil, nil, bSaved)
    a:start("bob-realm", "pack:DM", true)
    equal(b.session.take, "pack:DM")
    b:confirm()
    equal(aSaved.packs.DM, 2)
    equal(bSaved.packs.DM, nil)
    a:confirm()
    equal(aSaved.packs.DM, 1)
    equal(bSaved.packs.DM, 1)
    a:step(3); b:step(3)
    equal(bSaved.packs.DM, 1)
    equal(aSaved.counts["pack:DM"], nil)
    equal(bSaved.counts["pack:DM"], nil)
    assert(aLedger:verify()); assert(bLedger:verify())
    equal(aLedger and aSaved.ledger[1].kind, "tradeOut")
    equal(aSaved.ledger[1].count, 1)
    equal(bCollection:swap("pack:BDX", nil, "alice-realm", "absent"), false)
end)

test("satchel skin uses native bag chrome and custom card artwork without binding a real bag", function()
    local keepUtil, keepBag = _G.NineSliceUtil, _G.ContainerFrame1
    local layout, applied = {}, nil
    _G.ContainerFrame1 = { sentinel = true }
    _G.NineSliceUtil = {
        GetLayout = function(name) equal(name, "HeldBagLayout") return layout end,
        ApplyLayout = function(chrome, value) equal(value, layout) applied = chrome end,
    }
    local saved = ACB.cleanSavedData({ packs = { ["WF:rare"] = 2 } })
    local view = ACB.createSatchel(saved)
    view:refresh()
    equal(view.frame.nativeBagSkin, true)
    equal(view.frame.chrome, applied)
    equal(view.frame.portrait.texture, ACB.satchelIcon)
    equal(view.slots[1].icon.texture, ACB.satchelIcon)
    equal(view.slots[1].qualityBorder:IsShown(), true)
    equal(view.slots[1].qualityBorder.vertex[3], ACB.packTiers.rare.color[3])
    view.slots[1]:OnClick("LeftButton")
    equal(view.slots[1].selection:IsShown(), true)
    saved.packs = {}; view:refresh()
    equal(view.slots[1].qualityBorder:IsShown(), false)
    equal(view.slots[1].selection:IsShown(), false)
    equal(_G.ContainerFrame1.sentinel, true)
    _G.NineSliceUtil = nil
    local fallback = ACB.createSatchel(saved)
    equal(fallback.frame.nativeBagSkin, false)
    equal(fallback.frame.width, 320)
    fallback.frame.closeButton:OnClick()
    equal(fallback.frame:IsShown(), false)
    _G.NineSliceUtil, _G.ContainerFrame1 = keepUtil, keepBag
end)

test("a pack offered in a live trade stays sealed but unreserved spares can still open", function()
    local saved = ACB.cleanSavedData({})
    saved.packs.DM = 1
    local ledger = newLedger(saved); ledger:begin(true)
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, nil, nil, ledger)
    collection.packReserved = function(zone) return zone == "DM" end
    local results, why = collection:openPack("DM")
    equal(results, nil)
    assert(why:find("in your trade", 1, true))
    equal(saved.packs.DM, 1)
    equal(#saved.ledger, 0)
    saved.packs.DM = 2
    equal(#collection:openPack("DM"), 5)
    equal(saved.packs.DM, 1)
end)

test("the satchel pages every zone, shows stacks, selects a trade pack and right-clicks the existing reveal", function()
    local saved = ACB.cleanSavedData({})
    for _, page in ipairs(ACB.pages) do if page.code then saved.packs[page.code] = 2 end end
    local view = ACB.createSatchel(saved)
    local keepOpen, keepTrade = ACB.openPack, ACB.prepareTrade
    local opened, offered
    ACB.openPack = function(zone) opened = zone end
    ACB.prepareTrade = function(_, key) offered = key end
    view:refresh()
    equal(#view.slots, 24)
    equal(view.slots[1].count.text, "2")
    equal(view.controls.more.enabled, true)
    local first = view.slots[1].zone
    view.slots[1]:OnClick("LeftButton")
    equal(opened, nil)
    view.controls.offer:OnClick()
    equal(offered, "pack:" .. first)
    view.slots[1]:OnClick("RightButton")
    equal(opened, first)
    view.controls.more:OnClick()
    assert(view.slots[1].zone ~= first)
    local seen = {}
    for page = 1, 3 do
        view.page = page; view:refresh()
        for _, slot in ipairs(view.slots) do if slot.zone then assert(not seen[slot.zone]); seen[slot.zone] = true end end
    end
    local n = 0; for _ in pairs(seen) do n = n + 1 end
    equal(n, #ACB.packList(saved))
    saved.packs = {}; view:refresh()
    equal(view.controls.offer.enabled, false)
    equal(view.slots[1].zone, nil)
    ACB.openPack, ACB.prepareTrade = keepOpen, keepTrade
    view.frame:Hide()
end)

test("the trade picker finds packs and uses a sealed pack face instead of a creature card", function()
    local saved = ACB.cleanSavedData({})
    saved.packs.DM = 2
    local trade = ACB.newTrade(saved.counts, function() return 10 end, function() return "pack-ui" end,
        function() return true end, function() return true end, nil, nil, saved)
    local view = ACB.createTradeView(UIParent, saved, trade)
    view.controls.choose:OnClick()
    view.controls.search:SetText("deadmines pack")
    view.controls.search:OnTextChanged()
    equal(view.controls.rows[1].key, "pack:DM")
    view.controls.rows[1]:OnClick()
    view:refresh()
    equal(view.controls.minePack.frame:IsShown(), true)
    equal(view.controls.mine.frame:IsShown(), false)
    view.controls.partner:SetText("Harry Dexter")
    view.controls.start:OnClick()
    equal(trade.session.give, "pack:DM")
end)

test("the satchel launcher uses the keyring when available and keeps a fallback for custom bars", function()
    local keep = _G.KeyRingButton
    _G.KeyRingButton = CreateFrame("Button", nil, UIParent)
    _G.KeyRingButton:Show()
    local saved = ACB.cleanSavedData({})
    local view = ACB.initSatchel(saved)
    equal(AzerothCardBinderSatchelButton.point[2], _G.KeyRingButton)
    AzerothCardBinderSatchelButton:OnClick()
    equal(view.frame:IsShown(), true)
    _G.KeyRingButton = nil
    AzerothCardBinderSatchelButton:OnEvent()
    equal(AzerothCardBinderSatchelButton.point[2], UIParent)
    _G.KeyRingButton = keep
    view.frame:Hide()
end)
