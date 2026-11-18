local _, ACB = ...

-- Informational, per-copy provenance. These records never grant cards or change the Ranked ledger.
local sources = { drop = true, pack = true, crafted = true, activity = true, unknown = true }
local methods = { found = true, trade = true, gift = true, returned = true }
local function whole(n, high) return type(n) == "number" and n == math.floor(n) and n >= 0 and n <= high end
local function utf8(s)
    local index = 1
    while index <= #s do
        local first, second = s:byte(index), s:byte(index + 1)
        local size = first < 128 and 1 or first >= 194 and first <= 223 and 2 or first >= 224 and first <= 239 and 3 or first >= 240 and first <= 244 and 4
        if not size or index + size - 1 > #s then return false end
        for offset = 1, size - 1 do local byte = s:byte(index + offset); if byte < 128 or byte > 191 then return false end end
        if (first == 224 and second < 160) or (first == 237 and second > 159) or (first == 240 and second < 144) or (first == 244 and second > 143) then return false end
        index = index + size
    end
    return true
end
local function text(s, limit) return type(s) == "string" and #s <= limit and not s:find("[%z\1-\31\127|]") and utf8(s) end
local function hex(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function unhex(s, limit)
    if #s > limit * 2 or #s % 2 ~= 0 or s:find("[^0-9a-f]") then return end
    local value = s:gsub("..", function(c) return string.char(tonumber(c, 16)) end)
    if text(value, limit) then return value end
end
function ACB.validCardCopy(copy, key)
    return type(copy) == "table" and type(copy.id) == "string" and #copy.id == 32 and not copy.id:find("[^0-9a-f]")
        and type(copy.key) == "string" and ACB.cards[copy.key] ~= nil and (not key or key == copy.key)
        and text(copy.finder, 80) and text(copy.place, 120) and text(copy.from, 80)
        and whole(copy.at, 4102444800) and whole(copy.received, 4102444800) and whole(copy.hops, 1000000)
        and sources[copy.source] == true and methods[copy.how] == true
        and ((copy.source == "unknown" and copy.finder == "" and copy.place == "" and copy.at == 0)
            or (copy.source ~= "unknown" and copy.finder ~= "" and copy.at > 0))
end
function ACB.encodeCardCopy(copy)
    if not ACB.validCardCopy(copy) then return end
    return table.concat({ "1", copy.id, copy.key, hex(copy.finder), copy.at, hex(copy.place), copy.source,
        hex(copy.from), copy.received, copy.how, copy.hops }, "|")
end
function ACB.decodeCardCopy(code, key)
    if type(code) ~= "string" or #code > 850 then return end
    local f = {}; for value in (code .. "|"):gmatch("(.-)|") do f[#f + 1] = value end
    if #f ~= 11 or f[1] ~= "1" then return end
    for _, index in ipairs({ 5, 9, 11 }) do if not f[index]:match("^%d+$") then return end end
    local copy = { id = f[2], key = f[3], finder = unhex(f[4], 80), at = tonumber(f[5]), place = unhex(f[6], 120),
        source = f[7], from = unhex(f[8], 80), received = tonumber(f[9]), how = f[10], hops = tonumber(f[11]) }
    if ACB.validCardCopy(copy, key) then return copy end
end
function ACB.cardHistoryEnabled(saved) return type(saved) == "table" and saved.cardHistoryVersion == 1 end
function ACB.cleanCardHistory(saved)
    saved.cardCopies = type(saved.cardCopies) == "table" and saved.cardCopies or {}
    saved.cardCopyChoice = type(saved.cardCopyChoice) == "table" and saved.cardCopyChoice or {}
    saved.cardHistoryDonations = type(saved.cardHistoryDonations) == "table" and saved.cardHistoryDonations or {}
    saved.cardHistorySerial = whole(saved.cardHistorySerial, 9007199254740000) and saved.cardHistorySerial or 0
    local ids = {}
    for key, list in pairs(saved.cardCopies) do
        local keep, count = {}, saved.counts[key] or 0
        if ACB.cards[key] and type(list) == "table" then
            for _, code in ipairs(list) do
                local copy = ACB.decodeCardCopy(code, key)
                if copy and not ids[copy.id] and #keep < count then keep[#keep + 1] = code; ids[copy.id] = key end
            end
        end
        saved.cardCopies[key] = #keep > 0 and keep or nil
    end
    for key, id in pairs(saved.cardCopyChoice) do
        if not ACB.cards[key] or type(id) ~= "string" or (id ~= "older" and ids[id] ~= key) then saved.cardCopyChoice[key] = nil end
    end
    for operation, code in pairs(saved.cardHistoryDonations) do
        if type(operation) ~= "string" or #operation ~= 32 or operation:find("[^0-9a-f]") or not ACB.decodeCardCopy(code) then saved.cardHistoryDonations[operation] = nil end
    end
end
function ACB.enableCardHistory(saved)
    ACB.cleanCardHistory(saved); saved.cardHistoryVersion = 1
end
local function list(saved, key) return saved.cardCopies and saved.cardCopies[key] or {} end
function ACB.cardCopyCounts(saved, key)
    local tracked = #list(saved, key)
    return tracked, math.max(0, (saved.counts[key] or 0) - tracked)
end
function ACB.cardCopyAt(saved, key, index)
    if not whole(index, 1000000000) or index < 1 or index > (saved.counts[key] or 0) then return end
    local code = list(saved, key)[index]
    return code and ACB.decodeCardCopy(code, key) or { key = key, source = "unknown", finder = "", place = "", at = 0 }
end
function ACB.selectedCardCopy(saved, key)
    local choice = saved.cardCopyChoice and saved.cardCopyChoice[key]
    local _, older = ACB.cardCopyCounts(saved, key)
    if choice == "older" and older > 0 then return end
    for _, code in ipairs(list(saved, key)) do local copy = ACB.decodeCardCopy(code, key); if copy and copy.id == choice then return copy end end
    return ACB.decodeCardCopy(list(saved, key)[1], key)
end
local function ownsID(saved, key, id)
    for _, code in ipairs(list(saved, key)) do local copy = ACB.decodeCardCopy(code, key); if copy and copy.id == id then return true end end
    return false
end
local function stamp() return math.max(0, math.floor(ACB.read(ACB.safe(time), "number") or 0)) end
function ACB.historyFinder()
    local first, surname = ACB.safe(UnitFullName, "player")
    first, surname = ACB.read(first, "string"), ACB.read(surname, "string")
    if first then
        local name = first .. (surname and surname ~= "" and (" " .. surname) or "")
        if text(name, 80) then return name end
    end
    local peer = ACB.read(ACB.safe(ACB.characterName), "string") or ""
    return (peer:gsub("%-", " "):gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end)):sub(1, 80)
end
function ACB.historyPlace()
    local place = ACB.read(ACB.safe(ACB.currentPlaceName), "string")
        or ACB.read(ACB.safe(GetRealZoneText), "string") or ACB.read(ACB.safe(GetZoneText), "string") or ""
    return text(place, 120) and place or ""
end
local function freshID(saved, salt)
    saved.cardHistorySerial = (saved.cardHistorySerial or 0) + 1
    return ACB.sha256(table.concat({ "copy1", saved.modeSetupID or "", saved.head and saved.head.hash or "", salt,
        ACB.historyFinder(), stamp(), saved.cardHistorySerial }, "|")):sub(1, 32)
end
function ACB.cardCopyOffer(saved, key, session, revision)
    if not ACB.cards[key] then return end
    local copy = ACB.selectedCardCopy(saved, key)
    if copy then return copy end
    if (saved.counts[key] or 0) < 1 then return end
    return { id = ACB.sha256("older-copy|" .. session .. "|" .. revision .. "|" .. key .. "|" .. ACB.historyFinder() .. "|" .. (saved.modeSetupID or "")):sub(1, 32),
        key = key, finder = "", at = 0, place = "", source = "unknown", from = "", received = 0, how = "found", hops = 0, older = true }
end
function ACB.canGiveCardCopy(saved, key, copy)
    if not ACB.cards[key] then return copy == nil end
    if not ACB.validCardCopy(copy, key) then return false end
    if ownsID(saved, key, copy.id) then return true end
    local _, older = ACB.cardCopyCounts(saved, key)
    return copy.older == true and copy.source == "unknown" and older > 0
end
function ACB.hasCardCopyID(saved, id)
    for key in pairs(saved.cardCopies or {}) do if ownsID(saved, key, id) then return true end end
    return false
end
local function remove(saved, key, copy)
    if not copy or copy.older then return end
    local copies = list(saved, key)
    for index, code in ipairs(copies) do if ACB.decodeCardCopy(code, key).id == copy.id then table.remove(copies, index); break end end
    if #copies == 0 then saved.cardCopies[key] = nil end
    if saved.cardCopyChoice[key] == copy.id then saved.cardCopyChoice[key] = nil end
end
local function put(saved, key, copy)
    local code = ACB.encodeCardCopy(copy)
    if not code or ACB.hasCardCopyID(saved, copy.id) then return false end
    saved.cardCopies[key] = saved.cardCopies[key] or {}; table.insert(saved.cardCopies[key], code)
    return true
end
function ACB.spendCardCopy(saved, key)
    if not ACB.cardHistoryEnabled(saved) then return end
    local _, older = ACB.cardCopyCounts(saved, key)
    if older > 0 and (older > 1 or not ACB.cardCopyReserved or not ACB.cardCopyReserved(saved, key, nil)) then return { older = true } end
    for _, code in ipairs(list(saved, key)) do
        local copy = ACB.decodeCardCopy(code, key)
        if not ACB.cardCopyReserved or not ACB.cardCopyReserved(saved, key, copy.id) then return copy end
    end
    return false
end
function ACB.recordCardHistory(saved, kind, key, fields)
    if not ACB.cardHistoryEnabled(saved) or not ACB.cards[key] then return end
    fields = fields or {}
    if kind == "drop" or kind == "packCard" or kind == "craft" then
        local source = kind == "craft" and "crafted" or kind == "packCard" and "pack" or ACB.cards[key].activity and "activity" or "drop"
        local finder, at = ACB.historyFinder(), stamp()
        if finder == "" or at == 0 then source, finder, at = "unknown", "", 0 end
        put(saved, key, { id = freshID(saved, kind .. "|" .. key), key = key, finder = finder, at = at,
            place = source == "unknown" and "" or ACB.historyPlace(), source = source, from = "", received = 0, how = "found", hops = 0 })
    elseif kind == "tradeOut" or kind == "recycle" then remove(saved, key, fields.historyCopy)
    elseif kind == "tradeIn" and fields.historyCopy then
        local copy = ACB.decodeCardCopy(ACB.encodeCardCopy(fields.historyCopy), key)
        if not copy then return end
        copy.from, copy.received = fields.partner:gsub("%-", " "), stamp()
        copy.how, copy.hops = fields.historyGift and "gift" or "trade", math.min(1000000, copy.hops + 1)
        put(saved, key, copy)
    end
end
function ACB.donateCardCopy(saved, key, operation)
    if not ACB.cardHistoryEnabled(saved) then return end
    local copy = ACB.cardCopyOffer(saved, key, operation, 1)
    if copy then saved.cardHistoryDonations[operation] = ACB.encodeCardCopy(copy); remove(saved, key, copy) end
end
function ACB.returnCardCopy(saved, operation)
    local copy = saved.cardHistoryDonations and ACB.decodeCardCopy(saved.cardHistoryDonations[operation])
    if copy then copy.from, copy.how, copy.received = "Guild binder", "returned", stamp(); put(saved, copy.key, copy); saved.cardHistoryDonations[operation] = nil end
end
