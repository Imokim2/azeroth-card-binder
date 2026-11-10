// Checking a chain of ledger events (docs/LEDGER-SPEC.md, sections 3 to 5). This is the server's own
// implementation of what packages/shared/src/ledger.js does; both must give the results in the shared vectors.
import { sha256Hex } from "../../packages/shared/src/crypto.ts";

export const GENESIS = "0".repeat(32);
const KINDS = ["drop", "craft", "recycle", "tradeIn", "tradeOut", "set", "mode"];
const STRING_FIELDS = ["kind", "key", "partner", "trade", "char", "prev"] as const;

export type LedgerEvent = {
  seq: number; t: number; kind: string; key: string; count: number; dust: number; shiny: number; tape: number;
  partner: string; trade: string; char: string; prev: string; h: string;
};
export type Head = { seq: number; hash: string };
export type ChainError = "replay" | "gap" | "bad-field" | "bad-prev" | "bad-hash";
export type ChainResult = { ok: true; head: Head } | { ok: false; error: ChainError; index: number };

const isInt = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value);

// The first field of an event that breaks the rules of sections 2 and 3, or null. The input is untrusted JSON.
export function badField(event: Record<string, unknown>): string | null {
  const { seq, t, kind, count, dust, shiny, tape } = event;
  if (!isInt(seq) || seq < 1) return "seq";
  if (!isInt(t) || t < 0) return "t";
  if (typeof kind !== "string" || !KINDS.includes(kind)) return "kind";
  if (!isInt(count) || count < 0) return "count";
  if (!isInt(dust)) return "dust";
  if (shiny !== 0 && shiny !== 1) return "shiny";
  if (!isInt(tape) || tape < 0) return "tape";
  for (const name of STRING_FIELDS) {
    const value = event[name];
    if (typeof value !== "string" || /[|\r\n]/.test(value)) return name;
  }
  if (event["key"] === "") return "key";
  if (event["char"] === "") return "char";
  if (!/^[0-9a-f]{32}$/.test(event["prev"] as string)) return "prev";
  return null;
}

export function eventText(event: LedgerEvent): string {
  return [event.seq, event.t, event.kind, event.key, event.count, event.dust, event.shiny, event.tape, event.partner,
    event.trade, event.char, event.prev].join("|");
}

export async function eventHash(event: LedgerEvent): Promise<string> {
  return (await sha256Hex(eventText(event))).slice(0, 32);
}

// Check events in order against the last stored event (or the start of a new chain). The first failure stops it.
export async function checkChain(events: Record<string, unknown>[], head: Head = { seq: 0, hash: GENESIS }): Promise<ChainResult> {
  let expected = head.seq + 1;
  let previous = head.hash;
  for (let index = 0; index < events.length; index++) {
    const event = events[index];
    if (typeof event !== "object" || event === null) return { ok: false, error: "bad-field", index };
    const seq = event["seq"];
    if (isInt(seq) && seq < expected) return { ok: false, error: "replay", index };
    if (seq !== expected) return { ok: false, error: "gap", index };
    if (badField(event) !== null) return { ok: false, error: "bad-field", index };
    if (event["prev"] !== previous) return { ok: false, error: "bad-prev", index };
    const typed = event as unknown as LedgerEvent;
    if (typed.h !== (await eventHash(typed))) return { ok: false, error: "bad-hash", index };
    expected = typed.seq + 1;
    previous = typed.h;
  }
  return { ok: true, head: { seq: expected - 1, hash: previous } };
}
