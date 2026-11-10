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
        elseif cmd:match("^view%s+%S") then
            local peer = ACB.tradePeer(message:match("^%s*%S+%s+(%S+)"))
            local ok, reason = ACB.requestBinder(peer)
            report(ok and "Asked for their binder. It opens when they answer." or (reason or "Enter another player's name."))
        elseif cmd == "privacy" then
            saved.inspectable = saved.inspectable == false
            report("Other players " .. (saved.inspectable == false and "can no longer" or "can now") .. " view your binder.")
        elseif cmd == "hints" then
            saved.hints = saved.hints == false
            report("Tooltip hints " .. (saved.hints == false and "off." or "on."))
        elseif cmd == "dust" then
            report(("Binder Dust: %d. Open a card in the binder to recycle a spare or craft a missing card."):format(saved.dust or 0))
        elseif cmd == "mode" or cmd:match("^mode%s+%a+$") then
            local wanted = cmd:match("^mode%s+(%a+)$")
            if wanted then
                local ok, why = ACB.setMode(saved, ACB.ledger, wanted)
                report(ok and ("Mode: " .. saved.mode .. ".") or why)
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
            report("/acb opens the binder. Options: index, trade, achievements, settings, dust, link, view, privacy, title, popup, popup test, hints, diag, log, boss.")
        end
        if ACB.refresh then ACB.refresh() end -- a switch may have changed on the Settings tab
    end
end
