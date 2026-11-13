local _, ACB = ...

-- Trading distance, like the game's own trading: a trade needs the partner targeted and
-- within about 11 yards. This is a nicety of play, not a safeguard: the add-on is the only thing that can check it, and
-- the server verifies every trade from both players' histories regardless.

-- CheckInteractDistance's index for trading: about 11 yards.
local TRADE_DISTANCE = 2
local UNITS = { "target", "focus", "mouseover" }
-- Native trades do not require keeping the partner targeted. Group unit tokens
-- let us keep checking the actual nearby player after the target changes.
for index = 1, 4 do UNITS[#UNITS + 1] = "party" .. index end
for index = 1, 40 do UNITS[#UNITS + 1] = "raid" .. index end

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
    -- Some clients return the whole Forever name in the first result.
    return ACB.tradePeer(name:find("%s") and name or realm and realm ~= "" and (name .. "-" .. realm) or name)
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

local function position(unit)
    local x, y, z, instance = ACB.safe(UnitPosition, unit)
    return ACB.read(x, "number"), ACB.read(y, "number"), ACB.read(z, "number"), ACB.read(instance, "number")
end

local function measuredDistance(unit)
    local distance, checked = ACB.safe(UnitDistanceSquared, unit)
    distance, checked = ACB.read(distance, "number"), ACB.read(checked, "boolean")
    if checked == true and distance and distance >= 0 then return distance end
    local x, y, z, instance = position(unit)
    local px, py, pz, playerInstance = position("player")
    if x and y and z and px and py and pz and instance and instance == playerInstance then
        return (x - px)^2 + (y - py)^2 + (z - pz)^2
    end
end

-- May a trade with this player go ahead? True, or false and what to tell the player.
function ACB.tradeDistanceOk(saved, peer)
    local unit = ACB.partnerUnit(peer)
    if not unit then
        return false, "Target your trade partner first. As in the game, trading works within about 11 yards."
    end
    -- If the game cannot say how far away they are (the call is missing or refuses), the trade is allowed.
    local near = ACB.read(ACB.safe(CheckInteractDistance, unit, TRADE_DISTANCE), "boolean")
    if near ~= true then
        local distance = measuredDistance(unit)
        if distance then near = distance <= 11.11^2 end
    end
    if near == false then
        local message = "Your partner is too far away. Move within about 11 yards."
        if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(message, 1, .4, .25) end
        return false, message
    end
    return true
end
