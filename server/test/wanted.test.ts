// The wanted board: what public players are looking for, uploaded by them and shown to everyone.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { NOW, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

const signed = (player: Player, cards: unknown, extra: Record<string, unknown> = {}, purpose = "wanted") => {
  const body = { key: player.publicKeyHex, sentAt: NOW, cards, ...extra };
  return { ...body, sig: reference.signBatch({ ...body, purpose }, player.privateKey) };
};
// A registered player who has played, so the server knows a character of theirs by name.
async function member(env: ReturnType<typeof setup>, name: string, visibility: "public" | "private" = "public") {
  const player = newPlayer(name);
  const registered = await read(await env.call("/v1/register", { body: registration(player, { visibility }) }));
  await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, 3), { character: name, realm: "Realm Name" }) });
  return { player, id: registered["playerId"] as string };
}
const board = async (env: ReturnType<typeof setup>) => ((await read(await env.call("/v1/wanted"))) as unknown as { players: { playerId: string; displayName: string; characters: string[]; cards: string[] }[] }).players;

test("a public player's list appears on the board with their character, and a new list replaces the old", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  assert.deepEqual(await board(env), []);
  const first = await env.call("/v1/wanted", { body: signed(alice.player, ["npc:639", "npc:589"]) });
  assert.equal(first.status, 200);
  assert.deepEqual(await first.json(), { stored: 2, listed: true });
  const listed = await board(env);
  assert.equal(listed.length, 1);
  assert.deepEqual([listed[0]!.playerId, listed[0]!.displayName, listed[0]!.characters, listed[0]!.cards], [alice.id, "Alice-Realm Name", ["alice-realmname"], ["npc:589", "npc:639"]]);
  // A new list replaces the old one; an empty list clears it.
  await env.call("/v1/wanted", { body: signed(alice.player, ["npc:573"], { sentAt: NOW + 1 }) });
  assert.deepEqual((await board(env))[0]!.cards, ["npc:573"]);
  await env.call("/v1/wanted", { body: signed(alice.player, [], { sentAt: NOW + 2 }) });
  assert.deepEqual(await board(env), []);
  assert.equal((await env.call("/v1/wanted")).headers.get("cache-control"), "public, max-age=60");
});

test("a private player's list is not kept, a banned player's disappears, and a player with no character yet is not shown", async () => {
  const env = setup();
  const quiet = await member(env, "Quiet", "private");
  const reply = await env.call("/v1/wanted", { body: signed(quiet.player, ["npc:589"]) });
  assert.deepEqual(await reply.json(), { stored: 0, listed: false });
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM wanted").get() as { n: number }).n, 0);
  assert.deepEqual(await board(env), []);

  const bob = await member(env, "Bob");
  await env.call("/v1/wanted", { body: signed(bob.player, ["npc:589"]) });
  assert.equal((await board(env)).length, 1);
  env.raw.prepare("UPDATE players SET status = 'banned' WHERE id = ?").run(bob.id);
  assert.deepEqual(await board(env), []);
  env.raw.prepare("UPDATE players SET status = 'active' WHERE id = ?").run(bob.id);
  env.raw.prepare("UPDATE players SET visibility = 'private' WHERE id = ?").run(bob.id);
  assert.deepEqual(await board(env), [], "going private takes the list off the board");
  env.raw.prepare("UPDATE players SET visibility = 'public' WHERE id = ?").run(bob.id);

  // Registered but never uploaded anything, so there is no character name to trade with: not listed.
  const fresh = newPlayer("fresh");
  await env.call("/v1/register", { body: registration(fresh) });
  await env.call("/v1/wanted", { body: signed(fresh, ["npc:590"]) });
  assert.equal((await board(env)).length, 1);
});

test("a list must be a short set of real cards, signed by the key for this purpose", async () => {
  const env = setup();
  const carol = await member(env, "Carol");
  const code = async (body: unknown) => (await read(await env.call("/v1/wanted", { body }))).error?.code;
  assert.equal(await code(signed(carol.player, ["npc:99999999"])), "bad_request");
  assert.equal(await code(signed(carol.player, ["npc:589", "npc:589"])), "bad_request", "no duplicates");
  assert.equal(await code(signed(carol.player, Array.from({ length: 61 }, (_, index) => `npc:${index}`))), "bad_request", "at most 60");
  assert.equal(await code(signed(carol.player, "npc:589")), "bad_request");
  assert.equal(await code(signed(carol.player, [5])), "bad_request");
  assert.equal(await code(signed(carol.player, ["npc:589"], { sentAt: NOW - 90_000 })), "bad_request");
  assert.equal(await code(signed(carol.player, ["npc:589"], {}, "tape")), "bad_signature", "a signature made for another purpose does not work");
  assert.equal(await code({ ...signed(carol.player, ["npc:589"]), cards: ["npc:590"] }), "bad_signature", "the list is what is signed");
  assert.equal(await code(signed(newPlayer("stranger"), ["npc:589"])), "unknown_key");
  env.raw.prepare("UPDATE players SET status = 'banned' WHERE id = ?").run(carol.id);
  assert.equal(await code(signed(carol.player, ["npc:589"])), "banned");
  assert.equal((await env.call("/v1/wanted", { method: "DELETE" })).status, 405);
});

test("deleting an account removes the list, and starting a new binder keeps it", async () => {
  const env = setup();
  const dave = await member(env, "Dave");
  await env.call("/v1/wanted", { body: signed(dave.player, ["npc:589"]) });
  const request = { key: dave.player.publicKeyHex, sentAt: NOW };
  assert.equal((await env.call("/v1/reset", { body: { ...request, sig: reference.signBatch({ ...request, purpose: "reset" }, dave.player.privateKey) } })).status, 200);
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM wanted WHERE player_id = ?").get(dave.id) as { n: number }).n, 1, "a wish belongs to the player, not to a binder");
  const del = { ...request, confirm: "delete my data" };
  assert.equal((await env.call("/v1/delete", { body: { ...del, sig: reference.signBatch({ ...del, purpose: "delete" }, dave.player.privateKey) } })).status, 200);
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM wanted").get() as { n: number }).n, 0);
});

test("the website page lists the most wanted cards first, names every player, and escapes what it shows", async () => {
  const env = setup();
  const empty = await (await env.call("/wanted")).text();
  assert.match(empty, /Nobody has listed a card they are looking for yet/);
  const alice = await member(env, "Alice");
  const bob = await member(env, "Bob");
  await env.call("/v1/wanted", { body: signed(alice.player, ["npc:589", "npc:639"]) });
  await env.call("/v1/wanted", { body: signed(bob.player, ["npc:639"]) });
  const response = await env.call("/wanted");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html/);
  const text = await response.text();
  assert.ok(text.indexOf("Edwin VanCleef") < text.indexOf(env.deps.catalog.cards["npc:589"]!.name), "wanted by two comes before wanted by one");
  assert.match(text, /<td class="num">2<\/td><td>[^<]*Alice-Realm Name[^<]*Bob-Realm Name|<td class="num">2<\/td><td>[^<]*Bob-Realm Name[^<]*Alice-Realm Name/);
  assert.match(text, /<details><summary>Alice-Realm Name: 2 cards<\/summary>/);
  assert.match(text, /<nav aria-label="Main"><a href="\/">Ladder<\/a><a href="\/wanted">Wanted<\/a>/);
  assert.ok(!/<script/i.test(text));
  // A hostile character name is shown as text.
  env.raw.prepare("UPDATE characters SET name = ? WHERE player_id = ?").run("<img src=x onerror=alert(1)>", alice.id);
  const hostile = await (await env.call("/wanted")).text();
  assert.ok(!hostile.includes("<img"));
  assert.ok(hostile.includes("&lt;img src=x onerror=alert(1)&gt;"));
});
