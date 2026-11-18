local _, ACB = ...

-- A history request fetches one copy, not the whole collection. Unsolicited and expired replies are ignored.
function ACB.newCardHistoryRequests(saved, send, now, after)
    local service, pending, served, servedOrder = {}, {}, {}, {}
    local serial, nextSend = 0, 0
    local function schedule(peer, packet, attempt, deadline)
        local at = math.max(now(), nextSend); nextSend = at + 1.05
        after(at - now(), function()
            if saved.inspectable == false or now() > deadline then return end
            if not send(peer, packet) and attempt < 3 then schedule(peer, packet, attempt + 1, deadline) end
        end)
    end
    function service:cancel(ticket) pending[ticket] = nil end
    function service:request(peer, key, index, callback)
        if type(peer) ~= "string" or not ACB.cards[key] or type(index) ~= "number" or index < 1 or index > 1000000000 or index % 1 ~= 0 then return nil, "Choose a card copy first." end
        local waiting = 0; for _ in pairs(pending) do waiting = waiting + 1 end
        if waiting >= 4 then return nil, "Wait for the current history request." end
        serial = serial + 1
        local ticket = ACB.sha256(peer .. "|" .. key .. "|" .. now() .. "|" .. serial):sub(1, 12)
        local request = { peer = peer, key = key, index = index, callback = callback, untilAt = now() + 25, parts = {} }
        pending[ticket] = request
        local ok, why = send(peer, table.concat({ "QH", ticket, ACB.shortKey(ACB.cards[key]), index }, "|"))
        if not ok then pending[ticket] = nil; return nil, why end
        after(25, function()
            if pending[ticket] == request then pending[ticket] = nil; callback(nil, nil, "History did not arrive. They need the latest addon, to allow viewing, and to be outdoors and out of combat.") end
        end)
        return ticket
    end
    function service:handle(peer, message)
        local ticket, short, index = message:match("^QH|([0-9a-f]+)|([cov]%d+)|(%d+)$")
        if ticket then
            if #ticket ~= 12 then return true end
            local key = ACB.longKey(short); index = tonumber(index)
            if not key or not ACB.cards[key] or index < 1 or index > 1000000000 then return true end
            if saved.inspectable == false then send(peer, "EH|" .. ticket .. "|private"); return true end
            if served[peer] and now() - served[peer] < 1 then return true end
            if nextSend - now() > 8 then send(peer, "EH|" .. ticket .. "|busy"); return true end
            if not served[peer] then
                if #servedOrder >= 64 then served[table.remove(servedOrder, 1)] = nil end
                servedOrder[#servedOrder + 1] = peer
            end
            served[peer] = now()
            local count = saved.counts[key] or 0
            local copy = ACB.cardCopyAt(saved, key, index)
            local body = count .. "|" .. (copy and ACB.encodeCardCopy(copy) or "0")
            local total = math.ceil(#body / 180)
            for part = 1, total do
                local packet = table.concat({ "PH", ticket, part .. "/" .. total, body:sub((part - 1) * 180 + 1, part * 180) }, "|")
                schedule(peer, packet, 1, now() + 23)
            end
            return true
        end
        local reason
        ticket, reason = message:match("^EH|([0-9a-f]+)|(%a+)$")
        if ticket then
            local request = pending[ticket]
            if request and peer == request.peer and now() <= request.untilAt then
                pending[ticket] = nil; request.callback(nil, nil, reason == "private" and "This binder is private." or "Their addon is busy. Try again in a moment.")
            end
            return true
        end
        local part, total, payload
        ticket, part, total, payload = message:match("^PH|([0-9a-f]+)|(%d+)/(%d+)|(.*)$")
        if not ticket then return false end
        local request = pending[ticket]; part, total = tonumber(part), tonumber(total)
        if not request or request.peer ~= peer or now() > request.untilAt or part < 1 or part > total or total > 6 or #payload > 180 then return true end
        if request.total and request.total ~= total then pending[ticket] = nil; request.callback(nil, nil, "History changed while loading. Try again."); return true end
        request.total = total
        if request.parts[part] and request.parts[part] ~= payload then pending[ticket] = nil; request.callback(nil, nil, "History changed while loading. Try again."); return true end
        request.parts[part] = payload
        for item = 1, total do if not request.parts[item] then return true end end
        pending[ticket] = nil
        local count, code = table.concat(request.parts):match("^(%d+)|(.*)$"); count = tonumber(count)
        if not count or count > 1000000000 then request.callback(nil, nil, "Invalid history reply."); return true end
        local copy = code ~= "0" and ACB.decodeCardCopy(code, request.key)
        if code ~= "0" and not copy then request.callback(nil, nil, "Invalid history reply."); return true end
        if request.index > count then request.callback(nil, count, "That copy is no longer in this binder.")
        else request.callback(copy or { key = request.key, source = "unknown", finder = "", place = "", at = 0 }, count) end
        return true
    end
    return service
end
