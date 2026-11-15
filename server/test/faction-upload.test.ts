// Cards only one faction can win, on the server (ledger spec 10, mode/faction1 and mode/side:*): a binder that has recorded the marker needs a
// companion that says spec 10; a character declares its faction once; and a card only one faction can win is refused for the other faction
// (or for a character that has declared nothing). Cards that both factions can win, trades and everything before the marker are unaffected.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { NOW, catalog, newPlayer, registration, setup, signedUpload } from "./harness.ts";

const require = createRequire(import.meta.url);
const ledger = require("../../packages/shared/src/ledger.js") as {
  GENESIS: string; makeEvent(partial: Record<string, unknown>, prev: string): Record<string, unknown> & { h: string };
};

const base = Object.entries(catalog.cards).filter(([, card]) => !card.baseKey);
const forAlliance = base.find(([, card]) => card.faction === "alliance")![0]; // only the Alliance can win it
const forHorde = base.find(([, card]) => card.faction === "horde")![0];
const shared = base.find(([, card]) => card.since === 10 && !card.faction && !card.unobtainable)![0]; // added in spec 10, either faction
const old = base.find(([, card]) => !card.since && !card.seasonal)![0]; // a launch card from before spec 10

type Part = { kind: string; key: string; char?: string; t?: number; count?: number };
function chain(...parts: Part[]): Record<string, unknown>[] {
  let prev = ledger.GENESIS;
  return parts.map((part, index) => {
    const made = ledger.makeEvent({ seq: index + 1, t: part.t ?? 1000 + index, char: part.char ?? "Ann-Realm", kind: part.kind, key: part.key,
      count: part.count ?? (part.kind === "mode" ? 0 : 1), tape: 0, dust: 0, shiny: 0, partner: "", trade: "" }, prev);
    prev = made.h;
    return made;
  });
}
const markers: Part[] = [{ kind: "mode", key: "chase1" }, { kind: "mode", key: "chase2" }, { kind: "mode", key: "launch1" }, { kind: "mode", key: "faction1" }];
const snapshot = (counts: Record<string, number> = {}) => ({ counts, dust: 0, sets: {}, attempts: {}, titles: {} });

async function world(name: string) {
  const env = setup();
  const who = newPlayer(name);
  assert.equal((await env.call("/v1/register", { body: registration(who) })).status, 200);
  const upload = (events: Record<string, unknown>[], specVersion = 10, counts: Record<string, number> = {}) =>
    env.call("/v1/ledger", { body: signedUpload(who, events, { specVersion, tapeIndex: 0, snapshot: snapshot(counts), sentAt: NOW }) });
  return { env, upload };
}
const rule = async (response: Response) => ((await response.json()) as { error?: { code: string; detail?: { rule?: string } } }).error?.detail?.rule;

test("a binder that has recorded mode/faction1 or a side needs spec 10, even for an empty upload", async () => {
  const { upload } = await world("faction-a");
  const events = chain(...markers, { kind: "mode", key: "side:alliance" });
  assert.equal((await upload(events, 9)).status, 426);
  assert.equal((await upload(events, 10)).status, 200);
  assert.equal((await upload([], 9)).status, 426);
  assert.equal((await upload([], 10)).status, 200);
});

test("a card only one faction can win needs a character that declared that faction", async () => {
  const { upload } = await world("faction-b");
  // Declared Alliance: the Alliance card is fine.
  assert.equal((await upload(chain(...markers, { kind: "mode", key: "side:alliance" }, { kind: "drop", key: forAlliance }), 10, { [forAlliance]: 1 })).status, 200);

  const wrong = await world("faction-c");
  const refused = await wrong.upload(chain(...markers, { kind: "mode", key: "side:alliance" }, { kind: "drop", key: forHorde }), 10, { [forHorde]: 1 });
  assert.equal(refused.status, 422);
  assert.equal(await rule(refused), "faction");

  const silent = await world("faction-d");
  assert.equal(await rule(await silent.upload(chain(...markers, { kind: "drop", key: forAlliance }), 10, { [forAlliance]: 1 })), "faction", "no declaration, no card");

  // Another character on the same binder declares the other faction and gets the Horde card.
  const both = await world("faction-e");
  const events = chain(...markers, { kind: "mode", key: "side:alliance" }, { kind: "drop", key: forAlliance },
    { kind: "mode", key: "side:horde", char: "Hal-Realm" }, { kind: "drop", key: forHorde, char: "Hal-Realm" });
  assert.equal((await both.upload(events, 10, { [forAlliance]: 1, [forHorde]: 1 })).status, 200);
});

test("the markers come in order, a character declares once, and a card added in spec 10 needs the marker first", async () => {
  const early = await world("faction-f");
  assert.equal(await rule(await early.upload(chain({ kind: "mode", key: "chase1" }, { kind: "mode", key: "chase2" }, { kind: "mode", key: "faction1" }))), "mode", "faction1 only after launch1");
  const twice = await world("faction-g");
  assert.equal(await rule(await twice.upload(chain(...markers, { kind: "mode", key: "side:horde" }, { kind: "mode", key: "side:alliance" }))), "mode", "a character's faction cannot change");
  const sideFirst = await world("faction-h");
  assert.equal(await rule(await sideFirst.upload(chain({ kind: "mode", key: "chase1" }, { kind: "mode", key: "chase2" }, { kind: "mode", key: "launch1" }, { kind: "mode", key: "side:alliance" }))), "mode", "a side only after faction1");

  const before = await world("faction-i");
  assert.equal(await rule(await before.upload(chain({ kind: "mode", key: "chase1" }, { kind: "mode", key: "chase2" }, { kind: "mode", key: "launch1" }, { kind: "drop", key: shared }), 10, { [shared]: 1 })), "retired");
  const after = await world("faction-j");
  assert.equal((await after.upload(chain(...markers, { kind: "drop", key: shared }), 10, { [shared]: 1 })).status, 200, "either faction, once the marker is recorded");
});

test("a card from before spec 10 is unaffected by the faction markers", async () => {
  const { upload } = await world("faction-k");
  assert.equal((await upload(chain(...markers, { kind: "drop", key: old }), 10, { [old]: 1 })).status, 200);
});
