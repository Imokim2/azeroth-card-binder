# Cards that cannot be won

A card whose creature cannot be killed can never drop, so it can never be won by playing, and neither can one whose creature appears only once. 31 cards are marked that way: ten from the scan below, 13 dungeon characters and 8 one-off kills added with the faction cards ([FACTION-CARDS.md](FACTION-CARDS.md)). They are held back for good: not in the launch collection, not needed to finish a page, never released by a season, and a season cannot name one (the server refuses it). Nothing is taken from anyone: a copy someone already owns stays, shows and can be traded.

The list is `AzerothCardBinder/UnobtainableCards.lua`. It sets `unobtainable` on the card; `tools/build-catalog-json.js` carries that into `packages/shared/catalog.json`, `tools/launch-collection.js` holds those cards back (CSV decision `never`) and the server's season rules (`server/src/seasons.ts`) refuse them.

## The scan

`node tools/scan-unkillable.js` reads the page of every creature card (3,384 of the 3,423 cards; the other 39 are gathering nodes, which are not killed) on wowforever.ninja, the fan database the catalog was built from. It is resumable (`--cache <file>`), polite (four readers, a short pause), and `--offline` re-analyses what it already read. `--report <file>` writes a Markdown report. It exits 1 if it flags a card that is not in `UnobtainableCards.lua`, so it can be run again after the catalog changes.

What the site gives: level, rank, type, health, reaction to each faction and zones. It does not say "cannot be attacked", so the scan flags what the data points to:

| | What the data says | Cards | Treatment |
|---|---|---|---|
| A | Type "Non-combat Pet" (companion pets) | 6: Silver Tabby, Orange Tabby, Cornish Rex, Bombay, Senegal, Cockatiel | Marked. Firm. |
| B | No health, a level 1 totem, a portal, or an event spirit | 4: Gordok Spirit, C'Thun Portal, Dire Maul Crystal Totem, Spirit of Azuregos | Marked. Very likely, so check each in the game. |
| D | Dungeon and raid characters the data lists as friendly to both factions (Naralex, Sah'rhee, Old Ironbark, Lord Victor Nefarius and similar) | 13 | Marked. Likely, check in the game. |
| E | No spawn point in the game database: summoned by a quest or an event (Nightlash, Verog, Echeyakee, three Galak, two Kolkar) | 8 | Marked. One-off: it cannot be farmed. A creature that only respawns slowly is not one. |
| C | No data at all (new Forever creatures: four Zephras Isle rares, Galemender Delanea and others; Rabid Forest Wolf has no page) | 9 | Left alone. Unknown, not evidence. Check in the game. |

The scan found no creature that is friendly to both factions, and the 321 that are neutral to both are all attackable. Every card also maps to exactly one creature in the add-on and no two cards share one.

Before the change seven of the 19 flagged cards were launch cards that would have stopped a page being finished (Bombay, Gordok Spirit, Spirit of Azuregos and the four Zephras Isle rares). Now the three marked ones (Bombay, Gordok Spirit, Spirit of Azuregos) are held back and three ordinary cards take their place, so the launch collection is still exactly half of the cards both factions can win (now 1,729 of 3,459). The four Zephras Isle rares are unverified, so they stay launch cards until someone checks them in the game.

## After checking in the game

- A card in B or C turns out to be killable: delete its line from `UnobtainableCards.lua` (for B), then run `node tools/build-catalog-json.js`, `node tools/launch-collection.js --write`, `node tools/build-catalog-json.js`, `node tools/build-vectors.js` and `node tools/launch-collection.js --write`, and commit the regenerated files. It goes back to being an ordinary held-back card.
- A card in C cannot be killed: add `["npc:<id>"] = "<name>: <why> (checked in game)"` and regenerate the same way. The tests require 31 entries today; change that number in `tests/unobtainable-cards.test.js` with the list.
- Changing which cards are launch cards after a release changes what players can win. Do it before launch, or announce it.
