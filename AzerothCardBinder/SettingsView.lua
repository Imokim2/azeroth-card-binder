local _, ACB = ...
local kit = ACB.uiKit
local brass = kit.brass
local parchment = kit.parchment
local muted = kit.muted
local gold = kit.gold
local label = kit.label
local button = kit.button
local backdrop = kit.backdrop

-- The Settings tab: tick boxes for the switches, and the title shown to other players.
-- `view:refresh()` copies the saved values onto the boxes; call it whenever the tab is shown.
function ACB.createSettingsView(frame, saved)
    -- Settings: tick boxes for the switches that used to be slash commands only, and the title shown beside your name.
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
        local y = 62 + (index - 1) * 32
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
    local titleY = 62 + #ACB.settings * 32 + 6
    label(general, "GameFontNormal", 32, titleY + 6, parchment, "Title shown in player tooltips")
    button(general, "Previous title", 290, titleY, 110, function()
        ACB.cycleTitle(saved, -1)
        ACB.refresh()
    end)
    local titleName = label(general, "GameFontHighlight", 406, titleY + 6, gold, "")
    titleName:SetWidth(170)
    titleName:SetJustifyH("CENTER")
    button(general, "Next title", 582, titleY, 110, function()
        ACB.cycleTitle(saved, 1)
        ACB.refresh()
    end)
    button(general, "Test pop-up", 32, titleY + 48, 130, function() SlashCmdList.AZEROTHCARDBINDER("popup test") end)
    button(general, "Open diagnostics log", 172, titleY + 48, 170, function() SlashCmdList.AZEROTHCARDBINDER("log") end)
    button(general, "Card design studio", 512, titleY + 48, 170, function() ACB.openCardStudio() end)
    -- Casual uses this computer's random numbers and does not count for the ladder; Ranked uses the server's tape.
    local modeButton = button(general, "Switch to Ranked", 352, titleY + 48, 150, function()
        SlashCmdList.AZEROTHCARDBINDER("mode " .. (saved.mode == "ranked" and "casual" or "ranked"))
    end)
    label(general, "GameFontHighlightSmall", 32, titleY + 90, muted,
        "Quick controls: /acb popup, hints, privacy, diag, boss, title and announce.")
    local verification = label(general, "GameFontHighlightSmall", 32, titleY + 118, muted, "")

    function settingsView:refresh()
        audio:refresh()
        for _, setting in ipairs(ACB.settings) do checks[setting.key]:SetChecked(ACB.settingOn(saved, setting)) end
        titleName:SetText(saved.title or "No title shown")
        modeButton:SetText(saved.mode == "ranked" and "Switch to Casual" or "Switch to Ranked")
        if ACB.ledger then
            local verified = ACB.ledger:check()
            verification:SetText(ACB.ledger:status() .. "  /acb verify checks again.")
            verification:SetTextColor(unpack(verified and muted or { 0.9, 0.45, 0.35 }))
        end
    end
    settingsView:SetScript("OnHide", function() ACB.stopSounds() end)
    settingsView.soundControls = audio.controls
    return settingsView
end
