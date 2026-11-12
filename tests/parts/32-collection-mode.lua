local function modeBinder()
    local saved = ACB.cleanSavedData({})
    saved.modeSetupID = ("a"):rep(32)
    local ledger = newLedger(saved)
    ledger:begin(false)
    return saved, ledger
end

test("an untouched binder defaults to Ranked only with companion setup and a usable matching supply", function()
    local keep = ACB.sync
    ACB.sync = { companionReady = true, rankedSetups = { ("a"):rep(32) }, tape = { start = 1, entries = { MISS } } }
    local saved, ledger = modeBinder()
    equal(ACB.defaultCollectionMode(saved, ledger), true)
    equal(saved.mode, "ranked")
    equal(saved.modeChoice, "ranked")
    equal(saved.ledger[1].key, "ranked2")
    equal(saved.tape.next, 1)
    equal(ACB.collectionModeText(saved), "RANKED / Ready")
    equal(ACB.defaultCollectionMode(saved, ledger), false)
    equal(#saved.ledger, 1)
    for _, supply in ipairs({ {}, { companionReady = true },
        { companionReady = true, tape = { start = 96, entries = { MISS } } },
        { companionReady = true, rankedIssue = "binder-mismatch", tape = { start = 1, entries = { MISS } } } }) do
        saved, ledger = modeBinder(); ACB.sync = supply
        equal(ACB.defaultCollectionMode(saved, ledger), false)
        equal(saved.mode, "casual")
        equal(saved.tape.next, 1)
    end
    ACB.sync = keep
end)

test("an explicit Casual choice and an existing Casual collection are never silently switched", function()
    local keep = ACB.sync
    ACB.sync = { companionReady = true, rankedSetups = { ("a"):rep(32) }, tape = { start = 1, entries = { MISS } } }
    local saved, ledger = modeBinder()
    assert(ACB.setMode(saved, ledger, "casual"))
    equal(saved.modeChoice, "casual")
    equal(ACB.defaultCollectionMode(saved, ledger), false)
    equal(ACB.collectionModeText(saved), "CASUAL / This collection does not count for Ranked")
    saved, ledger = modeBinder()
    saved.casualDrops = 1
    equal(ACB.defaultCollectionMode(saved, ledger), false)
    local ok, why = ACB.setMode(saved, ledger, "ranked")
    equal(ok, false)
    assert(why:find("cannot count for Ranked", 1, true))
    saved.mode = "ranked" -- older builds allowed the mode to change even for an ineligible collection
    assert(ACB.collectionModeText(saved):find("keep this binder off the ladder", 1, true))
    equal(saved.mode, "ranked", "the warning never silently changes an existing player's mode")
    ACB.sync = keep
end)

test("a new player cannot roll their first Casual card or open a pack without choosing", function()
    local oldDB, keepSync = AzerothCardBinderDB, ACB.sync
    local keep = { ACB.ensureCollectionMode, ACB.chooseCollectionMode, ACB.requestCollectionMode, ACB.modeChoicePrompt }
    local saved, ledger = modeBinder()
    AzerothCardBinderDB, ACB.sync = saved, {}
    ACB.initCollectionMode(saved, ledger, ignore)
    local collection = ACB.newCollection(saved, function() return 1 end, ignore, ignore, nil, nil, ledger)
    equal(collection:roll(guid(589, "first-choice"), "loot"), nil)
    equal(next(saved.counts), nil)
    equal(next(saved.attempts), nil)
    equal(saved.casualDrops, 0)
    equal(ACB.modeChoicePrompt:IsShown(), true)
    ACB.modeChoicePrompt:Hide()
    equal(collection:roll(guid(589, "closed-choice"), "loot"), nil)
    equal(ACB.modeChoicePrompt:IsShown(), true)
    saved.packs.DM = 1
    equal(collection:openPack("DM"), nil)
    equal(saved.packs.DM, 1)
    ACB.modeChoicePrompt.ranked:OnClick()
    equal(saved.mode, "ranked")
    equal(ACB.modeChoicePrompt:IsShown(), false)
    equal(collection:roll(guid(589, "waiting-for-companion"), "loot"), nil)
    equal(saved.casualDrops, 0, "waiting for setup never falls back to Casual")
    ACB.requestCollectionMode("casual")
    equal(saved.mode, "ranked", "opening the confirmation does not switch modes")
    ACB.modeChoicePrompt.casual:OnClick()
    equal(saved.modeChoice, "casual")
    assert(collection:roll(guid(589, "deliberate-casual"), "loot"))
    equal(saved.casualDrops, 1)
    AzerothCardBinderDB, ACB.sync = oldDB, keepSync
    ACB.ensureCollectionMode, ACB.chooseCollectionMode, ACB.requestCollectionMode, ACB.modeChoicePrompt = unpack(keep)
end)
