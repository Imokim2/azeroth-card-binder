// The admin panel's reset and restore: a reset archives the player's binder (nothing is lost) and refuses their old history afterwards,
// because their add-on still holds it; a restore brings an archived binder back and puts the current one aside in turn.
import assert from "node:assert/strict";
import test from "node:test";
import { ADMIN_TOKEN, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";

type Body = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any
const admin = { authorization: "Bearer " + ADMIN_TOKEN };

async function world() {
  const env = setup();
  const player = newPlayer("alice");
  const registered = (await (await env.call("/v1/register", { body: registration(player, { visibility: "public" }) })).json()) as Body;
  const id = registered["playerId"] as string;
  const upload = (count: number) => env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, count), { character: "Filfred", realm: "Whizzlebang" }) });
  assert.equal((await upload(3)).status, 200);
  env.pretendVerified();
  const detail = async () => ((await (await env.call(`/v1/admin/players/${id}`, { headers: admin })).json()) as { player: Body }).player;
  const post = (action: string, body: unknown) => env.call(`/v1/admin/players/${id}/${action}`, { method: "POST", headers: admin, body });
  const epoch = () => (env.raw.prepare("SELECT epoch FROM players WHERE id = ?").get(id) as { epoch: number }).epoch;
  return { env, player, id, upload, detail, post, epoch };
}

test("reset and restore need the admin token, the player id repeated, and an existing player", async () => {
  const { env, id, post } = await world();
  assert.equal((await env.call(`/v1/admin/players/${id}/reset`, { method: "POST", body: { confirm: id } })).status, 401);
  assert.equal((await env.call(`/v1/admin/players/${id}/restore`, { method: "POST", body: { confirm: id } })).status, 401);
  assert.equal((await post("reset", {})).status, 400);
  assert.equal((await post("reset", { confirm: "yes" })).status, 400);
  assert.equal((await post("reset", { confirm: id, reason: "x".repeat(201) })).status, 400);
  const other = "01ARZ3NDEKTSV4RRFFQ69G5FAV";
  assert.equal((await env.call(`/v1/admin/players/${other}/reset`, { method: "POST", headers: admin, body: { confirm: other } })).status, 404);
  assert.equal((await post("restore", { confirm: id })).status, 400, "no archive named");
  assert.equal((await post("restore", { confirm: id, archiveId: "nope" })).status, 400);
  assert.equal((await post("restore", { confirm: id, archiveId: other })).status, 404, "an archive that is not theirs");
});

test("a reset archives the binder, takes the player off the ladder, bars the old history and is recorded", async () => {
  const { env, id, detail, post, epoch, upload } = await world();
  const before = await detail();
  assert.equal(before["binder"]["cardsOwned"] > 0, true);
  assert.equal((await env.call(`/v1/player/${id}`)).status, 200, "on the ladder before");
  const done = await post("reset", { confirm: id, reason: "Binder was edited" });
  assert.equal(done.status, 200);
  assert.deepEqual(await done.json(), { playerId: id, reset: true });
  const after = await detail();
  assert.equal(after["binder"], null);
  assert.equal(after["score"], null);
  assert.equal(after["archives"].length, 1);
  assert.equal(after["archives"][0]["cardsOwned"], before["binder"]["cardsOwned"]);
  assert.equal(after["archives"][0]["batches"], 1);
  assert.equal(after["barredBefore"], env.clock.now);
  assert.equal(epoch(), 1, "a new roll tape for the next binder");
  assert.equal((await env.call(`/v1/player/${id}`)).status, 404, "off the ladder");
  // The player is still found by the name on the binder that was put aside (so a restore can be done), once, and the archive itself is not listed.
  const found = ((await env.call("/v1/admin/players?q=Filfred", { headers: admin }).then((r) => r.json())) as Body)["players"] as Body[];
  assert.deepEqual(found.map((row) => row["playerId"]), [id]);
  assert.ok(found[0]!["displayName"].includes("Filfred"), "named from the archived binder");
  // Their add-on still holds the old history: it is refused, and nothing is stored.
  const again = await upload(3);
  assert.equal(again.status, 409);
  assert.equal(((await again.json()) as Body)["error"]["code"], "binder_reset");
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM batches WHERE player_id = ?").get(id) as { n: number }).n, 0);
  // Nothing to reset a second time.
  assert.equal((await post("reset", { confirm: id })).status, 400);
  const entries = ((await (await env.call("/v1/admin/audit", { headers: admin })).json()) as { entries: Body[] }).entries;
  assert.deepEqual([entries[0]!["action"], entries[0]!["target"], entries[0]!["detail"]], ["reset-binder", id, "Binder was edited"]);
});

test("a binder started after the reset is accepted: only history from before it is refused", async () => {
  const { env, id, post, upload, detail } = await world();
  await post("reset", { confirm: id });
  env.raw.prepare("UPDATE players SET barred_before = 500 WHERE id = ?").run(id); // the reset was before the new binder's first event (t = 1000)
  assert.equal((await upload(2)).status, 200);
  assert.equal((await detail())["uploads"]["batches"], 1);
  assert.equal((await detail())["archives"].length, 1, "the old binder is still put aside");
});

test("a restore brings the binder back with its epoch and chain, so the player's add-on carries on", async () => {
  const { env, id, post, detail, epoch, upload } = await world();
  const original = await detail();
  await post("reset", { confirm: id });
  const archiveId = (await detail())["archives"][0]["archiveId"] as string;
  const restored = await post("restore", { confirm: id, archiveId, reason: "Reset was a mistake" });
  assert.equal(restored.status, 200);
  assert.deepEqual(await restored.json(), { playerId: id, restored: archiveId });
  const after = await detail();
  assert.deepEqual(after["binder"], original["binder"]);
  assert.equal(after["score"]["scoreTenths"], original["score"]["scoreTenths"]);
  assert.equal(after["barredBefore"], null);
  assert.equal(after["archives"].length, 0, "no empty archive is left behind");
  assert.equal(epoch(), 0, "back to the epoch the binder was written under");
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM players WHERE id = ?").get(archiveId) as { n: number }).n, 0);
  assert.equal((await env.call(`/v1/player/${id}`)).status, 200, "back on the ladder");
  // The add-on's upload of the same history is simply already stored.
  const resent = await upload(3);
  assert.equal(resent.status, 200);
  assert.equal(((await resent.json()) as Body)["duplicate"], true);
  const entries = ((await (await env.call("/v1/admin/audit", { headers: admin })).json()) as { entries: Body[] }).entries;
  assert.deepEqual([entries[0]!["action"], entries[0]!["target"]], ["restore-binder", id]);
  assert.match(entries[0]!["detail"], new RegExp(`^Reset was a mistake - binder ${archiveId}$`));
  // A binder restored once is not an archive any more: restoring it again finds nothing.
  assert.equal((await post("restore", { confirm: id, archiveId })).status, 404);
});

test("restoring over a binder the player has started since puts that one aside, and nothing is lost either way", async () => {
  const { env, id, post, detail, epoch, upload } = await world();
  await post("reset", { confirm: id });
  const oldArchive = (await detail())["archives"][0]["archiveId"] as string;
  env.raw.prepare("UPDATE players SET barred_before = 500 WHERE id = ?").run(id);
  assert.equal((await upload(2)).status, 200); // a new binder of two events
  assert.equal(epoch(), 1);
  assert.equal((await post("restore", { confirm: id, archiveId: oldArchive })).status, 200);
  const after = await detail();
  assert.equal(after["binder"]["headSeq"], 3, "the three-event binder is current again");
  assert.equal(after["archives"].length, 1, "and the two-event one is the archive");
  assert.equal(after["archives"][0]["batches"], 1);
  assert.equal(after["archives"][0]["epoch"], 1, "written under epoch 1");
  assert.equal(epoch(), 0);
  // Restoring that one swaps them back.
  assert.equal((await post("restore", { confirm: id, archiveId: after["archives"][0]["archiveId"] })).status, 200);
  const swapped = await detail();
  assert.equal(swapped["binder"]["headSeq"], 2);
  assert.equal(epoch(), 1);
  assert.equal(swapped["archives"].length, 1);
});

test("deleting a player removes their archived binders too, and no foreign keys are left dangling", async () => {
  const { env, id, post } = await world();
  await post("reset", { confirm: id });
  const done = await post("delete", { confirm: id });
  assert.equal(done.status, 200);
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM players").get() as { n: number }).n, 0);
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get() as { n: number }).n, 0);
  assert.deepEqual(env.raw.prepare("PRAGMA foreign_key_check").all(), []);
});
