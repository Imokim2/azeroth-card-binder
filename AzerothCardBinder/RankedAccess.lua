local _, ACB = ...
local trades = setmetatable({}, { __mode = "kv" })

ACB.rankedTradeNotice = "Trading and gifting need Ranked mode. Download the companion from worldofwarcards.co.uk/download, connect your game folder, then enable Ranked."

-- Sync.lua proves a matching setup, not whether a desktop process is running.
function ACB.companionPaired(saved)
    local sync = type(ACB.sync) == "table" and ACB.sync or {}
    if sync.companionReady ~= true or type(saved.modeSetupID) ~= "string" or #saved.modeSetupID ~= 32 then return false end
    for _, id in ipairs(type(sync.rankedSetups) == "table" and sync.rankedSetups or {}) do
        if id == saved.modeSetupID then return true end
    end
    -- Companion 1.0.1 lists only untouched binders in rankedSetups. Its synced
    -- seasonal payload also names the exact binders it successfully uploaded,
    -- including established Ranked and explicitly chosen Casual collections.
    -- Match the nonce, never merely the presence of a companion file or tape.
    local seasonal = type(sync.seasonal) == "table" and sync.seasonal or {}
    for _, id in ipairs(type(seasonal.binders) == "table" and seasonal.binders or {}) do
        if id == saved.modeSetupID then return true end
    end
    return false
end

function ACB.tradeModeReason(saved)
    if not saved then return end -- Transport-only callers have no collection mode.
    if saved.mode ~= "ranked" then return ACB.rankedTradeNotice end
    if saved.legacy or (saved.casualDrops or 0) > 0 then
        return "This binder contains Casual or older unverified cards. Trading and gifting need a fresh Ranked binder. Your current cards have been kept."
    end
    if ACB.cardHistoryEnabled and ACB.cardHistoryEnabled(saved) and not (ACB.sync and ACB.sync.copyHistoryReady) then
        return "Update the companion to 1.0.7 or later, sync and /reload before trading cards with history. Your collection is kept."
    end
end

function ACB.rankedTradeAllowed(saved, peer)
    local why = ACB.tradeModeReason(saved)
    if why then return false, why end
    if not ACB.companionPaired(saved) then return false, ACB.rankedTradeNotice end
    return ACB.tradeDistanceOk(saved, peer)
end

function ACB.trackTrade(saved, trade)
    if saved then trades[saved] = trade end
end

function ACB.tradeModeLocked(saved)
    local trade = trades[saved]
    local session = trade and trade:active()
    return session and not session.applied and not session.closed
end
