import assert from "node:assert/strict";
import test from "node:test";
import { createRequire } from "node:module";
import { SqlSeasons, seasonDefinition, seasonalCandidates } from "../src/seasons.ts";
import type { SeasonSync } from "../src/seasons.ts";
import type { LedgerEvent } from "../src/ledger.ts";
import { newState, replay } from "../src/shared.ts";
import { ADMIN_TOKEN, NOW, catalog, chain, newPlayer, rankedHistory, registration, setup, signedUpload } from "./harness.ts";
import { runMaintenance } from "../src/maintenance.ts";
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(body: Record<string, unknown>, key: unknown): string };
const draft = (extra: Record<string, unknown> = {}) => ({ id: "first-hunt", title: "The First Hunt", startsAt: NOW + 10, endsAt: NOW + 3600,
  selection: { mode: "manual", cards: ["npc:589"] }, rewards: {
    completion: { title: "Season Seeker", packs: [{ pack: catalog.cards["npc:589"]!.set, count: 1 }] },
    first: { places: 1, title: "First of the Hunt", packs: [{ pack: catalog.cards["npc:589"]!.set, count: 1 }] },
  }, ...extra });
function request(player: ReturnType<typeof newPlayer>, at = NOW, purpose = "seasons") {
  const body = { key: player.publicKeyHex, sentAt: at };
  return { ...body, sig: reference.signBatch({ ...body, purpose }, player.privateKey) };
}
async function fixture(name = "season-alice") {
  const env = setup(), seasons = new SqlSeasons(env.db, catalog);
  env.deps.seasons = seasons;
  const player = newPlayer(name);
  const registered = await env.call("/v1/register", { body: registration(player) });
  const id = (await registered.json() as { playerId: string }).playerId;
  await seasons.schedule(draft(), NOW);
  return { ...env, seasons, player, id };
}
async function uploadDrops(f: Awaited<ReturnType<typeof fixture>>, count: number, at: number, receivedAt = at) {
  const history = await rankedHistory(f.id, count);
  const events = chain(history.events.map(e => ({ ...e, t: at })));
  await f.store.recordIssue(f.id, { start: 1, end: history.tapeNext, commitment: "test" }, NOW);
  f.clock.now = receivedAt;
  const response = await f.call("/v1/ledger", { body: signedUpload(f.player, events, {
    specVersion: 7, tapeIndex: history.tapeNext,
    snapshot: { counts: { "npc:589": count }, attempts: { "npc:589": history.attempts }, sets: {}, dust: 0, titles: {} },
  }) });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  return events;
}

test("random selection is resolved once, filtered and identical for every player", async () => {
  const input = draft({ selection: { mode: "random", seed: "week-one", count: 4, sets: [catalog.cards["npc:589"]!.set] } });
  const a = await seasonDefinition(input, catalog, NOW), b = await seasonDefinition(input, catalog, NOW);
  assert.deepEqual(a.cards, b.cards); assert.equal(new Set(a.cards).size, 4);
  await assert.rejects(seasonDefinition(draft({ endsAt: NOW }), catalog, NOW));
  await assert.rejects(seasonDefinition(draft({ selection: { mode: "manual", cards: ["npc:589", "npc:589"] } }), catalog, NOW));
  await assert.rejects(seasonDefinition(draft({ selection: { mode: "random", seed: "s", count: 999, sets: ["WF"] } }), catalog, NOW));
});

test("scheduling and private progress require the correct authority and signature purpose", async () => {
  const f = await fixture();
  assert.equal((await f.call("/v1/admin/seasons", { body: draft({ id: "other" }) })).status, 401);
  assert.equal((await f.call("/v1/admin/seasons", { headers: { authorization: "Bearer " + ADMIN_TOKEN } })).status, 200);
  assert.equal((await f.call("/v1/seasons", { body: request(f.player, NOW, "tape") })).status, 401);
  const response = await f.call("/v1/seasons", { body: request(f.player) });
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual((await response.json() as SeasonSync).seasons[0]!.collected, []);
  await assert.rejects(f.seasons.schedule(draft(), NOW), { code: "bad_request" });
});

test("existing normal cards do not count; a fresh verified duplicate earns seasonal progress and ordinary inventory", async () => {
  const f = await fixture();
  // First copy was received before the season.
  const history = await rankedHistory(f.id, 2);
  const firstDrop = history.events.findIndex(e => e["kind"] === "drop");
  const events = chain(history.events.map((e, i) => ({ ...e, t: i <= firstDrop ? NOW : NOW + 20 })));
  await f.store.recordIssue(f.id, { start: 1, end: history.tapeNext, commitment: "test" }, NOW);
  const snapshot = { counts: { "npc:589": 1 }, attempts: { "npc:589": history.attempts }, dust: 0, sets: {}, titles: {} };
  assert.equal((await f.call("/v1/ledger", { body: signedUpload(f.player, events.slice(0, firstDrop + 1), { specVersion: 7, tapeIndex: history.tapeNext, snapshot }) })).status, 200);
  assert.deepEqual((await f.seasons.sync(f.id, NOW + 15)).seasons[0]!.collected, []);
  f.clock.now = NOW + 20;
  const response = await f.call("/v1/ledger", { body: signedUpload(f.player, events.slice(firstDrop + 1), { specVersion: 7, tapeIndex: history.tapeNext, snapshot: { ...snapshot, counts: { "npc:589": 2 } } }) });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  const state = await f.store.load(f.id), progress = await f.seasons.sync(f.id, f.clock.now);
  assert.equal(state.state.counts["npc:589"], 2);
  assert.equal(progress.seasons[0]!.place, 1);
  assert.deepEqual(progress.seasons[0]!.collected, ["npc:589"]);
  assert.deepEqual(progress.seasons[0]!.titles, ["Season Seeker", "First of the Hunt"]);
  assert.equal(progress.grants.length, 2);
  assert.equal((await f.seasons.sync(f.id, f.clock.now)).grants.length, 2, "retries do not multiply grants");
});

test("everyone finishing wins, first-place bonus is limited, and rewards redeem once atomically", async () => {
  const f = await fixture();
  const events = await uploadDrops(f, 1, NOW + 20);
  const bob = newPlayer("season-bob");
  const id = (await (await f.call("/v1/register", { body: registration(bob) })).json() as { playerId: string }).playerId;
  await uploadDrops({ ...f, player: bob, id }, 1, NOW + 21);
  const second = await f.seasons.sync(id, NOW + 21);
  assert.equal(second.seasons[0]!.place, 2); assert.equal(second.grants.length, 1);
  assert.deepEqual(second.seasons[0]!.titles, ["Season Seeker"]);
  const [grant] = (await f.seasons.sync(f.id, NOW + 22)).grants;
  assert.ok(grant);
  const claim = chain([{ seq: events.length + 1, t: NOW + 22, kind: "seasonReward", key: grant.pack, count: 1,
    dust: 0, shiny: 0, tape: 0, partner: "", trade: grant.id, char: "Alice-RealmName" }], String(events.at(-1)!["h"]));
  assert.equal(await f.seasons.checkGrants(id, claim as LedgerEvent[]), false, "another account cannot use the grant");
  const stateBefore = await f.store.load(f.id);
  const upload = signedUpload(f.player, claim, { specVersion: 7, tapeIndex: stateBefore.tapeNext,
    snapshot: { counts: stateBefore.state.counts, attempts: {}, sets: {}, dust: 0, titles: {} } });
  f.clock.now = NOW + 22;
  assert.equal((await f.call("/v1/ledger", { body: upload })).status, 200);
  assert.equal((await f.store.load(f.id)).state.packs![grant.pack], 1);
  assert.equal((await f.call("/v1/ledger", { body: upload })).status, 200, "a lost reply can retry safely");
  assert.equal((await f.store.load(f.id)).state.packs![grant.pack], 1);
  assert.equal(await f.seasons.checkGrants(f.id, claim as LedgerEvent[]), false);
  const forged = chain([{ ...claim[0], seq: events.length + 2, trade: "f".repeat(32), count: 2 }], String(claim[0]!["h"]));
  const rejected = await f.call("/v1/ledger", { body: signedUpload(f.player, forged, { specVersion: 7, tapeIndex: stateBefore.tapeNext }) });
  assert.equal(rejected.status, 422);
  assert.equal((await f.store.load(f.id)).state.packs![grant.pack], 1, "failed claims cannot change inventory");
});

test("deadline uses both acquisition time and server receipt; old, late, Casual and craft gains do not qualify", async () => {
  const f = await fixture();
  await uploadDrops(f, 1, NOW + 20, NOW + 3600);
  assert.deepEqual((await f.seasons.sync(f.id, NOW + 3600)).seasons[0]!.collected, []);
  const base = { seq: 1, t: NOW + 30, key: "npc:589", count: 1, dust: 0, shiny: 0, tape: 0, trade: "", partner: "", char: "A-R", prev: "0".repeat(32), h: "0".repeat(32) };
  assert.deepEqual(seasonalCandidates([{ ...base, kind: "drop" }, { ...base, kind: "craft" }] as LedgerEvent[], "casual"), []);
  assert.deepEqual(seasonalCandidates([{ ...base, kind: "craft" }] as LedgerEvent[], "ranked2"), []);
  const reward = { ...base, kind: "seasonReward", key: catalog.cards["npc:589"]!.set, trade: "a".repeat(32) };
  assert.ok(replay([reward], catalog, newState()).ok);
  assert.equal(replay([reward, { ...reward, count: 2 }], catalog).ok, false, "replay itself refuses duplicate grants");
});

test("a new incoming trade counts only after both halves and Ranked provenance are verified", async () => {
  const f = await fixture();
  const before = await uploadDrops(f, 1, NOW);
  const bob = newPlayer("season-bob");
  const bobId = (await (await f.call("/v1/register", { body: registration(bob) })).json() as { playerId: string }).playerId;
  f.clock.now = NOW + 30;
  const fields = { t: NOW + 30, dust: 0, shiny: 0, tape: 0, trade: "seasontrade0001" };
  const incoming = chain([
    { ...fields, seq: 1, kind: "mode", key: "ranked2", count: 0, partner: "", trade: "", char: "Bob-RealmName" },
    { ...fields, seq: 2, kind: "tradeIn", key: "npc:589", count: 1, partner: "alice-realmname", char: "Bob-RealmName" },
  ]);
  const snapshot = { counts: { "npc:589": 1 }, attempts: {}, sets: {}, titles: {}, dust: 0 };
  const receive = await f.call("/v1/ledger", { body: signedUpload(bob, incoming, { specVersion: 7, character: "Bob", tapeIndex: 1, snapshot }) });
  assert.equal(receive.status, 200, JSON.stringify(await receive.clone().json()));
  assert.deepEqual((await f.seasons.sync(bobId, f.clock.now)).seasons[0]!.collected, []);
  const outgoing = chain([{ ...fields, seq: before.length + 1, kind: "tradeOut", key: "npc:589", count: 0, partner: "bob-realmname", char: "Alice-RealmName" }], String(before.at(-1)!["h"]));
  const stored = await f.store.load(f.id);
  assert.equal((await f.call("/v1/ledger", { body: signedUpload(f.player, outgoing, { specVersion: 7, tapeIndex: stored.tapeNext, snapshot: { ...snapshot, counts: {} } }) })).status, 200);
  await runMaintenance({ ingest: f.store, trades: f.store, catalog, now: () => f.clock.now });
  await f.seasons.settlePending(f.clock.now);
  assert.deepEqual((await f.seasons.sync(bobId, f.clock.now)).seasons[0]!.collected, ["npc:589"]);
  assert.equal((await f.store.load(bobId)).state.counts["npc:589"], 1);
});

test("seasonal rewards survive binder restarts without duplication and follow account export/deletion", async () => {
  const f = await fixture();
  await uploadDrops(f, 1, NOW + 20);
  const original = await f.seasons.sync(f.id, NOW + 20);
  const exported = await f.store.exportPlayer(f.id);
  assert.ok(exported?.["seasonal"]);
  await f.store.resetBinder(f.id, "season-archive", NOW + 21);
  const after = await f.seasons.sync(f.id, NOW + 21);
  assert.deepEqual(after.grants, original.grants);
  assert.deepEqual(after.titles, original.titles);
  assert.equal(after.seasons[0]!.place, 1);
  const [grant] = after.grants;
  await f.db.batch([{ sql: "INSERT INTO season_redemptions VALUES (?, ?, ?)", params: [grant!.id, f.id, 1] }]);
  await f.store.deletePlayer(f.id);
  for (const table of ["season_acquisitions", "season_completions", "season_grants", "season_redemptions"]) {
    assert.equal(f.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()?.["n"], 0);
  }
});

test("review holds seasonal rewards without removing ordinary binder gains", async () => {
  const f = await fixture();
  await f.store.addFlag(f.id, { id: "season-review", kind: "manual-review", notes: "test" }, NOW);
  await uploadDrops(f, 1, NOW + 20);
  assert.deepEqual((await f.seasons.sync(f.id, NOW + 20)).grants, []);
  assert.equal((await f.store.load(f.id)).state.counts["npc:589"], 1);
  await f.store.review("season-review", "cleared", "test", NOW + 25);
  assert.equal((await f.seasons.sync(f.id, NOW + 25)).grants.length, 2);
});

test("a temporary settlement failure cannot reject already verified normal progress", async () => {
  const f = await fixture();
  const settle = f.seasons.settle.bind(f.seasons);
  f.seasons.settle = async () => { throw new Error("test settlement failure"); };
  await uploadDrops(f, 1, NOW + 20);
  assert.equal((await f.store.load(f.id)).state.counts["npc:589"], 1);
  assert.ok(f.logs.some(entry => entry["msg"] === "season settlement deferred"));
  f.seasons.settle = settle;
  assert.equal((await f.seasons.sync(f.id, NOW + 21)).grants.length, 2);
});
