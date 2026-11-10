// Rebuild everything that is derived from the stored batches (roadmap D8): each player's state, drops, trade halves,
// finished sets and score. The batches are the only source of truth; the rest can always be recomputed, which is how a
// change to a scoring weight or a rule (a new rules version) is applied, and how a bug in the derived data is repaired.
//
// A run handles one page of players and says where to carry on, so a big ladder is done in several short runs. A dry run
// reports what would change and writes nothing. A player whose stored history no longer passes the rules (because a rule
// was tightened) is reported and left as it is, never half rewritten.
import { dropCountsOf, tradeRowsOf } from "./derive.ts";
import { RULES_VERSION, scoreOf } from "./score.ts";
import { newState, replay } from "./shared.ts";
import type { Catalog } from "./shared.ts";
import type { RebuildStore } from "./store.ts";

export type RebuildReport = {
  checked: number;
  changed: { playerId: string; differences: string[] }[];
  failed: { playerId: string; rule: string; index: number }[];
  next: string | null; // carry on after this player id, or null when every player has been done
  dryRun: boolean;
};

export async function rebuild(
  deps: { rebuild: RebuildStore; catalog: Catalog },
  options: { after?: string | null; limit?: number; dryRun?: boolean; force?: boolean } = {},
): Promise<RebuildReport> {
  const limit = options.limit ?? 50;
  const ids = await deps.rebuild.playerIds(options.after ?? null, limit);
  const report: RebuildReport = { checked: 0, changed: [], failed: [], next: ids.length === limit ? (ids[ids.length - 1] as string) : null, dryRun: options.dryRun === true };
  for (const playerId of ids) {
    report.checked += 1;
    const batches = await deps.rebuild.batchesOf(playerId);
    const events = batches.flatMap((batch) => batch.events);
    const played = replay(events, deps.catalog, newState());
    if (!played.ok) {
      report.failed.push({ playerId, rule: played.rule, index: played.index });
      continue;
    }
    const received = new Map<number, number>(); // seq to the time of the batch that held it
    for (const batch of batches) for (const event of batch.events) received.set(event.seq, batch.receivedAt);
    const score = scoreOf(deps.catalog, played.state);
    const drops = dropCountsOf(events);
    const now = await deps.rebuild.derivedNow(playerId);
    const differences: string[] = [];
    if (!now || JSON.stringify(sorted(now.state)) !== JSON.stringify(sorted(played.state))) differences.push("state");
    if (!now || JSON.stringify(sorted(now.drops)) !== JSON.stringify(sorted(drops))) differences.push("drops");
    if (!now || now.score !== score.score) differences.push("score");
    if (differences.length === 0 && !options.force) continue;
    report.changed.push({ playerId, differences });
    if (report.dryRun) continue;
    await deps.rebuild.writeDerived(playerId, {
      state: played.state, drops, score, rulesVersion: RULES_VERSION,
      dropRows: events.filter((event) => event.kind === "drop"),
      trades: tradeRowsOf(events as unknown as Record<string, unknown>[]).map((row) => ({ ...row, receivedAt: received.get(row.seq) ?? 0 })),
      completions: events.filter((event) => event.kind === "set").map((event) => ({ setCode: event.key, t: event.t, receivedAt: received.get(event.seq) ?? 0 })),
    });
  }
  return report;
}

// Key order does not matter when comparing stored and rebuilt data.
function sorted(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sorted);
  if (typeof value === "object" && value !== null) return Object.fromEntries(Object.entries(value).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([key, entry]) => [key, sorted(entry)]));
  return value;
}
