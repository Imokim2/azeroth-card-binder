# Faction cards, dungeon cards and one-off kills

Ledger spec 10 (`mode/faction1`, `mode/side:*`; see [the ledger spec](LEDGER-SPEC.md), "Faction cards"). Three rules about which creatures have a card and who can win it.

## 1. A creature the other faction cannot kill is a card only one faction can win

A creature friendly to the Horde cannot be killed by it, so its card can be won only by the Alliance, and the other way round. Until now the catalog held only creatures both factions can attack (neutral or hostile to both). Now:

- A creature friendly to the Horde and neutral or hostile to the Alliance (a Horde guard, an Orgrimmar-side soldier) is a card `faction: "alliance"`: the Alliance can win it.
- A creature friendly to the Alliance and not to the Horde is a card `faction: "horde"`.
- The two sides get **162 cards each**. The Alliance's candidates are all kept. The Horde had 286, so 124 are left out by a rule that does not depend on order (`tools/build-catalog.js`): every dungeon and raid creature stays, then every rare, elite and boss, then ordinary creatures spread over the places in proportion to what each has, first by SHA-256 of `faction-v1|<npc id>`.
- Capital cities are left out, as before. A creature friendly to both factions outside an instance (townsfolk, escorts, horses) has no card: nobody can kill it.

How it plays:

- **Earning is locked, trading is open.** The add-on treats the card of a creature the character's faction cannot win as unavailable: it is not a source, is not in the pack pool, cannot be crafted, and is not shown in the binder unless a copy is owned. A copy that arrives by trade or gift counts and shows.
- **Pages need only the cards both factions can win**, so both factions can finish every page. The faction cards are extras, always available, never held back for seasons, never required.
- **A season cannot name one.** The scheduler refuses it and a random pick never draws it.
- **The ledger knows each character's faction.** The add-on writes `mode/faction1` once, and `mode/side:alliance` or `mode/side:horde` for each character before its first roll, pack or craft of a card added in spec 10. The server refuses a faction card from a character that has not declared that faction, and checks a pack's cards against the opener's pool. The declaration is the player's own word, like every event (spec section 1).
- **Nothing before the markers changes.** The new cards (`since: 10`) do not exist for a binder until it records `faction1`, so every earlier history and pack replays exactly as it did.

The published spec-9 launch list is also preserved. `packages/shared/spec9-collection.json` is a frozen checkpoint from catalog `3d0b62359bee`, with the earlier seasonal flags and page requirements that changed. The catalog generator embeds these as `seasonalBeforeFaction` and `requiredBeforeFaction`; replay and server pack checks use them until `faction1`. After that marker, new finds use the current list. Do not rebuild this checkpoint from the new catalog: that would reinterpret existing drops, packs and completed pages. Regression fixtures contain actual outcomes from the published catalog, including Defias Miner changing from a launch card to a held-back card.

## 2. Every dungeon and raid creature has a card

41 creatures in dungeons and raids were missing because the data lists them as friendly:

- 5 are friendly to one faction only (a card for the other faction).
- 36 are friendly to both: scripted event creatures (the Blackrock Depths arena, the Zul'Farrak gauntlet, the Wailing Caverns event) and quest characters inside the instance. They get a card either faction can win.
- 13 of those cannot be killed at all (Naralex, Sah'rhee, Old Ironbark and similar story characters). They have a card that nobody can win, on `AzerothCardBinder/UnobtainableCards.lua`; see [UNOBTAINABLE-CARDS.md](UNOBTAINABLE-CARDS.md). They are "likely, check in game" like the other unconfirmed entries.
- A script object, "Idol Oven Fire Target", is not a monster and has no card.

Forever's 9 new dungeons and 2 new raids have no creature data on the fan site yet (only a name and a level range: Alcaz Prison, Blackmaw Hold, Drowned City, Hall of Thanes, Shaper's Terrace, Manor Mistmantle, Excavation Site: Wetlands, Krol'dok Stronghold, Half-Pint Tavern, Barrow Deeps, Hyjal Summit). They cannot have cards until the creature lists are known; run the routine below when the site has them.

## 3. One-off kills are not cards anyone can win

A creature that appears once, through a quest or an event, cannot be farmed. The test is the game database (cMaNGOS classic-db, the source the fan site is built from): **no spawn point**. Eight creatures have none: Nightlash, Verog the Dervish, Echeyakee, Galak Wrangler, Scout and Windchaser, Kolkar Stormseer and Kolkar Invader. They stay as cards that nobody can win (`UnobtainableCards.lua`, "one-off"), tradable if owned.

Slow respawn is **not** a reason: world bosses and rares that come back after more than a day (Lord Kazzak, Azuregos, Jade, the 36-hour elemental invaders; 39 creatures) stay in. Dungeon and raid bosses reset with the instance and stay in. The eight new Zephras Isle rares have no spawn data yet and are left alone.

## The numbers

| | Cards |
|---|---|
| Cards both factions can win (before) | 3,423 |
| + dungeon and raid creatures friendly to both | +36 |
| = both factions can win | 3,459 (1,729 at launch, 1,730 held back for seasons, 31 of them never winnable) |
| Only the Alliance can win | 162 |
| Only the Horde can win | 162 |
| **Catalog** | **3,783** base cards |

An Alliance character can win 3,459 - 31 + 162 = 3,590 of them (the 31 never-winnable cards are among the 3,459), and so can a Horde character.

## Rebuilding the creature list

The catalog is generated from the fan site's pages, which change as the beta is explored. To rebuild (this changes the catalog: review the diff, and expect a new `catalogVersion`):

```bash
node tools/fetch-zone-pages.js <folder>
node tools/fetch-reactions.js <folder> <reactions file>
node tools/build-catalog.js <folder> <folder>/zones-index.html <reactions file>
node tools/build-catalog-json.js
node tools/launch-collection.js --write
node tools/build-catalog-json.js
node tools/build-vectors.js
node tools/launch-collection.js --write
```

`build-catalog.js` prints how many cards each side has and how many were cut to match. After any rebuild run `node tools/release.js test` and read `docs/UNOBTAINABLE-CARDS.md` for the unkillable-creature scan: new creatures can need an entry on `UnobtainableCards.lua`. Changing which creatures are cards after a release changes what players can win: do it before launch, or announce it.
