// Which versions are out of date: the server says what is newest, the add-on's folder and saved data say what is installed
// and what last ran, and a sync pass puts the answer in the status and in Sync.lua for the add-on to read.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { CLIENT, NOW, catalog, setup } from "../../server/test/harness.ts";
import { registerKey } from "../src/client.ts";
import type { ClientOptions, FetchLike } from "../src/client.ts";
import { Engine } from "../src/engine.ts";
import { describeInstall } from "../src/files.ts";
import { loadOrCreateIdentity } from "../src/identity.ts";
import type { SecretStore } from "../src/identity.ts";
import { compareVersions, readAddonVersion, updateReport, updateState } from "../src/versions.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const luajit = process.env["LUAJIT"] || "luajit";

const memoryStore = (): SecretStore => {
  let value: string | null = null;
  return { async get() { return value; }, async set(secret: string) { value = secret; } };
};

// A game folder with a saved file (written by the real add-on) that says which add-on version last wrote it, and an add-on
// folder whose .toc says which version is installed.
async function gameFolder(options: { installed: string | null; running: string | null }) {
  const folder = await mkdtemp(join(tmpdir(), "warcards-updates-"));
  const saved = join(folder, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  const result = spawnSync(luajit, ["tests/tools/write-saved.lua", saved, "0"], { cwd: root, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(result.stderr);
  if (options.running) {
    const text = await readFile(saved, "utf8");
    await writeFile(saved, text.replace("AzerothCardBinderDB = {", `AzerothCardBinderDB = {\n["addonVersion"] = "${options.running}",`));
  }
  const addon = join(folder, "Interface", "AddOns", "AzerothCardBinder");
  await mkdir(join(addon, "Data"), { recursive: true });
  if (options.installed) {
    await writeFile(join(addon, "AzerothCardBinder.toc"), `## Interface: 11500\n## Title: World of Warcards\n## Version: ${options.installed}\nSwaps.lua\n`);
  }
  return { folder, cleanup: () => rm(folder, { recursive: true, force: true }) };
}

async function world(options: { releasesDown?: boolean } = {}) {
  const env = setup();
  env.deps.releases = { latestApp: "9.9.9", latestAddon: "0.5.0", minAddon: "0.4.0" };
  const identity = await loadOrCreateIdentity(memoryStore());
  const fetch: FetchLike = async (url, init) => {
    if (options.releasesDown && new URL(url).pathname === "/v1/releases") return new Response("{}", { status: 500 });
    return env.api(new Request(url, init));
  };
  const client: ClientOptions = {
    baseUrl: "https://warcards.test", fetch, identity, clientVersion: CLIENT, catalogVersion: catalog.catalogVersion,
    now: () => NOW, sleep: async () => {},
  };
  const registered = await registerKey(client, "discord:alice", "public");
  assert.equal(registered.status, "registered");
  return { env, client, playerId: () => (registered.status === "registered" ? registered.playerId : null) };
}

test("versions compare as numbers, and the state says what is out of date", () => {
  assert.equal(compareVersions("0.4.0", "0.10.0"), -1);
  assert.equal(compareVersions("1.0.0", "0.99.99"), 1);
  assert.equal(compareVersions("0.4.0", "0.4.0"), 0);
  assert.equal(updateState("0.4.0", "0.4.0", "0.3.0"), "current");
  assert.equal(updateState("0.4.1", "0.4.0", "0.3.0"), "current", "newer than the newest is not out of date");
  assert.equal(updateState("0.3.5", "0.4.0", "0.3.0"), "update");
  assert.equal(updateState("0.2.9", "0.4.0", "0.3.0"), "required");
  assert.equal(updateState(null, "0.4.0", "0.3.0"), "unknown");
  assert.equal(updateState("0.4.0", null, null), "unknown");
});

test("the report says a reload is needed only when the folder holds a newer add-on than the game last ran", () => {
  const releases = { app: { latest: "0.2.0", min: "0.1.0" }, addon: { latest: "0.5.0", min: "0.4.0" } };
  assert.equal(updateReport("0.2.0", releases, "0.5.0", "0.4.0").addon.reloadNeeded, true);
  assert.equal(updateReport("0.2.0", releases, "0.5.0", "0.5.0").addon.reloadNeeded, false);
  assert.equal(updateReport("0.2.0", releases, "0.4.0", "0.5.0").addon.reloadNeeded, false);
  assert.equal(updateReport("0.2.0", releases, "0.5.0", null).addon.reloadNeeded, false, "nothing known about what ran");
  assert.equal(updateReport("0.2.0", undefined, "0.5.0", "0.5.0").addon.state, "unknown", "the server has not said");
});

test("the installed add-on version is read from its .toc, and a missing or odd file says null", async () => {
  const game = await gameFolder({ installed: "0.4.7", running: null });
  try {
    assert.equal(await readAddonVersion(game.folder), "0.4.7");
    assert.equal(await readAddonVersion(join(game.folder, "nowhere")), null);
    await writeFile(join(game.folder, "Interface", "AddOns", "AzerothCardBinder", "AzerothCardBinder.toc"), "## Version: not-a-version\n");
    assert.equal(await readAddonVersion(game.folder), null);
  } finally {
    await game.cleanup();
  }
});

test("a pass reports an add-on and an app that are out of date, and writes the versions into Sync.lua for the add-on", async () => {
  const game = await gameFolder({ installed: "0.4.1", running: "0.4.1" });
  try {
    const w = await world();
    const install = await describeInstall(game.folder);
    const report = await new Engine({ install, client: w.client, playerId: w.playerId }).syncOnce();
    assert.deepEqual(report.updates.addon, { installed: "0.4.1", running: "0.4.1", latest: "0.5.0", min: "0.4.0", state: "update", reloadNeeded: false });
    assert.equal(report.updates.app.state, "update");
    assert.equal(report.updates.app.latest, "9.9.9");
    const text = await readFile(install.syncPath, "utf8");
    assert.ok(text.includes('releases = { latestAddon = "0.5.0", minAddon = "0.4.0" },'), text);
    // The real add-on code reads it back.
    const path = install.syncPath.replace(/\\/g, "/");
    const script = 'local ACB = {}; assert(loadfile("' + path + '"))("AzerothCardBinder", ACB); print(ACB.sync.releases.latestAddon, ACB.sync.releases.minAddon)';
    const result = spawnSync(luajit, ["-e", script], { encoding: "utf8" });
    assert.equal(result.stdout.trim(), "0.5.0\t0.4.0", result.stderr);
  } finally {
    await game.cleanup();
  }
});

test("a pass tells the player to reload when the folder holds a newer add-on than the game last ran, and when it is too old", async () => {
  const reload = await gameFolder({ installed: "0.5.0", running: "0.4.2" });
  const old = await gameFolder({ installed: "0.3.0", running: "0.3.0" });
  try {
    const w = await world();
    const first = await new Engine({ install: await describeInstall(reload.folder), client: w.client, playerId: w.playerId }).syncOnce();
    assert.equal(first.updates.addon.reloadNeeded, true);
    assert.equal(first.updates.addon.state, "current");
    const second = await new Engine({ install: await describeInstall(old.folder), client: w.client, playerId: w.playerId }).syncOnce();
    assert.equal(second.updates.addon.state, "required");
  } finally {
    await reload.cleanup();
    await old.cleanup();
  }
});

test("when the server cannot say what is current, nothing is called out of date and the sync still works", async () => {
  const game = await gameFolder({ installed: "0.4.1", running: "0.4.1" });
  try {
    const w = await world({ releasesDown: true });
    const install = await describeInstall(game.folder);
    const report = await new Engine({ install, client: w.client, playerId: w.playerId }).syncOnce();
    assert.equal(report.accounts[0]?.result.status, "synced");
    assert.equal(report.updates.addon.state, "unknown");
    assert.equal(report.updates.addon.installed, "0.4.1");
    assert.ok(!(await readFile(install.syncPath, "utf8")).includes("releases"), "no versions are written when none are known");
  } finally {
    await game.cleanup();
  }
});

test("an add-on that is not in the game folder is reported as not found", async () => {
  const game = await gameFolder({ installed: null, running: "0.4.1" });
  try {
    const w = await world();
    const report = await new Engine({ install: await describeInstall(game.folder), client: w.client, playerId: w.playerId }).syncOnce();
    assert.equal(report.updates.addon.installed, null);
    assert.equal(report.updates.addon.state, "unknown");
  } finally {
    await game.cleanup();
  }
});
