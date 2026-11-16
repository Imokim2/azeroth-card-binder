local _, ACB = ...

-- How the campfire boost is shown (docs/CAMPFIRE.md). The game's own buff for the camp (Camp Benefits, 1229741) stays where it is on the buff bar. Two things
-- say that the card rate has gone up with it:
--   1. A line added to that buff's tooltip, wherever the game lets an add-on do it (both the older tooltip calls and the newer tooltip data are tried).
--   2. If that cannot be done, a small icon of the add-on's own: the game's buff bar takes no new buff from an add-on, so it sits beside the bar, carries the
--      time left and a tooltip, and can be dragged anywhere (it is remembered). In the default setting ("auto") the icon is shown until the tooltip line has
--      been seen working once on this computer, and then it hides itself; /acb campfire icon on keeps it, off never shows it.

local icon, shownKind
local function format(seconds)
    seconds = math.floor(seconds)
    if seconds >= 3600 then return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
end

-- The setting: "auto" (the default), "on" or "off". The older true and false of /acb campfire icon still mean on and off.
local function setting()
    local value = AzerothCardBinderDB and AzerothCardBinderDB.campfireIcon
    if value == true or value == "on" then return "on" end
    if value == false or value == "off" then return "off" end
    return "auto"
end

-- Whether the add-on's own icon should be showing while the buff lasts.
function ACB.campfireIconWanted()
    local mode = setting()
    if mode ~= "auto" then return mode == "on" end
    return not (AzerothCardBinderDB and AzerothCardBinderDB.campTooltipSeen)
end

-- ---------------------------------------------------------------------------------------------------------
-- The tooltip line

local LINE = "World of Warcards: common and rare card drop chance doubled."

-- Add the line to a tooltip that is describing one of the camp's auras on the player. Returns whether it did.
function ACB.campTooltip(tooltip, spellId)
    spellId = ACB.read(spellId, "number")
    if not tooltip or not spellId or not ACB.campAuras[spellId] or not ACB.campfire() then return false end
    if tooltip.acbCampLine == LINE .. tostring(tooltip.acbCampLineAt) and tooltip.acbCampLineAt == (GetTime and GetTime()) then return false end -- not twice in one moment
    tooltip:AddLine(LINE, 0.45, 0.8, 1, true)
    tooltip.acbCampLine, tooltip.acbCampLineAt = LINE .. tostring(GetTime and GetTime()), GetTime and GetTime()
    if tooltip.Show then tooltip:Show() end -- the tooltip grows to fit the new line
    if AzerothCardBinderDB then AzerothCardBinderDB.campTooltipSeen = true end
    ACB.refreshCampfire()
    return true
end

-- The spell id of the player's buff at a place on the buff bar, the way the older tooltip calls name it.
local function buffAt(unit, index)
    if unit ~= "player" or type(index) ~= "number" then return end
    for _, aura in ipairs((ACB.playerAuras())) do if aura.kind == "BUFF" and aura.index == index then return aura.spellId end end
end

local installed
-- Hook the game's tooltips, in whichever way this client has. Safe to call again (`force` is for tests, which give it tooltips of their own).
function ACB.installCampTooltip(force)
    if installed and not force then return installed end
    installed = {}
    -- The newer way: tooltip data carries the spell id of what it describes.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        for _, kind in ipairs({ Enum.TooltipDataType.UnitAura, Enum.TooltipDataType.Spell }) do
            if kind and pcall(TooltipDataProcessor.AddTooltipPostCall, kind, function(tooltip, data)
                if tooltip == GameTooltip and type(data) == "table" then pcall(ACB.campTooltip, tooltip, data.id) end
            end) then installed[#installed + 1] = "data" end
        end
    end
    -- The older way: the buff bar asks the tooltip to describe the buff at a place on the bar.
    if GameTooltip and hooksecurefunc then
        for _, name in ipairs({ "SetUnitAura", "SetUnitBuff" }) do
            if type(GameTooltip[name]) == "function" and pcall(hooksecurefunc, GameTooltip, name, function(tooltip, unit, index)
                pcall(function() ACB.campTooltip(tooltip, buffAt(unit, index)) end)
            end) then installed[#installed + 1] = name end
        end
        if type(GameTooltip.SetUnitBuffByAuraInstanceID) == "function" and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
            and pcall(hooksecurefunc, GameTooltip, "SetUnitBuffByAuraInstanceID", function(tooltip, unit, id)
                pcall(function()
                    local data = unit == "player" and C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id)
                    ACB.campTooltip(tooltip, data and data.spellId)
                end)
            end) then installed[#installed + 1] = "instance" end
    end
    return installed
end

-- ---------------------------------------------------------------------------------------------------------
-- The icon

local function place(frame)
    local saved = AzerothCardBinderDB
    local at = saved and saved.campfirePos
    frame:ClearAllPoints()
    if type(at) == "table" and type(at.point) == "string" and type(at.relativePoint) == "string" and type(at.x) == "number" and type(at.y) == "number"
        and math.abs(at.x) < 5000 and math.abs(at.y) < 5000 then
        frame:SetPoint(at.point, UIParent, at.relativePoint, at.x, at.y)
    elseif BuffFrame then
        frame:SetPoint("TOPRIGHT", BuffFrame, "TOPLEFT", -10, -2)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -14)
    end
end

local function build()
    local frame = CreateFrame("Frame", "AzerothCardBinderCampfire", UIParent)
    frame:SetSize(32, 32)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    place(frame)
    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetAllPoints()
    frame.timer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.timer:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    frame:EnableMouse(true)
    -- Drag it with the left mouse button; where it is let go is remembered.
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        if AzerothCardBinderDB and type(point) == "string" and type(relativePoint) == "string" and type(x) == "number" and type(y) == "number" then
            AzerothCardBinderDB.campfirePos = { point = point, relativePoint = relativePoint, x = x, y = y }
        end
    end)
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Campfire luck")
        GameTooltip:AddLine(LINE, 1, 1, 1, true)
        local camp = ACB.campfire()
        if camp then GameTooltip:AddLine(format(camp.remaining) .. " remaining", .6, .8, 1) end
        GameTooltip:AddLine("Drag to move it. /acb campfire reset puts it back.", .7, .7, .7, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame:Hide()
    return frame
end

-- Show, update or hide the icon from the buff on the player right now.
function ACB.refreshCampfire()
    local camp = ACB.campfire()
    if not camp or not ACB.campfireIconWanted() then
        if icon then icon:Hide() end
        shownKind = nil
        return camp
    end
    icon = icon or build()
    icon.texture:SetTexture(camp.icon or 134400)
    icon.timer:SetText(format(camp.remaining))
    icon:Show()
    shownKind = camp.kind
    return camp
end

function ACB.campfireShown() return icon ~= nil and icon:IsShown() or false, shownKind end
function ACB.placeCampfire() if icon then place(icon) end end -- back to where it is saved to be, or beside the buff bar

-- /acb campfire: where the boost stands. /acb campfire icon [on|off|auto]: show the icon always, never, or until the tooltip line is seen working
-- (with no word it switches between on and off). /acb campfire reset: put the icon back beside the buff bar.
function ACB.campfireCommand(saved, argument, report)
    local word = (argument or ""):match("^%S+")
    local choice = (argument or ""):match("^%S+%s+(%S+)")
    if word == "icon" then
        if choice == "auto" then
            saved.campfireIcon, saved.campTooltipSeen = nil, nil
            report("Campfire icon: automatic. It shows until the card-rate line is seen on the game's own buff tooltip, then hides.")
        elseif choice == "on" or choice == "off" then
            saved.campfireIcon = choice
            report("Campfire icon " .. (choice == "on" and "always shown." or "hidden."))
        else
            saved.campfireIcon = ACB.campfireIconWanted() and "off" or "on"
            report("Campfire icon " .. (saved.campfireIcon == "on" and "shown." or "hidden."))
        end
        ACB.refreshCampfire()
        return
    end
    if word == "reset" then
        saved.campfirePos = nil
        ACB.placeCampfire()
        report("Campfire icon put back beside the buff bar.")
        return
    end
    local camp = ACB.campfire()
    if camp then
        report(("Campfire buff: %s, %s left. Common and rare card drop chance is doubled%s."):format(camp.kind, format(camp.remaining), saved.mode == "ranked" and (saved.exactMode and " and recorded for the server" or "") or ""))
        report("Hover the buff on your buff bar: its tooltip says so too once the game allows it (" .. (saved.campTooltipSeen and "seen working" or "not seen yet") .. ").")
    else
        report("No campfire buff. Sit at a camp for a minute to receive it: common and rare card drop chance is doubled while it lasts.")
    end
end

-- It follows the buff: it is looked at when auras change, when the player enters the world, and once a second while it is shown.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_AURA")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
local sinceLast = 0
watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then pcall(ACB.installCampTooltip) end -- the tooltips exist by now
    if event == "PLAYER_ENTERING_WORLD" or unit == "player" then ACB.refreshCampfire() end
end)
watcher:SetScript("OnUpdate", function(_, elapsed)
    if not (icon and icon:IsShown()) then return end
    sinceLast = sinceLast + (elapsed or 0)
    if sinceLast >= 1 then sinceLast = 0 ACB.refreshCampfire() end
end)
pcall(ACB.installCampTooltip)
