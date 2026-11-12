local _, ACB = ...

-- The simple trade/gift flow. Legacy O/R/C sessions remain readable by Trade.lua;
-- I/U/A/F/D messages carry revisioned offers and a single coordinator's decision.
function ACB.addTradeSession(trade, counts, now, makeID, send, apply, allowed)
    local legacyReceive, legacyConfirm = trade.receive, trade.confirm
    local lastInvite, elapsed
    local terminal, terminalOrder = {}, {}
    local function wire(key) return key or "0" end
    local function valid(key) return key == "0" or ACB.cards[key] ~= nil end
    local function owns(key) return not key or (ACB.cards[key] and (counts[key] or 0) > 0) end
    local function current()
        local s = trade:active()
        return s and s.modern and s
    end
    local function packet(s, command)
        return table.concat({ command, s.id, s.revision, s.theirRevision, wire(s.give), wire(s.take) }, "|")
    end
    local function transmit(s, message)
        local ok, why = send(s.peer, message)
        if not ok then trade.status = why or "Could not reach that player. Trying again." end
        return ok
    end
    local function offer(s, invite)
        return transmit(s, invite and table.concat({ "I", s.id, wire(s.give), s.gift and "g" or "t" }, "|")
            or table.concat({ "U", s.id, s.revision, wire(s.give) }, "|"))
    end
    local function close(s, status)
        s.closed, s.cancelPending, s.expires = true, nil, now() + 120
        trade.status = status
        local key = s.peer .. "|" .. s.id
        if not terminal[key] then
            terminalOrder[#terminalOrder + 1] = key
            if #terminalOrder > 64 then terminal[table.remove(terminalOrder, 1)] = nil end
        end
        terminal[key] = s
    end
    local function finish(s)
        if s.applied then return true end
        if not apply(s.give, s.take, s.peer, s.id) then
            s.failed = true
            close(s, "Trade stopped. An offered card is no longer available.")
            return false
        end
        s.applied = true
        local out, into = ACB.cards[s.give], ACB.cards[s.take]
        close(s, out and into and ("Trade complete. You received %s."):format(into.name)
            or out and ("Gift sent: %s."):format(out.name) or ("Gift received: %s."):format(into.name))
        return true
    end
    local function decide(s)
        if not s.initiator or s.closed or s.cancelPending or not s.sentConfirm or not s.peerConfirmed then return end
        s.decision, s.expires = "commit", math.huge
        transmit(s, packet(s, "F"))
    end
    local function changed(s)
        s.sentConfirm, s.peerConfirmed = nil, nil
        s.expires = now() + 120
        trade.status = "Check both sides, then click Accept."
    end

    function trade:canAccept()
        local s = current()
        return s ~= nil and not s.closed and not s.cancelPending and s.connected == true and not s.sentConfirm
            and (s.give ~= nil or s.take ~= nil) and s.give ~= s.take and owns(s.give) == true
    end

    function trade:start(peer, key, gift)
        local old = self:active()
        if old and not old.applied and not old.closed then return end
        if not peer or not owns(key) or (gift and not key) then self.status = "Choose a player and a card first." return end
        local ok, why = allowed(peer)
        if not ok then self.status = why return end
        local s = { modern = true, initiator = true, peer = peer, id = makeID(), give = key, gift = gift == true,
            revision = 1, theirRevision = 0, expires = now() + 120 }
        self.session = s
        self.seen[peer .. "|" .. s.id] = true
        self.status = "Waiting for the other player to join. You both need the latest addon."
        offer(s, true)
    end

    function trade:change(key)
        local s = current()
        if not s or s.closed or s.cancelPending or s.decision then return false end
        if s.sentConfirm then self.status = "You accepted. Wait for the other player, or cancel." return false end
        if not owns(key) or s.revision >= 9999 or (s.gift and (not s.initiator or not key)) then return false end
        if key == s.give then return true end
        s.give, s.revision = key, s.revision + 1
        changed(s)
        offer(s)
        return true
    end

    function trade:cancel()
        local s = current()
        if not s or s.closed then self:reset("Trade cancelled.") return end
        if s.initiator then
            if s.decision == "commit" then transmit(s, packet(s, "F")) return end
            close(s, "Trade cancelled. No cards were moved.")
            s.cancelled = true
            transmit(s, "X|" .. s.id)
        else
            s.cancelPending = true
            self.status = "Cancelling trade..."
            transmit(s, "K|" .. s.id)
        end
    end

    function trade:confirm()
        local s = current()
        if not s then return legacyConfirm(self) end
        if not self:canAccept() then return end
        local ok, why = allowed(s.peer)
        if not ok then self.status = why return end
        s.sentConfirm, s.expires = true, math.huge
        self.status = "You accepted. Waiting for the other player."
        if not transmit(s, packet(s, "A")) then s.sentConfirm = nil return end
        decide(s)
    end

    function trade:receive(peer, message)
        if type(peer) ~= "string" or type(message) ~= "string" or #message > 100 then return end
        local verb, incoming = message:match("^([A-Z])|([%w%-]+)")
        local done = incoming and terminal[peer .. "|" .. incoming]
        if done then
            if done.cancelled and (verb == "K" or verb == "I" or verb == "A" or verb == "U") then send(peer, "X|" .. incoming)
            elseif done.applied and not done.initiator and verb == "F" then send(peer, "D|" .. incoming)
            elseif done.applied and done.initiator and verb == "K" then send(peer, packet(done, "F"))
            elseif done.failed and verb == "F" then send(peer, "E|" .. incoming) end
            return
        end
        local id, key, mode = message:match("^I|([%w%-]+)|([%w:]+)|([tg])$")
        if id then
            if #id > 36 or not valid(key) or (mode == "g" and key == "0") then return end
            local s = self:active()
            if s and s.modern and s.id == id and s.peer == peer then
                if s.cancelled then transmit(s, "X|" .. id)
                elseif not s.closed then offer(s) end
                return
            end
            if (s and not s.closed and not s.applied) or self.seen[peer .. "|" .. id]
                or (lastInvite and now() - lastInvite < 3) then return end
            lastInvite = now()
            self.seen[peer .. "|" .. id] = true
            s = { modern = true, peer = peer, id = id, take = key ~= "0" and key or nil, gift = mode == "g",
                revision = 1, theirRevision = 1, connected = true, expires = now() + 120 }
            self.session = s
            self.status = s.gift and "A gift for you. Check the card, then click Accept."
                or "Choose a card, or leave your side empty to receive a gift."
            offer(s)
            return true
        end
        local s = current()
        if not s or not s.modern then return legacyReceive(self, peer, message) end
        if s.peer ~= peer then return end
        local updateId, revision, newKey = message:match("^U|([%w%-]+)|(%d+)|([%w:]+)$")
        if updateId then
            local number = tonumber(revision)
            if s.closed or s.decision or updateId ~= s.id or not valid(newKey) or number < 1 or number > 9999 then return end
            if s.gift and ((s.initiator and newKey ~= "0") or (not s.initiator and newKey == "0")) then return end
            if number > s.theirRevision then
                s.take, s.theirRevision, s.connected = newKey ~= "0" and newKey or nil, number, true
                changed(s)
            end
            return
        end
        local command, confirmId, mine, theirs, give, take = message:match("^([AF])|([%w%-]+)|(%d+)|(%d+)|([%w:]+)|([%w:]+)$")
        if command then
            if confirmId ~= s.id or tonumber(mine) ~= s.theirRevision or tonumber(theirs) ~= s.revision
                or give ~= wire(s.take) or take ~= wire(s.give) or (not s.give and not s.take) or s.give == s.take then return end
            if command == "A" and not s.closed and not s.cancelPending then
                s.peerConfirmed = true
                self.status = s.sentConfirm and "Both accepted. Finishing trade..." or "The other player accepted. Check both sides and click Accept."
                decide(s)
            elseif command == "F" and not s.initiator and s.sentConfirm and not s.cancelled then
                if finish(s) then transmit(s, "D|" .. s.id) else transmit(s, "E|" .. s.id) end
            end
            return
        end
        local simple, simpleId = message:match("^([DKXE])|([%w%-]+)$")
        if simpleId ~= s.id then return end
        if simple == "D" and s.initiator and s.decision == "commit" then
            finish(s)
        elseif simple == "K" and s.initiator then
            if s.decision == "commit" then transmit(s, packet(s, "F"))
            else self:cancel() end
        elseif simple == "X" and not s.initiator and not s.applied then
            s.cancelled = true
            close(s, "Trade cancelled. No cards were moved.")
        elseif simple == "E" and s.initiator and not s.applied then
            close(s, "Trade stopped. The other player's card is no longer available.")
        end
    end

    function trade:step(dt)
        elapsed = (elapsed or 0) + dt
        if elapsed < 2 then return end
        elapsed = 0
        local s = current()
        if not s or s.closed then return true end
        if s.cancelPending then transmit(s, "K|" .. s.id)
        elseif s.decision == "commit" then transmit(s, packet(s, "F"))
        elseif s.sentConfirm then transmit(s, packet(s, "A"))
        else
            if s.initiator and not s.connected then
                -- Nobody has answered the invitation: it may be a player of the other faction (see Link.lua).
                s.silent = (s.silent or 0) + 1
                if s.silent == 3 and ACB.forceLink then ACB.forceLink(s.peer) end
            end
            offer(s, s.initiator and not s.connected)
        end
        return true
    end
end
