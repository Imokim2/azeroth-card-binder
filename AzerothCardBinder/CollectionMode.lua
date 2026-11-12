local _, ACB = ...

function ACB.canDefaultRanked(saved)
    return saved.modeChoice ~= "casual" and not saved.legacy and (saved.casualDrops or 0) == 0
        and next(saved.counts or {}) == nil and next(saved.attempts or {}) == nil
end

-- A companion file is evidence of setup, not a live process signal. A usable supply is required too.
function ACB.defaultCollectionMode(saved, ledger)
    if saved.mode == "ranked" or not ACB.canDefaultRanked(saved) then return false end
    local sync = type(ACB.sync) == "table" and ACB.sync or {}
    local setups = type(sync.rankedSetups) == "table" and sync.rankedSetups or {}
    if type(saved.modeSetupID) ~= "string" or #saved.modeSetupID ~= 32 then return false end
    local paired = false
    for _, id in ipairs(setups) do if id == saved.modeSetupID then paired = true end end
    if not (paired and sync.companionReady == true and ACB.tapeHolds(saved, 1)) then return false end
    return ACB.setMode(saved, ledger, "ranked")
end

function ACB.collectionModeText(saved)
    if saved.mode == "ranked" then
        if saved.legacy or (saved.casualDrops or 0) > 0 then return "RANKED / Earlier Casual cards keep this binder off the ladder" end
        return ACB.tapeHolds(saved, 1) and "RANKED / Ready" or "RANKED / Open the companion to finish syncing"
    end
    return saved.modeChoice == "casual" and "CASUAL / This collection does not count for Ranked"
        or "CHOOSE A MODE / Ranked is recommended"
end

function ACB.initCollectionMode(saved, ledger, report)
    if type(saved.modeSetupID) ~= "string" or #saved.modeSetupID ~= 32 or saved.modeSetupID:find("[^0-9a-f]") then
        saved.modeSetupID = ACB.sha256(tostring(GetTime and GetTime() or "") .. "|" .. tostring(math.random(1, 999999999)) .. "|" .. tostring({})):sub(1, 32)
    end
    ACB.defaultCollectionMode(saved, ledger)
    if saved.mode == "ranked" and (saved.legacy or (saved.casualDrops or 0) > 0) then
        report("This binder contains earlier Casual cards and cannot join the Ranked ladder. Your collection has been kept.")
    end
    local kit = ACB.uiKit
    local prompt = kit.window("AzerothCardBinderModeChoice", 480, 252, "How would you like to collect?")
    prompt:SetFrameStrata("FULLSCREEN_DIALOG")
    local info = kit.label(prompt, "GameFontHighlight", 28, 52, kit.parchment, "")
    info:SetWidth(424); info:SetHeight(92); info:SetWordWrap(true)
    local notice = kit.label(prompt, "GameFontHighlightSmall", 28, 151, kit.brass, "")
    notice:SetWidth(424); notice:SetHeight(35); notice:SetWordWrap(true)
    local function refresh()
        local eligible = not saved.legacy and (saved.casualDrops or 0) == 0
        info:SetText(eligible and "Ranked lets your collection count on the ladder. Install the free companion, sign in with Discord and choose your game folder. Keep it open while playing."
            or "This binder already contains Casual cards. They are safe, but this collection cannot join the Ranked ladder. You can keep collecting here in Casual.")
        notice:SetText(eligible and "Casual works without the companion. Casual drops cannot count towards Ranked later."
            or "Starting a separate Ranked collection is a deliberate choice. Nothing will be reset here.")
        prompt.ranked:SetEnabled(eligible)
    end
    prompt.ranked = kit.button(prompt, "Play Ranked", 28, 202, 204, function()
        local ok, why = ACB.setMode(saved, ledger, "ranked")
        if not ok then report(why) return end
        prompt:Hide()
        report(ACB.tapeHolds(saved, 1) and "Ranked is ready. Your finds will count for Ranked."
            or "Ranked selected. Open the companion, sign in and choose your game folder. /reload, wait for sync, then /reload again. No Casual cards will be rolled while setup finishes.")
        ACB.refresh()
    end)
    prompt.casual = kit.button(prompt, "Play Casual", 244, 202, 208, function()
        ACB.setMode(saved, ledger, "casual") -- an explicit choice, even when already Casual
        prompt:Hide()
        report("Casual selected. Cards collected here will not count towards Ranked.")
        ACB.refresh()
    end)
    function ACB.chooseCollectionMode()
        refresh(); prompt:Show()
    end
    function ACB.ensureCollectionMode()
        if saved.mode == "ranked" or saved.modeChoice == "casual" then return true end
        ACB.chooseCollectionMode()
        return false
    end
    function ACB.requestCollectionMode(mode)
        if mode == "casual" then
            info:SetText("Switch to Casual? Once you find a Casual card, this binder will no longer qualify for Ranked. Your existing cards will be kept.")
            notice:SetText("Close this window to stay in Ranked, or choose Play Casual to continue.")
            prompt.ranked:SetEnabled(true)
            prompt:Show()
        else
            local ok, why = ACB.setMode(saved, ledger, "ranked")
            report(ok and "Ranked selected. Keep the companion open and reload to sync." or why)
            ACB.refresh()
        end
    end
    ACB.modeChoicePrompt = prompt
    if saved.mode ~= "ranked" and saved.modeChoice ~= "casual" then ACB.chooseCollectionMode() end
end
