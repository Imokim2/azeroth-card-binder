// Reports: one player telling us about another. A note for a person to read; several players reporting the same one opens a review flag.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { ADMIN_TOKEN, NOW, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string; detail?: Record<string, unknown> } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };
const admin = { authorization: "Bearer " + ADMIN_TOKEN };

type Report = { token: string; target: string; reason: string; note: string };
const signed = (player: Player, reports: unknown, extra: Record<string, unknown> = {}, purpose = "report") => {
  const body = { key: player.publicKeyHex, sentAt: NOW, reports, ...extra };
  return { ...body, sig: reference.signBatch({ ...body, purpose }, player.privateKey) };
};
const one = (token: string, target: string, extra: Partial<Report> = {}): Report => ({ token, target, reason: "cheating", note: "", ...extra });

// A registered player who has played, so the server knows a character of theirs by name.
async function member(env: ReturnType<typeof setup>, name: string) {
  const player = newPlayer(name);
  const registered = await read(await env.call("/v1/register", { body: registration(player, { visibility: "public" }) }));
  await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, 3), { character: name, realm: "Realm Name" }) });
  return { player, id: registered["playerId"] as string, peer: `${name.toLowerCase()}-realmname` };
}
const send = async (env: ReturnType<typeof setup>, player: Player, reports: unknown, extra: Record<string, unknown> = {}) => env.call("/v1/report", { body: signed(player, reports, extra) });
const flagKinds = (env: ReturnType<typeof setup>, playerId: string) =>
  (env.raw.prepare("SELECT kind FROM flags WHERE player_id = ? AND state = 'open' AND kind = 'reported'").all(playerId) as { kind: string }[]).map((row) => row.kind);
const count = (env: ReturnType<typeof setup>, where = "1 = 1") => (env.raw.prepare(`SELECT COUNT(*) AS n FROM reports WHERE ${where}`).get() as { n: number }).n;

test("a report is stored against the player the character belongs to, and a reviewer can read it", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  const bob = await member(env, "Bob");
  const response = await send(env, alice.player, [one("tok00001", bob.peer, { reason: "trading", note: "took the card, gave nothing" })]);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { done: ["tok00001"], stored: 1 });
  assert.equal(count(env, `target_id = '${bob.id}'`), 1);
  // One report opens nothing.
  assert.deepEqual(flagKinds(env, bob.id), []);
  const seen = await read(await env.call(`/v1/admin/reports?player=${bob.id}`, { headers: admin }));
  const reports = seen["reports"] as { reporterId: string; reason: string; note: string; targetName: string }[];
  assert.equal(reports.length, 1);
  assert.deepEqual([reports[0]!.reporterId, reports[0]!.reason, reports[0]!.note, reports[0]!.targetName], [alice.id, "trading", "took the card, gave nothing", bob.peer]);
  // Only a reviewer can read them.
  assert.equal((await read(await env.call(`/v1/admin/reports?player=${bob.id}`))).error?.code, "unauthorized");
  assert.equal((await read(await env.call(`/v1/admin/reports?player=${bob.id}`, { headers: { authorization: "Bearer wrong" } }))).error?.code, "unauthorized");
  assert.equal((await read(await env.call("/v1/admin/reports?player=nope", { headers: admin }))).error?.code, "bad_request");
});

test("telling us twice changes nothing: the same report, or the same character within a day", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  const bob = await member(env, "Bob");
  await send(env, alice.player, [one("tok00001", bob.peer)]);
  // The same token again (a lost reply), and a new token for the same character: settled, not stored again.
  const again = await read(await send(env, alice.player, [one("tok00001", bob.peer), one("tok00002", bob.peer)], { sentAt: NOW + 1 }));
  assert.deepEqual(again, { done: ["tok00001", "tok00002"], stored: 0 });
  assert.equal(count(env), 1);
  // A day later the same character can be reported again.
  env.clock.now = NOW + 86_401;
  const later = await read(await send(env, alice.player, [one("tok00003", bob.peer)], { sentAt: NOW + 86_401 }));
  assert.equal(later["stored"], 1);
});

test("three different players reporting one player opens a single review flag, and nothing else happens to them", async () => {
  const env = setup();
  const target = await member(env, "Target");
  const names = ["Ann", "Ben", "Cat", "Dan"];
  for (const [index, name] of names.entries()) {
    const reporter = await member(env, name);
    await send(env, reporter.player, [one("tok0000" + index, target.peer)]);
    assert.deepEqual(flagKinds(env, target.id), index >= 2 ? ["reported"] : [], `after ${index + 1} reports`);
  }
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM flags WHERE kind = 'reported'").get() as { n: number }).n, 1, "a fourth report does not open a second flag");
  // The same player reporting three times is still one reporter.
  const solo = setup();
  const t = await member(solo, "Target");
  const r = await member(solo, "Reporter");
  for (let day = 0; day < 3; day++) {
    solo.clock.now = NOW + day * 86_401;
    await send(solo, r.player, [one("tok0000" + day, t.peer)], { sentAt: NOW + day * 86_401 });
  }
  assert.deepEqual(flagKinds(solo, t.id), []);
  // The flag says only how many players, and the target is still on the ladder's books (no hold).
  const flag = env.raw.prepare("SELECT notes FROM flags WHERE kind = 'reported'").get() as { notes: string };
  assert.match(flag.notes, /players reported them/);
});

test("reporting yourself, or a character nobody has played, is settled without any effect on a player", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  const response = await read(await send(env, alice.player, [one("tok00001", alice.peer), one("tok00002", "nobody-realmname")]));
  assert.deepEqual(response, { done: ["tok00001", "tok00002"], stored: 1 });
  assert.equal(count(env, "target_id IS NULL"), 1, "an unknown name is kept for a reviewer to search, tied to no player");
  assert.equal(count(env, `target_id = '${alice.id}'`), 0);
});

test("a player can send only so many reports a day, and the rest wait", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  const batch = (from: number) => Array.from({ length: 10 }, (_, index) => one(`tok${String(from + index).padStart(5, "0")}`, `name${from + index}-realmname`));
  assert.equal((await read(await send(env, alice.player, batch(0))))["stored"], 10);
  assert.equal((await read(await send(env, alice.player, batch(10), { sentAt: NOW + 1 })))["stored"], 10);
  const over = await read(await send(env, alice.player, batch(20), { sentAt: NOW + 2 }));
  assert.deepEqual(over, { done: [], stored: 0 }, "nothing settled: the add-on keeps them and the app sends them again tomorrow");
  assert.equal(count(env), 20);
});

test("a malformed or unsigned report is refused outright and stores nothing", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  const bob = await member(env, "Bob");
  const code = async (body: unknown) => (await read(await env.call("/v1/report", { body }))).error?.code;
  const field = async (reports: unknown) => (await read(await send(env, alice.player, reports))).error?.detail?.["field"];
  assert.equal(await field([]), "reports");
  assert.equal(await field("x"), "reports");
  assert.equal(await field(Array.from({ length: 11 }, (_, index) => one("tok0000" + index, bob.peer))), "reports");
  assert.equal(await field([one("short", bob.peer)]), "token");
  assert.equal(await field([one("tok00001", bob.peer), one("tok00001", "x-y")]), "token", "a token repeated within one request");
  assert.equal(await field([one("tok00001", "no realm")]), "target");
  assert.equal(await field([one("tok00001", "<b>x</b>-realm")]), "target");
  assert.equal(await field([one("tok00001", bob.peer, { reason: "rude" })]), "reason");
  assert.equal(await field([one("tok00001", bob.peer, { note: "x".repeat(121) })]), "note");
  assert.equal(await field([one("tok00001", bob.peer, { note: "line\nbreak" })]), "note");
  assert.equal(await code(signed(newPlayer("stranger"), [one("tok00001", bob.peer)])), "unknown_key");
  assert.equal(await code({ ...signed(alice.player, [one("tok00001", bob.peer)]), sentAt: NOW + 5 }), "bad_signature");
  assert.equal(await code(signed(alice.player, [one("tok00001", bob.peer)], {}, "wanted")), "bad_signature");
  assert.equal(await code(signed(alice.player, [one("tok00001", bob.peer)], { sentAt: NOW - 90_000 })), "bad_request");
  assert.equal(await code({ key: alice.player.publicKeyHex }), "bad_request");
  assert.equal((await env.call("/v1/report")).status, 405);
  assert.equal(count(env), 0);
  // A banned player cannot send reports.
  await env.call(`/v1/admin/players/${alice.id}/ban`, { body: { banned: true }, headers: admin });
  assert.equal(await code(signed(alice.player, [one("tok00009", bob.peer)])), "banned");
});

test("deleting a player removes the reports they sent and the reports about them", async () => {
  const env = setup();
  const alice = await member(env, "Alice");
  const bob = await member(env, "Bob");
  await send(env, alice.player, [one("tok00001", bob.peer)]);
  await send(env, bob.player, [one("tok00002", alice.peer)]);
  assert.equal(count(env), 2);
  const body = { key: alice.player.publicKeyHex, sentAt: NOW, confirm: "delete my data" };
  const response = await env.call("/v1/delete", { body: { ...body, sig: reference.signBatch({ ...body, purpose: "delete" }, alice.player.privateKey) } });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  assert.equal(count(env), 0, "both the report Alice sent and the one about her are gone");
});
