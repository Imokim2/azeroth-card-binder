// The work that happens on a timer rather than in answer to a request (roadmap C5): matching the two halves of trades,
// and writing off halves whose partner never confirmed them. Run hourly by the Worker's scheduled handler.
import { newId } from "../../packages/shared/src/crypto.ts";
import { scoreOf } from "./score.ts";
import type { Catalog } from "./shared.ts";
import type { IngestStore, TradeStore } from "./store.ts";

export const TRADE_GRACE_SECONDS = 7 * 24 * 3600;

export async function runMaintenance(deps: { ingest: IngestStore; trades: TradeStore; catalog: Catalog; now: () => number }): Promise<{ matchedBack: number; unmatched: number }> {
  const now = deps.now();
  const affected = new Set<string>(await deps.trades.matchOpen());
  const matchedBack = affected.size;
  const expired = await deps.trades.expire(now - TRADE_GRACE_SECONDS);
  const counts = new Map<string, { in: number; out: number }>();
  for (const row of expired) {
    affected.add(row.playerId);
    const entry = counts.get(row.playerId) ?? { in: 0, out: 0 };
    entry[row.direction] += 1;
    counts.set(row.playerId, entry);
  }
  // A trade half with no other half after a week is flagged for a person to look at, and what it brought in stops counting.
  for (const [playerId, entry] of counts) {
    await deps.trades.addFlag(playerId, { id: newId(now * 1000), kind: "trade-unmatched", notes: `${entry.in} received and ${entry.out} given with no matching trade from the partner` }, now);
  }
  for (const playerId of affected) {
    const stored = await deps.ingest.load(playerId);
    await deps.trades.setScore(playerId, scoreOf(deps.catalog, stored.state, await deps.trades.excluded(playerId)));
  }
  return { matchedBack, unmatched: expired.length };
}
