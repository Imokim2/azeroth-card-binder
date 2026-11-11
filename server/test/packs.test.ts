// Card packs: found on one attempt in 500, five cards from the zone, all decided by tape entries the server can recompute.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import { PACK_SIZE, packPick, packValue } from "../src/shared.ts";
import { chanceAfter } from "../src/stack.ts";
import { rollValue, shinyValue, tapeEntry, tapeKey } from "../src/tape.ts";
import { NOW, TAPE_SECRET, catalog, chain, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string; detail?: Record<string, unknown> } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

const CARD = "npc:589"; // a common card of Westfall
const ZONE = catalog.cards[CARD]!.set;

// Register players until one has a pack on an early entry of their tape (about one in three do, within 200).
async function playerWithPack(env: ReturnType<typeof setup>) {
  for (let attempt = 0; attempt < 40; attempt++) {
    const player = newPlayer("pack" + attempt);
    const registered = await read(await env.call("/v1/register", { body: registration(player) }));
    const id = registered["playerId"] as string;
    const request = { key: player.publicKeyHex, sentAt: NOW };
    await env.call("/v1/tape", { body: { ...request, sig: reference.signBatch({ ...request, purpose: "tape" }, player.privateKey) } });
    const key = await tapeKey(TAPE_SECRET);
    for (let position = 2; position <= 200; position++) {
      if (packValue(await tapeEntry(key, id, position), catalog.shinyOdds) === 1) return { player, id, position };
    }
  }
  throw new Error("no player with a pack in 40 tries");
}

// A position that does not hold a pack, for a forged find.
async function plainPosition(id: string): Promise<number> {
  const key = await tapeKey(TAPE_SECRET);
  for (let position = 3; ; position++) if (packValue(await tapeEntry(key, id, position), catalog.shinyOdds) !== 1) return position;
}

// An honest Ranked history of `packAt` attempts on one card, a pack found on the last, opened at once. Misses are written as
// runs and the attempt that finds the pack ends its run, as the add-on does. `forge` may change the cards of the pack.
async function packPlay(id: string, packAt: number, open = true) {
  const key = await tapeKey(TAPE_SECRET);
  const rate = catalog.rates[catalog.cards[CARD]!.rank] ?? 0;
  const base = { dust: 0, partner: "", trade: "", char: "Alice-RealmName" };
  const partials: Record<string, unknown>[] = [];
  const push = (event: Record<string, unknown>) => partials.push({ seq: partials.length + 1, t: 1000 + partials.length * 10, shiny: 0, tape: 0, count: 0, ...base, ...event });
  push({ kind: "mode", key: "ranked2" });
  const counts: Record<string, number> = {};
  const shinyHad = new Set<string>();
  let misses = 0;
  let run = 0;
  const flush = (tape: number) => { if (run > 0) { push({ kind: "miss", key: CARD, count: run, tape }); run = 0; } };
  for (let position = 1; position <= packAt; position++) {
    const entry = await tapeEntry(key, id, position);
    if (rollValue(entry) > chanceAfter(rate, misses, catalog.stackFactor)) {
      misses++;
      run++;
      if (position === packAt) flush(position);
      continue;
    }
    flush(position - 1);
    misses = 0;
    counts[CARD] = (counts[CARD] ?? 0) + 1;
    const shiny = !shinyHad.has(CARD) && shinyValue(entry, catalog.shinyOdds) === 1;
    if (shiny) shinyHad.add(CARD);
    push({ kind: "drop", key: CARD, count: counts[CARD], shiny: shiny ? 1 : 0, tape: position });
  }
  push({ kind: "packFind", key: ZONE, count: 1, tape: packAt });
  if (open) {
    push({ kind: "packOpen", key: ZONE, count: 0, tape: packAt });
    for (let step = 1; step <= PACK_SIZE; step++) {
      const entry = await tapeEntry(key, id, packAt + step);
      const card = packPick(catalog, ZONE, entry, catalog.shinyOdds)!;
      counts[card] = (counts[card] ?? 0) + 1;
      const shiny = !shinyHad.has(card) && shinyValue(entry, catalog.shinyOdds) === 1;
      if (shiny) shinyHad.add(card);
      push({ kind: "packCard", key: card, count: counts[card], shiny: shiny ? 1 : 0, tape: packAt + step });
    }
  }
  return { partials, events: chain(partials), counts, tapeNext: packAt + (open ? PACK_SIZE : 0) + 1, attempts: packAt };
}

const upload = (env: ReturnType<typeof setup>, player: Player, events: Record<string, unknown>[], counts: Record<string, number>, attempts: number, tapeIndex: number, extra: Record<string, unknown> = {}) =>
  env.call("/v1/ledger", { body: signedUpload(player, events, { tapeIndex, snapshot: { counts, dust: 0, sets: {}, attempts: { [CARD]: attempts }, titles: {} }, ...extra }) });
const stateOf = (env: ReturnType<typeof setup>) => JSON.parse((env.raw.prepare("SELECT state_json FROM ledger_state").get() as { state_json: string }).state_json) as Record<string, unknown>;
const strip = (event: Record<string, unknown>) => { const { prev, h, ...rest } = event; void prev; void h; return rest; };

test("a pack found and opened is accepted: the five cards are what the entries give, and they count", async () => {
  const env = setup();
  const { player, id, position } = await playerWithPack(env);
  const play = await packPlay(id, position);
  const response = await upload(env, player, play.events, play.counts, play.attempts, play.tapeNext);
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  const state = stateOf(env);
  assert.deepEqual(state["packs"], {}, "the pack was opened");
  assert.equal(state["packLeft"], 0);
  assert.deepEqual(state["counts"], play.counts);
  assert.equal((env.raw.prepare("SELECT casual_drops AS n FROM ledger_state").get() as { n: number }).n, 0, "Ranked cards from a pack are not Casual drops");
  // Found but not opened yet: the pack is held.
  const env2 = setup();
  const second = await playerWithPack(env2);
  const held = await packPlay(second.id, second.position, false);
  assert.equal((await upload(env2, second.player, held.events, held.counts, held.attempts, held.tapeNext)).status, 200);
  assert.deepEqual(stateOf(env2)["packs"], { [ZONE]: 1 });
});

test("a pack cannot be made up: the entry must say a pack was found", async () => {
  const env = setup();
  const { player, id } = await playerWithPack(env);
  const position = await plainPosition(id);
  const forged = await packPlay(id, position);
  const body = await read(await upload(env, player, forged.events, forged.counts, forged.attempts, forged.tapeNext));
  assert.equal(body.error?.code, "tape_invalid", JSON.stringify(body));
  assert.equal(body.error?.detail?.["reason"], "pack");
});

test("the cards of a pack cannot be chosen: a different card, or a different shiny flag, is refused", async () => {
  const env = setup();
  const { player, id, position } = await playerWithPack(env);
  const play = await packPlay(id, position);
  const firstCard = play.partials.findIndex((event) => event["kind"] === "packCard");
  const other = catalog.sets.find((set) => set.code === ZONE)!.cards.find((key) => key !== play.partials[firstCard]!["key"] && !play.counts[key])!;
  const change = (mutate: (event: Record<string, unknown>) => Record<string, unknown>) => chain(play.partials.map((event, index) => (index === firstCard ? mutate(strip(event)) : strip(event))));
  const swapped = await read(await upload(env, player, change((event) => ({ ...event, key: other, count: 1, shiny: 0 })), { ...play.counts, [other]: 1 }, play.attempts, play.tapeNext));
  assert.equal(swapped.error?.code, "tape_invalid", JSON.stringify(swapped));
  assert.equal(swapped.error?.detail?.["reason"], "pack");
  const flipped = await read(await upload(env, player, change((event) => ({ ...event, shiny: event["shiny"] === 1 ? 0 : 1 })), play.counts, play.attempts, play.tapeNext));
  assert.equal(flipped.error?.code, "tape_invalid", JSON.stringify(flipped));
  assert.equal(flipped.error?.detail?.["reason"], "shiny");
  // Nothing was stored, and the honest version still goes through.
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get() as { n: number }).n, 0);
  assert.equal((await upload(env, player, play.events, play.counts, play.attempts, play.tapeNext)).status, 200);
});

test("a pack of the wrong zone, or a pack with the wrong tape position, breaks the rules before the tape is looked at", async () => {
  const env = setup();
  const { player, id, position } = await playerWithPack(env);
  const play = await packPlay(id, position);
  const find = play.partials.findIndex((event) => event["kind"] === "packFind");
  const otherZone = catalog.sets.find((set) => set.code !== ZONE && set.code !== "GA")!.code;
  const wrongZone = chain(play.partials.slice(0, find + 1).map((event, index) => (index === find ? { ...strip(event), key: otherZone } : strip(event))));
  const zoneBody = await read(await upload(env, player, wrongZone, play.counts, play.attempts, position + 1));
  assert.equal(zoneBody.error?.code, "rule_broken", JSON.stringify(zoneBody));
  assert.equal(zoneBody.error?.detail?.["rule"], "pack");
  const early = chain(play.partials.slice(0, find + 1).map((event, index) => (index === find ? { ...strip(event), tape: position - 1 } : strip(event))));
  const tapeBody = await read(await upload(env, player, early, play.counts, play.attempts, position + 1));
  assert.equal(tapeBody.error?.code, "rule_broken", JSON.stringify(tapeBody));
  assert.equal(tapeBody.error?.detail?.["rule"], "tape");
});

test("a pack can be opened across two uploads, and the cards are still checked in the second", async () => {
  const env = setup();
  const { player, id, position } = await playerWithPack(env);
  const play = await packPlay(id, position);
  const split = play.events.findIndex((event) => event["kind"] === "packCard") + 2; // two cards in the first upload
  const firstCounts: Record<string, number> = {};
  for (const event of play.events.slice(0, split)) if (event["kind"] === "drop" || event["kind"] === "packCard") firstCounts[String(event["key"])] = Number(event["count"]);
  const first = await upload(env, player, play.events.slice(0, split), firstCounts, play.attempts, position + 3);
  assert.equal(first.status, 200, JSON.stringify(await first.clone().json()));
  assert.equal(stateOf(env)["packLeft"], PACK_SIZE - 2);
  const second = await upload(env, player, play.events.slice(split), play.counts, play.attempts, play.tapeNext, { sentAt: NOW + 1 });
  assert.equal(second.status, 200, JSON.stringify(await second.clone().json()));
  assert.equal(stateOf(env)["packLeft"], 0);

  // The same split, with a wrong card in the second part.
  const env2 = setup();
  const again = await playerWithPack(env2);
  const play2 = await packPlay(again.id, again.position);
  const cardAt = play2.partials.findIndex((event) => event["kind"] === "packCard") + 3;
  const other = catalog.sets.find((set) => set.code === ZONE)!.cards.find((key) => key !== play2.partials[cardAt]!["key"] && !play2.counts[key])!;
  const bad = chain(play2.partials.map((event, index) => (index === cardAt ? { ...strip(event), key: other, count: 1, shiny: 0 } : strip(event))));
  const cut = play2.partials.findIndex((event) => event["kind"] === "packCard") + 2;
  const firstOk = await upload(env2, again.player, bad.slice(0, cut), (() => { const c: Record<string, number> = {}; for (const e of bad.slice(0, cut)) if (e["kind"] === "drop" || e["kind"] === "packCard") c[String(e["key"])] = Number(e["count"]); return c; })(), play2.attempts, again.position + 3);
  assert.equal(firstOk.status, 200);
  const refused = await read(await upload(env2, again.player, bad.slice(cut), { ...play2.counts, [other]: 1 }, play2.attempts, play2.tapeNext, { sentAt: NOW + 1 }));
  assert.equal(refused.error?.code, "tape_invalid", JSON.stringify(refused));
  assert.equal(refused.error?.detail?.["reason"], "pack");
});

test("the pack arithmetic: one in 500, five cards, and the rarities share what a zone has", () => {
  assert.equal(PACK_SIZE, 5);
  const hex8 = (n: number) => n.toString(16).padStart(8, "0");
  // The second half of an entry decides the pack: 20 is the shiny odds, so 0 to 19 are the first of each 500.
  assert.equal(packValue(hex8(0) + hex8(0), catalog.shinyOdds), 1);
  assert.equal(packValue(hex8(0) + hex8(19), catalog.shinyOdds), 1);
  assert.equal(packValue(hex8(0) + hex8(20), catalog.shinyOdds), 2);
  assert.equal(packValue(hex8(0) + hex8(20 * 500), catalog.shinyOdds), 1);
  // About one entry in 500 finds a pack over a large sample.
  let found = 0;
  for (let index = 0; index < 50_000; index++) if (packValue(hex8(0) + hex8((index * 2_654_435_761) % 4_294_967_296), catalog.shinyOdds) === 1) found++;
  assert.ok(found > 60 && found < 140, `found ${found} in 50,000`);
  // A zone of common and epic cards only never gives a legendary or a rare; the rarest roll still gives an epic.
  const rarityOf = (zone: string, roll: number) => catalog.cards[packPick(catalog, zone, hex8(roll - 1) + hex8(0), catalog.shinyOdds)!]!.rarity;
  assert.equal(rarityOf("AHX", 1), "common");
  assert.equal(rarityOf("AHX", 10000), "epic");
  assert.equal(rarityOf("ABX", 10000), "common", "a zone of common cards only gives common cards");
  assert.equal(rarityOf("AQT", 10000), "legendary");
  assert.equal(packPick(catalog, "NOPE", hex8(0) + hex8(0), catalog.shinyOdds), null);
  void canonicalJson;
});
