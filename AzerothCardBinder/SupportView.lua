local _, ACB = ...
local kit = ACB.uiKit

ACB.supportLinks = {
    report = "https://github.com/Imokim2/azeroth-card-binder/issues/new?template=bug_report.yml",
    known = "https://github.com/Imokim2/azeroth-card-binder/blob/main/KNOWN-ISSUES.md",
    discord = "https://worldofwarcards.co.uk/discord",
}

local function readable(value, limit)
    value = ACB.read(value, "string") or "Not available"
    return value:gsub("[%c|]", " "):sub(1, limit or 100)
end

local function encode(text)
    return (text:gsub("([^%w%-%._~])", function(char) return ("%%%02X"):format(char:byte()) end))
end

-- Only these public support fields are included. Never copy account files,
-- player names, ledger contents, sync tokens or an assumed companion version.
function ACB.bugReportDetails(saved)
    local client, build = ACB.safe(GetBuildInfo)
    local version = readable(ACB.addonVersion(), 32)
    local location = readable(ACB.currentPlaceName and ACB.currentPlaceName())
    local details = ("Addon: %s\nGame: %s (build %s)\nMode: %s\nLocation: %s\n3D card models: %s"):format(
        version, readable(client, 32), readable(build, 32), saved.mode == "ranked" and "Ranked" or "Casual",
        location, ACB.settingOn(saved, "cardModels") and "On" or "Off")
    local url = ACB.supportLinks.report .. "&addon-version=" .. encode(version) .. "&location=" .. encode(location) .. "&log=" .. encode(details)
    return details, url
end

function ACB.createSupportView(parent, saved)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    kit.label(view, "GameFontNormalLarge", 32, 63, kit.brass, "Help & community")
    kit.label(view, "GameFontHighlightSmall", 32, 94, kit.muted,
        "Ask for help, share your binder or tell us what went wrong. You do not need to diagnose the problem.")
    local title = kit.label(view, "GameFontNormal", 32, 181, kit.parchment, "")
    local function edit(y, height, multiline)
        local box = CreateFrame("EditBox", nil, view, "BackdropTemplate")
        box:SetPoint("TOPLEFT", 32, -y)
        box:SetSize(824, height)
        kit.backdrop(box, "Interface\\Buttons\\WHITE8X8", 1)
        box:SetBackdropColor(.07, .055, .045, 1)
        box:SetBackdropBorderColor(.58, .43, .27, 1)
        box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        box:SetTextColor(unpack(kit.parchment))
        box:SetTextInsets(9, 9, 7, 7)
        box:SetMultiLine(multiline)
        if multiline then box:SetJustifyV("TOP") end
        box:SetAutoFocus(false)
        box:SetMaxLetters(3000)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        return box
    end
    local link = edit(207, 30, false)
    kit.label(view, "GameFontHighlightSmall", 32, 244, kit.muted, "Click the link, press Ctrl+C, then paste it into your browser.")
    kit.label(view, "GameFontNormal", 32, 281, kit.parchment, "Support details")
    local details = edit(305, 105, true)
    kit.label(view, "GameFontHighlightSmall", 32, 419, kit.muted,
        "The bug-report link includes these details. You can also copy them when asking for help in Discord.")
    kit.label(view, "GameFontHighlightSmall", 32, 455, kit.brass,
        "Loading-screen loop? If chat responds, try /reload. Check Known issues for the current workarounds.")
    local buttons, selected = {}, "report"
    local labels = { report = "Report a bug", known = "Known issues", discord = "Join Discord" }
    function view:choose(kind)
        if not labels[kind] then return false end
        selected = kind
        local text, reportURL = ACB.bugReportDetails(saved)
        details:SetText(text)
        link:SetText(kind == "report" and reportURL or ACB.supportLinks[kind])
        title:SetText(labels[kind] .. " — open in your browser")
        for key, control in pairs(buttons) do control:SetEnabled(key ~= kind) end
        link:ClearFocus(); details:ClearFocus()
        return true
    end
    for position, kind in ipairs({ "report", "known", "discord" }) do
        buttons[kind] = kit.button(view, labels[kind], 32 + (position - 1) * 212, 127, 196, function() view:choose(kind) end)
    end
    view:SetScript("OnShow", function() view:choose(selected) end)
    view:SetScript("OnHide", function() link:ClearFocus(); details:ClearFocus() end)
    view.controls = { buttons = buttons, link = link, details = details }
    view:choose("report")
    return view
end
