local _, ACB = ...

-- Hints while you play: mob and node tooltips say whether the card is in your binder, and the
-- binder says where to look for a missing card. Turn the tooltip lines off with /acb hints.

-- A sentence saying where a card can be found.
function ACB.whereToFind(card)
    local zone = ACB.zones[card.zone]
    local place = zone and zone.place or "the world"
    if card.profession then return ("Gather it in %s."):format(place) end
    if card.boss then return ("Defeat this boss in %s."):format(place) end
    return ("Defeat it in %s."):format(place)
end

-- The tooltip lines for a card, as { text, r, g, b } rows.
function ACB.hintLines(saved, card)
    local lines = {}
    local count = ACB.familyCount(saved.counts, card)
    if count > 0 then
        local shiny = saved.shiny and saved.shiny[card.key] and ", shiny" or ""
        lines[1] = { ("Card: in your binder (x%d%s)"):format(count, shiny), 0.54, 0.80, 0.61 }
    else
        lines[1] = { "Card: not in your binder yet", 1, 0.82, 0 }
    end
    if count == 0 and saved.wanted and saved.wanted[card.key] then
        lines[#lines + 1] = { "On your wanted list", 0.55, 0.92, 1 }
    end
    return lines
end

local function tooltipGUID(data)
    if ACB.read(data, "table") then return ACB.read(data.guid, "string") end
end

local function tooltipUnit(tooltip, data)
    local name, unit, guid = ACB.safe(tooltip.GetUnit, tooltip)
    name, unit, guid = ACB.read(name, "string"), ACB.read(unit, "string"), ACB.read(guid, "string")
    local unitName = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.UnitName
    local lines = ACB.read(data, "table") and ACB.read(data.lines, "table")
    if unitName and lines then
        for _, line in ipairs(lines) do
            if ACB.read(line, "table") and ACB.read(line.type, "number") == unitName then
                unit = unit or ACB.read(line.unitToken, "string")
                name = name or ACB.read(line.leftText, "string")
                break
            end
        end
    end
    return name, unit, guid
end

local function visibleCard(saved, card)
    if card and (ACB.cardAvailable(card) or ACB.familyCount(saved.counts, card) > 0) then return card end
end

-- Tooltip lookup is read-only. Never use names to award cards or reconstruct a restricted GUID.
function ACB.tooltipCard(saved, tooltip, data, isUnit)
    local hidden = ACB.read(data, "table") and issecretvalue and issecretvalue(data.guid) == true
    local guid = tooltipGUID(data)
    local name, unit, displayedGUID
    if isUnit then name, unit, displayedGUID = tooltipUnit(tooltip, data) end
    guid = guid or displayedGUID or (unit and ACB.read(ACB.safe(UnitGUID, unit), "string"))
    if guid then
        local kind, id = guid:match("^(%a+)%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)%-[^%-]+$")
        return visibleCard(saved, kind and ACB.sources[kind] and ACB.sources[kind][tonumber(id)])
    end
    if not isUnit then return end
    if not unit then return nil, hidden end
    local player = ACB.read(ACB.safe(UnitIsPlayer, unit), "boolean")
    if player ~= false then return nil, player == nil and hidden end
    name = name or ACB.read(ACB.safe(UnitName, unit), "string")
    if not name then
        return nil, hidden == true
    end
    local place = ACB.currentPlaceName and ACB.currentPlaceName()
    local page = place and ACB.pageForName(place)
    local match
    for _, card in ipairs(page and (ACB.pages[page].all or ACB.pages[page].cards) or {}) do
        if not card.profession and card.name:lower() == name:lower() then
            if match and match ~= card then return end -- Ambiguous names cannot identify the card.
            match = card
        end
    end
    return visibleCard(saved, match)
end

function ACB.initHints(saved)
    local watchedPeer, watchedGUID
    local function canAskTitle(unit)
        if not UnitFactionGroup then return false end
        local mine = ACB.read(ACB.safe(UnitFactionGroup, "player"), "string")
        local theirs = ACB.read(ACB.safe(UnitFactionGroup, unit), "string")
        if not mine or mine ~= theirs then return false end
        if UnitIsConnected and ACB.read(ACB.safe(UnitIsConnected, unit), "boolean") ~= true then return false end
        return true
    end

    local function addTitle(tooltip, guid)
        if tooltip ~= GameTooltip or not guid:match("^Player%-") then return end
        local unit
        if UnitTokenFromGUID then unit = ACB.read(UnitTokenFromGUID(guid), "string") end
        if not unit and tooltip.GetUnit then
            local _, token = tooltip:GetUnit()
            unit = ACB.read(token, "string")
        end
        if not unit or not UnitGUID or ACB.read(UnitGUID(unit), "string") ~= guid then return end
        watchedPeer, watchedGUID = nil, nil
        local title
        if UnitIsUnit and ACB.read(UnitIsUnit(unit, "player"), "boolean") then
            title = saved.title
        elseif UnitFullName and ACB.peerTitle then
            local name, realm = UnitFullName(unit)
            name, realm = ACB.read(name, "string"), ACB.read(realm, "string")
            local peer = name and ACB.tradePeer(realm and realm ~= "" and name .. "-" .. realm or name)
            if peer then
                watchedPeer, watchedGUID = peer, guid
                title = ACB.peerTitle(peer, canAskTitle(unit))
            end
        end
        if title then tooltip:AddLine("Binder title: " .. title, 0.88, 0.69, 0.40) end
    end

    function ACB.refreshPeerTitle(peer)
        if peer ~= watchedPeer or not GameTooltip or not GameTooltip.RefreshDataNextUpdate
            or not GameTooltip.GetPrimaryTooltipData or not GameTooltip:IsShown() then return end
        local ok, guid = pcall(function() return tooltipGUID(GameTooltip:GetPrimaryTooltipData()) end)
        if ok and guid == watchedGUID then GameTooltip:RefreshDataNextUpdate() end
    end

    local function addHints(tooltip, data, isUnit)
        if not tooltip or not tooltip.AddLine then return end
        local guid = tooltipGUID(data)
        if guid then addTitle(tooltip, guid) end
        if saved.hints == false then return end
        local card, restricted = ACB.tooltipCard(saved, tooltip, data, isUnit)
        if not card then
            if restricted then
                tooltip:AddLine("Card status: hidden by the game here. Check the binder index.", .76, .72, .64)
                if tooltip.Show then tooltip:Show() end
            end
            return
        end
        for _, line in ipairs(ACB.hintLines(saved, card)) do
            tooltip:AddLine(line[1], line[2], line[3], line[4])
        end
        if tooltip.Show then tooltip:Show() end
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        local function hook(kind, isUnit)
            if kind then
                pcall(TooltipDataProcessor.AddTooltipPostCall, kind, function(tooltip, data)
                    pcall(addHints, tooltip, data, isUnit)
                end)
            end
        end
        hook(Enum.TooltipDataType.Unit, true)
        hook(Enum.TooltipDataType.Object)
    elseif GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
            pcall(addHints, tooltip, {}, true)
        end)
    end
end
