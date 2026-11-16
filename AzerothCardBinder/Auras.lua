local _, ACB = ...

-- /acb auras: lists the buffs on your character, with the name, the spell id and how long each has left, so the campfire buff (and any other aura a
-- feature might depend on) can be identified in the real game. It only reads: nothing here changes the binder, and nothing is sent anywhere.
-- Both the older UnitAura call and the newer C_UnitAuras one are tried, every call is protected, and a value the game marks secret is ignored.

local read = ACB.read

-- One entry per aura: { kind, index, name, spellId, duration, remaining, count, source }. `duration` and `remaining` are in seconds, 0 when the aura
-- does not expire. Buffs come first, then debuffs. Returns the list, and which API supplied it ("C_UnitAuras", "UnitAura" or nil).
function ACB.playerAuras()
    local list, api = {}, nil
    for _, kind in ipairs({ "HELPFUL", "HARMFUL" }) do
        for index = 1, 80 do
            local entry
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, kind)
                if not ok then break end
                api = "C_UnitAuras" -- the call works, even if there is nothing to list
                if type(data) ~= "table" then break end
                entry = { name = read(data.name, "string"), icon = read(data.icon, "number"), spellId = read(data.spellId, "number"), duration = read(data.duration, "number"),
                    expires = read(data.expirationTime, "number"), count = read(data.applications, "number"), source = read(data.sourceUnit, "string") }
            elseif UnitAura then
                local values = { pcall(UnitAura, "player", index, kind) }
                if not values[1] then break end
                api = "UnitAura"
                if values[2] == nil then break end
                entry = { name = read(values[2], "string"), icon = read(values[3], "number"), count = read(values[4], "number"), duration = read(values[6], "number"),
                    expires = read(values[7], "number"), source = read(values[8], "string"), spellId = read(values[11], "number") }
            else
                break
            end
            local now = GetTime and read(GetTime(), "number") or 0
            entry.kind = kind == "HELPFUL" and "BUFF" or "DEBUFF"
            entry.index = index
            entry.duration = entry.duration or 0
            entry.remaining = entry.expires and entry.expires > 0 and math.max(0, entry.expires - now) or 0
            list[#list + 1] = entry
        end
    end
    return list, api
end

local function span(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds <= 0 then return "no timer" end
    if seconds >= 3600 then return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
end

-- The list as text, one aura to a line, for chat and for the copy window.
function ACB.auraText(list)
    local lines = {}
    for _, aura in ipairs(list) do
        lines[#lines + 1] = ("%s %d: %s | spell id %s | left %s of %s%s%s"):format(
            aura.kind, aura.index, aura.name or "(hidden)", aura.spellId and tostring(aura.spellId) or "unknown", span(aura.remaining), span(aura.duration),
            aura.count and aura.count > 1 and (" | x" .. aura.count) or "", aura.source and (" | from " .. aura.source) or "")
    end
    return table.concat(lines, "\n")
end

function ACB.auraCommand(report)
    local list, api = ACB.playerAuras()
    if not api then report("This game does not give the add-on a way to read auras."); return end
    if #list == 0 then report("No buffs or debuffs on your character."); return end
    local text = ACB.auraText(list)
    report(("%d auras on your character (read with %s). The full list is in the window: Ctrl+A, Ctrl+C to copy it."):format(#list, api))
    ACB.showLog(text, true)
end
