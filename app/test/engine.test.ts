// The sync engine, with the real add-on, the real server and real files: one pass does everything, passes never
// overlap, a damaged file or an unregistered key costs only that account, and a changed saved file starts a pass.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { CLIENT, NOW, catalog, setup } from "../../server/test/harness.ts";
import { fetchTape, registerKey } from "../src/client.ts";
import type { ClientOptions, FetchLike } from "../src/client.ts";
import { Engine } from "../src/engine.ts";
import { describeInstall, writeFileAtomic } from "../src/files.ts";
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

const memoryStore = (): SecretStore => {
  let value: string | null = null;
  return { async get() { return value; }, async set(secret: string) { value = secret; } };
};

async function gameFolder(extraDrops = 0) {
  const folder = await mkdtemp(join(tmpdir(), "warcards-engine-"));
  const saved = join(folder, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  lua("tests/tools/write-saved.lua", saved, String(extraDrops));
  return { folder, saved, cleanup: () => rm(folder, { recursive: true, force: true }) };
}

async function world(options: { register?: boolean } = {}) {
  const env = setup();
  const identity = await loadOrCreateIdentity(memoryStore());
  const calls: string[] = [];
  const fetch: FetchLike = async (url, init) => {
    calls.push(`${init.method} ${new URL(url).pathname}`);
    return env.api(new Request(url, init));
  };
  let tick = NOW;
  const client: ClientOptions = {
    baseUrl: "https://warcards.test", fetch, identity, clientVersion: CLIENT, catalogVersion: catalog.catalogVersion,
    now: () => tick, sleep: async () => {},
  };
  let playerId: string | null = null;
  if (options.register !== false) {
    const registered = await registerKey(client, "discord:alice", "public");
    assert.equal(registered.status, "registered");
    if (registered.status === "registered") playerId = registered.playerId;
  }
  return { env, client, calls, playerId: () => playerId, advance: () => { tick += 1; return tick; } };
}

test("one pass: uploads, acknowledges into Sync.lua, writes the standings, and the add-on can use the file", async () => {
  const game = await gameFolder();
  try {
    const w = await world();
    const install = await describeInstall(game.folder);
    const engine = new Engine({ install, client: w.client, playerId: w.playerId });
    const report = await engine.syncOnce();
    assert.equal(report.accounts.length, 1);
    assert.equal(report.accounts[0]?.result.status, "synced");
    assert.equal(report.accounts[0]?.mode, "casual");
    assert.equal(report.tape, null, "Casual needs no tape");
    assert.equal(report.standings, "fresh");
    assert.equal(report.wroteSync, true);
    // The server stored the events; the add-on loads the file the engine wrote and drops them.
    const loaded = JSON.parse(lua("tests/tools/load-saved.lua", game.saved, install.syncPath)) as Record<string, unknown>;
    assert.equal(loaded["verified"], true, JSON.stringify(loaded));
    assert.equal(loaded["eventsAfter"], 0);
    assert.equal(loaded["syncedAt"], NOW);
    // A second pass has nothing to upload and the standings are kept (fetched less than five minutes ago).
    const again = await engine.syncOnce();
    assert.equal(again.accounts[0]?.result.status, "synced");
    assert.equal(again.standings, "kept");
    assert.equal(w.env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get()?.["n"], 1);
  } finally {
    await game.cleanup();
  }
});

test("Ranked: the pass brings the tape back from where the add-on got to, and the player's place with it", async () => {
  const game = await gameFolder();
  try {
    const w = await world();
    const install = await describeInstall(game.folder);
    // The add-on has a tape, switches to Ranked and rolls sixty attempts.
    const issued = await fetchTape(w.client);
    assert.equal(issued.status, "tape");
    if (issued.status !== "tape") return;
    await writeFileAtomic(install.syncPath, syncFileText({ syncedAt: NOW, acks: [], tape: { start: issued.start, entries: issued.entries } }));
    lua("tests/tools/write-saved.lua", game.saved, "60", install.syncPath);

    const engine = new Engine({ install, client: w.client, playerId: w.playerId });
    const report = await engine.syncOnce();
    assert.equal(report.accounts[0]?.result.status, "synced", JSON.stringify(report));
    assert.equal(report.accounts[0]?.mode, "ranked");
    assert.deepEqual(report.tape, { start: 61, count: 1_000 - 60 });
    const text = await readFile(install.syncPath, "utf8");
    assert.match(text, /start = 61,/);
    assert.match(text, /leaderboard = \{/);
    assert.match(text, /you = \{ rank = 1,/);
    assert.match(text, /\["alice-realmname"\] = true/); // the ranked character is marked verified
  } finally {
    await game.cleanup();
  }
});

test("Ranked tape is asked for only when the add-on is running low, and the ladder is refreshed only every half hour", async () => {
  const game = await gameFolder();
  try {
    const w = await world();
    const install = await describeInstall(game.folder);
    const issued = await fetchTape(w.client);
    if (issued.status !== "tape") throw new Error("no tape");
    await writeFileAtomic(install.syncPath, syncFileText({ syncedAt: NOW, acks: [], tape: { start: issued.start, entries: issued.entries } }));
    lua("tests/tools/write-saved.lua", game.saved, "60", install.syncPath);
    const engine = new Engine({ install, client: w.client, playerId: w.playerId });
    const tapeCalls = () => w.calls.filter((call) => call === "POST /v1/tape").length;
    const standingsCalls = () => w.calls.filter((call) => call === "GET /v1/leaderboard").length;
    const before = tapeCalls();
    await engine.syncOnce();
    assert.equal(tapeCalls() - before, 1, "the first pass asks, the app holds nothing yet");
    assert.equal(standingsCalls(), 1);
    // Plenty is left (940 of 1,000): the next passes ask for neither the tape nor the standings, and still report what is left.
    w.advance();
    const again = await engine.syncOnce();
    await engine.syncOnce();
    assert.equal(tapeCalls() - before, 1, "no new tape request while plenty is left");
    assert.equal(standingsCalls(), 1, "no new standings request within half an hour");
    assert.deepEqual(again.tape, { start: 61, count: 1_000 - 60 });
    assert.match(await readFile(install.syncPath, "utf8"), /start = 61,/, "Sync.lua still carries the tape");
    // The add-on uses most of it (800 attempts: 200 left, below the refill mark): now the tape is asked for again.
    lua("tests/tools/write-saved.lua", game.saved, "800", install.syncPath);
    await engine.syncOnce();
    assert.equal(tapeCalls() - before, 2, "asked again once it runs low");
  } finally {
    await game.cleanup();
  }
});

test("an unregistered key, a damaged file and a missing server each cost only what they must", async () => {
  const game = await gameFolder();
  try {
    const w = await world({ register: false });
    const install = await describeInstall(game.folder);
    // Not registered: told so, and Sync.lua is still written so the add-on is never left without a file.
    const engine = new Engine({ install, client: w.client, playerId: w.playerId });
    const first = await engine.syncOnce();
    assert.deepEqual(first.accounts[0]?.result, { status: "not-registered" });
    assert.equal(first.wroteSync, true);

    // A damaged saved file is reported for that account and nothing is thrown.
    await writeFile(game.saved, "AzerothCardBinderDB = { this is not lua");
    const second = await engine.syncOnce();
    assert.equal(second.accounts[0]?.result.status, "unreadable");
    assert.equal(second.wroteSync, true);

    // The server cannot be reached: the account is told to come back later, and the engine does not throw.
    const down: ClientOptions = { ...w.client, attempts: 1, fetch: async () => { throw new Error("offline"); } };
    const fresh = await gameFolder();
    try {
      const freshInstall = await describeInstall(fresh.folder);
      const offline = await new Engine({ install: freshInstall, client: down, playerId: () => null }).syncOnce();
      assert.equal(offline.accounts[0]?.result.status, "retry-later");
      assert.equal(offline.standings, "unavailable");
      assert.equal(offline.wroteSync, true);
    } finally {
      await fresh.cleanup();
    }
  } finally {
    await game.cleanup();
  }
});

test("passes never overlap: asking during a pass gets that pass", async () => {
  const game = await gameFolder();
  try {
    const w = await world();
    const install = await describeInstall(game.folder);
    const engine = new Engine({ install, client: w.client, playerId: w.playerId });
    const [a, b] = [engine.syncOnce(), engine.syncOnce()];
    assert.equal(a, b);
    await a;
    assert.equal(w.calls.filter((call) => call === "POST /v1/ledger").length, 1);
  } finally {
    await game.cleanup();
  }
});

test("start: a pass runs at once, again when the game rewrites its file, and stops when told", async () => {
  const game = await gameFolder();
  try {
    const w = await world();
    const install = await describeInstall(game.folder);
    const counting: ClientOptions = { ...w.client, now: () => w.advance() };
    const engine = new Engine({ install, client: counting, playerId: w.playerId, quietMs: 40, everyMs: 3_600_000 });
    const stop = engine.start();
    const waitFor = async (what: string, check: () => Promise<boolean>) => {
      for (let waited = 0; waited < 6000; waited += 50) {
        if (await check()) return;
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      assert.fail("timed out waiting for " + what);
    };
    const syncedAt = async () => /syncedAt = (\d+)/.exec(await readFile(install.syncPath, "utf8").catch(() => ""))?.[1];
    await waitFor("the first pass", async () => (await syncedAt()) !== undefined);
    const first = Number(await syncedAt());
    // The game rewrites its file: another pass follows without anyone asking.
    await writeFile(game.saved, await readFile(game.saved, "utf8"));
    await waitFor("the pass after a rewrite", async () => Number(await syncedAt()) > first);
    stop();
    await new Promise((resolve) => setTimeout(resolve, 200));
    const settled = Number(await syncedAt());
    await writeFile(game.saved, await readFile(game.saved, "utf8"));
    await new Promise((resolve) => setTimeout(resolve, 400));
    assert.equal(Number(await syncedAt()), settled, "no pass after stop");
  } finally {
    await game.cleanup();
  }
});

test("reports made in the game go to the server once, and the settled ones come back in Sync.lua for the add-on to forget", async () => {
  const folder = await mkdtemp(join(tmpdir(), "warcards-reports-"));
  const saved = join(folder, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  process.env["WARCARDS_REPORTS"] = "bob-realmname:trading:never gave the card,carl-realmname:cheating:";
  try { lua("tests/tools/write-saved.lua", saved, "0"); } finally { delete process.env["WARCARDS_REPORTS"]; }
  try {
    const w = await world();
    const install = await describeInstall(folder);
    const engine = new Engine({ install, client: w.client, playerId: w.playerId, standingsEveryMs: 0 });
    await engine.syncOnce();
    const rows = w.env.raw.prepare("SELECT token, target_name, reason, note FROM reports ORDER BY target_name").all() as { token: string; target_name: string; reason: string; note: string }[];
    assert.deepEqual(rows.map((row) => [row.target_name, row.reason, row.note]), [["bob-realmname", "trading", "never gave the card"], ["carl-realmname", "cheating", ""]]);
    assert.equal(w.calls.filter((call) => call === "POST /v1/report").length, 1);
    // The tokens the server settled are written for the add-on; a second pass does not send them again.
    const text = await readFile(install.syncPath, "utf8");
    for (const row of rows) assert.ok(text.includes(`["${row.token}"] = true,`), text);
    await engine.syncOnce();
    assert.equal(w.calls.filter((call) => call === "POST /v1/report").length, 1);
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});

test("the player's wanted cards go to the board once, again only when they change, and the board comes back in Sync.lua", async () => {
  const folder = await mkdtemp(join(tmpdir(), "warcards-wanted-"));
  const saved = join(folder, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  process.env["WARCARDS_WANTED"] = "npc:639,npc:589";
  try { lua("tests/tools/write-saved.lua", saved, "0"); } finally { delete process.env["WARCARDS_WANTED"]; }
  try {
    const w = await world();
    const install = await describeInstall(folder);
    const engine = new Engine({ install, client: w.client, playerId: w.playerId, standingsEveryMs: 0 });
    await engine.syncOnce();
    const board = (await (await w.env.call("/v1/wanted")).json()) as { players: { displayName: string; cards: string[] }[] };
    assert.deepEqual(board.players.map((entry) => [entry.displayName, entry.cards]), [["Alice-RealmName", ["npc:589", "npc:639"]]]);
    assert.equal(w.calls.filter((call) => call === "POST /v1/wanted").length, 1);
    // Nothing changed: it is not sent again. The board is on its way back into the file the add-on reads.
    await engine.syncOnce();
    assert.equal(w.calls.filter((call) => call === "POST /v1/wanted").length, 1);
    const text = await readFile(install.syncPath, "utf8");
    assert.ok(text.includes('{ name = "Alice-RealmName", characters = { "alice-realmname" }, cards = { "npc:589", "npc:639" } },'), text);
    // The player changes their list in the game: the new one goes up.
    process.env["WARCARDS_WANTED"] = "npc:573";
    try { lua("tests/tools/write-saved.lua", saved, "0"); } finally { delete process.env["WARCARDS_WANTED"]; }
    await engine.syncOnce();
    assert.equal(w.calls.filter((call) => call === "POST /v1/wanted").length, 2);
    const again = (await (await w.env.call("/v1/wanted")).json()) as { players: { cards: string[] }[] };
    assert.deepEqual(again.players[0]?.cards, ["npc:573"]);
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});
