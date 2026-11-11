// Only Ranked counts (roadmap decision D5): a player with any Casual drop, which the server cannot recheck, is not
// listed on the ladder, and cards received in trades from such a player do not count for the other side.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { runMaintenance } from "../src/maintenance.ts";
import { rebuild } from "../src/rebuild.ts";
import { NOW, catalog, chain, chainedHistory, newPlayer, rankedHistory, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

async function register(env: ReturnType<typeof setup>, name: string) {
  const player = newPlayer(name);
  const body = await read(await env.call("/v1/register", { body: registration(player) }));
  return { player, id: body["playerId"] as string };
}
async function takeTape(env: ReturnType<typeof setup>, player: Player) {
  const request = { key: player.publicKeyHex, sentAt: NOW };
  await env.call("/v1/tape", { body: { ...request, sig: reference.signBatch({ ...request, purpose: "tape" }, player.privateKey) } });
}
const head = (env: ReturnType<typeof setup>) => (env.raw.prepare("SELECT head_hash FROM ledger_state WHERE player_id = (SELECT player_id FROM ledger_state ORDER BY rowid DESC LIMIT 1)").get() as { head_hash: string }).head_hash;
const ladder = async (env: ReturnType<typeof setup>) => ((await read(await env.call("/v1/leaderboard"))) as unknown as { entries: { playerId: string }[] }).entries.map((entry) => entry.playerId);
const scoreOfPlayer = (env: ReturnType<typeof setup>, id: string) => Number((env.raw.prepare("SELECT score FROM scores WHERE player_id = ?").get(id) as { score: number }).score);
const casualDrops = (env: ReturnType<typeof setup>, id: string) => Number((env.raw.prepare("SELECT casual_drops AS n FROM ledger_state WHERE player_id = ?").get(id) as { n: number }).n);

async function rankedPlayer(env: ReturnType<typeof setup>, name: string, extra: Record<string, unknown>[] = []) {
  const { player, id } = await register(env, name);
  await takeTape(env, player);
  const { events, tapeNext, attempts } = await rankedHistory(id, 2, "npc:589", `${name}-RealmName`);
  const all = extra.length > 0 ? chain([...events.map(({ prev, h, ...rest }) => { void prev; void h; return rest; }), ...extra.map((event, index) => ({ ...event, seq: events.length + index + 1, t: 5000 + index }))]) : events;
  const counts: Record<string, number> = { "npc:589": 2 };
  for (const event of extra) if (event["kind"] === "tradeIn") counts[String(event["key"])] = 1;
  const response = await env.call("/v1/ledger", {
    body: signedUpload(player, all, { character: name, realm: "RealmName", tapeIndex: tapeNext, snapshot: { counts, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} } }),
  });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  return { player, id };
}

test("a Ranked player is on the ladder; a player with Casual drops is stored and scored but never listed", async () => {
  const env = setup();
  const casual = await register(env, "casual");
  const response = await env.call("/v1/ledger", { body: signedUpload(casual.player, chainedHistory(), { character: "Casual", realm: "RealmName" }) });
  assert.equal(response.status, 200);
  assert.ok(casualDrops(env, casual.id) > 0);
  assert.ok(scoreOfPlayer(env, casual.id) > 0, "still stored and scored");
  assert.deepEqual(await ladder(env), []);
  assert.equal((await env.call("/v1/player/" + casual.id)).status, 404);

  const ranked = await rankedPlayer(env, "Ranked");
  assert.equal(casualDrops(env, ranked.id), 0);
  assert.deepEqual(await ladder(env), [ranked.id]);
  assert.equal((await env.call("/v1/player/" + ranked.id)).status, 200);
});

test("one Casual drop takes a Ranked player off the ladder", async () => {
  const env = setup();
  const ranked = await rankedPlayer(env, "Ranked");
  assert.deepEqual(await ladder(env), [ranked.id]);
  // They switch to Casual and a drop is rolled with the computer's own random numbers.
  const base = { dust: 0, shiny: 0, partner: "", trade: "", char: "Ranked-RealmName" };
  const later = chain([
    { seq: 0, t: 0, kind: "mode", key: "casual", count: 0, tape: 0, ...base },
    { seq: 0, t: 0, kind: "drop", key: "npc:589", count: 3, tape: 0, ...base },
  ].map((event, index) => ({ ...event, seq: ((env.raw.prepare("SELECT head_seq AS s FROM ledger_state WHERE player_id = ?").get(ranked.id) as { s: number }).s) + index + 1, t: 9000 + index })), head(env));
  const response = await env.call("/v1/ledger", {
    body: signedUpload(ranked.player, later, { character: "Ranked", realm: "RealmName", tapeIndex: 1, snapshot: { counts: { "npc:589": 3 }, dust: 0, sets: {}, attempts: { "npc:589": 500 }, titles: {} } }),
  });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  assert.equal(casualDrops(env, ranked.id), 1);
  assert.deepEqual(await ladder(env), []);
  assert.equal((await env.call("/v1/player/" + ranked.id)).status, 404);
});

test("cards received from a player with Casual drops do not count, even if the trade was recorded first", async () => {
  const env = setup();
  const trade = "111-482910-1";
  const tradeIn = { kind: "tradeIn", key: "npc:590", count: 1, dust: 0, shiny: 0, tape: 0, partner: "alice-realmname", trade, char: "Bob-RealmName" };
  // Bob plays Ranked and receives a card from Alice, who has not uploaded yet: for now it counts.
  const bob = await rankedPlayer(env, "Bob", [tradeIn]);
  const withTrade = scoreOfPlayer(env, bob.id);
  const alice = await register(env, "alice");
  // Alice's history is Casual: a drop, then the other half of the trade.
  const base = { dust: 0, shiny: 0, tape: 0, char: "Alice-RealmName" };
  const events = chain([
    { seq: 1, t: 1000, kind: "drop", key: "npc:590", count: 1, partner: "", trade: "", ...base },
    { seq: 2, t: 1010, kind: "tradeOut", key: "npc:590", count: 0, partner: "bob-realmname", trade, ...base },
  ]);
  const response = await env.call("/v1/ledger", {
    body: signedUpload(alice.player, events, { character: "Alice", realm: "RealmName", snapshot: { counts: {}, dust: 0, sets: {}, attempts: { "npc:590": 100 }, titles: {} } }),
  });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  assert.equal(casualDrops(env, alice.id), 1);
  assert.equal(scoreOfPlayer(env, bob.id), withTrade, "nothing has re-checked Bob yet");
  // The hourly job notices: Bob's copy came from a Casual player, so it stops counting.
  await runMaintenance(env.deps);
  const card = catalog.cards["npc:590"]!;
  const points = ({ common: 1, rare: 2, epic: 5, legendary: 10 } as Record<string, number>)[card.rarity] ?? 0;
  assert.equal(withTrade - scoreOfPlayer(env, bob.id), points * 10);
  assert.deepEqual(await ladder(env), [bob.id], "Bob is still on the ladder: only the borrowed card stopped counting");
  // Run again: nothing more changes.
  const settled = scoreOfPlayer(env, bob.id);
  await runMaintenance(env.deps);
  assert.equal(scoreOfPlayer(env, bob.id), settled);
});

test("a rebuild works out the Casual drops again from the stored events", async () => {
  const env = setup();
  const casual = await register(env, "casual");
  await env.call("/v1/ledger", { body: signedUpload(casual.player, chainedHistory(), { character: "Casual", realm: "RealmName" }) });
  const honest = casualDrops(env, casual.id);
  assert.ok(honest > 0);
  // Damaged: the count says no Casual drops, which would put the player on the ladder.
  env.raw.prepare("UPDATE ledger_state SET casual_drops = 0").run();
  assert.deepEqual(await ladder(env), [casual.id]);
  const dry = await rebuild(env.deps, { dryRun: true });
  assert.deepEqual(dry.changed.map((entry) => entry.differences), [["casual"]]);
  assert.equal(casualDrops(env, casual.id), 0, "a dry run changes nothing");
  await rebuild(env.deps);
  assert.equal(casualDrops(env, casual.id), honest);
  assert.deepEqual(await ladder(env), []);
});

// ---- following a card through more than one trade ----
import { computeTaint } from "../src/taint.ts";
import type { TradeHalf } from "../src/taint.ts";

const half = (playerId: string, seq: number, key: string, source: string | null, state: TradeHalf["state"] = "matched"): TradeHalf => ({ playerId, seq, key, state, source });
const ids = (rows: { playerId: string; seq: number }[]) => rows.map((row) => `${row.playerId}:${row.seq}`).sort();

test("a card is followed from a Casual player through every clean player it passes through", () => {
  // A has Casual drops and gave npc:590 to B, who gave it to C, who gave it to D.
  const chain = [half("B", 1, "npc:590", "A"), half("C", 1, "npc:590", "B"), half("D", 1, "npc:590", "C")];
  assert.deepEqual(ids(computeTaint(chain, ["A"])), ["B:1", "C:1", "D:1"]);
  // The order the halves are listed in does not matter.
  assert.deepEqual(ids(computeTaint([...chain].reverse(), ["A"])), ["B:1", "C:1", "D:1"]);
  // Without a Casual player at the start, nothing is untrusted.
  assert.deepEqual(computeTaint(chain, []), []);
  // A different card from a clean player is not affected: C got npc:591 from E, who is clean.
  assert.deepEqual(ids(computeTaint([...chain, half("C", 2, "npc:591", "E")], ["A"])), ["B:1", "C:1", "D:1"]);
  // A card from a player who holds an untrusted copy of that same card is untrusted (the cautious rule).
  assert.deepEqual(ids(computeTaint([half("B", 1, "npc:590", "A"), half("C", 1, "npc:590", "B"), half("C", 2, "npc:600", "B")], ["A"])), ["B:1", "C:1"]);
  // A copy from an unconfirmed trade makes the holder's copies of that card untrusted when passed on.
  assert.deepEqual(ids(computeTaint([half("B", 1, "npc:590", null, "unmatched"), half("C", 1, "npc:590", "B")], [])), ["C:1"]);
  // A loop of trades between untrusted players ends.
  assert.deepEqual(ids(computeTaint([half("B", 1, "npc:590", "A"), half("C", 1, "npc:590", "B"), half("B", 2, "npc:590", "C")], ["A"])), ["B:1", "B:2", "C:1"]);
});

test("a card passed from a Casual player to a clean one to a Ranked main stops counting for the main", async () => {
  const env = setup();
  const t1 = "111-482910-1"; // A gives B the card
  const t2 = "111-482910-2"; // B gives C the same card
  const pass = { dust: 0, shiny: 0, tape: 0 };
  const inFrom = (partner: string, trade: string, char: string) => ({ kind: "tradeIn", key: "npc:590", count: 1, ...pass, partner, trade, char });
  const outTo = (partner: string, trade: string, char: string) => ({ kind: "tradeOut", key: "npc:590", count: 0, ...pass, partner, trade, char });

  // C (the main) and B (the clean middle) both play Ranked; the trades are recorded before A's Casual play is known.
  const c = await rankedPlayer(env, "Carl", [inFrom("bert-realmname", t2, "Carl-RealmName")]);
  const b = await rankedPlayer(env, "Bert", [inFrom("alice-realmname", t1, "Bert-RealmName"), outTo("carl-realmname", t2, "Bert-RealmName")]);
  const before = scoreOfPlayer(env, c.id);
  await runMaintenance(env.deps);
  assert.equal(scoreOfPlayer(env, c.id), before, "nothing untrusted is known yet: A has not played");

  // Alice's Casual play arrives. Bert's copy came from her, so Bert's does not count, and neither does what he passed on to Carl.
  const alice = await register(env, "alice");
  const base = { dust: 0, shiny: 0, tape: 0, char: "Alice-RealmName" };
  const events = chain([
    { seq: 1, t: 1000, kind: "drop", key: "npc:590", count: 1, partner: "", trade: "", ...base },
    { seq: 2, t: 1010, kind: "tradeOut", key: "npc:590", count: 0, partner: "bert-realmname", trade: t1, ...base },
  ]);
  const response = await env.call("/v1/ledger", { body: signedUpload(alice.player, events, { character: "Alice", realm: "RealmName", snapshot: { counts: {}, dust: 0, sets: {}, attempts: { "npc:590": 100 }, titles: {} } }) });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  const points = ({ common: 1, rare: 2, epic: 5, legendary: 10 } as Record<string, number>)[catalog.cards["npc:590"]!.rarity] ?? 0;
  const bertBefore = scoreOfPlayer(env, b.id);
  await runMaintenance(env.deps);
  assert.equal(before - scoreOfPlayer(env, c.id), points * 10, "Carl's copy came from Casual play, two trades back");
  assert.equal(scoreOfPlayer(env, b.id), bertBefore, "Bert passed the card on, so he holds nothing untrusted to lose");
  assert.equal(new Set(await ladder(env)).has(c.id), true, "both are still on the ladder: only the borrowed card stopped counting");

  // Running again changes nothing further.
  const settled = scoreOfPlayer(env, c.id);
  await runMaintenance(env.deps);
  assert.equal(scoreOfPlayer(env, c.id), settled);
});
