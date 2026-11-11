// Ranked random numbers: the server issues the tape, and every ranked drop is checked against it.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import { attemptsNeeded, chanceAfter } from "../src/stack.ts";
import { REFILL_BELOW, TAPE_SIZE, rollValue, shinyValue, tapeCommitment, tapeEntry, tapeKey } from "../src/tape.ts";
import { NOW, TAPE_SECRET, catalog, chain, newPlayer, rankedHistory, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string; detail?: Record<string, unknown> } };
const read = async (response: Response) => (await response.json()) as Body;

async function registered(env: ReturnType<typeof setup>, name = "alice") {
  const player = newPlayer(name);
  const body = await read(await env.call("/v1/register", { body: registration(player) }));
  return { player, id: body["playerId"] as string };
}

// A signed request for the tape. `purpose` is part of what is signed, so a signature made for another purpose fails.
function tapeRequest(player: Player, extra: Record<string, unknown> = {}, purpose = "tape") {
  const body = { key: player.publicKeyHex, sentAt: NOW, ...extra };
  return { ...body, sig: signWith(player, canonicalJson({ ...body, purpose })) };
}

import { createRequire } from "node:module";
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };
function signWith(player: Player, canonical: string): string {
  // The reference signer signs the canonical JSON of an object; hand it the same object by parsing the canonical text.
  return reference.signBatch(JSON.parse(canonical), player.privateKey);
}

test("the tape is issued once, is the same on every request, and differs from player to player", async () => {
  const env = setup();
  const alice = await registered(env, "alice");
  const bob = await registered(env, "bob");
  const first = await read(await env.call("/v1/tape", { body: tapeRequest(alice.player) }));
  const entries = first["entries"] as string[];
  assert.equal(first["start"], 1);
  assert.equal(entries.length, TAPE_SIZE);
  assert.ok(entries.every((entry) => /^[0-9a-f]{16}$/.test(entry)));
  const issued = first["issued"] as { start: number; end: number; commitment: string };
  assert.deepEqual([issued.start, issued.end], [1, TAPE_SIZE]);
  assert.equal(issued.commitment, await tapeCommitment(entries));
  // Asking again returns the same entries and issues nothing new.
  const again = await read(await env.call("/v1/tape", { body: tapeRequest(alice.player, { sentAt: NOW + 5 }) }));
  assert.deepEqual(again["entries"], entries);
  assert.equal(again["issued"], null);
  // Another player's tape is different, and each entry matches its derivation from the secret.
  const other = (await read(await env.call("/v1/tape", { body: tapeRequest(bob.player) })))["entries"] as string[];
  assert.notDeepEqual(other.slice(0, 20), entries.slice(0, 20));
  const key = await tapeKey(TAPE_SECRET);
  assert.equal(entries[41], await tapeEntry(key, alice.id, 42));
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM tapes").get()?.["n"], 2);
});

test("a refill is issued only when 2,000 or fewer entries are unused, and always starts where the old one ended", async () => {
  const env = setup();
  const { player } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  // The add-on says it will next use entry 7,500: 2,500 unused, not yet time.
  const history = chain([{ seq: 1, t: 1000, kind: "mode", key: "casual", count: 0, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Alice-RealmName" }]);
  const upload = (tapeIndex: number, events = history) => env.call("/v1/ledger", { body: signedUpload(player, events, { tapeIndex, snapshot: { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} } }) });
  assert.equal((await upload(7500)).status, 200);
  let reply = await read(await env.call("/v1/tape", { body: tapeRequest(player, { sentAt: NOW + 1 }) }));
  assert.equal(reply["start"], 7500);
  assert.equal((reply["entries"] as string[]).length, TAPE_SIZE - 7500 + 1);
  assert.equal(reply["issued"], null);
  // At entry 8,500 there are exactly 1,501 left (8,500 to 10,000): refill.
  await upload(8500, []);
  reply = await read(await env.call("/v1/tape", { body: tapeRequest(player, { sentAt: NOW + 2 }) }));
  assert.equal(reply["start"], 8500);
  assert.deepEqual((reply["issued"] as { start: number; end: number }).start, TAPE_SIZE + 1);
  assert.equal((reply["entries"] as string[]).length, 2 * TAPE_SIZE - 8500 + 1);
  assert.ok(REFILL_BELOW < TAPE_SIZE);
  // A second request at the same position issues nothing more.
  const repeat = await read(await env.call("/v1/tape", { body: tapeRequest(player, { sentAt: NOW + 3 }) }));
  assert.equal(repeat["issued"], null);
  assert.deepEqual(repeat["entries"], reply["entries"]);
});

test("asking for a tape needs a registered key, a valid signature made for this purpose, and Ranked to be open", async () => {
  const env = setup();
  const { player } = await registered(env);
  const code = async (body: unknown) => (await read(await env.call("/v1/tape", { body }))).error?.code;
  assert.equal(await code(tapeRequest(newPlayer("stranger"))), "unknown_key");
  assert.equal(await code({ ...tapeRequest(player), sentAt: NOW + 1 }), "bad_signature");
  assert.equal(await code(tapeRequest(player, {}, "register")), "bad_signature");
  assert.equal(await code(tapeRequest(player, { sentAt: NOW - 90_000 })), "bad_request");
  assert.equal(await code({ key: player.publicKeyHex }), "bad_request");
  const closed = setup();
  closed.deps.tapeSecret = undefined;
  const second = await registered(closed);
  assert.equal((await read(await closed.call("/v1/tape", { body: tapeRequest(second.player) }))).error?.code, "ranked_unavailable");
});

test("an honest Ranked history that matches the tape is accepted and scored", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const { events, tapeNext, attempts } = await rankedHistory(id, 3);
  const snapshot = { counts: { "npc:589": 3 }, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} };
  const response = await env.call("/v1/ledger", { body: signedUpload(player, events, { tapeIndex: tapeNext, snapshot }) });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  assert.equal(env.raw.prepare("SELECT tape_next FROM ledger_state").get()?.["tape_next"], tapeNext);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM flags").get()?.["n"], 0);
});

test("a drop on a roll above the card's rate is refused, unless the attempts can account for the stack that allows it", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const key = await tapeKey(TAPE_SIZE ? TAPE_SECRET : "");
  // Find an entry that loses for a 1% card, and needs a stack of at least five attempts (a roll above 4%).
  let losing = 1;
  while (rollValue(await tapeEntry(key, id, losing)) <= 400) losing++;
  const lossEntry = await tapeEntry(key, id, losing);
  const needed = attemptsNeeded(rollValue(lossEntry), 100, catalog.stackFactor);
  assert.ok(needed >= 5);
  const base = { dust: 0, partner: "", trade: "", char: "Alice-RealmName", count: 1 };
  const forged = chain([
    { seq: 1, t: 1000, kind: "mode", key: "ranked", ...base, count: 0, shiny: 0, tape: 0 },
    { seq: 2, t: 1010, kind: "drop", key: "npc:589", ...base, shiny: shinyValue(lossEntry, 20) === 1 ? 1 : 0, tape: losing },
  ]);
  const send = (events: Record<string, unknown>[], attempts: number) => env.call("/v1/ledger", {
    body: signedUpload(player, events, { tapeIndex: losing + 1, snapshot: { counts: { "npc:589": 1 }, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} } }),
  });
  // One attempt short of the stack that roll needs: refused.
  const refused = await read(await send(forged, needed - 1));
  assert.equal(refused.error?.code, "tape_invalid");
  assert.equal(refused.error?.detail?.["reason"], "stack");
  // With exactly the attempts the stack needs, the same drop is allowed.
  assert.equal((await send(forged, needed)).status, 200);
});

test("the stack arithmetic: what a roll needs, and what an attempt's chance is", () => {
  assert.equal(chanceAfter(100, 0, 1), 100);
  assert.equal(chanceAfter(100, 2, 1), 300);
  assert.equal(chanceAfter(100, 500, 1), 10000, "never above certain");
  assert.equal(chanceAfter(100, 4, 0), 100, "a factor of 0 is a flat chance");
  assert.equal(attemptsNeeded(1, 100, 1), 1);
  assert.equal(attemptsNeeded(100, 100, 1), 1);
  assert.equal(attemptsNeeded(101, 100, 1), 2);
  assert.equal(attemptsNeeded(300, 100, 1), 3);
  assert.equal(attemptsNeeded(10000, 100, 1), 100);
  assert.equal(attemptsNeeded(10000, 1000, 1), 10);
  assert.equal(attemptsNeeded(101, 100, 0), Infinity);
  // It agrees with the chance for every roll, including with a fractional factor.
  for (const factor of [1, 0.5, 0.3, 2]) {
    for (const rate of [100, 200, 1000]) {
      for (let roll = 1; roll <= 10000; roll += 37) {
        const n = attemptsNeeded(roll, rate, factor);
        assert.ok(chanceAfter(rate, n - 1, factor) >= roll, `${roll} at ${rate}/${factor}`);
        assert.ok(n === 1 || chanceAfter(rate, n - 2, factor) < roll, `${roll} at ${rate}/${factor} is not the fewest`);
      }
    }
  }
});

test("every other way of misusing the tape is refused", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const { events, tapeNext, attempts } = await rankedHistory(id, 2);
  const snapshot = (count: number) => ({ counts: { "npc:589": count }, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} });
  const partials = (list: Record<string, unknown>[]) => list.map((event) => { const { prev, h, ...rest } = event; void prev; void h; return rest; });
  const refuse = async (mutate: (list: Record<string, unknown>[]) => Record<string, unknown>[], tapeIndex: number, reason: string) => {
    const changed = chain(mutate(partials(events)));
    const body = await read(await env.call("/v1/ledger", { body: signedUpload(player, changed, { tapeIndex, snapshot: snapshot(2) }) }));
    assert.equal(body.error?.code, "tape_invalid", JSON.stringify(body));
    assert.equal(body.error?.detail?.["reason"], reason);
  };
  // A position that was never issued (the last drop, so the positions still rise).
  await refuse((list) => list.map((event, index) => (index === 2 ? { ...event, tape: 50_000 } : event)), tapeNext, "not-issued");
  // The wrong shiny flag for the entry. Flip a flag the rules alone would let through.
  const flags = [events[1]?.["shiny"], events[2]?.["shiny"]];
  const flip = flags[0] === 1 || flags[1] === 0 ? 1 : 2;
  await refuse((list) => list.map((event, index) => (index === flip ? { ...event, shiny: event["shiny"] === 1 ? 0 : 1 } : event)), tapeNext, "shiny");
  // Saying the next entry is one the add-on has already used, or one that was never issued.
  await refuse((list) => list, 1, "next");
  await refuse((list) => list, 20_000, "next");
  // Nothing was stored by any of that, and the honest version still goes through.
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 0);
  assert.equal((await env.call("/v1/ledger", { body: signedUpload(player, events, { tapeIndex: tapeNext, snapshot: snapshot(2) }) })).status, 200);
});

test("a Ranked drop cannot be uploaded to a server where Ranked is closed", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const { events, tapeNext, attempts } = await rankedHistory(id, 1);
  env.deps.tapeSecret = undefined;
  const response = await env.call("/v1/ledger", { body: signedUpload(player, events, { tapeIndex: tapeNext, snapshot: { counts: { "npc:589": 1 }, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} } }) });
  assert.equal((await read(response)).error?.code, "ranked_unavailable");
  assert.equal(response.status, 503);
});

test("the tape's roll and shiny values follow the shared vectors", () => {
  const vectors = JSON.parse(readFileSync(new URL("../../packages/shared/vectors/tape.json", import.meta.url), "utf8")) as {
    shinyOdds: number; entries: string[]; commitment: string; cases: { entry: string; roll: number; shiny: number }[];
  };
  for (const item of vectors.cases) {
    assert.equal(rollValue(item.entry), item.roll);
    assert.equal(shinyValue(item.entry, vectors.shinyOdds), item.shiny);
  }
});
