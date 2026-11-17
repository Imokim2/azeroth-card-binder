local _, ACB = ...
local active = setmetatable({}, { __mode = "k" })
local function digest(code) return ACB.sha256(code):sub(1, 12) end
local function card(key) return key and ACB.cards[key] ~= nil end
function ACB.cardCopyReserved(saved, key, id)
    local trade = active[saved]
    local s = trade and trade:active()
    local h = s and s.copyHistory
    return h and not s.closed and (s.sentConfirm or s.decision) and s.give == key
        and h.out and ((h.out.older and id == nil) or (not h.out.older and h.out.id == id)) or false
end
function ACB.newTradeHistory(saved, send, now, trade)
    if not ACB.cardHistoryEnabled(saved) then return end
    active[saved] = trade
    local history = {}
    local lastOutbound = -math.huge
    function history:sent() lastOutbound = now() end
    local function state(s)
        if not s or not s.modern or s.invited or not s.connected or s.closed then return end
        local h = s.copyHistory
        if not h or h.revision ~= s.revision or h.key ~= s.give then
            local out = card(s.give) and ACB.cardCopyOffer(saved, s.give, s.id, s.revision) or nil
            local code = out and ACB.encodeCardCopy(out) or "0"
            h = { revision = s.revision, key = s.give, out = out, code = code, hash = digest(code), next = 1,
                count = code == "0" and 0 or math.ceil(#code / 150), last = -math.huge, header = -math.huge }
            s.copyHistory = h
        end
        if h.peerRevision ~= s.theirRevision then
            h.peerRevision, h.inbox, h.into, h.received, h.acked, h.ackSent, h.ackPending = s.theirRevision, nil, nil, nil, nil, nil, nil
            h.next, h.header, h.last = 1, -math.huge, -math.huge
        end
        return h
    end
    function history:ready(s)
        if s and not card(s.give) and not card(s.take) then return true end
        local h = state(s)
        if not h or h.bad or not h.acked or not h.received or not h.ackSent then return false end
        if card(s.give) and not ACB.canGiveCardCopy(saved, s.give, h.out) then return false end
        if card(s.take) and (not ACB.validCardCopy(h.into, s.take) or ACB.hasCardCopyID(saved, h.into.id)) then return false end
        return true
    end
    local function status(s)
        if s.sentConfirm or s.decision then return end
        if history:ready(s) then trade.status = "Check both cards and their history, then click Accept."
        else trade.status = "Preparing card history. Both players need the latest addon." end
    end
    local function acknowledge(s, h)
        h.ackPending = true
    end
    function history:receive(s, message)
        local verb = message:sub(1, 2)
        if verb ~= "H|" and verb ~= "J|" and verb ~= "Y|" then return false end
        local h = state(s)
        if not h then return true end
        local id, revision, peerRevision, version, hash, total = message:match("^H|([%w%-]+)|(%d+)|(%d+)|(%d+)|([0-9a-f]+)|(%d+)$")
        if id then
            total, revision = tonumber(total), tonumber(revision)
            if id ~= s.id or revision ~= s.theirRevision or tonumber(peerRevision) ~= s.revision or version ~= "1" or #hash ~= 12 or total > 6 then return true end
            if h.inbox and (h.inbox.hash ~= hash or h.inbox.total ~= total) then
                h.bad = true; s.sentConfirm, s.peerConfirmed = nil, nil
                trade.status = "The offered card history changed. Cancel and start a new trade."
                return true
            end
            if not h.inbox then h.inbox = { hash = hash, total = total, parts = {} } end
            if total == 0 and not card(s.take) and hash == digest("0") then h.received = true end
            if h.received then acknowledge(s, h) end
            status(s); return true
        end
        local part, payload
        id, revision, peerRevision, part, total, payload = message:match("^J|([%w%-]+)|(%d+)|(%d+)|(%d+)/(%d+)|(.*)$")
        if id then
            revision, part, total = tonumber(revision), tonumber(part), tonumber(total)
            local box = h.inbox
            if id ~= s.id or revision ~= s.theirRevision or tonumber(peerRevision) ~= s.revision or not box or total ~= box.total or part < 1 or part > total or #payload > 150 then return true end
            if h.received then return true end
            if box.parts[part] and box.parts[part] ~= payload then h.bad = true; return true end
            box.parts[part] = payload
            for index = 1, total do if not box.parts[index] then return true end end
            local code = table.concat(box.parts)
            local copy = digest(code) == box.hash and ACB.decodeCardCopy(code, s.take)
            if not card(s.take) or not copy then h.bad = true; trade.status = "Card history did not match the offer. Cancel and try again."; return true end
            h.into, h.received = copy, true
            acknowledge(s, h); status(s); return true
        end
        id, revision, peerRevision, hash = message:match("^Y|([%w%-]+)|(%d+)|(%d+)|([0-9a-f]+)$")
        if id == s.id and tonumber(revision) == s.revision and tonumber(peerRevision) == s.theirRevision and hash == h.hash then h.acked = true; status(s) end
        return true
    end
    function history:knowsOffer(s) local h = state(s); return h and h.inbox ~= nil end
    function history:step(s, untilOffer)
        if s and not card(s.give) and not card(s.take) then return false end
        local h = state(s)
        if not h or h.bad or now() - lastOutbound < 1.05 or now() - h.last < 1.05 then return false end
        if not h.inbox and untilOffer and untilOffer < 1.05 then return false end
        h.last = now()
        local message
        if h.ackPending then
            message = table.concat({ "Y", s.id, s.theirRevision, s.revision, h.inbox.hash }, "|")
            if send(s.peer, message) then h.ackPending, h.ackSent, lastOutbound = nil, true, now() end
        elseif now() - h.header >= 8 or (not h.acked and h.next > h.count) then
            message = table.concat({ "H", s.id, s.revision, s.theirRevision, 1, h.hash, h.count }, "|")
            if send(s.peer, message) then h.header, h.next, lastOutbound = now(), 1, now() end
        elseif not h.acked and h.next <= h.count then
            local index = h.next
            message = table.concat({ "J", s.id, s.revision, s.theirRevision, index .. "/" .. h.count,
                h.code:sub((index - 1) * 150 + 1, index * 150) }, "|")
            if send(s.peer, message) then h.next, lastOutbound = index + 1, now() end
        end
        if not s.sentConfirm then status(s) end
        return message ~= nil
    end
    function history:context(s)
        if not self:ready(s) then return end
        if not card(s.give) and not card(s.take) then return { gift = not s.give or not s.take } end
        return { out = s.copyHistory.out, into = s.copyHistory.into, gift = not s.give or not s.take }
    end
    return history
end
