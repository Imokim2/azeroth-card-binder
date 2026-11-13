# Release 0.7.0: add-on 0.7.0, companion 0.5.0, server 0.5.0 (group-test candidate)

**Status: prepared, not published.** Versions are bumped on `release/0.7.0-candidate`; nothing has been tagged, signed, built into an installer or deployed. This is a group-test candidate on the way to 1.0 (see [V1-RELEASE.md](V1-RELEASE.md)), not 1.0 itself.

## What it contains

| | |
|---|---|
| **Seasons** (Ollie, `feat/seasonal-binders`) | Seasonal collections alongside Ranked, reward packs and titles, the Seasons tab, trading from the player menu. Server migration `0014_seasons.sql`. Ledger protocol 7. |
| **Second set of drop rates** (`feat/drop-rates-v2`) | Critters four times as likely, other ordinary cards 20% more likely, limited chase cards unchanged. Marker `mode/chase2`. Protocol 8. |
| **Launch collection** (`feat/seasonal-availability`) | Half the cards held back for seasons; released for good by the first season that features them; pages finished by launch cards alone. Marker `mode/launch1`. Protocol 9. |
| **Admin panel** | Already live (it deployed earlier from `main`); not part of this release. |

Players keep everything: no reset, no removed card, and every earlier history replays as it always did. The new rules start at once-only markers the add-on writes before its first roll after upgrading (`chase1`, `chase2`, `launch1`, in that order).

## Who works with whom

| Server 0.5.0 with... | Companion 0.4.5 and older | Companion 0.5.0 |
|---|---|---|
| **Add-on 0.6.x** | Works as today. | Works; uploads say protocol 9, which the add-on's history does not need. |
| **Add-on 0.7.0** | **Refused** at upload (`client_too_old`): the companion cannot describe the new markers. The player must update the companion. | Works. |

An old server refuses a new companion (it does not know protocol 8 or 9), so **the server goes first** (step 3). Casual play uses the new rates too but is not checked. A player who does not run the companion sees only the launch cards until it syncs, because the release list reaches the add-on through `Data/Sync.lua`.

## Before anything ships: merge order

The branches are stacked; each pull request must merge after the one before it, and the full suites must pass on `main` after each.

1. `feat/seasonal-binders` (Ollie)
2. `feat/drop-rates-v2`
3. `feat/seasonal-availability`
4. `release/0.7.0-candidate` (this branch: version bumps, notes, this checklist)

Then on `main`: `node tools/release.js check`, `node tools/release.js test`, `cd server; npm test`, `cd app; npm run build; npm test`. All green is required to continue.

## Steps

1. **Back up.** `node tools/backup-db.js` for production (see `docs/runbooks/BACKUPS.md`). Keep your own saved-variables backup and one existing-collection account for the upgrade test.
2. **Staging database.** `cd server; npx wrangler d1 migrations apply DB --env staging --remote` (applies `0014_seasons.sql`; additive). It must be in place before the matching server code.
3. **Deploy the server to staging, then production**, with the *current* signed manifest still in place: `npx wrangler deploy --env staging`, then `node tools/smoke.js --env staging`. Production gets the migration and the deploy the same way after the staging checks below pass. The new server accepts old clients unchanged.
4. **Staging checks** (below), including scheduling a test season on staging that releases a few held-back cards (`node tools/seasons.js preview` then `schedule ... --env staging`; the season needs a start in the near future and `WARCARDS_ADMIN_TOKEN` plus, for Access, a service token, in the environment: never in a file).
5. **Build the candidate.** Tag `v0.7.0` and push it: the release workflow builds the add-on zip and the Windows installer (`World-of-Warcards-Setup-0.5.0.exe`) and publishes a GitHub release with `SHA256SUMS`. The packaged-startup gate (docs/PACKAGED-STARTUP.md) must pass before the installer is published.
6. **Sign** (maintainer's computer; the release key never goes anywhere else): download the two files once, then
   `node tools/release-manifest.js sign --key <keyfile> --app <installer> --app-url <address> --addon dist/AzerothCardBinder-0.7.0.zip --addon-url <address> --app-notes "..." --addon-notes "..."` and `node tools/release-manifest.js verify`. Set `LATEST_APP = "0.5.0"` and `LATEST_ADDON = "0.7.0"` in `server/wrangler.toml` (both environments).
7. **Deploy the signed manifest**: staging, `node tools/smoke.js --env staging --deep`, then production and `node tools/smoke.js --deep`. Players are offered the update from here on.
8. **Do not raise the minimums yet.** After about a week raise `MIN_CLIENT` to `0.5.0` and `MIN_ADDON` to `0.7.0` and deploy (`docs/runbooks/RELEASES.md`, "Raising the minimum").

## Staging checks

Use two Ranked accounts (one fresh, one with an existing collection) and one Casual.

- **Upgrade keeps everything.** Cards, shiny cards, editions, packs, dust, titles and history are unchanged after installing the companion then the add-on. The saved file's ledger gains `chase1` (if absent), `chase2`, `launch1`, in that order, once.
- **Sync.** The companion uploads at protocol 9; the server accepts; the ladder and standings still refresh. An old companion (0.4.5) with the new add-on shows "The server refused it (client_too_old)".
- **Rates.** `node tools/report-drop-balance.js` shows critters at about 450 expected attempts; `/acb diag` in game shows the new first-attempt chances; a critter's guarantee arrives far sooner than before. Casual and Ranked use the same rates.
- **Launch collection.** A held-back creature (see `docs/seasons/launch-collection-draft.csv`) gives no card and no attempt; a launch creature does. A fresh binder shows launch cards only; an existing binder that owns a held-back card still shows it. Packs never contain a held-back card. Every page can be finished from its launch cards. Look at the sparse leveling-zone pages (for example Teldrassil, Ashenvale) in game.
- **A season releases cards.** Schedule a staging season featuring two held-back cards. After it starts and the companion syncs (`Data/Sync.lua` has `seasonal.released`), `/reload`: those cards drop, appear in packs and can be crafted; after the season ends they still do. Cards that were not featured stay held back.
- **Seasons.** Completion, titles and pack rewards work as in Ollie's notes (`docs/SEASONS.md`, "Release and group test"); claiming twice gives nothing extra.
- **Trading.** Trades and gifts of a held-back card someone already owns still work; the other player's binder view shows it.
- **Admin panel** still loads behind Cloudflare Access and its player page shows binders (it does not know about the new markers; nothing changes there).
- `node tools/smoke.js --env staging` passes.

## If something goes wrong

- **Server bug after deploy:** `npx wrangler rollback --env production`. Migration `0014` is additive and stays. While the old server is live, a new companion's uploads are refused (it does not know protocols 8 and 9); nothing is lost: saves are intact on each player's computer and sync when the server is fixed. Old clients are unaffected.
- **Bad add-on or companion build:** publish a fixed version with a higher number (versions only go up); players can restore the add-on from `addon-backups` in the companion's data folder. Do not raise the minimums to a bad build.
- **A wrong card list or rate:** fix the generator or `DropRates.lua` and ship a new build; the markers and `rate2`/`seasonal` data are versioned by the catalog, and earlier histories are not affected. A rate change after players have recorded `chase2` needs a new marker (see `docs/adr/0011-second-generation-drop-rates.md`).
- **A season released the wrong cards:** seasons cannot be edited once scheduled; schedule a corrected one. A release cannot be undone (released cards stay available for good).

## What preparing it did not do

It did not tag, build the installer, sign the manifest (that needs the release key), deploy, or touch production. The add-on zip builds locally with `node tools/release.js build`.
