// The score (roadmap decision D7). Kept in tenths of a point so every value is a whole number: a card is worth
// its rarity's points; a shiny adds half again; finishing a set adds a tenth of that set's card points.
// Rules version 1. A change to any weight is a new RULES_VERSION and a recompute from the stored ledgers, never an edit.
import type { Catalog, LedgerState } from "./shared.ts";

export const RULES_VERSION = 1;
const POINTS: Record<string, number> = { common: 1, rare: 2, epic: 5, legendary: 10 };

export type Score = { score: number; uniqueCards: number; setsDone: number };

export function scoreOf(catalog: Catalog, state: LedgerState): Score {
  let tenths = 0;
  let uniqueCards = 0;
  for (const [key, count] of Object.entries(state.counts)) {
    const card = catalog.cards[key];
    if (!card || count < 1) continue;
    const points = POINTS[card.rarity] ?? 0;
    uniqueCards += 1;
    tenths += points * 10;
    if (state.shiny[key]) tenths += points * 5;
  }
  let setsDone = 0;
  for (const set of catalog.sets) {
    if (!state.sets[set.code]) continue;
    setsDone += 1;
    // A tenth of the set's points, in tenths of a point, is the set's points.
    for (const key of set.cards) tenths += POINTS[catalog.cards[key]?.rarity ?? ""] ?? 0;
  }
  return { score: tenths, uniqueCards, setsDone };
}
