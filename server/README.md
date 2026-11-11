# Server

The Worker API that receives signed ledger uploads, verifies them, and serves the leaderboard. Built in Phase B of [docs/ROADMAP.md](../docs/ROADMAP.md). The API is described in [docs/API.md](../docs/API.md); the ledger rules it enforces in [docs/LEDGER-SPEC.md](../docs/LEDGER-SPEC.md) and [packages/shared/](../packages/shared/).

TypeScript in strict mode, no runtime dependencies: only Web Crypto and standard `Request`/`Response`, so the same code runs in a Cloudflare Worker and in Node.

```
src/index.ts      the Worker entry point; wires settings to the pieces below, no logic
src/api.ts        routes, request limits, error mapping, logging
src/upload.ts     checking and storing a ledger upload (signature, chain, rules, snapshot, idempotency)
src/ledger.ts     hash chain checks; src/crypto.ts hashing, signatures, canonical JSON, ids
src/shared.ts     the rules shared with the app (../packages/shared/src/rules.js), with types
src/score.ts      the score formula, versioned
src/tape.ts       the roll tape: entries derived from a secret, and the check of every ranked drop
src/site.ts       the website: the ladder, a player's page, fair play and privacy, as plain safe HTML
src/taint.ts      following cards that came from Casual play through any number of trades
src/limit.ts      rate limiting
src/discord.ts    Discord sign-in, server half: exchange the code, read the player's id, revoke the token
src/maintenance.ts the hourly job: match the two halves of trades, write off unconfirmed ones
src/rebuild.ts    recompute everything derived from the stored batches (a page of players at a time)
src/derive.ts     what an upload's events say about trades, finished sets and drops (shared by upload and rebuild)
src/store.ts      PlayerStore, IngestStore and LeaderboardStore: what the rules code needs from storage
src/sqlStore.ts   those stores on D1 (or SQLite in tests); src/db.ts the small Db interface and the D1 adapter
migrations/       forward-only SQL; CHECKSUMS.txt records each one so a published migration cannot be edited
test/             contract tests against the shared vectors, the API end to end on SQLite, migrations
```

## Run the tests

Needs Node 24 or later (it runs TypeScript directly). No install is needed to run them:

```
node --test test/*.test.ts
```

Type-check (needs `npm ci` once, for the TypeScript compiler):

```
npm ci
npm run typecheck
```

`node tools/release.js build` at the repository root runs these tests along with everything else.

## Rules for changing it

- **Migrations are forward-only.** Never edit one that has shipped: add `000N_name.sql` and its line in `migrations/CHECKSUMS.txt` (`sha256sum` of the file, with line endings as LF). Use expand then contract: add the new column, deploy, backfill, switch the code, remove the old one in a later migration.
- **Storage stays behind the three interfaces** in `src/store.ts`. Rules and routes never touch SQL.
- **A new error code** goes in `src/errors.ts` and in the table in `docs/API.md`; a test keeps them equal.
- **No hidden state.** Settings come from `wrangler.toml` variables and secrets; nothing is read from the environment anywhere but `src/index.ts`.

## Not deployed yet

`wrangler.toml` holds placeholders until the Cloudflare account and the databases exist (roadmap B2). Discord sign-in is not connected, so `/v1/register` answers `registration_closed` (B7). Rate limits at the edge, the tape (Phase C) and the flag queue (Phase D) are not built.
