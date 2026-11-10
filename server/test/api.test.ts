// The HTTP API end to end, against a real SQLite database with the real migrations: registration, uploads,
// every way an upload can be wrong or dishonest, retries, the public pages and the health check.
import assert from "node:assert/strict";
import test from "node:test";
import { scoreOf } from "../src/score.ts";
import { CLIENT, NOW, casualAttempts, casualSnapshot, casualState, catalog, chain, chainedHistory, newPlayer, registration, setup, signedUpload, vectors } from "./harness.ts";

type Body = { error?: { code: string; detail?: Record<string, unknown> } } & Record<string, unknown>;
async function read(response: Response): Promise<Body> {
  return (await response.json()) as Body;
}

async function registered(env: ReturnType<typeof setup>, name = "alice", extra: Record<string, unknown> = {}) {
  const player = newPlayer(name);
  const response = await env.call("/v1/register", { body: registration(player, extra) });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  const body = await read(response);
  return { player, id: body["playerId"] as string };
}

test("registration is closed until a sign-in provider is connected", async () => {
  const env = setup({ identity: false });
  const response = await env.call("/v1/register", { body: registration(newPlayer("alice")) });
  assert.equal(response.status, 503);
  assert.equal((await read(response)).error?.code, "registration_closed");
});

test("registration needs the key's proof, a valid sign-in and a recent time", async () => {
  const env = setup();
  const alice = newPlayer("alice");
  const good = registration(alice);
  assert.equal((await env.call("/v1/register", { body: { ...good, visibility: "private" } })).status, 401); // signed as public
  assert.equal((await read(await env.call("/v1/register", { body: { ...good, visibility: "private" } }))).error?.code, "bad_signature");
  const stranger = registration(newPlayer("bob"));
  assert.equal((await read(await env.call("/v1/register", { body: { ...good, proof: stranger["proof"] } }))).error?.code, "bad_signature");
  assert.equal((await read(await env.call("/v1/register", { body: registration(alice, { identityToken: "nobody" }) }))).error?.code, "bad_identity");
  assert.equal((await read(await env.call("/v1/register", { body: registration(alice, { sentAt: NOW - 90_000 }) }))).error?.code, "bad_request");
  assert.equal((await read(await env.call("/v1/register", { body: registration(alice, { visibility: "everyone" }) }))).error?.code, "bad_request");
  assert.equal((await env.call("/v1/register", { body: good })).status, 200);
});

test("registering twice is safe, and a new key from the same account replaces the old one", async () => {
  const env = setup();
  const first = await registered(env, "alice");
  const again = await env.call("/v1/register", { body: registration(first.player) });
  assert.equal((await read(again))["playerId"], first.id);
  // The same Discord account signs in with a new key: same player, old key revoked.
  const second = newPlayer("alice-new");
  const rotated = await env.call("/v1/register", { body: registration(second, { identityToken: "discord:alice" }) });
  assert.equal((await read(rotated))["playerId"], first.id);
  const upload = (player: typeof second) => env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, 3)) });
  assert.equal((await read(await upload(first.player))).error?.code, "unknown_key");
  assert.equal((await upload(second)).status, 200); // the new key is accepted for the same player
});

test("a whole honest history is accepted, scored, and shown on the public pages", async () => {
  const env = setup();
  const { player, id } = await registered(env);
  const response = await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory()) });
  const body = await read(response);
  assert.equal(response.status, 200, JSON.stringify(body));
  const events = chainedHistory();
  assert.equal(body["ackSeq"], events.length);
  assert.equal(body["ackHash"], events[events.length - 1]?.["h"]);
  assert.equal(body["accepted"], events.length);
  assert.equal(body["duplicate"], false);
  assert.equal(body["minClient"], "0.1.0");

  const expected = scoreOf(catalog, casualState.ok ? casualState.state : (undefined as never));
  const profile = await read(await env.call("/v1/player/" + id));
  assert.equal(profile["scoreTenths"], expected.score);
  assert.equal(profile["uniqueCards"], expected.uniqueCards);
  assert.equal(profile["setsDone"], expected.setsDone);
  assert.equal(profile["rank"], 1);
  assert.equal(profile["displayName"], "Alice-RealmName");
  assert.equal(profile["attempts"], Object.values(casualAttempts).reduce((sum, value) => sum + value, 0));

  const board = await env.call("/v1/leaderboard");
  assert.equal(board.headers.get("cache-control"), "public, max-age=60");
  const entries = (await read(board))["entries"] as { rank: number; playerId: string }[];
  assert.deepEqual(entries.map((entry) => [entry.rank, entry.playerId]), [[1, id]]);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM drops").get()?.["n"], events.filter((e) => e["kind"] === "drop").length);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM flags").get()?.["n"], 0);
});

test("uploads in several batches continue the chain, and a retried batch changes nothing", async () => {
  const env = setup();
  const { player } = await registered(env);
  const events = chainedHistory();
  const send = (slice: Record<string, unknown>[]) => env.call("/v1/ledger", { body: signedUpload(player, slice) });
  const first = await read(await send(events.slice(0, 6)));
  assert.equal(first["ackSeq"], 6);
  const second = await read(await send(events.slice(6)));
  assert.equal(second["ackSeq"], events.length);
  const retry = await read(await send(events.slice(0, 6)));
  assert.equal(retry["duplicate"], true);
  assert.equal(retry["accepted"], 0);
  assert.equal(retry["ackSeq"], events.length); // the answer says where the server really is
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 2);
  // An empty batch just reports where the chain stands.
  const empty = await read(await send([]));
  assert.equal(empty["ackSeq"], events.length);
});

test("each way an upload can be wrong is refused with its own code, and nothing is stored", async () => {
  const env = setup();
  const { player } = await registered(env);
  const events = chainedHistory();
  const expectError = async (body: unknown, code: string, status: number) => {
    const response = await env.call("/v1/ledger", { body });
    const result = await read(response);
    assert.equal(result.error?.code, code, JSON.stringify(result));
    assert.equal(response.status, status);
    return result;
  };
  // Changed after signing.
  const signed = signedUpload(player, events.slice(0, 4));
  await expectError({ ...signed, tapeIndex: 9 }, "bad_signature", 401);
  // A cheater who edits an event and signs again is caught by the chain.
  const edited = chainedHistory(1, 4).map((event) => ({ ...event }));
  (edited[2] as Record<string, unknown>)["count"] = 9;
  await expectError(signedUpload(player, edited), "bad_hash", 422);
  // Events out of order, missing, or pointing at the wrong one.
  await expectError(signedUpload(player, [events[1] as Record<string, unknown>, events[0] as Record<string, unknown>]), "gap", 409);
  await expectError(signedUpload(player, [events[0] as Record<string, unknown>, events[2] as Record<string, unknown>]), "gap", 409);
  const wrongPrev = chainedHistory(1, 3).map((event) => ({ ...event }));
  (wrongPrev[1] as Record<string, unknown>)["prev"] = "f".repeat(32);
  await expectError(signedUpload(player, wrongPrev), "bad_prev", 422);
  await expectError(signedUpload(player, [{ ...(events[0] as object), kind: "gift" }]), "bad_field", 422);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 0);

  // Store a prefix, then send events that were already stored in a different grouping: a replay, with the head given.
  await env.call("/v1/ledger", { body: signedUpload(player, events.slice(0, 5)) });
  const replayed = await expectError(signedUpload(player, events.slice(2, 7)), "replay", 409);
  assert.equal(replayed.error?.detail?.["ackSeq"], 5);
  const skipped = await expectError(signedUpload(player, events.slice(6, 9)), "gap", 409);
  assert.equal(skipped.error?.detail?.["ackSeq"], 5);
});

test("rewriting events that are already stored is refused as a rewrite, not a replay", async () => {
  const env = setup();
  const { player } = await registered(env);
  const events = chainedHistory();
  await env.call("/v1/ledger", { body: signedUpload(player, events.slice(0, 5)) });
  // The same five positions, different contents, hashes and signature all recomputed.
  const rewritten = chain(vectors.valid.events.slice(0, 5).map((event, index) => ({ ...event, t: Number(event["t"]) + (index === 0 ? 1 : 0) })));
  const response = await env.call("/v1/ledger", { body: signedUpload(player, rewritten) });
  const body = await read(response);
  assert.equal(body.error?.code, "duplicate_batch");
  assert.equal(response.status, 409);
  assert.equal(body.error?.detail?.["ackSeq"], 5);
});

test("a busy database is reported as overloaded with a retry time, not as a server fault", async () => {
  const env = setup();
  env.deps.board.top = async () => { throw new Error("D1 DB is overloaded. Requests queued for too long."); };
  const response = await env.call("/v1/leaderboard");
  assert.equal(response.status, 503);
  assert.equal(response.headers.get("retry-after"), "5");
  const body = await read(response);
  assert.equal(body.error?.code, "overloaded");
  assert.equal(body.error?.["retryAfter" as keyof typeof body.error], 5);
});

test("a cheater who recomputes every hash and signs again is still stopped by the rules", async () => {
  const env = setup();
  const { player } = await registered(env);
  for (const item of vectors.invalid) {
    const events = chain(item.events.map((event) => {
      const { prev, h, ...rest } = event as Record<string, unknown>;
      void prev; void h;
      return rest;
    }));
    const response = await env.call("/v1/ledger", { body: signedUpload(player, events) });
    const body = await read(response);
    assert.equal(response.status, 422, item.name);
    assert.equal(body.error?.code, "rule_broken", item.name);
    assert.equal(body.error?.detail?.["rule"], item.rule, item.name);
    assert.equal(body.error?.detail?.["index"], item.index, item.name);
  }
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 0);
});

test("a snapshot that disagrees with the events is flagged, and the events still decide", async () => {
  const env = setup();
  const { player } = await registered(env);
  const snapshot = { ...casualSnapshot, attempts: {}, titles: {}, dust: 999 };
  const response = await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(), { snapshot }) });
  assert.equal(response.status, 200);
  const flag = env.raw.prepare("SELECT kind, notes, state FROM flags").get();
  assert.deepEqual({ ...flag }, { kind: "snapshot-mismatch", notes: "dust", state: "open" });
});

test("two uploads racing for the same place cannot both be stored", async () => {
  const env = setup();
  const { player } = await registered(env);
  const sends = [signedUpload(player, chainedHistory(1, 4)), signedUpload(player, chainedHistory(1, 4), { sentAt: NOW + 1 })];
  const responses = await Promise.all(sends.map((body) => env.call("/v1/ledger", { body })));
  const codes = await Promise.all(responses.map(async (response) => response.status === 200 ? "ok" : (await read(response)).error?.code));
  assert.deepEqual([...codes].sort(), ["conflict", "ok"]);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 1);
  const retried = await read(await env.call("/v1/ledger", { body: sends[1] }));
  assert.equal(retried["duplicate"], true);
});

test("private players are stored but never listed, and banned players cannot upload", async () => {
  const env = setup();
  const quiet = await registered(env, "quiet", { visibility: "private" });
  await env.call("/v1/ledger", { body: signedUpload(quiet.player, chainedHistory()) });
  assert.deepEqual((await read(await env.call("/v1/leaderboard")))["entries"], []);
  assert.equal((await env.call("/v1/player/" + quiet.id)).status, 404);
  env.raw.prepare("UPDATE players SET status = 'banned' WHERE id = ?").run(quiet.id);
  const response = await env.call("/v1/ledger", { body: signedUpload(quiet.player, []) });
  // A banned player's key is still active in the keys table but the player status refuses the upload.
  assert.equal((await read(response)).error?.code, "banned");
});

test("the leaderboard orders by score, then by who got there first, and honours the limit", async () => {
  const env = setup();
  const names = ["a", "b", "c"];
  const ids: string[] = [];
  for (const [index, name] of names.entries()) {
    const { player, id } = await registered(env, name);
    env.clock.now = NOW + index * 10;
    const count = index === 2 ? chainedHistory().length : 3; // c has more; a and b tie
    const events = chainedHistory(1, count);
    const snapshot = { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} };
    await env.call("/v1/ledger", { body: signedUpload(player, events, { snapshot }) });
    ids.push(id);
  }
  const board = (await read(await env.call("/v1/leaderboard")))["entries"] as { playerId: string; rank: number }[];
  assert.deepEqual(board.map((entry) => entry.playerId), [ids[2], ids[0], ids[1]]);
  const limited = (await read(await env.call("/v1/leaderboard?limit=2")))["entries"] as unknown[];
  assert.equal(limited.length, 2);
  assert.equal(((await read(await env.call("/v1/leaderboard?limit=-5")))["entries"] as unknown[]).length, 3);
  const second = await read(await env.call("/v1/player/" + ids[0]));
  assert.equal(second["rank"], 2);
});

test("bad requests get plain answers", async () => {
  const env = setup();
  const code = async (response: Response) => (await read(response)).error?.code;
  assert.equal(await code(await env.call("/v1/ledger", { raw: "{not json" })), "bad_request");
  assert.equal(await code(await env.call("/v1/ledger", { raw: "[]" })), "bad_request");
  assert.equal(await code(await env.call("/v1/ledger", { raw: "{}", headers: { "content-type": "text/plain" } })), "unsupported_media");
  assert.equal(await code(await env.call("/v1/ledger", { raw: "x".repeat(2_000_001) })), "too_large");
  assert.equal(await code(await env.call("/v1/ledger", { body: {}, headers: { "x-warcards-client": "" } })), "bad_request");
  assert.equal(await code(await env.call("/v1/ledger", { body: {}, headers: { "x-warcards-client": "0.0.9" } })), "client_too_old");
  const { player } = await registered(env);
  assert.equal(await code(await env.call("/v1/ledger", { body: { ...signedUpload(player, []), specVersion: 99 } })), "client_too_old");
  assert.equal(await code(await env.call("/v1/ledger", { body: { ...signedUpload(player, []), events: "none" } })), "bad_request");
  const stranger = signedUpload(newPlayer("stranger"), []);
  assert.equal(await code(await env.call("/v1/ledger", { body: stranger })), "unknown_key");
  assert.equal(await code(await env.call("/v1/nothing")), "not_found");
  assert.equal(await code(await env.call("/v1/player/not-an-id")), "not_found");
  const wrongMethod = await env.call("/v1/ledger", { method: "GET" });
  assert.equal(wrongMethod.status, 405);
  assert.equal(wrongMethod.headers.get("allow"), "POST");
  assert.equal(CLIENT, "0.1.0");
});

test("health checks the database, and every request is logged once with its route and status", async () => {
  const env = setup();
  const ok = await read(await env.call("/v1/health"));
  assert.equal(ok["ok"], true);
  assert.equal(ok["catalogVersion"], catalog.catalogVersion);
  env.breakHealth();
  const down = await env.call("/v1/health");
  assert.equal(down.status, 503);
  assert.equal((await read(down))["ok"], false);
  const requests = env.logs.filter((entry) => entry["msg"] === "request");
  assert.deepEqual(requests.map((entry) => [entry["route"], entry["status"]]), [["health", 200], ["health", 503]]);
  assert.ok(requests.every((entry) => typeof entry["requestId"] === "string" && typeof entry["ms"] === "number"));
});

test("an unexpected failure is logged in full but answered without internal detail", async () => {
  const env = setup();
  env.deps.board.top = async () => { throw new Error("secret database detail"); };
  const response = await env.call("/v1/leaderboard");
  assert.equal(response.status, 500);
  const text = await response.text();
  assert.ok(!text.includes("secret"));
  assert.equal(JSON.parse(text).error.code, "internal");
  assert.ok(env.logs.some((entry) => entry["level"] === "error" && String(entry["error"]).includes("secret database detail")));
  assert.ok(response.headers.get("x-request-id"));
});
