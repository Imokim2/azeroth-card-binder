# Changelog

Notable changes, newest first. Versions follow [semantic versioning](https://semver.org): a new feature raises the middle number, a fix the last one. Read the entry for any version you upgrade across.

## Unreleased

- Companion app core: the sync engine joins everything into one loop (upload, roll tape, standings, `Data/Sync.lua`) that runs whenever the game finishes writing its saved file. Still no window around it.
- Server: a flag review API (clear, confirm, ban) behind an admin token, luck that a reviewer has cleared is not flagged again, and a rebuild job that recomputes everything derived from the stored batches (a page of players at a time, with a dry run).

- **Ladder tab** in the binder: the top of the Ranked ladder, where you stand, and who finished each set first, with a "(verified)" mark beside ranked players in the trade window and the binder view. The standings come from the companion app, so they need the app and a reload; without it the tab says so.
- Server: trade matching (the two halves of a trade are paired; a half nobody confirms within a week is flagged and stops counting), the firsts feed (`GET /v1/firsts`) and the ranked players' characters on the leaderboard.

- **The zone card bar is now green and takes the reputation bar's place** (the bar above the experience bar), in the same green, instead of the honour bar. It hands the reputation bar back when switched off.
- **Trading works with any card**, not just duplicates, including a last copy. Trade panel text says when an offer is your only copy. The shared rules and test vectors allow a trade out of a last copy.
- **Viewing other players' binders** now explains itself: you are told when the request was sent, when someone keeps their binder private, when nothing comes back, and when only part arrives. Binder parts go out at a pace the game accepts and a refused part is sent again. Before, a binder of more than about ten messages could be cut short without any sign.

- **Zone card bar.** A thin bar takes the honour bar's place above the experience bar (or sits above the experience bar if there is no honour bar) and shows how many cards you own in the zone, dungeon, raid or battleground you are in, and changes by itself as you travel. Hover for the detail and click to open the binder; Shift-drag moves it. Turn it off in Settings or with `/acb bar` and the honour bar returns; `/acb bar reset` clears a dragged position; `/acb bar debug` says which bars it found.

- **Stacking drop chance.** Every miss now raises a card's chance for the next attempt by its listed rate (a 1% card goes 1%, 2%, 3% and so on, up to certain), and a drop starts it over. This replaces the old bad-luck guarantee and makes cards drop far more often: a 1% card now takes about 13 kills on average instead of about 63. The step is one setting (`ACB.stackFactor` in `Catalog.lua`) if it proves too generous.
- Card names are never cut off with "..." any more: the text shrinks to fit the card, the binder grid and the card page, and breaks onto two lines only for the very longest names.
- Zephras Isle, the Skyborne starting zone, is in the binder with its eight rare creatures. Its ordinary creatures follow when their ids are published.

- The binder keeps a tamper-evident ledger of every card found, crafted, recycled and traded, and checks it each time you log in. If a card count is edited by hand, the Settings tab and `/acb verify` say "Binder unverified". Nothing about playing changes. Saved data moves to version 2 on first load; cards, dust, titles and trade history are kept.
- Ranked mode (needs the companion app): `/acb mode ranked` or the Settings button. Ranked rolls use random numbers the server issues, so every drop can be rechecked. If the supply runs out, Ranked rolling pauses with a message until the app refills it; `/acb mode casual` returns to normal play. Binders that hold cards from before the ledger cannot enter Ranked yet.
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
