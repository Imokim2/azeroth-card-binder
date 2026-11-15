local function withDungeonHints(check)
    local oldGUID, oldName, oldPlayer = UnitGUID, UnitName, UnitIsPlayer
    local oldInstance, oldInfo, oldLineTypes = IsInInstance, GetInstanceInfo, Enum.TooltipDataLineType
    local oldTooltipTypes = Enum.TooltipDataType
    local oldRefresh, first = ACB.refreshPeerTitle, #hintCallbacks
    local env = { name = "Edwin VanCleef", unitName = "Edwin VanCleef", unit = "mouseover", player = false, lines = {} }
    env.saved = ACB.cleanSavedData({ counts = { ["npc:639"] = 2 } })
    env.tip = {
        GetUnit = function() return env.name, env.unit, env.displayedGUID end,
        AddLine = function(_, line) env.lines[#env.lines + 1] = line end,
        Show = ignore,
    }
    UnitGUID = function(unit) assert(unit == "mouseover"); return env.guid end
    UnitName = function(unit) assert(unit == "mouseover"); return env.unitName end
    UnitIsPlayer = function(unit) assert(unit == "mouseover"); return env.player end
    IsInInstance = function() return true end
    GetInstanceInfo = function() return "Deadmines", "party", 1, "", 5, false, false, 36 end
    Enum.TooltipDataLineType = { UnitName = 55 }
    Enum.TooltipDataType = { Unit = 1, Object = 2 }
    ACB.initHints(env.saved)
    env.show = function(data) hintCallbacks[first + 1](env.tip, data) end
    local ok, why = pcall(check, env)
    for index = #hintCallbacks, first + 1, -1 do hintCallbacks[index] = nil end
    UnitGUID, UnitName, UnitIsPlayer = oldGUID, oldName, oldPlayer
    IsInInstance, GetInstanceInfo, Enum.TooltipDataLineType = oldInstance, oldInfo, oldLineTypes
    Enum.TooltipDataType = oldTooltipTypes
    ACB.refreshPeerTitle = oldRefresh
    assert(ok, why)
end

test("dungeon tooltips use the displayed unit when the tooltip GUID is absent or restricted", function()
    withDungeonHints(function(env)
        env.guid = guid(639, "tooltip-fallback")
        env.show({})
        equal(env.lines[1], "Card: in your binder (x2)")
        env.lines = {}; env.show({ guid = secret })
        equal(env.lines[1], "Card: in your binder (x2)")
        env.saved.counts["npc:639"], env.saved.wanted["npc:639"] = nil, true
        env.lines = {}; env.show({ guid = secret })
        equal(env.lines[1], "Card: not in your binder yet")
        equal(env.lines[2], "On your wanted list")
    end)
end)

test("dungeon tooltip names are a read-only local fallback and protected names are never inspected", function()
    withDungeonHints(function(env)
        env.guid, env.name = secret, secret
        env.show({ guid = secret })
        equal(env.lines[1], "Card: in your binder (x2)", "a separately readable UnitName is allowed")
        env.lines = {}; env.tip.GetUnit = nil
        env.unitName = secret
        env.show({ guid = secret, lines = { { type = 55, unitToken = "mouseover", leftText = "Edwin VanCleef" } } })
        equal(env.lines[1], "Card: in your binder (x2)")
        env.lines = {}; env.tip.GetUnit = function() return secret, "mouseover" end
        env.show({ guid = secret })
        equal(env.lines[1], "Card status: hidden by the game here. Check the binder index.")
        equal(env.saved.counts["npc:639"], 2)
        env.saved.hints = false; env.lines = {}; env.show({ guid = secret })
        equal(#env.lines, 0)
    end)
end)

test("tooltip fallbacks do not guess for unknown GUIDs, player names or ambiguous NPC names", function()
    withDungeonHints(function(env)
        env.guid = guid(99999, "unknown")
        equal(ACB.tooltipCard(env.saved, env.tip, { guid = env.guid }, true), nil)
        env.guid, env.player = secret, true
        local card, restricted = ACB.tooltipCard(env.saved, env.tip, { guid = secret }, true)
        equal(card, nil); assert(not restricted)
        env.player = false
        local page = ACB.pages[ACB.cards["npc:639"].page]
        local all = page.all or page.cards
        all[#all + 1] = { key = "npc:999999", name = "Edwin VanCleef" }
        card = ACB.tooltipCard(env.saved, env.tip, { guid = secret }, true)
        all[#all] = nil
        equal(card, nil)
    end)
end)

test("owned seasonal cards keep tooltip status without becoming eligible loot sources", function()
    withDungeonHints(function(env)
        withLaunchCollection(function()
            ACB.sync = {}
            local held = oneOfEach()
            assert(held)
            local source = guid(held.id, "owned-seasonal-tooltip")
            equal(ACB.source(source), nil)
            equal(ACB.tooltipCard(env.saved, env.tip, { guid = source }, true), nil)
            env.saved.counts[held.key] = 1
            equal(ACB.tooltipCard(env.saved, env.tip, { guid = source }, true), held)
            equal(ACB.source(source), nil, "displaying ownership must not change collection eligibility")
        end)
    end)
end)

test("legacy unit tooltip hooks use the same guarded dungeon lookup", function()
    withDungeonHints(function(env)
        local oldProcessor, oldTip = TooltipDataProcessor, GameTooltip
        TooltipDataProcessor, GameTooltip = nil, env.tip
        env.tip.HookScript = function(self, event, callback) self[event] = callback end
        env.guid = guid(639, "legacy-tooltip")
        ACB.initHints(env.saved)
        env.tip:OnTooltipSetUnit()
        equal(env.lines[1], "Card: in your binder (x2)")
        TooltipDataProcessor, GameTooltip = oldProcessor, oldTip
    end)
end)

local function indexCards(index)
    local cards = {}
    for _, widget in ipairs(widgets) do
        if widget.parent == index and widget.cardKey and widget:IsShown() then cards[#cards + 1] = widget end
    end
    return cards
end
local function indexText(index, value)
    for _, widget in ipairs(widgets) do if widget.parent == index and widget.text == value then return widget end end
end

test("index ownership filters combine with mob, set and category searches and open the chosen card", function()
    local saved = ACB.cleanSavedData({ counts = { ["npc:639"] = 2, ["npc:589"] = 1 } })
    local opened
    local index = ACB.createFolioIndex(UIParent, saved, ignore, function(key) opened = key end)
    index:showSets(1); index:Show()
    index.filters.owned:OnClick()
    equal(#indexCards(index), 2); equal(index.filters.owned.enabled, false)
    index.search:SetText(" Deadmines "); index.search:OnTextChanged()
    local rows = indexCards(index)
    equal(#rows, 1); equal(rows[1].cardKey, "npc:639")
    rows[1]:OnClick(); equal(opened, "npc:639")
    index.search:SetText("Dungeon"); index.search:OnTextChanged()
    equal(#indexCards(index), 1)
    index.search:SetText("Defias Pillager"); index.search:OnTextChanged()
    equal(indexCards(index)[1].cardKey, "npc:589")
    index.filters.unowned:OnClick()
    equal(#indexCards(index), 0); assert(indexText(index, "No unowned cards match"))
    index.filters.all:OnClick()
    equal(#indexCards(index), 1)
    equal(saved.counts["npc:639"], 2); equal(saved.counts["npc:589"], 1)
    index:Hide()
end)

test("index filters count collectible editions individually and retain the chosen filter", function()
    local base = ACB.cards["npc:639"]
    local variant = ACB.cardEditions(base)[2]
    local saved = ACB.cleanSavedData({ counts = { [variant.key] = 1 } })
    local index = ACB.createFolioIndex(UIParent, saved, ignore)
    index.search:SetText(base.name); index.search:OnTextChanged()
    index:setOwnership("owned")
    local rows = indexCards(index)
    equal(#rows, 1); equal(rows[1].cardKey, variant.key)
    index:setOwnership("unowned")
    local seen = {}
    for _, row in ipairs(indexCards(index)) do seen[row.cardKey] = true end
    equal(seen[base.key], true); equal(seen[variant.key], nil)
    local reopened = ACB.createFolioIndex(UIParent, saved, ignore)
    reopened:showSets(base.page)
    equal(reopened.filters.unowned.enabled, false)
    equal(reopened:setOwnership("bad filter"), false)
    equal(saved.indexOwnership, "unowned")
    ACB.cleanSavedData(saved)
    equal(saved.indexOwnership, "unowned"); equal(saved.counts[variant.key], 1)
end)

test("index filter changes reset pagination and ownership updates without changing saved progress", function()
    local saved, chosen = ACB.cleanSavedData({}), {}
    for _, page in ipairs(ACB.pages) do for _, card in ipairs(page.cards) do
        if #chosen < 20 and not saved.counts[card.key] then chosen[#chosen + 1] = card.key; saved.counts[card.key] = 1 end
    end end
    local index = ACB.createFolioIndex(UIParent, saved, ignore)
    index:setOwnership("owned")
    equal(#indexCards(index), 8)
    index:OnMouseWheel(-1)
    assert(indexText(index, "Results  /  2 of 3"))
    index:setOwnership("all")
    local pages = math.ceil(#ACB.pages / ACB.folioUi.SETS_PER_INDEX_PAGE)
    assert(indexText(index, "Results  /  1 of " .. pages))
    for _, key in ipairs(chosen) do saved.counts[key] = nil end
    index:setOwnership("owned")
    equal(#indexCards(index), 0); assert(indexText(index, "No owned cards match"))
    saved.counts["npc:639"] = 1
    index:showSets(1)
    equal(#indexCards(index), 1); equal(indexCards(index)[1].cardKey, "npc:639")
end)
