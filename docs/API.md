# API

Version 1, served under `/v1`. The server is `server/`; the ledger and signing rules it enforces are in [LEDGER-SPEC.md](LEDGER-SPEC.md). Everything is JSON. Times are whole seconds since 1970-01-01 UTC.

## Rules for clients

- Send `Content-Type: application/json` on POST, and `X-Warcards-Client: <x.y.z>` (the companion app's version) on `/v1/register` and `/v1/ledger`. A version below the server's `minClient` is refused with `client_too_old`; every successful upload reply states the current `minClient`.
- Uploads are **safe to repeat**. Sending a batch the server has already stored, with the same range and the same last hash, changes nothing and answers `200` with `duplicate: true`. After a lost reply, send the same batch again.
- A rate-limit or overload answer carries `Retry-After` (seconds) and a `retryAfter` field; wait at least that long. Back off further on repeated failures.
- Request bodies are limited to 2,000,000 bytes and uploads to 5,000 events. Send more events in more batches.
- Behave the same for any error you do not know: act on `error.code`, never on `error.message`.

## Compatibility

| App | Server API | Ledger spec | Add-on saved-data schema |
|---|---|---|---|
| 0.1.x | `/v1` | 2–4 (current app: 4) | 2 |

The server rejects uploads whose `specVersion` it does not support (`client_too_old`). It supports versions 2, 3 and 4. Version 3 adds packs; version 4 adds collectible editions and the `editions1` activation marker. Old chain hashes remain valid. Edition events require version 4; the companion app now uploads version 4. All components need the matching generated catalog. The table gains a row with every release that changes one of the columns.

## Endpoints

The public HTML website is served outside `/v1`: `/` introduces the project, `/ladder` lists Ranked collections, `/wanted` lists public requests, and `/player/:id` shows eligible public binders. Setup information is at `/download`, `/help` and `/faq`, with existing policies at `/fair-play` and `/privacy`.

`GET /status` performs a current database check and returns an HTML status page (200 healthy, 503 database unavailable). `GET /status/badge.svg` performs the same check and returns an SVG online/issue indicator with HTTP 200 in either case so it remains a valid image. Both use `Cache-Control: no-store`; neither monitors Discord, game realms or historical uptime. Public pages otherwise cache for 60 seconds and use no JavaScript or external resources.

### `GET /v1/health`

`200 { ok: true, db: true, version, catalogVersion }` when the database answers a query; `503 { ok: false, db: false, version }` when it does not. Never cached. Use this for uptime checks.

### `GET /v1/releases`

`200 { app: { latest, min }, addon: { latest, min } }`, every version as `x.y.z`. `latest` is the newest release of the companion app and of the add-on; `min` the oldest still accepted (the app's is the `minClient` that other routes enforce; the add-on's is not enforced yet). The companion app asks at start-up and every few hours, and tells the player when either is out of date. Public, cached for 5 minutes, not rate-limited more than other routes. The versions are Worker variables (`MIN_CLIENT`, `LATEST_APP`, `LATEST_ADDON`, `MIN_ADDON` in `server/wrangler.toml`), changed by a release, not by code.

### `POST /v1/register`

Links a public key to a Discord account. Body: `{ key, visibility, sentAt, identityToken, proof }`.

- `key`: Ed25519 public key, 64 lowercase hex characters.
- `visibility`: `"public"` (shown on the leaderboard and profile pages) or `"private"` (stored, never listed).
- `sentAt`: when the app built the request; refused if more than a day from the server's clock.
- `identityToken`: the one-time authorisation code Discord sent to the player's browser (letters, digits, `.`, `_`, `-`, 8 to 200 characters). The server exchanges it, with the Discord application's secret, for a short-lived token that can read only the player's own Discord id (scope `identify`), reads the id and revokes the token. A bad, used or expired code answers `bad_identity`.
- `proof`: Ed25519 signature, by `key`, of the canonical JSON of every other field plus `"purpose": "register"`. It proves the sender holds the private key.

`200 { playerId, visibility, minClient }`. Registering the same key twice returns the same player. A Discord account that signs in again with a **new** key keeps its player and ledger; its older keys are revoked, so a lost or leaked key is replaced by signing in again. Until the sign-in provider is connected the server answers `registration_closed`.

### `POST /v1/ledger`

Uploads new ledger events, signed with the registered key. The body and its signature are specified in [LEDGER-SPEC.md](LEDGER-SPEC.md) section 6. The server checks, in this order: the shape; the spec version; that the key is registered and active; the signature; whether this is a repeat of a stored batch; the hash chain; the meaning of every event (section 3.1); then compares the snapshot with what the events add up to. A difference in the snapshot is **recorded as a flag, not an error**: the events decide.

`200 { ackSeq, ackHash, accepted, duplicate, minClient, syncVersion }`. `ackSeq` and `ackHash` identify the last stored event: the app writes them into the add-on's `Data/Sync.lua` so the add-on can drop events the server holds. `accepted` is how many events this call stored (0 for a repeat or an empty batch). An empty batch simply reports where the chain stands.

Errors about the chain (`replay`, `gap`, `bad_field`, `bad_prev`, `bad_hash`) include `detail.index` (the position in the batch) and, for `replay` and `gap`, `detail.ackSeq` and `detail.ackHash`, so the app can work out what to send next. `rule_broken` includes `detail.rule` (for example `count`, `shiny`, `craft`, `recycle`, `trade`, `set`, `tape`, `time`, `dust`) and `detail.index`.

### `POST /v1/tape`

Ranked random numbers. Body: `{ key, sentAt, sig }`, where `sig` signs the canonical JSON of `{ key, sentAt, purpose: "tape" }` (a signature made for another purpose fails). `200 { start, entries, issued }`: `entries` are all the roll-tape entries this player has not used yet, counting from `start` (the position the add-on last said it would use next); each is 16 hex characters. When 250 or fewer remain, 1,000 new entries are added (a player is never more than about 1,250 entries ahead, so little of it can be read in advance) and `issued` is `{ start, end, commitment }` for the new range (the commitment is the SHA-256 of its entries joined by line feeds); otherwise `issued` is `null`. Asking again returns the same entries, so a lost reply costs nothing. `ranked_unavailable` while the server has no tape secret.

Every entry is derived from a server secret, the player and the position, so nothing is stored per entry and a player cannot compute entries they were not given. Every ranked attempt is checked against the entry at its `tape` position (spec section 8.1): a drop needs a roll at or below the chance that the card's own run of misses has built up, and its shiny flag must match the entry's second half while the card has no shiny yet; every attempt inside a `miss` run needs a roll above that chance. The positions of the events must follow each other with no gap (`rule_broken`, rule `tape`), and must have been issued. The `tapeIndex` of an upload may never pass the first position after the last one issued. A `packFind` must sit on an entry that says a pack was found, and each `packCard` must be the card and shiny flag its entry gives from the pack's zone (spec section 8.2). Failures are `tape_invalid` with `detail.reason` (`not-issued`, `roll`, `shiny`, `pack`, `next`).

### `POST /v1/reset`

Start a new binder. Body: `{ key, sentAt, sig }`, where `sig` is the Ed25519 signature, by the player's key, of the canonical JSON of `{ key, sentAt }` plus `"purpose": "reset"`. Everything stored for the player (batches, drops, scores, flags, trades, tapes) is kept under a new private archive with no Discord link and no key, so it can never be listed or uploaded to; the player's own record is emptied and their **epoch** goes up by one. Their keys, Discord link and visibility stay. `200 { playerId, epoch }`. The player then uploads a new chain from event 1.

The roll tape of a new binder is derived under `<playerId>.<epoch>` instead of `<playerId>`, so the old binder's roll values are never replayed. A history rolled on the old tape is refused with `tape_invalid`. At most once a day: `too_soon` (`429`) carries `Retry-After` and `detail.retryAfter`. A banned player gets `banned`, so a reset cannot be used to wipe a record. An unknown key, a wrong signature or one made for another purpose are refused as for `/v1/tape`.

### `POST /v1/delete`

Delete everything held about the player: their record, ledger, scores, characters, flags, trade halves, roll tapes, keys, Discord link and any archived binders from earlier resets. Body: `{ key, sentAt, confirm: "delete my data", sig }`, where `sig` is the Ed25519 signature, by the player's key, of the canonical JSON of `{ key, sentAt, confirm }` plus `"purpose": "delete"`. `200 { deleted: true }`. It cannot be undone. The same Discord account can sign up again and starts from nothing. Trade halves other players recorded against this player stay with those players. A **banned** player is refused (`banned`): their record, and the ban, is kept so that deleting the account cannot undo it. Cards in the game and files on the player's computer are not touched.

### Rate limits

Each client address has a general limit (120 requests a minute) and a stricter one for `POST` to `/v1/register`, `/v1/reset`, `/v1/delete` and `/v1/admin/*` (10 a minute). Over the limit the answer is `429 rate_limited` with `Retry-After: 60`; the companion app waits as long as it is told and tries again. `/v1/health` is never limited. The limits are Cloudflare rate-limit bindings (`server/wrangler.toml`); with no binding configured nothing is limited. Cloudflare counts them per location and approximately: on staging, 60 requests a minute against the strict limit of 10 let about 35 through before the first refusal. They stop floods, not exact counts, so do not rely on them for fine control.

### Checks that flag instead of reject

After an upload is accepted the server also looks at the player's results and may open a flag for a person to review (the upload is still stored): `snapshot-mismatch` (the snapshot disagrees with what the events add up to), `luck-review` and `luck-hold` (more drops than the attempts explain; a held player is hidden from `/v1/leaderboard` and `/v1/player/:id` until the flag is cleared), `rate` (roll-tape entries used faster than 1,200 an hour), `fast-start` (over 200 unique cards in an account's first hour), `trade-unmatched` (a trade half the partner never confirmed within seven days; see below) and `trade-half-missing` (raised against a player who uploaded after a trade and never recorded their half of it) and `reported` (three different players reported the player within a week; see `POST /v1/report`). Flags carry no public detail and are not part of any response.

### `GET /v1/leaderboard?limit=N`

The best **public** players **with no Casual drops** (see below), highest score first, ties broken by who reached the score first. `limit` is 1 to 100 (default 100). `200 { generatedAt, entries: [{ rank, playerId, displayName, scoreTenths, uniqueCards, setsDone, characters }] }`. `characters` lists the player's characters in the form players are named by between themselves (`name-realmname`, lower case), so a client can mark them as verified. Cached for 60 seconds.

### `GET /v1/firsts`

Who finished each set first, among the players who may appear on the ladder (public, not banned, not held): `200 { generatedAt, firsts: [{ setCode, title, playerId, displayName, at }] }`, earliest first. `at` is when the server received the upload with the finishing event, not the player's own clock. If the first player is later held back or banned, the next one is first. Cached for 60 seconds.

### `POST /v1/wanted` and `GET /v1/wanted`

The cards a player is looking for, so other players can see them at once. `POST` body: `{ key, sentAt, cards, sig }`, where `cards` is a list of up to 60 distinct catalog keys (`npc:589`, `obj:1731`) and `sig` is the Ed25519 signature, by the player's key, of the canonical JSON of `{ key, sentAt, cards }` plus `"purpose": "wanted"`. `sentAt` must be within a day of the server's clock. It replaces the player's whole list. `200 { stored, listed }`: only a **public** player's list is kept (`listed: true`); a private player's is stored as empty. `GET` answers `200 { generatedAt, players: [{ playerId, displayName, characters, cards, updatedAt }] }` for up to 100 public, non-banned players with at least one character, most recently changed first. Cached for 60 seconds. The same list is the website's `/wanted` page. The companion app uploads the list whenever it changes and brings the board into `Data/Sync.lua` for the add-on's Wanted tab.

### `POST /v1/report`

A player tells us about another player: a suspected cheat or a trade that went wrong. Body: `{ key, sentAt, reports, sig }`, where `reports` is 1 to 10 of `{ token, target, reason, note }` and `sig` is the Ed25519 signature, by the reporter's key, of the canonical JSON of `{ key, sentAt, reports }` plus `"purpose": "report"`. `token` is 6 to 40 characters of `0-9a-z` that the add-on makes up, so a lost reply can be sent again safely. `target` is the character as players name each other (`name-realmname`, lower case). `reason` is `cheating`, `trading` or `other`; `note` is up to 120 characters with no control characters (it may be empty). `200 { done, stored }`: `done` lists the tokens that are settled (stored, repeated, or about the reporter's own character), so the companion app can tell the add-on to forget them; `stored` is how many were new. A reporter can store 20 reports a day (the rest are left out of `done` and sent again later) and one about the same character a day; a name no known player has played is stored with no player attached. Nothing is hidden or changed for the reported player: when three different players have reported them within a week the server opens one `reported` flag for a person to review, which does not hide them from the ladder. A banned reporter gets `banned`. This route has the stricter rate limit.

### `GET /v1/admin/reports?player=<id>&limit=N`

For reviewers, behind the admin token (see Admin routes below): the newest reports about one player, `{ reports: [{ id, reporterId, targetName, targetId, reason, note, createdAt }] }` (`limit` 1 to 200, default 50).

### Only Ranked counts

A drop rolled in Casual mode (tape position 0) uses the player's own random numbers, which the server cannot recheck. Such uploads are stored and scored as before, but a player with **any** Casual drop is not listed on `/v1/leaderboard`, `/v1/player/:id` or `/v1/firsts`. Cards received in a trade from a player with Casual drops do not count towards the receiver's score either (the hourly job puts scores right after the fact). The count is `ledger_state.casual_drops`, and a rebuild recomputes it from the stored events.

### Trade matching

Every `tradeIn` and `tradeOut` is stored as one half of a trade. A half is matched when the other player's upload holds the opposite half: the same trade id and card, each naming the other as partner. Once an hour the server pairs up what it has; a half still unmatched after seven days is written off, and the copies it brought in stop counting towards the score and towards finishing a set. Who is flagged depends on who is at fault: if the partner has uploaded since the trade and their upload still lacks the matching half, **the partner** gets a `trade-half-missing` flag (this is how someone who takes a card without recording what they gave shows up, rather than the person they took it from). If the partner has not uploaded since, the owner of the half gets `trade-unmatched`, because nothing says whose fault it is. If the partner's upload turns up later, the halves match and the score is put right.

### Admin routes

For the people who run the service, not for clients. They need the header `authorization: Bearer <ADMIN_TOKEN>`, where the token is a Worker secret (`wrangler secret put ADMIN_TOKEN`). With no token configured these addresses answer `not_found`, as if they did not exist; a missing or wrong token answers `unauthorized`. Never cached.

- `GET /v1/admin/flags?state=open|cleared|confirmed|all&limit=N` (default `open`, `limit` 1 to 500): `200 { flags: [{ id, playerId, displayName, kind, state, notes, createdAt, reviewedAt, reviewNote }] }`, oldest first.
- `POST /v1/admin/flags/:id { state: "cleared" | "confirmed", note? }` (note up to 500 characters): a reviewer's decision. A **held** player stays off the ladder until their flag is **cleared**; **confirmed** keeps them off. Luck that was cleared is not flagged again until it is two more orders of magnitude beyond what was cleared. `404` for an unknown flag.
- `POST /v1/admin/players/:id/ban { banned: boolean }`: a banned player cannot upload (`banned`) and is hidden from the ladder; nothing is deleted. `404` for an unknown player.
- `POST /v1/admin/rebuild { after?, limit?, dryRun?, force? }`: recomputes everything derived from the stored batches (state, drops, trade halves, finished sets, score and its rules version) for one page of players (`limit` 1 to 200, default 50, in id order after `after`). `200 { checked, changed: [{ playerId, differences }], failed: [{ playerId, rule, index }], next, dryRun }`; carry on with `after: next` until it is `null`. A dry run writes nothing. A player whose stored history no longer passes the rules is listed in `failed` and left as it is. Trade halves come back open; the hourly job matches them again.

### `GET /v1/player/:id`

A public player's entry: `{ playerId, displayName, rank, scoreTenths, uniqueCards, setsDone, attempts, updatedAt }`. Private players and unknown ids answer `not_found`, the same for both, so privacy cannot be probed. Cached for 60 seconds.

`scoreTenths` is the score in tenths of a point (a whole number); divide by 10 to show it. The weights are in `server/src/score.ts` and [ROADMAP.md](ROADMAP.md) (D7); a change to them is a new rules version and a recompute, never an edit.

## Errors

Every error is `{ "error": { "code", "message", "detail"?, "retryAfter"? } }` with the HTTP status below. This table is kept equal to `server/src/errors.ts` by a test.

<!-- errors:start -->
| Code | HTTP | Meaning |
|---|---|---|
| `bad_request` | 400 | The request could not be understood. |
| `bad_signature` | 401 | The signature does not match the key. |
| `unknown_key` | 401 | This key is not registered. |
| `unauthorized` | 401 | The admin token is missing or wrong. |
| `bad_identity` | 401 | The sign-in could not be verified. |
| `banned` | 403 | This player is not allowed to upload. |
| `not_found` | 404 | There is nothing here. |
| `method_not_allowed` | 405 | That method is not supported here. |
| `duplicate_batch` | 409 | These events are already stored with different contents. |
| `replay` | 409 | These events were already stored. |
| `gap` | 409 | Events are missing before this batch. |
| `conflict` | 409 | Another upload for this player was in progress. Try again. |
| `too_soon` | 429 | A binder was started recently. Try again later. |
| `rate_limited` | 429 | Too many requests. Slow down and try again. |
| `too_large` | 413 | The upload is too large. |
| `unsupported_media` | 415 | Send JSON. |
| `bad_field` | 422 | An event field is not valid. |
| `bad_prev` | 422 | An event does not follow the one before it. |
| `bad_hash` | 422 | An event was changed after it was written. |
| `rule_broken` | 422 | The events describe a binder that cannot exist. |
| `tape_invalid` | 422 | A ranked drop does not match the roll tape. |
| `client_too_old` | 426 | Update the companion app. |
| `internal` | 500 | Something went wrong on our side. |
| `registration_closed` | 503 | Registration is not open yet. |
| `ranked_unavailable` | 503 | Ranked play is not open yet. |
| `overloaded` | 503 | The server is busy. Try again soon. |
<!-- errors:end -->

`conflict` and `overloaded` are worth retrying after `retryAfter`; the 4xx errors about the contents of a batch are not, until the batch is fixed.
