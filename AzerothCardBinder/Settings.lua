local _, ACB = ...

-- The switches in the binder's Settings tab. Each one is stored as true or false in the saved variables;
-- until a player touches it the default applies. The same switches are still available as slash commands.
ACB.settings = {
    { key = "popups", name = "Card pop-ups", default = true,
        note = "Show a pop-up when you find a card. Audio has separate controls under Sounds." },
    { key = "hints", name = "Tooltip hints", default = true,
        note = "Add your card status to creature and node tooltips." },
    { key = "zoneBar", name = "Zone card bar", default = true,
        note = "Takes the reputation bar's place (in green) to show the cards you own in the zone or dungeon you are in." },
    { key = "inspectable", name = "Let others view my binder", default = true,
        note = "Other players using the add-on can ask to see which cards you own." },
    { key = "cardModels", name = "3D card models", default = true,
        note = "Turn off if card models cause display problems. Cards use their zone artwork and a binder seal instead." },
}

ACB.chatSettings = {
    { key = "announceCards", name = "Announce cards in group chat or /say", default = true,
        note = "Share card finds in your group, or /say when solo. This is separate from guild chat." },
    { key = "guildCards", name = "Announce cards in guild chat", default = false,
        note = "Share cards at or above your chosen rarity. Includes cards revealed from packs." },
    { key = "guildPacks", name = "Announce pack finds in guild chat", default = false,
        note = "Share packs you find, with their zone and pack rarity. Does not reveal the cards inside." },
}
ACB.guildRarities = {
    { key = "common", name = "All cards" }, { key = "rare", name = "Rare and above" },
    { key = "epic", name = "Epic and Legendary" }, { key = "legendary", name = "Legendary only" },
}
function ACB.guildRarity(saved)
    for index, rarity in ipairs(ACB.guildRarities) do
        if saved.guildMinRarity == rarity.key then return rarity, index end
    end
    return ACB.guildRarities[3], 3
end

ACB.soundSettings = {
    { key = "sounds", name = "Enable addon sounds", default = true, note = "Master switch. Sounds respect the game's sound-effects volume." },
    { key = "pickupSounds", name = "Card pickup sounds", default = true, note = "Card finds, duplicates, crafting and set completions." },
    { key = "packSounds", name = "Pack sounds", default = true, note = "Pack finds, opening, card flips and pack reveals." },
    { key = "tradeSounds", name = "Trade and gift sounds", default = true, note = "One confirmation when a trade or gift completes." },
    { key = "windowSounds", name = "Window sounds", default = true, note = "Subtle paper and leather when opening the binder or satchel." },
}
local byKey = {}
for _, setting in ipairs(ACB.settings) do byKey[setting.key] = setting end
for _, setting in ipairs(ACB.chatSettings) do byKey[setting.key] = setting end
for _, setting in ipairs(ACB.soundSettings) do byKey[setting.key] = setting end
-- Diagnostics remain available to support through slash commands, outside player settings.
byKey.diagnostics = { key = "diagnostics", default = false }
byKey.bossTrial = { key = "bossTrial", default = false }

function ACB.settingOn(saved, setting)
    if type(setting) == "string" then setting = byKey[setting] end
    if not setting then return false end
    local value = saved[setting.key]
    if value == nil then return setting.default end
    return value == true
end

function ACB.setSetting(saved, key, on)
    if not byKey[key] then return false end
    saved[key] = on == true
    if key == "cardModels" then
        ACB.releaseCardModels()
        ACB.refreshCardModels()
    end
    if (key == "announceCards" or key == "guildCards" or key == "guildPacks") and not on
        and ACB.collection and ACB.collection.announcements then
        ACB.collection.announcements:clear(key)
    end
    if byKey[key] and (key == "sounds" or key:find("Sounds$")) and ACB.stopSounds then ACB.stopSounds() end
    return true
end

-- Step through the earned titles, with "no title" as the first stop. Returns the title now shown, if any.
function ACB.cycleTitle(saved, step)
    local earned = ACB.earnedTitles(saved)
    if #earned == 0 then
        saved.title = nil
        return
    end
    local position = 0
    for index, title in ipairs(earned) do
        if title == saved.title then position = index end
    end
    position = (position + step) % (#earned + 1)
    ACB.selectTitle(saved, earned[position])
    return saved.title
end
