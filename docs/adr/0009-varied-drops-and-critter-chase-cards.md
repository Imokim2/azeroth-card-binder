# 0009: Varied drops and critter chase cards

Accepted 12 November 2026.

Assign stable per-card profiles to the whole catalog. Most cards retain fast stacking protection and rates near their rank baseline. A smaller uncommon group is slower. Three percent of ordinary sources become chase cards with a flat early chance and a late protection ramp. Bosses, rare spawns and gathering retain immediate stacking because opportunities are less frequent. Curated critters are exceptionally rare and gain collectible face-close-up editions.

Hide exact odds, miss counts and guarantees from ordinary binder pages and tooltips. Keep source information, ownership and broad discovery descriptions. Diagnostics and developer reports retain the numbers. Client code cannot make published addon odds secret; this is a presentation decision.

Chase cards cannot be crafted, and packs assign them smaller per-card weights. Both restrictions activate with the new rules; old events retain their old meaning. Keys and existing collections remain intact.

Ledger specification 5 adds a `mode/chase1` marker using existing fields and hashes. Replay persists the policy across batches and rebuilds. Historical events retain rank rates and uniform within-rarity pack selection. New events use per-card profiles, weighted packs and crafting restrictions. Ranked tape checks implement both eras. Integrity checks use post-marker ranked attempt/drop counters so earlier easy critter drops cannot falsely flag an honest collection. Existing miss counts carry over at activation.

The addon, companion catalog and server must be updated together. Live deployment is a separate coordinated rollout. Simulate the distribution before release; economy pacing and critter portrait framing require playtesting.
