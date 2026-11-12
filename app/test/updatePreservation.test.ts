import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { installAddon, TAR } from "../src/updates.ts";

const zipSupported = /bsdtar/i.test(spawnSync(TAR, ["--version"], { encoding: "utf8" }).stdout ?? "");

test("addon replacement leaves every account's binder and backup save untouched", { skip: !zipSupported }, async () => {
  const root = await mkdtemp(join(tmpdir(), "warcards-preserve-update-"));
  try {
    const game = join(root, "game"), addon = join(game, "Interface", "AddOns", "AzerothCardBinder");
    const fresh = join(root, "incoming", "AzerothCardBinder");
    await mkdir(join(addon, "Data"), { recursive: true });
    await mkdir(join(fresh, "Data"), { recursive: true });
    await writeFile(join(addon, "AzerothCardBinder.toc"), "## Version: 0.6.0\n");
    await writeFile(join(addon, "Data", "Sync.lua"), "existing acknowledgements and ranked supply");
    await writeFile(join(fresh, "AzerothCardBinder.toc"), "## Version: 0.6.1\n");
    await writeFile(join(fresh, "Data", "Sync.lua"), "empty release placeholder");
    await writeFile(join(fresh, "Main.lua"), "new addon code");
    const protectedFiles = new Map<string, Buffer>();
    for (const account of ["ACCOUNT1", "ACCOUNT2"]) for (const suffix of ["", ".bak"]) {
      const path = join(game, "WTF", "Account", account, "SavedVariables", "AzerothCardBinder.lua" + suffix);
      const bytes = Buffer.from('AzerothCardBinderDB = { counts = { ["npc:639"] = 9 }, dust = 42, shiny = { ["npc:639"] = true }, packs = { DM = 2 }, titles = {}, achievements = {}, head = { seq = 200 } }\n-- ' + account + suffix);
      await mkdir(join(path, ".."), { recursive: true }); await writeFile(path, bytes); protectedFiles.set(path, bytes);
    }
    const zip = join(root, "addon.zip");
    const result = spawnSync(TAR, ["-a", "-cf", zip, "AzerothCardBinder"], { cwd: join(root, "incoming"), encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    const installed = await installAddon(zip, game, join(root, "backups"), "0.6.1");
    assert.ok(installed.backup);
    for (const [path, bytes] of protectedFiles) assert.deepEqual(await readFile(path), bytes, path);
    assert.equal(await readFile(join(addon, "Data", "Sync.lua"), "utf8"), "existing acknowledgements and ranked supply");
    await assert.rejects(installAddon(zip, game, join(root, "backups"), "9.0.0"), /not the version/);
    for (const [path, bytes] of protectedFiles) assert.deepEqual(await readFile(path), bytes, "a rejected update preserves " + path);
    // Force an error after the old code has been backed up, inside the copy phase.
    await writeFile(join(addon, "Blocked.lua"), "old file blocks a new directory");
    await mkdir(join(fresh, "Blocked.lua"), { recursive: true });
    await writeFile(join(fresh, "Blocked.lua", "Child.lua"), "new code");
    await writeFile(join(fresh, "AzerothCardBinder.toc"), "## Version: 0.6.2\n");
    assert.equal(spawnSync(TAR, ["-a", "-cf", zip, "AzerothCardBinder"], { cwd: join(root, "incoming") }).status, 0);
    await assert.rejects(installAddon(zip, game, join(root, "backups"), "0.6.2"));
    assert.match(await readFile(join(addon, "AzerothCardBinder.toc"), "utf8"), /Version: 0\.6\.1/);
    assert.equal(await readFile(join(addon, "Data", "Sync.lua"), "utf8"), "existing acknowledgements and ranked supply");
    for (const [path, bytes] of protectedFiles) assert.deepEqual(await readFile(path), bytes, "a rolled-back update preserves " + path);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("installer identity and app-data retention stay compatible with installed companions", async () => {
  const config = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
  assert.equal(config.build.appId, "app.worldofwarcards.companion");
  assert.equal(config.build.productName, "World of Warcards");
  assert.equal(config.build.nsis.deleteAppDataOnUninstall, false);
});
