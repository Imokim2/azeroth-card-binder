local _, ACB = ...

-- A World of Warcraft style card, built only from the game's own textures and its Friz Quadrata font:
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
local PORTRAIT = { width = WIDTH - PAD * 2, height = 96 }
local PLATE = { top = 108, height = 20 }
local NAME_WIDTH = PORTRAIT.width - 30 -- the rarity gem takes the left end of the plate
local SUBLINE_TOP = 129
local LORE = { top = 151, height = 34 }
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

local function safe(fn, ...)
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end

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

-- Find the best real artwork the running client can give us for a zone. Every lookup is optional
-- and guarded; the card falls back to a colour gradient when nothing resolves.
local artCache = {}
local function resolveArt(zoneKey)
    local cached = artCache[zoneKey]
    if cached then return cached end
    local zone = ACB.zones[zoneKey]
    local found = { gradient = zone }

    if zone.journal and EJ_GetInstanceInfo then
        local _, _, background = safe(EJ_GetInstanceInfo, zone.journal)
        if type(background) == "number" and background > 0 then
            found = { file = background, gradient = zone }
        end
    end
    if not found.file and GetFileIDFromPath then
        for _, path in ipairs(zone.paths or {}) do
            local id = safe(GetFileIDFromPath, path)
            if type(id) == "number" and id > 0 then
                found = { file = id, gradient = zone }
                break
            end
        end
    end
    if not found.file and zone.map and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
        local layers = safe(C_Map.GetMapArtLayers, zone.map)
        local layer = type(layers) == "table" and layers[1]
        local tiles = layer and safe(C_Map.GetMapArtLayerTextures, zone.map, 1)
        if type(tiles) == "table" and layer.tileWidth and layer.tileWidth > 0 then
            local cols = math.ceil(layer.layerWidth / layer.tileWidth)
            local rows = math.ceil(layer.layerHeight / layer.tileHeight)
            if cols > 0 and rows > 0 and #tiles == cols * rows then
                found = { tiles = tiles, cols = cols, rows = rows, tileWidth = layer.tileWidth,
                    tileHeight = layer.tileHeight, gradient = zone }
            end
        end
    end
    artCache[zoneKey] = found
    return found
end

local function newArt(parent, width, height)
    local art = CreateFrame("Frame", nil, parent)
    art:SetSize(width, height)
    art:SetClipsChildren(true)
    art.tiles = {}
    art.base = art:CreateTexture(nil, "BACKGROUND")
    art.base:SetAllPoints(art)
    art.shade = art:CreateTexture(nil, "OVERLAY")
    art.shade:SetAllPoints(art)
    art.shade:SetColorTexture(0, 0, 0, 1)

    function art:show(zoneKey, found)
        local source = resolveArt(zoneKey)
        local desaturate = not found
        for _, tile in ipairs(self.tiles) do tile:Hide() end
        self.base:Hide()
        if source.file then
            -- Loading screens and journal art are wide; keep the middle of the picture.
            local visible = (width / height) / (16 / 9)
            self.base:SetTexture(source.file)
            self.base:SetTexCoord((1 - visible) / 2, (1 + visible) / 2, 0, 1)
            self.base:SetDesaturated(desaturate)
            self.base:SetVertexColor(1, 1, 1)
            self.base:Show()
        elseif source.tiles then
            local scale = math.max(width / (source.cols * source.tileWidth),
                height / (source.rows * source.tileHeight))
            local tileW, tileH = source.tileWidth * scale, source.tileHeight * scale
            local offsetX = (width - tileW * source.cols) / 2
            local offsetY = (height - tileH * source.rows) / 2
            for index, file in ipairs(source.tiles) do
                local tile = self.tiles[index]
                if not tile then
                    tile = self:CreateTexture(nil, "BACKGROUND")
                    self.tiles[index] = tile
                end
                local column, row = (index - 1) % source.cols, math.floor((index - 1) / source.cols)
                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", self, "TOPLEFT", offsetX + column * tileW, -(offsetY + row * tileH))
                tile:SetSize(tileW + 0.5, tileH + 0.5)
                tile:SetTexture(file)
                tile:SetDesaturated(desaturate)
                tile:Show()
            end
        else
            local zone = source.gradient
            self.base:SetColorTexture(1, 1, 1, 1)
            local top, bottom = zone.top, zone.bottom
            if CreateColor and self.base.SetGradient then
                safe(self.base.SetGradient, self.base, "VERTICAL",
                    CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
            else
                self.base:SetColorTexture((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2, 1)
            end
            self.base:Show()
        end
        self.shade:SetAlpha(found and 0.15 or 0.62)
    end
    return art
end

local function diamond(parent, size, color)
    local texture = parent:CreateTexture(nil, "OVERLAY")
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    texture:SetSize(size, size)
    texture:SetRotation(math.rad(45))
    texture:SetVertexColor(color[1], color[2], color[3], 1)
    return texture
end

function ACB.createCard(parent)
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
    for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
        local stud = diamond(trim, 5, gold)
        stud:SetPoint("CENTER", trim, corner[1], corner[2] * 2, corner[3] * 2)
    end

    -- Portrait window: zone art, then the 3D model on top.
    local window = strip(frame, PAD, PAD, PORTRAIT.width, PORTRAIT.height, { 0, 0, 0 })
    window:SetFrameLevel(level + 1)
    local inner = { width = PORTRAIT.width - 2, height = PORTRAIT.height - 2 }
    card.art = newArt(window, inner.width, inner.height)
    card.art:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    card.art:SetFrameLevel(level + 2)

    card.model = CreateFrame("PlayerModel", nil, window)
    card.model:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    card.model:SetSize(inner.width, inner.height)
    card.model:SetFrameLevel(level + 3)

    card.glow = CreateFrame("Frame", nil, window, "BackdropTemplate")
    card.glow:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    card.glow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -1, 1)
    card.glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    card.glow:SetFrameLevel(level + 4)

    -- Only used when the client cannot load a gathering node's model.
    card.node = card.model:CreateTexture(nil, "ARTWORK")
    card.node:SetSize(inner.width * 0.42, inner.width * 0.42)
    card.node:SetPoint("CENTER")
    card.node:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- The duplicate count sits on the window's top right corner.
    local badges = CreateFrame("Frame", nil, frame)
    badges:SetAllPoints(frame)
    badges:SetFrameLevel(level + 5)
    card.countBadge = strip(badges, WIDTH - PAD - 3 - 24, PAD + 3, 24, 16, { 0.04, 0.035, 0.03 })
    card.count = card.countBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.count:SetPoint("CENTER")
    card.count:SetFont(FONT, 10, "")
    card.count:SetTextColor(0.54, 0.80, 0.61)

    -- Name plate with the rarity gem set into its left end.
    local nameplate = strip(badges, PAD, PLATE.top, PORTRAIT.width, PLATE.height, plate)
    card.name = nameplate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.name:SetShadowOffset(1, -1)
    card.name:SetShadowColor(0, 0, 0, 1)
    card.name:SetPoint("CENTER", nameplate, "CENTER", 7, 0)
    card.name:SetWidth(NAME_WIDTH)
    card.name:SetWordWrap(false)
    card.gemBezel = diamond(badges, 13, goldDark)
    card.gemBezel:SetPoint("CENTER", frame, "TOPLEFT", PAD + 11, -(PLATE.top + PLATE.height / 2))
    card.gem = diamond(badges, 9, { 1, 1, 1 })
    card.gem:SetPoint("CENTER", frame, "TOPLEFT", PAD + 11, -(PLATE.top + PLATE.height / 2))

    -- A dark text box so the rarity line and the description stay readable over the stone.
    local textBox = strip(frame, PAD, SUBLINE_TOP - 3, PORTRAIT.width, HEIGHT - 6 - (SUBLINE_TOP - 3), { 0.04, 0.035, 0.03 })
    textBox:SetFrameLevel(level + 4)

    card.subline = badges:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.subline:SetPoint("TOP", frame, "TOPLEFT", WIDTH / 2, -SUBLINE_TOP)
    card.subline:SetFont(FONT, 9, "")

    local rule = badges:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(goldDark[1], goldDark[2], goldDark[3], 0.8)
    rule:SetSize(PORTRAIT.width - 30, 1)
    rule:SetPoint("TOP", frame, "TOPLEFT", WIDTH / 2, -(LORE.top - 4))

    local ornament = diamond(badges, 5, gold)
    ornament:SetPoint("CENTER", frame, "TOPLEFT", WIDTH / 2, -(LORE.top - 4))

    card.lore = badges:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.lore:SetShadowOffset(1, -1)
    card.lore:SetShadowColor(0, 0, 0, 1)
    card.lore:SetPoint("TOP", frame, "TOPLEFT", WIDTH / 2, -LORE.top)
    card.lore:SetWidth(PORTRAIT.width - 8)
    card.lore:SetHeight(LORE.height)
    card.lore:SetFont(FONT, 9, "")
    card.lore:SetJustifyH("CENTER")
    card.lore:SetJustifyV("TOP")
    card.lore:SetWordWrap(true)
    card.lore:SetTextColor(gold[1], gold[2], gold[3])

    frame:SetScript("OnEnter", function(self)
        local entry = card.entry
        if not entry or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local rarity = ACB.rarities[entry.rarity]
        GameTooltip:AddLine(entry.name, unpack(rarity.color))
        GameTooltip:AddLine(rarity.name .. " " .. typeName(entry), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(("%g%% chance per source"):format(ACB.rates[entry.rank] / 100), 0.65, 0.61, 0.54)
        if card.owned > 0 then
            GameTooltip:AddLine(("Owned %d, spare %d"):format(card.owned, card.owned - 1), 0.54, 0.80, 0.61)
        else
            GameTooltip:AddLine("Not in your binder yet", 0.65, 0.61, 0.54)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Fill the card for a catalog entry. `count` is how many copies the player owns.
    function card:set(entry, count)
        local found = count > 0
        self.entry, self.owned = entry, count
        local rarity = ACB.rarities[entry.rarity]
        local color = rarity.color
        local dim = found and 1 or 0.5

        frame:SetBackdropBorderColor(color[1] * dim, color[2] * dim, color[3] * dim, 1)
        self.glow:SetBackdropBorderColor(color[1], color[2], color[3], found and 0.55 or 0.25)
        self.art:show(entry.zone, found)

        -- Creatures use their in-game model by NPC ID, gathering nodes by the model file of the node.
        self.model:SetShown(found)
        if found and self.modelFor ~= entry.key then
            self.modelFor = entry.key
            safe(self.model.ClearModel, self.model)
            if entry.profession then
                safe(self.model.SetModel, self.model, entry.model)
                safe(self.model.SetFacing, self.model, 0.6)
                safe(self.model.SetCamDistanceScale, self.model, 1)
            else
                safe(self.model.SetCreature, self.model, entry.id)
                safe(self.model.SetCamDistanceScale, self.model, 1.05)
            end
            safe(self.model.SetPosition, self.model, 0, 0, -0.05)
            -- If the client reports a different model than requested, fall back to the node's icon.
            local loaded = entry.profession and safe(self.model.GetModelFileID, self.model)
            self.useIcon = entry.profession and (not entry.model or (type(loaded) == "number" and loaded ~= entry.model))
        end
        if not found then self.useIcon = false end
        self.node:SetShown(found and self.useIcon == true)
        if self.useIcon then self.node:SetTexture(entry.icon) end

        local name = entry.name
        self.name:SetFont(FONT, math.max(8, math.min(11, NAME_WIDTH / (0.56 * #name))), "OUTLINE")
        self.name:SetText(name)
        self.name:SetTextColor(color[1] * dim, color[2] * dim, color[3] * dim)
        self.gem:SetVertexColor(color[1], color[2], color[3], 1)
        self.gem:SetAlpha(dim)
        self.subline:SetText(("%s%s|r  %s%s|r"):format(hex({ color[1] * dim, color[2] * dim, color[3] * dim }),
            rarity.name, hex({ 0.62, 0.6, 0.56 }), typeName(entry)))

        self.countBadge:SetShown(count > 1)
        self.count:SetText("x" .. count)

        self.lore:SetText(found and entry.lore or "Defeat this foe to add it to your binder.")
        local lore = found and gold or { 0.55, 0.52, 0.46 }
        self.lore:SetTextColor(lore[1], lore[2], lore[3])
    end

    return card
end
