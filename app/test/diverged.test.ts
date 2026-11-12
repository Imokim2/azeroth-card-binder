// A saved binder that does not continue the one the server holds is recognised, rather than silently treated as uploaded.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { readBinder } from "../src/binderFile.ts";
import { syncBinder } from "../src/client.ts";
import type { ClientOptions, FetchLike } from "../src/client.ts";
import { readText } from "../src/files.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const luajit = process.env["LUAJIT"] || "luajit";

async function binder() {
  const folder = await mkdtemp(join(tmpdir(), "warcards-div-"));
  const file = join(folder, "AzerothCardBinder.lua");
  const result = spawnSync(luajit, ["tests/tools/write-saved.lua", file, "0"], { cwd: root, encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr);
  const parsed = readBinder(await readText(file));
  await rm(folder, { recursive: true, force: true });
  return parsed;
}

const clientWith = (reply: (path: string) => { status: number; body: unknown }): ClientOptions => {
  const fetch: FetchLike = async (url) => {
    const { status, body } = reply(new URL(url).pathname);
    return { status, headers: { get: () => null }, json: async () => body };
  };
  return {
    baseUrl: "https://x.test", fetch, identity: { publicKeyHex: "0".repeat(64), sign: async () => "0".repeat(128) },
    clientVersion: "0.1.0", catalogVersion: "t", now: () => 1_700_000_000, sleep: async () => {}, attempts: 1,
  };
};
const replay = (ackSeq: number, ackHash: string) => ({ status: 409, body: { error: { code: "replay", detail: { ackSeq, ackHash } } } });

test("a server chain that is not ours means a different binder, in every way the server can say so", async () => {
  const mine = await binder();
  const last = mine.events[mine.events.length - 1]!;
  const other = "f".repeat(32);
  // The server holds events up to a point that is in our file, with a different hash.
  assert.deepEqual(await syncBinder(clientWith(() => replay(3, other)), mine, null), { status: "diverged", serverSeq: 3 });
  // The server is further along than our whole file.
  assert.deepEqual(await syncBinder(clientWith(() => replay(last.seq + 50, other)), mine, null), { status: "diverged", serverSeq: last.seq + 50 });
  // The same range stored with other contents.
  assert.deepEqual(await syncBinder(clientWith(() => ({ status: 409, body: { error: { code: "duplicate_batch", detail: { ackSeq: 9, ackHash: other } } } })), mine, null), { status: "diverged", serverSeq: 9 });
  // An empty-upload answer that does not match our chain.
  const probing = { ...mine, events: mine.events.slice(2) };
  assert.equal((await syncBinder(clientWith(() => ({ status: 200, body: { ackSeq: 3, ackHash: other } })), probing, null)).status, "diverged");
});

test("a server chain that is ours is not mistaken for a new binder", async () => {
  const mine = await binder();
  const event = mine.events[4]!;
  // The server already has events up to the fifth: that event is in our file with the same hash, so we carry on from it.
  let uploads = 0;
  const outcome = await syncBinder(clientWith((path) => {
    assert.equal(path, "/v1/ledger");
    uploads += 1;
    return uploads === 1 ? replay(event.seq, event.h) : { status: 200, body: { ackSeq: mine.head.seq, ackHash: mine.head.hash, accepted: mine.events.length - 5 } };
  }), mine, null);
  assert.equal(outcome.status, "synced");
});

test("empty or fully pruned saved history must still match a cached or cold-start server head", async () => {
  const mine = await binder();
  const ack = { seq: mine.head.seq, hash: mine.head.hash };
  const empty = { ...mine, events: [], head: { seq: 0, hash: "0".repeat(32) }, tapeNext: 1 };
  let calls = 0;
  const client = clientWith(() => { calls++; return { status: 200, body: { ackSeq: ack.seq, ackHash: ack.hash, accepted: 0 } }; });
  assert.deepEqual(await syncBinder(client, empty, ack), { status: "diverged", serverSeq: ack.seq });
  assert.equal(calls, 0, "a known mismatch needs no request");
  assert.deepEqual(await syncBinder(client, empty, null), { status: "diverged", serverSeq: ack.seq });
  assert.equal(calls, 1, "cold-start empty history is checked rather than assumed uploaded");
  const pruned = { ...mine, events: [] };
  assert.deepEqual(await syncBinder(client, pruned, ack), { status: "synced", ack, uploaded: 0 });
  assert.deepEqual(await syncBinder(client, { ...pruned, head: { ...pruned.head, hash: "f".repeat(32) } }, ack), { status: "diverged", serverSeq: ack.seq });
});

test("an empty new server acknowledgement is cached without repeated checks", async () => {
  const mine = await binder();
  const empty = { ...mine, events: [], head: { seq: 0, hash: "0".repeat(32) }, tapeNext: 1 };
  const ack = { seq: 0, hash: "0".repeat(32) };
  let calls = 0;
  const client = clientWith(() => { calls++; return { status: 200, body: { ackSeq: 0, ackHash: ack.hash, accepted: 0 } }; });
  assert.deepEqual(await syncBinder(client, empty, null), { status: "synced", ack, uploaded: 0 });
  assert.deepEqual(await syncBinder(client, empty, ack), { status: "synced", ack, uploaded: 0 });
  assert.equal(calls, 1);
});
