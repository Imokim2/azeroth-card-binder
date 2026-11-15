-- Guild binders (docs/proposals/GUILD-BINDERS-DESIGN.md, ledger spec 11): a Ranked binder gives a copy of a card to its guild for good. The companion
-- app writes what the server says into Data/Sync.lua (ACB.sync.guild); the add-on writes donate and donateReturn events and never asks the server.

do
    local GUILD, OTHER_GUILD = "01HF7YAT00QKSEP5RCNMPTQ3KN", "01HF7YAT00QKSEP5RCNMPTQ3KP"
    local CARD, OTHER = "npc:589", "npc:590"

    -- A Ranked binder, in a guild, holding `copies` of CARD that the ledger knows about (so it still verifies).
    local function guildBinder(copies, member)
        local saved, ledger = modeBinder()
        saved.mode = "ranked"
        for index = 1, copies do
            local before = saved.counts[CARD] or 0
            saved.counts[CARD] = before + 1
            ledger:record("tradeIn", CARD, { before = before, partner = "bob-realm", trade = "gift" .. index })
        end
        ACB.sync = { guild = { binders = { saved.modeSetupID }, donations = { results = {}, refunds = {} },
            membership = member == false and nil or { state = "active", role = "member", guild = { id = GUILD, name = "Knights of Light", realm = "Realm", side = "alliance", members = 3 } } } }
        return saved, ledger
    end
    local function kinds(saved, from)
        local list = {}
        for index = from or 1, #saved.ledger do list[#list + 1] = saved.ledger[index].kind .. ":" .. saved.ledger[index].key end
        return table.concat(list, " ")
    end

    test("saved guild donations keep only well-formed pending operations", function()
        local saved = ACB.cleanSavedData({})
        local good = ("a"):rep(32)
        saved.guildDonations = {
            [good] = { key = CARD, guild = GUILD, t = 5, extra = "dropped" },
            ["short"] = { key = CARD, guild = GUILD, t = 5 },
            [("b"):rep(32)] = { key = "npc:0", guild = GUILD, t = 5 },
            [("c"):rep(32)] = { key = CARD, guild = "bad", t = 5 },
            [("d"):rep(32)] = { key = CARD, guild = GUILD, t = "x" },
            [("e"):rep(32)] = "nope",
        }
        ACB.cleanGuildData(saved)
        local count = 0
        for _ in pairs(saved.guildDonations) do count = count + 1 end
        equal(count, 1)
        equal(saved.guildDonations[good].key, CARD)
        equal(saved.guildDonations[good].extra, nil)
        saved.guildDonations = "junk"
        ACB.cleanGuildData(saved)
        equal(next(saved.guildDonations), nil)
    end)

    test("guild data is used only for the binder the companion paired it with", function()
        local keep = ACB.sync
        local saved = guildBinder(1)
        equal(ACB.guildData(saved) ~= nil, true)
        local guild, role = ACB.guildMembership(saved)
        equal(guild.name, "Knights of Light"); equal(role, "member")
        ACB.sync.guild.binders = { ("f"):rep(32) }
        equal(ACB.guildData(saved), nil)
        equal(ACB.guildMembership(saved), nil)
        ACB.sync.guild.binders = { saved.modeSetupID }
        ACB.sync.guild.membership.state = "pending"
        equal(ACB.guildMembership(saved), nil, "an application is not a membership")
        ACB.sync = nil
        equal(ACB.guildData(saved), nil)
        ACB.sync = keep
    end)

    test("a donation writes the markers once, then the donate event, and the copy leaves the binder", function()
        local keep = ACB.sync
        local saved, ledger = guildBinder(2)
        local before = #saved.ledger
        local ok, operation = ACB.donateCard(saved, ledger, CARD)
        equal(ok, true)
        equal(kinds(saved, before + 1), "mode:chase1 mode:chase2 mode:launch1 mode:faction1 mode:side:alliance mode:guild1 donate:" .. CARD)
        local event = saved.ledger[#saved.ledger]
        equal(event.partner, GUILD); equal(event.trade, operation); equal(event.count, 1); equal(event.dust, 0); equal(event.shiny, 0); equal(event.tape, 0)
        equal(#operation, 32); equal(operation:find("[^0-9a-f]"), nil)
        equal(saved.counts[CARD], 1)
        equal(saved.guildDonations[operation].key, CARD); equal(saved.guildDonations[operation].guild, GUILD)
        equal(ACB.pendingDonationCount(saved), 1)
        equal(ledger:check(), true)
        -- Every event still verifies as a chain, with the new kinds.
        equal(select(1, ACB.checkChain(saved.ledger, { seq = saved.ledger[1].seq - 1, hash = saved.ledger[1].prev })), true)

        -- The next donation writes no more markers, and the last copy leaves the card at nothing.
        local count = #saved.ledger
        local ok2, second = ACB.donateCard(saved, ledger, CARD)
        equal(ok2, true)
        equal(kinds(saved, count + 1), "donate:" .. CARD)
        assert(second ~= operation, "every donation has its own operation id")
        equal(saved.counts[CARD], nil)
        equal(ledger:check(), true)
        local gone, reason = ACB.donateCard(saved, ledger, CARD)
        equal(gone, false); equal(reason, "You do not own that card.")
        ACB.sync = keep
    end)

    test("a donation is refused unless the binder is Ranked, clean, in a guild and has the card", function()
        local keep = ACB.sync
        local saved, ledger = guildBinder(1)
        local function refused(text)
            local ok, reason = ACB.donateCard(saved, ledger, CARD)
            equal(ok, false); assert(reason:find(text, 1, true), reason)
            equal(saved.counts[CARD], 1, "nothing left the binder")
        end
        saved.mode = "casual"; refused("Ranked"); saved.mode = "ranked"
        saved.casualDrops = 1; refused("Casual finds"); saved.casualDrops = nil
        saved.legacy = true; refused("Ranked"); saved.legacy = nil
        saved.balancedDrops = nil; refused("drop rules"); saved.balancedDrops = 2
        ACB.sync.guild.membership = nil; refused("not in a guild")
        ACB.sync.guild.membership = { state = "pending", guild = { id = GUILD, name = "G", realm = "R", side = "alliance" } }; refused("not in a guild")
        equal(ACB.canDonate(saved, ledger, "npc:999999999"), false)
        equal(ACB.canDonate(saved, ledger, OTHER), false)
        saved.guildDonations = {}
        for index = 1, ACB.maxPendingDonations do saved.guildDonations[("%032x"):format(index)] = { key = CARD, guild = GUILD, t = 1 } end
        ACB.sync.guild.membership = { state = "active", role = "member", guild = { id = GUILD, name = "G", realm = "R", side = "alliance" } }
        refused("waiting for the server")
        saved.guildDonations = {}
        saved.ledger[#saved.ledger + 1] = saved.ledger[#saved.ledger] -- the history no longer verifies
        refused("does not verify")
        ACB.sync = keep
    end)

    test("a donation the server credited is finished; one it refused comes back as a donateReturn, once", function()
        local keep = ACB.sync
        local saved, ledger = guildBinder(2)
        local first = select(2, ACB.donateCard(saved, ledger, CARD))
        local second = select(2, ACB.donateCard(saved, ledger, CARD))
        equal(saved.counts[CARD], nil)
        local said = {}
        local function report(text) said[#said + 1] = text end
        -- Nothing from the server yet: nothing changes.
        equal(ACB.settleGuild(saved, ledger, report), 0)
        equal(ACB.pendingDonationCount(saved), 2)
        -- The first was credited, the second refused.
        ACB.sync.guild.donations = { results = { [first] = "credited", [second] = "refunded" }, refunds = { { operation = second, guild = GUILD, card = CARD } } }
        local count = #saved.ledger
        equal(ACB.settleGuild(saved, ledger, report), 1)
        equal(kinds(saved, count + 1), "donateReturn:" .. CARD)
        local back = saved.ledger[#saved.ledger]
        equal(back.partner, GUILD); equal(back.trade, second); equal(back.count, 1)
        equal(saved.counts[CARD], 1)
        equal(ACB.pendingDonationCount(saved), 0)
        equal(ledger:check(), true)
        assert(said[1]:find("back in your binder", 1, true), said[1])
        -- The server still lists the refund until it has seen the donateReturn: the binder does not write it twice.
        equal(ACB.settleGuild(saved, ledger, report), 0)
        equal(saved.counts[CARD], 1)
        -- A refund for a donation this binder never made, or for another card or guild, is ignored.
        local third = select(2, ACB.donateCard(saved, ledger, CARD))
        ACB.sync.guild.donations = { results = {}, refunds = {
            { operation = ("9"):rep(32), guild = GUILD, card = CARD },
            { operation = third, guild = OTHER_GUILD, card = CARD },
            { operation = third, guild = GUILD, card = OTHER },
        } }
        equal(ACB.settleGuild(saved, ledger, report), 0)
        equal(saved.counts[CARD], nil)
        equal(ACB.pendingDonationCount(saved), 1)
        -- "returned" from the server also closes a donation (the return was written on another machine's saved file).
        ACB.sync.guild.donations = { results = { [third] = "returned" }, refunds = {} }
        ACB.settleGuild(saved, ledger, report)
        equal(ACB.pendingDonationCount(saved), 0)
        -- Another binder's data is ignored.
        local other, otherLedger = guildBinder(1)
        local stale = select(2, ACB.donateCard(other, otherLedger, CARD))
        ACB.sync.guild = { binders = { ("f"):rep(32) }, donations = { results = { [stale] = "credited" }, refunds = {} } }
        equal(ACB.settleGuild(other, otherLedger, report), 0)
        equal(ACB.pendingDonationCount(other), 1)
        ACB.sync = keep
    end)

    test("/acb guild says where the binder stands and asks before a donation", function()
        local keep, keepLedger = ACB.sync, ACB.ledger
        local saved, ledger = guildBinder(2)
        ACB.ledger = ledger
        local said = {}
        local function report(text) said[#said + 1] = text end
        ACB.guildCommand(saved, "", report)
        assert(said[1]:find("Knights of Light", 1, true) and said[1]:find("a member", 1, true), said[1])
        said = {}
        ACB.guildCommand(saved, "donate confirm", report)
        equal(said[1], "Nothing to confirm. Start with /acb guild donate <card name>.")
        said = {}
        ACB.guildCommand(saved, "donate Not A Card", report)
        equal(said[1], "You do not own a card with that name.")
        said = {}
        local name = ACB.cards[CARD].name
        local before = #saved.ledger
        ACB.guildCommand(saved, "donate " .. name, report)
        assert(said[1]:find("for good", 1, true) and said[1]:find("/acb guild donate confirm", 1, true), said[1])
        equal(#saved.ledger, before, "asking changes nothing")
        equal(saved.counts[CARD], 2)
        ACB.guildCommand(saved, "donate cancel", report)
        ACB.guildCommand(saved, "donate confirm", report)
        equal(said[#said], "Nothing to confirm. Start with /acb guild donate <card name>.")
        ACB.guildCommand(saved, "donate " .. name, report)
        ACB.guildCommand(saved, "donate confirm", report)
        assert(said[#said]:find("Donated", 1, true), said[#said])
        equal(saved.counts[CARD], 1)
        ACB.guildCommand(saved, "", report)
        assert(said[#said - 0]:find("1 donation is waiting", 1, true), said[#said])
        ACB.guildCommand(saved, "nonsense", report)
        equal(said[#said], "Use /acb guild, or /acb guild donate <card name>.")
        -- Not in a guild, applied, or no companion data.
        ACB.sync.guild.membership = { state = "pending", guild = { name = "Waiting Guild" } }
        said = {}
        ACB.guildCommand(saved, "", report)
        assert(said[1]:find("Waiting Guild", 1, true), said[1])
        ACB.sync.guild.membership = nil
        ACB.guildCommand(saved, "", report)
        assert(said[2]:find("not in a guild binder", 1, true), said[2])
        ACB.sync = nil
        ACB.guildCommand(saved, "", report)
        assert(said[3]:find("companion app", 1, true), said[3])
        ACB.sync, ACB.ledger = keep, keepLedger
    end)

    test("the slash command reaches the guild commands", function()
        local keep, keepLedger = ACB.sync, ACB.ledger
        ACB.sync = { guild = { binders = {} } }
        SlashCmdList.AZEROTHCARDBINDER("guild")
        SlashCmdList.AZEROTHCARDBINDER("guild donate nothing")
        ACB.sync, ACB.ledger = keep, keepLedger
    end)
    test("guild page confirms a permanent donation, supports cancellation and prevents repeat acceptance", function()
        local keepSync, keepLedger, keepRefresh = ACB.sync, ACB.ledger, ACB.refresh
        local saved, ledger = guildBinder(2)
        ACB.ledger, ACB.refresh = ledger, function() end
        ACB.sync.guild.summary = { guildId = GUILD, cards = 1, points = 10, inventory = { { card = CARD, copies = 1 } } }
        local view = ACB.createGuildView(UIParent, saved)
        view:refresh(); view.controls.contribute.OnClick()
        view.controls.donate.OnClick()
        equal(2, saved.counts[CARD]); assert(view.controls.confirm:IsShown())
        view.controls.cancel.OnClick(); equal(2, saved.counts[CARD])
        view.controls.donate.OnClick(); view.controls.accept.OnClick()
        equal(1, saved.counts[CARD]); equal(1, ACB.pendingDonationCount(saved))
        view.controls.accept.OnClick(); equal(1, saved.counts[CARD])
        ACB.sync, ACB.ledger, ACB.refresh = keepSync, keepLedger, keepRefresh
    end)

    test("guild donation confirmation cannot be reused after membership changes", function()
        local keepSync, keepLedger, keepRefresh = ACB.sync, ACB.ledger, ACB.refresh
        local saved, ledger = guildBinder(2)
        ACB.ledger, ACB.refresh = ledger, function() end
        ACB.sync.guild.summary = { guildId = GUILD, cards = 0, points = 0, inventory = {} }
        local view = ACB.createGuildView(UIParent, saved)
        view:refresh(); view.controls.contribute.OnClick(); view.controls.donate.OnClick()
        ACB.sync.guild.membership.guild.id = OTHER_GUILD
        view.controls.accept.OnClick()
        equal(2, saved.counts[CARD]); equal(0, ACB.pendingDonationCount(saved))
        ACB.sync, ACB.ledger, ACB.refresh = keepSync, keepLedger, keepRefresh
    end)

    test("guild donation list defaults to spares and supports literal name searches", function()
        local saved = { counts = { [CARD] = 1, [OTHER] = 2 } }
        local rows = ACB.guildCardRows(saved, {}, true, true, "")
        equal(1, #rows); equal(OTHER, rows[1].key)
        equal(2, #ACB.guildCardRows(saved, {}, true, false, ""))
        equal(0, #ACB.guildCardRows(saved, {}, true, false, "["))
    end)

end
