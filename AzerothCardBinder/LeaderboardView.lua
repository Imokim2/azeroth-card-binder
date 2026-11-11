local _, ACB = ...
local kit = ACB.uiKit
local brass = kit.brass
local parchment = kit.parchment
local muted = kit.muted
local gold = kit.gold
local label = kit.label
local backdrop = kit.backdrop

-- The Ladder tab: the top of the Ranked ladder, where you stand, and who finished each set first. The numbers are
-- written into Data/Sync.lua by the companion app (docs/ROADMAP.md, 2.4), so they are as fresh as the last sync and
-- reload. Without the app there is nothing to show but a note saying so.

-- Players the server has checked (a ranked character on the ladder), as written by the app. Names are in the form
-- the add-on uses between players: "name-realmname", lower case.
function ACB.isVerified(peer)
    local verified = ACB.sync and ACB.sync.verified
    return type(verified) == "table" and type(peer) == "string" and verified[peer] == true
end

-- Points are kept in tenths so every value is a whole number; this is how they are shown.
function ACB.pointsText(tenths)
    return ("%g"):format((tonumber(tenths) or 0) / 10)
end

-- The ladder rows the app wrote, at most 100, with anything that is not a well-formed row left out.
function ACB.ladderRows()
    local rows, list = {}, ACB.sync and ACB.sync.leaderboard
    if type(list) ~= "table" then return rows end
    for _, row in ipairs(list) do
        if type(row) == "table" and type(row.name) == "string" and type(row.rank) == "number" then
            rows[#rows + 1] = row
            if #rows >= 100 then break end
        end
    end
    return rows
end

-- Who finished each set first, as lines of text.
function ACB.firstsLines()
    local lines, list = {}, ACB.sync and ACB.sync.firsts
    if type(list) ~= "table" then return lines end
    for _, row in ipairs(list) do
        if type(row) == "table" and type(row.title) == "string" and type(row.by) == "string" then
            lines[#lines + 1] = ("%s: %s"):format(row.title, row.by)
        end
    end
    return lines
end

-- What to say about the player's own place.
function ACB.ladderStatus(saved)
    local you = ACB.sync and ACB.sync.you
    if type(you) == "table" and type(you.rank) == "number" then
        return ("You are number %d with %s points (%d cards, %d sets)."):format(
            you.rank, ACB.pointsText(you.score), tonumber(you.cards) or 0, tonumber(you.sets) or 0)
    end
    -- Only Ranked counts: a binder with unverifiable cards or drops cannot be on the ladder.
    if saved.legacy then return "This binder holds cards from before the ledger, which the server cannot check, so it cannot join the ladder." end
    if (saved.casualDrops or 0) > 0 then
        return ("This binder has %d Casual drop%s, which cannot be checked, so it cannot join the ladder."):format(saved.casualDrops, saved.casualDrops == 1 and "" or "s")
    end
    if saved.mode ~= "ranked" then return "Switch to Ranked in Settings before your next drop to join the ladder. Only Ranked counts." end
    if #ACB.ladderRows() == 0 then return "No standings yet. The companion app brings them in when it syncs." end
    return "You are not on the ladder yet. Standings update when the companion app syncs and you reload."
end

local ROWS, ROW_HEIGHT = 100, 18

function ACB.createLadderView(frame, saved)
    local view = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    view:SetPoint("TOPLEFT", 20, -109)
    view:SetSize(900, 500)
    backdrop(view, "Interface\\Buttons\\WHITE8X8", 1)
    view:SetBackdropColor(0.13, 0.09, 0.07, 1)
    view:SetBackdropBorderColor(0.58, 0.43, 0.27, 1)
    label(view, "GameFontNormalLarge", 32, 20, brass, "Ranked ladder")
    local status = label(view, "GameFontHighlight", 32, 52, gold, "")
    status:SetWidth(560)
    local updated = label(view, "GameFontHighlightSmall", 32, 76, muted, "")
    updated:SetWidth(560)
    for text, x in pairs({ ["#"] = 38, Player = 80, Cards = 380, Sets = 440, Points = 495 }) do
        label(view, "GameFontNormalSmall", x, 100, brass, text)
    end
    local scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 32, -120)
    scroll:SetPoint("BOTTOMRIGHT", -310, 16)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(540, ROWS * ROW_HEIGHT)
    scroll:SetScrollChild(body)
    local rows = {}
    local function row(index)
        if rows[index] then return rows[index] end
        local line = {}
        local y = (index - 1) * ROW_HEIGHT
        line.rank = label(body, "GameFontHighlightSmall", 6, y, parchment, "")
        line.name = label(body, "GameFontHighlightSmall", 48, y, parchment, "")
        line.name:SetWidth(290)
        line.cards = label(body, "GameFontHighlightSmall", 348, y, parchment, "")
        line.sets = label(body, "GameFontHighlightSmall", 408, y, parchment, "")
        line.points = label(body, "GameFontHighlightSmall", 463, y, parchment, "")
        rows[index] = line
        return line
    end
    label(view, "GameFontNormal", 620, 100, brass, "First to finish a set")
    local firsts = label(view, "GameFontHighlightSmall", 620, 124, parchment, "")
    firsts:SetWidth(260)
    firsts:SetJustifyV("TOP")
    firsts:SetSpacing(4)

    function view:refresh()
        status:SetText(ACB.ladderStatus(saved))
        local at = ACB.sync and tonumber(ACB.sync.syncedAt)
        updated:SetText(at and at > 0 and ("Standings as of " .. (date and date("%d %b %H:%M", at) or tostring(at))
            .. ". They refresh when the companion app syncs and you reload.") or "")
        local list = ACB.ladderRows()
        local you = ACB.sync and type(ACB.sync.you) == "table" and ACB.sync.you.rank
        for index = 1, math.max(#list, #rows) do
            local entry, line = list[index], row(index)
            for _, field in pairs(line) do field:SetShown(entry ~= nil) end
            if entry then
                local color = entry.rank == you and gold or parchment
                line.rank:SetText(tostring(entry.rank))
                line.name:SetText(entry.name)
                line.cards:SetText(tostring(tonumber(entry.cards) or 0))
                line.sets:SetText(tostring(tonumber(entry.sets) or 0))
                line.points:SetText(ACB.pointsText(entry.score))
                for _, field in pairs(line) do field:SetTextColor(unpack(color)) end
            end
        end
        body:SetHeight(math.max(ROW_HEIGHT, #list * ROW_HEIGHT))
        local lines = ACB.firstsLines()
        firsts:SetText(#lines > 0 and table.concat(lines, "\n") or "Nobody yet.")
    end
    return view
end
