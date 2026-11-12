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

function ACB.initHints(saved)
    local watchedPeer, watchedGUID
    local function tooltipGUID(data)
        return ACB.read(type(data) == "table" and data.guid or nil, "string")
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
                title = ACB.peerTitle(peer)
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

    local function addHints(tooltip, data)
        if not tooltip or not tooltip.AddLine then return end
        local guid = tooltipGUID(data)
        if guid then addTitle(tooltip, guid) end
        if saved.hints == false then return end
        local card = ACB.source(guid)
        if not card then return end
        for _, line in ipairs(ACB.hintLines(saved, card)) do
            tooltip:AddLine(line[1], line[2], line[3], line[4])
        end
        if tooltip.Show then tooltip:Show() end
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        local function hook(kind)
            if kind then
                pcall(TooltipDataProcessor.AddTooltipPostCall, kind, function(tooltip, data)
                    pcall(addHints, tooltip, data)
                end)
            end
        end
        hook(Enum.TooltipDataType.Unit)
        hook(Enum.TooltipDataType.Object)
    elseif GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
            local _, unit = tooltip:GetUnit()
            local guid = unit and UnitGUID and UnitGUID(unit)
            pcall(addHints, tooltip, { guid = guid })
        end)
    end
end
