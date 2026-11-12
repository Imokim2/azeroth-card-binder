// Statistical checks on a player's results (roadmap D1, D2). They never reject an upload: they raise flags for a
// person to review, and the worst one holds a player off the public ladder until reviewed. Starting thresholds,
// to be tuned in the beta. Rules version 1.
import type { Catalog, LedgerState } from "./shared.ts";
import { baseCardKey } from "./shared.ts";
import { profileChance, profileFor } from "../../packages/shared/src/drops.js";

export const LUCK_REVIEW = 4; // -log10(p) at which a flag opens for review
export const LUCK_HOLD = 6; // -log10(p) at which the player is held off the ladder until reviewed
export const MAX_ATTEMPTS_PER_HOUR = 1200;
export const FAST_START_CARDS = 200; // more unique cards than this within the first hour of an account
const MIN_WINDOW_SECONDS = 600; // a rate is judged only over uploads at least this far apart

// The drops a card should give per attempt, and how much that varies, with the stacking chance in force: attempt k
// after a drop wins with probability chanceAfter(rate, k - 1). Without a stack a card would drop with probability
// `rate` each attempt. The wait T for a drop has mean m and variance v, and over n attempts the drop count is about
// normal with mean n/m and variance n*v/m^3 (renewal theory).
const models = new Map<string, { perAttempt: number; variancePerAttempt: number }>();
export function dropModel(rate: number, stackFactor: number, style = "stack"): { perAttempt: number; variancePerAttempt: number } {
  const key = `${rate}|${stackFactor}|${style}`;
  const cached = models.get(key);
  if (cached) return cached;
  if (rate <= 0) return { perAttempt: 0, variancePerAttempt: 0 };
  let mean = 0;
  let second = 0;
  let survive = 1; // the chance that the wait is longer than k attempts
  for (let k = 0; k < 1_000_000; k++) {
    mean += survive;
    second += (2 * k + 1) * survive;
    survive *= 1 - profileChance({ rate, style }, k, stackFactor) / 10000;
    if (survive < 1e-15) break;
  }
  const variance = Math.max(second - mean * mean, 0);
  const model = { perAttempt: 1 / mean, variancePerAttempt: variance / (mean * mean * mean) };
  if (models.size >= 2048) models.clear();
  models.set(key, model);
  return model;
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
export function luckScore(catalog: Catalog, attempts: Record<string, number>, drops: Record<string, number>, balanced = false): number {
  let mean = 0;
  let variance = 0;
  let observed = 0;
  for (const [key, count] of Object.entries(attempts)) {
    const card = catalog.cards[key];
    if (!card || count < 1) continue;
    const profile = profileFor(catalog, key, balanced);
    const model = dropModel(profile.rate, catalog.stackFactor, profile.style);
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
  tapeNextBefore: number; tapeNextNow: number; lastUploadAt: number | null; now: number; playerCreatedAt: number; openKinds: string[]; clearedLuck?: number;
}): Flag[] {
  const flags: Flag[] = [];
  const open = new Set(args.openKinds);
  const balanced = args.state.balance === 1;
  const luck = luckScore(args.catalog, balanced ? args.state.balanceAttempts || {} : args.attempts,
    balanced ? args.state.balanceDrops || {} : args.drops, balanced);
  // Luck a reviewer has already cleared is not flagged again until it grows by two more orders of magnitude.
  const worth = luck >= (args.clearedLuck ?? 0) + (args.clearedLuck ? 2 : 0);
  if (luck >= LUCK_HOLD && worth && !open.has("luck-hold")) flags.push({ kind: "luck-hold", notes: `luck ${luck.toFixed(1)}` });
  else if (luck >= LUCK_REVIEW && worth && !open.has("luck-review") && !open.has("luck-hold")) flags.push({ kind: "luck-review", notes: `luck ${luck.toFixed(1)}` });

  // Entries used per hour between two uploads: each attempt uses one entry.
  if (args.lastUploadAt !== null && args.now - args.lastUploadAt >= MIN_WINDOW_SECONDS && !open.has("rate")) {
    const perHour = ((args.tapeNextNow - args.tapeNextBefore) * 3600) / (args.now - args.lastUploadAt);
    if (perHour > MAX_ATTEMPTS_PER_HOUR) flags.push({ kind: "rate", notes: `${Math.round(perHour)} attempts an hour` });
  }
  const unique = new Set(Object.entries(args.state.counts).filter(([, count]) => count > 0).map(([key]) => baseCardKey(args.catalog, key))).size;
  if (args.now - args.playerCreatedAt < 3600 && unique > FAST_START_CARDS && !open.has("fast-start")) {
    flags.push({ kind: "fast-start", notes: `${unique} cards within the first hour` });
  }
  return flags;
}
