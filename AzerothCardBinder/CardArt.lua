local _, ACB = ...
local safe = ACB.safe

-- The scenic picture behind a card's portrait. `ACB.newCardArt(parent, width, height)` makes a frame whose
-- `:show(zoneKey, found)` fills it with the best artwork available.
-- Find the best real artwork the running client can give us for a zone. Every lookup is optional
-- and guarded; the card falls back to a colour gradient when nothing resolves.
-- Names of the world map's zones and the Dungeon Journal's instances, looked up lazily.
local mapNames, journalNames
local function mapByName(name)
    if not mapNames then
        if not (C_Map and C_Map.GetMapChildrenInfo) then return end -- not ready yet: try again next time
        mapNames = {}
        safe(function()
            for _, info in ipairs(C_Map.GetMapChildrenInfo(946, nil, true) or {}) do
                local key = type(info.name) == "string" and info.name:lower()
                if key and not mapNames[key] then mapNames[key] = info.mapID end
            end
        end)
    end
    local found = mapNames[name:lower()]
    if not next(mapNames) then mapNames = nil end
    return found
end
-- Loading screens are named after the place, so every zone and instance gets its likely names tried too.
-- A name that does not exist simply does not resolve, and the next idea is used.
local function loadingPaths(zone)
    local list = {}
    for _, path in ipairs(zone.paths or {}) do list[#list + 1] = path end
    if zone.name then
        local plain = (zone.name:gsub("[^%w]", ""))
        local bare = (plain:gsub("^The", ""))
        for _, name in ipairs({ plain, bare }) do
            list[#list + 1] = "Interface\\Glues\\LoadingScreens\\LoadScreen" .. name
        end
    end
    return list
end

local function journalByName(name)
    if not journalNames then
        if not EJ_GetInstanceByIndex then return end -- not ready yet: try again next time
        journalNames = {}
        safe(function()
            for _, raid in ipairs({ false, true }) do
                for position = 1, 200 do
                    local id, title = EJ_GetInstanceByIndex(position, raid)
                    if not id then break end
                    if type(title) == "string" then journalNames[title:lower()] = journalNames[title:lower()] or id end
                end
            end
        end)
    end
    local found = journalNames[name:lower()]
    if not next(journalNames) then journalNames = nil end
    return found
end

local artCache = {}
local function resolveArt(zoneKey)
    local cached = artCache[zoneKey]
    if cached then return cached end
    local zone = ACB.zones[zoneKey]
    local found = { gradient = zone }

    local journal = zone.journal
    if not journal and zone.name and (zone.kind == "Dungeon" or zone.kind == "Raid") then
        journal = journalByName(zone.name) or journalByName("the " .. zone.name)
    end
    if journal and EJ_GetInstanceInfo then
        local _, _, background = safe(EJ_GetInstanceInfo, journal)
        if type(background) == "number" and background > 0 then
            found = { file = background, gradient = zone }
        end
    end
    if not found.file and GetFileIDFromPath then
        for _, path in ipairs(loadingPaths(zone)) do
            local id = safe(GetFileIDFromPath, path)
            if type(id) == "number" and id > 0 then
                found = { file = id, gradient = zone }
                break
            end
        end
    end
    local mapID = zone.map
    if not mapID and C_Map and C_Map.GetMapChildrenInfo then
        -- An instance with no picture of its own borrows the map of the zone it sits in.
        mapID = (zone.name and mapByName(zone.name)) or (zone.parent and mapByName(zone.parent))
    end
    if not found.file and mapID and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
        local layers = safe(C_Map.GetMapArtLayers, mapID)
        local layer = type(layers) == "table" and layers[1]
        local tiles = layer and safe(C_Map.GetMapArtLayerTextures, mapID, 1)
        if type(tiles) == "table" and layer.tileWidth and layer.tileWidth > 0 then
            local cols = math.ceil(layer.layerWidth / layer.tileWidth)
            local rows = math.ceil(layer.layerHeight / layer.tileHeight)
            if cols > 0 and rows > 0 and #tiles == cols * rows then
                found = { tiles = tiles, cols = cols, rows = rows, tileWidth = layer.tileWidth,
                    tileHeight = layer.tileHeight, gradient = zone }
            end
        end
    end
    -- A gradient may mean the game's art APIs were not ready yet. Try again on
    -- reveal instead of permanently caching that temporary fallback.
    if found.file or found.tiles then artCache[zoneKey] = found end
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
        local desaturate = not found
        for _, tile in ipairs(self.tiles) do tile:Hide() end
        self.base:Hide()
        local backdrop = ACB.cardBackdrop and ACB.cardBackdrop(zoneKey) or ACB.zones[zoneKey].backdrop
        if backdrop and ACB.read(safe(self.base.SetTexture, self.base, ACB.folioArt .. backdrop), "boolean") then
            self.base:SetTexCoord(0, 1, 0, 1)
            self.base:SetDesaturated(desaturate)
            self.base:SetVertexColor(1, 1, 1)
            self.base:Show()
            self.shade:SetAlpha(found and 0.10 or 0.42)
            return
        end
        local source = resolveArt(zoneKey)
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
            if desaturate then top, bottom = { 0.48, 0.48, 0.48 }, { 0.23, 0.23, 0.23 } end
            if CreateColor and self.base.SetGradient then
                safe(self.base.SetGradient, self.base, "VERTICAL",
                    CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
            else
                self.base:SetColorTexture((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2, 1)
            end
            self.base:Show()
        end
        self.shade:SetAlpha(found and 0.15 or 0.42)
    end
    return art
end

ACB.newCardArt = newArt
