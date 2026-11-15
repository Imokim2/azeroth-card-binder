test("bug reports contain only readable public support details and encode form fields", function()
    local oldVersion, oldPlace = ACB.addonVersion, ACB.currentPlaceName
    ACB.addonVersion = function() return "1.0.11" end
    ACB.currentPlaceName = function() return "Razorfen & Kraul|\n" end
    local saved = ACB.cleanSavedData({ mode = "ranked", cardModels = false })
    saved.accountKey, saved.playerName, saved.ledger = "PRIVATEKEY", "PRIVATEPLAYER", { token = "PRIVATETOKEN" }
    local details, url = ACB.bugReportDetails(saved)
    assert(details:find("Addon: 1.0.11", 1, true))
    assert(details:find("Mode: Ranked", 1, true))
    assert(details:find("3D card models: Off", 1, true))
    assert(not details:find("|", 1, true))
    assert(url:find("&location=Razorfen%20%26%20Kraul%20%20", 1, true))
    assert(url:find("&log=Addon%3A%201.0.11%0A", 1, true))
    assert(not url:find("PRIVATE", 1, true))
    equal(ACB.supportLinks.report .. "&addon-version=1.0.11", url:match("^(.-)&location="))
    ACB.currentPlaceName = function() return nil end
    ACB.addonVersion = function() return nil end
    details = ACB.bugReportDetails(saved)
    assert(details:find("Addon: Not available", 1, true))
    assert(details:find("Location: Not available", 1, true))
    ACB.addonVersion, ACB.currentPlaceName = oldVersion, oldPlace
end)

test("Settings offers report, known-issue and community links without creating models or changing progress", function()
    local saved = ACB.cleanSavedData({ counts = { ["npc:639"] = 2 } })
    local before = #widgets
    local settings = ACB.createSettingsView(UIParent, saved)
    local controls = settings.supportControls
    settings.reportBugButton:OnClick()
    local help = controls.link.parent
    equal(help:IsShown(), true)
    assert(controls.link:GetText():find("template=bug_report.yml", 1, true))
    equal(controls.buttons.report.enabled, false)
    controls.buttons.known:OnClick()
    equal(controls.link:GetText(), ACB.supportLinks.known)
    controls.buttons.discord:OnClick()
    equal(controls.link:GetText(), "https://worldofwarcards.co.uk/discord")
    equal(help:choose("invalid"), false)
    local oldPlace = ACB.currentPlaceName
    ACB.currentPlaceName = function() return "Blackfathom Deeps" end
    help:OnShow()
    assert(controls.details:GetText():find("Location: Blackfathom Deeps", 1, true))
    local cleared = 0
    controls.link.ClearFocus = function() cleared = cleared + 1 end
    controls.details.ClearFocus = controls.link.ClearFocus
    help:OnHide(); equal(cleared, 2)
    for index = before + 1, #widgets do assert(widgets[index].kind ~= "PlayerModel") end
    equal(saved.counts["npc:639"], 2)
    ACB.currentPlaceName = oldPlace
end)
