local _, ACB = ...

-- Two small requests between players, over the same whispers as binder viewing (docs: Social.lua):
--   "A|<card>"       asking a player for a card you are looking for. They are told only if they own it.
--   "L?" and "L|..." asking a player what they are looking for, and their answer (their wanted list).
-- Every request is paced on both sides so none can be used to flood anyone, and a player who keeps their binder private
-- answers neither.

local ASK_ANY_GAP, ASK_SAME_GAP, ASK_HEARD_GAP = 3, 30, 10 -- one ask every few seconds; the same card to the same player not for half a minute; a player hears from one other every ten
local LIST_GAP, LIST_WINDOW, NO_ANSWER_AFTER = 5, 30, 8 -- a player is asked or answers at most every 5 seconds, and has 30 to answer

-- `send(peer, message)` whispers, `now()` gives seconds, `after(delay, action)` runs later, `report(text)` prints to chat.
function ACB.newRequests(saved, send, now, after, report)
    local requests = {}
    local askedAt, askedBy, lastAsk = {}, {}, 0
    local listWindow, listedTo, listAsked = {}, {}, {} -- wanted lists: who we are waiting for, who we answered, when we asked

    -- Expect a wanted list from this player until `until` (their binder view sends one after the binder).
    function requests:expectList(peer, expires) listWindow[peer] = expires end

    -- The cards you are looking for, as one message (up to 24; the total is in it).
    function requests:listMessage()
        local wanted = ACB.wantedCards(saved)
        local keys = {}
        for index = 1, math.min(#wanted, 24) do keys[index] = ACB.shortKey(ACB.cards[wanted[index]]) end
        return ("L|%d|%s"):format(#wanted, table.concat(keys, ","))
    end

    -- Ask a player what they are looking for. Their list is shown on the Wanted tab when it arrives.
    function requests:requestWanted(peer)
        if not peer then return false, "Target a player first." end
        local at = now()
        if listAsked[peer] and at < listAsked[peer] then return false, "You asked them a moment ago." end
        local sent, reason = send(peer, "L?")
        if not sent then return false, reason end
        listAsked[peer] = at + LIST_GAP
        local window = at + LIST_WINDOW
        listWindow[peer] = window
        after(NO_ANSWER_AFTER, function()
            if listWindow[peer] == window then
                report(("No answer from %s yet. They need this add-on, to be near, and to allow viewing (Settings)."):format(peer))
            end
        end)
        return true
    end

    -- Ask a player for a card you are looking for.
    function requests:ask(peer, card)
        if not peer then return false, "Target a player or enter a player's name first." end
        if not card then return false, "There is no card with that name." end
        local at = now()
        if at < lastAsk + ASK_ANY_GAP then return false, "Wait a moment before asking again." end
        local gate = peer .. "|" .. card.key
        if askedAt[gate] and at < askedAt[gate] then return false, "You asked them for that card a moment ago." end
        local sent, reason = send(peer, "A|" .. card.key)
        if not sent then return false, reason end
        askedAt[gate], lastAsk = at + ASK_SAME_GAP, at
        report(("Asked %s for %s."):format(peer, ACB.cardLink(card, false)))
        return true
    end

    -- Deal with a message if it is one of these. Returns true when it was, so the caller need look no further.
    function requests:handle(peer, message)
        if message == "L?" then
            -- Someone asks what you are looking for. Answered unless you keep your binder private, and not too often.
            if saved.inspectable ~= false then
                local at = now()
                if not (listedTo[peer] and at < listedTo[peer]) then
                    listedTo[peer] = at + LIST_GAP
                    send(peer, self:listMessage())
                end
            end
            return true
        end
        local total, list = message:match("^L|(%d+)|([%w,]*)$")
        if total then
            -- Only an answer to our own question counts.
            if listWindow[peer] and now() <= listWindow[peer] then
                listWindow[peer] = nil
                local cards = {}
                for short in list:gmatch("[co]%d+") do
                    local key = ACB.longKey(short)
                    if key and ACB.cards[key] and #cards < 24 then cards[#cards + 1] = key end
                end
                local count = tonumber(total) or #cards
                ACB.heardWanted[peer] = { at = now(), cards = cards, total = count }
                report(#cards == 0 and (peer .. " is not looking for any card.")
                    or ("%s is looking for %d card%s: %s"):format(peer, count, count == 1 and "" or "s", ACB.nameList(cards)))
                if ACB.refreshInspect then ACB.refreshInspect(peer) end
                if ACB.refresh then ACB.refresh() end
            end
            return true
        end
        local key = message:match("^A|(%a+:%d+)$")
        if key then
            -- Someone is looking for a card. Only said if you have it, and not more than once in a while per player.
            if saved.inspectable ~= false then
                local card, at = ACB.cards[key], now()
                local owned = saved.counts[key] or 0
                if card and owned >= 1 and not (askedBy[peer] and at < askedBy[peer]) then
                    askedBy[peer] = at + ASK_HEARD_GAP
                    report(("%s is looking for %s. You have %d (%d spare). Type /acb trade %s to offer a swap."):format(
                        peer, ACB.cardLink(card, saved.shiny and saved.shiny[key] == true), owned, owned - 1, peer))
                end
            end
            return true
        end
        return false
    end

    return requests
end
