local _, ACB = ...
local kit = ACB.uiKit
local brass = kit.brass
local parchment = kit.parchment
local muted = kit.muted
local label = kit.label
local button = kit.button
local backdrop = kit.backdrop

-- Everyday collection and audio controls. Titles live in Achievements.
-- `view:refresh()` copies the saved values onto the boxes; call it whenever the tab is shown.
function ACB.createSettingsView(frame, saved)
    -- Player-facing controls, with sound switches on their own page.
    local settingsView = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    settingsView:SetPoint("TOPLEFT", 20, -109)
    settingsView:SetSize(900, 500)
    backdrop(settingsView, "Interface\\Buttons\\WHITE8X8", 1)
    settingsView:SetBackdropColor(0.13, 0.09, 0.07, 1)
    settingsView:SetBackdropBorderColor(0.58, 0.43, 0.27, 1)
    label(settingsView, "GameFontNormalLarge", 32, 20, brass, "Settings")
    local general = CreateFrame("Frame", nil, settingsView)
    general:SetAllPoints(settingsView)
    local audio = ACB.createSoundSettingsView(settingsView, saved)
    audio:Hide()
    local generalTab, soundTab
    local function selectAudio(on)
        general:SetShown(not on)
        audio:SetShown(on)
        if not on then ACB.stopSounds() end
        generalTab:SetEnabled(on)
        soundTab:SetEnabled(not on)
        settingsView:refresh()
    end
    generalTab = button(settingsView, "General", 640, 16, 104, function() selectAudio(false) end)
    soundTab = button(settingsView, "Sounds", 754, 16, 104, function() selectAudio(true) end)
    generalTab:SetEnabled(false)
    local checks = {}
    for index, setting in ipairs(ACB.settings) do
        local y = 62 + (index - 1) * 46
        local check = CreateFrame("CheckButton", nil, general, "UICheckButtonTemplate")
        check.settingGroup = "general"
        check:SetPoint("TOPLEFT", 30, -y)
        check:SetSize(30, 30)
        check:SetScript("OnClick", function(self)
            ACB.setSetting(saved, setting.key, self:GetChecked() == true)
            ACB.refresh()
        end)
        label(general, "GameFontNormal", 70, y + 2, parchment, setting.name)
        label(general, "GameFontHighlightSmall", 70, y + 18, muted, setting.note)
        checks[setting.key] = check
    end
    local controlsY = 62 + #ACB.settings * 46 + 14
    button(general, "Reset satchel button", 32, controlsY, 182, function()
        if ACB.resetSatchelButton then ACB.resetSatchelButton() end
    end)
    label(general, "GameFontHighlightSmall", 230, controlsY + 7, muted, "Shift-drag the satchel button to move it.")
    -- Casual uses this computer's random numbers and does not count for the ladder; Ranked uses the server's tape.
    local modeButton = button(general, "Switch to Ranked", 32, controlsY + 46, 182, function()
        SlashCmdList.AZEROTHCARDBINDER("mode " .. (saved.mode == "ranked" and "casual" or "ranked"))
    end)
    label(general, "GameFontHighlightSmall", 230, controlsY + 53, muted, "Titles can be selected in the Achievements tab.")

    function settingsView:refresh()
        audio:refresh()
        for _, setting in ipairs(ACB.settings) do checks[setting.key]:SetChecked(ACB.settingOn(saved, setting)) end
        modeButton:SetText(saved.mode == "ranked" and "Switch to Casual" or "Switch to Ranked")
    end
    settingsView:SetScript("OnHide", function() ACB.stopSounds() end)
    settingsView.soundControls = audio.controls
    return settingsView
end
