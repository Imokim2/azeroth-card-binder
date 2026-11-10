# Changelog

Notable changes, newest first. Versions follow [semantic versioning](https://semver.org): a new feature raises the middle number, a fix the last one. Read the entry for any version you upgrade across.

## Unreleased

- The binder keeps a tamper-evident ledger of every card found, crafted, recycled and traded, and checks it each time you log in. If a card count is edited by hand, the Settings tab and `/acb verify` say "Binder unverified". Nothing about playing changes. Saved data moves to version 2 on first load; cards, dust, titles and trade history are kept.
- Every roll is now counted, kept apart from the bad-luck counter, and the add-on remembers recently rolled corpses across a reload so the same corpse cannot be rolled twice.

- Engineering foundations (Phase 0 of the [roadmap](docs/ROADMAP.md)): repository layout, continuous integration, the written ledger specification with shared test vectors, contributing guide, decision records, and a release script. Nothing changes for players.

## 0.2.9

- Achievement tracks for cards collected, sets completed, cards traded and shiny cards, each earning a title; loot and binder-sharing fixes; drop rates of 1% for normal creatures and gathering nodes, 2% for elites and 10% for rares (the guarantee now lands on the 100th attempt for a normal card).
- Binder Dust: recycle a spare copy into dust and craft a missing card with it.
- A Settings tab for pop-ups, hints, privacy, diagnostics and the title shown beside your name.
- "Kills since last drop" on every card page.
- Cards fall back to the Dungeon Journal picture, a loading screen, or the zone map when there is no packaged painting.
- The add-on is now called World of Warcards. The folder and saved-data names are unchanged, so existing binders carry over.

## 0.2.x

- The catalog covers neutral and hostile Forever creatures and gathering nodes (about 3,375 cards), with lore for every card.
- Rarity-coloured corner studs, serial numbers and sets listed in level order; card names centred.
- Pop-ups with sounds, shiny cards, a bad-luck safety net, hints on tooltips, set rewards and titles, a wanted list, card links in chat, binder viewing and a trade window.
