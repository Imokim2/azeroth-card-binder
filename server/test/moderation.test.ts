// Reviewing flags and banning players (roadmap D4), behind the admin token.
import assert from "node:assert/strict";
import test from "node:test";
import { luckScore } from "../src/integrity.ts";
import { ADMIN_TOKEN, catalog, chain, newPlayer, registration, setup, signedUpload } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };
const read = async (response: Response) => (await response.json()) as Body;
type Flags = { flags: { id: string; playerId: string; displayName: string; kind: string; state: string; notes: string; reviewedAt: number | null; reviewNote: string }[] };

const admin = { authorization: "Bearer " + ADMIN_TOKEN };
const base = { dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Alice-RealmName" };
const drops = (count: number, from = 1) => Array.from({ length: count }, (_, index) => ({ seq: from + index, t: 1000 + from + index, kind: "drop", key: "npc:589", count: from + index, ...base }));
const snapshot = (count: number, attempts: number) => ({ counts: { "npc:589": count }, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} });

async function luckyPlayer(env: ReturnType<typeof setup>, count = 30) {
  const player = newPlayer("alice");
  const registered = (await read(await env.call("/v1/register", { body: registration(player) }))) as { playerId: string };
  const response = await env.call("/v1/ledger", { body: signedUpload(player, chain(drops(count)), { snapshot: snapshot(count, 200) }) });
  assert.equal(response.status, 200);
  return { player, id: registered.playerId };
}
const listed = async (env: ReturnType<typeof setup>, query = "") => ((await read(await env.call("/v1/admin/flags" + query, { headers: admin }))) as unknown as Flags).flags;

test("the admin routes do not exist without a token configured, and refuse a missing or wrong one", async () => {
  const env = setup();
  const { id } = await luckyPlayer(env);
  assert.equal((await read(await env.call("/v1/admin/flags"))).error?.code, "unauthorized");
  assert.equal((await read(await env.call("/v1/admin/flags", { headers: { authorization: "Bearer wrong" } }))).error?.code, "unauthorized");
  assert.equal((await read(await env.call("/v1/admin/flags", { headers: { authorization: ADMIN_TOKEN } }))).error?.code, "unauthorized", "the Bearer word is needed");
  assert.equal((await read(await env.call("/v1/admin/flags/ABC", { body: { state: "cleared" }, headers: { authorization: "Bearer wrong" } }))).error?.code, "unauthorized");
  assert.equal((await read(await env.call(`/v1/admin/players/${id}/ban`, { body: { banned: true }, headers: { authorization: "Bearer wrong" } }))).error?.code, "unauthorized");
  // With no token configured at all, there is nothing at these addresses.
  env.deps.adminToken = undefined;
  assert.equal((await read(await env.call("/v1/admin/flags", { headers: admin }))).error?.code, "not_found");
  assert.equal((await env.call("/v1/admin/flags", { headers: admin })).status, 404);
});

test("a held player is listed for review; confirming keeps them hidden, clearing puts them back", async () => {
  const env = setup();
  const { id } = await luckyPlayer(env);
  assert.equal((await env.call("/v1/player/" + id)).status, 404, "held off the ladder");
  const open = await listed(env);
  assert.equal(open.length, 1);
  const flag = open[0]!;
  assert.deepEqual([flag.kind, flag.state, flag.displayName, flag.playerId], ["luck-hold", "open", "Alice-RealmName", id]);
  assert.match(flag.notes, /^luck \d/);
  assert.equal(flag.reviewedAt, null);

  // Confirmed: still hidden, no longer in the open queue, and the reason is on record.
  env.clock.now += 60;
  const confirmed = await env.call("/v1/admin/flags/" + flag.id, { body: { state: "confirmed", note: "no way" }, headers: admin });
  assert.equal(confirmed.status, 200);
  assert.deepEqual(await listed(env), []);
  assert.equal((await env.call("/v1/player/" + id)).status, 404);
  const done = (await listed(env, "?state=confirmed"))[0]!;
  assert.deepEqual([done.state, done.reviewNote, done.reviewedAt], ["confirmed", "no way", env.clock.now]);

  // Cleared (a second look): back on the ladder.
  assert.equal((await env.call("/v1/admin/flags/" + flag.id, { body: { state: "cleared" }, headers: admin })).status, 200);
  assert.equal((await env.call("/v1/player/" + id)).status, 200);
  assert.equal((await listed(env, "?state=all")).length, 1);
});

test("luck a person has cleared is not flagged again, but much more luck than that is", async () => {
  const env = setup();
  const { player, id } = await luckyPlayer(env, 30);
  const flag = (await listed(env))[0]!;
  await env.call("/v1/admin/flags/" + flag.id, { body: { state: "cleared" }, headers: admin });
  const head = () => (env.raw.prepare("SELECT head_hash FROM ledger_state").get() as { head_hash: string }).head_hash;
  const cleared = Number(/luck ([\d.]+)/.exec(flag.notes)?.[1]);
  // One more drop from the same attempts: still over the line, but about as lucky as what was cleared.
  const more = chain(drops(1, 31).map((event) => ({ ...event, count: 31 })), head());
  const second = await env.call("/v1/ledger", { body: signedUpload(player, more, { snapshot: snapshot(31, 200) }) });
  assert.equal(second.status, 200, JSON.stringify(await second.clone().json()));
  assert.deepEqual(await listed(env), [], "no new flag for the same luck");
  assert.equal((await env.call("/v1/player/" + id)).status, 200);
  // Far more luck than was cleared: flagged again.
  let count = 31;
  let score = luckScore(catalog, { "npc:589": 200 }, { "npc:589": count });
  while (score < cleared + 2.5 && count < 400) { count += 20; score = luckScore(catalog, { "npc:589": 200 }, { "npc:589": count }); }
  const lots = chain(drops(count - 31, 32), head());
  const response = await env.call("/v1/ledger", { body: signedUpload(player, lots, { snapshot: snapshot(count, 200) }) });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  assert.equal((await listed(env)).length, 1, "flagged again once it is far beyond what was cleared");
});

test("a banned player cannot upload and leaves the ladder; unbanning puts them back", async () => {
  const env = setup();
  const player = newPlayer("bob");
  const registered = (await read(await env.call("/v1/register", { body: registration(player) }))) as { playerId: string };
  const events = chain([{ seq: 1, t: 1000, kind: "drop", key: "npc:589", count: 1, ...base }]);
  const upload = (overrides: Record<string, unknown> = {}) => env.call("/v1/ledger", { body: signedUpload(player, events, { snapshot: snapshot(1, 100), ...overrides }) });
  assert.equal((await upload()).status, 200);
  assert.equal(((await read(await env.call("/v1/leaderboard"))) as { entries: unknown[] }).entries.length, 1);
  const ban = (banned: unknown) => env.call(`/v1/admin/players/${registered.playerId}/ban`, { body: { banned }, headers: admin });
  assert.equal((await ban(true)).status, 200);
  assert.equal(((await read(await env.call("/v1/leaderboard"))) as { entries: unknown[] }).entries.length, 0);
  assert.equal((await env.call("/v1/player/" + registered.playerId)).status, 404);
  assert.equal((await read(await upload({ sentAt: 1_700_000_001 }))).error?.code, "banned");
  assert.equal((await ban(false)).status, 200);
  assert.equal(((await read(await env.call("/v1/leaderboard"))) as { entries: unknown[] }).entries.length, 1);
});

test("bad admin requests are refused plainly", async () => {
  const env = setup();
  const { id } = await luckyPlayer(env);
  const flag = (await listed(env))[0]!;
  const post = (path: string, body: unknown) => env.call(path, { body, headers: admin });
  assert.equal((await read(await env.call("/v1/admin/flags?state=bogus", { headers: admin }))).error?.code, "bad_request");
  assert.equal((await read(await post("/v1/admin/flags/" + flag.id, { state: "banned" }))).error?.code, "bad_request");
  assert.equal((await read(await post("/v1/admin/flags/" + flag.id, { state: "cleared", note: "x".repeat(501) }))).error?.code, "bad_request");
  assert.equal((await read(await post("/v1/admin/flags/NOSUCHFLAG", { state: "cleared" }))).error?.code, "not_found");
  assert.equal((await read(await post(`/v1/admin/players/${id}/ban`, { banned: "yes" }))).error?.code, "bad_request");
  assert.equal((await read(await post("/v1/admin/players/01ARZ3NDEKTSV4RRFFQ69G5FAV/ban", { banned: true }))).error?.code, "not_found");
  assert.equal((await env.call("/v1/admin/flags", { method: "DELETE", headers: admin })).status, 405);
  assert.equal((await listed(env, "?limit=0")).length, 1, "a nonsense limit falls back to the default");
});
