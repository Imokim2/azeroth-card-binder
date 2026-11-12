local _, ACB = ...

-- Sharing with other players: right-click a player to offer a trade or look at their binder, put a
-- card in chat as a link, and open a card someone else linked.
--   Card links travel as plain chat text and are rendered as addon links on receipt.
--   Viewing:     a read-only copy of the owner's counts is whispered on request (prefix below).
--                /acb privacy stops your binder from being viewable.
ACB.viewPrefix = "AzerothBinderV1"

local ENTRIES_PER_MESSAGE = 19
local catalogSize = 0
for _, page in ipairs(ACB.pages) do catalogSize = catalogSize + #page.cards end
local MAX_PARTS = math.ceil(catalogSize / ENTRIES_PER_MESSAGE)
-- The game limits how fast addon messages can go out (a short burst, then about one a second), and a message over
-- the limit is refused, not queued. The first parts go quickly, the rest at a steady pace, and a refused part is
-- sent again a moment later.
local BURST_PARTS, BURST_INTERVAL, STEADY_INTERVAL, RETRY_DELAY, RETRIES = 8, 0.3, 1.1, 1.3, 10
local function partDelay(index)
    if index <= BURST_PARTS then return BURST_INTERVAL * (index - 1) end
    return BURST_INTERVAL * (BURST_PARTS - 1) + STEADY_INTERVAL * (index - BURST_PARTS)
end
local REQUEST_WINDOW, SERVE_GAP = 30 + partDelay(MAX_PARTS) + RETRY_DELAY * 3, 10
local NO_ANSWER_AFTER = 8
local TITLE_REPLY_WINDOW, TITLE_RETRY, TITLE_CACHE = 5, 20, 45
local MENUS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND" }
local PORTRAIT_MENUS = { "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_BOSS" }
local CHAT_TYPES = { "SAY", "YELL", "CHANNEL", "GUILD", "OFFICER", "PARTY", "PARTY_LEADER", "RAID",
    "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "WHISPER", "WHISPER_INFORM",
    "BN_WHISPER", "BN_WHISPER_INFORM" }
local gold = { 1, 0.82, 0 }

-- ---- Card links ----

function ACB.cardLink(entry, shiny)
    local color = ACB.rarities[entry.rarity].color
    return ("|cff%02x%02x%02x|Haddon:AzerothCardBinder:card:%s:%d|h[%s%s]|h|r"):format(
        color[1] * 255 + 0.5, color[2] * 255 + 0.5, color[3] * 255 + 0.5,
        entry.key, shiny and 1 or 0, entry.name, shiny and " (Shiny)" or "")
end

-- Read the part of a clicked link after the "addon:" prefix back into a catalog card.
function ACB.parseCardLink(link)
    link = ACB.read(link, "string")
    if not link or #link > 80 then return end
    local key, shiny = link:match("^addon:AzerothCardBinder:card:(%a+:%d+):([01])$")
    local entry = key and ACB.cards[key]
    if entry then return entry, shiny == "1" end
end

local function renderCardLinks(_, _, message, ...)
    message = ACB.read(message, "string")
    if not message or not message:find("[ACB:", 1, true) then return end
    local changed
    local rendered = message:gsub("%[ACB:(%a+:%d+):([01]) [^%[%]|]+%]", function(key, shiny)
        local entry = ACB.cards[key]
        if entry then
            changed = true
            return ACB.cardLink(entry, shiny == "1")
        end
    end)
    if changed then return false, rendered, ... end
end

-- Find an owned card by part of its name.
function ACB.findCard(saved, text)
    text = (text or ""):lower():match("^%s*(.-)%s*$")
    if text == "" then return end
    local best
    for _, page in ipairs(ACB.inventoryPages()) do
        for _, card in ipairs(page.cards) do
            local name = card.name:lower()
            if (saved.counts[card.key] or 0) > 0 and name:find(text, 1, true) then
                if name == text then return card end
                best = best or card
            end
        end
    end
    return best
end

-- ---- Viewing a binder ----

-- Cards go over the wire as "c589" (a creature) or "o1731" (a node), then =count and * for a shiny.
local function shortKey(card) return card.baseKey and ("v" .. card.key:match("%d+$")) or (card.profession and "o" or "c") .. card.id end
function ACB.shortKey(card) return shortKey(card) end
local function longKey(short)
    local kind, id = short:match("^([cov])(%d+)$")
    return kind and ((kind == "v" and "edition:" or kind == "o" and "node:" or "npc:") .. id)
end
ACB.longKey = longKey

-- The messages that describe a binder: "B|part/parts|key=count[*],..." where * marks a shiny.
function ACB.encodeBinder(saved)
    local parts, current = {}, {}
    for _, page in ipairs(ACB.inventoryPages()) do
        for _, card in ipairs(page.cards) do
            local count = saved.counts[card.key] or 0
            if count > 0 then
                current[#current + 1] = ("%s=%d%s"):format(shortKey(card), math.min(count, 99),
                    saved.shiny and saved.shiny[card.key] and "*" or "")
                if #current == ENTRIES_PER_MESSAGE then
                    parts[#parts + 1], current = current, {}
                end
            end
        end
    end
    if #current > 0 or #parts == 0 then parts[#parts + 1] = current end
    local messages = {}
    for index, part in ipairs(parts) do
        messages[index] = ("B|%d/%d|%s"):format(index, #parts, table.concat(part, ","))
    end
    return messages
end

-- `report` tells the player what is happening with a request they made (it prints to chat).
function ACB.initSocial(saved, send, now, after, report)
    report = report or function() end
    local pending, served, inbox, heard = {}, {}, {}, {}
    local requests = ACB.newRequests(saved, send, now, after, report)
    function ACB.requestWanted(peer) return requests:requestWanted(peer) end
    function ACB.askForCard(peer, card) return requests:ask(peer, card) end
    local titleChecks, titleServed = {}, {}

    function ACB.peerTitle(peer)
        local at = now()
        local check = titleChecks[peer]
        if check and at < check.expires then return check.title end
        check = { expires = at + TITLE_RETRY, pendingUntil = at + TITLE_REPLY_WINDOW }
        titleChecks[peer] = check
        if not send(peer, "T?") then check.pendingUntil = nil end
    end

    -- ---- Windows ----
    local function window(name, width, height, title)
        local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
        frame:SetSize(width, height)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        })
        frame:SetBackdropColor(0.072, 0.057, 0.049, 0.99)
        frame:SetBackdropBorderColor(0.78, 0.63, 0.42)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        frame.title:SetPoint("TOP", 0, -18)
        frame.title:SetTextColor(gold[1], gold[2], gold[3])
        frame.title:SetText(title)
        ACB.uiKit.closeButton(frame, -16, -16)
        table.insert(UISpecialFrames, name)
        frame:Hide()
        return frame
    end

    -- Another player's binder, read-only.
    local inspector = window("AzerothCardBinderInspect", 380, 560, "Binder")
    local scroll = CreateFrame("ScrollFrame", nil, inspector, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 28, -54)
    scroll:SetPoint("BOTTOMRIGHT", -44, 58)
    local inspectBody = CreateFrame("Frame", nil, scroll)
    inspectBody:SetSize(300, 100)
    scroll:SetScrollChild(inspectBody)
    local inspectText = inspectBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inspectText:SetPoint("TOPLEFT", 0, 0)
    inspectText:SetWidth(300)
    inspectText:SetJustifyH("LEFT")
    inspectText:SetJustifyV("TOP")
    inspectText:SetSpacing(3)

    -- Start a trade with the player whose binder this is.
    local tradeButton = ACB.uiKit.button(inspector, "Offer a trade", nil, nil, 130, function() end)
    tradeButton:SetSize(130, 24)
    tradeButton:SetPoint("BOTTOMLEFT", 28, 24)
    tradeButton:SetText("Offer a trade")
    tradeButton:SetScript("OnClick", function()
        if inspector.peer and ACB.prepareTrade then
            ACB.prepareTrade(inspector.peer)
            inspector:Hide()
        end
    end)

    -- Report this player for cheating. The second click, within a few seconds, is the one that counts, so one slip sends
    -- nothing; for another reason, or to add a note, use /acb report.
    local reportButton = ACB.uiKit.button(inspector, "Report", nil, nil, 120, function() end)
    reportButton:SetSize(120, 24)
    reportButton:SetPoint("BOTTOMRIGHT", -28, 24)
    reportButton:SetText("Report")
    local confirmUntil = 0
    reportButton:SetScript("OnClick", function()
        if not inspector.peer then return end
        if now() > confirmUntil then
            confirmUntil = now() + 6
            reportButton:SetText("Click to confirm")
            after(6, function() if now() >= confirmUntil then reportButton:SetText("Report") end end)
            report(("Report %s for cheating? Click Report again within a few seconds. For another reason, type /acb report."):format(inspector.peer))
            return
        end
        confirmUntil = 0
        reportButton:SetText("Report")
        local ok, problem = ACB.addReport(saved, inspector.peer, "cheating", "", time())
        report(ok and ("Report about %s saved. The companion app sends it the next time it syncs."):format(inspector.peer) or problem)
    end)

    function ACB.showInspect(peer, counts, shiny)
        inspector.peer, inspector.counts, inspector.shiny = peer, counts, shiny
        inspector.title:SetText(peer .. "'s binder" .. (ACB.isVerified(peer) and " (verified)" or ""))
        local heard = ACB.heardWanted and ACB.heardWanted[peer]
        local lines = ACB.inspectLines(counts, shiny, saved.counts, saved.wanted, heard and heard.cards)
        inspectText:SetText(table.concat(lines, "\n"))
        inspectBody:SetHeight(math.max(100, #lines * 15))
        inspector:Show()
    end

    -- Draw the binder window again, if it is open for this player (their wanted list has just arrived).
    function ACB.refreshInspect(peer)
        if inspector:IsShown() and inspector.peer == peer and inspector.counts then ACB.showInspect(peer, inspector.counts, inspector.shiny) end
    end

    -- ---- Asking for and answering binder views ----
    function ACB.requestBinder(peer)
        if not peer then return false, "Enter a player's name first." end
        local sent, reason = send(peer, "Q")
        if sent then
            local window = now() + REQUEST_WINDOW
            pending[peer], inbox[peer], heard[peer] = window, nil, nil
            requests:expectList(peer, window + 10) -- their wanted list follows the binder
            -- Say something if nothing comes back, instead of leaving the player looking at nothing.
            after(NO_ANSWER_AFTER, function()
                if pending[peer] == window and not heard[peer] then
                    report(("No answer from %s yet. They need this add-on, to be online, outdoors and out of combat, and to allow viewing (Settings)."):format(peer))
                end
            end)
            after(REQUEST_WINDOW + 1, function()
                if pending[peer] == window and inbox[peer] then
                    report(("Only part of %s's binder arrived. Ask again."):format(peer))
                end
            end)
            return true
        end
        return false, reason
    end

    function ACB.receiveView(peer, message)
        if not peer or type(message) ~= "string" or #message > 250 then return end
        if requests:handle(peer, message) then return end
        if message == "T?" then
            local at = now()
            if titleServed[peer] and at < titleServed[peer] then return end
            titleServed[peer] = at + TITLE_REPLY_WINDOW
            local title = saved.title
            send(peer, "T|" .. (ACB.isBinderTitle(title) and saved.titles[title] and title or ""))
            return
        end
        local title = message:match("^T|(.*)$")
        if title then
            local at = now()
            local check = titleChecks[peer]
            if not check or not check.pendingUntil or at > check.pendingUntil then return end
            if title ~= "" and not ACB.isBinderTitle(title) then return end
            check.title = title ~= "" and title or nil
            check.pendingUntil, check.expires = nil, at + TITLE_CACHE
            if check.title and ACB.refreshPeerTitle then ACB.refreshPeerTitle(peer) end
            return
        end
        if message == "Q" then
            -- Always answer, so the other player is told why nothing is coming rather than left waiting.
            if saved.inspectable == false then
                send(peer, "N|private")
                return
            end
            local started = now()
            if served[peer] and started < served[peer] then
                send(peer, "N|wait")
                return
            end
            local parts = ACB.encodeBinder(saved)
            served[peer] = started + math.max(SERVE_GAP, partDelay(#parts) + RETRY_DELAY)
            local function sendPart(part, attempt)
                if not send(peer, part) and attempt < RETRIES then
                    after(RETRY_DELAY, function() sendPart(part, attempt + 1) end)
                end
            end
            for index, part in ipairs(parts) do
                after(partDelay(index), function() sendPart(part, 1) end)
            end
            -- Then what this player is looking for, so the binder window can show it.
            after(partDelay(#parts + 1), function() sendPart(requests:listMessage(), 1) end)
            return
        end
        local refusal = message:match("^N|(%a+)$")
        if refusal then
            if not pending[peer] or now() > pending[peer] then return end
            heard[peer] = true
            if refusal == "private" then
                pending[peer], inbox[peer] = nil, nil
                report(peer .. " keeps their binder private.")
            elseif refusal == "wait" then
                report(peer .. "'s binder is still on its way. Give it a few seconds.")
            end
            return
        end
        local index, total, list = message:match("^B|(%d+)/(%d+)|([%w:=,%*]*)$")
        index, total = tonumber(index), tonumber(total)
        if not index or not total or total < 1 or total > MAX_PARTS or index < 1 or index > total then return end
        if not pending[peer] or now() > pending[peer] then return end -- only answers to our own request
        local book = inbox[peer]
        if not book or book.total ~= total then
            book = { total = total, got = {}, counts = {}, shiny = {} }
            inbox[peer] = book
        end
        heard[peer] = true
        if book.got[index] then return end
        book.got[index] = true
        for short, count, star in list:gmatch("([cov]%d+)=(%d+)(%*?)") do
            local key = longKey(short)
            if key and ACB.cards[key] then
                book.counts[key] = math.min(tonumber(count) or 0, 99)
                if star == "*" then book.shiny[key] = true end
            end
        end
        local have = 0
        for _ in pairs(book.got) do have = have + 1 end
        if have == total then
            pending[peer], inbox[peer] = nil, nil
            ACB.showInspect(peer, book.counts, book.shiny)
        end
    end

    -- ---- Right-clicking a player ----
    local function playerName(context)
        if type(context) ~= "table" then return end
        local name, realm = context.name, context.server
        if context.unit and UnitFullName then
            name, realm = UnitFullName(context.unit)
        end
        name, realm = ACB.read(name, "string"), ACB.read(realm, "string")
        if not name then return end
        return ACB.tradePeer(realm and realm ~= "" and (name .. "-" .. realm) or name)
    end

    if Menu and Menu.ModifyMenu then
        for _, tag in ipairs(MENUS) do
            pcall(Menu.ModifyMenu, tag, function(_, root, context)
                local peer = playerName(context)
                if not peer then return end
                root:CreateDivider()
                root:CreateButton("Offer a card trade", function() ACB.prepareTrade(peer) end)
                root:CreateButton("View their binder", function()
                    local ok, reason = ACB.requestBinder(peer)
                    if ok then
                        report("Asked " .. peer .. " for their binder. It opens when they answer.")
                    else
                        report(reason or "Could not ask for their binder.")
                    end
                end)
            end)
        end
    end

    if Menu and Menu.ModifyMenu then
        for _, tag in ipairs(PORTRAIT_MENUS) do
            pcall(Menu.ModifyMenu, tag, function(_, root, context)
                local unit = ACB.read(type(context) == "table" and context.unit or nil, "string")
                if not unit or not UnitGUID then return end
                local ok, guid = pcall(UnitGUID, unit)
                local entry = ok and ACB.source(guid)
                if not entry then return end
                root:CreateDivider()
                root:CreateButton("Open card in binder", function() ACB.openCard(entry.key) end)
            end)
        end
    end

    local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if addFilter then
        for _, chatType in ipairs(CHAT_TYPES) do
            addFilter("CHAT_MSG_" .. chatType, renderCardLinks)
        end
    end

    local function openLink(link)
        local entry = ACB.parseCardLink(link)
        if entry then ACB.openCard(entry.key) end
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link) openLink(link) end, ACB)
    elseif hooksecurefunc then
        pcall(hooksecurefunc, "SetItemRef", openLink)
    end
end

-- Draft a message the server can carry without a custom hyperlink.
function ACB.linkCard(saved, entry)
    local shiny = saved.shiny and saved.shiny[entry.key] == true
    local message = ("[ACB:%s:%d %s%s]"):format(entry.key, shiny and 1 or 0, entry.name, shiny and " (Shiny)" or "")
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        local editBox = ChatFrameUtil.GetActiveWindow()
        if editBox then
            editBox:Insert(message)
            editBox:SetFocus()
        else
            ChatFrameUtil.OpenChat(message, SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME)
        end
    elseif not (ChatEdit_InsertLink and ChatEdit_InsertLink(message)) and ChatFrame_OpenChat then
        ChatFrame_OpenChat(message)
    end
end
