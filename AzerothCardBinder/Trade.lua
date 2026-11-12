local _, ACB = ...

ACB.tradePrefix = "AzerothBinder1"

-- A swap runs over addon whispers: the sender offers a card they own (O), the partner replies with one
-- of their own (R), and each side confirms the exact pair (C). When a side has sent its confirmation
-- and received the partner's, it applies the swap once through `apply`.
-- `wanted` returns the cards the player is looking for, as a list of catalog keys.
function ACB.newTrade(counts, now, makeID, send, apply, wanted, allowed, saved)
    local trade = { seen = {}, status = "Choose a player and a card, then click Start trade." }
    apply = apply or function() return true end
    -- `allowed(peer)` may say no, with a reason (the trading distance); with none given every trade may go ahead.
    allowed = allowed or function() return true end

    function trade:reset(status)
        self.session = nil
        self.status = status or "Choose a player and a card to start a new trade."
    end

    function trade:active()
        local session = self.session
        if session and now() >= session.expires then
            self:reset(session.applied and self.status or "Trade expired. Start a new one with your partner.")
        end
        return self.session
    end

    -- A trade that has already been applied stays around for a while only so a lost confirmation can
    -- be re-sent; it must not block a new trade.
    local function busy(self)
        local session = self:active()
        return session and not session.applied
    end

    -- Any card in the binder can be traded, including a last copy.
    local function owns(key)
        return ACB.cards[key] and (counts[key] or 0) >= 1
    end

    local function confirmation(session)
        return table.concat({ "C", session.id, session.give, session.take }, "|")
    end

    function trade:listen(peer)
        if busy(self) or not peer then return end
        self.session = { peer = peer, expires = now() + 120 }
        self.status = "Listening for an offer from " .. peer .. "."
    end

    function trade:retry()
        local session = self:active()
        if not session or not session.give then return end
        local message = session.sentConfirm and confirmation(session)
            or ((session.initiator and "O" or "R") .. "|" .. session.id .. "|" .. session.give)
        local sent, reason = send(session.peer, message)
        if not sent then
            self.status = reason
        elseif not session.applied then
            self.status = session.sentConfirm and "Confirmation sent again." or "Offer sent."
        end
    end

    function trade:offer(peer, key)
        if busy(self) or not peer then return end
        local ok, why = allowed(peer)
        if not ok then
            self.status = why
            return
        end
        if not owns(key) then
            self.status = "Choose a card from your binder."
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
        local ok, why = allowed(session.peer)
        if not ok then
            self.status = why
            return
        end
        if not owns(key) or key == session.take then
            self.status = "Choose a different card from your binder."
            return
        end
        session.give = key
        self:retry()
    end

    -- Apply the swap once both confirmations are in.
    local function finish(self)
        local session = self.session
        if not session or session.applied or not session.sentConfirm or not session.peerConfirmed then return end
        session.applied = true
        session.expires = now() + 120
        local give, take = ACB.cards[session.give], ACB.cards[session.take]
        if apply(session.give, session.take, session.peer, session.id) then
            self.status = ("Trade complete. You gave %s and received %s."):format(give.name, take.name)
        else
            self.status = "The trade could not finish because the card you offered is no longer in your binder."
        end
    end

    -- Tell the partner which spare cards (second copies) you have (S) and which cards you are looking for (W).
    function trade:shareLists()
        local session = self:active()
        if not session then
            self.status = "Start a trade first."
            return
        end
        local spares = {}
        for key, count in pairs(counts) do
            if ACB.cards[key] and count >= 2 then spares[#spares + 1] = key end
        end
        table.sort(spares)
        local function pack(command, list)
            local out, length = {}, #command + 1
            for _, key in ipairs(list) do
                if length + #key + 1 > 98 then break end
                out[#out + 1] = key
                length = length + #key + 1
            end
            return command .. "|" .. table.concat(out, ",")
        end
        local first, reason = send(session.peer, pack("S", spares))
        local second = first and send(session.peer, pack("W", wanted and wanted() or {}))
        self.status = second and "Your spare and wanted cards were shared." or (reason or "Your lists could not be sent.")
    end

    function trade:confirm()
        local session = self:active()
        if not session or session.sentConfirm or not session.take or not session.give then return end
        local ok, why = allowed(session.peer)
        if not ok then
            self.status = why
            return
        end
        if not owns(session.give) then
            self.status = "The card you offered is no longer in your binder."
            return
        end
        local sent, reason = send(session.peer, confirmation(session))
        if sent then
            session.sentConfirm = true
            self.status = "Your confirmation was sent."
            finish(self)
        else
            self.status = reason
        end
    end

    function trade:receive(peer, message)
        local session = self:active()
        if not session or session.peer ~= peer or type(message) ~= "string" or #message > 100 then return end
        local listCommand, list = message:match("^([SW])|([%w:,]*)$")
        if listCommand then
            local items = {}
            for key in list:gmatch("[^,]+") do
                if ACB.cards[key] and #items < 12 then items[#items + 1] = key end
            end
            if listCommand == "S" then session.theirSpares = items else session.theirWants = items end
            self.status = "Your partner shared their " .. (listCommand == "S" and "spare" or "wanted") .. " cards."
            return
        end
        local command, id, give, take = message:match("^([ORC])|([%w%-]+)|([%w:]+)(.*)$")
        if not id or #id > 36 or not ACB.cards[give] then return end

        if command == "O" and take == "" and not session.id then
            local seenKey = peer .. "|" .. id
            if self.seen[seenKey] then return end
            self.seen[seenKey] = true
            session.id, session.take = id, give
            self.status = "Offer received. Choose your card and send a reply."
        elseif command == "R" and take == "" and id == session.id and session.initiator
            and not session.take and session.give ~= give then
            session.take = give
            self.status = "Reply received. Review both cards and accept."
        elseif command == "C" and id == session.id and session.give and session.take
            and session.take == give and take == "|" .. session.give then
            if session.peerConfirmed then
                -- The partner re-sent, so they probably missed our confirmation. Answer a couple of
                -- times without starting an endless exchange.
                if session.sentConfirm and (session.echoes or 0) < 2 then
                    session.echoes = (session.echoes or 0) + 1
                    send(session.peer, confirmation(session))
                end
                return
            end
            session.peerConfirmed = true
            self.status = "Partner accepted the displayed cards."
            finish(self)
        end
    end

    if ACB.addTradeSession then ACB.addTradeSession(trade, counts, now, makeID, send, apply, allowed, saved) end
    return trade
end
