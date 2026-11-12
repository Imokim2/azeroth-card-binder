local _, ACB = ...

-- A World of Warcraft style card with an in-game model in a scenic portrait:
--   * stone panel with the tooltip border tinted by rarity, an inner gold trim and corner studs
--   * portrait window holding the zone art with the creature model on top, ringed by a rarity glow
--   * name plate with the name in the rarity colour, and a rarity gem
--   * rarity and type line, an ornate divider, then the description in quest-text gold
-- Everything is laid out in pixels on a WIDTH x HEIGHT card.
local WIDTH, HEIGHT = 136, 190
ACB.cardWidth, ACB.cardHeight = WIDTH, HEIGHT

local FONT = "Fonts\\FRIZQT__.TTF"
local STONE = "Interface\\FrameGeneral\\UI-Background-Rock"
local PAD = 7
local PORTRAIT = { width = WIDTH - PAD * 2, height = 92 }
local PLATE = { top = 104, height = 20 }
local NAME_WIDTH = PORTRAIT.width - 8
local SUBLINE_TOP = 125
local LORE = { top = 147, height = 29 } -- three short lines, with the serial number beneath
local SHINY = { 0.55, 0.92, 1 }
local LOCKED = { 0.59, 0.60, 0.62 }
local LOCKED_TEXT = { 0.76, 0.77, 0.79 }
local FULL_TURN = 2 * math.pi
local SWAY_ANGLE, SWAY_SPEED = math.rad(8), FULL_TURN / 8
local gold, goldDark = { 1, 0.82, 0 }, { 0.42, 0.33, 0.14 }
local panel, plate = { 0.055, 0.05, 0.045 }, { 0.06, 0.05, 0.04 }

local typeNames = { mining = "Mining", herbalism = "Herbalism" }
local function typeName(entry)
    if entry.profession then return typeNames[entry.profession] or "Gathering" end
    if entry.boss then return "Boss" end
    if entry.rank == "elite" then return "Elite" end
    if entry.rank == "rare" or entry.rank == "rareelite" then return "Rare" end
    return "Normal"
end

local function hex(color)
    return ("|cff%02x%02x%02x"):format(color[1] * 255 + 0.5, color[2] * 255 + 0.5, color[3] * 255 + 0.5)
end

local safe = ACB.safe
local loadModel, setModelFinish, poseCreature = ACB.loadCardModel, ACB.setModelFinish, ACB.poseCreature

local function edged(frame, background, edge, edgeSize, inset)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = edge, edgeSize = edgeSize,
        insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    frame:SetBackdropColor(background[1], background[2], background[3], 1)
end

local function strip(parent, x, y, width, height, background)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    edged(frame, background, "Interface\\Buttons\\WHITE8X8", 1, 1)
    frame:SetBackdropBorderColor(goldDark[1], goldDark[2], goldDark[3], 1)
    return frame
end

local function diamond(parent, size, color)
    local texture = parent:CreateTexture(nil, "OVERLAY")
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    texture:SetSize(size, size)
    texture:SetRotation(math.rad(45))
    texture:SetVertexColor(color[1], color[2], color[3], 1)
    return texture
end

local function gradient(texture, direction, first, last)
    if CreateColor and texture.SetGradient then
        texture:SetColorTexture(1, 1, 1, 1)
        if pcall(texture.SetGradient, texture, direction, CreateColor(unpack(first)), CreateColor(unpack(last))) then return end
    end
    texture:SetColorTexture(unpack(first))
end

function ACB.createCard(parent, previewUnowned, share, options)
    options = options or {}
    local card = { entry = nil, owned = 0 }
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = STONE, tile = true, tileSize = 256,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.42, 0.39, 0.36, 1)
    card.frame = frame
    local level = frame:GetFrameLevel()

    local trim = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    trim:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    trim:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    trim:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    trim:SetBackdropBorderColor(goldDark[1], goldDark[2], goldDark[3], 0.9)
    trim:SetFrameLevel(level + 1)
    card.trim = trim

    -- Four corner studs in the rarity colour. They live on their own frame above every other layer, so the
    -- two at the bottom are not hidden by the text box.
    card.studFrame = CreateFrame("Frame", nil, frame)
    card.studFrame:SetAllPoints(frame)
    card.studFrame:SetFrameLevel(level + 9)
    card.studs = {}
    for _, corner in ipairs({ { "TOPLEFT", 6, -6 }, { "TOPRIGHT", -6, -6 }, { "BOTTOMLEFT", 6, 6 }, { "BOTTOMRIGHT", -6, 6 } }) do
        local bezel = diamond(card.studFrame, 10, { 0.03, 0.025, 0.02 })
        bezel:SetPoint("CENTER", card.studFrame, corner[1], corner[2], corner[3])
        local stud = diamond(card.studFrame, 7, gold)
        stud:SetPoint("CENTER", card.studFrame, corner[1], corner[2], corner[3])
        card.studs[#card.studs + 1] = stud
    end

    -- Portrait window: zone art, then the 3D model on top.
    local window = strip(frame, PAD, PAD, PORTRAIT.width, PORTRAIT.height, { 0, 0, 0 })
    card.window = window
    window:SetFrameLevel(level + 1)
    local inner = { width = PORTRAIT.width - 2, height = PORTRAIT.height - 2 }
    card.art = ACB.newCardArt(window, inner.width, inner.height)
    card.art:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    card.art:SetFrameLevel(level + 2)

    card.model = CreateFrame("PlayerModel", nil, window)
    card.model:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    card.model:SetSize(inner.width, inner.height)
    card.model:SetFrameLevel(level + 3)
    safe(card.model.SetKeepModelOnHide, card.model, true)

    local swayPhase, animationElapsed, modelReady = 0, 0, false
    local function portraitFacing()
        return card.facing + SWAY_ANGLE * math.sin(swayPhase)
    end

    local function updateModel(model)
        local entry = card.entry
        if not entry or entry.key ~= card.modelFor then return end
        setModelFinish(model, card.owned > 0)
        local loaded = ACB.read(safe(model.GetModelFileID, model), "number")
        modelReady = loaded and loaded > 0 and (not entry.profession or loaded == entry.model)
        if not loaded or loaded <= 0 then return end
        if entry.profession then
            card.node:SetShown(not modelReady)
        else
            card.playing, card.playbackAnimation = poseCreature(model, entry, portraitFacing(), card.presentation,
                share ~= nil and card.owned > 0 and not card.motionPaused)
        end
    end
    card.refreshPortrait = ACB.watchCardModel(card, updateModel, function() return card.owned > 0 or previewUnowned end)

    card.glow = CreateFrame("Frame", nil, window, "BackdropTemplate")
    card.glow:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    card.glow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -1, 1)
    card.glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    card.glow:SetFrameLevel(level + 4)

    -- Draw the rarity tint and foil above the model, below the count badge.
    local finish = CreateFrame("Frame", nil, window)
    finish:SetAllPoints(card.model)
    finish:SetFrameLevel(level + 5)
    card.tint = finish:CreateTexture(nil, "ARTWORK")
    card.tint:SetAllPoints(finish)
    card.tint:SetBlendMode("ADD")
    card.veil = finish:CreateTexture(nil, "OVERLAY")
    card.veil:SetAllPoints(finish)
    gradient(card.veil, "VERTICAL", { 0.76, 0.77, 0.79, 0.24 }, { 0.76, 0.77, 0.79, 0.09 })

    card.foil = CreateFrame("Frame", nil, window)
    card.foil:SetAllPoints(finish)
    card.foil:SetFrameLevel(level + 6)
    local sheen = card.foil:CreateTexture(nil, "ARTWORK")
    sheen:SetAllPoints(card.foil)
    sheen:SetBlendMode("ADD")
    gradient(sheen, "VERTICAL", { 0.78, 0.35, 1, 0.32 }, { 0.22, 0.92, 1, 0.28 })
    local glint = diamond(card.foil, 5, SHINY)
    glint:SetPoint("TOPLEFT", 5, -5)

    -- Move the highlight inside the portrait so the foil does not depend on animation clipping.
    local bandWidth = inner.width * 0.32
    local band = CreateFrame("Frame", nil, card.foil)
    band:SetSize(bandWidth, inner.height)
    band:SetPoint("LEFT")
    band:SetAlpha(0)
    for _, side in ipairs({ { "LEFT", 0, 0.75 }, { "RIGHT", 0.75, 0 } }) do
        local half = band:CreateTexture(nil, "OVERLAY")
        half:SetSize(bandWidth / 2, inner.height)
        half:SetPoint(side[1], band, side[1], 0, 0)
        half:SetBlendMode("ADD")
        gradient(half, "HORIZONTAL", { 0.76, 0.96, 1, side[2] }, { 0.76, 0.96, 1, side[3] })
    end
    local sweep = 0
    card.foil:SetScript("OnUpdate", function(self, elapsed)
        sweep = (sweep + elapsed) % 3.4
        local progress = math.min(1, sweep / 1.15)
        band:SetAlpha(math.min(1, progress * 5, (1 - progress) * 5))
        if progress < 1 then
            band:SetPoint("LEFT", self, "LEFT", (inner.width - bandWidth) * progress, 0)
        end
    end)
    card.foil:Hide()

    -- Only used when the client cannot load a gathering node's model.
    card.node = card.model:CreateTexture(nil, "ARTWORK")
    card.node:SetSize(inner.width * 0.42, inner.width * 0.42)
    card.node:SetPoint("CENTER")
    card.node:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- The duplicate count sits on the window's top right corner.
    local badges = CreateFrame("Frame", nil, frame)
    badges:SetAllPoints(frame)
    badges:SetFrameLevel(level + 7)
    card.badges = badges
    card.countBadge = strip(badges, WIDTH - PAD - 3 - 24, PAD + 3, 24, 16, { 0.04, 0.035, 0.03 })
    card.count = card.countBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.count:SetPoint("CENTER")
    card.count:SetFont(FONT, 10, "")
    card.count:SetTextColor(0.54, 0.80, 0.61)

    -- The name has the entire plate; rarity belongs on the divider below it.
    local nameplate = strip(badges, PAD, PLATE.top, PORTRAIT.width, PLATE.height, plate)
    card.nameplate = nameplate
    card.name = nameplate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.name:SetShadowOffset(1, -1)
    card.name:SetShadowColor(0, 0, 0, 1)
    card.name:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    card.name:SetWidth(NAME_WIDTH)
    card.name:SetJustifyH("CENTER")
    card.name:SetWordWrap(false)
    card.gemBezel = badges:CreateTexture(nil, "OVERLAY")
    card.gemBezel:SetSize(15, 15)
    card.gemBezel:SetVertexColor(0.035, 0.03, 0.025, 1)
    card.gemBezel:SetPoint("CENTER", frame, "TOPLEFT", WIDTH / 2, -140)
    card.gem = badges:CreateTexture(nil, "OVERLAY")
    card.gem:SetSize(11, 11)
    card.gem:SetPoint("CENTER", frame, "TOPLEFT", WIDTH / 2, -140)

    -- A dark text box so the rarity line and the description stay readable over the stone.
    local textBox
    textBox = strip(frame, PAD, SUBLINE_TOP - 3, PORTRAIT.width, HEIGHT - 6 - (SUBLINE_TOP - 3), { 0.04, 0.035, 0.03 })
    textBox:SetFrameLevel(level + 4)
    card.textBox = textBox

    -- The card's serial number, at the bottom in the middle.
    card.serial = badges:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.serial:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    card.serial:SetFont(FONT, 7, "")
    card.serial:SetTextColor(0.62, 0.6, 0.56)

    card.subline = badges:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.subline:SetPoint("TOP", frame, "TOPLEFT", WIDTH / 2, -SUBLINE_TOP)
    card.subline:SetFont(FONT, 9, "")

    local rule = badges:CreateTexture(nil, "ARTWORK")
    card.rule = rule
    rule:SetColorTexture(goldDark[1], goldDark[2], goldDark[3], 0.8)
    rule:SetSize(PORTRAIT.width - 30, 1)
    rule:SetPoint("TOP", frame, "TOPLEFT", WIDTH / 2, -140)

    card.lore = badges:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.lore:SetShadowOffset(1, -1)
    card.lore:SetShadowColor(0, 0, 0, 1)
    card.lore:SetPoint("TOP", frame, "TOPLEFT", WIDTH / 2, -LORE.top)
    card.lore:SetWidth(PORTRAIT.width - 8)
    card.lore:SetHeight(LORE.height)
    card.lore:SetFont(FONT, 9, "")
    safe(card.lore.SetMaxLines, card.lore, 3)
    card.lore:SetJustifyH("CENTER")
    card.lore:SetJustifyV("TOP")
    card.lore:SetWordWrap(true)
    card.lore:SetTextColor(gold[1], gold[2], gold[3])

    ACB.installCardTooltip(card, typeName, share ~= nil)

    local linkEntry, previousX, radiansPerPixel
    local function stopInteraction()
        previousX, linkEntry = nil, nil
    end
    if share then
        frame:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" and card.presentation and card.presentation.animated then
                card:setMotionPaused(not card.motionPaused)
                return
            end
            if button ~= "LeftButton" or not card.entry then return end
            if IsShiftKeyDown() then
                linkEntry = card.entry
                return
            end
            if card.entry.profession or not modelReady or not card.model:IsMouseOver() then return end
            previousX = GetCursorPosition()
            radiansPerPixel = 0.025 / self:GetEffectiveScale()
        end)
        frame:SetScript("OnUpdate", function(_, elapsed)
            if not modelReady then return end
            if previousX and IsMouseButtonDown("LeftButton") then
                local x = GetCursorPosition()
                card.facing = (card.facing + (x - previousX) * radiansPerPixel) % FULL_TURN
                previousX = x
            else
                previousX = nil
                if not card.motionPaused then swayPhase = (swayPhase + elapsed * SWAY_SPEED) % FULL_TURN end
            end
            safe(card.model.SetFacing, card.model, portraitFacing())
            if card.playing then
                animationElapsed = animationElapsed + elapsed
                local duration = card.presentation.duration or 4
                if animationElapsed >= duration then
                    animationElapsed = animationElapsed % duration
                    safe(card.model.SetAnimation, card.model, card.playbackAnimation or card.presentation.pose.animation, 0)
                end
            end
        end)
        frame:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            local entry = linkEntry
            stopInteraction()
            if entry and self:IsMouseOver() then share(entry) end
        end)
        frame:SetScript("OnHide", stopInteraction)
    end

    -- Fill the card for a catalog entry. `count` is how many copies the player owns.
    function card:set(entry, count, shiny, wanted)
        local found = count > 0
        local showModel = found or previewUnowned
        shiny = found and shiny == true
        wanted = not found and wanted == true
        if self.entry ~= entry then
            stopInteraction()
            swayPhase, modelReady = 0, false
        end
        self.entry, self.owned, self.shiny = entry, count, shiny
        local presentation = ACB.cardPresentation(entry, options.presentation)
        local changedPresentation = not self.presentation or self.presentation.id ~= presentation.id
        self.presentation = presentation
        local rarity = ACB.rarities[entry.rarity]
        local color = found and rarity.color or LOCKED
        local nameColor = found and rarity.color or LOCKED_TEXT

        if found then
            frame:SetBackdropColor(0.42, 0.39, 0.36, 1)
        else
            frame:SetBackdropColor(0.39, 0.39, 0.40, 1)
        end
        for _, stud in ipairs(self.studs) do stud:SetVertexColor(color[1], color[2], color[3], 1) end
        self.serial:SetText("No. " .. entry.serial)
        self.serial:SetAlpha(found and 1 or 0.6)
        frame:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        local trimColor = shiny and SHINY or (found and goldDark or LOCKED)
        self.trim:SetBackdropBorderColor(trimColor[1], trimColor[2], trimColor[3], shiny and 1 or 0.9)
        self.tint:SetShown(found)
        gradient(self.tint, "VERTICAL", { color[1], color[2], color[3], entry.rarity == "common" and 0.09 or 0.24 },
            { color[1], color[2], color[3], 0 })
        self.foil:SetShown(shiny)
        self.glow:SetBackdropBorderColor(color[1], color[2], color[3], found and 0.55 or 0.25)
        self.art:show(entry.zone, found)
        self.veil:SetShown(not found)
        self.node:SetDesaturated(not found)
        self.node:SetAlpha(found and 1 or 0.68)

        -- Creatures use their in-game model by NPC ID, gathering nodes by the model file of the node.
        self.model:SetShown(showModel == true)
        if showModel and self.modelFor ~= entry.key then
            self.playing = false
            self.modelFor = nil
            safe(self.model.ClearModel, self.model)
            self.modelFor = entry.key
            self.facing = entry.profession and 0.6 or presentation.pose.facing
            animationElapsed = 0
            self.node:SetShown(entry.profession ~= nil)
            if entry.profession then self.node:SetTexture(entry.icon) end
            if entry.profession then
                safe(self.model.SetPaused, self.model, false)
                safe(self.model.SetPortraitZoom, self.model, 0)
                safe(self.model.SetFacing, self.model, self.facing)
                safe(self.model.SetCamDistanceScale, self.model, 1)
                safe(self.model.SetPosition, self.model, 0, 0, -0.05)
            else
                safe(self.model.SetCamDistanceScale, self.model, 1.05)
            end
            loadModel(self.model, entry)
            -- Cached models may already be ready. Newly loaded models also run the hook above.
            updateModel(self.model)
        elseif showModel then
            setModelFinish(self.model, found)
            if changedPresentation then
                self.facing, swayPhase, animationElapsed = presentation.pose.facing, 0, 0
                updateModel(self.model)
            elseif not entry.profession then
                local shouldPlay = share ~= nil and found and presentation.animated and not self.motionPaused
                if (self.playing == true) ~= (shouldPlay == true) then updateModel(self.model) end
            end
        end

        local name = entry.name
        ACB.fitText(self.name, FONT, name, NAME_WIDTH, 11, 6.5, "OUTLINE")
        self.name:SetTextColor(unpack(nameColor))
        self.gem:SetVertexColor(color[1], color[2], color[3], 1)
        local shapes = { common = "Circle", rare = "Square", epic = "Diamond", legendary = "Hexagon" }
        self.rarityShape = entry.baseKey and "Star" or shapes[entry.rarity] or "Circle"
        local icon = "Interface\\AddOns\\AzerothCardBinder\\Art\\Rarity\\" .. self.rarityShape .. ".tga"
        self.gem:SetTexture(icon)
        self.gemBezel:SetTexture(icon)
        self.subline:SetText(("%s%s|r  %s%s|r%s"):format(hex(nameColor),
            rarity.name, hex({ 0.62, 0.6, 0.56 }), typeName(entry),
            (shiny and ("  " .. hex(SHINY) .. "Shiny|r") or "") .. (wanted and ("  " .. hex(LOCKED_TEXT) .. "Wanted|r") or "")))

        self.countBadge:SetShown(count > 1)
        self.count:SetText("x" .. count)

        local missing = entry.profession and "Gather this node to add it to your binder."
            or "Defeat this foe to add it to your binder."
        local text = found and entry.lore or missing
        self.lore:SetFont(FONT, #text > 64 and 8 or 9, "") -- longer lines get a touch smaller so three lines hold them
        self.lore:SetText(text)
        local lore = found and gold or LOCKED
        self.lore:SetTextColor(lore[1], lore[2], lore[3])
        ACB.applyCardDesign(self, found, shiny)
    end

    -- These controls are used by the artwork studio; they never change ownership.
    function card:setPresentation(id)
        options.presentation = id
        if self.entry then self:set(self.entry, self.owned, self.shiny, self.wantedFlag) end
    end

    function card:setMotionPaused(paused)
        self.motionPaused = paused == true
        animationElapsed = 0
        if self.entry then updateModel(self.model) end
    end

    ACB.installCardDesign(card, options.design)

    return card
end
