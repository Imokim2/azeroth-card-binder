local _, ACB = ...

-- All four treatments use the same 136 x 190 card and real model window.
-- Colours, solid textures, backdrop borders and rotated squares are supported
-- natively by the addon; these designs do not require a web renderer or new art.
ACB.cardDesigns = {
    { id = "classic", name = "First Edition", note = "The current stone frame and rarity-coloured gems." },
    { id = "relic", name = "Archivist", note = "A parchment text panel, antique brass and engraved corners.",
        body = { 0.16, 0.12, 0.085 }, plate = { 0.25, 0.18, 0.11 }, paper = { 0.84, 0.76, 0.61 },
        metal = { 0.69, 0.53, 0.30 }, ink = { 0.23, 0.16, 0.10 }, nameInk = { 0.96, 0.87, 0.67 } },
    { id = "runebound", name = "Runebound", note = "Midnight blue, silver rails and restrained arcane detail.",
        body = { 0.055, 0.065, 0.105 }, plate = { 0.10, 0.12, 0.19 }, paper = { 0.045, 0.055, 0.09 },
        metal = { 0.55, 0.64, 0.78 }, ink = { 0.74, 0.78, 0.88 }, nameInk = { 0.88, 0.91, 0.98 } },
    { id = "sovereign", name = "Sovereign", note = "Black enamel, layered gold rails and a crowned centrepiece.",
        body = { 0.065, 0.055, 0.045 }, plate = { 0.17, 0.105, 0.075 }, paper = { 0.055, 0.045, 0.04 },
        metal = { 0.84, 0.65, 0.32 }, ink = { 0.85, 0.75, 0.57 }, nameInk = { 0.98, 0.89, 0.66 } },
}

function ACB.cardDesign(id)
    for _, design in ipairs(ACB.cardDesigns) do if design.id == id then return design end end
    return ACB.cardDesigns[1]
end

local function line(parent, x, y, width, height, color, angle)
    local texture = parent:CreateTexture(nil, "OVERLAY")
    texture:SetColorTexture(color[1], color[2], color[3], 1)
    texture:SetSize(width, height)
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if angle then texture:SetRotation(angle) end
    return texture
end

function ACB.installCardDesign(card, id)
    local design = ACB.cardDesign(id)
    card.design = design
    if design.id == "classic" then return end
    card.frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    local metal = design.metal
    local decoration = CreateFrame("Frame", nil, card.frame)
    decoration:SetAllPoints(card.frame)
    decoration:SetFrameLevel(card.studFrame:GetFrameLevel() - 1)
    card.designDecoration = decoration
    -- Engraved corner brackets leave the model, name and ownership badge clear.
    for _, corner in ipairs({ { 9, 10, 1, 1 }, { 126, 10, -1, 1 }, { 9, 180, 1, -1 }, { 126, 180, -1, -1 } }) do
        local x, y, dx, dy = unpack(corner)
        line(decoration, dx == 1 and x or x - 12, y, 12, 1, metal)
        line(decoration, x, dy == 1 and y or y - 9, 1, 9, metal)
    end
    if design.id == "relic" then
        line(decoration, 11, 186, 114, 1, metal)
        for _, x in ipairs({ 14, 119 }) do line(decoration, x, 139, 3, 3, metal, math.rad(45)) end
    elseif design.id == "runebound" then
        for _, x in ipairs({ 2, 132 }) do
            for y = 34, 80, 9 do line(decoration, x, y, 2, 4, metal, math.rad(35)) end
        end
        line(decoration, 28, 101, 80, 1, metal)
        line(decoration, 65, 98, 6, 6, metal, math.rad(45))
    else
        for _, x in ipairs({ 2, 132 }) do line(decoration, x, 24, 1, 142, metal) end
        line(decoration, 24, 3, 88, 1, metal)
        line(decoration, 64, 1, 8, 8, metal, math.rad(45))
        for _, x in ipairs({ 57, 76 }) do line(decoration, x, 3, 3, 3, metal, math.rad(45)) end
        line(decoration, 20, 184, 96, 1, metal)
    end
end

function ACB.applyCardDesign(card, found, shiny)
    local design = card.design
    if not design or design.id == "classic" then return end
    local metal = found and design.metal or { 0.5, 0.5, 0.51 }
    card.frame:SetBackdropColor(unpack(found and design.body or { 0.17, 0.17, 0.18 }))
    card.frame:SetBackdropBorderColor(metal[1], metal[2], metal[3], 1)
    card.trim:SetBackdropBorderColor(unpack(shiny and { 0.55, 0.92, 1 } or metal))
    card.window:SetBackdropBorderColor(unpack(metal))
    card.nameplate:SetBackdropColor(unpack(found and design.plate or { 0.16, 0.16, 0.17 }))
    card.nameplate:SetBackdropBorderColor(unpack(metal))
    local paper = found and design.paper or { 0.16, 0.16, 0.17 }
    card.textBox:SetBackdropColor(paper[1], paper[2], paper[3], 1)
    card.textBox:SetBackdropBorderColor(unpack(metal))
    card.name:SetTextColor(unpack(found and design.nameInk or { 0.76, 0.77, 0.79 }))
    local ink = found and design.ink or { 0.65, 0.66, 0.68 }
    card.lore:SetTextColor(unpack(ink))
    card.subline:SetText(card.subline:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    card.subline:SetTextColor(unpack(ink))
    card.serial:SetTextColor(unpack(metal))
    card.rule:SetColorTexture(metal[1], metal[2], metal[3], 0.8)
    card.designDecoration:SetAlpha(found and 1 or 0.45)
end
