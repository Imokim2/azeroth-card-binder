local _, ACB = ...
local frame
local function displayName(peer)
    return (peer:gsub("%-", " "):gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end
local function when(at)
    if not at or at == 0 then return "Not recorded" end
    return date and date("%d %b %Y, %H:%M", at) or tostring(at)
end
function ACB.cardCopyLines(copy)
    if not copy or copy.source == "unknown" then
        local lines = { "Original finder: Not recorded", "Location: Not recorded", "This older copy has no recorded origin." }
        if copy and copy.from and copy.from ~= "" then lines[#lines + 1] = "Received from " .. displayName(copy.from) .. " / " .. when(copy.received) end
        return lines
    end
    local action = copy.source == "crafted" and "Created by: " or copy.source == "pack" and "Opened by: " or "Found by: "
    local lines = { action .. copy.finder, "Location: " .. (copy.place ~= "" and copy.place or "Not recorded"),
        "Date: " .. when(copy.at), "Source: " .. ({ drop = "Creature or gathering find", pack = "Opened from a pack", crafted = "Crafted with Binder Dust", activity = "Activity reward" })[copy.source] }
    if copy.from ~= "" then
        lines[#lines + 1] = (copy.how == "gift" and "Gifted by: " or copy.how == "returned" and "Returned from: " or "Last received from: ") .. displayName(copy.from)
        lines[#lines + 1] = "Received: " .. when(copy.received)
    end
    if copy.hops > 0 then lines[#lines + 1] = ("Trades and gifts: %d"):format(copy.hops) end
    lines[#lines + 1] = "Copy: " .. copy.id
    return lines
end
local function window()
    if frame then return frame end
    local kit, ui = ACB.uiKit, ACB.folioUi
    frame = kit.window("AzerothCardBinderCopyHistory", 640, 510, "Card history", true)
    frame.edition:Hide(); frame:SetFrameStrata("FULLSCREEN_DIALOG")
    local paper = ui.panel(frame, "Frame", 20, 80, 600, 345, { .88, .80, .62 }, ui.EDGE)
    local skin = paper:CreateTexture(nil, "BACKGROUND"); skin:SetAllPoints(); skin:SetTexture(ACB.folioArt .. "Parchment.tga")
    frame.name = ui.text(paper, 20, 18, "", 24, ui.INK, 560, "LEFT", true)
    frame.copyNumber = ui.text(paper, 20, 53, "", 11, ui.SEPIA, 560)
    frame.body = ui.text(paper, 20, 81, "", 13, ui.INK, 560); frame.body:SetHeight(238); frame.body:SetWordWrap(true)
    frame.previous = kit.button(frame, "Previous copy", 26, 446, 148, function() frame:load(frame.index - 1) end)
    frame.choose = kit.button(frame, "Use this copy", 190, 446, 260, function()
        local copy, saved = frame.copy, frame.saved
        if not saved or saved.historyPeer or frame.single then return end
        local id = copy and copy.id or "older"
        if copy and copy.id and not ACB.hasCardCopyID(saved, copy.id) then frame.body:SetText("This copy is no longer in your binder."); return end
        local previous = saved.cardCopyChoice[frame.key]
        saved.cardCopyChoice[frame.key] = id
        local trade = ACB.trade
        local session = trade and trade:active()
        if session and session.give == frame.key and not session.closed and not trade:change(frame.key, true) then
            saved.cardCopyChoice[frame.key] = previous
            frame.body:SetText("Finish or cancel the accepted trade before selecting a different copy."); return
        end
        frame:load(frame.index); if ACB.refresh then ACB.refresh() end
    end)
    frame.next = kit.button(frame, "Next copy", 466, 446, 148, function() frame:load(frame.index + 1) end)
    frame.retry = kit.button(frame, "Try again", 190, 446, 260, function() frame:load(frame.index) end)
    ui.text(frame, 26, 483, "Original details stay with this copy when traded or gifted.", 11, kit.muted, 588, "CENTER")
    function frame:draw(copy, count, problem)
        self.copy, self.count = copy, count or self.count or 0
        self.copyNumber:SetText(("Copy %d of %d"):format(self.index, self.count))
        self.body:SetText(problem or table.concat(ACB.cardCopyLines(copy), "\n\n"))
        self.previous:SetEnabled(not self.single and self.index > 1)
        self.next:SetEnabled(not self.single and self.index < self.count)
        self.choose:SetShown(not self.single and not self.saved.historyPeer and ACB.cardHistoryEnabled(self.saved))
        self.retry:SetShown(not self.single and self.saved.historyPeer and not self.loading and problem ~= nil)
        self.choose:SetEnabled(copy ~= nil)
        if copy then
            local selected = not self.saved.historyPeer and ACB.selectedCardCopy(self.saved, self.key)
            local chosen = selected and selected.id == copy.id or not selected and not copy.id
            self.choose:SetText(chosen and "Selected for trades and gifts" or "Use this copy")
        end
    end
    function frame:load(index)
        if index < 1 then return end
        if self.ticket and ACB.copyHistoryRequests then ACB.copyHistoryRequests:cancel(self.ticket); self.ticket = nil end
        self.index = index
        if not self.saved.historyPeer then self:draw(ACB.cardCopyAt(self.saved, self.key, index), self.saved.counts[self.key] or 0); return end
        self.loading = true; self:draw(nil, self.count, "Loading this copy's history...")
        self.next:SetEnabled(false); self.previous:SetEnabled(false)
        local requestKey, requestIndex, peer = self.key, index, self.saved.historyPeer
        local service = ACB.copyHistoryRequests
        if not service then self.loading = nil; self:draw(nil, self.count, "History sharing is not ready."); return end
        local ticket, why = service:request(peer, requestKey, index, function(copy, count, problem)
            if self:IsShown() and self.key == requestKey and self.index == requestIndex and self.saved.historyPeer == peer then self.ticket, self.loading = nil, nil; self:draw(copy, count, problem) end
        end)
        self.ticket = ticket
        if not ticket then self.loading = nil; self:draw(nil, self.count, why or "Could not request history.") end
    end
    frame:SetScript("OnHide", function(self) if self.ticket and ACB.copyHistoryRequests then ACB.copyHistoryRequests:cancel(self.ticket) end; self.ticket = nil end)
    return frame
end
function ACB.openCardHistory(saved, key)
    local view, card = window(), ACB.cards[key]
    if not card or (saved.counts[key] or 0) < 1 then return end
    view.saved, view.key, view.index, view.single, view.count, view.loading = saved, key, 1, false, saved.counts[key], nil
    view.name:SetText(card.name); view:Show(); view:load(1)
    view:SetScale(math.min(1, (UIParent:GetWidth() - 24) / 640, (UIParent:GetHeight() - 24) / 510))
    return view
end
function ACB.showCardCopyHistory(key, copy)
    local view, card = window(), ACB.cards[key]
    if not card then return end
    if view.ticket and ACB.copyHistoryRequests then ACB.copyHistoryRequests:cancel(view.ticket); view.ticket = nil end
    view.saved, view.key, view.index, view.single, view.loading = { counts = { [key] = 1 }, historyPeer = true }, key, 1, true, nil
    view.name:SetText(card.name); view:draw(copy, 1); view:Show()
    view:SetScale(math.min(1, (UIParent:GetWidth() - 24) / 640, (UIParent:GetHeight() - 24) / 510))
    return view
end
