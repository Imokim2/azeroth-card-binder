// The roll tape (docs/LEDGER-SPEC.md, section 8). Each entry is 16 hex characters derived from a server secret, the
// player and the entry's position, so nothing needs storing to recompute any entry later, and a player cannot guess
// an entry they have not been given. Roll and shiny values follow the spec and the shared vectors exactly.
import { sha256Hex, toHex } from "../../packages/shared/src/crypto.ts";
import type { LedgerEvent } from "./ledger.ts";
import type { Catalog, LedgerState } from "./shared.ts";
import { chanceAfter } from "./stack.ts";

// A player is never given more than TAPE_SIZE + REFILL_BELOW entries ahead of the last upload that used them, so what
// they could read ahead of time is small. Heavy play is about a thousand attempts an hour.
export const TAPE_SIZE = 1_000; // entries added at each refill
export const REFILL_BELOW = 250; // a refill happens when this few unused entries remain

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

export type TapeFailure = { reason: "not-issued" | "roll" | "shiny" | "next"; index: number };

// Replay every ranked attempt in a batch against the entry the server issued for it (spec section 8). In ranked2 every
// attempt is written down, as a drop or inside a run of misses, so each one can be checked exactly: a miss needs a roll
// above the chance of that attempt, a drop needs a roll at or below it. `stack` is how many misses in a row each card
// has had since its last drop; entering ranked2 starts every card at zero. Returns the failure, or null and the new stack.
export async function checkTape(args: {
  key: TapeKey; playerId: string; events: LedgerEvent[]; stateBefore: LedgerState; catalog: Catalog;
  issuedEnd: number; stack: Record<string, number>; tapeNext: number;
}): Promise<{ failure: TapeFailure } | { failure: null; stack: Record<string, number> }> {
  let stack = { ...args.stack };
  const owned = new Set(Object.keys(args.stateBefore.shiny));
  let lastTape = args.stateBefore.lastTape;
  const entryAt = (position: number): Promise<string> => tapeEntry(args.key, args.playerId, position);
  for (const [index, event] of args.events.entries()) {
    if (event.kind === "mode" && event.key === "ranked2") {
      stack = {};
      lastTape = event.tape;
      continue;
    }
    if ((event.kind !== "drop" && event.kind !== "miss") || event.tape === 0) continue;
    if (event.tape > args.issuedEnd) return { failure: { reason: "not-issued", index } };
    const card = args.catalog.cards[event.key];
    if (!card) continue; // the rules have already refused unknown cards
    const rate = args.catalog.rates[card.rank] ?? 0;
    if (event.kind === "miss") {
      for (let position = event.tape - event.count + 1; position <= event.tape; position++) {
        const misses = stack[event.key] ?? 0;
        // A miss that the roll would have won is a drop the player left out.
        if (rollValue(await entryAt(position)) <= chanceAfter(rate, misses, args.catalog.stackFactor)) return { failure: { reason: "roll", index } };
        stack[event.key] = misses + 1;
      }
      lastTape = event.tape;
      continue;
    }
    const entry = await entryAt(event.tape);
    if (rollValue(entry) > chanceAfter(rate, stack[event.key] ?? 0, args.catalog.stackFactor)) return { failure: { reason: "roll", index } };
    delete stack[event.key];
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
  return { failure: null, stack };
}
