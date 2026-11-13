# Seasonal collections

Seasons run alongside a clean Ranked binder. There is no separate character reset or inventory. Each scheduled season has one shared list of exact card versions, a start, an end, rewards for everyone who finishes, and an optional extra reward for the first N finishers.

An existing copy does not tick a seasonal slot. A new verified drop, pack pull or incoming trade during the window does. The normal binder keeps that copy too. Crafting and Casual play do not count. Once verified, a seasonal slot stays ticked if the player later trades that copy away. Alternate collectible versions are separate goals when explicitly selected; random selection uses base cards.

The **Seasons** tab shows four previews per page, the deadline, confirmed progress, pending local gains and rewards. Selecting a preview shows the existing full card presentation. **Open in binder** returns to the ordinary collection; **Claim packs** adds earned packs to the ordinary satchel. Titles appear with the other achievement titles and use the existing addon tooltip system.

Seasons occupies the old Trade tab position. New trades and gifts start from the player's right-click menu; incoming invitations and the active card/pack picker retain their existing acceptance flow.

## A smaller launch collection

Card retirement is a separate catalog change, not part of scheduling a checklist. Keep stable card/edition IDs and definitions for any card already collected: hiding an inactive, unowned card or disabling its live drop source must never erase an owned copy, its variants, ledger history or trades. A returning card must keep that identity and still need a fresh acquisition to count in its season. Do not remove arbitrary definitions or rebalance history to shrink the launch collection.

The retirement list and whether a returning card stays available after its season still need to be agreed. This change retires no cards and does not yet switch their availability through season scheduling. That availability policy must be enforced consistently by the addon and server when the actual catalog reduction is prepared.

## Held-back cards and releasing them

The launch collection is half the cards (`docs/proposals/SMALLER-LAUNCH-COLLECTION.md`). The other half is **held back**: marked `seasonal` in the catalog from `AzerothCardBinder/LaunchCollection.lua`, not dropped, not in packs, not crafted and not shown in a binder that does not own one. **Scheduling a season that features a held-back card releases it: from the season's start the card is available to everyone, and it stays available after the season ends.** A season therefore gives early access and rewards to the players who collect it during the window. Pages are finished by their launch cards alone; released season cards are extras.

The server enforces this once a binder has recorded `mode/launch1` (ledger spec 9): see [the ledger spec](LEDGER-SPEC.md), "Launch collection". The add-on knows which cards are released from `sync.seasonal.released`, which the companion writes from the seasons sync, so a player who does not run the companion sees only the launch cards until they do.

## Timing and fairness

Both the event time and the server's receipt must fall in `[start, end)`. Players must log out or `/reload` to save and sync before the deadline. An offline or late upload still preserves normal cards, but does not qualify for the ended season. The client clock alone never decides a win.

Places mean **order of server-verified completion**, not an unverifiable in-game kill time. Trades need both halves and the existing Ranked provenance checks; the hourly trade job can confirm them after the deadline if the incoming acquisition was received in time. Pending trades can therefore finish later than immediately verifiable drops. Open integrity flags hold progress for review. This uses the existing addon's trust model; an addon cannot prove actual gameplay independently of the game server.

Rewards are account-wide, once per season. Each pack has a server-owned grant id. Claiming appends a `seasonReward` event; upload validates its owner and pack and redeems it in the same transaction as inventory. Repeated syncs and claims cannot multiply it. Starting another binder does not award the same reward again. Updates never clear normal progress. Recovery refuses to discard claimed rewards or seasonal titles.

## Prepare a season

`docs/seasons/example.json` is an **inactive example**, not a scheduled season. Copy it to a local draft and fill in `startsAt` and `endsAt` as UTC ISO dates, such as `2027-01-01T18:00:00Z`. Windows can display local time differently; the saved timestamps are UTC. A season can last up to 90 days and include up to 64 cards.

For manual selection use `"selection": { "mode": "manual", "cards": ["npc:589", "npc:594"] }`. For random selection choose the eligible set codes, optional rarities/boss filter, number of cards and a seed. Change the seed to preview a different list. The final list is stored once when scheduled; catalog changes and client reloads cannot reroll it.

Run `node tools/seasons.js preview path/to/draft.json` to see card names and rewards locally. When the dates and rewards are agreed, set the admin credentials in the environment and run `node tools/seasons.js schedule path/to/draft.json --env staging`. Use `--env production` only for an agreed live schedule. Cloudflare Access protection still applies; the tool accepts existing service credentials from environment variables when configured. No tokens belong in the draft or repository.

`GET /v1/admin/seasons` lists scheduled seasons; `POST` schedules one behind the existing admin and Access checks. Scheduling refuses duplicate ids and cards, invalid dates, unknown cards/packs and a preview that differs from the server catalog. Scheduled definitions are immutable: draft and test first. No season is seeded by the migration or enabled by installing the addon.

## Release and group test

Deploy migration `0014_seasons.sql` before the matching server code. The addon, server and companion changes must ship together once for this feature: the companion carries bounded seasonal data through Sync.lua; protocol 7 adds reward events while old uploads remain accepted. The public downloads stay on their current working versions until a new release is built and signed. Later seasons need server-side scheduling only, within these supported rules.

Test with two Ranked accounts: an old owned copy, a fresh duplicate, a pack pull, a normal trade/gift, rejected and unmatched trades, completion and bonus places, repeated claims/reloads, and an ended season. Verify normal inventory and satchel counts after logout, restart and update. Run the packaged-app startup gate before publishing a companion. In-game layout and model checks remain part of group testing.
