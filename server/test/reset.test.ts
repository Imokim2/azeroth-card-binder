// Starting a new binder: the old record is archived, the chain begins again, and the roll tape is new.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { RESET_COOLDOWN_SECONDS } from "../src/api.ts";
import { rebuild } from "../src/rebuild.ts";
import { NOW, chainedHistory, newPlayer, rankedHistory, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

const signed = (player: Player, purpose: string, extra: Record<string, unknown> = {}) => {
  const body = { key: player.publicKeyHex, sentAt: NOW, ...extra };
  return { ...body, sig: reference.signBatch({ ...body, purpose }, player.privateKey) };
};
async function register(env: ReturnType<typeof setup>, name: string) {
  const player = newPlayer(name);
  const body = await read(await env.call("/v1/register", { body: registration(player) }));
  return { player, id: body["playerId"] as string };
}
const tapeOf = async (env: ReturnType<typeof setup>, player: Player) => ((await read(await env.call("/v1/tape", { body: signed(player, "tape") }))) as unknown as { start: number; entries: string[] });
const ladder = async (env: ReturnType<typeof setup>) => ((await read(await env.call("/v1/leaderboard"))) as unknown as { entries: { playerId: string }[] }).entries.map((entry) => entry.playerId);
const count = (env: ReturnType<typeof setup>, sql: string, ...params: (string | number)[]) => Number((env.raw.prepare(sql).get(...params) as { n: number }).n);

async function playRanked(env: ReturnType<typeof setup>, player: Player, owner: string, name: string) {
  const { events, tapeNext, attempts } = await rankedHistory(owner, 3, "npc:589", `${name}-RealmName`);
  const response = await env.call("/v1/ledger", {
    body: signedUpload(player, events, { character: name, realm: "RealmName", tapeIndex: tapeNext, snapshot: { counts: { "npc:589": 3 }, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} } }),
  });
  return response;
}

test("a reset archives the old binder, empties the player's record and lets a fresh chain start from event 1", async () => {
  const env = setup();
  const alice = await register(env, "alice");
  const events = chainedHistory();
  assert.equal((await env.call("/v1/ledger", { body: signedUpload(alice.player, events) })).status, 200);
  assert.equal(count(env, "SELECT COUNT(*) AS n FROM batches WHERE player_id = ?", alice.id), 1);

  const response = await env.call("/v1/reset", { body: signed(alice.player, "reset") });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { playerId: alice.id, epoch: 1 });

  // Everything that was stored is still there, under an archive that nothing lists; the player's own record is empty.
  assert.equal(count(env, "SELECT COUNT(*) AS n FROM batches WHERE player_id = ?", alice.id), 0);
  assert.equal(count(env, "SELECT COUNT(*) AS n FROM ledger_state WHERE player_id = ?", alice.id), 0);
  const archive = env.raw.prepare("SELECT id, discord_id, visibility, status FROM players WHERE id != ?").get(alice.id) as { id: string; discord_id: string | null; visibility: string; status: string };
  assert.deepEqual([archive.discord_id, archive.visibility, archive.status], [null, "private", "active"]);
  assert.equal(count(env, "SELECT COUNT(*) AS n FROM batches WHERE player_id = ?", archive.id), 1);
  assert.equal(count(env, "SELECT COUNT(*) AS n FROM drops WHERE player_id = ?", archive.id) > 0, true);
  assert.equal(count(env, "SELECT COUNT(*) AS n FROM keys WHERE player_id = ?", archive.id), 0, "the archive has no key, so nothing can upload to it");
  assert.equal((env.raw.prepare("SELECT epoch, reset_at FROM players WHERE id = ?").get(alice.id) as { epoch: number }).epoch, 1);

  // The same key uploads a new chain from event 1; it is a different binder, stored beside the archive, not on top of it.
  const fresh = chainedHistory(1, 4);
  const upload = await env.call("/v1/ledger", { body: signedUpload(alice.player, fresh, { sentAt: NOW + 1 }) });
  assert.equal(upload.status, 200, JSON.stringify(await upload.clone().json()));
  assert.equal(((await upload.json()) as { ackSeq: number }).ackSeq, 4);
  assert.equal(count(env, "SELECT COUNT(*) AS n FROM batches WHERE player_id = ?", alice.id), 1);
  assert.equal((await rebuild(env.deps)).failed.length, 0, "the archive replays cleanly too");
});

test("a new binder gets a new roll tape: the old binder's values are not replayed, and a Ranked history works again", async () => {
  const env = setup();
  const bob = await register(env, "bob");
  const before = await tapeOf(env, bob.player);
  assert.equal(before.start, 1);
  assert.equal((await playRanked(env, bob.player, bob.id, "Bob")).status, 200);
  assert.deepEqual(await ladder(env), [bob.id]);

  assert.equal((await env.call("/v1/reset", { body: signed(bob.player, "reset") })).status, 200);
  assert.deepEqual(await ladder(env), [], "nothing is listed until the new binder plays");
  assert.equal((await env.call("/v1/player/" + bob.id)).status, 404);

  const after = await tapeOf(env, bob.player);
  assert.equal(after.start, 1, "a new tape from the start");
  assert.equal(after.entries.length, 10_000);
  assert.notDeepEqual(after.entries.slice(0, 20), before.entries.slice(0, 20), "different values");

  // A history rolled on the old values is refused; one rolled on the new tape is accepted and listed.
  env.clock.now = NOW + 10;
  const stale = await playRanked(env, bob.player, bob.id, "Bob");
  assert.equal(stale.status, 422);
  assert.equal(((await stale.json()) as Body).error?.code, "tape_invalid");
  const fresh = await playRanked(env, bob.player, `${bob.id}.1`, "Bob");
  assert.equal(fresh.status, 200, JSON.stringify(await fresh.clone().json()));
  assert.deepEqual(await ladder(env), [bob.id]);
});

test("a reset can only be asked for by the key's holder, not by a banned player, and not again for a day", async () => {
  const env = setup();
  const carol = await register(env, "carol");
  const dave = await register(env, "dave"); // registered now: a registration is only valid near the clock it was made at
  const stranger = newPlayer("stranger");
  const code = async (body: unknown) => (await read(await env.call("/v1/reset", { body }))).error?.code;
  assert.equal(await code(signed(stranger, "reset")), "unknown_key");
  assert.equal(await code({ ...signed(carol.player, "reset"), sentAt: NOW + 5 }), "bad_signature");
  assert.equal(await code(signed(carol.player, "tape")), "bad_signature", "a signature made for another purpose does not work");
  assert.equal(await code(signed(carol.player, "reset", { sentAt: NOW - 90_000 })), "bad_request");
  assert.equal(await code({ key: carol.player.publicKeyHex }), "bad_request");
  assert.equal((await env.call("/v1/reset", { method: "GET" })).status, 405);

  assert.equal((await env.call("/v1/reset", { body: signed(carol.player, "reset") })).status, 200);
  // Again straight away: told how long to wait.
  env.clock.now = NOW + 60;
  const again = await env.call("/v1/reset", { body: signed(carol.player, "reset", { sentAt: NOW + 60 }) });
  assert.equal(again.status, 429);
  assert.equal(Number(again.headers.get("retry-after")), RESET_COOLDOWN_SECONDS - 60);
  assert.equal(((await again.json()) as Body).error?.code, "too_soon");
  // A day later it is allowed, and the epoch counts up.
  env.clock.now = NOW + RESET_COOLDOWN_SECONDS + 1;
  const later = await env.call("/v1/reset", { body: signed(carol.player, "reset", { sentAt: env.clock.now }) });
  assert.deepEqual(await later.json(), { playerId: carol.id, epoch: 2 });

  // A banned player cannot use a reset to start with a clean record.
  env.raw.prepare("UPDATE players SET status = 'banned' WHERE id = ?").run(dave.id);
  assert.equal(await code(signed(dave.player, "reset", { sentAt: env.clock.now })), "banned");
});
