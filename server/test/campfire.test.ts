// The campfire boost on the server (ledger spec 12, docs/CAMPFIRE.md): an attempt written down as boosted (partner "camp") is checked against double the
// chance, one that is not is checked as before, and a binder that has recorded mode/camp1 needs a companion that says spec 12. The server cannot see the
// camp, so what it holds the binder to is the roll: a boosted miss has to be a miss at double the chance, and a boosted drop has to win at it.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import { chanceFor } from "../../packages/shared/src/drops.js";
import { TAPE_SECRET, catalog, chain, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import { rollValue, shinyValue, tapeEntry, tapeKey } from "../src/tape.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string; detail?: Record<string, unknown> } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };
const NPC = "npc:589";
const char = "Ann-Realm";

async function registered(env: ReturnType<typeof setup>) {
  const player = newPlayer("camper");
  const body = await read(await env.call("/v1/register", { body: registration(player) }));
  const request = { key: player.publicKeyHex, sentAt: 1_700_000_000 };
  await env.call("/v1/tape", { body: { ...request, sig: reference.signBatch({ ...request, purpose: "tape" }, player.privateKey) } });
  return { player, id: body["playerId"] as string };
}

type Part = { kind: string; key: string; count: number; tape?: number; partner?: string; shiny?: number };
const markers = ["chase1", "chase2", "launch1", "faction1", "camp1"].map((key): Part => ({ kind: "mode", key, count: 0 }));
const toEvents = (parts: Part[], base = 0) => chain(parts.map((part, index) => ({
  seq: base + index + 1, t: 1000 + index * 10, kind: part.kind, key: part.key, count: part.count, dust: 0, shiny: part.shiny ?? 0, tape: part.tape ?? 0, partner: part.partner ?? "", trade: "", char,
})));

// Play the tape for a card: every attempt boosted or not, as told, written down as the add-on would. Returns the parts, the next tape position, and
// the attempts where the boost made the difference (a roll above the plain chance and within the doubled one).
async function play(id: string, attempts: number, boost: boolean) {
  const key = await tapeKey(TAPE_SECRET);
  const parts: Part[] = [...markers, { kind: "mode", key: "ranked2", count: 0 }, { kind: "camp", key: "violet", count: 7200 }];
  let misses = 0, run = 0, owned = 0, shinyOwned = false;
  const differing: number[] = [];
  const flush = (at: number) => { if (run > 0) parts.push({ kind: "miss", key: NPC, count: run, tape: at - 1, ...(boost ? { partner: "camp" } : {}) }); run = 0; };
  for (let position = 1; position <= attempts; position++) {
    const entry = await tapeEntry(key, id, position);
    const roll = rollValue(entry);
    const plain = chanceFor(catalog, NPC, misses, 2);
    const chance = Math.min(10000, plain * (boost ? 2 : 1));
    if (roll > plain && roll <= Math.min(10000, plain * 2)) differing.push(position);
    if (roll <= chance) {
      flush(position);
      owned += 1;
      const shiny = !shinyOwned && shinyValue(entry, catalog.shinyOdds) === 1; // the first copy is shiny exactly when its entry says so
      if (shiny) shinyOwned = true;
      parts.push({ kind: "drop", key: NPC, count: owned, tape: position, shiny: shiny ? 1 : 0, ...(boost ? { partner: "camp" } : {}) });
      misses = 0;
    } else { run += 1; misses += 1; }
  }
  flush(attempts + 1);
  return { parts, tapeNext: attempts + 1, owned, differing };
}
const upload = (env: ReturnType<typeof setup>, player: Player, parts: Part[], tapeIndex: number, owned: number, specVersion = 12) =>
  env.call("/v1/ledger", { body: signedUpload(player, toEvents(parts), { specVersion, character: "Ann", realm: "Realm", tapeIndex, snapshot: { counts: { [NPC]: owned }, dust: 0, sets: {}, attempts: { [NPC]: 0 }, titles: {} } }) });

test("a history played at the boosted chance is accepted, and its attempts count double in the luck statistics", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  // A long enough stretch that the boost changes at least one outcome.
  let attempts = 60, played = await play(id, attempts, true);
  while (played.differing.length === 0) played = await play(id, (attempts += 40), true);
  const response = await upload(env, player, played.parts, played.tapeNext, played.owned);
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  const state = JSON.parse((env.raw.prepare("SELECT state_json FROM ledger_state").get() as { state_json: string }).state_json) as { camp: number; campEnd: number; campBoosted: number; balanceAttempts: Record<string, number> };
  assert.equal(state.camp, 1);
  assert.equal(state.campEnd, 1000 + 6 * 10 + 7200, "the claim: the camp event is the seventh event");
  assert.equal(state.campBoosted > 0, true);
  const plainAttempts = attempts - state.campBoosted; // the attempts that began the statistics (a card's first drop) were not counted
  assert.ok((state.balanceAttempts[NPC] ?? 0) >= state.campBoosted, "boosted attempts count twice: " + JSON.stringify({ plainAttempts, state }));
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM flags WHERE kind LIKE 'luck%'").get()!["n"], 0);
});

test("the same attempts written down as plain are refused where the boost made the difference, and boosted ones where it did not hold", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  let attempts = 60, boosted = await play(id, attempts, true);
  while (boosted.differing.length === 0) boosted = await play(id, (attempts += 40), true);
  // The binder played at the doubled chance but says its attempts were plain: a drop it should not have had.
  const plain = boosted.parts.map((part) => (part.partner === "camp" ? { ...part, partner: "" } : part));
  const refused = await read(await upload(env, player, plain, boosted.tapeNext, boosted.owned));
  assert.equal(refused.error?.code, "tape_invalid", JSON.stringify(refused));
  assert.equal(refused.error?.detail?.["reason"], "roll");
  // The binder played plain but claims the boost for its misses: a miss at double the chance has to beat a higher bar.
  const honestPlain = await play(id, attempts, false);
  const claimed = honestPlain.parts.map((part) => (part.kind === "miss" || part.kind === "drop" ? { ...part, partner: "camp" } : part));
  const needs = honestPlain.differing.length > 0;
  const body = await read(await upload(env, player, claimed, honestPlain.tapeNext, honestPlain.owned));
  if (needs) assert.equal(body.error?.detail?.["reason"], "roll", JSON.stringify(body)); else assert.equal(body.error, undefined);
});

test("a boosted drop outside its claimed buff, or with no camp claim at all, is refused by the rules before the tape", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  const parts: Part[] = [...markers, { kind: "mode", key: "ranked2", count: 0 }, { kind: "drop", key: NPC, count: 1, tape: 1, partner: "camp" }];
  void id;
  const body = await read(await upload(env, player, parts, 2, 1));
  assert.equal(body.error?.code, "rule_broken", JSON.stringify(body));
  assert.equal(body.error?.detail?.["rule"], "camp");
});

test("a binder that has recorded mode/camp1 needs a companion that says spec 12, even for an empty upload", async () => {
  const env = setup();
  const { player } = await registered(env);
  const all = toEvents(markers);
  const send = (events: Record<string, unknown>[], specVersion: number) =>
    env.call("/v1/ledger", { body: signedUpload(player, events, { specVersion, character: "Ann", realm: "Realm", tapeIndex: 1, snapshot: { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} } }) });
  assert.equal((await send(all.slice(0, 4), 11)).status, 200, "spec 11 is fine until the marker");
  const refused = await send(all.slice(4), 11);
  assert.equal(refused.status, 426);
  assert.equal(((await refused.json()) as Body).error?.code, "client_too_old");
  const accepted = await send(all.slice(4), 12);
  assert.equal(accepted.status, 200, JSON.stringify(await accepted.clone().json()));
  // Now the stored binder is on spec 12: an empty upload from an older companion is refused too.
  assert.equal((await send([], 11)).status, 426);
  assert.equal((await send([], 12)).status, 200);
  void canonicalJson;
});
