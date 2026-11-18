import assert from "node:assert/strict";
import test from "node:test";
import { SqlBonusEvents, bonusDefinition } from "../src/bonusEvents.ts";
import { ADMIN_TOKEN, NOW, TAPE_SECRET, catalog, chain, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import { chanceFor } from "../../packages/shared/src/drops.js";
import { rollValue, shinyValue, tapeEntry, tapeKey } from "../src/tape.ts";
import { createRequire } from "node:module";
import { replay } from "../src/shared.ts";
import * as bonus from "../../packages/shared/src/bonus-events.js";
const signer = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(value: unknown, key: unknown): string };
const example = { id: "collectors-hour", title: "Collector's Hour", startsAt: NOW + 60, endsAt: NOW + 3660, effect: "card-drops", percent: 200, sets: [] as string[] };

test("only administrators schedule immutable events; the public schedule is cacheable and scoped to known sets", async () => {
  const env = setup(); env.deps.bonuses = new SqlBonusEvents(env.db, catalog);
  assert.equal((await env.call("/v1/admin/bonus-events", { body: example })).status, 401);
  const headers = { authorization: "Bearer " + ADMIN_TOKEN };
  const response = await env.call("/v1/admin/bonus-events", { headers, body: example });
  assert.equal(response.status, 201, await response.text());
  assert.equal((await env.call("/v1/admin/bonus-events", { headers, body: { ...example, percent: 500 } })).status, 400);
  const publicReply = await env.call("/v1/bonus-events");
  assert.equal(publicReply.headers.get("cache-control"), "public, max-age=300");
  assert.equal((await publicReply.json() as { events: unknown[] }).events.length, 1);
  for (const changed of [{ startsAt: NOW-1 }, { endsAt: example.startsAt + 20 }, { percent: 501 }, { effect: "give-cards" }, { sets: ["missing"] }, { title: "bad|Hlink" }]) assert.throws(() => bonusDefinition({ ...example, ...changed }, catalog, NOW));
  env.clock.now = example.endsAt;
  assert.equal((await (await env.call("/v1/bonus-events")).json() as { events: unknown[] }).events.length, 0);
  assert.equal((await env.deps.bonuses.forEvents([{ kind: "miss", partner: "bonus", trade: example.id + ":" + example.startsAt + ":" + example.startsAt }]))[example.id]?.percent, 200, "expired rules remain for offline uploads");
});

test("bonus claims need official matching rules, exact scope and times; a player named Bonus remains a normal trade partner", () => {
  const at = example.startsAt, card = "npc:589";
  const event = { kind: "drop", key: card, tape: 1, t: at, partner: "bonus", trade: example.id + ":" + at + ":" + at };
  assert.equal(bonus.forEvent(event, catalog, { [example.id]: example }, at-1, at)?.percent, 200);
  assert.equal(bonus.forEvent(event, catalog, {}, at-1, at), null);
  assert.equal(bonus.forEvent(event, catalog, { [example.id]: { ...example, sets: ["missing"] } }, at-1, at), null);
  assert.equal(bonus.forEvent({ ...event, t: example.endsAt, trade: example.id + ":" + example.endsAt + ":" + example.endsAt }, catalog, { [example.id]: example }), null);
  assert.equal(bonus.forEvent(event, catalog, { [example.id]: example }, at+1, at), null);
  assert.equal(bonus.isBonus({ kind: "tradeIn", partner: "bonus", trade: "normal-session" }), false);
});

test("an event's real boosted tape replays on upload and in a later rebuild, while invented events are refused", async () => {
  const env = setup(); env.deps.bonuses = new SqlBonusEvents(env.db, catalog);
  await env.deps.bonuses.schedule(example, NOW);
  const player = newPlayer("event-finder");
  const registered = await (await env.call("/v1/register", { body: registration(player) })).json() as { playerId: string };
  const request = { key: player.publicKeyHex, sentAt: NOW };
  assert.equal((await env.call("/v1/tape", { body: { ...request, sig: signer.signBatch({ ...request, purpose: "tape" }, player.privateKey) } })).status, 200);
  const key = await tapeKey(TAPE_SECRET), npc = "npc:589", at = example.startsAt;
  const parts: Record<string, unknown>[] = ["chase1", "chase2", "launch1", "faction1", "ranked2"].map((name, index) => ({ seq: index+1, t: at-10+index, kind: "mode", key: name, count: 0, tape: 0 }));
  let misses=0, owned=0, shinyOwned=false, changed=false;
  for (let position=1; position<=80; position++) {
    const entry=await tapeEntry(key,registered.playerId,position), roll=rollValue(entry), plain=chanceFor(catalog,npc,misses,2), won=roll<=Math.min(10000,plain*2);
    changed ||= won && roll>plain;
    const shiny=won && !shinyOwned && shinyValue(entry,catalog.shinyOdds)===1;
    if (won) { owned++; misses=0; if (shiny) shinyOwned=true; } else misses++;
    parts.push({ seq: parts.length+1, t: at, kind: won?"drop":"miss", key:npc, count:won?owned:1, shiny:shiny?1:0, tape:position, partner:"bonus", trade:example.id+":"+at+":"+at });
  }
  assert.ok(changed,"test tape must include wins caused by the event");
  const events=chain(parts.map(part=>({ dust:0, shiny:0, partner:"", trade:"", char:"Filfred-Whizzlebang", ...part })));
  env.clock.now=example.endsAt+100; // saved after the hour; the recorded attempt times stay in the official window
  const response=await env.call("/v1/ledger",{body:signedUpload(player,events,{specVersion:13,tapeIndex:81,sentAt:env.clock.now,snapshot:{counts:owned?{[npc]:owned}:{},dust:0,sets:{},attempts:{[npc]:80},titles:{}}})});
  assert.equal(response.status,200,JSON.stringify(await response.json()));
  const definitions=await env.deps.bonuses.forEvents(events as unknown as {kind:string;partner:string;trade:string}[]);
  assert.equal(replay(events,catalog,undefined,{bonuses:definitions}).ok,true);
  assert.equal(replay(events,catalog).ok,false);
});
