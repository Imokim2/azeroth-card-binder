local _, ACB = ...

-- Colours and small helpers for the binder window: labels, buttons, the window frame, tabs.

local brass = { 0.88, 0.69, 0.40 }
local parchment = { 0.94, 0.88, 0.75 }
local muted = { 0.65, 0.61, 0.54 }

local function label(parent, font, x, y, color, value)
    local line = parent:CreateFontString(nil, "OVERLAY", font)
    line:SetPoint("TOPLEFT", x, -y)
    line:SetJustifyH("LEFT")
    line:SetTextColor(unpack(color))
    line:SetText(value or "")
    return line
end

local function button(parent, text, x, y, width, click)
    local control = CreateFrame("Button", nil, parent, "BackdropTemplate")
    if x then control:SetPoint("TOPLEFT", x, -y) end
    control:SetSize(width, 26)
    control:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    local caption = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    control.caption = caption
    caption:SetPoint("CENTER")
    control:SetFontString(caption)
    local hovered, pressed, enabled = false, false, true
    local function paint()
        local bright = enabled and hovered
        control:SetBackdropColor(pressed and 0.12 or bright and 0.31 or 0.20, pressed and 0.09 or bright and 0.23 or 0.14, 0.09, 1)
        control:SetBackdropBorderColor(bright and 0.88 or 0.59, bright and 0.69 or 0.44, bright and 0.40 or 0.29, 1)
        caption:SetTextColor(unpack(enabled and parchment or muted))
        control:SetAlpha(enabled and 1 or 0.55)
    end
    control:SetScript("OnEnter", function() hovered = true paint() end)
    control:SetScript("OnLeave", function() hovered, pressed = false, false paint() end)
    control:SetScript("OnMouseDown", function() pressed = true paint() end)
    control:SetScript("OnMouseUp", function() pressed = false paint() end)
    control:SetScript("OnEnable", function() enabled = true paint() end)
    control:SetScript("OnDisable", function() enabled, pressed = false, false paint() end)
    paint()
    control:SetText(text)
    control:SetScript("OnClick", click)
    return control
end

local function closeButton(parent, x, y)
    local close = button(parent, "x", nil, nil, 24, function() parent:Hide() end)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", x, y)
    return close
end

local function backdrop(frame, edge, size)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = edge, edgeSize = size })
end

local function window(name, width, height, title, folio)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if folio then
        frame:SetBackdrop({ bgFile = ACB.folioArt .. "Leather.tga" })
        frame:SetBackdropColor(1, 1, 1, 1)
    else
        backdrop(frame, "Interface\\DialogFrame\\UI-DialogBox-Border", 24)
        frame:SetBackdropColor(0.072, 0.057, 0.049, 0.99)
        frame:SetBackdropBorderColor(0.78, 0.63, 0.42)
    end
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 18, -14)
    header:SetPoint("TOPRIGHT", -42, -14)
    header:SetHeight(folio and 52 or 32)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    if folio then
        local seal = header:CreateTexture(nil, "ARTWORK")
        seal:SetTexture(ACB.folioArt .. "Launcher.tga")
        seal:SetSize(36, 36)
        seal:SetPoint("TOPLEFT", 8, -6)
        local heading = label(header, "GameFontNormalLarge", 55, 9, parchment, title)
        heading:SetFont("Fonts\\MORPHEUS.ttf", 33, "")
        frame.heading = heading
        local edition = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        edition:SetPoint("TOPRIGHT", -14, -20)
        edition:SetTextColor(unpack(brass))
        edition:SetText("F I R S T   E D I T I O N")
    else
        label(header, "GameFontNormalLarge", 2, 3, brass, title)
    end
    closeButton(frame, folio and -20 or -16, folio and -18 or -16)
    table.insert(UISpecialFrames, name)
    frame:Hide()
    return frame
end

local function tab(parent, caption, index, open)
    local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", 30 + (index - 1) * 127, -76)
    frame:SetSize(116, 31)
    backdrop(frame, "Interface\\Buttons\\WHITE8X8", 1)
    frame:SetBackdropBorderColor(0.63, 0.46, 0.29, 1)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("CENTER")
    frame:SetFontString(title)
    frame:SetText(caption)
    frame:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    frame:SetScript("OnClick", open)
    return { frame = frame, title = title }
end

local gold, goldDark, green = { 1, 0.82, 0 }, { 0.42, 0.33, 0.14 }, { 0.2, 1, 0.3 }

local function centered(parent, font, y, color, width)
    local line = parent:CreateFontString(nil, "OVERLAY", font)
    line:SetPoint("TOP", parent, "TOP", 0, -y)
    line:SetWidth(width)
    line:SetJustifyH("CENTER")
    line:SetTextColor(unpack(color))
    return line
end

ACB.uiKit = {
    brass = brass,
    parchment = parchment,
    muted = muted,
    gold = gold,
    goldDark = goldDark,
    green = green,
    label = label,
    button = button,
    closeButton = closeButton,
    backdrop = backdrop,
    window = window,
    tab = tab,
    centered = centered,
}
