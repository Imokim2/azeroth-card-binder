// Rebuilding everything derived from the stored batches (roadmap D8).
import assert from "node:assert/strict";
import test from "node:test";
import { gzip } from "../src/gzip.ts";
import { rebuild } from "../src/rebuild.ts";
import { RULES_VERSION } from "../src/score.ts";
import { ADMIN_TOKEN, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };
const read = async (response: Response) => (await response.json()) as Body;
const admin = { authorization: "Bearer " + ADMIN_TOKEN };

async function twoPlayers(env: ReturnType<typeof setup>) {
  const ids: string[] = [];
  for (const [name, count] of [["Alice", Infinity], ["Bob", 4]] as const) {
    const player = newPlayer(name.toLowerCase());
    const registered = (await read(await env.call("/v1/register", { body: registration(player) }))) as { playerId: string };
    ids.push(registered.playerId);
    const response = await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, count), { character: name }) });
    assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  }
  return ids.sort(); // the rebuild goes in id order
}

const one = (env: ReturnType<typeof setup>, sql: string, ...params: (string | number)[]) => env.raw.prepare(sql).get(...params) as Record<string, number | string>;
const scoreOf = (env: ReturnType<typeof setup>, id: string) => Number(one(env, "SELECT score FROM scores WHERE player_id = ?", id)["score"]);

test("damaged derived data is repaired from the batches, and a dry run only reports", async () => {
  const env = setup();
  const [first, second] = await twoPlayers(env);
  const honest = { first: scoreOf(env, first as string), second: scoreOf(env, second as string) };
  const dropsHeld = Number(one(env, "SELECT COUNT(*) AS n FROM drops WHERE player_id = ?", first as string)["n"]);
  assert.ok(dropsHeld > 0);
  // Three kinds of damage: a wrong score, wrong drop counts, and drop rows that are gone.
  env.raw.prepare("UPDATE scores SET score = 999999, rules_version = 0 WHERE player_id = ?").run(first as string);
  env.raw.prepare("UPDATE ledger_state SET drops_json = '{}' WHERE player_id = ?").run(second as string);
  env.raw.prepare("DELETE FROM drops WHERE player_id = ?").run(first as string);

  // Nothing is written by a dry run, but it says what is wrong.
  const dry = await rebuild(env.deps, { dryRun: true });
  assert.equal(dry.dryRun, true);
  assert.deepEqual(dry.changed.map((entry) => entry.playerId).sort(), [first, second]);
  assert.deepEqual(dry.changed.find((entry) => entry.playerId === first)?.differences, ["score"]);
  assert.deepEqual(dry.changed.find((entry) => entry.playerId === second)?.differences, ["drops"]);
  assert.equal(scoreOf(env, first as string), 999999);
  assert.equal(Number(one(env, "SELECT COUNT(*) AS n FROM drops WHERE player_id = ?", first as string)["n"]), 0);

  // The real run puts it all right, including the rules version and the drop rows (found by force, as they are not compared).
  const done = await rebuild(env.deps, { force: true });
  assert.equal(done.checked, 2);
  assert.deepEqual(done.failed, []);
  assert.equal(done.next, null);
  assert.deepEqual([scoreOf(env, first as string), scoreOf(env, second as string)], [honest.first, honest.second]);
  assert.equal(Number(one(env, "SELECT rules_version AS v FROM scores WHERE player_id = ?", first as string)["v"]), RULES_VERSION);
  assert.equal(Number(one(env, "SELECT COUNT(*) AS n FROM drops WHERE player_id = ?", first as string)["n"]), dropsHeld);
  assert.notEqual(one(env, "SELECT drops_json AS d FROM ledger_state WHERE player_id = ?", second as string)["d"], "{}");
  // Run again: nothing left to change.
  assert.deepEqual((await rebuild(env.deps)).changed, []);
});

test("a rebuild goes through the players a page at a time", async () => {
  const env = setup();
  const [first, second] = await twoPlayers(env);
  env.raw.prepare("UPDATE scores SET score = 1").run();
  const page = await rebuild(env.deps, { limit: 1 });
  assert.deepEqual([page.checked, page.next, page.changed.length], [1, first, 1]);
  const rest = await rebuild(env.deps, { limit: 1, after: page.next });
  assert.deepEqual([rest.checked, rest.next, rest.changed.map((entry) => entry.playerId)], [1, second, [second]]);
  const end = await rebuild(env.deps, { limit: 1, after: rest.next });
  assert.deepEqual([end.checked, end.next], [0, null]);
});

test("a player whose stored history breaks a rule is reported and left exactly as it was", async () => {
  const env = setup();
  const [first] = await twoPlayers(env);
  const before = scoreOf(env, first as string);
  // The stored batch now says something the rules do not allow, as if a rule had been tightened since.
  const events = chainedHistory(1, 3).map((event, index) => (index === 1 ? { ...event, count: 5 } : event));
  env.raw.prepare("UPDATE batches SET events_gzip = ? WHERE player_id = ?").run(await gzip(JSON.stringify(events)), first as string);
  env.raw.prepare("UPDATE scores SET score = 7 WHERE player_id = ?").run(first as string);
  const report = await rebuild(env.deps);
  assert.equal(report.failed.length >= 1, true);
  assert.equal(report.failed[0]?.playerId === first || report.failed.some((entry) => entry.playerId === first), true);
  assert.equal(scoreOf(env, first as string), 7, "left as it was");
  void before;
});

test("the admin route runs a rebuild, and only for the admin", async () => {
  const env = setup();
  const [first] = await twoPlayers(env);
  env.raw.prepare("UPDATE scores SET score = 5 WHERE player_id = ?").run(first as string);
  assert.equal((await read(await env.call("/v1/admin/rebuild", { body: {} }))).error?.code, "unauthorized");
  const dry = (await read(await env.call("/v1/admin/rebuild", { body: { dryRun: true }, headers: admin }))) as unknown as { changed: unknown[]; dryRun: boolean };
  assert.equal(dry.dryRun, true);
  assert.equal(dry.changed.length, 1);
  assert.equal(scoreOf(env, first as string), 5);
  const real = (await read(await env.call("/v1/admin/rebuild", { body: {}, headers: admin }))) as unknown as { changed: unknown[] };
  assert.equal(real.changed.length, 1);
  assert.notEqual(scoreOf(env, first as string), 5);
  for (const bad of [{ limit: 0 }, { limit: 1000 }, { dryRun: "yes" }, { after: 5 }]) {
    assert.equal((await read(await env.call("/v1/admin/rebuild", { body: bad, headers: admin }))).error?.code, "bad_request", JSON.stringify(bad));
  }
});
