local _, ACB = ...
ACB.satchelIcon = ACB.folioArt .. "CardStack.tga"

-- Visual bag chrome only: no native inventory scripts, IDs or secure bag buttons.
-- HeldBagLayout is the game's own small-portrait metal bag frame.
function ACB.createSatchelWindow()
    local frame = CreateFrame("Frame", "AzerothCardBinderSatchel", UIParent, "BackdropTemplate")
    frame:SetSize(320, 346)
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -34, 104)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local chrome = CreateFrame("Frame", nil, frame)
    chrome:SetAllPoints(frame)
    chrome.layoutType = "HeldBagLayout"
    local util = _G.NineSliceUtil
    local layout = util and util.GetLayout and util.GetLayout("HeldBagLayout")
    local native = layout and util.ApplyLayout and pcall(util.ApplyLayout, chrome, layout)
    frame.nativeBagSkin = native == true
    if not native then
        chrome:Hide()
        frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        frame:SetBackdropColor(.07, .07, .07, .98)
        frame:SetBackdropBorderColor(.65, .65, .65, 1)
    end
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", 5, -20)
    background:SetPoint("BOTTOMRIGHT", -5, 5)
    background:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    background:SetVertexColor(.55, .55, .55, .98)
    local portrait = frame:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(40, 40)
    portrait:SetPoint("TOPLEFT", 1, 7)
    portrait:SetTexture(ACB.satchelIcon)
    local header = CreateFrame("Frame", nil, frame)
    header:SetAllPoints(frame)
    header:SetFrameLevel(chrome:GetFrameLevel() + 2)
    local title = ACB.uiKit.label(header, "GameFontNormal", 48, 2, ACB.uiKit.parchment, "Warcards Satchel")
    title:SetWidth(224)
    title:SetWordWrap(false)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", 2, 5)
    close:SetFrameLevel(chrome:GetFrameLevel() + 3)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.chrome, frame.portrait, frame.closeButton = chrome, portrait, close
    table.insert(UISpecialFrames, "AzerothCardBinderSatchel")
    frame:Hide()
    return frame
end

function ACB.satchelButton(parent, text, x, y, width, click)
    local control = CreateFrame("Button", nil, parent, "BackdropTemplate")
    control:SetPoint("TOPLEFT", x, -y)
    control:SetSize(width, 26)
    control:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    local caption = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    caption:SetPoint("CENTER")
    control:SetFontString(caption)
    local enabled, hovered = true, false
    local function paint()
        control:SetBackdropColor(hovered and .22 or .12, hovered and .22 or .12, hovered and .24 or .14, 1)
        control:SetBackdropBorderColor(hovered and .9 or .55, hovered and .8 or .55, hovered and .55 or .55, 1)
        caption:SetTextColor(unpack(enabled and ACB.uiKit.parchment or ACB.uiKit.muted))
        control:SetAlpha(enabled and 1 or .5)
    end
    control:SetScript("OnEnter", function() hovered = true paint() end)
    control:SetScript("OnLeave", function() hovered = false paint() end)
    control:SetScript("OnEnable", function() enabled = true paint() end)
    control:SetScript("OnDisable", function() enabled = false paint() end)
    control:SetScript("OnClick", click)
    control:SetText(text)
    paint()
    return control
end

function ACB.styleSatchelSlot(slot)
    local background = slot:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(slot)
    background:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    local border = slot:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    border:Hide()
    local selected = slot:CreateTexture(nil, "OVERLAY")
    selected:SetAllPoints(slot)
    selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    selected:SetBlendMode("ADD")
    selected:Hide()
    slot.qualityBorder, slot.selection = border, selected
end
