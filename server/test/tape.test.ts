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

test("a 10,000-attempt session buffer is issued once, is repeatable, and differs between players", async () => {
  const env = setup();
  const alice = await registered(env, "alice");
  const bob = await registered(env, "bob");
  const first = await read(await env.call("/v1/tape", { body: tapeRequest(alice.player) }));
  const entries = first["entries"] as string[];
  assert.equal(first["start"], 1);
  assert.equal(entries.length, TAPE_SIZE);
  assert.equal(entries.length, 10_000);
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

test("an exhausted legacy 1,000-entry tape refills at its next position without changing the binder", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  const key = await tapeKey(TAPE_SECRET);
  const legacy: string[] = [];
  for (let index = 1; index <= 1_000; index++) legacy.push(await tapeEntry(key, id, index));
  await env.deps.tapes.recordIssue(id, { start: 1, end: 1_000, commitment: await tapeCommitment(legacy) }, NOW);
  // This is an existing binder and acknowledgement, not a new registration or reset during refill.
  const history = chain([{ seq: 1, t: 1000, kind: "mode", key: "casual", count: 0, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Alice-RealmName" }]);
  assert.equal((await env.call("/v1/ledger", { body: signedUpload(player, history, { tapeIndex: 1_001, snapshot: { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} } }) })).status, 200);
  const before = env.raw.prepare("SELECT * FROM players WHERE id = ?").get(id);
  const response = await env.call("/v1/tape", { body: tapeRequest(player) });
  assert.equal(response.status, 200);
  const reply = await read(response);
  const entries = reply["entries"] as string[];
  assert.equal(reply["start"], 1_001);
  assert.equal(entries.length, 10_000);
  assert.equal(entries[0], await tapeEntry(key, id, 1_001));
  assert.equal(entries.at(-1), await tapeEntry(key, id, 11_000));
  assert.deepEqual(env.raw.prepare("SELECT * FROM players WHERE id = ?").get(id), before);
  assert.equal(await env.deps.tapes.issuedEnd(id), 11_000);
  assert.equal(await env.deps.tapes.tapeNext(id), 1_001);
});

test("a refill is issued only when few entries are unused, and always starts where the old one ended", async () => {
  const env = setup();
  const { player } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const far = TAPE_SIZE - REFILL_BELOW - 100; // plenty unused: not yet time
  const near = TAPE_SIZE - REFILL_BELOW + 50; // few enough unused to need more
  // The add-on says it will next use `far`.
  const history = chain([{ seq: 1, t: 1000, kind: "mode", key: "casual", count: 0, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Alice-RealmName" }]);
  const upload = (tapeIndex: number, events = history) => env.call("/v1/ledger", { body: signedUpload(player, events, { tapeIndex, snapshot: { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} } }) });
  assert.equal((await upload(far)).status, 200);
  let reply = await read(await env.call("/v1/tape", { body: tapeRequest(player, { sentAt: NOW + 1 }) }));
  assert.equal(reply["start"], far);
  assert.equal((reply["entries"] as string[]).length, TAPE_SIZE - far + 1);
  assert.equal(reply["issued"], null);
  // At `near` there are no more than REFILL_BELOW left: refill.
  await upload(near, []);
  reply = await read(await env.call("/v1/tape", { body: tapeRequest(player, { sentAt: NOW + 2 }) }));
  assert.equal(reply["start"], near);
  assert.deepEqual((reply["issued"] as { start: number; end: number }).start, TAPE_SIZE + 1);
  assert.equal((reply["entries"] as string[]).length, 2 * TAPE_SIZE - near + 1);
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

// Cheats the aggregate check could not see, because every attempt is now written down and replayed on its own entry.
const NPC = "npc:589";
const events12 = (id: string) => ({ dust: 0, partner: "", trade: "", char: "Alice-RealmName", id });
const without = (event: Record<string, unknown>) => { const { prev, h, ...rest } = event; void prev; void h; return rest; };

test("a drop on an entry that loses is refused: the roll decides, whatever the player says about their attempts", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const key = await tapeKey(TAPE_SECRET);
  // An honest history, then one more drop at the next entry, which has to be one that loses for a card with no stack.
  let wins = 1;
  let history = await rankedHistory(id, wins);
  while (rollValue(await tapeEntry(key, id, history.tapeNext)) <= 100) history = await rankedHistory(id, ++wins);
  const entry = await tapeEntry(key, id, history.tapeNext);
  const forged = chain([...history.events.map(without), { ...events12(id), seq: history.events.length + 1, t: 5000, kind: "drop", key: NPC, count: wins + 1, shiny: 0, tape: history.tapeNext }]);
  void entry;
  const body = await read(await env.call("/v1/ledger", { body: signedUpload(player, forged, { tapeIndex: history.tapeNext + 1, snapshot: { counts: { [NPC]: wins + 1 }, dust: 0, sets: {}, attempts: { [NPC]: 999_999 }, titles: {} } }) }));
  assert.equal(body.error?.code, "tape_invalid", JSON.stringify(body));
  assert.equal(body.error?.detail?.["reason"], "roll");
  assert.equal(body.error?.detail?.["index"], history.events.length);
});

test("a miss that the roll would have won is refused: a drop cannot be left out", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  // Take the honest history up to its last drop and write that drop down as a run of one miss instead.
  const { events, tapeNext } = await rankedHistory(id, 2);
  const list = events.map(without);
  const last = list[list.length - 1] as Record<string, unknown>;
  list[list.length - 1] = { ...last, kind: "miss", count: 1, shiny: 0, tape: last["tape"] };
  const body = await read(await env.call("/v1/ledger", { body: signedUpload(player, chain(list), { tapeIndex: tapeNext, snapshot: { counts: { [NPC]: 1 }, dust: 0, sets: {}, attempts: { [NPC]: 10 }, titles: {} } }) }));
  assert.equal(body.error?.code, "tape_invalid", JSON.stringify(body));
  assert.equal(body.error?.detail?.["reason"], "roll");
});

test("an attempt left out of the ledger breaks the chain of tape positions", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const { events, tapeNext } = await rankedHistory(id, 2);
  const list = events.map(without);
  // Skip an entry: the last drop claims the position after the next one.
  const last = list[list.length - 1] as Record<string, unknown>;
  list[list.length - 1] = { ...last, tape: (last["tape"] as number) + 1 };
  const body = await read(await env.call("/v1/ledger", { body: signedUpload(player, chain(list), { tapeIndex: tapeNext + 1, snapshot: { counts: { [NPC]: 2 }, dust: 0, sets: {}, attempts: { [NPC]: 10 }, titles: {} } }) }));
  assert.equal(body.error?.code, "rule_broken", JSON.stringify(body));
  assert.equal(body.error?.detail?.["rule"], "tape");
});

test("the first kind of Ranked, which did not write misses down, is no longer accepted for new events", async () => {
  const env = setup();
  const { player } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const loose = chain([{ seq: 1, t: 1000, kind: "mode", key: "ranked", count: 0, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Alice-RealmName" }]);
  const body = await read(await env.call("/v1/ledger", { body: signedUpload(player, loose, { tapeIndex: 1, snapshot: { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} } }) }));
  assert.equal(body.error?.code, "rule_broken");
  assert.equal(body.error?.detail?.["rule"], "mode");
  // An upload in the first version of the format is turned away before anything else is looked at.
  const old = await read(await env.call("/v1/ledger", { body: signedUpload(player, [], { specVersion: 1 }) }));
  assert.equal(old.error?.code, "client_too_old");
});

test("a player who went Ranked on the old add-on and then updated can still sync: the old switch is accepted when a new one follows it", async () => {
  const env = setup();
  const { player } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const base = { t: 1000, count: 0, dust: 0, shiny: 0, partner: "", trade: "", char: "Alice-RealmName" };
  const events = chain([
    { ...base, seq: 1, kind: "mode", key: "ranked", tape: 0 },
    { ...base, seq: 2, t: 1001, kind: "mode", key: "ranked2", tape: 0 },
  ]);
  const snapshot = { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} };
  const body = await read(await env.call("/v1/ledger", { body: signedUpload(player, events, { tapeIndex: 1, snapshot }) }));
  assert.equal(body["accepted"], 2, JSON.stringify(body));
  assert.equal(body.error, undefined);
});

test("a run of misses long enough to leave the issued entries is refused before any are looked at", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  await env.call("/v1/tape", { body: tapeRequest(player) });
  const { events } = await rankedHistory(id, 1);
  const list = events.map(without);
  const lastTape = (list[list.length - 1] as Record<string, unknown>)["tape"] as number;
  const run = TAPE_SIZE + 5;
  list.push({ ...events12(id), seq: list.length + 1, t: 6000, kind: "miss", key: NPC, count: run, shiny: 0, tape: lastTape + run });
  const body = await read(await env.call("/v1/ledger", { body: signedUpload(player, chain(list), { tapeIndex: TAPE_SIZE, snapshot: { counts: { [NPC]: 1 }, dust: 0, sets: {}, attempts: { [NPC]: 10 }, titles: {} } }) }));
  assert.equal(body.error?.code, "tape_invalid", JSON.stringify(body));
  assert.equal(body.error?.detail?.["reason"], "not-issued");
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
  // The wrong shiny flag for the entry. Flip a flag the rules alone would let through: the first shiny drop to plain, or,
  // when none is shiny, the first drop to shiny.
  const dropAt = events.flatMap((event, index) => (event["kind"] === "drop" ? [index] : []));
  const flip = dropAt.find((index) => events[index]?.["shiny"] === 1) ?? (dropAt[0] as number);
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
