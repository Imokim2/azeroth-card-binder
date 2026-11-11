local _, ACB = ...

-- Trading distance, like the game's own trading: with the setting on (Settings tab), a trade needs the partner targeted and
-- within about 11 yards. This is a nicety of play, not a safeguard: the add-on is the only thing that can check it, and
-- the server verifies every trade from both players' histories regardless.

-- CheckInteractDistance's index for trading: about 11 yards.
local TRADE_DISTANCE = 2
local UNITS = { "target", "focus", "mouseover" }

-- Print a line to chat in the add-on's usual style.
function ACB.say(message)
    print("|cffe8bc6bWorld of Warcards|r  " .. message)
end

-- The partner name, in the form used between players ("name-realmname"), of a player unit; nothing for anything else
-- (an enemy, an object, yourself).
function ACB.unitPeer(unit)
    if not UnitFullName or not ACB.read(ACB.safe(UnitIsPlayer, unit), "boolean") then return end
    local name, realm = ACB.safe(UnitFullName, unit)
    name, realm = ACB.read(name, "string"), ACB.read(realm, "string")
    if not name then return end
    return ACB.tradePeer(realm and realm ~= "" and (name .. "-" .. realm) or name)
end

-- The unit that is this player, if they are targeted, focused or under the mouse.
function ACB.partnerUnit(peer)
    for _, unit in ipairs(UNITS) do
        if ACB.unitPeer(unit) == peer then return unit end
    end
end

-- The player you have targeted, as a trade partner.
function ACB.targetPeer()
    local peer = ACB.unitPeer("target")
    if peer then return peer end
    return nil, "Target the player first."
end

-- May a trade with this player go ahead? True, or false and what to tell the player.
function ACB.tradeDistanceOk(saved, peer)
    if not ACB.settingOn(saved, "tradeRange") then return true end
    local unit = ACB.partnerUnit(peer)
    if not unit then
        return false, "Target your trade partner first. As in the game, trading works within about 11 yards."
    end
    -- If the game cannot say how far away they are (the call is missing or refuses), the trade is allowed.
    local near = ACB.read(ACB.safe(CheckInteractDistance, unit, TRADE_DISTANCE), "boolean")
    if near == false then return false, "Your partner is too far away. Move within about 11 yards." end
    return true
end
