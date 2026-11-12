// A player's copy of their data (POST /v1/export): signed with their key, complete for every binder they have had, and never
// containing what belongs to someone else or to the service.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { ADMIN_TOKEN, NOW, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

const exportRequest = (player: Player, purpose = "export", extra: Record<string, unknown> = {}) => {
  const body = { key: player.publicKeyHex, sentAt: NOW, ...extra };
  return { ...body, sig: reference.signBatch({ ...body, purpose }, player.privateKey) };
};

async function member(env: ReturnType<typeof setup>, name: string) {
  const player = newPlayer(name);
  const registered = await read(await env.call("/v1/register", { body: registration(player, { visibility: "public" }) }));
  await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, 3), { character: name, realm: "Realm Name" }) });
  return { player, id: registered["playerId"] as string };
}

test("a signed request returns the account, keys, characters, events and the reports they sent, and nothing about the service's secrets", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  const bob = await member(env, "Bob");
  env.raw.prepare("INSERT INTO reports (id, reporter_id, token, target_name, target_id, reason, note, created_at) VALUES ('r1', ?, 'tok1', 'bob-realmname', ?, 'cheating', 'saw it happen', ?)").run(alice.id, bob.id, NOW);
  env.raw.prepare("INSERT INTO reports (id, reporter_id, token, target_name, target_id, reason, note, created_at) VALUES ('r2', ?, 'tok2', 'alice-realmname', ?, 'cheating', 'a note about Alice', ?)").run(bob.id, alice.id, NOW);
  env.raw.prepare("INSERT INTO wanted (player_id, card_key, added_at) VALUES (?, 'npc:589', ?)").run(alice.id, NOW);
  env.raw.prepare("INSERT INTO flags (id, player_id, kind, notes, created_at) VALUES ('f1', ?, 'luck-hold', 'INTERNAL: how it was detected', ?)").run(alice.id, NOW);
  const response = await env.call("/v1/export", { body: exportRequest(alice.player) });
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-disposition") ?? "", /attachment; filename="worldofwarcards-my-data.json"/);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const data = (await response.json()) as Record<string, any>;
  assert.equal(data["format"], 1);
  assert.equal(data["account"].playerId, alice.id);
  assert.equal(data["account"].discordId, alice.player.discord);
  assert.equal(data["account"].visibility, "public");
  assert.deepEqual(data["keys"].map((key: any) => key.publicKey), [alice.player.publicKeyHex]);
  assert.deepEqual(data["characters"].map((character: any) => character.name), ["Alice"]);
  assert.equal(data["binders"].length, 1);
  const binder = data["binders"][0];
  assert.equal(binder.archived, false);
  assert.equal(binder.events.length, chainedHistory(1, 3).length, "every event they uploaded");
  assert.equal(binder.saved.headSeq, binder.events.length);
  assert.deepEqual(binder.wanted.map((entry: any) => entry.card), ["npc:589"]);
  assert.ok(binder.flags.map((flag: any) => flag.kind).includes("luck-hold"), "flags are listed by kind");
  assert.ok(binder.flags.every((flag: any) => Object.keys(flag).sort().join() === "createdAt,kind,reviewedAt,state"), "and carry no notes");
  assert.deepEqual(data["reportsSent"].map((report: any) => report.note), ["saw it happen"]);
  // What is not theirs, or not ours to give: another player's report about them, the reviewer's notes, anything secret.
  const text = JSON.stringify(data);
  assert.ok(!text.includes("a note about Alice"), "reports about them are left out");
  assert.ok(!text.includes("INTERNAL"), "reviewers' notes are left out");
  assert.ok(!text.includes(ADMIN_TOKEN) && !text.includes("tape secret"), "no secrets");
  assert.ok(!text.includes(bob.player.publicKeyHex) && !text.includes(bob.player.discord), "nothing of another player");
  assert.match(String(data["notIncluded"]), /Reports other players made about you/);
});

test("a binder they started over from is included too, marked archived", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  await env.store.resetBinder(alice.id, "01ARCHIVEDBINDER000000000A", NOW + 10);
  const data = (await (await env.call("/v1/export", { body: exportRequest(alice.player) })).json()) as Record<string, any>;
  assert.equal(data["binders"].length, 2);
  assert.deepEqual(data["binders"].map((binder: any) => binder.archived), [false, true]);
  assert.equal(data["binders"][1].events.length, chainedHistory(1, 3).length, "the old binder's events are in the copy");
  assert.equal(data["binders"][0].events.length, 0, "the new binder starts empty");
});

test("only the key holder can ask: a wrong signature, a signature for another purpose, an unknown key and an old request are refused", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  const stranger = newPlayer("stranger");
  assert.equal((await read(await env.call("/v1/export", { body: exportRequest(stranger) }))).error?.code, "unknown_key");
  assert.equal((await read(await env.call("/v1/export", { body: exportRequest(alice.player, "delete") }))).error?.code, "bad_signature");
  assert.equal((await read(await env.call("/v1/export", { body: { ...exportRequest(alice.player), sentAt: NOW + 1 } }))).error?.code, "bad_signature");
  const old = { key: alice.player.publicKeyHex, sentAt: NOW - 200_000 };
  assert.equal((await read(await env.call("/v1/export", { body: { ...old, sig: reference.signBatch({ ...old, purpose: "export" }, alice.player.privateKey) } }))).error?.code, "bad_request");
  assert.equal((await env.call("/v1/export", { method: "GET" })).status, 405);
});

test("a banned player can still have their copy, and after deleting the account there is nothing left to export", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  await env.store.setBanned(alice.id, true);
  assert.equal((await env.call("/v1/export", { body: exportRequest(alice.player) })).status, 200);
  await env.store.setBanned(alice.id, false);
  await env.store.deletePlayer(alice.id);
  assert.equal((await read(await env.call("/v1/export", { body: exportRequest(alice.player) }))).error?.code, "unknown_key");
});
