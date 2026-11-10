// Statistical checks on a player's results (roadmap D1, D2). They never reject an upload: they raise flags for a
// person to review, and the worst one holds a player off the public ladder until reviewed. Starting thresholds,
// to be tuned in the beta. Rules version 1.
import type { Catalog, LedgerState } from "./shared.ts";

export const LUCK_REVIEW = 4; // -log10(p) at which a flag opens for review
export const LUCK_HOLD = 6; // -log10(p) at which the player is held off the ladder until reviewed
export const MAX_ATTEMPTS_PER_HOUR = 1200;
export const FAST_START_CARDS = 200; // more unique cards than this within the first hour of an account
const MIN_WINDOW_SECONDS = 600; // a rate is judged only over uploads at least this far apart

// The drops a card should give per attempt, and how much that varies, with the bad-luck guarantee in force. Without it
// a card would drop with probability `rate` each attempt; with it, the wait for a drop is capped at `limit` attempts.
// The wait T has mean m and variance v, and over n attempts the drop count is about normal with mean n/m and
// variance n*v/m^3 (renewal theory).
export function dropModel(rate: number, pityFactor: number): { perAttempt: number; variancePerAttempt: number } {
  const p = rate / 10000;
  if (p <= 0) return { perAttempt: 0, variancePerAttempt: 0 };
  const limit = pityFactor > 0 ? Math.ceil((pityFactor * 10000) / rate) : Infinity;
  const cap = Number.isFinite(limit) ? limit : 100_000; // without a guarantee the wait is effectively unbounded
  let mean = 0;
  let second = 0;
  let survive = 1;
  for (let k = 0; k < cap; k++) {
    mean += survive;
    second += (2 * k + 1) * survive;
    survive *= 1 - p;
    if (survive < 1e-15) break;
  }
  const variance = Math.max(second - mean * mean, 0);
  return { perAttempt: 1 / mean, variancePerAttempt: variance / (mean * mean * mean) };
}

// Upper tail of the standard normal distribution.
function normalTail(z: number): number {
  // Abramowitz and Stegun 7.1.26 for erfc, good to about 1e-7; the far tail uses the asymptotic form.
  if (z > 8) return Math.exp(-0.5 * z * z) / (z * Math.sqrt(2 * Math.PI));
  const x = Math.abs(z) / Math.SQRT2;
  const t = 1 / (1 + 0.3275911 * x);
  const poly = ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t;
  const half = 0.5 * poly * Math.exp(-x * x);
  return z >= 0 ? half : 1 - half;
}

// How lucky the player's drops are: -log10 of the chance of at least this many drops from this many attempts.
// 0 or less means ordinary luck; 4 means about 1 in 10,000. Uses lifetime attempts and the drops stored for each card.
export function luckScore(catalog: Catalog, attempts: Record<string, number>, drops: Record<string, number>): number {
  let mean = 0;
  let variance = 0;
  let observed = 0;
  for (const [key, count] of Object.entries(attempts)) {
    const card = catalog.cards[key];
    if (!card || count < 1) continue;
    const model = dropModel(catalog.rates[card.rank] ?? 0, catalog.pityFactor);
    mean += count * model.perAttempt;
    variance += count * model.variancePerAttempt;
  }
  for (const count of Object.values(drops)) observed += count;
  if (variance <= 0 || observed <= mean) return 0;
  // Continuity correction: "at least `observed`" starts half a drop below it.
  const z = (observed - 0.5 - mean) / Math.sqrt(variance);
  const tail = normalTail(z);
  return tail <= 0 ? 99 : Math.max(0, -Math.log10(tail));
}

export type Flag = { kind: string; notes: string };

// Everything the checks look at after an accepted upload.
export function integrityFlags(args: {
  catalog: Catalog; state: LedgerState; attempts: Record<string, number>; drops: Record<string, number>;
  tapeNextBefore: number; tapeNextNow: number; lastUploadAt: number | null; now: number; playerCreatedAt: number; openKinds: string[];
}): Flag[] {
  const flags: Flag[] = [];
  const open = new Set(args.openKinds);
  const luck = luckScore(args.catalog, args.attempts, args.drops);
  if (luck >= LUCK_HOLD && !open.has("luck-hold")) flags.push({ kind: "luck-hold", notes: `luck ${luck.toFixed(1)}` });
  else if (luck >= LUCK_REVIEW && !open.has("luck-review") && !open.has("luck-hold")) flags.push({ kind: "luck-review", notes: `luck ${luck.toFixed(1)}` });

  // Entries used per hour between two uploads: each attempt uses one entry.
  if (args.lastUploadAt !== null && args.now - args.lastUploadAt >= MIN_WINDOW_SECONDS && !open.has("rate")) {
    const perHour = ((args.tapeNextNow - args.tapeNextBefore) * 3600) / (args.now - args.lastUploadAt);
    if (perHour > MAX_ATTEMPTS_PER_HOUR) flags.push({ kind: "rate", notes: `${Math.round(perHour)} attempts an hour` });
  }
  const unique = Object.values(args.state.counts).filter((count) => count > 0).length;
  if (args.now - args.playerCreatedAt < 3600 && unique > FAST_START_CARDS && !open.has("fast-start")) {
    flags.push({ kind: "fast-start", notes: `${unique} cards within the first hour` });
  }
  return flags;
}
