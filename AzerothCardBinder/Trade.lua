local _, ACB = ...

ACB.tradePrefix = "AzerothBinder1"

function ACB.newTrade(counts, now, makeID, send)
    local trade = { seen = {}, status = "Choose a partner and a duplicate to offer." }

    function trade:reset(status)
        self.session = nil
        self.status = status or "Preview cleared. Choose a partner to start again."
    end

    function trade:active()
        if self.session and now() >= self.session.expires then
            self:reset("Preview expired. Start a new one with your partner.")
        end
        return self.session
    end

    local function hasDuplicate(key)
        return ACB.cards[key] and (counts[key] or 0) >= 2
    end

    function trade:listen(peer)
        if self:active() or not peer then return end
        self.session = { peer = peer, expires = now() + 120 }
        self.status = "Listening for an offer from " .. peer .. "."
    end

    function trade:retry()
        local session = self:active()
        if not session or not session.give then return end
        local command = session.sentConfirm and "C" or (session.initiator and "O" or "R")
        local message = command .. "|" .. session.id .. "|" .. session.give
        if command == "C" then message = message .. "|" .. session.take end
        local sent, reason = send(session.peer, message)
        if sent then
            self.status = session.sentConfirm and "Confirmation sent again." or "Offer sent."
        else
            self.status = reason
        end
    end

    function trade:offer(peer, key)
        if self:active() or not peer then return end
        if not hasDuplicate(key) then
            self.status = "Choose a card with at least two copies."
            return
        end
        local id = makeID()
        self.seen[peer .. "|" .. id] = true
        self.session = { peer = peer, id = id, give = key, initiator = true, expires = now() + 120 }
        self:retry()
    end

    function trade:reply(key)
        local session = self:active()
        if not session or not session.take or session.give then return end
        if not hasDuplicate(key) or key == session.take then
            self.status = "Choose a different card with at least two copies."
            return
        end
        session.give = key
        self:retry()
    end

    function trade:confirm()
        local session = self:active()
        if not session or session.sentConfirm or not session.take or not session.give then return end
        if not hasDuplicate(session.give) then
            self.status = "The offered duplicate is no longer available."
            return
        end
        local sent, reason = send(session.peer, table.concat({ "C", session.id, session.give, session.take }, "|"))
        if sent then
            session.sentConfirm = true
            self.status = "Your confirmation was sent."
        else
            self.status = reason
        end
    end

    function trade:receive(peer, message)
        local session = self:active()
        if not session or session.peer ~= peer or type(message) ~= "string" or #message > 100 then return end
        local command, id, give, take = message:match("^([ORC])|([%w%-]+)|([%w:]+)(.*)$")
        if not id or #id > 36 or not ACB.cards[give] then return end

        if command == "O" and take == "" and not session.id then
            local seenKey = peer .. "|" .. id
            if self.seen[seenKey] then return end
            self.seen[seenKey] = true
            session.id, session.take = id, give
            self.status = "Offer received. Choose your duplicate and send a reply."
        elseif command == "R" and take == "" and id == session.id and session.initiator
            and not session.take and session.give ~= give then
            session.take = give
            self.status = "Reply received. Review both cards and confirm."
        elseif command == "C" and id == session.id and session.give and session.take
            and session.take == give and take == "|" .. session.give then
            session.peerConfirmed = true
            self.status = "Partner confirmed the displayed cards."
        end
    end

    return trade
end
