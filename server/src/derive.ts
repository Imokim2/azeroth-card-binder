// What can be worked out from a player's events alone: the trade halves, the finished sets and the drops per card.
// Used when an upload is stored and again when everything derived is rebuilt from the stored batches (roadmap D8), so the
// two can never disagree about what an event means.
import { peerName } from "./names.ts";
import type { TradeRow } from "./store.ts";

type EventLike = Record<string, unknown>;

export function tradeRowsOf(events: EventLike[]): TradeRow[] {
  const rows: TradeRow[] = [];
  for (const event of events) {
    const kind = event["kind"];
    if (kind !== "tradeIn" && kind !== "tradeOut") continue;
    rows.push({
      seq: Number(event["seq"]), tradeId: String(event["trade"]), direction: kind === "tradeIn" ? "in" : "out", key: String(event["key"]),
      char: peerName(String(event["char"])), partner: String(event["partner"]), t: Number(event["t"]),
    });
  }
  return rows;
}

export function completionsOf(events: EventLike[]): { setCode: string; t: number }[] {
  return events.filter((event) => event["kind"] === "set").map((event) => ({ setCode: String(event["key"]), t: Number(event["t"]) }));
}

// Drops rolled in Casual mode: the add-on writes tape position 0 for them, and a Ranked drop always has a position.
export function casualDropsOf(events: EventLike[]): number {
  return events.filter((event) => (event["kind"] === "drop" || event["kind"] === "packCard" || event["kind"] === "packFind") && Number(event["tape"]) === 0).length;
}

export function dropCountsOf(events: EventLike[], start: Record<string, number> = {}): Record<string, number> {
  const drops = { ...start };
  for (const event of events) if (event["kind"] === "drop") drops[String(event["key"])] = (drops[String(event["key"])] ?? 0) + 1;
  return drops;
}
