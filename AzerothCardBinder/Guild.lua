local _, ACB = ...

-- Guild binders (docs/proposals/GUILD-BINDERS-DESIGN.md). A Ranked binder can give a copy of a card to its guild for good. The companion app does
-- the talking to the server: it writes what the server says about this player's guild and donations into Data/Sync.lua (`ACB.sync.guild`), paired to
-- this binder by `binders` the way the seasons data is. The add-on never asks the server anything. A donation is written down at once, as a `donate`
-- event, and the copy leaves the binder; the server then credits the guild when the upload arrives, or refuses it and issues the copy back, which
-- `ACB.settleGuild` writes as a `donateReturn` the next time the game loads. Until then the donation is "pending" and the copy is not anywhere.

ACB.maxPendingDonations = 50 -- a donation the server has not settled yet; more than this waits, so one lost upload cannot hold a whole binder

local function operationOK(id) return type(id) == "string" and #id == 32 and not id:find("[^0-9a-f]") end

-- Keep the donations still waiting for the server in a form the rest of the add-on can rely on: operation id -> { key, guild, t }.
function ACB.cleanGuildData(saved)
    saved.guildDonations = type(saved.guildDonations) == "table" and saved.guildDonations or {}
    for id, entry in pairs(saved.guildDonations) do
        if not operationOK(id) or type(entry) ~= "table" or type(entry.key) ~= "string" or not ACB.cards[entry.key]
            or type(entry.guild) ~= "string" or #entry.guild ~= 26 or entry.guild:find("[^0-9A-Z]")
            or type(entry.t) ~= "number" then
            saved.guildDonations[id] = nil
        else
            saved.guildDonations[id] = { key = entry.key, guild = entry.guild, t = entry.t }
        end
    end
end

-- What the server last said about this binder's guild, or nil when the companion has not paired it.
function ACB.guildData(saved)
    local data = ACB.sync and ACB.sync.guild
    if type(data) ~= "table" then return end
    for _, id in ipairs(data.binders or {}) do if id == saved.modeSetupID then return data end end
end

-- The guild this player is an active member of, as { id, name, realm, side, members }, and their role; or nil.
function ACB.guildMembership(saved)
    local data = ACB.guildData(saved)
    local member = data and data.membership
    if type(member) == "table" and member.state == "active" and type(member.guild) == "table"
        and type(member.guild.id) == "string" and #member.guild.id == 26 then
        return member.guild, member.role
    end
end

function ACB.pendingDonationCount(saved)
    local count = 0
    for _ in pairs(saved.guildDonations or {}) do count = count + 1 end
    return count
end

-- Whether one copy of a card may be donated now, and if not, why (a sentence for the player).
function ACB.canDonate(saved, ledger, key)
    local guild = ACB.guildMembership(saved)
    if not guild then return false, "You are not in a guild binder yet. The companion app starts or joins one." end
    if not ledger or not ledger:check() then return false, "This binder's history does not verify, so it cannot donate." end
    if saved.mode ~= "ranked" or saved.legacy or (saved.casualDrops or 0) > 0 then
        return false, "Only a Ranked binder with no Casual finds can donate to a guild."
    end
    if not saved.balancedDrops then return false, "This binder is not on the current drop rules yet, so it cannot donate." end
    if not ACB.cards[key] then return false, "That is not a card." end
    if (saved.counts[key] or 0) < 1 then return false, "You do not own that card." end
    if ACB.pendingDonationCount(saved) >= ACB.maxPendingDonations then
        return false, "Earlier donations are still waiting for the server. Sync with the companion app and /reload first."
    end
    if ledger:backlogFull() then return false, "Too many events are waiting for the companion app. Sync first." end
    return true, guild
end

-- Give one copy of a card to the guild. The copy leaves the binder now and cannot be undone by the player; if the server refuses it, it comes back.
-- Returns true and the operation id, or false and the reason.
function ACB.donateCard(saved, ledger, key, quiet)
    local ok, guild = ACB.canDonate(saved, ledger, key)
    if not ok then return false, guild end
    -- The markers that come before it, written once each: the drop-rate generations, the faction rules and this character's side.
    ACB.activateDropBalance(saved, ledger)
    if not saved.factionLedger or not (saved.sides and saved.sides[ACB.characterName()]) then
        return false, "This character's faction is not known yet. Try again in a moment."
    end
    ledger:flushRun()
    if not saved.guildLedger then
        ledger:record("mode", "guild1")
        saved.guildLedger = true
    end
    local before = saved.counts[key]
    -- One id for this donation: it follows from where the history stands and what is given, so it is new every time and the same on every machine.
    local operation = ACB.sha256("donate|" .. saved.head.hash .. "|" .. key .. "|" .. saved.head.seq):sub(1, 32)
    saved.counts[key] = before - 1
    ledger:record("donate", key, { before = before, partner = guild.id, trade = operation })
    if saved.counts[key] == 0 then saved.counts[key] = nil end
    saved.guildDonations[operation] = { key = key, guild = guild.id, t = time() }
    if not quiet and ACB.refresh then ACB.refresh() end
    if not quiet and ACB.refreshZoneBar then ACB.refreshZoneBar() end
    return true, operation
end

-- Act on what the server has said about the donations this binder is waiting to hear about. A credited donation is finished; a refused one has the
-- copy issued back, which is written as a donateReturn for the same operation. Returns how many copies came back.
function ACB.settleGuild(saved, ledger, report)
    local data = ACB.guildData(saved)
    local news = data and data.donations
    if type(news) ~= "table" or not saved.guildDonations then return 0 end
    for operation in pairs(saved.guildDonations) do
        local result = type(news.results) == "table" and news.results[operation]
        if result == "credited" or result == "returned" then saved.guildDonations[operation] = nil end
    end
    local back = 0
    for _, refund in ipairs(type(news.refunds) == "table" and news.refunds or {}) do
        local entry = type(refund) == "table" and saved.guildDonations[refund.operation]
        if entry and entry.key == refund.card and entry.guild == refund.guild and ledger and ledger:check() and not ledger:backlogFull() then
            ledger:flushRun()
            local before = saved.counts[entry.key] or 0
            saved.counts[entry.key] = before + 1
            ledger:record("donateReturn", entry.key, { before = before, partner = entry.guild, trade = refund.operation })
            saved.guildDonations[refund.operation] = nil
            back = back + 1
            if report then report(("The guild could not take %s, so it is back in your binder."):format(ACB.cards[entry.key].name)) end
        end
    end
    if back > 0 then
        if ACB.refresh then ACB.refresh() end
        if ACB.refreshZoneBar then ACB.refreshZoneBar() end
    end
    return back
end

-- /acb guild, /acb guild donate <card>, /acb guild donate confirm. A donation is asked about first, because it cannot be taken back.
local confirmation
function ACB.guildCommand(saved, argument, report)
    argument = argument or ""
    local lower = argument:lower()
    local guild, role = ACB.guildMembership(saved)
    if lower == "" then
        local data = ACB.guildData(saved)
        local member = data and data.membership
        if guild then
            report(("%s (%s, %s): %d members. You are %s. Donate a card with /acb guild donate <card name>."):format(
                guild.name, guild.realm, guild.side, guild.members or 1, role == "owner" and "its owner" or "a member"))
            local waiting = ACB.pendingDonationCount(saved)
            if waiting > 0 then report(("%d donation%s waiting for the server. Sync with the companion app, then /reload."):format(waiting, waiting == 1 and " is" or "s are")) end
        elseif type(member) == "table" and member.state == "pending" and type(member.guild) == "table" then
            report(("Your application to %s is waiting for its owner to decide."):format(member.guild.name))
        elseif data then
            report("You are not in a guild binder. Start or join one in the companion app.")
        else
            report("Guild binders need the companion app, signed in and synced, and a server that has them switched on.")
        end
        return
    end
    if lower == "donate cancel" then
        confirmation = nil
        report("Donation cancelled.")
    elseif lower == "donate confirm" then
        if not confirmation or time() - confirmation.at > 120 then
            confirmation = nil
            report("Nothing to confirm. Start with /acb guild donate <card name>.")
            return
        end
        local key = confirmation.key
        confirmation = nil
        local ok, result = ACB.donateCard(saved, ACB.ledger, key)
        if ok then
            report(("Donated %s to %s. It stays with the guild for good."):format(ACB.cards[key].name, guild and guild.name or "your guild"))
        else
            report(result)
        end
    elseif lower:match("^donate%s+%S") then
        local card = ACB.findCard(saved, argument:match("^%S+%s+(.-)%s*$"))
        if not card then report("You do not own a card with that name."); return end
        local ok, reason = ACB.canDonate(saved, ACB.ledger, card.key)
        if not ok then report(reason); return end
        confirmation = { key = card.key, at = time() }
        report(("Donate one %s to %s? It leaves your binder for good and nobody, including the guild's officers, can take it out again. Type /acb guild donate confirm to go ahead, or /acb guild donate cancel."):format(card.name, reason.name))
    else
        report("Use /acb guild, or /acb guild donate <card name>.")
    end
end
