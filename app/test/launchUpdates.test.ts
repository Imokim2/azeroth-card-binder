import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { NOW, setup } from "../../server/test/harness.ts";
import { Controller } from "../src/controller.ts";

async function fixture(options: { folder?: boolean; signedIn?: boolean; offline?: boolean; badSignature?: boolean } = {}) {
  const root = await mkdtemp(join(tmpdir(), "warcards-launch-update-"));
  const game = join(root, "game"), data = join(root, "data");
  await mkdir(join(game, "WTF", "Account"), { recursive: true });
  await mkdir(join(game, "Interface", "AddOns", "AzerothCardBinder"), { recursive: true });
  await writeFile(join(game, "Interface", "AddOns", "AzerothCardBinder", "AzerothCardBinder.toc"), "## Version: 0.5.0\n");
  await mkdir(data, { recursive: true });
  await writeFile(join(data, "settings.json"), JSON.stringify({ gameFolder: options.folder ? game : null,
    visibility: "public", startAtLogin: false, playerId: options.signedIn ? "A".repeat(26) : null }));
  const pair = generateKeyPairSync("ed25519");
  const publicKey = pair.publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("hex");
  const bytes = Buffer.from("test release");
  const artifact = (version: string) => ({ version, url: "https://downloads.test/" + version,
    size: bytes.length, sha256: createHash("sha256").update(bytes).digest("hex"), notes: "A test update" });
  const manifest = JSON.stringify({ format: 1, issuedAt: NOW, app: artifact("2.0.0"), addon: artifact("0.6.0") });
  const env = setup();
  env.deps.releases = { latestApp: "2.0.0", latestAddon: "0.6.0", minAddon: "0.0.0", signed: {
    manifest, signature: options.badSignature ? "ab".repeat(64) : sign(null, Buffer.from(manifest), pair.privateKey).toString("hex"),
  } };
  const calls: string[] = [], downloads: string[] = [], installers: string[] = [];
  let secret: string | null = null, confirmations = 0;
  const controller = new Controller({ dataFolder: data, server: "https://warcards.test", version: "1.0.0", catalogVersion: "test",
    secrets: { get: async () => secret, set: async value => { secret = value; } }, now: () => NOW,
    releaseKey: publicKey, sleep: async () => {}, open: async () => {}, chooseFolder: async () => game,
    confirm: async () => { confirmations++; return false; },
    fetch: async (url, init) => {
      calls.push(init.method + " " + new URL(url).pathname);
      if (options.offline) throw new Error("offline");
      return env.api(new Request(url, init));
    },
    download: async url => { downloads.push(url); return { ok: true, status: 200, arrayBuffer: async () => new ArrayBuffer(0) }; },
    runInstaller: path => { installers.push(path); },
  });
  return { controller, calls, downloads, installers, confirmations: () => confirmations,
    cleanup: async () => { await controller.stop(); await rm(root, { recursive: true, force: true }); } };
}

test("launch discovers a trusted companion update before Discord sign-in or choosing a game folder", async () => {
  const f = await fixture();
  try {
    await f.controller.start();
    assert.deepEqual(f.calls, ["GET /v1/releases"]);
    assert.deepEqual(f.controller.status().canUpdate, { app: true, addon: false });
    assert.equal(f.controller.status().signedIn, false);
    assert.equal(f.controller.status().updates?.app.latest, "2.0.0");
    assert.deepEqual(f.downloads, [], "launch detection does not authorise installation");
    await f.controller.updateApp();
    assert.equal(f.confirmations(), 1);
    assert.deepEqual(f.downloads, [], "declining the restart keeps the current installation");
    assert.deepEqual(f.installers, []);
    await Promise.all([f.controller.updateApp(), f.controller.updateApp()]);
    assert.equal(f.confirmations(), 2, "repeated clicks open only one more confirmation");
    assert.equal(f.controller.status().updating, null);
  } finally { await f.cleanup(); }
});

test("a configured launch offers both signed updates, with no duplicate startup check", async () => {
  const f = await fixture({ folder: true, signedIn: true });
  try {
    await f.controller.start();
    for (let count = 0; count < 100 && f.controller.status().lastSyncAt === null; count++) await new Promise(resolve => setTimeout(resolve, 5));
    assert.notEqual(f.controller.status().lastSyncAt, null);
    assert.deepEqual(f.controller.status().canUpdate, { app: true, addon: true });
    assert.deepEqual(f.calls, ["GET /v1/releases"], "the sync engine reuses the launch check without refreshing standings");
    await f.controller.checkForUpdates(false);
    await f.controller.checkForUpdates(false);
    assert.deepEqual(f.calls, ["GET /v1/releases"], "opening/focusing the same window does not duplicate a recent check");
    await f.controller.checkForUpdates();
    assert.deepEqual(f.calls, ["GET /v1/releases", "GET /v1/releases"]);
  } finally { await f.cleanup(); }
});

test("a selected game folder can update the addon before Discord sign-in", async () => {
  const f = await fixture({ folder: true });
  try {
    await f.controller.start();
    assert.equal(f.controller.status().signedIn, false);
    assert.deepEqual(f.controller.status().canUpdate, { app: true, addon: true });
    assert.deepEqual(f.calls, ["GET /v1/releases"]);
  } finally { await f.cleanup(); }
});

test("untrusted release announcements never enable a startup installation", async () => {
  const f = await fixture({ folder: true, badSignature: true });
  try {
    await f.controller.start();
    assert.deepEqual(f.controller.status().canUpdate, { app: false, addon: false });
    await f.controller.updateAddon(); await f.controller.updateApp();
    assert.deepEqual(f.downloads, []);
  } finally { await f.cleanup(); }
});

test("an offline launch finishes setup and explains a failed check without polling or starting downloads", async () => {
  const f = await fixture({ offline: true });
  try {
    await f.controller.start();
    assert.equal(f.controller.status().checkingUpdates, false);
    assert.match(f.controller.status().updateCheckMessage ?? "", /Could not check/);
    assert.equal(f.controller.status().problem, null);
    assert.deepEqual(f.calls, ["GET /v1/releases"]);
    assert.deepEqual(f.downloads, []);
  } finally { await f.cleanup(); }
});
