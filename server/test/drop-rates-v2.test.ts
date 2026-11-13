// The second drop generation (ledger spec 8, mode/chase2): an upload that carries it, or a binder already on it, needs a companion that
// says it speaks spec 8; and a binder that stops at chase1 is accepted exactly as before.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { NOW, newPlayer, registration, setup, signedUpload } from "./harness.ts";

const require = createRequire(import.meta.url);
const ledger = require("../../packages/shared/src/ledger.js") as {
  GENESIS: string; makeEvent(partial: Record<string, unknown>, prev: string): Record<string, unknown> & { h: string };
};

function markers(...keys: string[]): Record<string, unknown>[] {
  let prev = ledger.GENESIS;
  return keys.map((key, index) => {
    const made = ledger.makeEvent({ seq: index + 1, t: 1000 + index, char: "Alice-RealmName", kind: "mode", key, count: 0, tape: 0, dust: 0, shiny: 0, partner: "", trade: "" }, prev);
    prev = made.h;
    return made;
  });
}
const snapshot = { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} };

async function player(name: string) {
  const env = setup();
  const who = newPlayer(name);
  assert.equal((await env.call("/v1/register", { body: registration(who) })).status, 200);
  const upload = (events: Record<string, unknown>[], specVersion: number) =>
    env.call("/v1/ledger", { body: signedUpload(who, events, { specVersion, tapeIndex: 0, snapshot, sentAt: NOW }) });
  return { env, upload };
}
const code = async (response: Response) => ((await response.json()) as { error?: { code: string } }).error?.code;

test("an upload that carries mode/chase2 needs spec 8; an older companion is told to update", async () => {
  const { upload } = await player("rates-a");
  const events = markers("chase1", "chase2");
  for (const old of [5, 6, 7]) {
    const refused = await upload(events, old);
    assert.equal(refused.status, 426, "spec " + old);
    assert.equal(await code(refused), "client_too_old");
  }
  assert.equal((await upload(events, 8)).status, 200);
});

test("once a binder is on the second generation, even an empty upload from an older companion is refused", async () => {
  const { upload } = await player("rates-b");
  assert.equal((await upload(markers("chase1", "chase2"), 8)).status, 200);
  assert.equal((await upload([], 7)).status, 426);
  assert.equal((await upload([], 8)).status, 200);
});

test("a binder that stops at chase1 is accepted from spec 5 or later, exactly as before", async () => {
  const { upload } = await player("rates-c");
  assert.equal((await upload(markers("chase1"), 4)).status, 426, "chase1 still needs spec 5");
  assert.equal((await upload(markers("chase1"), 5)).status, 200);
  assert.equal((await upload([], 6)).status, 200, "and no spec 8 is asked of it");
});

test("chase2 before chase1, or twice, is a broken history", async () => {
  const first = await player("rates-d");
  assert.equal((await first.upload(markers("chase2"), 8)).status, 422);
  const twice = await player("rates-e");
  assert.equal((await twice.upload(markers("chase1", "chase2", "chase2"), 8)).status, 422);
});
