// The whole loop, with the real pieces: the Lua add-on writes a saved-data file; the app reads it and uploads to the
// server (in-process, on SQLite); the app writes Sync.lua; the Lua add-on loads that file and prunes what the
// server holds. The saved file is read by the app's parser AND by the real Lua interpreter, and the two must agree.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { CLIENT, NOW, catalog, newPlayer, setup } from "../../server/test/harness.ts";
import { readBinder } from "../src/binderFile.ts";
import { fetchTape, registerKey, syncBinder } from "../src/client.ts";
import type { ClientOptions, FetchLike } from "../src/client.ts";
import { describeInstall, findGameFolders, readText, writeFileAtomic } from "../src/files.ts";
import { loadOrCreateIdentity } from "../src/identity.ts";
import type { SecretStore } from "../src/identity.ts";
import { syncFileText } from "../src/syncFile.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const luajit = process.env["LUAJIT"] || "luajit";

function lua(script: string, ...args: string[]): string {
  const result = spawnSync(luajit, [script, ...args], { cwd: root, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${script} failed: ${result.error ?? result.stderr}`);
  return result.stdout;
}

function memoryStore(): SecretStore & { value: string | null } {
  const store = { value: null as string | null, async get() { return store.value; }, async set(secret: string) { store.value = secret; } };
  return store;
}

// A "game folder" on disk with one WoW account that has played, and the saved file the add-on really wrote.
async function gameFolder(extraDrops = 0) {
  const folder = await mkdtemp(join(tmpdir(), "warcards-game-"));
  const saved = join(folder, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  const json = JSON.parse(lua("tests/tools/write-saved.lua", saved, String(extraDrops))) as Record<string, unknown>;
  return { folder, saved, json, cleanup: () => rm(folder, { recursive: true, force: true }) };
}

function connect(env: ReturnType<typeof setup>, identity: ClientOptions["identity"], overrides: Partial<ClientOptions> = {}) {
  const sleeps: number[] = [];
  const calls: { path: string; status: number }[] = [];
  const fetch: FetchLike = async (url, init) => {
    const response = await env.api(new Request(url, init));
    calls.push({ path: new URL(url).pathname, status: response.status });
    return response;
  };
  const options: ClientOptions = {
    baseUrl: "https://warcards.test", fetch, identity, clientVersion: CLIENT, catalogVersion: catalog.catalogVersion,
    now: () => NOW, sleep: async (ms) => { sleeps.push(ms); }, ...overrides,
  };
  return { options, sleeps, calls };
}

test("the app reads the add-on's file exactly as the Lua interpreter does", async () => {
  const game = await gameFolder();
  try {
    const binder = readBinder(await readText(game.saved));
    assert.deepEqual(binder.events, game.json["ledger"]);
    assert.deepEqual(binder.head, game.json["head"]);
    assert.deepEqual(binder.snapshot.counts, game.json["counts"]);
    assert.deepEqual(binder.snapshot.attempts, game.json["attempts"]);
    assert.equal(binder.snapshot.dust, game.json["dust"]);
    assert.equal(binder.schema, 2);
    assert.equal(binder.mode, "casual");
    assert.deepEqual(binder.character, { name: "Alice", realm: "RealmName" });
    assert.ok(binder.events.length > 8);
    // The title with accents and a dash was written as byte escapes and must come back as the same text.
    const raw = await readText(game.saved);
    assert.match(raw, /\\195\\156/);
    assert.ok(raw.includes('["title"] = '));
  } finally {
    await game.cleanup();
  }
});

test("a first-time player: key made once, registered, uploaded, acknowledged back into the add-on", async () => {
  const game = await gameFolder();
  try {
    const env = setup();
    const secrets = memoryStore();
    const identity = await loadOrCreateIdentity(secrets);
    assert.match(identity.publicKeyHex, /^[0-9a-f]{64}$/);
    // The same secret loads the same key; the key is made once.
    assert.equal((await loadOrCreateIdentity(secrets)).publicKeyHex, identity.publicKeyHex);
    const client = connect(env, identity);

    const registered = await registerKey(client.options, "discord:alice", "public");
    assert.equal(registered.status, "registered");

    const install = await describeInstall(game.folder);
    assert.deepEqual(install.savedFiles.map((file) => file.account), ["ACCOUNT1"]);
    const binder = readBinder(await readText(install.savedFiles[0]?.path ?? ""));
    const outcome = await syncBinder(client.options, binder, null);
    assert.equal(outcome.status, "synced");
    if (outcome.status !== "synced") return;
    assert.equal(outcome.uploaded, binder.events.length);
    assert.deepEqual(outcome.ack, { seq: binder.head.seq, hash: binder.head.hash });

    // The add-on's snapshot matched the replay. This scripted binder wins every single roll, which no honest player
    // does, so the luck check rightly holds it off the ladder: the only flag is that one.
    const flags = env.raw.prepare("SELECT kind FROM flags").all() as { kind: string }[];
    assert.deepEqual(flags.map((flag) => flag.kind), ["luck-hold"]);

    // The app writes Sync.lua and the real add-on code understands it: the stored events are dropped, the chain still verifies.
    await writeFileAtomic(install.syncPath, syncFileText({ syncedAt: NOW, acks: [outcome.ack as { seq: number; hash: string }] }));
    const loaded = JSON.parse(lua("tests/tools/load-saved.lua", game.saved, install.syncPath)) as Record<string, unknown>;
    assert.equal(loaded["verified"], true, JSON.stringify(loaded));
    assert.equal(loaded["eventsBefore"], binder.events.length);
    assert.equal(loaded["removed"], binder.events.length);
    assert.equal(loaded["eventsAfter"], 0);
    assert.equal(loaded["verifiedAfter"], true);
    assert.equal(loaded["headSeq"], binder.head.seq);
    assert.equal(loaded["syncedAt"], NOW);
    assert.equal(loaded["mode"], "casual");

    // Syncing again with nothing new sends nothing; syncing with no memory at all is harmless (a repeat, stored once).
    assert.deepEqual(await syncBinder(client.options, binder, outcome.ack), { status: "synced", ack: outcome.ack, uploaded: 0 });
    const forgetful = await syncBinder(client.options, binder, null);
    assert.equal(forgetful.status, "synced");
    assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 1);
  } finally {
    await game.cleanup();
  }
});

test("a long session goes up in several batches that continue each other", async () => {
  const game = await gameFolder(40);
  try {
    const env = setup();
    const identity = await loadOrCreateIdentity(memoryStore());
    const client = connect(env, identity, {});
    await registerKey(client.options, "discord:alice", "public");
    const binder = readBinder(await readText(game.saved));
    const small = { ...client.options, batchSize: 7 };
    const outcome = await syncBinder(small, binder, null);
    assert.equal(outcome.status, "synced");
    assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], Math.ceil(binder.events.length / 7));
    assert.equal(env.raw.prepare("SELECT head_seq FROM ledger_state").get()?.["head_seq"], binder.head.seq);
  } finally {
    await game.cleanup();
  }
});

test("when the server is down the app backs off and tries again; the file is the queue", async () => {
  const game = await gameFolder();
  try {
    const env = setup();
    const identity = await loadOrCreateIdentity(memoryStore());
    const live = connect(env, identity);
    await registerKey(live.options, "discord:alice", "public");
    const binder = readBinder(await readText(game.saved));

    const down = connect(env, identity, { fetch: async () => { throw new Error("connection refused"); } });
    const failed = await syncBinder(down.options, binder, null);
    assert.equal(failed.status, "retry-later");
    if (failed.status === "retry-later") assert.ok(failed.afterMs >= 30_000);
    assert.deepEqual(down.sleeps, [500, 1000, 2000]); // growing pauses, then it stops for now
    assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 0);

    // A busy server that says when to come back: the app waits at least that long, then succeeds.
    let busy = 2;
    const wrapped: FetchLike = async (url, init) => {
      if (busy > 0) {
        busy--;
        return { status: 503, headers: { get: (name) => (name === "retry-after" ? "7" : null) }, json: async () => ({ error: { code: "overloaded" } }) };
      }
      return live.options.fetch(url, init);
    };
    const slow = connect(env, identity, { fetch: wrapped });
    const recovered = await syncBinder(slow.options, binder, null);
    assert.equal(recovered.status, "synced");
    assert.deepEqual(slow.sleeps, [7000, 7000]);
    assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 1);
  } finally {
    await game.cleanup();
  }
});

test("a file that was edited is refused for good: nothing is stored and the app does not keep retrying", async () => {
  const game = await gameFolder();
  try {
    const env = setup();
    const identity = await loadOrCreateIdentity(memoryStore());
    const client = connect(env, identity);
    await registerKey(client.options, "discord:alice", "public");
    const text = await readText(game.saved);
    // Change the count in the recycle event (the one that gives 10 dust), as a player might edit it by hand.
    const edited = text.replace(/(\["count"\] = )1(,\s+\["dust"\] = 10,)/, "$19$2");
    assert.notEqual(edited, text);
    const outcome = await syncBinder(client.options, readBinder(edited), null);
    assert.equal(outcome.status, "rejected");
    if (outcome.status === "rejected") assert.equal(outcome.code, "bad_hash");
    assert.equal(client.calls.filter((call) => call.path === "/v1/ledger").length, 1); // not retried
    assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 0);
  } finally {
    await game.cleanup();
  }
});

test("a file with its early events already pruned continues from the server's record, or says the history is missing", async () => {
  const game = await gameFolder();
  try {
    const env = setup();
    const identity = await loadOrCreateIdentity(memoryStore());
    const client = connect(env, identity);
    await registerKey(client.options, "discord:alice", "public");
    const full = readBinder(await readText(game.saved));
    const cut = 6;
    // The server holds events up to `cut`; the file (pruned by an earlier ack) keeps only what follows.
    await syncBinder(client.options, { ...full, events: full.events.slice(0, cut) }, null);
    const pruned = { ...full, events: full.events.slice(cut) };
    const resumed = await syncBinder(client.options, pruned, null);
    assert.equal(resumed.status, "synced");
    assert.equal(env.raw.prepare("SELECT head_seq FROM ledger_state").get()?.["head_seq"], full.head.seq);

    // A different player whose server record is empty cannot upload a file that begins mid-history.
    const other = connect(setup(), await loadOrCreateIdentity(memoryStore()));
    await registerKey(other.options, "discord:bob", "public");
    const stuck = await syncBinder(other.options, pruned, null);
    assert.deepEqual(stuck, { status: "history-missing", haveFrom: 1, needFrom: cut + 1 });
  } finally {
    await game.cleanup();
  }
});

test("Sync.lua only ever contains numbers and hashes, and refuses anything else", () => {
  const ok = syncFileText({ syncedAt: 5, acks: [{ seq: 3, hash: "0123456789abcdef0123456789abcdef" }] });
  assert.match(ok, /syncedAt = 5,/);
  assert.match(ok, /\{ seq = 3, hash = "0123456789abcdef0123456789abcdef" \},/);
  assert.throws(() => syncFileText({ syncedAt: 5, acks: [{ seq: 1, hash: '"}; os.execute("x") --' }] }));
  assert.throws(() => syncFileText({ syncedAt: 5, acks: [{ seq: 1.5, hash: "0".repeat(32) }] }));
  assert.throws(() => syncFileText({ syncedAt: -1, acks: [] }));
  assert.throws(() => syncFileText({ syncedAt: 5, acks: [{ seq: 1, hash: "0".repeat(31) + "G" }] }));
});

test("the game folder is found even when it is one or two levels down, and accounts without the add-on are skipped", async () => {
  const base = await mkdtemp(join(tmpdir(), "warcards-find-"));
  try {
    await mkdir(join(base, "Games", "Forever", "WTF", "Account", "A1", "SavedVariables"), { recursive: true });
    await mkdir(join(base, "Games", "Forever", "WTF", "Account", "A2", "SavedVariables"), { recursive: true });
    await writeFile(join(base, "Games", "Forever", "WTF", "Account", "A1", "SavedVariables", "AzerothCardBinder.lua"), "");
    await mkdir(join(base, "Games", "Other", "Interface"), { recursive: true });
    const found = await findGameFolders(base);
    assert.deepEqual(found, [join(base, "Games", "Forever")]);
    const install = await describeInstall(found[0] ?? "");
    assert.deepEqual(install.savedFiles.map((file) => file.account), ["A1"]);
    assert.ok(install.syncPath.endsWith(join("Interface", "AddOns", "AzerothCardBinder", "Data", "Sync.lua")));
    assert.deepEqual(await findGameFolders(join(base, "nowhere")), []);
  } finally {
    await rm(base, { recursive: true, force: true });
  }
  void newPlayer;
});

test("Ranked, end to end: the server issues a tape, the real add-on rolls it, and the server accepts every drop", async () => {
  const game = await gameFolder();
  try {
    const env = setup();
    const identity = await loadOrCreateIdentity(memoryStore());
    const client = connect(env, identity);
    await registerKey(client.options, "discord:alice", "public");

    // The app fetches the tape and writes it into Data/Sync.lua, which the add-on loads at login.
    const issued = await fetchTape(client.options);
    assert.equal(issued.status, "tape");
    if (issued.status !== "tape") return;
    assert.equal(issued.start, 1);
    assert.equal(issued.entries.length, 10_000);
    const install = await describeInstall(game.folder);
    await writeFileAtomic(install.syncPath, syncFileText({ syncedAt: NOW, acks: [], tape: { start: issued.start, entries: issued.entries } }));

    // The add-on switches to Ranked and rolls sixty kills of a 10% card against the tape.
    const played = JSON.parse(lua("tests/tools/write-saved.lua", game.saved, "60", install.syncPath)) as { mode: string; tape: { next: number } };
    assert.equal(played.mode, "ranked");
    assert.equal(played.tape.next, 61);
    const binder = readBinder(await readText(game.saved));
    assert.equal(binder.tapeNext, 61);
    const drops = binder.events.filter((event) => event.kind === "drop");
    assert.ok(drops.length >= 6, "a 10% card with a stacking chance gives at least six drops in sixty attempts");
    assert.ok(drops.every((event) => event.tape >= 1 && event.tape <= 60));
    assert.deepEqual(binder.events.map((event) => event.tape).filter((tape) => tape > 0), drops.map((event) => event.tape).sort((a, b) => a - b));

    // The server recomputes every drop from its own secret and accepts them.
    const outcome = await syncBinder(client.options, binder, null);
    assert.equal(outcome.status, "synced", JSON.stringify(outcome));
    assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM drops").get()?.["n"], drops.length);
    assert.equal(env.raw.prepare("SELECT tape_next FROM ledger_state").get()?.["tape_next"], 61);
    assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM flags").get()?.["n"], 0); // real luck, real tape: nothing to flag

    // The player is on the public ladder with a real score.
    const board = (await (await env.call("/v1/leaderboard")).json()) as { entries: { displayName: string; scoreTenths: number }[] };
    assert.equal(board.entries[0]?.displayName, "Alice-RealmName");
    assert.ok((board.entries[0]?.scoreTenths ?? 0) > 0);

    // The next tape request starts at the position the add-on will use next.
    const next = await fetchTape(client.options);
    assert.equal(next.status === "tape" ? next.start : 0, 61);
  } finally {
    await game.cleanup();
  }
});
