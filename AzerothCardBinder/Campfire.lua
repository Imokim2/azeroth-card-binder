local _, ACB = ...

-- The campfire (docs/CAMPFIRE.md, ledger spec 12). Standing at a camp with its buff doubles the chance of a card drop. The buff is read from the
-- player's own auras, so its length is the game's: an hour, or two when the camp has been dusted with violet. A Ranked binder says so in its ledger
-- (mode/camp1 once, then a `camp` event whenever the buff reaches further than the last claim) and writes each boosted attempt with partner "camp", so the
-- server can recheck the rolls at the doubled chance. The server cannot see a camp: the claim is the player's word, like their faction.

ACB.campFactor = 2
-- The boost is for ordinary creatures: the cards of common and rare rarity. Elites, rare spawns and bosses (epic and legendary cards) are not boosted.
function ACB.campEligible(card) return card ~= nil and card.baseKey == nil and (card.rarity == "common" or card.rarity == "rare") end
-- The two camp auras the game gives (found with /acb auras): the welcoming campfire, and the same dusted with violet.
ACB.campAuras = {
    [1229739] = { kind = "welcoming", seconds = 3600 },
    [1289723] = { kind = "violet", seconds = 7200 },
}

-- The campfire buff on the player, or nil: { kind, seconds, remaining, icon, spellId }. With both on, the one with more time left.
function ACB.campfire()
    local found
    for _, aura in ipairs((ACB.playerAuras())) do
        local camp = aura.kind == "BUFF" and aura.spellId and ACB.campAuras[aura.spellId]
        if camp and aura.remaining > 0 and (not found or aura.remaining > found.remaining) then
            found = { kind = camp.kind, seconds = camp.seconds, remaining = math.min(aura.remaining, camp.seconds), icon = aura.icon, spellId = aura.spellId }
        end
    end
    return found
end

-- Before a Ranked attempt: write what the server needs to know about the camp, once, and say whether this attempt is boosted. A Casual attempt is
-- boosted too (nothing is written). `ranked` is whether the attempt uses the tape. Returns true when the chance should be doubled.
function ACB.campBoost(saved, ledger, ranked, card)
    if not ACB.campEligible(card) then return false end
    local camp = ACB.campfire()
    if not camp then return false end
    if not ranked then return true end
    -- Only a binder that records every attempt can be boosted on the record, and only while its history verifies and has room.
    if not ledger or not saved.exactMode or not saved.factionLedger or ledger.ok == false or ledger:backlogFull() then return false end
    local seconds = math.floor(camp.remaining)
    if seconds < 1 then return false end
    if not saved.campLedger then
        ledger:flushRun()
        ledger:record("mode", "camp1")
        saved.campLedger = true
    end
    -- A claim is written only when the buff reaches further than the last one did (a few seconds of difference is the clock, not a new buff).
    local now = time()
    if now + seconds > (saved.campEnd or 0) + 5 then
        ledger:flushRun()
        local fellow = ACB.fellowshipMarker and ACB.fellowshipMarker(saved, ledger) -- Fellowship.lua: a camp earns a roll once its marker is written
        local claim = ledger:record("camp", camp.kind, { count = seconds })
        saved.campEnd = claim.t + seconds -- the server reckons the window from the event's own time
        if fellow then ACB.fellowshipOwe(saved, "camp") end -- paid before the next creature roll: this claim is made in the middle of one
    end
    return now <= saved.campEnd
end

-- ---------------------------------------------------------------------------------------------------------
-- The icon: the game's buff bar cannot take a new buff from an add-on, so the campfire boost is shown as an icon of its own beside the buff bar,
-- with the time left and a tooltip. It follows the camp's own buff, so it ends when the buff does.

local icon, shownKind
local function format(seconds)
    seconds = math.floor(seconds)
    if seconds >= 3600 then return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
end

local function build()
    local frame = CreateFrame("Frame", "AzerothCardBinderCampfire", UIParent)
    frame:SetSize(32, 32)
    frame:SetFrameStrata("MEDIUM")
    if BuffFrame then frame:SetPoint("TOPRIGHT", BuffFrame, "TOPLEFT", -10, -2) else frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -14) end
    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetAllPoints()
    frame.timer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.timer:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Campfire luck")
        GameTooltip:AddLine("Card drop chance is doubled while you have the campfire buff.", 1, 1, 1, true)
        local camp = ACB.campfire()
        if camp then GameTooltip:AddLine(format(camp.remaining) .. " remaining", .6, .8, 1) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame:Hide()
    return frame
end

-- Show, update or hide the icon from the buff on the player right now.
function ACB.refreshCampfire()
    local camp = ACB.campfire()
    if not camp or (ACB.campfireIconOff and ACB.campfireIconOff()) then
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

-- The icon's own settings: it can be hidden with /acb campfire icon, and /acb campfire says where the boost stands.
local function iconOff() return AzerothCardBinderDB and AzerothCardBinderDB.campfireIcon == false end
ACB.campfireIconOff = iconOff

function ACB.campfireCommand(saved, argument, report)
    if argument == "icon" then
        saved.campfireIcon = iconOff() and true or false
        report("Campfire icon " .. (saved.campfireIcon == false and "hidden." or "shown."))
        ACB.refreshCampfire()
        return
    end
    local camp = ACB.campfire()
    if camp then
        report(("Campfire buff: %s, %s left. Card drop chance is doubled%s."):format(camp.kind, format(camp.remaining), saved.mode == "ranked" and (saved.exactMode and " and recorded for the server" or "") or ""))
    else
        report("No campfire buff. Sit at a camp for a minute to receive it: card drop chance is doubled while it lasts.")
    end
end

-- The icon follows the buff: it is looked at when auras change, when the player enters the world, and once a second while it is shown.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_AURA")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
local sinceLast = 0
watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" or unit == "player" then ACB.refreshCampfire() end
end)
watcher:SetScript("OnUpdate", function(_, elapsed)
    if not (icon and icon:IsShown()) then return end
    sinceLast = sinceLast + (elapsed or 0)
    if sinceLast >= 1 then sinceLast = 0 ACB.refreshCampfire() end
end)
