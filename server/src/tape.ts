// The roll tape (docs/LEDGER-SPEC.md, section 8). Each entry is 16 hex characters derived from a server secret, the
// player and the entry's position, so nothing needs storing to recompute any entry later, and a player cannot guess
// an entry they have not been given. Roll and shiny values follow the spec and the shared vectors exactly.
import { sha256Hex, toHex } from "../../packages/shared/src/crypto.ts";
import type { LedgerEvent } from "./ledger.ts";
import type { Catalog, LedgerState } from "./shared.ts";
import { attemptsNeeded } from "./stack.ts";

export const TAPE_SIZE = 10_000; // entries added at each refill
export const REFILL_BELOW = 2_000; // a refill happens when this few unused entries remain

const encoder = new TextEncoder();

export type TapeKey = Awaited<ReturnType<typeof crypto.subtle.importKey>>;

export async function tapeKey(secret: string): Promise<TapeKey> {
  return crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
}

// The name a player's tape is derived under: their id, and after each new binder the id with the epoch added, so a
// new binder never replays the roll values of an old one.
export const tapeOwner = (player: { id: string; epoch: number }): string => (player.epoch > 0 ? `${player.id}.${player.epoch}` : player.id);

// Entry number `index` (from 1) of this player's tape.
export async function tapeEntry(key: TapeKey, playerId: string, index: number): Promise<string> {
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(`${playerId}|${index}`));
  return toHex(new Uint8Array(mac)).slice(0, 16);
}

export const rollValue = (entry: string): number => (parseInt(entry.slice(0, 8), 16) % 10000) + 1;
export const shinyValue = (entry: string, odds: number): number => (parseInt(entry.slice(8, 16), 16) % odds) + 1;
export const tapeCommitment = (entries: string[]): Promise<string> => sha256Hex(entries.join("\n"));

export type TapeFailure = { reason: "not-issued" | "roll" | "stack" | "shiny" | "next"; index: number };

// Check every ranked drop in a batch against the entry the server would have issued for it. `claims` are the
// attempts each card's ranked drops have needed so far; `attempts` is the snapshot's lifetime attempts per card.
// Returns the failure, or null and the updated claims.
export async function checkTape(args: {
  key: TapeKey; playerId: string; events: LedgerEvent[]; stateBefore: LedgerState; catalog: Catalog;
  issuedEnd: number; claims: Record<string, number>; attempts: Record<string, number>; tapeNext: number;
}): Promise<{ failure: TapeFailure } | { failure: null; claims: Record<string, number> }> {
  const claims = { ...args.claims };
  const owned = new Set(Object.keys(args.stateBefore.shiny));
  let lastTape = args.stateBefore.lastTape;
  for (const [index, event] of args.events.entries()) {
    if (event.kind !== "drop" || event.tape === 0) continue;
    if (event.tape > args.issuedEnd) return { failure: { reason: "not-issued", index } };
    const card = args.catalog.cards[event.key];
    if (!card) continue; // the rules have already refused unknown cards
    const entry = await tapeEntry(args.key, args.playerId, event.tape);
    const rate = args.catalog.rates[card.rank] ?? 0;
    // The server cannot see the misses between two drops, but a drop with this roll needed at least this many
    // attempts since the card's last one. Added up, those can never exceed the attempts the add-on has counted.
    const used = (claims[event.key] ?? 0) + attemptsNeeded(rollValue(entry), rate, args.catalog.stackFactor);
    claims[event.key] = used;
    if (used > (args.attempts[event.key] ?? 0)) return { failure: { reason: "stack", index } };
    // While a card has no shiny copy, a drop is shiny exactly when its entry says so. Once it has one, the rules
    // already refuse any further shiny.
    if (!owned.has(event.key) && (shinyValue(entry, args.catalog.shinyOdds) === 1) !== (event.shiny === 1)) return { failure: { reason: "shiny", index } };
    if (event.shiny === 1) owned.add(event.key);
    lastTape = event.tape;
  }
  // The position the add-on says it will use next must follow the last entry it used and lie within what was issued.
  if (args.tapeNext > args.issuedEnd + 1 || (lastTape > 0 && args.tapeNext <= lastTape)) {
    return { failure: { reason: "next", index: args.events.length } };
  }
  return { failure: null, claims };
}
