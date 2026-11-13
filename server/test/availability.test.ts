// Cards held back for seasons, on the server (ledger spec 9, mode/launch1): a binder on the launch collection needs a companion that
// says spec 9, and may not acquire a held-back card until a scheduled season has released it; the time counted is the earlier of the
// event's own and the server's now. Cards that are not held back, and everything before the marker, are unaffected.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { SqlSeasons } from "../src/seasons.ts";
import { NOW, catalog, newPlayer, registration, setup, signedUpload } from "./harness.ts";

const require = createRequire(import.meta.url);
const ledger = require("../../packages/shared/src/ledger.js") as {
  GENESIS: string; makeEvent(partial: Record<string, unknown>, prev: string): Record<string, unknown> & { h: string };
};

const held = Object.entries(catalog.cards).find(([, card]) => card.seasonal && !card.baseKey)![0];
const free = Object.entries(catalog.cards).find(([, card]) => !card.seasonal && !card.baseKey)![0];

function chain(...partials: [string, string, number?][]): Record<string, unknown>[] {
  let prev = ledger.GENESIS;
  return partials.map(([kind, key, t], index) => {
    const made = ledger.makeEvent({ seq: index + 1, t: t ?? 1000 + index, char: "Alice-RealmName", kind, key, count: kind === "mode" ? 0 : 1, tape: 0, dust: 0, shiny: 0, partner: "", trade: "" }, prev);
    prev = made.h;
    return made;
  });
}
const MARKERS: [string, string][] = [["mode", "chase1"], ["mode", "chase2"], ["mode", "launch1"]];
const snapshot = (counts: Record<string, number> = {}) => ({ counts, dust: 0, sets: {}, attempts: {}, titles: {} });

async function world(name: string) {
  const env = setup();
  const who = newPlayer(name);
  assert.equal((await env.call("/v1/register", { body: registration(who) })).status, 200);
  const upload = (events: Record<string, unknown>[], specVersion = 9, counts: Record<string, number> = {}) =>
    env.call("/v1/ledger", { body: signedUpload(who, events, { specVersion, tapeIndex: 0, snapshot: snapshot(counts), sentAt: NOW }) });
  return { env, upload };
}
const body = async (response: Response) => (await response.json()) as { error?: { code: string; detail?: { rule?: string } } };

test("a binder that has recorded mode/launch1 needs spec 9, even for an empty upload", async () => {
  const { upload } = await world("avail-a");
  const events = chain(...MARKERS);
  assert.equal((await upload(events, 8)).status, 426);
  assert.equal((await upload(events, 9)).status, 200);
  assert.equal((await upload([], 8)).status, 426);
  assert.equal((await upload([], 9)).status, 200);
});

test("an unreleased held-back card is refused after the marker; a launch card and a card from before the marker are not", async () => {
  const { env, upload } = await world("avail-b");
  env.deps.released = async () => ({}); // nothing released
  const refused = await upload(chain(...MARKERS, ["drop", held, NOW - 50]), 9, { [held]: 1 });
  assert.equal(refused.status, 422);
  const failure = await body(refused);
  assert.equal(failure.error?.code, "rule_broken");
  assert.equal(failure.error?.detail?.rule, "retired");
  assert.equal((await upload(chain(...MARKERS, ["drop", free, NOW - 50]), 9, { [free]: 1 })).status, 200, "a launch card is fine");
  // A held-back card dropped BEFORE the marker was legitimate when it happened, and still is.
  const second = await world("avail-c");
  second.env.deps.released = async () => ({});
  assert.equal((await second.upload(chain(["drop", held, 1000], ["mode", "chase1"], ["mode", "chase2"], ["mode", "launch1"]), 9, { [held]: 1 })).status, 200);
});

test("once a season has released it a held-back card is allowed, and the time counted is the earlier of the event's and now", async () => {
  const released = await world("avail-d");
  released.env.deps.released = async () => ({ [held]: NOW - 100 });
  assert.equal((await released.upload(chain(...MARKERS, ["drop", held, NOW - 50]), 9, { [held]: 1 })).status, 200);

  // The season starts a little in the future: a clock set ahead does not make the card available early.
  const early = await world("avail-e");
  early.env.deps.released = async () => ({ [held]: NOW + 100 });
  const ahead = await early.upload(chain(...MARKERS, ["drop", held, NOW + 200]), 9, { [held]: 1 });
  assert.equal(ahead.status, 422);
  assert.equal((await body(ahead)).error?.detail?.rule, "retired");
  // And an event from before the release is refused even though the server is past it now.
  const late = await world("avail-f");
  late.env.deps.released = async () => ({ [held]: NOW - 100 });
  assert.equal((await late.upload(chain(...MARKERS, ["drop", held, NOW - 200]), 9, { [held]: 1 })).status, 422);
});

test("with no override the scheduled seasons decide: a card is released from the start of the first season that features it, for good", async () => {
  const { env, upload } = await world("avail-g");
  delete (env.deps as { released?: unknown }).released;
  env.deps.seasons = new SqlSeasons(env.db, catalog);
  assert.equal((await upload(chain(...MARKERS, ["drop", held, NOW - 50]), 9, { [held]: 1 })).status, 422, "no season yet: nothing is released");
  env.raw.prepare("INSERT INTO seasons (id, title, starts_at, ends_at, cards_json, rewards_json, selection_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
    .run("first-hunt", "The First Hunt", NOW - 1000, NOW - 500, JSON.stringify([held]), JSON.stringify({ completion: { title: "", packs: [] }, first: { places: 0, title: "", packs: [] } }), "{}", NOW - 2000);
  assert.deepEqual(await env.deps.seasons.released(), { [held]: NOW - 1000 });
  // The season has ended, but the card stays available.
  assert.equal((await upload(chain(...MARKERS, ["drop", held, NOW - 50]), 9, { [held]: 1 })).status, 200);
});

test("the seasons sync tells the add-on which held-back cards are released: started seasons only, and only cards that were held back", async () => {
  const env = setup();
  const who = newPlayer("avail-sync");
  const registered = (await (await env.call("/v1/register", { body: registration(who) })).json()) as { playerId: string };
  const seasons = new SqlSeasons(env.db, catalog);
  const others = Object.entries(catalog.cards).filter(([, card]) => card.seasonal && !card.baseKey).map(([key]) => key);
  const [now, later] = [others[1] as string, others[2] as string];
  const rewards = JSON.stringify({ completion: { title: "", packs: [] }, first: { places: 0, title: "", packs: [] } });
  const add = (id: string, start: number, cards: string[]) => env.raw.prepare("INSERT INTO seasons (id, title, starts_at, ends_at, cards_json, rewards_json, selection_json, created_at) VALUES (?, ?, ?, ?, ?, ?, '{}', ?)")
    .run(id, id, start, start + 86400, JSON.stringify(cards), rewards, start - 10);
  add("started", NOW - 5000, [now, free]); // free is not held back: it is not listed
  add("not-yet", NOW + 5000, [later]);
  const sync = await seasons.sync(registered.playerId, NOW);
  assert.deepEqual(sync.released, [now]);
});
