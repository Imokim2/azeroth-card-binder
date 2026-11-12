local _, ACB = ...

-- Original bundled cues, played on SFX so the game's volume/mute controls apply.
local bank = {
    paper = { .19, 0, "packs", "IG_MAINMENU_OPTION_CHECKBOX_ON", "IG_QUEST_LIST_COMPLETE" },
    common = { .48, 1, "pickup", "IG_QUEST_LIST_COMPLETE" },
    duplicate = { .19, 0, "pickup", "IG_QUEST_LIST_COMPLETE" },
    rare = { .95, 2, "pickup", "UI_RAID_LOOT_TOAST_LESSER_ITEM_WON", "IG_QUEST_LIST_COMPLETE" },
    epic = { 1.35, 3, "pickup", "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
    legendary = { 1.95, 4, "pickup", "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
    shiny = { 1.65, 5, "pickup", "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
    pack_anticipate = { 1, 0, "packs" }, pack_burst = { .55, 0, "packs" },
    pack_found = { .85, 2, "packs", "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
    trade = { .72, 0, "trades", "IG_CHARACTER_INFO_TAB" },
    set_complete = { 1.85, 4, "pickup", "UI_LEGENDARY_LOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
    binder = { .32, 0, "windows", "IG_SPELLBOOK_OPEN", "IG_CHARACTER_INFO_OPEN" },
}
local groups = { pickup = "pickupSounds", packs = "packSounds", trades = "tradeSounds", windows = "windowSounds" }
local saved, last, handles, previewToken = {}, {}, {}, 0
local dominantUntil, dominantPriority, dominantHandle = 0, 0, nil
local function stop(handle)
    if handle and type(StopSound) == "function" then pcall(StopSound, handle, .10) end
end
function ACB.stopSounds()
    previewToken = previewToken + 1
    for _, handle in ipairs(handles) do stop(handle) end
    handles, last = {}, {}
    dominantUntil, dominantPriority, dominantHandle = 0, 0, nil
end
function ACB.initSounds(value)
    ACB.stopSounds()
    saved = value
end
function ACB.soundOn(group, settings)
    settings = settings or saved
    return settings.sounds ~= false and (not groups[group] or settings[groups[group]] ~= false)
end
function ACB.playSound(cue, group, preview)
    local definition = bank[cue]
    if not definition then return end
    group = group or definition[3]
    if not ACB.soundOn(group) then return end
    local now = type(GetTime) == "function" and GetTime() or 0
    if not preview and last[cue] and now - last[cue] < .12 then return end
    local priority = definition[2]
    if not preview and priority > 0 and now < dominantUntil and priority < dominantPriority then return end
    local result, handle
    if type(PlaySoundFile) == "function" then
        local path = "Interface\\AddOns\\AzerothCardBinder\\Sounds\\" .. cue .. ".ogg"
        local ok, played, soundHandle = pcall(PlaySoundFile, path, "SFX")
        if ok and played then result, handle = path, soundHandle end
    end
    -- Older clients or absent files retain a known native sound, when available.
    if not result and type(PlaySound) == "function" and type(SOUNDKIT) == "table" then
        for index = 4, #definition do
            local id = SOUNDKIT[definition[index]]
            if id then
                local ok, played, soundHandle = pcall(PlaySound, id, "SFX")
                if ok and played ~= false then result, handle = id, soundHandle break end
            end
        end
    end
    if result then
        last[cue] = now
        if priority > 0 then
            if dominantHandle ~= handle then stop(dominantHandle) end
            dominantUntil, dominantPriority, dominantHandle = now + definition[1], priority, handle
        end
        if type(handle) == "number" then
            handles[#handles + 1] = handle
            if #handles > 16 then table.remove(handles, 1) end
        end
    end
    return result
end

function ACB.cardSound(entry, info)
    info = info or {}
    if info.trade then return end -- the transaction has its own single confirmation
    if info.shiny then return "shiny" end
    if info.crafted or info.first == false or (info.count or 1) > 1 then return "duplicate" end
    if entry.baseKey then return "epic" end
    return bank[entry.rarity] and entry.rarity or "common"
end
function ACB.playCardSound(entry, info, group)
    local cue = ACB.cardSound(entry, info)
    if cue then return ACB.playSound(cue, group or "pickup") end
end
function ACB.playToastSound(rarity, shiny)
    return ACB.playSound(shiny and "shiny" or bank[rarity] and rarity or "common", "pickup")
end
function ACB.soundPriority(cue) return bank[cue] and bank[cue][2] or 0 end

local previews = {
    pickup = { "duplicate", "common", "rare", "epic", "legendary", "shiny", "set_complete" },
    packs = { "pack_found", "pack_anticipate", "pack_burst", "paper", "rare" },
    trades = { "trade" }, windows = { "binder" },
}
function ACB.previewSounds(group, report)
    group = group or "pickup"
    report = report or function() end
    if not previews[group] then report("Choose pickup, packs, trades or windows.") return end
    if not ACB.soundOn(group) then report("That sound group is muted. Enable it in Settings > Sounds to preview it.") return end
    ACB.stopSounds()
    local token, delay = previewToken, 0
    for _, cue in ipairs(previews[group]) do
        local function play()
            if token == previewToken and ACB.soundOn(group) then report("Sound preview: " .. cue:gsub("_", " ")); ACB.playSound(cue, group, true) end
        end
        if delay == 0 then play()
        elseif C_Timer and C_Timer.After then C_Timer.After(delay, play) end
        delay = delay + bank[cue][1] + .35
    end
end
