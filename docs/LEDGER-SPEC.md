# Ledger specification

Version 1 (draft until Phase A of the [roadmap](ROADMAP.md) has shipped). This is the contract between the Lua add-on, the companion app and the server. All three implement it separately; all three must produce exactly the results in [packages/shared/vectors](../packages/shared/vectors). The reference implementation is [packages/shared/src/ledger.js](../packages/shared/src/ledger.js).

If this document, the reference implementation and the vectors ever disagree, that is a bug. Fix all three together in one change.

## 1. What the ledger is for

The ledger is a tamper-evident history of every change to a player's binder. Each event includes a hash of the one before it, so any edit to an earlier event breaks every hash after it. The server keeps the ledger and rebuilds everything else (counts, scores, ranks) from it.

It does **not** prove an event really happened in the game. The player's computer is the only witness, and the player controls it. It makes history impossible to rewrite after upload, and it gives the server something exact to check. See Section 0 of the roadmap.

## 2. Conventions

- **Integers** are written in decimal with no leading zeros and no plus sign. A minus sign is allowed only where stated. Values must fit in 53 bits (a JavaScript safe integer).
- **Strings** are UTF-8. In a ledger event they must not contain `|`, a carriage return or a line feed.
- **Hex** is lowercase.
- **Time** is whole seconds since 1970-01-01 UTC.
- **Card keys** are `npc:<id>` or `node:<id>`. A key is never reused or renamed.

## 3. Events

| Field | Type | Meaning |
|---|---|---|
| `seq` | integer, 1 or more | Position in the chain. The first event is 1; each next one is exactly one more. |
| `t` | integer, 0 or more | When the add-on wrote it, by the player's clock. |
| `kind` | string | One of `drop`, `craft`, `recycle`, `tradeIn`, `tradeOut`, `set`, `mode`. |
| `key` | string, not empty | The card key; for `set` the set code (for example `DM`); for `mode` either `casual` or `ranked`. |
| `count` | integer, 0 or more | How many copies of that card the player owns after this event. 0 for `set` and `mode`. |
| `dust` | integer, may be negative | Change in Binder Dust: plus for `recycle`, minus for `craft`, 0 otherwise. |
| `shiny` | 0 or 1 | 1 when this event produced the shiny copy of a card. |
| `tape` | integer, 0 or more | The ranked tape entry used, counting from 1; 0 when none was used. |
| `partner` | string, may be empty | For trades: the other player, as `name-realm` in lowercase, spaces removed. |
| `trade` | string, may be empty | For trades: the trade id both players share. |
| `char` | string, not empty | The acting character as `Name-Realm`, spaces removed from the realm. |
| `prev` | 32 hex characters | The `h` of the previous event; 32 zeros for `seq` 1. |
| `h` | 32 hex characters | This event's hash (Section 4). |

### 3.1 Meaning of each kind (checked by the server in Phase B)

The server replays the events from `seq` 1 and keeps a running count per card and a running dust balance. It rejects a batch that breaks any of these:

- `drop`: `count` is the previous count plus 1. `shiny` may be 1 only when `count` is 1 and no earlier event for that card had `shiny` 1. In ranked mode `tape` must be at least 1 and greater than the `tape` of every earlier event.
- `craft`: the previous count is 0 and `count` is 1; `dust` equals minus the craft cost of the card's rarity, from the catalog; `shiny` is 0.
- `recycle`: the previous count is at least 2, `count` is one less, and `dust` equals the recycle yield of the card's rarity.
- `tradeOut`: the previous count is at least 2 and `count` is one less. `tradeIn`: `count` is the previous count plus 1. Both need `partner` and `trade`.
- `set`: `key` is a set code and every card of that set is owned at that point.
- `mode`: `key` is `casual` or `ranked`.
- The running dust balance never goes below 0.
- `t` never decreases from one event to the next.

Misses are not events. They are counted in the snapshot's `attempts` (Section 6).

## 4. The event hash

1. Write the event's fields as text, in this exact order, joined by `|`:

   `seq|t|kind|key|count|dust|shiny|tape|partner|trade|char|prev`

   An empty `partner` or `trade` is an empty piece of text between two bars.
2. Take the SHA-256 of that text as UTF-8 bytes (FIPS 180-4).
3. `h` is the first 32 characters of the lowercase hex result.

Example (the first event in the vectors): `1|1000|mode|ranked|0|0|0|0|||Alice-RealmName|00000000000000000000000000000000`.

## 5. Checking a batch

Given the stored head (`seq` and `h` of the last stored event, or `seq` 0 and 32 zeros for a new chain) and a batch of events, check each event in order. The first failure rejects the whole batch with one of these errors:

| Error | When |
|---|---|
| `replay` | The event's `seq` is not greater than the previous one: it is already stored. |
| `gap` | The event's `seq` is not the previous one plus 1. |
| `bad-field` | A field breaks the rules in Sections 2 and 3. |
| `bad-prev` | `prev` is not the previous event's `h` (or the stored head's). |
| `bad-hash` | `h` does not match the hash of the event's own fields. |

The checks run in that order. An empty batch is valid. On success the new head is the last event's `seq` and `h`.

## 6. Uploads

The app sends the server a JSON object with these fields:

| Field | Meaning |
|---|---|
| `specVersion` | This specification's version (1). |
| `key` | The player's public key, 64 hex characters (Ed25519). |
| `character`, `realm` | Where the file was last written. |
| `schema` | The add-on's saved-data schema version. |
| `catalogVersion` | The card catalog the add-on had loaded. |
| `events` | New events, oldest first, continuing the stored chain. |
| `snapshot` | `counts` (card key to copies owned), `attempts` (card key to lifetime attempts), `dust`, `sets` (set code to true), `titles` (title name to true). |
| `tapeIndex` | The next tape entry the add-on will use. |
| `sentAt` | When the app sent it. The server also records its own receive time and trusts that one. |
| `sig` | Ed25519 signature, 128 hex characters. |

The snapshot is a check, not a source: the server compares it with the counts it gets by replaying events and flags any difference.

### 6.1 Canonical JSON and the signature

The signature covers the **canonical JSON** of the object without its `sig` field. Canonical JSON is UTF-8 text with:

- object keys in ascending order by Unicode code point;
- no spaces or line breaks between tokens;
- integers only (no fractions, no exponents), no `null`, no missing values;
- strings written as `JSON.stringify` writes them (quotes and backslashes and control characters escaped; every other character, including non-ASCII, left as it is).

`sig` is the Ed25519 signature (RFC 8032) of those bytes, as 128 hex characters. Ed25519 is deterministic: signing the same bytes with the same key gives the same signature.

## 7. Identity

- The app creates an Ed25519 key pair on first run and keeps the private key in the operating system's keychain. The public key (64 hex characters) is the player's identity on the server.
- The in-game link code (`/acb link CODE`) proves that a given saved-data file and a given key belong together. The server never sees the file's owner, only the key.
- Losing the private key, or having it leak, is repaired by signing in with Discord again and registering a new key. The server revokes the old key and keeps the player and the ledger: the chain is not tied to the key, so the next upload simply continues it. Without a Discord sign-in there is no way to take over an identity.

## 8. Ranked random numbers (the tape)

A tape is a list of entries issued by the server, 16 hex characters each. The server stores a commitment: the SHA-256 of all the entries joined by a line feed.

For each ranked roll the add-on takes the next unused entry (counting from 1):

- **Roll value** = the first 8 hex characters read as a number, modulo 10000, plus 1 (so 1 to 10000).
- **Drop** when the roll value is at most the card's rate (in hundredths of a percent: 100 is 1%), or when the bad-luck guarantee applies.
- **Shiny** (for a first copy only) when the next 8 hex characters read as a number, modulo the shiny odds, plus 1, equals 1.
- A roll uses its entry whether it wins or not, so `tape` in a drop event tells the server how many entries were spent before and including it.

The server knows every entry, so it can recheck each drop. Entries are never reused.

## 9. Versioning and compatibility

- `specVersion` changes when anything in this document changes in a way an old implementation would get wrong. The server states the lowest version it accepts.
- Fields may be added to uploads without a version change, but never to the hashed event text: that would change every hash. A new hashed field means a new `specVersion` and a new chain.
- Event kinds are only ever added. An implementation that sees a kind it does not know rejects the batch with `bad-field`.
- Cards are never removed from the catalog; a retired card stays valid in old ledgers.

## 10. Implementing it

- **Lua (the add-on):** WoW's Lua 5.1 provides the `bit` library; SHA-256 is written with it. Numbers are doubles, so integers stay below 2^53. Hex to number is `tonumber(text, 16)`, which is exact for 8 hex characters.
- **TypeScript (server, app):** use the reference implementation, or Web Crypto for SHA-256 and Ed25519.
- Every implementation's tests load the shared vectors and compare results exactly. The Lua vectors are in `packages/shared/vectors/vectors.lua`; the JSON ones are in the same folder.
- To change a vector, change [tools/build-vectors.js](../tools/build-vectors.js) and run it. `node --test tests/vectors.test.js` fails if the committed files differ from what the generator writes.

## 11. The add-on's local check value

The add-on keeps one more value that is not part of an event and is never uploaded: `stateSum`, 12 hex characters, which stands for the card counts and the dust balance as the ledger last left them. It is two 24-bit sums, each adding the first half of SHA-256 of `<card key>=<count>` for every owned card and `dust=<balance>` when the balance is above zero. Adding or removing a copy changes the sum by two small hashes instead of rehashing the whole binder.

On load the add-on recomputes the sum from the saved counts and compares it. A mismatch, a broken chain, a head that does not match the last event, or a missing sum on a binder that has a history all mean the binder is **unverified**: the add-on switches to Casual mode and says so. A missing sum on a brand new binder, or one just upgraded from schema 1, is instead filled in from the counts at that moment, so a binder that existed before the ledger starts its history from the cards it already owns.

This is a local check for accidents and casual edits. Anyone who reads the add-on can recompute the sum, so only the server's replay of the events is a real check.

## 12. Known limits

- The ledger cannot show that a kill happened. See the roadmap's plausibility checks and evidence process.
- A player who edits the add-on can still choose which tape entries to spend. The server bounds this by rate limits and by comparing attempts with drops.
- A binder upgraded from schema 1 has cards the ledger never saw drop, so its events cannot account for them. Phase B must decide how the server treats such a binder (play Casual, or ranked from a fresh binder). Until then it is verified locally only.
- The 32-character hash is a truncation of SHA-256. It is plenty to catch edits and accidents; it is not meant to resist someone who controls both ends of the chain, which this design never claims to stop.
