local _, ACB = ...

-- The switches in the binder's Settings tab. Each one is stored as true or false in the saved variables;
-- until a player touches it the default applies. The same switches are still available as slash commands.
ACB.settings = {
    { key = "popups", name = "Card pop-ups", default = true,
        note = "Show a pop-up, with a sound, when you find a card." },
    { key = "hints", name = "Tooltip hints", default = true,
        note = "Add your card status to creature and node tooltips." },
    { key = "inspectable", name = "Let others view my binder", default = true,
        note = "Other players using the add-on can ask to see which cards you own." },
    { key = "diagnostics", name = "Record diagnostics", default = false,
        note = "Keep a trace of loot rolls for bug reports. Open it with /acb log." },
    { key = "bossTrial", name = "VanCleef completion trial", default = false,
        note = "A testing option for the Deadmines boss roll. Leave it off unless asked." },
}

local byKey = {}
for _, setting in ipairs(ACB.settings) do byKey[setting.key] = setting end

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
