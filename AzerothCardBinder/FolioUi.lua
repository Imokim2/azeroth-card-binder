local _, ACB = ...

ACB.folioArt = "Interface\\AddOns\\AzerothCardBinder\\Art\\"

-- The look of the binder's parchment pages and the small drawing helpers the folio files share.

local DISPLAY_FONT = "Fonts\\MORPHEUS.ttf"
local INK = { 0.21, 0.13, 0.08 }
local SEPIA = { 0.37, 0.25, 0.15 }
local MISSING_INK = { 0.34, 0.32, 0.29 }
local EDGE = { 0.59, 0.44, 0.29 }
local POCKET = { 0.76, 0.64, 0.46 }
local SELECTED = { 0.79, 0.67, 0.47 }
local RARITY_INK = {
    common = INK,
    rare = { 0.16, 0.28, 0.46 },
    epic = { 0.35, 0.19, 0.48 },
    legendary = { 0.50, 0.25, 0.07 },
}
local PAPER_WIDTH, PAPER_HEIGHT = 449, 501
local CARDS_PER_LEAF = 4
local SETS_PER_INDEX_PAGE = 8

local function place(widget, x, y, width, height)
    widget:SetSize(width, height)
    widget:SetPoint("TOPLEFT", x, -y)
    return widget
end

local function panel(parent, kind, x, y, width, height, color, edge)
    local frame = place(CreateFrame(kind, nil, parent, "BackdropTemplate"), x, y, width, height)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(edge))
    return frame
end

local function text(parent, x, y, value, size, color, width, align, display)
    local line = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetPoint("TOPLEFT", x, -y)
    line:SetFont(display and DISPLAY_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    line:SetTextColor(unpack(color))
    line:SetShadowOffset(0, 0)
    line:SetJustifyH(align or "LEFT")
    line:SetWidth(width)
    line:SetText(value)
    return line
end

local function rule(parent, x, y, width)
    local line = place(parent:CreateTexture(nil, "ARTWORK"), x, y, width, 1)
    line:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.65)
end

local function paper(parent, x, mirror)
    local frame = place(CreateFrame("Frame", nil, parent), x, 109, PAPER_WIDTH, PAPER_HEIGHT)
    local skin = frame:CreateTexture(nil, "BACKGROUND")
    skin:SetAllPoints()
    skin:SetTexture(ACB.folioArt .. "Parchment.tga")
    if mirror then skin:SetTexCoord(1, 0, 0, 1) end
    return frame
end

-- A holder keeps both scaled card sizes aligned to the page's coordinates.
local function mountCard(parent, x, y, scale, share)
    local holder = place(CreateFrame("Frame", nil, parent), x, y, ACB.cardWidth * scale, ACB.cardHeight * scale)
    local card = ACB.createCard(holder, true, share)
    card.frame:SetScale(scale)
    card.frame:SetPoint("CENTER", holder, "CENTER")
    card.frame:EnableMouse(share ~= nil)
    return card
end

local function setCard(card, entry, count, shiny, wanted)
    shiny, wanted = shiny == true, wanted == true
    if card.entry ~= entry or card.owned ~= count or card.shiny ~= (count > 0 and shiny)
        or card.wantedFlag ~= wanted then
        card.wantedFlag = wanted
        card:set(entry, count, shiny, wanted)
    end
end

-- A thin progress bar. `bar:set(have, total)` fills it and turns it gold once the set is complete.
local function progressBar(parent, x, y, width)
    local bar = { width = width }
    local back = place(parent:CreateTexture(nil, "ARTWORK"), x, y, width, 5)
    back:SetColorTexture(0.40, 0.28, 0.17, 0.55)
    bar.fill = place(parent:CreateTexture(nil, "OVERLAY"), x, y, 1, 5)
    function bar:set(have, total)
        local fraction = total > 0 and math.min(1, have / total) or 0
        self.fill:SetWidth(math.max(1, self.width * fraction))
        self.fill:SetShown(have > 0)
        if total > 0 and have >= total then
            self.fill:SetColorTexture(0.85, 0.65, 0.12, 1)
        else
            self.fill:SetColorTexture(0.50, 0.33, 0.16, 1)
        end
    end
    return bar
end

local function turnButton(parent, x, caption, action)
    local control = panel(parent, "Button", x, 455, 72, 24, POCKET, EDGE)
    local captionText = text(control, 0, 5, caption, 11, INK, 72, "CENTER")
    control:SetFontString(captionText)
    control:SetText(caption)
    control:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    control:SetScript("OnClick", action)
    return control
end

ACB.folioUi = {
    DISPLAY_FONT = DISPLAY_FONT,
    INK = INK,
    SEPIA = SEPIA,
    MISSING_INK = MISSING_INK,
    EDGE = EDGE,
    POCKET = POCKET,
    SELECTED = SELECTED,
    RARITY_INK = RARITY_INK,
    PAPER_WIDTH = PAPER_WIDTH,
    PAPER_HEIGHT = PAPER_HEIGHT,
    CARDS_PER_LEAF = CARDS_PER_LEAF,
    SETS_PER_INDEX_PAGE = SETS_PER_INDEX_PAGE,
    place = place,
    panel = panel,
    text = text,
    rule = rule,
    paper = paper,
    mountCard = mountCard,
    setCard = setCard,
    progressBar = progressBar,
    turnButton = turnButton,
}
