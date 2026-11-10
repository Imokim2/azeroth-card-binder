# World of Warcards: global collectathon roadmap

Goal: a competitive, global collection race for World of Warcraft: Forever, with a companion desktop app (in the style of TradeSkillMaster's app) that syncs every player's binder to a server, ranks them, and keeps the race honest for the long run.

This is a working plan. Task IDs (A1, B3, ...) are meant to be turned into issues. Sizes are rough estimates in working days for one developer and assume nothing about hours per week.

## 0. What this can and cannot promise

- A WoW add-on runs on the player's computer and its saved data is an editable text file. The server never sees the game, only what the client says. So **cheating cannot be made impossible, only bounded, visible and not worth it**.
- The design therefore rests on five things: an append-only history the player cannot rewrite after upload, server-issued random numbers for ranked play, statistical checks on results, evidence from top players, and seasons with human review before any prize.
- The cost of a cheater is limited by rate limits. Even a cheater who skips unlucky rolls is capped at how many kills a human could plausibly make per hour.
- If any of this is wrong about Forever (rules, file locations, APIs), Section 1 lists what must be checked before building.

## 1. Decisions and checks to settle first

| # | Decision or check | Recommended answer | Needed before |
|---|---|---|---|
| D1 | Does Forever's add-on policy allow an external app that reads and writes add-on data files? | Check the official policy and ask in the Forever community. TSM does this on retail, but Forever is separate. | B1 |
| D2 | Does Forever expose any character API (for example kill statistics)? | Research. If yes, use it as a cross-check in Phase D. | D1 |
| D3 | Is this noncommercial? The data and art sources allow noncommercial fan use only. | Yes: no paid features, no ads, prizes non-monetary (titles, hall of fame, cosmetic card backs). Donations only if the source terms allow it. | B1 |
| D4 | Licence for this repository. CatalogForever.lua is derived from cMaNGOS classic-db data (GPL-3.0). | Choose a licence compatible with GPL-3.0 and say so in CREDITS.md. Not legal advice; confirm. | Public launch |
| D5 | Two modes: **Casual** (local random numbers, no ranking) and **Ranked** (server-issued random numbers, counts for the ladder). | Yes. Ranked is opt-in and requires the companion app. | A5, C1 |
| D6 | Season length. | 90 days, ladder resets, hall of fame and all-time collection never reset. | D5 |
| D7 | Score formula. | Starting weights: common 1, rare 2, epic 5, legendary 10 per unique card; shiny adds half again; set completion adds 10% of the set's points. Tune in beta. | C3 |
| D8 | Hosting. | Cloudflare Workers plus D1 (free plan to build, $5 per month paid plan to launch). | B2 |
| D9 | App stack. | Electron, Windows first. | B5 |
| D10 | Is one binder per WoW account correct? SavedVariables here are per account. | Yes. Events record the character name and realm. | A2 |

## 2. Architecture

```
Add-on -> SavedVariables file -> Companion app -> Worker API -> D1 + file storage -> Website
   ^                                   |
   '-- Data/Sync.lua (tape, acks, leaderboards) <-- written by the app
```

Rules that never change:
1. **Card keys are permanent.** `npc:<id>` and `node:<id>` are never reused or renamed. Retired cards stay in the catalog, flagged.
2. **Everything is versioned**: saved-data `schema`, API `/v1`, `catalogVersion`, add-on version. The server states the minimum client version it accepts.
3. **The ledger is append-only**: events are never edited, only added.
4. **The server is the only source of rankings.** The in-game leaderboard is a copy, not a source.
5. **The ledger is the source of truth; everything else is a projection.** Scores, ranks, snapshots and flags are all derived from stored ledgers and can be rebuilt from scratch. A scoring bug is fixed by changing the code and recomputing, never by editing data.
6. **One written spec, three implementations.** The ledger format, hashing and signing are defined once in `docs/LEDGER-SPEC.md` with shared test vectors. The Lua add-on, the server and the app must all pass the same vectors (see Section 9).
7. **Every table is keyed by player.** Identifiers are random (ULID), never auto-incrementing, so data can be split across databases later without rewriting anything (see Section 10).

### 2.1 Saved-data additions (schema 2)

```
saved.schema = 2
saved.player  = { guid, linkCode, key }        -- key is the app's public key, written by the app
saved.attempts[cardKey] = lifetime attempts    -- every roll, win or miss
saved.rolledGuids = ring buffer of 2000        -- stops re-rolling the same corpse after a reload
saved.ledger  = array of events
saved.head    = { seq, hash }                  -- last event; kept after pruning
saved.mode    = "casual" | "ranked"
saved.tape    = { index }                      -- next unused random number (ranked)
```

Ledger event (one table per event, hashed with the previous one). The exact rules are in [LEDGER-SPEC.md](LEDGER-SPEC.md):

```
{ seq, t, kind, key, count, dust, shiny, tape, partner, trade, char, prev, h }
kind: drop | craft | recycle | tradeIn | tradeOut | set | mode
h = first 32 hex characters of SHA-256( seq|t|kind|key|count|dust|shiny|tape|partner|trade|char|prev )
```

Misses are not events. They are counted in `attempts`, and in ranked mode each roll consumes one tape entry, so the server can check attempts against `tape` indexes.

### 2.2 Upload (app to server)

`POST /v1/ledger` with `{ key, character, realm, schema, catalogVersion, events[], snapshot{ counts, attempts, dust, sets, titles }, tapeIndex, sig }` where `sig` is an Ed25519 signature of the canonical JSON.

The server:
1. checks the signature against the registered key;
2. checks `events[0].seq` equals stored `head.seq + 1` and recomputes every hash;
3. checks card keys, counts and rates against its own copy of the catalog;
4. checks plausibility (Section 5) and stores the batch;
5. replies `{ ackSeq, minClient, tape?, syncVersion }`.

### 2.3 Database (D1)

```
players(id, discordId, createdAt, status)
keys(playerId, publicKey, status, createdAt)
characters(playerId, name, realm, firstSeen)
batches(playerId, firstSeq, lastSeq, blobRef, receivedAt)   -- compressed events, one row per upload
drops(playerId, seq, cardKey, t, shiny, tapeIdx)            -- indexed, small
snapshots(playerId, at, uniqueCards, setsDone, score, attemptsTotal)
tapes(playerId, startIdx, endIdx, seedHash, issuedAt)
trades(tradeId, aPlayer, bPlayer, aCard, bCard, aSeen, bSeen, state)
flags(playerId, kind, score, state, notes, createdAt)       -- state: open, cleared, confirmed
seasons(id, startsAt, endsAt, rulesVersion)
```

Keep rows few: whole upload batches are stored as one compressed blob, and only drops and snapshots are rows. This keeps database writes (and the bill) small.

### 2.4 In-game data file

`AzerothCardBinder/Data/Sync.lua`, written by the app, loaded by the add-on on reload:

```
ACB.sync = { syncVersion, ackSeq, tape = { "<hex>", ... 10000 entries }, tapeStart,
             season = { id, endsAt }, leaderboard = { top 100 }, you = { rank, score },
             verified = { <names> }, minClient }
```

The game reads it only at login or `/reload`, so in-game rankings are as fresh as the last reload.

### 2.5 Ranked random numbers (the roll tape)

- The server issues a tape: 10,000 random 64-bit values per refill, stored as a hash commitment on the server.
- In ranked mode, roll *n* uses tape entry *n*, in order. A drop requires `entry mod 10000 + 1 <= rate` (or the bad-luck guarantee). Each drop event records its tape index.
- The server knows every tape value, so it can check each recorded drop against its entry and check the pity counter.
- A player who modifies the add-on can still read ahead and skip unlucky entries, but skipped entries must still be explained by attempts, and attempts are rate-limited. Their advantage is bounded, not zero. This is stated openly on the fair-play page.

## 3. Phases

### Phase 0: engineering foundations (before anything else). Done on 2026-11-10, apart from the follow-ups below.

These make every later phase cheaper. Skipping them is how projects like this become unmaintainable.

- [x] **G1. Repository layout.** `AzerothCardBinder/` stays at the root (it is the folder players install, and the tools point at it). `server/`, `app/`, `packages/shared/` and `docs/` sit beside it, each with a README. `README.md`, `.gitignore` and `.gitattributes` added. See Section 9.
- [x] **G2. CI on every pull request** (`.github/workflows/ci.yml`): `node tools/release.js build`, which syntax-checks every Lua, JavaScript and JSON file, checks that the `.toc` lists every add-on file, runs the Lua tests and the shared-contract tests, and builds the install ZIP. A monthly Dependabot update keeps the workflow's actions current. **Not yet run on GitHub**; the first run on a pull request is the real test.
- [ ] **G2b. Linters.** luacheck and StyLua were left out on purpose (see [ADR 0006](adr/0006-ci-checks-in-phase-0.md)). Add them with a baseline: record the current warnings, fail only on new ones, and do the one-time formatting pass in its own commit.
- [x] **G3. `docs/LEDGER-SPEC.md` and test vectors** in `packages/shared/vectors/`: SHA-256 vectors, a valid ledger covering every kind of event, ten kinds of invalid ledger, canonical JSON, a signed batch with a published test key, and ranked tape values, as JSON and as a Lua table. The JavaScript reference implementation is `packages/shared/src/ledger.js`; `node --test tests/vectors.test.js` checks it against the vectors and the vectors against the generator (`tools/build-vectors.js`). The spec added a `dust` field to the hashed event text.
- [x] **G4. Split the big Lua files.** `Forever.lua` 494 to 376 lines (saved-data cleanup in `SavedData.lua`, slash commands in `Slash.lua`); `Cards.lua` 672 to 407 (`CardModels.lua`, `CardArt.lua`); `Folio.lua` 544 to 322 (`FolioUi.lua`, `FolioIndex.lua`); `Binder.lua` 453 to 332 (`UiKit.lua`, `SettingsView.lua`). Behaviour is unchanged (all earlier tests still pass). A test now fails if any add-on code file passes 450 lines.
- [ ] **G4b. Split `tests/run.lua`** (about 1,900 lines) into one file per area, loaded by a small runner. It is exempt from the size rule until then.
- [x] **G5. `CONTRIBUTING.md`, PR template and ADR folder** (`docs/adr/`), with six decision records: the ledger rule, Casual and Ranked modes, hosting, the app stack, keeping internal names, and the Phase 0 CI scope. `docs/runbooks/` holds the list of runbooks still to write.
- [x] **G6. Release script** (`tools/release.js`): `check`, `test`, `build` (ZIP into `dist/`, developer notes left out) and `bump <version>` (updates the `.toc` and `CHANGELOG.md`). `CHANGELOG.md` started.

Done when: a new contributor can clone the repo, run the tests and build a release from the README alone, and CI blocks a broken change. The README part is true now. The "CI blocks a broken change" part needs the first pull request, plus branch protection on `main` requiring the CI check, to be true.

### Phase A: add-on foundation (no server). About 5 to 8 days.

- [x] **A1. SHA-256 in pure Lua** (`AzerothCardBinder/Hash.lua`) using the `bit` library WoW provides, with two-argument calls only. It passes all ten shared vectors under LuaJIT. Not yet run inside the game.
- [x] **A2. Saved-data schema 2** with a migration from the current format (`SavedData.lua`). The test loads `tests/fixtures/saved-v1.lua`, a hand-written stand-in shaped like a version 1 file, not a copy of a real one. Still to do: add a real player's file as a second fixture.
- [x] **A3. Attempts counters**: `saved.attempts[key]` incremented on every roll in `Collection.lua`. Keep `misses` (pity) separate.
- [x] **A4. Persistent roll memory**: `saved.rolledGuids` so the same corpse cannot be re-rolled after a reload.
- [x] **A5. Ledger and hash chain** in a new `Ledger.lua`. Every drop, craft, recycle and trade appends an event. Verify the chain on load; if it fails, set `saved.mode = "casual"` and show "binder unverified" on the Settings tab.
- [ ] **A6. Ledger pruning** after the app acknowledges (`ackSeq` from `Sync.lua`), keeping `head`. Until it ships the ledger only grows, at about 250 bytes an event, and a player who never installs the app never prunes it. Measured on a desktop with LuaJIT's JIT switched off (the game's own Lua may be slower), 5,000 events take about 0.4 s to verify at login and about 0.15 ms each to write. Decide a cap for never-synced binders when this item is built.
- [ ] **A7. Settings tab**: status line done ("Binder verified: N changes on record" or "Binder unverified: reason"). The mode switch and the link code wait for Phase C and B7, because Ranked cannot do anything before the tape exists; "Last synced" waits for `Sync.lua`.
- [x] **A8. `/acb verify`** prints the chain status and counts to chat.
- [x] **A9. Trade receipts**: each trade carries a shared trade id and both partners record `tradeIn` / `tradeOut` with the partner name.
- [x] **A10. Tests** for all of the above in `tests/run.lua`, including a tampered ledger and a migrated file.

Done when: all tests pass; editing any count by hand marks the binder unverified; reloading mid-loot cannot re-roll; in-game check passes (Section 6).

### Phase B: server, companion app (read-only) and website. About 15 to 22 days.

- [ ] **B1. Policy and licence checks** (D1, D3, D4) written up in `docs/POLICY.md`.
- [ ] **B2. Cloudflare account, staging and production environments**, D1 databases, migrations folder, secrets.
- [ ] **B3. Worker API** (`server/`): `POST /v1/ledger`, `POST /v1/register`, `GET /v1/player/:id`, `GET /v1/leaderboard`, `GET /v1/health`. Request signing and hash-chain verification as in 2.2. Unit tests with recorded ledgers.
- [ ] **B4. Shared catalog**: a build script turns the Lua catalog into `catalog.json` (keys, names, rarity, rate, set), used by the server and website. Version it.
- [ ] **B5. Companion app skeleton** (`app/`, Electron): finds the WoW folder, lets the player pick the account, shows status.
- [ ] **B6. Lua parser and file watcher**: reads `AzerothCardBinder.lua` from SavedVariables, debounced, only uploads new events.
- [ ] **B7. Identity**: the app creates an Ed25519 key, stores the private key in the OS keychain, registers it with Discord login, and binds to the character through the in-game link code (`/acb link CODE`).
- [ ] **B8. Website**: leaderboard, profile with a read-only binder view, fair-play rules, privacy page, report button.
- [ ] **B9. CI** (GitHub Actions): Lua tests, server tests, app build, deploy to staging.
- [ ] **B10. Auto-update** for the app through GitHub Releases, plus the installer.
- [ ] **B11. Storage behind interfaces.** The Worker talks to `IngestStore`, `PlayerStore` and `LeaderboardStore` interfaces, not to D1 directly, so the database can be sharded or replaced without touching the rules.
- [ ] **B12. Idempotent, retry-safe uploads.** Uploading the same batch twice has the same result as once (keyed by player and `seq`). The app retries with backoff and keeps a local queue if the server is down.
- [ ] **B13. Migrations folder and rules.** Forward-only SQL migrations in `server/migrations/`, each tested against a copy of staging data; changes use expand then contract (add the new column, deploy, backfill, switch, remove later).
- [ ] **B14. Structured logging, error code catalogue and a `/v1/health` endpoint** that checks the database, so alerts and runbooks have something exact to point at.
- [ ] **B15. Static, cached public pages.** Leaderboard and profile pages are served from precomputed files cached for about 60 seconds, never computed per visit.

Done when: a test player installs the app, links a binder, plays, and appears on the staging leaderboard within a minute of reloading; a tampered file is rejected by the server.

### Phase C: ranked mode and in-game features. About 10 to 15 days.

- [ ] **C1. Tape issuing** on the server (`tapes` table) and `/v1/tape`; app writes it into `Data/Sync.lua`.
- [ ] **C2. Ranked rolls** in `Collection.lua`: consume tape entries in order; "Ranked rolls paused: refill the tape" message if exhausted; fall back to casual rolls clearly labelled and not ranked.
- [ ] **C3. Score and rank** computed on the server per D7; written back to `Sync.lua`.
- [ ] **C4. In-game leaderboard tab** (top 100 plus your rank), "verified" badge beside ranked players in inspect and trade.
- [ ] **C5. Trade matching** on the server: pair `tradeOut` with `tradeIn`; unmatched trades after 7 days are excluded from score and flagged.
- [ ] **C6. Firsts feed** ("first to complete Blackrock Depths") on the website and in `Sync.lua`.
- [ ] **C7. Tests**: server verifies a tape-based ledger; add-on rejects a tape out of order.

Done when: a ranked player's every drop is reproducible from the tape on the server; a modified drop is rejected.

### Phase D: integrity and seasons. About 10 to 15 days.

- [ ] **D1. Luck score**: for each player, the probability of seeing at least their number of drops given their attempts and the rates. Score = -log10(p). Review at 4, auto-hold from the ladder at 6.
- [ ] **D2. Rate limits**: at most 1,200 attempts per hour sustained and per-day caps, derived from the fastest plausible farming; timestamps from upload time, not the client.
- [ ] **D3. Duplicate-kill check**: the same kill id can be claimed once per player.
- [ ] **D4. Flag queue**: admin page to review, clear or confirm; flagged players hidden from ranks, not deleted.
- [ ] **D5. Evidence upload**: players who reach the top ranks, or complete a set first, must upload their combat log (file storage). A reviewer checks it against the claimed kills.
- [ ] **D6. Seasons**: automatic rollover, hall of fame, final standings frozen and signed.
- [ ] **D7. Appeals and bans** procedure in `docs/MODERATION.md`.
- [ ] **D8. Rebuild job.** A command that deletes all derived data (snapshots, scores, ranks, flags' scores) and recomputes it from stored ledgers, tested against staging. This is what makes scoring fixes and rule changes safe.
- [ ] **D9. Rules versioning.** Score formula and plausibility thresholds live in one versioned config (`rulesVersion`). Changing them creates a new version and a recompute, and old seasons keep the rules they were played under.

Done when: a simulated cheater (edited counts, skipped tape entries, replayed batches) is caught by tests; a real review of one flagged and one clean player has been done by a person.

### Phase E: beta and launch. About 10 to 20 days elapsed, mostly waiting.

- [ ] **E1. Closed beta**, 20 to 50 players for two weeks. Collect: upload failures, parse failures, in-game errors, leaderboard disputes.
- [ ] **E2. Load test**: replay 5,000 simulated players' batches against staging; check the database write count against the plan limit.
- [ ] **E3. Launch checklist** (below), then a public beta labelled as such for one season before prizes.
- [ ] **E4. Announce** with the fair-play page and the honest limits from Section 0.

Launch checklist: policy checks done; privacy page live; data-deletion route works; backups restore tested; monitoring and alert to a Discord webhook; app installs on a clean Windows machine; paid Cloudflare plan on; minimum client version enforced; moderation rota agreed.

### Phase F: long-run operations (never finished)

- **Game patches.** When Forever patches: re-run the catalog pipeline (`fetch-reactions`, `build-catalog`, `build-nodes`), review the diff report, ship a new `catalogVersion`. New cards never change old scores; score changes need a `rulesVersion` bump and a recompute.
- **Releases.** Increase the add-on, app and API versions together; keep a compatibility table; the server rejects clients below `minClient` with a plain message.
- **Backups.** Nightly D1 export to file storage, restored in a test environment once a month.
- **Monitoring.** Uptime check, error rate, write counts against the plan limit, parse-failure rate from the app.
- **Costs.** Review monthly; set a spending alert.
- **Moderation.** Weekly review of the flag queue; publish a short transparency note each season.
- **Security.** Rotate secrets yearly; dependency updates monthly; no personal data beyond Discord id and character names.
- **Community.** Keep the fair-play page, rules and known issues up to date.
- **If it ends.** Freeze the final season, publish the hall of fame, leave the add-on working offline in Casual mode.

## 4. Privacy and policy

- Stored: Discord id, public key, character name and realm, ledger. Nothing else.
- Ranked players are public on the website by character name. Casual players are not listed.
- A player can delete their data from the website; the server removes rows and blobs and keeps only an anonymous ban marker if needed.
- No Blizzard art is stored on the website. Card art comes from the game client only.

## 5. Plausibility checks (starting values, tune in beta)

| Check | Starting rule |
|---|---|
| Chain integrity | Any broken hash rejects the batch |
| Sequence | No gaps, no replays |
| Attempts per hour | Over 1,200 sustained is flagged |
| New character, large collection | More than 200 unique cards in the first hour is flagged |
| Luck score | Review at 4, hold at 6 |
| Tape order | Out-of-order or reused index rejects the batch |
| Trade match | Unmatched after 7 days is excluded |
| Dust balance | Must equal recycled minus crafted; mismatch rejects the batch |

## 6. Testing

- **Lua**: `luajit tests/run.lua` on every change (currently 54 checks), plus `node --test tests/vectors.test.js` for the shared contract (7 checks). New code needs tests before merge.
- **Server**: unit tests with recorded ledgers, including tampered and replayed ones.
- **End to end**: a recorded real saved file replayed through the app against staging.
- **In game** (manual, before every release): load with no errors; find a card; recycle and craft; trade between two real accounts; reload and confirm the ledger verifies; open the Settings tab; open the leaderboard tab.
- **Chaos**: kill the app mid-upload, delete the data file, change the clock; the system must recover without losing cards.

## 7. Rough costs

| Stage | Hosting per month |
|---|---|
| Build and closed beta | $0 (free plans) |
| Public launch | about $5 (Cloudflare Workers Paid) |
| If analytics outgrow D1 | $25 (a hosted Postgres) |

Plus a domain (about $10 to $15 per year), and optionally a Windows code-signing certificate. Prices were checked on third-party sites on 10 Nov 2026 and must be confirmed on the providers' own pages before committing.

## 8. Risks

| Risk | Impact | Response |
|---|---|---|
| Forever forbids the app or changes the add-on rules | Project blocked | Settle D1 first; Casual mode still works |
| Players edit the add-on to skip unlucky rolls | Unfair advantage | Bounded by rate limits, luck score, evidence from top ranks |
| Saved data only writes on reload or logout | Stale leaderboards | Say so in the UI; show "last synced" |
| Game patch breaks events the add-on relies on | No drops recorded | Version checks, kill switch (server tells clients to pause ranked mode) |
| Support and moderation load grows | Burnout | Keep rules simple, automate flags, publish decisions |
| Licence or source-terms problem | Public launch delayed | Settle D3 and D4 before launch |

## 9. Maintainability standards

**Layout**

```
AzerothCardBinder/     the add-on, installed as-is (keep this path)
server/                Worker API: src/, migrations/, test/
app/                   companion app: src/, test/
packages/shared/       catalog.json, JSON schemas, test vectors (the contracts)
tools/                 data pipelines (fetch-reactions, build-catalog, build-nodes, backdrop-prompts)
docs/                  ROADMAP, LEDGER-SPEC, API, MODERATION, POLICY, adr/, runbooks/
tests/                 Lua tests
```

**Contracts first.** The ledger format, hashing, signing, API requests and catalog are described once, as `docs/LEDGER-SPEC.md`, `docs/API.md` and JSON Schemas under `packages/shared/`. Lua, server and app tests all load the same vectors. A change to the format means changing the spec and the vectors first; a CI job fails if an implementation disagrees.

**Code rules**
- Server and app are TypeScript in strict mode. The add-on stays Lua 5.1 and is checked with luacheck.
- Formatters are enforced in CI (Prettier for TypeScript, StyLua for Lua). No debates about style in reviews.
- Keep files small: a Lua file over about 400 lines or a TypeScript file over about 300 lines gets split before new code goes in.
- No hidden global state on the server. Configuration comes from environment settings, documented in one place.
- Dependencies are few, pinned by lockfile, and updated monthly (Dependabot or Renovate). Adding one needs a line in the PR saying why.
- Commit messages are short and imperative; releases follow semantic versioning with a `CHANGELOG.md`.

**Decisions and knowledge**
- Every significant decision gets an ADR (`docs/adr/NNNN-title.md`): context, decision, alternatives, consequences.
- Each component has a README: how to run it, test it, release it.
- Runbooks in `docs/runbooks/` for: database overloaded, bad deploy rollback, flag storm, season rollover failure, leaked or lost key, data deletion request, catalog refresh after a game patch.
- At least two people can deploy and restore from backup. Secrets are in a password manager and the host's secret store, never in the repo.
- Infrastructure is code: `wrangler.toml`, migrations and scripts live in the repo. No configuration that exists only in a web dashboard.

**Testing pyramid**
- Many fast unit tests (Lua, server, app) on every pull request.
- Contract tests from the shared vectors, on every pull request.
- A smaller set of replay tests: recorded real saved files run through the app and staging server.
- Load and chaos tests before each major release (Section 10).
- Core modules (ledger, hashing, scoring, migrations) have no merge without tests; the rest follow the existing habit of testing every feature.
- Add-on saved-data migrations are tested with committed fixture files for every past schema version, so v1 and v2 files keep loading forever.

**Changing things safely**
- Feature flags and kill switches are served from the server (for example "pause ranked mode", "pause new uploads"), so a bad release can be contained in minutes without every player updating.
- API and saved-data changes are additive first; breaking changes get a new version and a migration window.
- Add-on, app and API versions are tied by a compatibility table in `docs/API.md`; the server states `minClient`.

## 10. Scalability plan

**What drives load.** One upload per player per reload or logout (a few per day), with tens of events. The expensive operations are writes, leaderboard calculation and rank lookups. Reads of public pages are cheap if cached.

**Platform facts** (from Cloudflare's own documentation, checked on 10 Nov 2026): each D1 database holds up to 10 GB on the paid plan, and each database processes queries one at a time (it queues, and returns an "overloaded" error if the queue fills); an account can have up to 50,000 databases; Worker CPU time is limited per request but waiting on the database does not count. Third-party blogs mention a write ceiling of roughly 200 per second and a 30-second query limit; treat both as unconfirmed and measure.

**Sizing (rough, assuming about 5 uploads per player per day, about 30 row writes per upload including index writes)**

| Active players | Uploads per day | Average per second | Peak (about 20 times average) | What it means |
|---|---|---|---|---|
| 1,000 | 5,000 | 0.06 | about 1 | Trivial. One D1 database. |
| 10,000 | 50,000 | 0.6 | about 12 | Comfortable on one database; watch season start and patch days. |
| 100,000 | 500,000 | 6 | about 120 | At or past one database's limit. Needs a queue and sharding. |

At 100,000 players the stored drops alone could pass 10 GB (about 100,000 players times about 10,000 drops times about 60 bytes is about 60 GB), so storage forces sharding before throughput does. Compressed upload batches (about 50 GB) belong in object storage, not in the database.

**Design choices that keep every tier open (built from the start)**
1. **Partition by player.** Every table has `playerId`; no query joins two players except trade matching, which goes through a small separate table.
2. **Random IDs.** ULIDs, never auto-increment, so players can be moved between databases.
3. **Thin ingest.** The upload endpoint only verifies the signature and hash chain, then hands the batch to an `IngestStore`. At small scale it writes directly; at large scale the same interface writes to a queue and a worker applies it. The rules code does not change.
4. **Idempotent uploads** (B12), so queues, retries and duplicate deliveries are safe.
5. **Precomputed reads.** Leaderboards are calculated on a schedule into cached files. "Your rank" comes from the last snapshot, not a live count. Public pages are cached about 60 seconds.
6. **Derived data is rebuildable** (D8), so a database can be re-sharded by replaying ledgers.
7. **Batch, don't chatter.** The app uploads only new events, at most every few minutes; the server replies with everything the app needs in one response.
8. **Cold storage by season.** Old season batches move to object storage and are fetched only for audits.
9. **Edge rate limits** per key and per IP, so one broken client cannot flood the system.

**Graceful degradation**
- Server down: the add-on works offline in Casual mode; ranked rolls keep working on the tape already downloaded (10,000 rolls, usually weeks of play); the app queues uploads and retries with backoff.
- Overloaded: the server answers "try again later" with a retry time; the app honours it.
- Add-on side: the ledger is pruned after acknowledgement; if the app has not run and un-acknowledged events pass a limit (starting at 5,000), the Settings tab warns and ranked rolls pause until the app syncs. The saved-data file stays small (target under about 5 MB; verify the client's tolerance).

**Targets** (starting values, review after the beta): uploads accepted in under 1 second at the 95th percentile; leaderboard at most 10 minutes stale; 99.5% monthly availability for the API; zero lost accepted events.

**Scale triggers** (reviewed monthly, tracked on a dashboard)

| Metric | Threshold | Action |
|---|---|---|
| Database write queue time or "overloaded" errors | Any sustained errors, or p95 over 200 ms | Turn on queued ingest |
| Peak writes per second | Over 60% of the measured limit | Shard by player into several databases |
| Database size | Over 6 GB of 10 GB | Move batches to object storage; start sharding |
| Monthly cost | Over the budget alert | Review write patterns, cache hit rate |
| Leaderboard job duration | Over half of its schedule interval | Compute incrementally, per shard |
| Upload failure rate | Over 1% | Investigate before adding features |

**Load testing** (E2): replay simulated players at 10 times the expected peak against staging; confirm the triggers fire before users are affected. Repeat before every season start.

## 11. First actions

1. Settle D1, D3 and D4 (policy, noncommercial status, licence).
2. ~~Phase 0: G1 to G6~~ Done. Still open from it: G2b (linters), G4b (split the test file), turn on branch protection requiring the CI check.
3. Build A1: SHA-256 with the shared vectors.
4. Build A2 and A3: schema 2 migration (with committed fixture files) and attempts counters.
5. Build A4: persistent roll memory.
6. Build A5: ledger and chain verification.
7. Build A7 and A8: Settings tab status and `/acb verify`.
8. Play-test Phase A in game with two accounts.
9. Create the Cloudflare account and the staging environment (B2); write the catalog export (B4).
10. Start the Worker API behind the store interfaces, with ledger verification and its tests (B3, B11).
