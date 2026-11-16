local _, ACB = ...

-- Unconfirmed guild copies are display only; they never add to confirmed totals or points.
function ACB.guildInventoryView(saved, guildID)
    local data = ACB.guildData(saved)
    local summary = data and data.summary
    local confirmed, pending, shown = {}, {}, {}
    if summary and summary.guildId == guildID then
        for _, entry in ipairs(summary.inventory or {}) do confirmed[entry.card] = entry.copies; shown[entry.card] = entry.copies end
    end
    local results = data and data.donations and data.donations.results or {}
    for operation, entry in pairs(saved.guildDonations or {}) do
        if entry.guild == guildID and not results[operation] then
            pending[entry.key] = (pending[entry.key] or 0) + 1
            shown[entry.key] = (shown[entry.key] or 0) + 1
        end
    end
    return confirmed, pending, shown
end

function ACB.guildBatchPlan(saved, ledger, tray, guildID)
    local guild = ACB.guildMembership(saved)
    if not guild or guild.id ~= guildID then return nil, "Your guild changed. Choose your cards again." end
    local plan = { guild = guild.id, name = guild.name, rows = {}, total = 0, lastCopies = 0 }
    for key, count in pairs(tray) do
        if type(count) ~= "number" or count < 1 or count ~= math.floor(count) then return nil, "Choose whole card copies." end
        local ok, why = ACB.canDonate(saved, ledger, key)
        if not ok then return nil, why end
        local before = saved.counts[key] or 0
        if count > before then return nil, "Your cards changed. Review the selection again." end
        plan.rows[#plan.rows + 1] = { key = key, count = count, before = before }
        plan.total = plan.total + count
        if count == before then plan.lastCopies = plan.lastCopies + 1 end
    end
    if plan.total == 0 then return nil, "Choose cards in your binder first." end
    if plan.total + ACB.pendingDonationCount(saved) > ACB.maxPendingDonations then
        return nil, "This batch is too large. Save and sync earlier donations, or choose fewer copies."
    end
    if #saved.ledger + plan.total + 7 > ACB.backlogLimit then return nil, "Save and sync before donating this batch." end
    if not ACB.playerSide() then return nil, "Your character's faction is not ready yet. Try again in a moment." end
    table.sort(plan.rows, function(a, b)
        local an, bn = ACB.cards[a.key].name, ACB.cards[b.key].name
        return an == bn and a.key < b.key or an < bn
    end)
    return plan
end

function ACB.donateGuildBatch(saved, ledger, reviewed)
    local tray = {}
    for _, row in ipairs(reviewed.rows) do
        if (saved.counts[row.key] or 0) ~= row.before then return false, "Your cards changed. Review the selection again.", 0 end
        tray[row.key] = row.count
    end
    local current, why = ACB.guildBatchPlan(saved, ledger, tray, reviewed.guild)
    if not current then return false, why, 0 end
    local done = 0
    for _, row in ipairs(current.rows) do
        for _ = 1, row.count do
            local ok, reason = ACB.donateCard(saved, ledger, row.key, true)
            if not ok then return false, reason, done end
            done = done + 1
        end
    end
    if ACB.refreshZoneBar then ACB.refreshZoneBar() end
    return true, "Donation saved. Reload once to save the batch; the companion syncs it automatically. Reload again after sync to confirm it.", done
end
