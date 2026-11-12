local _, ACB = ...

-- The /acb and /cardbinder commands. `tools` hands over what lives in Forever.lua: report (print to chat),
-- log (the diagnostics trace), the trace itself, and apiValue (a protected read of a game API).
function ACB.initSlash(saved, tools)
    local report, log, diagnostics, apiValue = tools.report, tools.log, tools.diagnostics, tools.apiValue
    local read = ACB.read
    SLASH_AZEROTHCARDBINDER1, SLASH_AZEROTHCARDBINDER2 = "/acb", "/cardbinder"
    SlashCmdList.AZEROTHCARDBINDER = function(message)
        local cmd = message:lower():match("^%s*(.-)%s*$")
        if cmd == "diag" then
            saved.diagnostics = not saved.diagnostics
            log("Diagnostics on. Client " .. (GetBuildInfo()))
            report("Diagnostics " .. (saved.diagnostics and "on. Use /acb log to copy." or "off."))
        elseif cmd == "log" then
            ACB.showLog(table.concat(diagnostics, "\n"), saved.diagnostics)
        elseif cmd == "boss" then
            saved.bossTrial = not saved.bossTrial
            report("VanCleef completion trial " .. (saved.bossTrial and "on." or "off."))
        elseif cmd == "title" or cmd:match("^title ") then
            local choice = cmd:match("^title%s+(.+)$")
            local earned = ACB.earnedTitles(saved)
            if choice == "off" then
                ACB.selectTitle(saved)
                report("Title cleared.")
            elseif choice and earned[tonumber(choice) or 0] then
                ACB.selectTitle(saved, earned[tonumber(choice)])
                report("Title set to " .. saved.title .. ".")
            elseif #earned == 0 then
                report("Earn an achievement or finish a set to unlock a title.")
            else
                for number, title in ipairs(earned) do
                    report(("%d. %s%s"):format(number, title, title == saved.title and " (shown)" or ""))
                end
                report("Use /acb title <number> to show one, or /acb title off.")
            end
            if ACB.refresh then ACB.refresh() end
        elseif cmd:match("^link%s+%S") then
            local card = ACB.findCard(saved, message:match("^%s*%S+%s+(.-)%s*$"))
            if card then ACB.linkCard(saved, card) else report("You do not own a card with that name.") end
        elseif cmd:match("^ask%s+%S+%s+%S") then
            local who, what = message:match("^%s*%S+%s+(%S+)%s+(.-)%s*$")
            local peer, why
            if who:lower() == "target" then peer, why = ACB.targetPeer() else peer = ACB.tradePeer(who) end
            local ok, reason = ACB.askForCard(peer, ACB.findAnyCard(what))
            if not ok then report(reason or why) end
        elseif cmd:match("^view%s+%S") then
            local peer = ACB.tradePeer(message:match("^%s*%S+%s+(.-)%s*$"))
            local ok, reason = ACB.requestBinder(peer)
            report(ok and "Asked for their binder. It opens when they answer." or (reason or "Enter another player's name."))
        elseif cmd == "whisperform space" or cmd == "whisperform hyphen" then
            saved.whisperForm = cmd:match("%a+$")
            report("Whispers to other players are now addressed as " .. (saved.whisperForm == "hyphen" and "First-Second." or "First Second."))
        elseif cmd == "privacy" then
            saved.inspectable = saved.inspectable == false
            report("Other players " .. (saved.inspectable == false and "can no longer" or "can now") .. " view your binder.")
        elseif cmd == "hints" then
            saved.hints = saved.hints == false
            report("Tooltip hints " .. (saved.hints == false and "off." or "on."))
        elseif cmd == "bar" or cmd == "bar reset" or cmd == "bar debug" then
            if cmd == "bar debug" then
                local place = ACB.currentPlaceName()
                local index, owned, total = ACB.zoneProgress(saved, place)
                report(("Zone: %s. Card bar: %s. %s"):format(place or "not available yet",
                    ACB.settingOn(saved, "zoneBar") and "on" or "off",
                    index and ("%s: %d / %d collected."):format(ACB.pages[index].title, owned, total) or "No matching card set."))
                local slot, name = ACB.replacedBar()
                report(slot and ("Replacing the bar: " .. tostring(name)) or "No bar to replace; the zone bar sits above the experience bar.")
                for _, frame in ipairs({ "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
                    "MainMenuExpBar", "ReputationWatchBar", "ReputationStatusBar" }) do
                    local found = _G[frame]
                    local wide = found and found.GetWidth and ACB.read(found:GetWidth(), "number")
                    local tall = found and found.GetHeight and ACB.read(found:GetHeight(), "number")
                    local shown = found and found.IsShown and ACB.read(found:IsShown(), "boolean")
                    report(("%s: %s%s"):format(frame, found and "exists" or "missing", found and (" %sx%s %s"):format(
                        wide and math.floor(wide) or "?", tall and math.floor(tall) or "?", shown and "shown" or "hidden") or ""))
                end
                local manager = _G.StatusTrackingBarManager
                if type(manager) == "table" and type(manager.bars) == "table" then
                    for index, found in pairs(manager.bars) do
                        report(("manager bar %s: kind %s, %s"):format(tostring(index), tostring(type(found) == "table" and ACB.read(found.barIndex, "number")),
                            type(found) == "table" and found.IsShown and ACB.read(found:IsShown(), "boolean") and "shown" or "hidden"))
                    end
                end
            elseif cmd == "bar reset" then
                saved.zoneBarSpot = nil
                ACB.setSetting(saved, "zoneBar", true)
                report("The zone card bar is on and its position has been reset.")
            else
                ACB.setSetting(saved, "zoneBar", not ACB.settingOn(saved, "zoneBar"))
                report("Zone card bar " .. (ACB.settingOn(saved, "zoneBar") and "on." or "off."))
            end
            if ACB.refreshZoneBar then ACB.refreshZoneBar() end
        elseif cmd == "packs" or cmd == "pack" then
            if ACB.openPacks then ACB.openPacks() end
        elseif cmd == "report" or cmd:match("^report%s") then
            ACB.reportCommand(saved, message:match("^%s*%S+%s*(.-)%s*$"), report, time())
        elseif cmd == "newbinder" or cmd == "newbinder confirm" then
            if cmd == "newbinder" then
                report("This erases your binder on this account and starts a new one. Do it to join the Ranked ladder, which only counts a binder that was Ranked from its first drop.")
                report("A copy of your collection is kept in the saved file. To go ahead, type /acb newbinder confirm. Then wait for the companion app to say the new binder was started before you switch to Ranked.")
            else
                ACB.startNewBinder(saved)
                report("A new binder was started. Reloading the interface.")
                if ReloadUI then ReloadUI() end
            end
        elseif cmd == "dust" then
            report(("Binder Dust: %d. Open a card in the binder to recycle a spare or craft a missing card."):format(saved.dust or 0))
        elseif cmd == "mode" or cmd:match("^mode%s+%a+$") then
            local wanted = cmd:match("^mode%s+(%a+)$")
            if wanted then
                local ok, why = ACB.setMode(saved, ACB.ledger, wanted)
                report(ok and ("Mode: " .. saved.mode .. ".") or why)
                if ok and wanted == "ranked" then
                    report("Ranked checks every attempt against the server. Every card starts again from its base drop chance, and the tape is topped up by the companion app, so /reload now and then to let it sync.")
                end
                if ok and wanted == "casual" then
                    report("Only Ranked counts for the ladder. A drop rolled in Casual cannot be checked, and one is enough to keep this binder off the ladder for good.")
                end
            else
                report(("Mode: %s. Roll tape entries left: %d. Use /acb mode ranked or /acb mode casual."):format(saved.mode, ACB.tapeLeft(saved)))
            end
            if ACB.refresh then ACB.refresh() end
        elseif cmd == "verify" then
            ACB.ledger:check()
            report(ACB.ledger:status())
            report(("Mode: %s. Cards owned: %d. Attempts counted: %d."):format(saved.mode, ACB.countKeys(saved.counts),
                ACB.sumValues(saved.attempts)))
            if ACB.refresh then ACB.refresh() end
        elseif cmd == "studio" or cmd == "designs" or cmd:match("^studio%s+") then
            local query = message:match("^%s*%S+%s+(.-)%s*$")
            ACB.openCardStudio(query and ACB.findAnyCard(query))
        elseif cmd == "settings" or cmd == "options" then
            ACB.open("settings")
        elseif cmd == "popup" then
            saved.popups = saved.popups == false
            report("Card pop-ups " .. (saved.popups == false and "off." or "on."))
        elseif cmd == "popup test" then
            local demo = ACB.cards["npc:639"]
            if saved.popups == false then
                report("Card pop-ups are off. Use /acb popup to turn them on.")
            else
                ACB.showToast(demo, { count = 1, first = true, shiny = true })
            end
        elseif cmd == "trade" or cmd == "index" or cmd == "achievements" then
            local unit = cmd == "trade" and apiValue("boolean", UnitIsPlayer, "target") == true
            local name, realm
            if unit then name, realm = UnitFullName("target") end
            name, realm = read(name, "string"), read(realm, "string")
            if name and ACB.prepareTrade then
                ACB.prepareTrade(realm and realm ~= "" and (name .. "-" .. realm) or name)
            else
                ACB.open(cmd)
            end
        elseif cmd:match("^trade%s+%S") then
            ACB.prepareTrade(message:match("^%s*%S+%s+(%S+)"))
        elseif cmd == "" then
            ACB.open()
        else
            report("/acb opens the binder. Options: index, trade, achievements, settings, studio, packs, dust, link, view, ask, privacy, title, popup, popup test, hints, bar, newbinder, diag, log, boss.")
        end
        if ACB.refresh then ACB.refresh() end -- a switch may have changed on the Settings tab
    end
end
