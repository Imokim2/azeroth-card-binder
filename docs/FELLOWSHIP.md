# The Fellowship cards

Four cards for doing things together. None of them drops from a creature: each can drop only when you complete its activity, once for each time you do. The chance is one in a hundred, flat: it does not build up after misses the way a creature's does, and it is the same for everyone. At a camp with the campfire buff it is doubled, like any common or rare card ([CAMPFIRE.md](CAMPFIRE.md)).

| Card | Activity | Who rolls |
|---|---|---|
| **The Trader** | A trade (a swap of cards or packs) | Both players, once each |
| **The Gifter** | A gift: giving a card or pack with nothing in return, or receiving one | The giver and the receiver, once each |
| **The Benefactor** | A card donated to your guild binder | The donor, once per copy donated |
| **Fireside Friend** | Sitting at a camp with the campfire buff (each new claim) | The player at the camp |

The four are one page, **Fellowship** (code `FW`, group Social), and the page is finished by owning all four. Finishing it earns the **Better Together** achievement and the **Fellow Traveler** title. (The page itself has no title of its own, so there is one title for the set, not two.)

## Art

They use game icons for now, shown the way a gathering node is: a large icon on the portrait window of the card, on the binder's seal backdrop, with no 3D model. The icons are `INV_Misc_Coin_02` (The Trader), `INV_Misc_Gift_01` (The Gifter), `INV_Shirt_GuildTabard_01` (The Benefactor) and `Spell_Fire_Fire` (Fireside Friend), set in `AzerothCardBinder/CatalogFellowship.lua`. These are standard Classic icon names; they have not been checked in the Forever client, and a name the client does not have shows as a blank square. Replacing one is a one-line change and touches nothing else, because the picture is not part of the ledger.

## How a roll works

- The add-on pays a roll as soon as an activity completes. For a camp it waits until just before your next creature attempt, because the claim is written in the middle of one.
- In Ranked a roll uses a tape entry like any other attempt, and is written as a drop or a miss on the activity's card, straight after the activity. With no tape left it stays owed (up to 50) and is paid when the tape comes.
- In Casual a roll uses the computer's own random numbers, and a drop counts as a Casual find, like any Casual drop (it keeps the binder out of Ranked).
- The cards cannot be crafted with dust, are never in a pack, and are not part of a season or the launch split. Copies can be traded, gifted, donated and recycled like any other card, so a spare of one can itself be a gift.

## The ledger and the server

This is ledger version 12 (`docs/LEDGER-SPEC.md`, *Fellowship cards*). `mode/fellow1` is written once, before the first activity that earns a roll; after it the ledger keeps a count of rolls earned by activity events, and an attempt on an activity card is valid only if it has a roll to spend. The server therefore rechecks the same things for these cards as for any: that the roll is the one the tape gave, at the flat chance, and that the attempt followed an activity.

**What this does not prove.** A trade, a gift or a donation is the player's own record. The server matches the two halves of a trade between players and flags halves nobody confirms, and a donation is settled by the server, but a player who writes a gift to a partner who never agreed to it earns the same roll as an honest one. The card is cosmetic and cheap to reach, so there is no further check; if it matters, the answer is the same as for trades in general: the trade-matching flags.

## If a game patch changes something

- The icons: see above.
- The camp spell ids are in `AzerothCardBinder/Campfire.lua` (`ACB.campAuras`).
