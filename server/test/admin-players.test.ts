// The admin panel's player tools: finding a player, looking at what is held about one, banning with a reason, deleting with a
// confirmation, and the audit record of each of those with the name of who did it.
import assert from "node:assert/strict";
import test from "node:test";
import { ADMIN_TOKEN, NOW, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";

type Body = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any
const admin = { authorization: "Bearer " + ADMIN_TOKEN };

async function world() {
  const env = setup();
  const make = async (name: string, character: string, realm: string, visibility = "public") => {
    const player = newPlayer(name);
    const registered = (await (await env.call("/v1/register", { body: registration(player, { visibility }) })).json()) as Body;
    await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, 3), { character, realm }) });
    env.clock.now += 5;
    return { player, id: registered["playerId"] as string };
  };
  const alice = await make("alice", "Filfred", "Whizzlebang");
  const bob = await make("bob", "Bobsled", "Realm Name", "private");
  return { env, alice, bob };
}
const get = (env: ReturnType<typeof setup>, path: string, headers = admin) => env.call(path, { headers });
const post = (env: ReturnType<typeof setup>, path: string, body: unknown) => env.call(path, { method: "POST", headers: admin, body });

test("the player routes need the admin token, and do not exist without one", async () => {
  const { env, alice } = await world();
  for (const path of ["/v1/admin/players", `/v1/admin/players/${alice.id}`, "/v1/admin/audit", "/v1/admin/me"]) {
    assert.equal((await env.call(path)).status, 401, path);
    assert.equal((await env.call(path, { headers: { authorization: "Bearer wrong" } })).status, 401, path);
  }
  assert.equal((await env.call(`/v1/admin/players/${alice.id}/delete`, { method: "POST", body: { confirm: alice.id } })).status, 401);
  env.deps.adminToken = undefined;
  assert.equal((await env.call("/v1/admin/players")).status, 404);
});

test("a player is found by name, by character, by id, or listed newest first, and typed wildcards match nothing extra", async () => {
  const { env, alice, bob } = await world();
  const find = async (query: string) => ((await (await get(env, "/v1/admin/players?q=" + encodeURIComponent(query))).json()) as Body)["players"] as Body[];
  assert.deepEqual((await find("")).map((row) => row["playerId"]), [bob.id, alice.id], "newest first");
  assert.deepEqual((await find("fil")).map((row) => row["playerId"]), [alice.id], "by character name, in part, in any case");
  assert.deepEqual((await find("BOBSLED")).map((row) => row["playerId"]), [bob.id]);
  assert.deepEqual((await find("realm name")).map((row) => row["playerId"]), [bob.id], "by name and realm together");
  assert.deepEqual((await find(alice.id.toLowerCase())).map((row) => row["playerId"]), [alice.id], "by player id");
  assert.deepEqual(await find("nobody"), []);
  assert.deepEqual(await find("%"), [], "a percent sign is a character, not a wildcard");
  assert.deepEqual(await find("_"), []);
  const row = (await find(alice.id))[0] as Body;
  assert.equal(row["status"], "active");
  assert.equal(row["visibility"], "public");
  assert.ok(Array.isArray(row["characters"]) && row["characters"].length === 1);
  assert.ok(!JSON.stringify(row).includes("discord"), "no Discord id in a search result");
  // Private players are findable here: the panel is for the people who run the service.
  assert.equal((await find("bobsled")).length, 1);
  // Bad queries and limits.
  assert.equal((await get(env, "/v1/admin/players?q=" + "x".repeat(65))).status, 400);
  assert.equal((await get(env, "/v1/admin/players?q=a%00b")).status, 400);
  assert.equal((((await (await get(env, "/v1/admin/players?limit=1")).json()) as Body)["players"] as Body[]).length, 1);
});

test("a player's page holds what a reviewer needs and nothing secret", async () => {
  const { env, alice } = await world();
  env.raw.prepare("INSERT INTO flags (id, player_id, kind, notes, created_at) VALUES ('f1', ?, 'luck-hold', 'lucky', ?)").run(alice.id, NOW);
  const response = await get(env, `/v1/admin/players/${alice.id}`);
  assert.equal(response.status, 200);
  const text = await response.text();
  const body = JSON.parse(text) as { player: Body };
  const player = body.player;
  assert.equal(player["playerId"], alice.id);
  assert.equal(player["status"], "active");
  assert.equal(player["hasDiscord"], true);
  assert.deepEqual(player["keys"], { active: 1, revoked: 0 });
  assert.equal(player["characters"][0]["name"], "Filfred");
  assert.ok(player["score"] && typeof player["score"]["scoreTenths"] === "number");
  assert.equal(player["binder"]["mode"], "casual");
  assert.ok(player["binder"]["cardsOwned"] > 0);
  assert.equal(player["uploads"]["batches"], 1);
  assert.equal(player["flags"].length >= 1, true);
  assert.ok(player["flags"].some((flag: Body) => flag["id"] === "f1"));
  assert.equal(player["reportsAbout"], 0);
  // No Discord id, no key, no events, no tape secrets.
  assert.ok(!text.includes(alice.player.discord) && !text.includes(alice.player.publicKeyHex), "no Discord id or key");
  assert.ok(!/"events"|"commitment"|"hash"/.test(text));
  assert.equal((await get(env, "/v1/admin/players/01ARZ3NDEKTSV4RRFFQ69G5FAV")).status, 404);
  assert.equal((await get(env, "/v1/admin/players/not-an-id")).status, 404);
});

test("banning takes an optional reason, is recorded with who did it, and lifting it is recorded too", async () => {
  const { env, alice } = await world();
  assert.equal((await post(env, `/v1/admin/players/${alice.id}/ban`, { banned: true, reason: "x".repeat(201) })).status, 400);
  assert.equal((await post(env, `/v1/admin/players/${alice.id}/ban`, { banned: true, reason: "Edited their saved file" })).status, 200);
  assert.equal(((await (await get(env, `/v1/admin/players/${alice.id}`)).json()) as { player: Body }).player["status"], "banned");
  assert.equal((await post(env, `/v1/admin/players/${alice.id}/ban`, { banned: false })).status, 200);
  assert.equal((await post(env, "/v1/admin/players/01ARZ3NDEKTSV4RRFFQ69G5FAV/ban", { banned: true })).status, 404);
  const entries = ((await (await get(env, "/v1/admin/audit")).json()) as { entries: Body[] }).entries;
  assert.deepEqual(entries.map((entry) => [entry["action"], entry["target"], entry["detail"], entry["actor"]]),
    [["unban", alice.id, "", "token"], ["ban", alice.id, "Edited their saved file", "token"]], "newest first; a failed ban leaves no entry");
});

test("deleting a player needs their id repeated, removes their data, and the record of it stays without their name", async () => {
  const { env, alice, bob } = await world();
  assert.equal((await post(env, `/v1/admin/players/${alice.id}/delete`, {})).status, 400);
  assert.equal((await post(env, `/v1/admin/players/${alice.id}/delete`, { confirm: bob.id })).status, 400);
  assert.equal((await post(env, `/v1/admin/players/${alice.id}/delete`, { confirm: "yes" })).status, 400);
  assert.equal((await post(env, "/v1/admin/players/01ARZ3NDEKTSV4RRFFQ69G5FAV/delete", { confirm: "01ARZ3NDEKTSV4RRFFQ69G5FAV" })).status, 404);
  assert.equal(((await (await get(env, `/v1/admin/players/${alice.id}`)).json()) as { player: Body }).player["playerId"], alice.id, "nothing was deleted yet");
  const done = await post(env, `/v1/admin/players/${alice.id}/delete`, { confirm: alice.id });
  assert.equal(done.status, 200);
  assert.deepEqual(await done.json(), { playerId: alice.id, deleted: true });
  assert.equal((await get(env, `/v1/admin/players/${alice.id}`)).status, 404);
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM players WHERE id = ?").get(alice.id) as { n: number }).n, 0);
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM batches WHERE player_id = ?").get(alice.id) as { n: number }).n, 0);
  assert.equal(((await (await get(env, `/v1/admin/players/${bob.id}`)).json()) as { player: Body }).player["playerId"], bob.id, "other players are untouched");
  const entries = ((await (await get(env, "/v1/admin/audit")).json()) as { entries: Body[] }).entries;
  assert.equal(entries.length, 1);
  assert.equal(entries[0]!["action"], "delete-player");
  assert.equal(entries[0]!["target"], alice.id);
  assert.ok(!JSON.stringify(entries).includes("Filfred") && !JSON.stringify(entries).includes(alice.player.discord), "the record holds no name or Discord id");
  // Their signed-in app can no longer upload with the old key.
  const after = await env.call("/v1/ledger", { body: signedUpload(alice.player, chainedHistory(1, 3), { character: "Filfred", realm: "Whizzlebang" }) });
  assert.equal(after.status, 401);
});

test("flag decisions and rebuilds are recorded too, in order, with a limit on how many are shown", async () => {
  const { env, alice } = await world();
  env.raw.prepare("INSERT INTO flags (id, player_id, kind, notes, created_at) VALUES ('f1', ?, 'luck-hold', 'lucky', ?)").run(alice.id, NOW);
  assert.equal((await post(env, "/v1/admin/flags/f1", { state: "cleared", note: "just luck" })).status, 200);
  assert.equal((await post(env, "/v1/admin/flags/nope", { state: "cleared" })).status, 404);
  assert.equal((await post(env, "/v1/admin/rebuild", { dryRun: true, limit: 10 })).status, 200);
  env.clock.now += 10;
  assert.equal((await post(env, `/v1/admin/players/${alice.id}/ban`, { banned: true })).status, 200);
  const all = ((await (await get(env, "/v1/admin/audit")).json()) as { entries: Body[] }).entries;
  assert.deepEqual(all.map((entry) => entry["action"]), ["ban", "rebuild-dry-run", "flag-cleared"]);
  assert.equal(all[2]!["detail"], "just luck");
  assert.equal(all[1]!["detail"], "limit 10");
  assert.equal(((await (await get(env, "/v1/admin/audit?limit=1")).json()) as { entries: Body[] }).entries.length, 1);
  // A failure to write the record is logged and does not undo or fail the action.
  env.deps.admin = { ...env.store, record: async () => { throw new Error("disk full"); }, audit: env.store.audit.bind(env.store), search: env.store.search.bind(env.store), detail: env.store.detail.bind(env.store), adminReset: env.store.adminReset.bind(env.store), restoreBinder: env.store.restoreBinder.bind(env.store) };
  assert.equal((await post(env, `/v1/admin/players/${alice.id}/ban`, { banned: false })).status, 200);
  assert.ok(env.logs.some((entry) => entry["msg"] === "audit write failed"));
});
