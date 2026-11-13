# Proposal: a smaller launch collection, with the rest as season targets

**Status: agreed (Harry, confirmed with Ollie, 13 Nov 2026). Built on `feat/drop-rates-v2` (the rates) and `feat/seasonal-availability` (the split and its rules); not released.** After a season ends its cards stay available for good, and pages are finished by launch cards alone (season cards are extras). It supports the open question in [SEASONS.md](../SEASONS.md): "The retirement list and whether a returning card stays available after its season still need to be agreed."

## The idea

- Launch with **half** the base cards (1,711 of 3,423) and hold the other half (1,712) back as targets for seasons.
- **Every elite, rare-elite and boss card stays**, so dungeons and raids launch whole. So do all critters and all gathering nodes.
- The held-back half is ordinary-creature cards: mostly normal-rank creatures and rare spawns, plus (in the default draft) the chase cards that sit on ordinary creatures.
- Raise drop rates a little for cards and a lot for critters.

## The draft split

Regenerate or check it any time with `node tools/launch-collection.js` (`--write` rewrites the two files below; `--chase keep` keeps the chase cards on ordinary creatures at launch instead).

- [`docs/seasons/launch-collection-draft.csv`](../seasons/launch-collection-draft.csv): every base card with its page, rarity, rank, tier and the decision (`launch` or `seasons`). Open it in a spreadsheet to review.
- [`docs/seasons/launch-collection-draft.json`](../seasons/launch-collection-draft.json): the same as keys, with counts per page.

The rule is deterministic: always keep elites, rare-elites, bosses, critters and gathering nodes; hold back chase cards on ordinary creatures; then keep just enough of the remaining ordinary-creature cards to make exactly half, spread over the pages in proportion to each page's size, choosing within a page by SHA-256 of `launch-v1|<card key>`. A test (`tests/launch-collection.test.js`) keeps the committed draft equal to what the rule produces from the current catalog.

| | At launch | Held for seasons |
|---|---:|---:|
| Elite (not boss) | 979 | 0 |
| Boss | 78 | 0 |
| Rare-elite | 94 | 0 |
| Critter | 31 | 0 |
| Gathering node | 39 | 0 |
| Normal-rank creature | 437 | 1,460 |
| Rare spawn | 53 | 192 |
| Chase on an ordinary creature | 0 | 60 |
| **Total** | **1,711** | **1,712** |

By kind of page: zones keep 930 of 2,535 cards, dungeons 511 of 573, raids 222 of 241, battlegrounds 9 of 35, professions all 39.

**What this does to the pages.** Because elites and bosses all stay, the leveling zones (which are mostly normal creatures) lose the most: Teldrassil keeps 14 of 61, Ashenvale 26 of 102, Duskwood 12 of 48, Arathi Basin 3 of 14, Deadwind Pass 2 of 9. Dungeons and raids are nearly untouched (Molten Core, Ragefire Chasm, Stormwind Stockade and Onyxia's Lair keep every card). Every page keeps at least one card at launch. Decide whether sparse zone pages are fine, or whether some small pages should be held back whole or kept whole.

## The rate change (draft numbers)

Rates are authored in `AzerothCardBinder/DropRates.lua` (and flow into `packages/shared/catalog.json`).

| Card | Today | Draft | Effect |
|---|---|---|---|
| Regular and uncommon | rate = `floor(rank rate x scale / 100)`, scale 80 to 125 (regular), 35 to 65 (uncommon) | **x1.2** (a "smidge") | median attempts 11.2 to 10.2 (regular), 15.7 to 14.3 (uncommon) |
| Chase on an ordinary creature | rate 5 to 12 (0.05% to 0.12%) | **x1.2** | median attempts 670 to 537 |
| Critter | rate `2 + detail % 4` (0.02% to 0.05%), guaranteed by attempt 2,000 to 5,000 | **x4**: rate 8 to 20 (0.08% to 0.2%), guaranteed by attempt 500 to 1,250 | median attempts 1,776 to 449 |

Because the stacking bonus per miss already does most of the work, **a 20% rate rise gives only about 9% fewer attempts.** If a bigger effect is wanted, x1.5 on cards gives about 20% fewer attempts (regular median 9.0).

## Modelled effect on the time to finish

From a model of the real catalog and drop rules with **assumed** play speeds (not measured play; the model script is not in the repo). "Focused" means routed farming at about 400 kills an hour in a zone; relaxed is about half that, hardcore about 1.5 times.

Hours to finish the launch collection (chase cards on ordinary creatures held back):

| Rates | Focused | Relaxed | Hardcore |
|---|---:|---:|---:|
| Whole 3,423-card collection today, for comparison | about 1,265 h | about 2,290 h | about 840 h |
| Launch half, rates unchanged | about 870 h | | |
| Launch half, cards x1.2, critters x4 | about 800 h | about 1,270 h | about 550 h |
| Launch half, cards x1.5, critters x10 | about 710 h | | |

- 90% of the launch collection is done in about 360 focused hours; the last 10% takes the rest.
- **Raids are the biggest cost.** About 440 of the 800 focused hours (about 110 raid clears, roughly 37 weeks at three clears a week) are raids, because every raid elite and boss stays. Drop rates barely move this. Easing raid pace, or holding back a raid, would.
- Seasons drawn from the held-back half are cheap: a focused player needs about 11 hours for 12 cards or 23 hours for 24 cards drawn from anywhere, and about 6 hours or 9 hours when the cards come from two pages. A trade can satisfy a slot, which the model ignores, so real seasons should be quicker.
- With 24-card seasons the held-back half is 72 seasons; at a monthly cadence that is six years of content.

## What has to be true before this ships

Taken from [SEASONS.md](../SEASONS.md), [LEDGER-SPEC.md](../LEDGER-SPEC.md) and [DROP-BALANCE.md](../runbooks/DROP-BALANCE.md):

1. **Rates are part of the rules.** The server replays every Ranked history against the catalog's rates, so editing `DropRates.lua` alone would make existing histories fail. A rate change needs its own once-only marker (like `mode/chase1`) so old events replay at their old rates, a new catalog version and regenerated test vectors, shipped to the add-on, server and companion together. The earlier the better: fewer Ranked histories exist now than there will be later.
2. **Stable identities.** Hiding an unowned, inactive card or switching off its live drop source must never remove an owned copy, its editions, its ledger history or its trades. Nothing is deleted from `catalog.json`.
3. **One availability policy, enforced twice.** The add-on and the server must agree on whether a held-back card can drop, be found in a pack, be traded or be crafted before its season. A returning card keeps its identity and still needs a fresh acquisition to count for its season.
4. **Pack pools, set completion and rewards.** Pack draws, "page complete", set titles, the first-to-finish feed and the leaderboard's card and set counts all read the catalog's card lists, so each needs a decision (for example, does a page count as complete with only its launch cards?).
5. **Existing players.** Anyone who already owns a held-back card keeps it. Decide how their binder pages show it.

## Open questions

- Chase cards on ordinary creatures: hold back for seasons (the default draft; launch about 800 hours) or keep at launch (about 890 hours)?
- Should a card stay available after its season ends?
- Are sparse leveling-zone pages acceptable, or should some pages be held back or kept whole?
- How big is "a smidge" (x1.1, x1.2 or x1.5) and "a lot" for critters (x3, x4 or x10)?
- Should some raid trash or a whole raid move to seasons to shorten the launch collection?
- Season size and cadence: drawing a season from one or two pages keeps it cheap; scattered seasons cost about twice as much.
