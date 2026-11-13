import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { CLIENT, NOW, catalog, setup } from "../../server/test/harness.ts";
import { fetchTape, registerKey } from "../src/client.ts";
import type { ClientOptions } from "../src/client.ts";
import { Engine } from "../src/engine.ts";
import type { PassReport } from "../src/engine.ts";
import { describeInstall, writeFileAtomic } from "../src/files.ts";
import { loadOrCreateIdentity } from "../src/identity.ts";
import { syncFileText } from "../src/syncFile.ts";
import { SqlSeasons } from "../../server/src/seasons.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const flush = () => new Promise<void>((resolve) => setImmediate(resolve));
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}
function observe() {
  const reports: PassReport[] = [], waits = new Map<number, ReturnType<typeof deferred<PassReport>>>();
  return {
    reports,
    onReport(report: PassReport) { reports.push(report); waits.get(reports.length)?.resolve(report); },
    wait(count: number) {
      if (reports[count - 1]) return Promise.resolve(reports[count - 1]!);
      const pending = deferred<PassReport>(); waits.set(count, pending); return pending.promise;
    },
  };
}
async function fixture() {
  const folder = await mkdtemp(join(tmpdir(), "warcards-idle-sync-"));
  const saved = join(folder, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  const write = (extra = 0, sync?: string) => {
    const args = ["tests/tools/write-saved.lua", saved, String(extra), ...(sync ? [sync] : [])];
    const result = spawnSync(process.env["LUAJIT"] || "luajit", args, { cwd: root, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
  };
  write();
  const env = setup();
  let key: string | null = null, stamp = NOW;
  const identity = await loadOrCreateIdentity({ async get() { return key; }, async set(value) { key = value; } });
  const calls: string[] = [];
  const client: ClientOptions = {
    baseUrl: "https://warcards.test", identity, clientVersion: CLIENT, catalogVersion: catalog.catalogVersion,
    now: () => stamp, sleep: async () => {}, attempts: 1,
    fetch: async (url, init) => { calls.push(`${init.method} ${new URL(url).pathname}`); return env.api(new Request(url, init)); },
  };
  const registered = await registerKey(client, "discord:idle-test", "public");
  if (registered.status !== "registered") throw new Error("fixture registration failed");
  return { folder, saved, env, client, calls, write, install: await describeInstall(folder),
    playerId: () => registered.playerId, advance(seconds: number) { stamp += seconds; },
    cleanup: () => rm(folder, { recursive: true, force: true }) };
}

test("seasonal data is paired to a synced binder and cached between saves without idle requests", { timeout: 30_000 }, async () => {
  const f = await fixture();
  try {
    const seasons = new SqlSeasons(f.env.db, catalog);
    f.env.deps.seasons = seasons;
    await seasons.schedule({ id: "first-hunt", title: "First Hunt", startsAt: NOW + 60, endsAt: NOW + 600,
      selection: { mode: "manual", cards: ["npc:589"] } }, NOW);
    const nonce = "b".repeat(32);
    const source = await readFile(f.saved, "utf8");
    await writeFile(f.saved, source.replace("AzerothCardBinderDB = {", 'AzerothCardBinderDB = { ["modeSetupID"] = "' + nonce + '",'));
    const engine = new Engine({ install: f.install, client: f.client, playerId: f.playerId });
    assert.equal((await engine.syncOnce({ saved: true })).wroteSync, true);
    const sync = await readFile(f.install.syncPath, "utf8");
    assert.ok(sync.includes("first-hunt")); assert.ok(sync.includes(nonce));
    assert.ok(f.calls.includes("POST /v1/seasons"));
    const count = f.calls.length;
    await engine.syncOnce();
    assert.equal(f.calls.length, count, "cached seasonal data adds no polling or idle requests");
  } finally { await f.cleanup(); }
});

test("a blocked sync file repairs itself after folder access returns without extra network polling", { timeout: 30_000 }, async (t) => {
  const f = await fixture(), observed = observe();
  let stop: (() => Promise<void>) | undefined;
  try {
    await mkdir(f.install.syncPath, { recursive: true }); // an isolated test directory blocks the file replacement
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const engine = new Engine({ install: f.install, client: f.client, playerId: f.playerId, onReport: observed.onReport });
    stop = engine.start();
    assert.equal((await observed.wait(1)).wroteSync, false); await flush();
    const calls = f.calls.length;
    assert.ok(resolve(f.install.syncPath).startsWith(resolve(f.folder) + sep), "only remove the obstruction inside this temporary fixture");
    await rm(f.install.syncPath, { recursive: true });
    t.mock.timers.tick(60_000);
    assert.equal((await observed.wait(2)).wroteSync, true); await flush();
    assert.match(await readFile(f.install.syncPath, "utf8"), /ACB.sync =/);
    assert.equal(f.calls.length, calls, "cached sync state repairs the local file without another network request");
    t.mock.timers.tick(3_600_000); await flush();
    assert.equal(observed.reports.length, 2, "successful repair returns to idle");
  } finally { await stop?.(); t.mock.timers.reset(); await f.cleanup(); }
});

test("a day idle makes no requests; a saved-file rewrite still syncs without manual input", { timeout: 10_000 }, async (t) => {
  const f = await fixture(), observed = observe();
  let stop: (() => Promise<void>) | undefined;
  try {
    t.mock.timers.enable({ apis: ["setInterval"] });
    const engine = new Engine({ install: f.install, client: f.client, playerId: f.playerId, quietMs: 20, onReport: observed.onReport });
    stop = engine.start();
    await observed.wait(1); await flush();
    const firstCalls = f.calls.length;
    f.advance(86_400);
    t.mock.timers.tick(86_400_000);
    await flush(); await flush();
    assert.equal(f.calls.length, firstCalls, "no polling requests while nothing was saved");
    assert.equal(observed.reports.length, 1, "idle time does not run another sync pass");
    await writeFile(f.saved, await readFile(f.saved, "utf8"));
    const saved = await observed.wait(2);
    assert.equal(saved.accounts[0]?.result.status, "synced");
    assert.equal(saved.standings, "fresh", "community data refreshes when a real save wakes the app");
    assert.equal(saved.wroteSync, true);
  } finally { await stop?.(); t.mock.timers.reset(); await f.cleanup(); }
});

test("a save arriving during an upload is queued and reaches the server without a polling timer", { timeout: 30_000 }, async () => {
  const f = await fixture(), observed = observe(), entered = deferred<void>(), release = deferred<void>();
  let held = false, stop: (() => Promise<void>) | undefined;
  try {
    const client: ClientOptions = { ...f.client, fetch: async (url, init) => {
      const response = await f.client.fetch(url, init);
      if (new URL(url).pathname === "/v1/ledger" && !held) { held = true; entered.resolve(); await release.promise; }
      return response;
    } };
    const engine = new Engine({ install: f.install, client, playerId: f.playerId, quietMs: 20, onReport: observed.onReport });
    stop = engine.start();
    await entered.promise;
    f.write(2);
    await new Promise((resolve) => setTimeout(resolve, 100));
    release.resolve();
    const second = await observed.wait(2);
    assert.equal(second.accounts[0]?.result.status, "synced");
    assert.equal(f.env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 2);
    assert.equal(f.calls.filter((call) => call === "POST /v1/ledger").length, 2);
  } finally { release.resolve(); await stop?.(); await f.cleanup(); }
});

test("Ranked data retries without another save, backs off after failures and stops after recovery", { timeout: 30_000 }, async (t) => {
  const f = await fixture(), observed = observe();
  let stop: (() => Promise<void>) | undefined;
  try {
    const issued = await fetchTape(f.client);
    if (issued.status !== "tape") throw new Error("fixture has no tape");
    await writeFileAtomic(f.install.syncPath, syncFileText({ syncedAt: NOW, acks: [], tape: { start: issued.start, entries: issued.entries } }));
    f.write(60, f.install.syncPath);
    let failures = 2;
    const client: ClientOptions = { ...f.client, fetch: async (url, init) => {
      if (new URL(url).pathname === "/v1/tape" && failures-- > 0) throw new Error("offline");
      return f.client.fetch(url, init);
    } };
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const engine = new Engine({ install: f.install, client, playerId: f.playerId, onReport: observed.onReport });
    stop = engine.start();
    const first = await observed.wait(1); await flush();
    assert.ok(first.retryAfterMs! >= 30_000);
    t.mock.timers.tick(59_999); await flush();
    assert.equal(observed.reports.length, 1);
    t.mock.timers.tick(1);
    await observed.wait(2); await flush();
    t.mock.timers.tick(119_999); await flush();
    assert.equal(observed.reports.length, 2, "second retry backs off to two minutes");
    t.mock.timers.tick(1);
    const recovered = await observed.wait(3); await flush();
    assert.ok(recovered.tape && "count" in recovered.tape && recovered.tape.count > 0);
    const count = f.calls.length;
    t.mock.timers.tick(3_600_000); await flush();
    assert.equal(observed.reports.length, 3);
    assert.equal(f.calls.length, count, "successful recovery returns to idle");
  } finally { await stop?.(); t.mock.timers.reset(); await f.cleanup(); }
});

test("stopping waits for the current upload and prevents queued saves from starting another pass", { timeout: 10_000 }, async () => {
  const f = await fixture(), entered = deferred<void>(), release = deferred<void>();
  let stop: (() => Promise<void>) | undefined;
  try {
    const client: ClientOptions = { ...f.client, fetch: async (url, init) => {
      const response = await f.client.fetch(url, init);
      if (new URL(url).pathname === "/v1/ledger") { entered.resolve(); await release.promise; }
      return response;
    } };
    const engine = new Engine({ install: f.install, client, playerId: f.playerId, quietMs: 20 });
    stop = engine.start();
    await entered.promise;
    f.write(2);
    await new Promise((resolve) => setTimeout(resolve, 100));
    let stopped = false;
    const finished = stop().then(() => { stopped = true; });
    await flush();
    assert.equal(stopped, false, "the active upload has not finished yet");
    release.resolve();
    await finished;
    assert.equal(stopped, true);
    assert.match(await readFile(f.install.syncPath, "utf8"), /ACB\.sync =/);
    assert.equal(f.calls.filter((call) => call === "POST /v1/ledger").length, 1);
    await flush();
    assert.equal(f.calls.filter((call) => call === "POST /v1/ledger").length, 1);
  } finally { release.resolve(); await stop?.(); await f.cleanup(); }
});

test("saved-file passes keep update checks for six hours while manual restart can check immediately", { timeout: 10_000 }, async () => {
  const f = await fixture();
  try {
    const options = { install: f.install, client: f.client, playerId: f.playerId };
    const engine = new Engine(options);
    const releases = () => f.calls.filter((call) => call === "GET /v1/releases").length;
    const boards = () => f.calls.filter((call) => call === "GET /v1/leaderboard").length;
    await engine.syncOnce();
    assert.equal(releases(), 1);
    assert.equal(boards(), 1);
    f.advance(3600);
    await engine.syncOnce();
    assert.equal(releases(), 1);
    assert.equal(boards(), 1, "elapsed time alone cannot refresh standings");
    f.advance(5 * 3600);
    await engine.syncOnce();
    assert.equal(releases(), 2);
    const restarted = await new Engine(options).syncOnce();
    assert.equal(releases(), 3, "the controller's manual Sync restarts the engine and checks immediately");
    assert.equal(restarted.standings, "kept");
    assert.equal(boards(), 1, "restarting restores the last board locally");
    await engine.syncOnce({ saved: true });
    assert.equal(boards(), 2, "a game save is what refreshes the board");
  } finally { await f.cleanup(); }
});
