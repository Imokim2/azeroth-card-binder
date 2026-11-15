local _, ACB = ...
local kit = ACB.uiKit
local brass = kit.brass
local parchment = kit.parchment
local muted = kit.muted
local label = kit.label
local button = kit.button
local backdrop = kit.backdrop

local function createChatView(parent, saved)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    local checks = {}
    for index, setting in ipairs(ACB.chatSettings) do
        local y = 62 + (index - 1) * 58
        local check = CreateFrame("CheckButton", nil, view, "UICheckButtonTemplate")
        check.settingGroup, check.settingKey = "chat", setting.key
        check:SetPoint("TOPLEFT", 30, -y)
        check:SetSize(30, 30)
        check:SetScript("OnClick", function(self)
            ACB.setSetting(saved, setting.key, self:GetChecked() == true)
            ACB.refresh()
            view:refresh()
        end)
        label(view, "GameFontNormal", 70, y + 2, parchment, setting.name)
        label(view, "GameFontHighlightSmall", 70, y + 20, muted, setting.note)
        checks[setting.key] = check
    end
    label(view, "GameFontNormal", 32, 258, brass, "Minimum card rarity for guild chat")
    local rarityButton = button(view, "", 32, 288, 210, function()
        local _, index = ACB.guildRarity(saved)
        saved.guildMinRarity = ACB.guildRarities[index % #ACB.guildRarities + 1].key
        view:refresh()
    end)
    label(view, "GameFontHighlightSmall", 260, 295, muted, "Click to choose which cards are shared with your guild.")
    label(view, "GameFontHighlightSmall", 32, 366, muted, "Pack finds use their own switch and include every pack rarity.")
    label(view, "GameFontHighlightSmall", 32, 390, muted, "Your private clickable card messages always stay on. Nothing is sent while you are unguilded.")
    function view:refresh()
        for key, check in pairs(checks) do check:SetChecked(ACB.settingOn(saved, key)) end
        rarityButton:SetText(ACB.guildRarity(saved).name)
        rarityButton:SetEnabled(ACB.settingOn(saved, "guildCards"))
    end
    view.controls = { checks = checks, rarity = rarityButton }
    return view
end

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
    local chat = createChatView(settingsView, saved)
    local help = ACB.createSupportView(settingsView, saved)
    audio:Hide()
    chat:Hide()
    help:Hide()
    local generalTab, soundTab, chatTab, helpTab
    local function selectTab(tab)
        general:SetShown(tab == "general")
        audio:SetShown(tab == "sounds")
        chat:SetShown(tab == "chat")
        help:SetShown(tab == "help")
        if tab ~= "sounds" then ACB.stopSounds() end
        generalTab:SetEnabled(tab ~= "general")
        soundTab:SetEnabled(tab ~= "sounds")
        chatTab:SetEnabled(tab ~= "chat")
        helpTab:SetEnabled(tab ~= "help")
        settingsView:refresh()
    end
    generalTab = button(settingsView, "General", 412, 16, 104, function() selectTab("general") end)
    chatTab = button(settingsView, "Chat", 526, 16, 104, function() selectTab("chat") end)
    soundTab = button(settingsView, "Sounds", 640, 16, 104, function() selectTab("sounds") end)
    helpTab = button(settingsView, "Help", 754, 16, 104, function() selectTab("help") end)
    generalTab:SetEnabled(false)
    local checks = {}
    for index, setting in ipairs(ACB.settings) do
        local y = 62 + (index - 1) * 46
        local check = CreateFrame("CheckButton", nil, general, "UICheckButtonTemplate")
        check.settingGroup, check.settingKey = "general", setting.key
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
        ACB.requestCollectionMode(saved.mode == "ranked" and "casual" or "ranked")
    end)
    local modeNote = label(general, "GameFontHighlightSmall", 230, controlsY + 53, brass, "")
    modeNote:SetWidth(615)
    local reportBug = button(general, "Report a bug", 32, controlsY + 92, 182, function()
        selectTab("help"); help:choose("report")
    end)
    label(general, "GameFontHighlightSmall", 230, controlsY + 99, muted, "Get help, check known issues or join the community.")

    function settingsView:refresh()
        audio:refresh()
        chat:refresh()
        for _, setting in ipairs(ACB.settings) do checks[setting.key]:SetChecked(ACB.settingOn(saved, setting)) end
        modeButton:SetText(saved.mode == "ranked" and "Switch to Casual" or "Switch to Ranked")
        modeNote:SetText(ACB.collectionModeText(saved))
    end
    settingsView:SetScript("OnHide", function() ACB.stopSounds() end)
    settingsView.soundControls = audio.controls
    settingsView.chatControls = chat.controls
    settingsView.supportControls = help.controls
    settingsView.reportBugButton = reportBug
    return settingsView
end
