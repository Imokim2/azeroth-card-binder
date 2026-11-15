local _, ACB = ...
local kit = ACB.uiKit

function ACB.createSoundSettingsView(parent, saved)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    local checks, samples = {}, {}
    for index, setting in ipairs(ACB.soundSettings) do
        local y = 62 + (index - 1) * 48
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check.settingGroup, check.settingKey = "sounds", setting.key
        check:SetPoint("TOPLEFT", 30, -y)
        check:SetSize(30, 30)
        check:SetScript("OnClick", function(self)
            ACB.setSetting(saved, setting.key, self:GetChecked() == true)
            ACB.refresh()
        end)
        kit.label(frame, "GameFontNormal", 70, y + 2, kit.parchment, setting.name)
        kit.label(frame, "GameFontHighlightSmall", 70, y + 20, kit.muted, setting.note)
        checks[setting.key] = check
    end
    kit.label(frame, "GameFontNormal", 32, 322, kit.brass, "Listen to the sound groups")
    for index, entry in ipairs({ { "pickup", "Card finds" }, { "packs", "Pack opening" }, { "trades", "Trading" }, { "windows", "Windows" } }) do
        samples[entry[1]] = kit.button(frame, entry[2], 32 + (index - 1) * 180, 352, 164, function()
            ACB.previewSounds(entry[1], ACB.say)
        end)
    end
    kit.button(frame, "Stop sounds", 32, 392, 164, function() ACB.stopSounds() end)
    kit.label(frame, "GameFontHighlightSmall", 32, 440, kit.muted,
        "Pop-ups and sounds are independent. Muting a group keeps your other choices saved.")
    function frame:refresh()
        local enabled = ACB.settingOn(saved, "sounds")
        for key, check in pairs(checks) do
            check:SetChecked(ACB.settingOn(saved, key))
            check:SetEnabled(key == "sounds" or enabled)
        end
        for group, control in pairs(samples) do control:SetEnabled(ACB.soundOn(group, saved)) end
    end
    frame:SetScript("OnHide", function() ACB.stopSounds() end)
    frame.controls = { checks = checks, samples = samples }
    return frame
end
