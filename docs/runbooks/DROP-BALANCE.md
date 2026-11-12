# Drop balance rollout

Prepared source: addon 0.5.0, companion/server 0.3.0, ledger spec 5, catalog `5e7dcd9e5e29`.
No remote deployment or test installer is performed by preparing this change.

Deploy the matching server and distribute the matching addon and rebuilt companion together. The server configuration announces the matching versions and requires companion 0.3.0; the new companion must use the new generated catalog. Old histories still replay using their original rates up to the once-only `mode/chase1` marker. Back up normal saved data before playtesting; do not reset a collection to upgrade it. No database migration is needed: the additional replay counters live in the existing JSON state.

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
