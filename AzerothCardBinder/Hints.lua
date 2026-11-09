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
    local count = saved.counts[card.key] or 0
    if count > 0 then
        local shiny = saved.shiny and saved.shiny[card.key] and ", shiny" or ""
        lines[1] = { ("Card: in your binder (x%d%s)"):format(count, shiny), 0.54, 0.80, 0.61 }
    else
        lines[1] = { ("Card: not in your binder yet (%g%% chance)"):format(ACB.rates[card.rank] / 100), 1, 0.82, 0 }
        local misses, limit = ACB.luck(saved, card)
        if limit and misses > 0 then
            lines[#lines + 1] = { ("Bad-luck safety net: %d / %d"):format(misses, limit), 0.65, 0.61, 0.54 }
        end
        if saved.wanted and saved.wanted[card.key] then
            lines[#lines + 1] = { "On your wanted list", 0.55, 0.92, 1 }
        end
    end
    return lines
end

function ACB.initHints(saved)
    local function addHints(tooltip, data)
        if saved.hints == false or not tooltip or not tooltip.AddLine then return end
        local guid = ACB.read(type(data) == "table" and data.guid or nil, "string")
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
