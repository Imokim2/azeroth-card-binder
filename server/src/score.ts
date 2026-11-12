// The score (roadmap decision D7). Kept in tenths of a point so every value is a whole number: a card is worth
// its rarity's points; a shiny adds half again; finishing a set adds a tenth of that set's card points.
// Rules version 2 groups collectible editions under their base creature without changing rarity weights.
import type { Catalog, LedgerState } from "./shared.ts";
import { baseCardKey, editionKeys } from "./shared.ts";

export const RULES_VERSION = 2;
const POINTS: Record<string, number> = { common: 1, rare: 2, epic: 5, legendary: 10 };

export type Score = { score: number; uniqueCards: number; setsDone: number };

// `excluded` is the copies of each card that came from trades the other player never confirmed (roadmap C5): they do
// not count. A card whose copies were all excluded is not owned for scoring, and a set whose finishing rested on such
// a card is not done.
export function scoreOf(catalog: Catalog, state: LedgerState, excluded: Record<string, number> = {}): Score {
  const effective = { ...excluded };
  for (const [zone, outputs] of Object.entries(state.packOutputs || {})) {
    if ((excluded[`pack:${zone}`] || 0) > 0) for (const [key, count] of Object.entries(outputs)) effective[key] = (effective[key] || 0) + count;
  }
  let tenths = 0;
  let uniqueCards = 0;
  const owned = (key: string): number => (state.counts[key] ?? 0) - (effective[key] ?? 0);
  const seen = new Set<string>();
  for (const key of Object.keys(state.counts)) {
    const card = catalog.cards[key];
    if (!card || owned(key) < 1) continue;
    const base = baseCardKey(catalog, key);
    if (seen.has(base)) continue;
    seen.add(base);
    const points = POINTS[card.rarity] ?? 0;
    uniqueCards += 1;
    tenths += points * 10;
    if (editionKeys(catalog, base).some((edition) => owned(edition) > 0 && state.shiny[edition])) tenths += points * 5;
  }
  let setsDone = 0;
  for (const set of catalog.sets) {
    // A finished set stays finished even if a card was traded away later; only a card that rests on copies from
    // unconfirmed trades takes the bonus away.
    if (!state.sets[set.code] || set.cards.some((key) => {
      const family = editionKeys(catalog, key);
      return family.some((edition) => (effective[edition] ?? 0) > 0) && family.every((edition) => owned(edition) < 1);
    })) continue;
    setsDone += 1;
    // A tenth of the set's points, in tenths of a point, is the set's points.
    for (const key of set.cards) tenths += POINTS[catalog.cards[key]?.rarity ?? ""] ?? 0;
  }
  return { score: tenths, uniqueCards, setsDone };
}
