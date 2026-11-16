local _, ACB = ...

-- The Fellowship set (docs/FELLOWSHIP.md, ledger spec 12): four cards for doing things together. None of them drops from a creature. Each can drop only
-- when you complete its activity: a trade with another player, a gift given or received, a donation to your guild binder, or sitting at a camp
-- with the campfire buff. The chance is one in a hundred each time, flat: it does not build up after misses (DropRates.lua gives these cards the
-- "flat" style), and at a campfire it is doubled like any common or rare card's.
-- Their keys sit in the npc: space with ids no creature has, so everything that handles card keys already accepts them.

ACB.pages[#ACB.pages + 1] = { title = "Fellowship", zone = "fellowship", group = "Social", code = "FW",
    subtitle = "Cards for doing things together", cards = {} }
local page = #ACB.pages
ACB.zones.fellowship = { name = "Fellowship", kind = "Social", place = "every place you meet other players",
    top = { 0.66, 0.46, 0.22 }, bottom = { 0.18, 0.10, 0.05 } }

-- What each activity is, in the words the add-on uses for it.
ACB.activities = {
    trade = "a trade with another player",
    gift = "a gift given or received",
    donate = "a card donated to your guild binder",
    camp = "sitting at a camp with the campfire buff",
}
ACB.activityCards = {}

local function fellow(id, name, activity, icon, lore)
    local key = "npc:" .. id
    local entry = {
        key = key, id = id, name = name, rank = "activity", icon = "Interface\\Icons\\" .. icon, boss = false, page = page, zone = "fellowship",
        lore = lore, activity = activity, since = 12, rarity = "rare", serial = ("F%05d"):format(id % 100000),
    }
    ACB.cards[key] = entry
    ACB.activityCards[activity] = entry
    table.insert(ACB.pages[page].cards, entry)
end

fellow(900000001, "The Trader", "trade", "INV_Misc_Coin_02", "A fair swap, fairly made, and a handshake to seal it.")
fellow(900000002, "The Gifter", "gift", "INV_Misc_Gift_01", "Given freely, and remembered long after.")
fellow(900000003, "The Benefactor", "donate", "INV_Shirt_GuildTabard_01", "What the guild keeps, the guild remembers.")
fellow(900000004, "Fireside Friend", "camp", "Spell_Fire_Fire", "Warm hands and warmer company at the end of a long road.")
