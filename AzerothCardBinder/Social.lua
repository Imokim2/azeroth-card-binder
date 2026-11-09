local _, ACB = ...

-- Sharing with other players: right-click a player to offer a trade or look at their binder, put a
-- card in chat as a link, and open a card someone else linked.
--   Card link:   |Haddon:AzerothCardBinder:card:<key>:<shiny 0|1>|h[Name]|h
--   Viewing:     a read-only copy of the owner's counts is whispered on request (prefix below).
--                /acb privacy stops your binder from being viewable.
ACB.viewPrefix = "AzerothBinderV1"

local ENTRIES_PER_MESSAGE = 20
local MAX_PARTS = 150
local REQUEST_WINDOW, SERVE_GAP = 30, 10
local MENUS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET" }
local gold, goldDark, muted = { 1, 0.82, 0 }, { 0.42, 0.33, 0.14 }, { 0.65, 0.61, 0.54 }

-- ---- Card links ----

function ACB.cardLink(entry, shiny)
    local color = ACB.rarities[entry.rarity].color
    return ("|cff%02x%02x%02x|Haddon:AzerothCardBinder:card:%s:%d|h[%s%s]|h|r"):format(
        color[1] * 255 + 0.5, color[2] * 255 + 0.5, color[3] * 255 + 0.5,
        entry.key, shiny and 1 or 0, entry.name, shiny and " (Shiny)" or "")
end

-- Read the part of a clicked link after the "addon:" prefix back into a catalog card.
function ACB.parseCardLink(link)
    if type(link) ~= "string" or #link > 80 then return end
    local key, shiny = link:match("^addon:AzerothCardBinder:card:(%a+:%d+):([01])$")
    local entry = key and ACB.cards[key]
    if entry then return entry, shiny == "1" end
end

-- Find an owned card by part of its name.
function ACB.findCard(saved, text)
    text = (text or ""):lower():match("^%s*(.-)%s*$")
    if text == "" then return end
    local best
    for _, page in ipairs(ACB.pages) do
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
local function shortKey(card) return (card.profession and "o" or "c") .. card.id end
local function longKey(short)
    local kind, id = short:match("^([co])(%d+)$")
    return kind and ((kind == "o" and "node:" or "npc:") .. id)
end

-- The messages that describe a binder: "B|part/parts|key=count[*],..." where * marks a shiny.
function ACB.encodeBinder(saved)
    local parts, current = {}, {}
    for _, page in ipairs(ACB.pages) do
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

-- Printable lines for someone's binder: totals, then one line for every set they have started.
function ACB.inspectLines(counts, shiny)
    local lines, owned, total, shinies = {}, 0, 0, 0
    local sets = {}
    for _, page in ipairs(ACB.pages) do
        local have = 0
        for _, card in ipairs(page.cards) do
            total = total + 1
            if (counts[card.key] or 0) > 0 then
                have, owned = have + 1, owned + 1
                if shiny[card.key] then shinies = shinies + 1 end
            end
        end
        if have > 0 then sets[#sets + 1] = ("%s   %d / %d"):format(page.title, have, #page.cards) end
    end
    lines[1] = ("%d of %d cards collected, %d shiny"):format(owned, total, shinies)
    lines[2] = ""
    for _, line in ipairs(sets) do lines[#lines + 1] = line end
    if #sets == 0 then lines[#lines + 1] = "No cards yet." end
    return lines
end

function ACB.initSocial(saved, send, now, after)
    local pending, served, inbox = {}, {}, {}

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
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
        table.insert(UISpecialFrames, name)
        frame:Hide()
        return frame
    end

    -- A card someone linked, shown at a readable size.
    local viewer = window("AzerothCardBinderViewer", 240, 330, "Shared card")
    local viewerCard = ACB.createCard(viewer)
    viewerCard.frame:SetPoint("TOP", viewer, "TOP", 0, -52)
    viewerCard.frame:SetScale(1.45)
    viewerCard.frame:EnableMouse(false)
    local viewerNote = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    viewerNote:SetPoint("BOTTOM", 0, 20)
    viewerNote:SetTextColor(muted[1], muted[2], muted[3])

    function ACB.showSharedCard(entry, shiny)
        viewer.title:SetText(shiny and "Shared shiny card" or "Shared card")
        viewerCard:set(entry, 1, shiny)
        local mine = saved.counts[entry.key] or 0
        viewerNote:SetText(mine > 0 and ("You own %d of this card."):format(mine) or "You do not have this card yet.")
        viewer:Show()
    end

    -- Another player's binder, read-only.
    local inspector = window("AzerothCardBinderInspect", 380, 560, "Binder")
    local scroll = CreateFrame("ScrollFrame", nil, inspector, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 28, -54)
    scroll:SetPoint("BOTTOMRIGHT", -44, 24)
    local inspectBody = CreateFrame("Frame", nil, scroll)
    inspectBody:SetSize(300, 100)
    scroll:SetScrollChild(inspectBody)
    local inspectText = inspectBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inspectText:SetPoint("TOPLEFT", 0, 0)
    inspectText:SetWidth(300)
    inspectText:SetJustifyH("LEFT")
    inspectText:SetJustifyV("TOP")
    inspectText:SetSpacing(3)

    function ACB.showInspect(peer, counts, shiny)
        inspector.title:SetText(peer .. "'s binder")
        local lines = ACB.inspectLines(counts, shiny)
        inspectText:SetText(table.concat(lines, "\n"))
        inspectBody:SetHeight(math.max(100, #lines * 15))
        inspector:Show()
    end

    -- ---- Asking for and answering binder views ----
    function ACB.requestBinder(peer)
        if not peer then return false, "Enter a player's name first." end
        local sent, reason = send(peer, "Q")
        if sent then
            pending[peer] = now() + REQUEST_WINDOW
            inbox[peer] = nil
            return true
        end
        return false, reason
    end

    function ACB.receiveView(peer, message)
        if not peer or type(message) ~= "string" or #message > 250 then return end
        if message == "Q" then
            if saved.inspectable == false then return end
            if served[peer] and now() - served[peer] < SERVE_GAP then return end
            served[peer] = now()
            for index, part in ipairs(ACB.encodeBinder(saved)) do
                after(0.3 * (index - 1), function() send(peer, part) end)
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
        if book.got[index] then return end
        book.got[index] = true
        for short, count, star in list:gmatch("([co]%d+)=(%d+)(%*?)") do
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
                    if not ok then print("Azeroth Card Binder  " .. (reason or "Could not ask for their binder.")) end
                end)
            end)
        end
    end

    -- ---- Clicking a card link ----
    if hooksecurefunc then
        pcall(hooksecurefunc, "SetItemRef", function(link)
            local entry, shiny = ACB.parseCardLink(link)
            if entry then ACB.showSharedCard(entry, shiny) end
        end)
    end
end

-- Put a card link in the chat box, or hand it back so the caller can print it.
function ACB.linkCard(saved, entry)
    local link = ACB.cardLink(entry, saved.shiny and saved.shiny[entry.key] == true)
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return link end
    if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
    return link
end
