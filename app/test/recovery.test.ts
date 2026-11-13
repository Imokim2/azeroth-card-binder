import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { CLIENT, NOW, catalog, setup } from "../../server/test/harness.ts";
import { exportAccount, registerKey, syncBinder } from "../src/client.ts";
import type { ClientOptions } from "../src/client.ts";
import { loadOrCreateIdentity } from "../src/identity.ts";
import { readBinder } from "../src/binderFile.ts";
import { parseSavedVariables } from "../src/luaTable.ts";
import { findRecovery, keepSavedBackup, luaLiteral, planRecovery, recoveryServer, restoreRecovery, savedBackups } from "../src/recovery.ts";
import { Controller } from "../src/controller.ts";
import { saveSettings } from "../src/settings.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const luajit = process.env["LUAJIT"] || "luajit";
const empty = () => ({ schema: 2, mode: "ranked", counts: {}, dust: 0, ledger: [], head: { seq: 0, hash: "0".repeat(32) },
  tape: { next: 1 }, pickupSounds: false, satchelButtonPosition: { x: 123, y: -45 }, wanted: { "npc:639": true } });
const saveText = (data: ReturnType<typeof empty>) => "AzerothCardBinderDB = " + luaLiteral(data) + "\n";

async function fixture() {
  const dir = await mkdtemp(join(tmpdir(), "warcards-recovery-"));
  const game = join(dir, "game"), path = join(game, "WTF", "Account", "TEST", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(path, ".."), { recursive: true });
  await mkdir(join(game, "Interface", "AddOns", "AzerothCardBinder", "Data"), { recursive: true });
  const played = spawnSync(luajit, ["tests/tools/write-saved.lua", path, "0"], { cwd: root, encoding: "utf8" });
  assert.equal(played.status, 0, played.stderr);
  const backup = await readFile(path, "utf8");
  const env = setup(); let key: string | null = null;
  const secrets = { get: async () => key, set: async (value: string) => { key = value; } };
  const identity = await loadOrCreateIdentity(secrets);
  const calls: string[] = [];
  const client: ClientOptions = { baseUrl: "https://recovery.test", identity, clientVersion: CLIENT, catalogVersion: catalog.catalogVersion,
    fetch: async (url, init) => { calls.push(new URL(url).pathname); return env.api(new Request(url, init)); }, now: () => NOW, sleep: async () => {} };
  const registered = await registerKey(client, "discord:alice", "public");
  assert.equal(registered.status, "registered");
  if (registered.status !== "registered") throw new Error("registration failed");
  assert.equal((await syncBinder(client, readBinder(backup), null)).status, "synced");
  const exported = await exportAccount(client);
  assert.equal(exported.status, "exported");
  if (exported.status !== "exported") throw new Error("export failed");
  const server = recoveryServer(exported.text); assert.ok(server);
  const current = saveText(empty());
  await writeFile(path, current); await writeFile(path + ".bak", backup);
  return { dir, game, path, backup, current, server, client, secrets, calls, playerId: registered.playerId,
    cleanup: () => rm(dir, { recursive: true, force: true }) };
}

test("a verified backup restores real Lua data while retaining settings and both original files", async () => {
  const f = await fixture();
  try {
    const plan = await findRecovery(f.path, f.server); assert.ok(plan);
    const copies = plan.copies;
    const backupFolder = join(f.dir, "retained");
    await restoreRecovery(plan, backupFolder, async () => true);
    assert.deepEqual(readBinder(await readFile(f.path, "utf8")).head, f.server.head);
    assert.equal(await readFile(f.path + ".bak", "utf8"), f.backup);
    assert.equal(await readFile(join(backupFolder, "AzerothCardBinder.lua"), "utf8"), f.current);
    assert.equal(await readFile(join(backupFolder, "AzerothCardBinder.lua.bak"), "utf8"), f.backup);
    const restored = parseSavedVariables(await readFile(f.path, "utf8")).AzerothCardBinderDB as Record<string, unknown>;
    assert.equal(restored.pickupSounds, false);
    assert.deepEqual(restored.satchelButtonPosition, { x: 123, y: -45 });
    assert.deepEqual(restored.wanted, { "npc:639": true });
    assert.equal(Object.values(readBinder(await readFile(f.path, "utf8")).snapshot.counts).reduce((a, b) => a + b, 0), copies);
    // Verify the repaired literal and checksum under the real addon code as well as the TypeScript reader.
    const code = `local A={}; for _,n in ipairs({"Catalog.lua","CatalogForever.lua","CatalogExtra.lua","CatalogNodes.lua","Lore.lua","DropRates.lua","Editions.lua","Achievements.lua","Hash.lua","Ledger.lua","Collection.lua","Packs.lua","Seasons.lua", "SavedData.lua"}) do assert(loadfile("AzerothCardBinder/"..n))("AzerothCardBinder",A) end; assert(loadfile(arg[1]))(); local s=A.cleanSavedData(AzerothCardBinderDB); local l=A.newLedger(s,function()return 1 end,function()return "A-B" end); assert(l:check())`;
    const checker = join(f.dir, "check.lua"); await writeFile(checker, code);
    const checked = spawnSync(luajit, [checker, f.path], { cwd: root, encoding: "utf8" });
    assert.equal(checked.status, 0, checked.stderr);
  } finally { await f.cleanup(); }
});

test("the companion's retained save repairs a backup overwritten by later game saves", async () => {
  const f = await fixture();
  try {
    const root = join(f.dir, "copies");
    await keepSavedBackup(root, "TEST", f.backup);
    const files = await savedBackups(root, "TEST");
    assert.equal(files.length, 1);
    assert.deepEqual(await savedBackups(root, "OTHER"), []);
    await writeFile(f.path + ".bak", f.current);
    assert.equal(await findRecovery(f.path, f.server), null);
    const plan = await findRecovery(f.path, f.server, files); assert.ok(plan);
    const retained = join(f.dir, "retained");
    await restoreRecovery(plan, retained, async () => true);
    assert.deepEqual(readBinder(await readFile(f.path, "utf8")).head, f.server.head);
    assert.equal(await readFile(f.path + ".bak", "utf8"), f.current);
    assert.equal(await readFile(join(retained, "AzerothCardBinder.lua.bak"), "utf8"), f.current);
    assert.equal(await readFile(join(retained, "verified-source.lua"), "utf8"), f.backup);
    assert.equal(await readFile(files[0]!, "utf8"), f.backup);
  } finally { await f.cleanup(); }
});

test("retained saves are bounded per account and never overwrite an existing head or unrelated files", async () => {
  const f = await fixture();
  try {
    const root = join(f.dir, "copies");
    await keepSavedBackup(root, "TEST", f.backup);
    const original = (await savedBackups(root, "TEST"))[0]!;
    const sentinel = join(dirname(original), "keep.txt"); await writeFile(sentinel, "keep");
    await keepSavedBackup(root, "TEST", f.backup + "\n-- later preferences");
    assert.equal(await readFile(original, "utf8"), f.backup);
    for (let seq = f.server.head.seq + 1; seq <= f.server.head.seq + 7; seq++) {
      const raw = parseSavedVariables(f.backup).AzerothCardBinderDB as Record<string, unknown>;
      raw.head = { seq, hash: "a".repeat(32) };
      await keepSavedBackup(root, "TEST", "AzerothCardBinderDB = " + luaLiteral(raw as never));
    }
    assert.equal((await savedBackups(root, "TEST")).length, 5);
    assert.equal(await readFile(sentinel, "utf8"), "keep");
  } finally { await f.cleanup(); }
});

test("repair refuses foreign, newer, incomplete or conflicting inventory and executable Lua", async () => {
  const f = await fixture();
  try {
    const changed = (edit: (data: Record<string, unknown>) => void) => {
      const data = parseSavedVariables(f.current).AzerothCardBinderDB as Record<string, unknown>;
      edit(data); return "AzerothCardBinderDB = " + luaLiteral(data as never);
    };
    for (const text of [changed(d => { d.head = { seq: f.server.head.seq + 1, hash: "a".repeat(32) }; }),
      changed(d => { d.head = { seq: f.server.head.seq, hash: "f".repeat(32) }; }),
      changed(d => { d.counts = { "npc:639": 999 }; }), changed(d => { d.dust = 99999; }),
      changed(d => { d.seasonClaims = { ["a".repeat(32)]: true }; }),
      changed(d => { d.seasonTitles = { "Season Seeker": true }; }),
      changed(d => { d.run = { key: "npc:589", n: 1, last: 1 }; }), "AzerothCardBinderDB = os.execute('bad')"]) {
      assert.equal(await planRecovery(f.path, text, f.backup, f.server), null);
    }
    const altered = parseSavedVariables(f.backup).AzerothCardBinderDB as Record<string, unknown>;
    altered.shiny = { "npc:639": true };
    assert.equal(await planRecovery(f.path, f.current, "AzerothCardBinderDB = " + luaLiteral(altered as never), f.server), null);
    assert.equal(await readFile(f.path, "utf8"), f.current);
  } finally { await f.cleanup(); }
});

test("an open game or a changed save prevents any backup replacement", async () => {
  const f = await fixture();
  try {
    const plan = await findRecovery(f.path, f.server); assert.ok(plan);
    await assert.rejects(restoreRecovery(plan, join(f.dir, "retained"), async () => false), /Close World/);
    await writeFile(f.path, f.current + "\n-- a later save");
    await assert.rejects(restoreRecovery(plan, join(f.dir, "retained"), async () => true), /changed/);
    assert.equal(await readFile(f.path + ".bak", "utf8"), f.backup);
    assert.equal(await readFile(f.path, "utf8"), f.current + "\n-- a later save");
  } finally { await f.cleanup(); }
});

test("the repair action asks before restoring, never resets, and a declined restore leaves both files alone", { timeout: 30_000 }, async () => {
  const f = await fixture(); let controller: Controller | undefined;
  try {
    const dataFolder = join(f.dir, "app"); await mkdir(dataFolder);
    await saveSettings(join(dataFolder, "settings.json"), { gameFolder: f.game, playerId: f.playerId, visibility: "public", startAtLogin: false });
    let prompts = 0, agree = false, gameOpen = true, notifications = 0;
    controller = new Controller({ dataFolder, secrets: f.secrets, server: f.client.baseUrl, version: CLIENT, catalogVersion: catalog.catalogVersion,
      fetch: f.client.fetch, now: f.client.now, sleep: f.client.sleep, chooseFolder: async () => null, open: () => {}, gameClosed: async () => !gameOpen,
      onSyncIssue: () => { notifications++; },
      confirm: async (message, action) => { prompts++; assert.match(message, /does not reset/); assert.equal(action, "Restore verified backup"); return agree; } });
    await controller.start(); await controller.syncNow(); await controller.syncNow();
    assert.equal(notifications, 1, "the repair prompt opens once, not on every pass");
    await controller.repairSync();
    assert.equal(prompts, 0, "an open game prevents the restore confirmation");
    assert.equal(await readFile(f.path, "utf8"), f.current);
    assert.match(controller.status().message ?? "", /Close World of Warcraft/);
    gameOpen = false;
    await controller.repairSync();
    assert.equal(prompts, 1);
    assert.equal(await readFile(f.path, "utf8"), f.current);
    assert.equal(await readFile(f.path + ".bak", "utf8"), f.backup);
    agree = true;
    await controller.repairSync();
    assert.equal(prompts, 2);
    assert.deepEqual(readBinder(await readFile(f.path, "utf8")).head, f.server.head);
    assert.equal(f.calls.includes("/v1/reset"), false);
    assert.equal(f.calls.includes("/v1/delete"), false);
    assert.equal(controller.status().repairing, false);
  } finally { await controller?.stop(); await f.cleanup(); }
});
