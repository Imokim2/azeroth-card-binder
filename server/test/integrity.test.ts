// The statistical checks: the maths against simulation, and the flags they raise through the API.
import assert from "node:assert/strict";
import test from "node:test";
import { LUCK_HOLD, LUCK_REVIEW, dropModel, luckScore } from "../src/integrity.ts";
import { chanceAfter } from "../src/stack.ts";
import { NOW, catalog, chain, newPlayer, registration, setup, signedUpload } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };

// A small seeded random generator, so the simulations are the same on every run.
function generator(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Play `attempts` kills of a card with the add-on's rules: a chance of `rate` that rises by `rate` after every miss.
function play(random: () => number, rate: number, attempts: number): number {
  let misses = 0;
  let drops = 0;
  for (let attempt = 0; attempt < attempts; attempt++) {
    if (random() * 10000 < chanceAfter(rate, misses, 1)) {
      drops += 1;
      misses = 0;
    } else {
      misses += 1;
    }
  }
  return drops;
}

test("the drop model matches what the stacking chance really does", () => {
  const plain = dropModel(100, 0);
  assert.ok(Math.abs(plain.perAttempt - 0.01) < 0.0005);
  const stacked = dropModel(100, 1);
  assert.ok(stacked.perAttempt > 0.07 && stacked.perAttempt < 0.085, String(stacked.perAttempt)); // one drop per about 13 attempts
  assert.ok(stacked.variancePerAttempt > 0 && stacked.variancePerAttempt < stacked.perAttempt);
  assert.deepEqual(dropModel(0, 1), { perAttempt: 0, variancePerAttempt: 0 });
  // The model agrees with a simulation of the add-on's own rules.
  const random = generator(7);
  for (const rate of [100, 200, 1000]) {
    const model = dropModel(rate, 1);
    const trials = 400;
    const attempts = 2000;
    let total = 0;
    let squares = 0;
    for (let trial = 0; trial < trials; trial++) {
      const drops = play(random, rate, attempts);
      total += drops;
      squares += drops * drops;
    }
    const mean = total / trials;
    const variance = squares / trials - mean * mean;
    assert.ok(Math.abs(mean - attempts * model.perAttempt) / (attempts * model.perAttempt) < 0.03, `mean for ${rate}`);
    assert.ok(Math.abs(variance - attempts * model.variancePerAttempt) / (attempts * model.variancePerAttempt) < 0.3, `variance for ${rate}`);
  }
});

test("honest players are almost never flagged, and a doubled drop count always is", () => {
  const random = generator(2026);
  const cards = { "npc:589": 100, "npc:639": 200, "npc:573": 1000 } as const; // a 1%, a 2% and a 10% card
  const attempts = { "npc:589": 3000, "npc:639": 1500, "npc:573": 800 };
  let flagged = 0;
  let sum = 0;
  const players = 3000;
  for (let player = 0; player < players; player++) {
    const drops: Record<string, number> = {};
    for (const [key, rate] of Object.entries(cards)) drops[key] = play(random, rate, attempts[key as keyof typeof attempts]);
    const score = luckScore(catalog, attempts, drops);
    sum += score;
    if (score >= LUCK_REVIEW) flagged += 1;
  }
  assert.ok(flagged / players <= 0.005, `${flagged} of ${players} honest players were flagged`);
  assert.ok(sum / players < 0.6, "the average score of honest play is near zero");
  // A cheater who doubles every drop count.
  const honest = Object.fromEntries(Object.keys(cards).map((key) => [key, Math.round(attempts[key as keyof typeof attempts] * dropModel(cards[key as keyof typeof cards], 1).perAttempt)]));
  const doubled = Object.fromEntries(Object.entries(honest).map(([key, count]) => [key, count * 2]));
  assert.ok(luckScore(catalog, attempts, honest) < 1);
  assert.ok(luckScore(catalog, attempts, doubled) >= LUCK_HOLD, String(luckScore(catalog, attempts, doubled)));
  // Odd inputs are not an error.
  assert.equal(luckScore(catalog, {}, {}), 0);
  assert.equal(luckScore(catalog, { "npc:99999999": 50 }, { "npc:99999999": 50 }), 0);
});

async function registered(env: ReturnType<typeof setup>, name = "alice") {
  const player = newPlayer(name);
  const body = (await (await env.call("/v1/register", { body: registration(player) })).json()) as Body;
  return { player, id: body["playerId"] as string };
}

const base = { dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Alice-RealmName" };
const drops = (key: string, count: number, from = 1) => Array.from({ length: count }, (_, index) => ({ seq: from + index, t: 1000 + index, kind: "drop", key, count: index + 1, ...base }));
const snapshot = (counts: Record<string, number>, attempts: Record<string, number>) => ({ counts, dust: 0, sets: {}, attempts, titles: {} });
const flagKinds = (env: ReturnType<typeof setup>) => (env.raw.prepare("SELECT kind FROM flags ORDER BY kind").all() as { kind: string }[]).map((row) => row.kind);

test("drops that the attempts cannot explain hold a player off the ladder until a person clears the flag", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  // Thirty drops of a 1% card from 200 kills: about three were to be expected.
  const response = await env.call("/v1/ledger", { body: signedUpload(player, chain(drops("npc:589", 30)), { snapshot: snapshot({ "npc:589": 30 }, { "npc:589": 200 }) }) });
  assert.equal(response.status, 200, "the upload is accepted: the checks flag, they do not reject");
  env.pretendVerified(); // these tests are about the luck hold, not about Casual
  assert.deepEqual(flagKinds(env), ["luck-hold"]);
  assert.equal((await env.call("/v1/player/" + id)).status, 404);
  assert.deepEqual(((await (await env.call("/v1/leaderboard")).json()) as { entries: unknown[] }).entries, []);
  // A second upload does not open a second flag for the same thing.
  const more = chain(drops("npc:589", 1, 31).map((event) => ({ ...event, count: 31 })), (env.raw.prepare("SELECT head_hash FROM ledger_state").get() as { head_hash: string }).head_hash);
  await env.call("/v1/ledger", { body: signedUpload(player, more, { snapshot: snapshot({ "npc:589": 31 }, { "npc:589": 200 }) }) });
  env.pretendVerified();
  assert.deepEqual(flagKinds(env), ["luck-hold"]);
  // After a person reviews and clears it, the player is back on the ladder.
  env.raw.prepare("UPDATE flags SET state = 'cleared'").run();
  assert.equal((await env.call("/v1/player/" + id)).status, 200);
});

test("ordinary luck and a big collection built over a long time raise no flag", async () => {
  const env = setup();
  const { player } = await registered(env);
  const response = await env.call("/v1/ledger", { body: signedUpload(player, chain(drops("npc:589", 5)), { snapshot: snapshot({ "npc:589": 5 }, { "npc:589": 400 }) }) });
  assert.equal(response.status, 200);
  assert.deepEqual(flagKinds(env), []);
});

test("a huge collection in a brand new account's first hour is flagged for a look", async () => {
  const env = setup();
  const { player } = await registered(env);
  const keys = Object.keys(catalog.cards).filter((key) => !catalog.cards[key]?.baseKey).slice(0, 210);
  const events = chain(keys.map((key, index) => ({ seq: index + 1, t: 1000 + index, kind: "drop", key, count: 1, ...base })));
  const counts = Object.fromEntries(keys.map((key) => [key, 1]));
  const attempts = Object.fromEntries(keys.map((key) => [key, 100]));
  const response = await env.call("/v1/ledger", { body: signedUpload(player, events, { snapshot: snapshot(counts, attempts) }) });
  assert.equal(response.status, 200);
  assert.deepEqual(flagKinds(env), ["fast-start"]);
});

test("using tape entries faster than a person could play is flagged", async () => {
  const env = setup();
  const { player } = await registered(env);
  const signed = async (path: string, extra: Record<string, unknown>) => env.call(path, { body: extra });
  void signed;
  const mode = (seq: number, key: string) => ({ seq, t: 1000 + seq, kind: "mode", key, count: 0, ...base });
  // Ranked needs an issued tape: ask for one, as the app would.
  const { createRequire } = await import("node:module");
  const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };
  const request = { key: player.publicKeyHex, sentAt: NOW };
  await env.call("/v1/tape", { body: { ...request, sig: reference.signBatch({ ...request, purpose: "tape" }, player.privateKey) } });
  const first = chain([mode(1, "ranked2")]);
  const empty = snapshot({}, {});
  assert.equal((await env.call("/v1/ledger", { body: signedUpload(player, first, { tapeIndex: 1, snapshot: empty }) })).status, 200);
  // Eleven minutes later it says it has used 400 entries: over 2,000 an hour.
  env.clock.now = NOW + 660;
  const second = chain([mode(2, "casual")], (env.raw.prepare("SELECT head_hash FROM ledger_state").get() as { head_hash: string }).head_hash);
  assert.equal((await env.call("/v1/ledger", { body: signedUpload(player, second, { tapeIndex: 400, sentAt: NOW + 660, snapshot: empty }) })).status, 200);
  assert.deepEqual(flagKinds(env), ["rate"]);
  // A slow, human pace over the next hour does not add another.
  env.clock.now = NOW + 7200;
  const third = chain([mode(3, "ranked2")], (env.raw.prepare("SELECT head_hash FROM ledger_state").get() as { head_hash: string }).head_hash);
  await env.call("/v1/ledger", { body: signedUpload(player, third, { tapeIndex: 500, sentAt: NOW + 7200, snapshot: empty }) });
  assert.deepEqual(flagKinds(env), ["rate"]);
});
