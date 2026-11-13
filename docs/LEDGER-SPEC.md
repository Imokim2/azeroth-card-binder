# Ledger specification

Version 8. Version 8 adds `mode/chase2` (the second set of drop rates, below). Versions 2–4 added exact attempts, packs and collectible editions. Version 5 adds `mode/chase1` for per-card drop profiles and weighted packs. Version 6 adds pack tiers, the satchel and pack trades. Version 7 adds server-authorised seasonal pack rewards. Existing hashes and older histories retain their meaning. All components must produce the results in [packages/shared/vectors](../packages/shared/vectors); the reference implementation is [packages/shared/src/ledger.js](../packages/shared/src/ledger.js).

## Seasonal rewards (version 7)

`seasonReward` has the canonical pack ID as `key`, the resulting pack inventory as `count` (exactly one higher), and the server-issued 32-hex grant ID as `trade`. Partner, dust, shiny and tape are zero/empty. It cannot interrupt a pack opening. Replay preserves `seasonClaims` and rejects a repeated grant. The server independently checks grant ownership, pack identity and non-redemption, then stores redemption atomically with the verified batch. These events need upload specification 7; ordinary uploads can remain version 6. No hashed field or historical event meaning changes. Seasonal progress itself is server-derived from eligible new acquisitions, not an inventory snapshot; see [SEASONS.md](SEASONS.md).

## Pack tiers and trades (version 6)

Pack IDs are `<zone>:common` (1 card), `<zone>:rare` (3 cards), or `<zone>` (Epic, 5 cards). The last keeps all legacy five-card packs intact without an inventory conversion. Only real catalog set codes and these canonical IDs are accepted. Player-facing names are always `Pack: <zone title>`; tier and size are separate labels.

`mode/packs2` (count/dust/shiny/tape zero) is written once, after flushing misses, before the first new tiered pack find. Replay persists `tieredPacks=true`. Earlier pack finds retain their original five-card meaning. After this marker, the find entry's `floor(hex2 / shinyOdds / 500) mod 100` selects Common for 0–69, Rare for 70–94, and Epic for 95–99. It uses the digits above the existing pack-find remainder. The pack find chance remains 1/500. The server checks both the pack find and its tier. Each pack draws its own size in consecutive tape entries from its zone, with the existing within-rarity weights, edition and shiny rules; a tier does not promise particular card rarities.

Trade-only keys `pack:<pack-ID>` are allowed in `tradeIn` and `tradeOut`. Their counts describe `state.packs[pack-ID]`, never card inventory; count changes by exactly one. They use the existing reciprocal identities, trade ID and matching process. Invalid zones, overspending, shiny/dust/tape fields, drops, crafting and recycling of pack keys are refused. The ordinary revisioned two-accept protocol handles one card or one pack on either side. The addon reserves the offered copy until trade completion/cancellation, including its cancellation wait, while unreserved spare packs remain openable.

Replay uses `packType` to remember the full ID of an opened pack, and `packLeft` is 1, 3 or 5. When a pack is received, it initializes `packOutputs[pack-ID]`, then records subsequent packCard counts of that type. Pending, unmatched, Casual-origin or otherwise tainted pack trades exclude those outputs for Ranked scoring. Maintenance traces taint from packs to their opened cards and subsequent trades; when an honest pending pair matches, its outputs count again. This deliberately over-excludes when found and traded packs of the same type are mixed. Casual packFind events also constitute unverified provenance, even if they never drop a card or are traded before opening. Local integrity checks still cover card counts and dust; server replay is authoritative for pack counts.

Specification 6 is required for `packs2`, tiered pack find/open IDs and pack trade keys; a collection that has used these cannot sync with an older companion. Legacy versions 2–5 remain replayable. See `satchel.json` and the Lua vectors for pack boundary/gift examples.

## Drop balance version 2

`mode/chase2` has count, dust, shiny and tape zero. It is valid only after `mode/chase1` and only once; it sets `balance=2`. From then on the chance of an attempt uses `dropProfile.rate2` where version 1 used `dropProfile.rate`; everything else (the style and its formulas, pack weights, crafting restrictions, edition and shiny draws) is unchanged. Events before `chase2` are checked at the version 1 rates, so every history written before this version replays exactly as it did. Miss counts carry over. The luck statistics (`balanceAttempts`, `balanceDrops`, `balanceReady`) start empty at `chase2`, so the first drop of each source afterwards is skipped and later cycles are compared against the new chances.

The catalog carries both: `dropProfile.rate` (version 1, never changed) and `dropProfile.rate2`. `rate2` is **four times `rate` for critters** (capped at 10000), **`round(rate x 1.2)` for ordinary cards** (the regular and uncommon tiers and chase cards on ordinary creatures), and **equal to `rate` for chase cards on limited sources** (bosses, rare spawns, gathering and epics, which use stacking). A critter's protection ramp moves with its rate: it is guaranteed on attempt `ceil(10000/rate2)`.

The add-on writes `chase1` (if the binder has not) and then `chase2` before its first roll after upgrading, after writing any run of misses at the old rates. A server must refuse an upload that contains `chase2`, or a binder already on generation 2, unless the upload's `specVersion` is at least 8 (`client_too_old`), including empty syncs. Vectors: `packages/shared/vectors/balance.json` (`balanced2`).

## Drop balance version 1

`mode/chase1` has count, dust, shiny and tape zero. It is recorded once before new balanced rolls or pack openings, after flushing any old miss run. It activates persistent `balance=1`; earlier events retain legacy rank rates and uniform within-rarity pack picks. Miss counts carry over. A new critter edition requires both `editions1` and `chase1`.

The catalog supplies each base card's `dropProfile`: integer hundredths-of-a-percent `rate`, `style` (`stack` or `chase`), integer `packWeight`, `tier` and `noCraft`. Variants inherit their source profile. Stack protection retains the existing `rate * (1 + misses * stackFactor)` formula. Chase protection stays at its base rate until `floor(0.75 * ceil(10000/rate))` misses, then rises linearly, rounded down, to 10000 on attempt `ceil(10000/rate)`. Its chance is `rate + floor((10000-rate) * (misses-start)/(limit-1-start))` in that final interval, clamped to 10000.

After activation, within-rarity pack selection uses each card's `packWeight`, in existing numeric-key order. The pool draw is `floor(hex2/shinyOdds) mod sum(weights)`; select the first cumulative weight above it. The rarity draw, pack-find odds, shiny and edition draws are unchanged. Cards with `noCraft=true` cannot be crafted after activation. There is no empty or synthetic event for these rules.

Replay accumulates `balanceAttempts` and `balanceDrops` by base source for post-marker Ranked misses/drops. The first cycle for each source may inherit legacy pity: skip it through its first drop, then set `balanceReady[source]=true` and count subsequent attempts and drops. Casual events do not enter these counters and remain ineligible for Ranked through their existing provenance rules. Statistical luck checks use those counters and the new profiles; old counters remain valid for legacy players. Counts, inventories, hashes and transferred card keys are retained. Versions 2–4 remain accepted for legacy events; version 5 is required for the new marker and critter editions.

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
| `kind` | string | One of `drop`, `craft`, `recycle`, `tradeIn`, `tradeOut`, `set`, `mode`, `miss`, `packFind`, `packOpen`, `packCard`. |
| `key` | string, not empty | The card key; for `set` the set code (for example `DM`); for `mode` `casual`, `ranked2` (or `ranked`, which only old history holds); for `packFind` and `packOpen` the zone (the set code). |
| `count` | integer, 0 or more | How many copies of that card the player owns after this event. 0 for `set` and `mode`. For `miss` it is the length of the run of misses instead (1 or more); no copies change. For `packFind` and `packOpen` it is the number of packs of that zone held after the event. |
| `dust` | integer, may be negative | Change in Binder Dust: plus for `recycle`, minus for `craft`, 0 otherwise. |
| `shiny` | 0 or 1 | 1 when this event produced the shiny copy of a card. |
| `tape` | integer, 0 or more | The ranked tape entry used, counting from 1; 0 when none was used. For a `miss` it is the last entry of the run; for `mode ranked2` it is the last entry used before it (0 for a new binder). For `packFind` it is the entry of the attempt that found the pack (it uses no entry of its own), for `packOpen` the last entry used before it, and for `packCard` the entry that chose the card. |
| `partner` | string, may be empty | For trades: the other player, as `name-realm` in lowercase, spaces removed. |
| `trade` | string, may be empty | For trades: the trade id both players share. |
| `char` | string, not empty | The acting character as `Name-Realm`, spaces removed from the realm. |
| `prev` | 32 hex characters | The `h` of the previous event; 32 zeros for `seq` 1. |
| `h` | 32 hex characters | This event's hash (Section 4). |

### 3.1 Meaning of each kind (checked by the server in Phase B)

The server replays the events from `seq` 1 and keeps a running count per card and a running dust balance. It rejects a batch that breaks any of these:

- `drop`: `count` is the previous count plus 1. `shiny` may be 1 only when no earlier event for that card had `shiny` 1: a card has at most one shiny copy, found by whichever drop rolls it first. In `ranked2` mode `tape` must be exactly one more than the last tape entry written down, so no attempt is left out. (In the old `ranked` mode it only had to rise; that mode is replayed from history but refused for new events.)
- `miss` (only in `ranked2`): a run of `count` attempts on one card that all missed, using the `count` tape entries that end at `tape`. `count` is at least 1 and `tape - count` is exactly the last tape entry written down. No copies change.
- `craft`: the previous count is 0 and `count` is 1; `dust` equals minus the craft cost of the card's rarity, from the catalog; `shiny` is 0.
- `recycle`: the previous count is at least 2, `count` is one less, and `dust` equals the recycle yield of the card's rarity.
- `tradeOut`: the previous count is at least 1 (any card in the binder can be traded, a last copy included) and `count` is one less. `tradeIn`: `count` is the previous count plus 1. Both need `partner` and `trade`.
  A gift uses exactly one `tradeOut` in the giver's history and one matching `tradeIn` in the recipient's history, with the same card, trade id and reciprocal player identities. There is no event for an empty offer. A two-way exchange has two such matched transfers. Gifts retain all existing matching, Casual-origin and scoring checks; the event format, hashes and specification version are unchanged.
- `set`: `key` is a set code and every card of that set is owned at that point.
- `packFind`: a pack of the zone `key` was found; `count` is the packs of that zone held afterwards. In `ranked2` its `tape` must be the entry of the last attempt written down (a `drop` or the end of a `miss` run), the same entry may not find two packs, and the zone must be the zone of the card that attempt was on, which cannot be a gathering node. In Casual `tape` is 0.
- `packOpen`: a pack of `key` is opened: the player must hold one, `count` is the packs held afterwards, and `tape` is the last entry used so far (0 in Casual). Exactly five `packCard` events must follow, with nothing between them.
- `packCard`: a card of the opened pack's zone, `count` one more than before, `shiny` as for a `drop`. In `ranked2` `tape` is one more than the last entry used; in Casual it is 0.
- `mode`: `key` is `casual`, `ranked2` or (history only) `ranked`. A `ranked2` event names in `tape` the last entry used so far. The first time it may be up to 2,000 past the last entry written down (for misses a binder kept before attempts were written down); every later time it must equal it, so entries cannot be skipped by leaving Ranked and coming back.
- The running dust balance never goes below 0.
- `t` never decreases from one event to the next.

In `ranked2` every attempt is on record, as a `drop` or inside a `miss` run. In Casual misses are not events; they are counted in the snapshot's `attempts` (Section 6).

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

A tape is a list of entries issued by the server, 16 hex characters each. Refills add 10,000 entries when 250 or fewer remain; installed companions already support this larger buffer. Existing issued ranges and positions remain valid. The server stores a commitment: the SHA-256 of all the entries joined by a line feed.

For each ranked roll the add-on takes the next unused entry (counting from 1):

- **Roll value** = the first 8 hex characters read as a number, modulo 10000, plus 1 (so 1 to 10000).
- **Drop** when the roll value is at most the chance of that attempt. The chance is the card's rate (in hundredths of a percent: 100 is 1%) plus `stackFactor` times the rate for each earlier attempt on that card since its last drop, up to 10000 (certain). A certain attempt needs no roll but still uses its entry. A drop starts the stack over. The server cannot see misses between two drops, so it checks that a drop whose roll is above the rate follows at least as many attempts as that roll needs (`attemptsNeeded`), and that the needs of all a card's ranked drops together never exceed its counted attempts.
- **Shiny** (only while the card has no shiny copy yet) when the next 8 hex characters read as a number, modulo the shiny odds, plus 1, equals 1.
- A roll uses its entry whether it wins or not, so `tape` in a drop event tells the server how many entries were spent before and including it.

The server knows every entry, so it can recheck each drop. Entries are never reused.

### 8.2 Card packs

Any attempt on a creature (not a gathering node) can find a pack: **1 in 500**. A pack holds **five cards from the zone it was found in**: the zone of the creature the attempt was on, as a set of the catalog. Both are decided by tape entries, so the server can recheck them. The Lua add-on, the server and the vectors (`packs.json`) must agree on the arithmetic below, which uses whole numbers only.

A tape entry's second half (8 hex characters, `hex2`) is used two ways that do not depend on each other: `hex2 mod shinyOdds` is the shiny remainder (section 8), and `floor(hex2 / shinyOdds)` is what packs use.

- **Finding a pack:** `(floor(hex2 / shinyOdds) mod 500) + 1 = 1`. It needs no entry of its own: it rides on the entry of the attempt, whether or not that attempt dropped its card, and is written as a `packFind` event with that attempt's `tape`.
- **Opening a pack** takes five consecutive entries, one for each card, at the positions after `packOpen`'s `tape`.
- **Choosing a card** from an entry: take the zone's cards by rarity, each rarity in order of card number, and leave out rarities the zone has none of. The rarities have weights Common 7000, Rare 2000, Epic 800, Legendary 200 (out of 10000 before leaving any out). With `total` the weights of the rarities that remain, the rarity is the first whose cumulative weight times 10000 is above `(roll - 1) * total`, where `roll` is the entry's roll (section 8). The card is number `floor(hex2 / shinyOdds) mod n` of that rarity's `n` cards. Creature zones have no Rare cards (only gathering nodes are Rare), so there the Rare share goes to the others.
- **Shiny:** exactly as for a drop: the card is shiny when it has no shiny copy yet and `hex2 mod shinyOdds` says so.

The server checks every `packFind` (the entry must say a pack was found) and every `packCard` (the card and its shiny flag must be exactly what the entry gives from the zone). Cards from Casual packs count as Casual drops. As for any ranked roll, a player who reads the tape ahead can choose which kills to spend on which entries, and when to open a pack; the small tape batches (section 8.1) bound that.

### 8.1 Ranked2: every attempt on record

Entering `ranked2` writes a `mode` event and starts every card's run of misses again from zero, so the server and the add-on agree on each card's chance. From then on every attempt is on record, in order: a drop is a `drop` event; consecutive misses on the **same card** are one `miss` event covering their entries; an attempt on another card, a drop, or a change of mode ends the run. The tape positions recorded therefore follow each other with no gap, which the rules in section 3.1 check without any secret.

The server then replays every attempt against its own entry, keeping each card's stack of misses: a **miss** needs a roll above the chance at that point (a roll that would have won means a drop was left out), a **drop** needs a roll at or below it, and a drop's shiny flag must match its entry while the card has no shiny copy. This replaces the older check, which could only compare totals. What the server still cannot see is **which card an entry was spent on**: a player who reads the entries ahead of time could spend a winning entry on the card they want. Two things bound that: the tape is issued in small batches, topped up only when an upload shows the last batch nearly used (at most 10,250 entries ahead of the last upload), and the luck checks still look at the totals.

## 9. Versioning and compatibility

- `specVersion` changes when anything in this document changes in a way an old implementation would get wrong. The server states the lowest version it accepts. Version 2 added the `miss` kind and the `ranked2` mode, and version 3 the three pack kinds; the chain and the hashed text did not change, so a version 1 chain continues under version 2, but new uploads must be in version 2 and any Ranked play must begin with a `ranked2` mode event.
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
- A player who edits the add-on can still choose which card to spend a tape entry on, and can read entries ahead of time (up to 10,250 at once). The server bounds this by issuing the tape in small batches, rate limits and the luck checks.
- A player can also end the game without it saving (killing the process) after seeing a result they do not like: the saved file then still holds the older state and the same entries. This cannot be seen from the ledger.
- A binder upgraded from schema 1 has cards the ledger never saw drop, so its events cannot account for them. Phase B must decide how the server treats such a binder (play Casual, or ranked from a fresh binder). Until then it is verified locally only.
- The 32-character hash is a truncation of SHA-256. It is plenty to catch edits and accidents; it is not meant to resist someone who controls both ends of the chain, which this design never claims to stop.
