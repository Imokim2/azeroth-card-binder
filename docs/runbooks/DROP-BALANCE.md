# Drop balance rollout

Prepared with the satchel rollout: addon 0.6.0, companion/server 0.4.0, ledger spec 6, catalog `5e7dcd9e5e29`. The original chase feature used spec 5; it was not included in the public 0.5.0 release.
No remote deployment or test installer is performed by preparing this change.

Deploy the matching server and distribute the matching addon and rebuilt companion together, following [the satchel rollout notes](SATCHEL.md). The new companion must use the new generated catalog. Old histories still replay using their original rates up to the once-only `mode/chase1` marker. Back up normal saved data before playtesting; do not reset a collection to upgrade it. No database migration is needed: the additional replay counters live in the existing JSON state.

After rollout, check health/catalog, release metadata, sign-in and a real Ranked sync. Kill and loot the same creature to confirm it gives only one attempt; check a critter with no loot, a gathering node, a boss, a pack opening and a trade of a critter edition. Check the normal UI has no rates or pity counter. `/acb diag` and `/acb log` retain effective odds for troubleshooting. On the studio, inspect Rabbit, Mouse, Deer and other face editions in game: model-specific framing may need adjustment.

`node tools/report-drop-balance.js` computes exact mean waits from survival probabilities, rather than sampling random outcomes. Initial catalog distribution:

| Group | Base cards | Median expected attempts | Median wait relative to previous rules |
|---|---:|---:|---:|
| Regular | 2,817 | 11.2 | 0.99x |
| Uncommon | 469 | 15.7 | 1.40x |
| Chase | 106 | 489.0 | 40.05x |
| Critter | 31 | 1,776.2 | 145.47x |

These are developer balance figures, not player-facing promises. Limited-opportunity chase cards retain immediate stacking; this is why the chase group spans a broad range of waits. Critters start at 0.02–0.05%, remain flat until the last quarter of their protection window, then ramp to a guarantee on attempt 2,000–5,000 depending on the card. The close-up edition replaces 25% of that source's successful drops, with its own inventory key. It is not an additional independent drop.

Statistical luck checks start after the first post-marker Ranked drop per source, avoiding false flags from inherited pity. Casual remains excluded from Ranked by provenance. Real addon/tape integration tests cover uploads before, during and after the marker, and splitting a weighted pack across batches.

## Second generation of rates (mode/chase2, ledger spec 8)

After the first public release, drop rates were raised: **critters four times as likely, other ordinary cards 20% more likely, chase cards on limited sources (bosses, rare spawns, gathering, epics) unchanged.** A binder does not switch silently: the add-on writes `mode/chase2` once (after `chase1`, and after flushing any run of misses at the old rates), and the server replays every event at the rates in force when it was rolled. See [the ledger spec](../LEDGER-SPEC.md), "Drop balance version 2".

| Median expected attempts | Before | After |
|---|---:|---:|
| Regular | 11.2 | 10.2 |
| Uncommon | 15.7 | 14.3 |
| Chase on an ordinary creature | 670 | 537 |
| Critter | 1,776 | 449 |

`node tools/report-drop-balance.js` prints both generations.

Rollout: this needs add-on, companion (spec 8) and server together, like `chase1` did. The server refuses a spec 7 or older upload from a binder on generation 2 (`client_too_old`), so raise `MIN_CLIENT` and `MIN_ADDON` to the release that carries it, and publish the signed companion before the server so players can update. Existing Ranked histories are unaffected; an old add-on's drops are checked at the old rates and a new add-on's at the new ones. Casual play is not checked but uses the same rates.

## The launch collection (mode/launch1, ledger spec 9)

Half the cards are held back for seasons: see [the proposal](../proposals/SMALLER-LAUNCH-COLLECTION.md), [SEASONS.md](../SEASONS.md) and [the ledger spec](../LEDGER-SPEC.md), "Launch collection". Rollout is the same shape as `chase2`: add-on, companion (spec 9) and server together, minimum versions raised, signed companion first. Nothing is deleted: every card stays in the catalog, and every binder keeps and shows the copies it owns.

- **The list** is generated: `node tools/launch-collection.js --write` rewrites `AzerothCardBinder/LaunchCollection.lua` and the review files in `docs/seasons/`; a test keeps them equal to the rule. Change the rule, or the catalog, and regenerate.
- **Releasing cards**: schedule a season that features them (`node tools/seasons.js schedule ...`). From its start the cards drop, appear in packs and can be crafted, for everyone and for good. Nothing else releases a card.
- **Check after deploying**: a Ranked sync from a new add-on is accepted; a held-back creature gives no card and no attempt in game; the binder shows only launch cards on a fresh binder and keeps owned copies; a pack never holds a held-back card; with a scheduled season, the card drops and the server accepts it.
- **Players without the companion** only see launch cards until it syncs, because the release list arrives in Data/Sync.lua.
