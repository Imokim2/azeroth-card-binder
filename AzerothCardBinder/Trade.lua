local _, ACB = ...

ACB.tradePrefix = "AzerothBinder1"

-- A swap runs over addon whispers: the sender offers a card they own (O), the partner replies with one
-- of their own (R), and each side confirms the exact pair (C). When a side has sent its confirmation
-- and received the partner's, it applies the swap once through `apply`.
-- `wanted` returns the cards the player is looking for, as a list of catalog keys.
function ACB.newTrade(counts, now, makeID, send, apply, wanted, allowed)
    local trade = { seen = {}, status = "Choose a partner and a card to offer." }
    apply = apply or function() return true end
    -- `allowed(peer)` may say no, with a reason (the trading distance); with none given every trade may go ahead.
    allowed = allowed or function() return true end

    function trade:reset(status)
        self.session = nil
        self.status = status or "Trade cleared. Choose a partner to start again."
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

    -- A proposal names both cards: what the sender gives (give) and the card of the partner they want for it (want).
    local function proposalMessage(session)
        return table.concat({ "P", session.id, session.give, session.want }, "|")
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
            or (session.want and session.initiator and not session.take and proposalMessage(session))
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

    -- Offer one of your cards (give) for a card you saw in the partner's binder (want). They accept or decline.
    function trade:propose(peer, give, want)
        if busy(self) or not peer then
            self.status = "Finish or cancel the trade you have open first."
            return false
        end
        local ok, why = allowed(peer)
        if not ok then
            self.status = why
            return false
        end
        if not owns(give) then
            self.status = "Choose a card from your binder."
            return false
        end
        if not ACB.cards[want] or want == give then
            self.status = "Choose the card you want from their binder."
            return false
        end
        local id = makeID()
        self.seen[peer .. "|" .. id] = true
        self.session = { peer = peer, id = id, give = give, want = want, initiator = true, expires = now() + 120 }
        self:retry()
        if self.session and self.status == "Offer sent." then
            self.status = ("Offer sent: your %s for their %s. Waiting for them to accept."):format(ACB.cards[give].name, ACB.cards[want].name)
        end
        return true
    end

    -- Accept an offer made to you: send the card they asked for, and confirm the pair.
    function trade:accept()
        local session = self:active()
        if not session or not session.incoming or session.give then
            self.status = "There is no offer to accept."
            return false
        end
        self:reply(session.want)
        if session.give then self:confirm() end
        return session.give ~= nil
    end

    function trade:decline()
        local session = self:active()
        if not session or not session.incoming or session.give then
            self.status = "There is no offer to decline."
            return false
        end
        send(session.peer, "X|" .. session.id)
        self:reset("Offer declined.")
        return true
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

    -- Somebody offers a card for one of yours. Said only if you own the card they ask for, at most once in a while per
    -- player, and never over a trade you have open.
    local proposedAt = {}
    local function receiveProposal(self, peer, id, give, want)
        if #id > 36 or not ACB.cards[give] or not ACB.cards[want] or give == want or not owns(want) then return end
        local at = now()
        if proposedAt[peer] and at < proposedAt[peer] then return end
        proposedAt[peer] = at + 10
        local key = peer .. "|" .. id
        if self.seen[key] then return end
        self.seen[key] = true
        local current = self:active()
        if current and not current.applied and not (current.peer == peer and not current.give and not current.take) then return end
        self.session = { peer = peer, id = id, take = give, want = want, incoming = true, expires = at + 120 }
        self.status = ("%s offers %s for your %s. Accept or decline."):format(peer, ACB.cards[give].name, ACB.cards[want].name)
        if self.notify then
            self.notify(("%s offers %s for your %s. Type /acb trade accept, or open the Trade tab."):format(
                peer, ACB.cards[give].name, ACB.cards[want].name))
        end
    end

    function trade:receive(peer, message)
        if type(message) == "string" and #message <= 100 then
            local id, give, want = message:match("^P|([%w%-]+)|(%a+:%d+)|(%a+:%d+)$")
            if id then return receiveProposal(self, peer, id, give, want) end
        end
        local session = self:active()
        if not session or session.peer ~= peer or type(message) ~= "string" or #message > 100 then return end
        local declined = message:match("^X|([%w%-]+)$")
        if declined then
            if declined == session.id and session.initiator and not session.take then
                self:reset(peer .. " declined your offer.")
                if self.notify then self.notify(self.status) end
            end
            return
        end
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
            and not session.take and session.give ~= give and (not session.want or give == session.want) then
            session.take = give
            self.status = "Reply received. Review both cards and accept."
            -- A proposal already named the card, so the proposer agreed to this pair when they sent it.
            if session.want then
                self:confirm()
                if self.notify then self.notify(peer .. " accepted your offer.") end
            end
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

    return trade
end
