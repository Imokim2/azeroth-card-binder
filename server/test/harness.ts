// Shared set-up for the API tests: a real SQLite database with the real migrations, a clock we control, a fake
// Discord sign-in, players with real Ed25519 keys, and histories taken from the shared rules vectors.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { createApi } from "../src/api.ts";
import type { Deps } from "../src/api.ts";
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import { SqlStore } from "../src/sqlStore.ts";
import type { Catalog, LedgerState } from "../src/shared.ts";
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

export function setup(options: { identity?: boolean } = {}) {
  const { db, raw } = openTestDb();
  const store = new SqlStore(db);
  const clock = { now: NOW };
  const logs: Record<string, unknown>[] = [];
  let healthy = true;
  const identity = options.identity === false ? undefined : { verify: async (token: string) => (token.startsWith("discord:") ? token.slice(8) : null) };
  const deps: Deps = {
    players: store, ingest: store, board: store, catalog,
    now: () => clock.now, log: (entry) => logs.push(entry),
    health: async () => { if (!healthy) throw new Error("database down"); await db.all("SELECT 1"); },
    minClient: "0.1.0", version: "test", ...(identity ? { identity } : {}),
  };
  const api = createApi(deps);
  return {
    db, raw, store, clock, logs, deps, api,
    breakHealth() { healthy = false; },
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

// The valid history from the shared vectors, chained: every event gets its prev and h.
export function chainedHistory(from = 1, count = Infinity): Record<string, unknown>[] {
  const events: Record<string, unknown>[] = [];
  let prev = reference.GENESIS;
  for (const partial of vectors.valid.events) {
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

export function signedUpload(player: Player, events: Record<string, unknown>[], overrides: Record<string, unknown> = {}) {
  const body: Record<string, unknown> = {
    specVersion: 1, key: player.publicKeyHex, character: "Alice", realm: "RealmName", schema: 2,
    catalogVersion: catalog.catalogVersion, events, tapeIndex: 0, sentAt: NOW,
    snapshot: { ...vectors.valid.snapshot, attempts: { "npc:589": 3 }, titles: {} }, ...overrides,
  };
  // The reference signer rejects nothing; canonicalJson here guards against building a body the server cannot read.
  canonicalJson(body);
  return { ...body, sig: reference.signBatch(body, player.privateKey) };
}
