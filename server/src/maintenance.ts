// The work that happens on a timer rather than in answer to a request (roadmap C5): matching the two halves of trades,
// and writing off halves whose partner never confirmed them. Run hourly by the Worker's scheduled handler.
import { newId } from "../../packages/shared/src/crypto.ts";
import { scoreOf } from "./score.ts";
import { computeTaint } from "./taint.ts";
import type { Catalog } from "./shared.ts";
import type { IngestStore, TradeStore } from "./store.ts";

export const TRADE_GRACE_SECONDS = 7 * 24 * 3600;

export async function runMaintenance(deps: { ingest: IngestStore; trades: TradeStore; catalog: Catalog; now: () => number }): Promise<{ matchedBack: number; unmatched: number }> {
  const now = deps.now();
  const affected = new Set<string>(await deps.trades.matchOpen());
  const matchedBack = affected.size;
  // Copies that came from Casual play, however many trades ago, do not count; that can change after a trade was recorded.
  const graph = await deps.trades.tradeGraph();
  for (const playerId of await deps.trades.replaceTaint(computeTaint(graph.halves, graph.casualPlayers, graph.outputs))) affected.add(playerId);
  // A newly matched pack may already have been opened; refresh its owner's score too.
  for (const output of graph.outputs || []) affected.add(output.playerId);
  const expired = await deps.trades.expire(now - TRADE_GRACE_SECONDS);
  const counts = new Map<string, { in: number; out: number }>();
  const missing = new Map<string, number>(); // partners who uploaded since, and still lack their half of a trade
  for (const row of expired) {
    affected.add(row.playerId);
    if (row.partnerUploadedSince !== null) {
      // The partner has played and uploaded since the trade and never recorded their half: the missing half is theirs. This
      // is how someone who takes a card without recording what they gave shows up, rather than the person they took it from.
      missing.set(row.partnerUploadedSince, (missing.get(row.partnerUploadedSince) ?? 0) + 1);
      continue;
    }
    const entry = counts.get(row.playerId) ?? { in: 0, out: 0 };
    entry[row.direction] += 1;
    counts.set(row.playerId, entry);
  }
  // A trade half with no other half after a week is flagged for a person to look at, and what it brought in stops counting.
  for (const [playerId, entry] of counts) {
    await deps.trades.addFlag(playerId, { id: newId(now * 1000), kind: "trade-unmatched", notes: `${entry.in} received and ${entry.out} given with no matching trade from the partner` }, now);
  }
  for (const [playerId, count] of missing) {
    await deps.trades.addFlag(playerId, { id: newId(now * 1000), kind: "trade-half-missing", notes: `${count} trade half(s) from partners that this player's uploads never matched` }, now);
  }
  for (const playerId of affected) {
    const stored = await deps.ingest.load(playerId);
    await deps.trades.setScore(playerId, scoreOf(deps.catalog, stored.state, await deps.trades.excluded(playerId)));
  }
  return { matchedBack, unmatched: expired.length };
}
