// Trade matching (roadmap C5), the firsts feed (C6) and the characters on the leaderboard (C3/C4).
import assert from "node:assert/strict";
import test from "node:test";
import { TRADE_GRACE_SECONDS, runMaintenance } from "../src/maintenance.ts";
import { scoreOf } from "../src/score.ts";
import { NOW, catalog, chain, newPlayer, registration, setup, signedUpload } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };
const read = async (response: Response) => (await response.json()) as Body;

async function registered(env: ReturnType<typeof setup>, name: string) {
  const player = newPlayer(name);
  const body = await read(await env.call("/v1/register", { body: registration(player) }));
  return { player, id: body["playerId"] as string };
}

const CARD_A = "npc:589"; // what Alice starts with
const CARD_B = "npc:590"; // what Bob starts with
const trade = "111-482910-1";

function half(char: string, partner: string, mine: string, theirs: string) {
  const base = { dust: 0, shiny: 0, tape: 0, char };
  return chain([
    { seq: 1, t: 1000, kind: "drop", key: mine, count: 1, partner: "", trade: "", ...base },
    { seq: 2, t: 1010, kind: "tradeOut", key: mine, count: 0, partner, trade, ...base },
    { seq: 3, t: 1010, kind: "tradeIn", key: theirs, count: 1, partner, trade, ...base },
  ]);
}
const snapshot = (key: string) => ({ counts: { [key]: 1 }, dust: 0, sets: {}, attempts: { [CARD_A]: 100, [CARD_B]: 100 }, titles: {} });
const alicesHalf = () => half("Alice-RealmName", "bob-realmname", CARD_A, CARD_B);
const bobsHalf = () => half("Bob-RealmName", "alice-realmname", CARD_B, CARD_A);
// These histories are Casual; the tests are about trade matching, so the players stand in for ones whose drops are all Ranked.
const upload = async (env: ReturnType<typeof setup>, player: ReturnType<typeof newPlayer>, who: string, events: Record<string, unknown>[], got: string) => {
  const response = await env.call("/v1/ledger", { body: signedUpload(player, events, { character: who, realm: "RealmName", snapshot: snapshot(got), sentAt: env.clock.now }) });
  env.pretendVerified();
  return response;
};
const states = (env: ReturnType<typeof setup>) => (env.raw.prepare("SELECT state, COUNT(*) AS n FROM trades GROUP BY state").all() as { state: string; n: number }[]).map((row) => ({ state: row.state, n: row.n }));
const scoreOfPlayer = (env: ReturnType<typeof setup>, id: string) => (env.raw.prepare("SELECT score FROM scores WHERE player_id = ?").get(id) as { score: number }).score;
const flagKinds = (env: ReturnType<typeof setup>) => (env.raw.prepare("SELECT kind FROM flags ORDER BY kind").all() as { kind: string }[]).map((row) => row.kind);

test("both halves of a trade, uploaded by the two players, match and nothing is flagged", async () => {
  const env = setup();
  const alice = await registered(env, "alice");
  const bob = await registered(env, "bob");
  assert.equal((await upload(env, alice.player, "Alice", alicesHalf(), CARD_B)).status, 200);
  assert.equal((await upload(env, bob.player, "Bob", bobsHalf(), CARD_A)).status, 200);
  assert.deepEqual(states(env), [{ state: "open", n: 4 }]);
  const result = await runMaintenance(env.deps);
  assert.equal(result.unmatched, 0);
  assert.deepEqual(states(env), [{ state: "matched", n: 4 }]);
  env.clock.now = NOW + TRADE_GRACE_SECONDS + 100;
  assert.equal((await runMaintenance(env.deps)).unmatched, 0, "matched halves are never written off");
  assert.deepEqual(flagKinds(env), []);
});

test("a half nobody confirms is flagged after a week and stops counting, and counts again if the partner turns up", async () => {
  const env = setup();
  const alice = await registered(env, "alice");
  const bob = await registered(env, "bob");
  await upload(env, alice.player, "Alice", alicesHalf(), CARD_B);
  const before = scoreOfPlayer(env, alice.id);
  assert.ok(before > 0);
  // Inside the week nothing happens.
  env.clock.now = NOW + TRADE_GRACE_SECONDS - 60;
  assert.equal((await runMaintenance(env.deps)).unmatched, 0);
  assert.equal(scoreOfPlayer(env, alice.id), before);
  // After it, the received card no longer counts, and the player is flagged for a look.
  env.clock.now = NOW + TRADE_GRACE_SECONDS + 60;
  assert.equal((await runMaintenance(env.deps)).unmatched, 2);
  assert.deepEqual(flagKinds(env), ["trade-unmatched"]);
  assert.equal(scoreOfPlayer(env, alice.id), 0);
  // Running it again does not flag again.
  assert.equal((await runMaintenance(env.deps)).unmatched, 0);
  assert.deepEqual(flagKinds(env), ["trade-unmatched"]);
  // The partner uploads late: the halves match and the score comes back.
  await upload(env, bob.player, "Bob", bobsHalf(), CARD_A);
  const result = await runMaintenance(env.deps);
  assert.equal(result.matchedBack, 1);
  assert.equal(scoreOfPlayer(env, alice.id), before);
});

test("a trade half that names the wrong partner, card or trade id does not match", async () => {
  const env = setup();
  const alice = await registered(env, "alice");
  const bob = await registered(env, "bob");
  await upload(env, alice.player, "Alice", alicesHalf(), CARD_B);
  // Bob's half names someone else as his partner.
  await upload(env, bob.player, "Bob", half("Bob-RealmName", "carol-realmname", CARD_B, CARD_A), CARD_A);
  await runMaintenance(env.deps);
  assert.deepEqual(states(env), [{ state: "open", n: 4 }]);
});

test("the score rule leaves a finished set alone when a card was traded away, and drops it when its cards were never confirmed", () => {
  const set = catalog.sets.filter((entry) => entry.cards.every((key) => key.startsWith("npc:"))).sort((a, b) => a.cards.length - b.cards.length || a.code.localeCompare(b.code))[0]!;
  const counts = Object.fromEntries(set.cards.map((key) => [key, 1]));
  const state = { counts, dust: 0, shiny: {}, sets: { [set.code]: true }, mode: "casual", lastTape: 0, lastT: 0 };
  const full = scoreOf(catalog, state);
  assert.equal(full.setsDone, 1);
  // One card traded away afterwards: the set still counts as done (the card itself no longer scores).
  const away = { ...state, counts: { ...counts } };
  delete (away.counts as Record<string, number>)[set.cards[0]!];
  assert.equal(scoreOf(catalog, away).setsDone, 1);
  assert.equal(scoreOf(catalog, away).uniqueCards, set.cards.length - 1);
  // That card came only from a trade nobody confirmed: it does not count, and neither does the set it finished.
  const unconfirmed = scoreOf(catalog, state, { [set.cards[0]!]: 1 });
  assert.equal(unconfirmed.setsDone, 0);
  assert.equal(unconfirmed.uniqueCards, set.cards.length - 1);
  assert.ok(unconfirmed.score < full.score);
  // A card owned twice, one copy from an unconfirmed trade, still counts once.
  assert.deepEqual(scoreOf(catalog, { ...state, counts: { ...counts, [set.cards[0]!]: 2 } }, { [set.cards[0]!]: 1 }), full);
});

// A history that collects and finishes the smallest all-creature set, for the firsts feed.
const smallest = catalog.sets.filter((entry) => entry.cards.every((key) => key.startsWith("npc:"))).sort((a, b) => a.cards.length - b.cards.length || a.code.localeCompare(b.code))[0]!;
function finishing(char: string) {
  const base = { dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char };
  const events = smallest.cards.map((key, index) => ({ seq: index + 1, t: 1000 + index, kind: "drop", key, count: 1, ...base }));
  events.push({ seq: events.length + 1, t: 2000, kind: "set", key: smallest.code, count: 0, ...base });
  return chain(events);
}
async function finish(env: ReturnType<typeof setup>, player: ReturnType<typeof newPlayer>, who: string) {
  const counts = Object.fromEntries(smallest.cards.map((key) => [key, 1]));
  const attempts = Object.fromEntries(smallest.cards.map((key) => [key, 100]));
  const body = signedUpload(player, finishing(`${who}-RealmName`), {
    character: who, realm: "RealmName", sentAt: env.clock.now, snapshot: { counts, dust: 0, sets: { [smallest.code]: true }, attempts, titles: {} },
  });
  const response = await env.call("/v1/ledger", { body });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  env.pretendVerified();
}

test("the firsts feed names whoever finished a set first, skips players held off the ladder, and the leaderboard lists characters", async () => {
  const env = setup();
  const alice = await registered(env, "alice");
  const bob = await registered(env, "bob");
  assert.deepEqual(((await read(await env.call("/v1/firsts"))) as { firsts: unknown[] }).firsts, []);
  await finish(env, alice.player, "Alice");
  env.clock.now = NOW + 100;
  await finish(env, bob.player, "Bob");
  let feed = (await read(await env.call("/v1/firsts"))) as { firsts: { setCode: string; title: string; displayName: string; playerId: string; at: number }[] };
  assert.equal(feed.firsts.length, 1);
  assert.deepEqual([feed.firsts[0]?.setCode, feed.firsts[0]?.title, feed.firsts[0]?.displayName, feed.firsts[0]?.at], [smallest.code, smallest.title, "Alice-RealmName", NOW]);
  assert.equal(feed.firsts[0]?.playerId, alice.id);
  // The leaderboard carries each ranked player's characters, in the form partners are named by.
  const board = (await read(await env.call("/v1/leaderboard"))) as { entries: { playerId: string; characters: string[] }[] };
  assert.deepEqual(board.entries.find((entry) => entry.playerId === alice.id)?.characters, ["alice-realmname"]);
  assert.deepEqual(board.entries.find((entry) => entry.playerId === bob.id)?.characters, ["bob-realmname"]);
  // If the first to finish is held off the ladder, the next one is first.
  env.raw.prepare("INSERT INTO flags (id, player_id, kind, notes, created_at) VALUES ('f1', ?, 'luck-hold', '', ?)").run(alice.id, NOW);
  feed = (await read(await env.call("/v1/firsts"))) as typeof feed;
  assert.equal(feed.firsts[0]?.playerId, bob.id);
  assert.equal(feed.firsts[0]?.at, NOW + 100);
  // Unknown routes and methods are refused as usual.
  assert.equal((await env.call("/v1/firsts", { method: "POST", body: {} })).status, 405);
});
