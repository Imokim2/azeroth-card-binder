// The stacking drop chance (docs/LEDGER-SPEC.md, section 8). Every attempt that misses raises the chance of the next
// by the card's listed rate times the stack factor, up to certain, and a drop starts it over. Chances are in hundredths
// of a percent, so 10000 is certain. This must agree with ACB.chanceAfter in the add-on, which the shared rules
// vectors check.

// The chance of an attempt that follows `misses` attempts without a drop.
export function chanceAfter(rate: number, misses: number, factor: number): number {
  return Math.min(10000, rate + rate * factor * misses);
}

// The fewest attempts since the last drop (counting the one that dropped) that make `roll` a winning roll, or
// Infinity when no number of attempts could. A drop with a roll of 3% on a 1% card must follow at least two misses.
export function attemptsNeeded(roll: number, rate: number, factor: number): number {
  if (roll <= rate) return 1;
  if (rate <= 0 || factor <= 0) return Infinity;
  let attempts = 1 + Math.ceil((roll - rate) / (rate * factor));
  // Floating point can leave the estimate one off for fractional factors; settle it against the real rule.
  while (attempts > 1 && chanceAfter(rate, attempts - 2, factor) >= roll) attempts--;
  while (chanceAfter(rate, attempts - 1, factor) < roll) attempts++;
  return attempts;
}
