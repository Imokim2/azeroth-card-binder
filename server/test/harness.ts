// Shared set-up for the API tests: a real SQLite database with the real migrations, a clock we control, a fake
// Discord sign-in, players with real Ed25519 keys, and histories taken from the shared rules vectors.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { createApi } from "../src/api.ts";
import type { Deps } from "../src/api.ts";
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import { SqlStore } from "../src/sqlStore.ts";
import { replay } from "../src/shared.ts";
import type { Catalog, LedgerState } from "../src/shared.ts";
import { chanceAfter } from "../src/stack.ts";
import { rollValue, shinyValue, tapeEntry, tapeKey } from "../src/tape.ts";
import { openTestDb } from "./sqliteDb.ts";

// The reference implementation signs and chains; the server under test verifies. Two independent code paths.
const require = createRequire(import.meta.url);
const reference = require("../../packages/shared/src/ledger.js") as {
  GENESIS: string;
  makeEvent(partial: Record<string, unknown>, prev: string): Record<string, unknown> & { h: string };
  keyPairFromSeed(seed: string): { privateKey: unknown; publicKeyHex: string };
  signBatch(batch: Record<string, unknown>, privateKey: unknown): string;
  sha256Hex(text: string): string;
};

const root = new URL("../../packages/shared/", import.meta.url);
export const catalog = JSON.parse(readFileSync(new URL("catalog.json", root), "utf8")) as Catalog;
export const vectors = JSON.parse(readFileSync(new URL("vectors/rules.json", root), "utf8")) as {
  valid: { events: Record<string, unknown>[]; finalState: LedgerState; snapshot: Record<string, unknown> };
  invalid: { name: string; rule: string; index: number; events: Record<string, unknown>[] }[];
};

export const CLIENT = "0.1.0";
export const NOW = 1_700_000_000;
export const TAPE_SECRET = "test-only tape secret, never used anywhere real";
export const ADMIN_TOKEN = "test-only admin token, never used anywhere real";

export function setup(options: { identity?: boolean } = {}) {
  const { db, raw } = openTestDb();
  const store = new SqlStore(db);
  const clock = { now: NOW };
  const logs: Record<string, unknown>[] = [];
  let healthy = true;
  const identity = options.identity === false ? undefined : { verify: async (token: string) => (token.startsWith("discord:") ? token.slice(8) : null) };
  const deps: Deps = {
    players: store, ingest: store, board: store, tapes: store, trades: store, moderation: store, rebuild: store, wanted: store, catalog, tapeSecret: TAPE_SECRET, adminToken: ADMIN_TOKEN,
    now: () => clock.now, log: (entry) => logs.push(entry),
    health: async () => { if (!healthy) throw new Error("database down"); await db.all("SELECT 1"); },
    minClient: "0.1.0", version: "test", ...(identity ? { identity } : {}),
  };
  const api = createApi(deps);
  return {
    db, raw, store, clock, logs, deps, api,
    breakHealth() { healthy = false; },
    // Most tests build their histories from Casual drops, which the server cannot recheck and so keeps off the ladder.
    // Tests about something else (ordering, flags, bans) call this to stand in for a player whose drops are all Ranked.
    pretendVerified() { raw.prepare("UPDATE ledger_state SET casual_drops = 0").run(); },
    call(path: string, init: { method?: string; body?: unknown; headers?: Record<string, string>; raw?: string } = {}) {
      const headers: Record<string, string> = { "x-warcards-client": CLIENT, ...init.headers };
      let body: string | undefined;
      if (init.raw !== undefined) body = init.raw;
      else if (init.body !== undefined) body = JSON.stringify(init.body);
      if (body !== undefined && !headers["content-type"]) headers["content-type"] = "application/json";
      return api(new Request("https://warcards.test" + path, { method: init.method ?? (body === undefined ? "GET" : "POST"), headers, ...(body !== undefined ? { body } : {}) }));
    },
  };
}

export type Player = { publicKeyHex: string; privateKey: unknown; discord: string };

export function newPlayer(name: string): Player {
  const keys = reference.keyPairFromSeed(reference.sha256Hex("test player " + name));
  return { publicKeyHex: keys.publicKeyHex, privateKey: keys.privateKey, discord: name };
}

export function registration(player: Player, extra: Record<string, unknown> = {}) {
  const body: Record<string, unknown> = {
    key: player.publicKeyHex, sentAt: NOW, identityToken: "discord:" + player.discord, visibility: "public", ...extra,
  };
  const proof = reference.signBatch({ ...body, purpose: "register" }, player.privateKey);
  return { ...body, proof };
}

// The Casual part of the valid history from the shared vectors (everything before it switches to Ranked), chained:
// every event gets its prev and h. Ranked drops have to match the server's tape, so they are built in tape.test.ts.
export const casualPartials = vectors.valid.events.slice(0, vectors.valid.events.findIndex((event) => event["kind"] === "mode"));
export function chainedHistory(from = 1, count = Infinity): Record<string, unknown>[] {
  const events: Record<string, unknown>[] = [];
  let prev = reference.GENESIS;
  for (const partial of casualPartials) {
    const event = reference.makeEvent(partial, prev);
    events.push(event);
    prev = event.h;
  }
  return events.slice(from - 1, from - 1 + count);
}

export function chain(partials: Record<string, unknown>[], prev = reference.GENESIS): Record<string, unknown>[] {
  const events: Record<string, unknown>[] = [];
  for (const partial of partials) {
    const event = reference.makeEvent(partial, prev);
    events.push(event);
    prev = event.h;
  }
  return events;
}

// What the Casual history adds up to, for snapshots and score expectations.
export const casualState = replay(casualPartials, catalog);
if (!casualState.ok) throw new Error("the shared Casual history breaks a rule");
// Honest attempts for that history: about a hundred kills for every drop, so the luck check sees ordinary luck.
export const casualAttempts: Record<string, number> = {};
for (const event of casualPartials) if (event["kind"] === "drop") casualAttempts[String(event["key"])] = (casualAttempts[String(event["key"])] ?? 0) + 100;
export const casualSnapshot = { counts: casualState.state.counts, dust: casualState.state.dust, sets: casualState.state.sets };

export function signedUpload(player: Player, events: Record<string, unknown>[], overrides: Record<string, unknown> = {}) {
  const body: Record<string, unknown> = {
    specVersion: 2, key: player.publicKeyHex, character: "Alice", realm: "RealmName", schema: 2,
    catalogVersion: catalog.catalogVersion, events, tapeIndex: 0, sentAt: NOW,
    snapshot: { ...casualSnapshot, attempts: casualAttempts, titles: {} }, ...overrides,
  };
  // The reference signer rejects nothing; canonicalJson here guards against building a body the server cannot read.
  canonicalJson(body);
  return { ...body, sig: reference.signBatch(body, player.privateKey) };
}

// A Ranked history built from the player's own tape: every attempt written down, as a drop at an entry that really wins
// (shiny exactly as the entry says) or inside a run of misses at the entries that really lose.
export async function rankedHistory(playerId: string, wins: number, cardKey = "npc:589", char = "Alice-RealmName") {
  const key = await tapeKey(TAPE_SECRET);
  const rate = catalog.rates[catalog.cards[cardKey]?.rank ?? ""] ?? 0;
  const base = { dust: 0, partner: "", trade: "", char };
  const partials: Record<string, unknown>[] = [{ seq: 1, t: 1000, kind: "mode", key: "ranked2", count: 0, shiny: 0, tape: 0, ...base }];
  let count = 0;
  let shinyOwned = false;
  let used = 0;
  let misses = 0; // the add-on's own stacking rule: every miss raises the chance of the next attempt
  for (let index = 1; count < wins; index++) {
    used = index;
    const entry = await tapeEntry(key, playerId, index);
    if (rollValue(entry) > chanceAfter(rate, misses, catalog.stackFactor)) {
      misses += 1;
      continue;
    }
    if (misses > 0) partials.push({ seq: partials.length + 1, t: 1000 + partials.length * 10, kind: "miss", key: cardKey, count: misses, shiny: 0, tape: index - 1, ...base });
    misses = 0;
    count += 1;
    const shiny = !shinyOwned && shinyValue(entry, catalog.shinyOdds) === 1;
    if (shiny) shinyOwned = true;
    partials.push({ seq: partials.length + 1, t: 1000 + partials.length * 10, kind: "drop", key: cardKey, count, shiny: shiny ? 1 : 0, tape: index, ...base });
  }
  return { events: chain(partials), tapeNext: used + 1, attempts: used };
}
