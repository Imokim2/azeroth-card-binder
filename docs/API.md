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
| 0.1.x | `/v1` | 1 | 2 |

The server rejects uploads whose `specVersion` it does not support. The table gains a row with every release that changes one of the columns.

## Endpoints

### `GET /v1/health`

`200 { ok: true, db: true, version, catalogVersion }` when the database answers a query; `503 { ok: false, db: false, version }` when it does not. Never cached. Use this for uptime checks.

### `POST /v1/register`

Links a public key to a Discord account. Body: `{ key, visibility, sentAt, identityToken, proof }`.

- `key`: Ed25519 public key, 64 lowercase hex characters.
- `visibility`: `"public"` (shown on the leaderboard and profile pages) or `"private"` (stored, never listed).
- `sentAt`: when the app built the request; refused if more than a day from the server's clock.
- `identityToken`: the Discord sign-in the app obtained; the server turns it into a Discord account id.
- `proof`: Ed25519 signature, by `key`, of the canonical JSON of every other field plus `"purpose": "register"`. It proves the sender holds the private key.

`200 { playerId, visibility, minClient }`. Registering the same key twice returns the same player. A Discord account that signs in again with a **new** key keeps its player and ledger; its older keys are revoked, so a lost or leaked key is replaced by signing in again. Until the sign-in provider is connected the server answers `registration_closed`.

### `POST /v1/ledger`

Uploads new ledger events, signed with the registered key. The body and its signature are specified in [LEDGER-SPEC.md](LEDGER-SPEC.md) section 6. The server checks, in this order: the shape; the spec version; that the key is registered and active; the signature; whether this is a repeat of a stored batch; the hash chain; the meaning of every event (section 3.1); then compares the snapshot with what the events add up to. A difference in the snapshot is **recorded as a flag, not an error**: the events decide.

`200 { ackSeq, ackHash, accepted, duplicate, minClient, syncVersion }`. `ackSeq` and `ackHash` identify the last stored event: the app writes them into the add-on's `Data/Sync.lua` so the add-on can drop events the server holds. `accepted` is how many events this call stored (0 for a repeat or an empty batch). An empty batch simply reports where the chain stands.

Errors about the chain (`replay`, `gap`, `bad_field`, `bad_prev`, `bad_hash`) include `detail.index` (the position in the batch) and, for `replay` and `gap`, `detail.ackSeq` and `detail.ackHash`, so the app can work out what to send next. `rule_broken` includes `detail.rule` (for example `count`, `shiny`, `craft`, `recycle`, `trade`, `set`, `tape`, `time`, `dust`) and `detail.index`.

### `POST /v1/tape`

Ranked random numbers. Body: `{ key, sentAt, sig }`, where `sig` signs the canonical JSON of `{ key, sentAt, purpose: "tape" }` (a signature made for another purpose fails). `200 { start, entries, issued }`: `entries` are all the roll-tape entries this player has not used yet, counting from `start` (the position the add-on last said it would use next); each is 16 hex characters. When 2,000 or fewer remain, 10,000 new entries are added and `issued` is `{ start, end, commitment }` for the new range (the commitment is the SHA-256 of its entries joined by line feeds); otherwise `issued` is `null`. Asking again returns the same entries, so a lost reply costs nothing. `ranked_unavailable` while the server has no tape secret.

Every entry is derived from a server secret, the player and the position, so nothing is stored per entry and a player cannot compute entries they were not given. A ranked drop is checked against the entry at its `tape` position: it must be at a position that was issued; its roll must be at or below the card's rate, or count as a bad-luck guarantee (a card earns one per `limit` attempts, judged from the snapshot's attempts); and its shiny flag must match the entry's second half while the card has no shiny yet. The `tapeIndex` of an upload may never pass the first position after the last one issued. Failures are `tape_invalid` with `detail.reason` (`not-issued`, `stack`, `shiny`, `next`).

### Checks that flag instead of reject

After an upload is accepted the server also looks at the player's results and may open a flag for a person to review (the upload is still stored): `snapshot-mismatch` (the snapshot disagrees with what the events add up to), `luck-review` and `luck-hold` (more drops than the attempts explain; a held player is hidden from `/v1/leaderboard` and `/v1/player/:id` until the flag is cleared), `rate` (roll-tape entries used faster than 1,200 an hour) and `fast-start` (over 200 unique cards in an account's first hour). Flags carry no public detail and are not part of any response.

### `GET /v1/leaderboard?limit=N`

The best **public** players, highest score first, ties broken by who reached the score first. `limit` is 1 to 100 (default 100). `200 { generatedAt, entries: [{ rank, playerId, displayName, scoreTenths, uniqueCards, setsDone }] }`. Cached for 60 seconds.

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
| `bad_identity` | 401 | The sign-in could not be verified. |
| `banned` | 403 | This player is not allowed to upload. |
| `not_found` | 404 | There is nothing here. |
| `method_not_allowed` | 405 | That method is not supported here. |
| `duplicate_batch` | 409 | These events are already stored with different contents. |
| `replay` | 409 | These events were already stored. |
| `gap` | 409 | Events are missing before this batch. |
| `conflict` | 409 | Another upload for this player was in progress. Try again. |
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
