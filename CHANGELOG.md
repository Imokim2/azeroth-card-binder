# Changelog

Notable changes, newest first. Versions follow [semantic versioning](https://semver.org): a new feature raises the middle number, a fix the last one. Read the entry for any version you upgrade across.

## Unreleased

- **Ranked now checks every attempt, not just totals.** Ledger specification version 2. In Ranked the add-on writes every attempt into the ledger, as a drop or as a short run of misses on one card (a new `miss` event), and the server replays each one against its own roll tape. A drop cannot be invented, and one cannot be left out by recording it as a miss, because the entry decides. Entering Ranked writes a `ranked2` mode event and starts every card's stack of misses from zero. The old totals check is gone. The roll tape is now handed out in batches of 1,000 (topped up when 250 or fewer remain) instead of 10,000, so a player can read far less of it ahead of time; heavy players may need to `/reload` about once an hour to let the companion app top it up. Uploads in version 1 are no longer accepted: update the companion app and the add-on together. Binders already in Ranked switch over automatically the next time the add-on loads. The ledger grows (up to one event per attempt on a different card), so uploads are bigger.
- **Wanted tab.** The cards players are looking for, in one place: the tab lists your own wanted cards (click to remove, or add one by name) and what other players are looking for, with the players who want a card you have spare at the top and marked. Click a name to offer a trade. The list comes from the public board, which the companion app uploads and brings back (public players only; so it is as fresh as the last sync and your last reload), and from **Check my target**, which asks the player you target and shows their answer at once (they need the add-on and to allow viewing). The binder view of another player now shows what they are looking for too. Server: `POST /v1/wanted`, `GET /v1/wanted` and a `/wanted` page.
- **Trading between players:** the binder view of another player now lists the spares they have that you need and the spares you have that they need (cards on your wanted list first), with an **Offer a trade** button. `/acb ask <player> <card>` (or `/acb ask target <card>`, or **Ask target** on a missing card's page) tells a player you are looking for a card; they see it only if they own it, with a link and how to start a swap. **Trading distance:** like the game's own trading, a trade now needs your partner targeted and within about 11 yards (a **My target** button on the Trade tab fills the name in); switch it off in Settings. The distance is a nicety of play, not a safeguard: the server checks every trade regardless.
- Server: when a trade half is never matched and the partner has uploaded since, the partner is flagged (`trade-half-missing`) instead of the player they took the card from.

- **Website pages**, served by the server: the ladder and first-to-finish list, a player's page with a read-only view of their binder, fair play and privacy. Plain, safe HTML with no scripts or game art.
- **Windows installer** for the companion app (`npm run dist` in `app/`). Unsigned, so Windows will show an "unknown publisher" warning.
- Cards that came from Casual play are now followed through any number of trades, not just the first.

- Server hardening: per-address rate limits (a general one and a strict one for registration, reset, deletion and admin routes), and a data-deletion route with a **Delete my data…** button in the companion app. Deleting erases the player's record and archived binders; a banned player's record is kept.

- **Start a new binder.** `/acb newbinder` (then `/acb newbinder confirm`) erases the binder on that account, keeps a copy of the old collection in the saved file and starts an empty one. The companion app notices that the saved data is not the binder the server holds and offers to start a new binder on the server, which archives the old record and gives the new one a fresh roll tape. Needed to join the Ranked ladder from a binder that already has Casual drops. Once a day at most.

- **Only Ranked counts for the ladder.** A drop rolled in Casual mode cannot be checked by the server, so a player with any Casual drop is no longer listed on the ladder or in the firsts feed, and cards traded in from such a player stop counting for the receiver. The Ladder tab says plainly why a binder cannot join, and `/acb mode casual` warns before you leave Ranked. To join the ladder, switch to Ranked before your first drop.

- Companion app window: an Electron window and tray icon with the three steps (sign in with Discord, choose the game folder, watch the sync). The key is kept encrypted by Windows. Run it with `npm start` in `app/`; there is no installer yet.

- Discord sign-in for the companion app and server: the player signs in with Discord in their own browser; the app never sees a Discord password or secret, and the server keeps only the Discord id. Registration opens once the Discord application's secret is set on the server.

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
