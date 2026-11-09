local _, ACB = ...

function ACB.initLauncher(saved)
    if not Minimap then return end
    local map = Minimap
    local button = CreateFrame("Button", "AzerothCardBinderMinimapButton", map)
    button:SetSize(34, 34)
    button:SetFrameLevel((ACB.read(map:GetFrameLevel(), "number") or 0) + 8)
    button:SetNormalTexture(ACB.folioArt .. "Launcher.tga")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", ACB.toggle)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Azeroth Card Binder", 1, 0.82, 0)
        GameTooltip:AddLine("Click to open or close. Drag to move.", 0.91, 0.85, 0.72)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local angle = ACB.read(saved.minimapAngle, "number")
    if not angle or angle < 0 or angle >= 360 or angle ~= angle then angle = 220 end

    local function position()
        local width = ACB.read(map:GetWidth(), "number") or 140
        local height = ACB.read(map:GetHeight(), "number") or 140
        local radians = math.rad(angle)
        button:ClearAllPoints()
        button:SetPoint("CENTER", map, "CENTER", math.cos(radians) * (width / 2 + 3),
            math.sin(radians) * (height / 2 + 3))
    end

    local function drag()
        local mapX, mapY = map:GetCenter()
        local cursorX, cursorY = GetCursorPosition()
        mapX, mapY = ACB.read(mapX, "number"), ACB.read(mapY, "number")
        cursorX, cursorY = ACB.read(cursorX, "number"), ACB.read(cursorY, "number")
        local scale = ACB.read(map:GetEffectiveScale(), "number")
        if not mapX or not mapY or not cursorX or not cursorY or not scale or scale <= 0 then return end
        angle = math.deg(math.atan2(cursorY / scale - mapY, cursorX / scale - mapX)) % 360
        position()
    end
    local function stopDrag()
        button:SetScript("OnUpdate", nil)
        saved.minimapAngle = angle
    end
    button:SetScript("OnDragStart", function()
        if GameTooltip then GameTooltip:Hide() end
        button:SetScript("OnUpdate", drag)
    end)
    button:SetScript("OnDragStop", stopDrag)
    button:SetScript("OnHide", stopDrag)
    position()
end
