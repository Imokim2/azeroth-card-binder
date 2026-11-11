// Launch hardening: rate limits, and deleting everything held about a player.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { bindingLimiter, memoryLimiter } from "../src/limit.ts";
import { NOW, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

test("the in-memory limiter counts per key within a window, and starts again in the next", async () => {
  let now = 1000;
  const limiter = memoryLimiter({ limit: 2, periodSeconds: 60, now: () => now });
  assert.deepEqual([await limiter.allow("a"), await limiter.allow("a"), await limiter.allow("a")], [true, true, false]);
  assert.equal(await limiter.allow("b"), true, "another key has its own count");
  now = 1000 - (1000 % 60) + 60; // the next window
  assert.equal(await limiter.allow("a"), true);
});

test("the Cloudflare binding is followed, and if it fails the service stays up", async () => {
  assert.equal(await bindingLimiter({ limit: async () => ({ success: true }) }).allow("k"), true);
  assert.equal(await bindingLimiter({ limit: async () => ({ success: false }) }).allow("k"), false);
  assert.equal(await bindingLimiter({ limit: async () => { throw new Error("down"); } }).allow("k"), true);
});

test("the API limits each client address: a general limit for everything, a strict one for creating and destroying", async () => {
  const env = setup();
  env.deps.limits = {
    general: memoryLimiter({ limit: 3, periodSeconds: 60, now: () => env.clock.now }),
    strict: memoryLimiter({ limit: 1, periodSeconds: 60, now: () => env.clock.now }),
  };
  const from = (ip: string) => ({ "cf-connecting-ip": ip });
  for (let index = 0; index < 3; index++) assert.equal((await env.call("/v1/leaderboard", { headers: from("1.1.1.1") })).status, 200);
  const refused = await env.call("/v1/leaderboard", { headers: from("1.1.1.1") });
  assert.equal(refused.status, 429);
  assert.equal(refused.headers.get("retry-after"), "60");
  assert.equal((await read(refused)).error?.code, "rate_limited");
  assert.equal((await env.call("/v1/leaderboard", { headers: from("2.2.2.2") })).status, 200, "another address is not affected");
  for (let index = 0; index < 10; index++) assert.equal((await env.call("/v1/health", { headers: from("1.1.1.1") })).status, 200, "health is never limited");

  // The strict limit is for POSTs to register, reset, delete and the admin routes: one a minute here.
  const post = (ip: string) => env.call("/v1/register", { body: {}, headers: from(ip) });
  assert.equal((await post("3.3.3.3")).status, 400, "the first goes through (and is refused as a bad request)");
  assert.equal((await post("3.3.3.3")).status, 429);
  assert.equal((await env.call("/v1/admin/flags", { headers: from("3.3.3.3") })).status, 401, "a GET uses the general limit, not the strict one");
  // After the window, allowed again.
  env.clock.now += 60;
  assert.equal((await post("3.3.3.3")).status, 400);
  assert.equal((await env.call("/v1/leaderboard", { headers: from("1.1.1.1") })).status, 200);

  // No limiter configured: nothing is limited.
  const open = setup();
  for (let index = 0; index < 50; index++) assert.equal((await open.call("/v1/leaderboard", { headers: from("9.9.9.9") })).status, 200);
});

const signed = (player: Player, purpose: string, extra: Record<string, unknown> = {}) => {
  const body = { key: player.publicKeyHex, sentAt: NOW, ...extra };
  return { ...body, sig: reference.signBatch({ ...body, purpose }, player.privateKey) };
};
const deletion = (player: Player, extra: Record<string, unknown> = {}) => signed(player, "delete", { confirm: "delete my data", ...extra });
async function register(env: ReturnType<typeof setup>, name: string) {
  const player = newPlayer(name);
  const body = await read(await env.call("/v1/register", { body: registration(player) }));
  return { player, id: body["playerId"] as string };
}
const rows = (env: ReturnType<typeof setup>, table: string) => Number((env.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n);
const tables = ["batches", "drops", "ledger_state", "scores", "characters", "tapes", "flags", "trades", "set_completions", "keys"];

test("deleting an account removes everything held about it, archives included, and nobody else's data", async () => {
  const env = setup();
  const alice = await register(env, "alice");
  const bob = await register(env, "bob");
  await env.call("/v1/ledger", { body: signedUpload(alice.player, chainedHistory()) });
  await env.call("/v1/ledger", { body: signedUpload(bob.player, chainedHistory(), { character: "Bob" }) });
  // Alice starts a new binder and plays again, so she has an archive too.
  assert.equal((await env.call("/v1/reset", { body: signed(alice.player, "reset") })).status, 200);
  assert.equal((await env.call("/v1/ledger", { body: signedUpload(alice.player, chainedHistory(1, 3), { sentAt: NOW + 1 }) })).status, 200);
  const bobBefore = Object.fromEntries(tables.map((table) => [table, Number((env.raw.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE player_id = ?`).get(bob.id) as { n: number }).n)]));
  assert.ok(rows(env, "players") === 3, "alice, her archive and bob");

  const response = await env.call("/v1/delete", { body: deletion(alice.player) });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { deleted: true });

  assert.equal(rows(env, "players"), 1, "only bob is left");
  for (const table of tables) {
    const left = Number((env.raw.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE player_id != ?`).get(bob.id) as { n: number }).n);
    assert.equal(left, 0, `${table} still holds data of the deleted player or their archive`);
    assert.equal(Number((env.raw.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE player_id = ?`).get(bob.id) as { n: number }).n), bobBefore[table], `${table} changed for another player`);
  }
  assert.equal((await env.call("/v1/player/" + alice.id)).status, 404);
  // The old key is nothing now; the same Discord account can sign up again and gets a new, empty player.
  assert.equal((await read(await env.call("/v1/ledger", { body: signedUpload(alice.player, chainedHistory(), { sentAt: NOW + 2 }) }))).error?.code, "unknown_key");
  const again = await register(env, "alice");
  assert.notEqual(again.id, alice.id);
  assert.equal(rows(env, "players"), 2);
});

test("a deletion needs the key's signature for that purpose and the exact words, and a banned player cannot use it to vanish", async () => {
  const env = setup();
  const carol = await register(env, "carol");
  const dave = await register(env, "dave");
  const code = async (body: unknown) => (await read(await env.call("/v1/delete", { body }))).error?.code;
  assert.equal(await code(deletion(newPlayer("stranger"))), "unknown_key");
  assert.equal(await code(signed(carol.player, "delete", { confirm: "yes" })), "bad_request", "the words must be exact");
  assert.equal(await code(signed(carol.player, "delete")), "bad_request", "the words are needed");
  assert.equal(await code(signed(carol.player, "reset", { confirm: "delete my data" })), "bad_signature", "a signature made for another purpose does not work");
  assert.equal(await code({ ...deletion(carol.player), sentAt: NOW + 3 }), "bad_signature");
  assert.equal(await code(deletion(carol.player, { sentAt: NOW - 90_000 })), "bad_request");
  assert.equal((await env.call("/v1/delete", { method: "GET" })).status, 405);
  assert.equal(rows(env, "players"), 2, "nothing was deleted by any of those");

  env.raw.prepare("UPDATE players SET status = 'banned' WHERE id = ?").run(dave.id);
  assert.equal(await code(deletion(dave.player)), "banned");
  assert.equal(rows(env, "players"), 2, "a banned player's record, and the ban with it, is kept");
});
