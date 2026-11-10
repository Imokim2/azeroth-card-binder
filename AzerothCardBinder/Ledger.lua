local _, ACB = ...

-- The ledger: a tamper-evident history of every change to the binder (docs/LEDGER-SPEC.md, version 1).
-- Each event carries the hash of the one before it, so changing an earlier event breaks every hash after it.
-- Part 1 below is the specification itself (event text, hashing, checking a chain). Part 2 keeps the player's
-- saved ledger up to date and checks it when the add-on loads.

local GENESIS = string.rep("0", 32)
ACB.GENESIS = GENESIS

local KINDS = { drop = true, craft = true, recycle = true, tradeIn = true, tradeOut = true, set = true, mode = true }
-- Un-synced events at which Ranked rolls pause until the companion app has picked them up.
ACB.backlogLimit = 5000

local MAX_INTEGER = 9007199254740991 -- the largest integer a double holds exactly (2^53 - 1)

local function whole(value, minimum)
    return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= MAX_INTEGER
end

local function plain(value)
    return type(value) == "string" and not value:find("[|\r\n]")
end

-- Integers are written in decimal. "%.0f" stays exact up to 2^53; "+ 0" turns a negative zero into zero.
local function integer(value)
    return ("%.0f"):format(value + 0)
end

-- ---------------------------------------------------------------------------------------------------------
-- Part 1: the specification

-- The name of the first field of an event that breaks the rules in section 3 of the spec, or nil.
function ACB.eventProblem(event)
    if type(event) ~= "table" then return "event" end
    if not whole(event.seq, 1) then return "seq" end
    if not whole(event.t, 0) then return "t" end
    if not KINDS[event.kind] then return "kind" end
    if not whole(event.count, 0) then return "count" end
    if not whole(event.dust, -MAX_INTEGER) then return "dust" end
    if event.shiny ~= 0 and event.shiny ~= 1 then return "shiny" end
    if not whole(event.tape, 0) then return "tape" end
    for _, name in ipairs({ "kind", "key", "partner", "trade", "char", "prev" }) do
        if not plain(event[name]) then return name end
    end
    if event.key == "" then return "key" end
    if event.char == "" then return "char" end
    if #event.prev ~= 32 or event.prev:find("[^0-9a-f]") then return "prev" end
end

-- The exact text that is hashed for an event.
function ACB.eventText(event)
    return table.concat({
        integer(event.seq), integer(event.t), event.kind, event.key, integer(event.count), integer(event.dust),
        integer(event.shiny), integer(event.tape), event.partner, event.trade, event.char, event.prev,
    }, "|")
end

function ACB.eventHash(event)
    return ACB.sha256(ACB.eventText(event)):sub(1, 32)
end

-- Check events in order against the last event already known (`head` is { seq, hash }; a new chain starts
-- from { seq = 0, hash = GENESIS }). Returns true and the new head, or false, the error name (replay, gap,
-- bad-field, bad-prev or bad-hash) and the position of the event that failed.
function ACB.checkChain(events, head)
    head = head or { seq = 0, hash = GENESIS }
    local expected, previous = head.seq + 1, head.hash
    for index, event in ipairs(events) do
        if type(event) == "table" and whole(event.seq, 1) and event.seq < expected then return false, "replay", index end
        if type(event) ~= "table" or event.seq ~= expected then return false, "gap", index end
        if ACB.eventProblem(event) then return false, "bad-field", index end
        if event.prev ~= previous then return false, "bad-prev", index end
        if event.h ~= ACB.eventHash(event) then return false, "bad-hash", index end
        expected, previous = event.seq + 1, event.h
    end
    return true, { seq = expected - 1, hash = previous }
end

-- ---------------------------------------------------------------------------------------------------------
-- Part 2: the player's ledger
--
-- Alongside the chain the add-on keeps a check value for the binder as it stands (every card count and the
-- dust balance). It is a sum of one small hash per owned card, so adding or removing a copy only changes the
-- sum by two small hashes instead of rehashing the whole binder. If a count is edited by hand, the sum no
-- longer matches the saved counts and the binder is reported as unverified. This is a local check for
-- accidents and casual edits; the server is the real check, because it replays the events themselves.

local HALF = 16777216 -- 2^24; the check value is two 24-bit halves written as 12 hex characters

local function entry(name, amount)
    if not amount or amount <= 0 then return 0, 0 end
    local hex = ACB.sha256(name .. "=" .. integer(amount))
    return tonumber(hex:sub(1, 6), 16), tonumber(hex:sub(7, 12), 16)
end

local function sumOf(saved)
    local high, low = 0, 0
    for key, count in pairs(saved.counts) do
        local a, b = entry(key, count)
        high, low = high + a, low + b
    end
    local a, b = entry("dust", saved.dust)
    return ("%06x%06x"):format((high + a) % HALF, (low + b) % HALF)
end

local function sumParts(text)
    return tonumber(text:sub(1, 6), 16), tonumber(text:sub(7, 12), 16)
end

-- `now` gives the time in seconds; `character` gives this character as "Name-Realm".
function ACB.newLedger(saved, now, character)
    local ledger = {}

    -- Start a ledger for a binder that has none yet: the cards owned today are the starting point. This
    -- happens for a new binder and for one upgraded from an older version (`upgraded`). A binder that has a
    -- history but lost its check value is not given a new one; it stays unverified.
    function ledger:begin(upgraded)
        -- Cards owned before the ledger existed cannot be replayed by the server, so such a binder cannot play Ranked.
        if upgraded and next(saved.counts) ~= nil then saved.legacy = true end
        local fresh = saved.head.seq == 0 and #saved.ledger == 0
        if type(saved.stateSum) ~= "string" and (upgraded or fresh) then saved.stateSum = sumOf(saved) end
    end

    -- Write one event. For events about a card, `fields.before` is how many copies the player had before
    -- (the copies now are read from the saved counts); `fields.dust` is the change in dust.
    function ledger:record(kind, key, fields)
        fields = fields or {}
        local head = saved.head
        local dust = fields.dust or 0
        local cardEvent = fields.before ~= nil
        local event = {
            seq = head.seq + 1, t = now(), kind = kind, key = key,
            count = cardEvent and (saved.counts[key] or 0) or 0, dust = dust,
            shiny = fields.shiny and 1 or 0, tape = fields.tape or 0,
            partner = fields.partner or "", trade = fields.trade or "", char = character(), prev = head.hash,
        }
        event.h = ACB.eventHash(event)
        table.insert(saved.ledger, event)
        saved.head = { seq = event.seq, hash = event.h }

        local high, low = sumParts(saved.stateSum)
        if cardEvent then
            local oldHigh, oldLow = entry(key, fields.before)
            local newHigh, newLow = entry(key, event.count)
            high, low = high - oldHigh + newHigh, low - oldLow + newLow
        end
        if dust ~= 0 then
            local oldHigh, oldLow = entry("dust", (saved.dust or 0) - dust)
            local newHigh, newLow = entry("dust", saved.dust)
            high, low = high - oldHigh + newHigh, low - oldLow + newLow
        end
        saved.stateSum = ("%06x%06x"):format(high % HALF, low % HALF)
        return event
    end

    -- Check the saved ledger. Returns true and the number of events kept, or false and what is wrong.
    function ledger:verify()
        local events, head = saved.ledger, saved.head
        if type(events) ~= "table" or type(head) ~= "table" then return false, "the history is missing" end
        local first = events[1]
        local start = { seq = 0, hash = GENESIS }
        -- After old events have been pruned the chain starts mid-way; its first link is taken as given.
        if type(first) == "table" and whole(first.seq, 1) and first.seq > 1 and plain(first.prev) then
            start = { seq = first.seq - 1, hash = first.prev }
        end
        local ok, result, position = ACB.checkChain(events, start)
        if not ok then
            return false, ("event %d is not valid (%s)"):format(position, result)
        end
        if #events > 0 and (result.seq ~= head.seq or result.hash ~= head.hash) then
            return false, "the latest event does not match the saved head"
        end
        if saved.stateSum ~= sumOf(saved) then
            return false, "card counts or dust do not match the history"
        end
        return true, #events
    end

    -- Drop the events the server has stored. `acks` is the list from Data/Sync.lua; an ack counts only when
    -- it names an event this binder really has (same position and same hash), because every WoW account on
    -- the computer shares that file. The newest event stays represented by `saved.head`. Returns how many
    -- events were removed.
    function ledger:prune(acks)
        local events, head = saved.ledger, saved.head
        local through = 0
        for _, ack in ipairs(type(acks) == "table" and acks or {}) do
            if type(ack) == "table" and whole(ack.seq, 1) and ack.seq > through and ack.seq <= head.seq then
                local match = ack.seq == head.seq and ack.hash == head.hash
                for _, event in ipairs(events) do
                    if event.seq == ack.seq and event.h == ack.hash then match = true end
                end
                if match then through = ack.seq end
            end
        end
        local kept, removed = {}, 0
        for _, event in ipairs(events) do
            if event.seq > through then kept[#kept + 1] = event else removed = removed + 1 end
        end
        if removed > 0 then saved.ledger = kept end
        return removed
    end

    -- How many events the app has not yet picked up, and whether Ranked has to wait for it.
    function ledger:waiting()
        return #saved.ledger
    end

    function ledger:backlogFull()
        return #saved.ledger >= ACB.backlogLimit
    end

    -- Check the ledger, remember the result, and fall back to Casual mode when it fails.
    function ledger:check()
        self.ok, self.detail = self:verify()
        if not self.ok then saved.mode = "casual" end
        return self.ok, self.detail
    end

    -- One line for the Settings tab and /acb verify.
    function ledger:status()
        if self.ok == nil then self:check() end
        if self.ok then
            local line = ("Binder verified: %d changes on record."):format(saved.head.seq)
            local synced = ACB.sync and ACB.sync.syncedAt
            if type(synced) == "number" and date then line = line .. " Last synced " .. date("%d %b %H:%M", synced) .. "." end
            if saved.mode == "ranked" and ACB.tapeLeft(saved) == 0 then
                line = line .. " The roll tape has run out: the companion app refills it."
            end
            if saved.mode == "ranked" and self:backlogFull() then
                line = line .. " Ranked rolls are paused until the companion app syncs."
            end
            return line
        end
        return "Binder unverified: " .. self.detail .. ". Ranked mode stays off for it."
    end

    return ledger
end

-- This character as "Name-Realm" with the spaces taken out of the realm, as the spec asks.
function ACB.characterName()
    local name, realm = ACB.safe(UnitFullName, "player")
    name, realm = ACB.read(name, "string"), ACB.read(realm, "string")
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and ACB.read(ACB.safe(GetNormalizedRealmName), "string")
    end
    name = (name or "Unknown"):gsub("[|%c]", "")
    realm = ((realm or "Unknown"):gsub("[|%c%s]", ""))
    return (name == "" and "Unknown" or name) .. "-" .. (realm == "" and "Unknown" or realm)
end
