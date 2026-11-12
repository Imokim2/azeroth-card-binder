test("sound groups mute independently, respect SFX, and stop only returned addon handles", function()
    local oldFile, oldStop = PlaySoundFile, StopSound
    local saved, played, stopped = ACB.cleanSavedData({}), {}, {}
    PlaySoundFile = function(path, channel) played[#played + 1] = { path, channel } return true, 100 + #played end
    StopSound = function(handle) stopped[#stopped + 1] = handle end
    ACB.initSounds(saved)
    ACB.playCardSound(ACB.cards["npc:639"], { first = true })
    equal(played[1][2], "SFX")
    assert(played[1][1]:find("legendary.ogg", 1, true))
    ACB.setSetting(saved, "pickupSounds", false)
    ACB.playCardSound(ACB.cards["npc:589"], { first = true, shiny = true })
    equal(#played, 1)
    ACB.playSound("pack_found")
    equal(#played, 2)
    ACB.setSetting(saved, "packSounds", false)
    ACB.playSound("rare", "packs")
    equal(#played, 2)
    ACB.playSound("trade")
    equal(#played, 3)
    ACB.setSetting(saved, "sounds", false)
    ACB.playSound("binder")
    equal(#played, 3)
    assert(#stopped >= 3)
    for _, handle in ipairs(stopped) do assert(handle >= 101 and handle <= 103) end
    equal(saved.pickupSounds, false)
    equal(saved.packSounds, false)
    ACB.setSetting(saved, "sounds", true)
    ACB.playSound("trade", "trades", true)
    equal(#played, 4)
    PlaySoundFile, StopSound = oldFile, oldStop
    ACB.initSounds(AzerothCardBinderDB)
end)

test("original clips fall back safely and stronger rewards suppress quieter musical pileups", function()
    local oldFile, oldSound, oldKit, oldStop = PlaySoundFile, PlaySound, SOUNDKIT, StopSound
    local saved, calls, stopped = ACB.cleanSavedData({}), {}, {}
    ACB.initSounds(saved)
    PlaySoundFile = function() error("unavailable on this client") end
    SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 733 }
    PlaySound = function(id, channel) equal(channel, "SFX") calls[#calls + 1] = id return true end
    equal(ACB.playSound("common"), 733)
    ACB.stopSounds()
    PlaySoundFile = function(path) calls[#calls + 1] = path return true, #calls end
    StopSound = function(handle) stopped[#stopped + 1] = handle end
    ACB.playSound("legendary")
    local count = #calls
    ACB.playSound("rare")
    equal(#calls, count)
    ACB.playSound("shiny")
    equal(#calls, count + 1)
    assert(#stopped >= 1)
    equal(ACB.cardSound(ACB.cards["npc:639"], { count = 2 }), "duplicate")
    equal(ACB.cardSound(ACB.cards["npc:639"], { trade = true }), nil)
    equal(ACB.cardSound(ACB.cards["edition:7211"], { first = true }), "epic")
    PlaySoundFile, PlaySound, SOUNDKIT, StopSound = oldFile, oldSound, oldKit, oldStop
    ACB.initSounds(AzerothCardBinderDB)
end)

test("Sounds settings preserve per-group choices and cancelling a preview cancels its delayed cues", function()
    local oldFile, oldTimer = PlaySoundFile, C_Timer
    local saved = ACB.cleanSavedData({ sounds = false, packSounds = false })
    local callbacks, played = {}, 0
    PlaySoundFile = function() played = played + 1 return true end
    C_Timer = { After = function(_, callback) callbacks[#callbacks + 1] = callback end }
    ACB.initSounds(saved)
    local view = ACB.createSettingsView(UIParent, saved)
    view:refresh()
    local checks = view.soundControls.checks
    equal(checks.sounds.checked, false)
    equal(checks.pickupSounds.checked, true)
    equal(checks.pickupSounds.enabled, false)
    equal(checks.packSounds.checked, false)
    checks.sounds.checked = true; checks.sounds:OnClick(); view:refresh()
    equal(checks.pickupSounds.enabled, true)
    equal(checks.packSounds.checked, false)
    ACB.previewSounds("pickup")
    equal(played, 1)
    assert(#callbacks > 1)
    ACB.setSetting(saved, "pickupSounds", false)
    for _, callback in ipairs(callbacks) do callback() end
    equal(played, 1)
    ACB.previewSounds("pickup")
    equal(played, 1)
    PlaySoundFile, C_Timer = oldFile, oldTimer
    ACB.initSounds(AzerothCardBinderDB)
    view:Hide()
end)

test("muting sounds keeps pop-ups, and hiding pop-ups keeps enabled pickup audio", function()
    local oldFile = PlaySoundFile
    local saved, played = ACB.cleanSavedData({ sounds = false }), 0
    PlaySoundFile = function() played = played + 1 return true end
    ACB.initToast(saved)
    ACB.showToast(ACB.cards["npc:589"], { count = 1, first = true })
    equal(ACB.toast:IsShown(), true)
    equal(played, 0)
    ACB.toast:OnUpdate(10)
    saved.sounds, saved.popups = true, false
    ACB.showToast(ACB.cards["npc:589"], { count = 1, first = true })
    equal(ACB.toast:IsShown(), false)
    equal(played, 1)
    PlaySoundFile = oldFile
    ACB.initToast(AzerothCardBinderDB)
end)

test("Flip all plays one best reveal with paper flips, and every face-down slot uses the same card back", function()
    local oldPlay, oldUV = ACB.playSound, methods.SetTexCoord
    local cues = {}
    ACB.playSound = function(cue, group) cues[#cues + 1] = { cue, group } end
    methods.SetTexCoord = function(self, ...) self.uv = { ... } end
    local saved = ACB.cleanSavedData({})
    local view = ACB.createPackView(saved)
    local results = {}
    for index, key in ipairs({ "npc:589", "npc:573", "npc:639", "npc:590", "npc:721" }) do
        results[index] = { card = ACB.cards[key], count = 1, first = true, shiny = index == 4 }
    end
    view:start(results, ACB.pages[ACB.cards["npc:589"].page])
    for _, slot in ipairs(view.slots) do
        equal(slot.backTexture.texture, ACB.folioArt .. "CardBack.tga")
        equal(slot.backTexture.uv[4], 358 / 512)
    end
    run(view, 3); view:flipAll(); run(view, 3)
    equal(view:flipped(), 5)
    local paper, rewards = 0, 0
    for _, entry in ipairs(cues) do
        if entry[1] == "paper" then paper = paper + 1 end
        if ACB.soundPriority(entry[1]) > 0 then rewards = rewards + 1; equal(entry[1], "shiny"); equal(entry[2], "packs") end
    end
    equal(paper, 5); equal(rewards, 1)
    view:finish(); view.frame:Hide()
    ACB.playSound, methods.SetTexCoord = oldPlay, oldUV
end)

test("trade completion sounds once per client and retries never replay the completion", function()
    local oldPlay, calls = ACB.playSound, 0
    ACB.playSound = function(cue) if cue == "trade" then calls = calls + 1 end end
    local a, b, messages = peers({ ["npc:589"] = 1 }, {})
    a:start("bob-realm", "npc:589", true); a:confirm(); b:confirm()
    equal(calls, 2)
    local copy = {}; for _, message in ipairs(messages) do copy[#copy + 1] = message end
    for _, message in ipairs(copy) do a:receive("bob-realm", message); b:receive("alice-realm", message) end
    equal(calls, 2)
    ACB.playSound = oldPlay
end)
