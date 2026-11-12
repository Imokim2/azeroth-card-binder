// Installing updates: a manifest is believed only when it is signed with the trusted key, a download is kept only when it is
// exactly the file the manifest describes, and the add-on is checked before it replaces anything and put back if it fails.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { discordIdentity } from "../../server/src/discord.ts";
import { CLIENT, NOW, setup } from "../../server/test/harness.ts";
import type { FetchLike } from "../src/client.ts";
import { Controller } from "../src/controller.ts";
import type { Deps, Status } from "../src/controller.ts";
import { encryptedFileStore } from "../src/secrets.ts";
import type { Crypt } from "../src/secrets.ts";
import { TAR, downloadVerified, entriesAreSafe, installAddon, verifiedManifest } from "../src/updates.ts";
import type { Artifact } from "../src/updates.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const luajit = process.env["LUAJIT"] || "luajit";
// Reading and writing zip files with `tar` is what the app relies on (Windows 10 and later); a GNU tar cannot.
const tarZip = /bsdtar/i.test(spawnSync(TAR, ["--version"], { encoding: "utf8" }).stdout ?? "");

const sha = (bytes: Buffer) => createHash("sha256").update(bytes).digest("hex");
const keys = () => {
  const pair = generateKeyPairSync("ed25519");
  const publicKey = pair.publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("hex");
  return { publicKey, sign: (text: string) => sign(null, Buffer.from(text), pair.privateKey).toString("hex") };
};
const trusted = keys();
const stranger = keys();

const item = (bytes: Buffer, version: string, extra: Partial<Artifact> = {}): Artifact => ({
  version, url: "https://downloads.test/" + version, sha256: sha(bytes), size: bytes.length, notes: "", ...extra,
});
const manifestText = (app: Artifact, addon: Artifact) => JSON.stringify({ format: 1, issuedAt: NOW, app, addon });
const signedBy = (who: ReturnType<typeof keys>, text: string) => ({ manifest: text, signature: who.sign(text) });

// A zip of an add-on folder, built with the system's tar.
async function addonZip(folder: string, version: string, files: Record<string, string>, top = "AzerothCardBinder") {
  const source = await mkdtemp(join(tmpdir(), "warcards-zipsrc-"));
  for (const [name, text] of Object.entries({ "AzerothCardBinder.toc": `## Title: World of Warcards\n## Version: ${version}\nMain.lua\n`, ...files })) {
    await mkdir(join(source, top, name, ".."), { recursive: true });
    await writeFile(join(source, top, name), text);
  }
  const zip = join(folder, `addon-${version}.zip`);
  const made = spawnSync(TAR, ["-a", "-cf", zip, top], { cwd: source, encoding: "utf8" });
  await rm(source, { recursive: true, force: true });
  if (made.status !== 0) throw new Error(made.stderr);
  return zip;
}

async function gameWithAddon(version: string, files: Record<string, string>) {
  const game = await mkdtemp(join(tmpdir(), "warcards-gameinstall-"));
  const dir = join(game, "Interface", "AddOns", "AzerothCardBinder");
  await mkdir(join(dir, "Data"), { recursive: true });
  await writeFile(join(dir, "AzerothCardBinder.toc"), `## Version: ${version}\nOld.lua\n`);
  for (const [name, text] of Object.entries(files)) await writeFile(join(dir, ...name.split("/")), text);
  return { game, dir };
}

test("a manifest is believed only when it is signed with the trusted key and every field is as it should be", async () => {
  const addon = item(Buffer.from("zip"), "0.5.0");
  const app = item(Buffer.from("exe"), "0.3.0");
  const text = manifestText(app, addon);
  assert.deepEqual((await verifiedManifest(signedBy(trusted, text), trusted.publicKey))?.addon.version, "0.5.0");
  assert.equal(await verifiedManifest(signedBy(stranger, text), trusted.publicKey), null, "signed with another key");
  assert.equal(await verifiedManifest({ manifest: text + " ", signature: trusted.sign(text) }, trusted.publicKey), null, "changed after signing");
  assert.equal(await verifiedManifest(signedBy(trusted, text), null), null, "no key built in: nothing is trusted");
  assert.equal(await verifiedManifest(undefined, trusted.publicKey), null);
  const bad = (change: Partial<Artifact>) => verifiedManifest(signedBy(trusted, manifestText(app, { ...addon, ...change })), trusted.publicKey);
  assert.equal(await bad({ url: "http://downloads.test/a" }), null, "https only");
  assert.equal(await bad({ sha256: "abc" }), null);
  assert.equal(await bad({ version: "latest" }), null);
  assert.equal(await bad({ size: 0 }), null);
  assert.equal(await bad({ size: 10 * 1024 * 1024 * 1024 }), null, "too large");
  assert.equal(await verifiedManifest(signedBy(trusted, JSON.stringify({ format: 2, issuedAt: NOW, app, addon })), trusted.publicKey), null);
});

test("a download is kept only when it is the exact size and checksum the manifest names", async () => {
  const folder = await mkdtemp(join(tmpdir(), "warcards-dl-"));
  try {
    const bytes = Buffer.from("the real installer");
    const serve = (body: Buffer, ok = true) => async () => ({ ok, status: ok ? 200 : 404, arrayBuffer: async () => body.buffer.slice(body.byteOffset, body.byteOffset + body.length) as ArrayBuffer });
    const file = join(folder, "out.bin");
    await downloadVerified(serve(bytes), item(bytes, "0.3.0"), file);
    assert.deepEqual(await readFile(file), bytes);
    const other = join(folder, "other.bin");
    await assert.rejects(downloadVerified(serve(Buffer.from("tampered installer")), item(bytes, "0.3.0"), other), /size|checksum/);
    await assert.rejects(downloadVerified(serve(Buffer.from("the REAL installer")), item(bytes, "0.3.0"), other), /checksum/);
    await assert.rejects(downloadVerified(serve(bytes, false), item(bytes, "0.3.0"), other), /404/);
    assert.deepEqual((await readdir(folder)).sort(), ["out.bin"], "nothing from a failed download is left behind");
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});

test("only names inside AzerothCardBinder/ are accepted from an add-on file", () => {
  assert.equal(entriesAreSafe(["AzerothCardBinder/", "AzerothCardBinder/Main.lua", "AzerothCardBinder/Data/Sync.lua"]), true);
  assert.equal(entriesAreSafe([]), false);
  assert.equal(entriesAreSafe(["AzerothCardBinder/Main.lua", "Evil/Main.lua"]), false);
  assert.equal(entriesAreSafe(["AzerothCardBinder/../Evil.lua"]), false);
  assert.equal(entriesAreSafe(["/AzerothCardBinder/Main.lua"]), false);
  assert.equal(entriesAreSafe(["AzerothCardBinder\\..\\Evil.lua"]), false);
  assert.equal(entriesAreSafe(["AzerothCardBinder/C:/Windows/x.lua"]), false);
});

test("installing the add-on replaces its files, keeps Sync.lua, drops files the new version does not have, and saves the old copy", { skip: !tarZip }, async () => {
  const scratch = await mkdtemp(join(tmpdir(), "warcards-inst-"));
  const { game, dir } = await gameWithAddon("0.4.0", { "Old.lua": "old", "Stale.lua": "stale", "Data/Sync.lua": "MY TAPE" });
  try {
    const zip = await addonZip(scratch, "0.5.0", { "Main.lua": "new", "Data/Sync.lua": "BLANK" });
    const { backup } = await installAddon(zip, game, join(scratch, "backups"), "0.5.0");
    assert.equal(await readFile(join(dir, "Main.lua"), "utf8"), "new");
    assert.match(await readFile(join(dir, "AzerothCardBinder.toc"), "utf8"), /Version: 0\.5\.0/);
    assert.equal(await readFile(join(dir, "Data", "Sync.lua"), "utf8"), "MY TAPE", "the app's own file is never replaced");
    await assert.rejects(readFile(join(dir, "Stale.lua")), /ENOENT/);
    await assert.rejects(readFile(join(dir, "Old.lua")), /ENOENT/);
    assert.ok(backup && backup.includes("AzerothCardBinder-0.4.0-"), String(backup));
    assert.equal(await readFile(join(backup as string, "Stale.lua"), "utf8"), "stale", "the old copy is kept aside");
  } finally {
    await rm(scratch, { recursive: true, force: true });
    await rm(game, { recursive: true, force: true });
  }
});

test("an add-on file of the wrong version, or with paths outside its folder, changes nothing", { skip: !tarZip }, async () => {
  const scratch = await mkdtemp(join(tmpdir(), "warcards-inst-"));
  const { game, dir } = await gameWithAddon("0.4.0", { "Old.lua": "old" });
  try {
    const wrong = await addonZip(scratch, "0.4.9", { "Main.lua": "new" });
    await assert.rejects(installAddon(wrong, game, join(scratch, "backups"), "0.5.0"), /not the version/);
    const outside = await addonZip(scratch, "0.5.0", { "Main.lua": "new" }, "Elsewhere");
    await assert.rejects(installAddon(outside, game, join(scratch, "backups"), "0.5.0"), /paths it should not/);
    assert.equal(await readFile(join(dir, "Old.lua"), "utf8"), "old");
    assert.match(await readFile(join(dir, "AzerothCardBinder.toc"), "utf8"), /Version: 0\.4\.0/);
  } finally {
    await rm(scratch, { recursive: true, force: true });
    await rm(game, { recursive: true, force: true });
  }
});

test("a first install works when no add-on is there yet", { skip: !tarZip }, async () => {
  const scratch = await mkdtemp(join(tmpdir(), "warcards-inst-"));
  const game = await mkdtemp(join(tmpdir(), "warcards-gamenew-"));
  try {
    const zip = await addonZip(scratch, "0.5.0", { "Main.lua": "new", "Data/Sync.lua": "BLANK" });
    const { backup } = await installAddon(zip, game, join(scratch, "backups"), "0.5.0");
    assert.equal(backup, null);
    assert.equal(await readFile(join(game, "Interface", "AddOns", "AzerothCardBinder", "Data", "Sync.lua"), "utf8"), "BLANK");
  } finally {
    await rm(scratch, { recursive: true, force: true });
    await rm(game, { recursive: true, force: true });
  }
});

// ---- The controller, with the real server and a signed manifest ----

const fakeCrypt = (): Crypt => ({
  available: () => true,
  encrypt: (text) => new TextEncoder().encode(text).map((byte) => byte ^ 0x5a),
  decrypt: (bytes) => new TextDecoder().decode(bytes.map((byte) => byte ^ 0x5a)),
});

async function world(options: { key: string | null; tamper?: boolean; agree?: boolean }) {
  const scratch = await mkdtemp(join(tmpdir(), "warcards-ctl-"));
  const { game, dir } = await gameWithAddon("0.4.0", { "Old.lua": "old", "Data/Sync.lua": "x" });
  const saved = join(game, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  const written = spawnSync(luajit, ["tests/tools/write-saved.lua", saved, "0"], { cwd: root, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  if (written.status !== 0) throw new Error(written.stderr);
  const zip = tarZip ? await addonZip(scratch, "0.5.0", { "Main.lua": "new" }) : null;
  const zipBytes = zip ? await readFile(zip) : Buffer.from("no zip on this system");
  const exe = Buffer.from("pretend installer");
  const text = manifestText(item(exe, "9.0.0", { url: "https://downloads.test/setup.exe" }), item(zipBytes, "0.5.0", { url: "https://downloads.test/addon.zip" }));
  const env = setup();
  env.deps.identity = discordIdentity({
    clientId: "1", clientSecret: "s", redirectUri: "r",
    fetch: (async (url: string | URL | Request, init?: RequestInit) => {
      const address = String(url);
      if (address.endsWith("/oauth2/token")) return new URLSearchParams(String(init?.body)).get("code") === "goodcode-1234" ? Response.json({ access_token: "t", scope: "identify" }) : new Response("{}", { status: 400 });
      if (address.endsWith("/users/@me")) return Response.json({ id: "555555555555" });
      return new Response("{}");
    }) as typeof fetch,
  });
  env.deps.releases = { latestApp: "9.0.0", latestAddon: "0.5.0", minAddon: "0.0.0", signed: signedBy(trusted, text) };
  const dataFolder = await mkdtemp(join(tmpdir(), "warcards-data-"));
  const fetchLike: FetchLike = async (url, init) => env.api(new Request(url, init));
  const installers: string[] = [];
  const served: string[] = [];
  const deps: Deps = {
    dataFolder, secrets: encryptedFileStore(join(dataFolder, "key.bin"), fakeCrypt()), server: "https://warcards.test",
    version: CLIENT, catalogVersion: "test", fetch: fetchLike, now: () => NOW, sleep: async () => {}, signInPort: 0,
    engineTimings: { quietMs: 40, everyMs: 3_600_000 },
    chooseFolder: async () => game,
    confirm: async () => options.agree ?? true,
    open: async (url) => {
      const callback = new URL(url).searchParams.get("redirect_uri") as string;
      const state = new URL(url).searchParams.get("state") as string;
      await fetch(`${callback}?code=goodcode-1234&state=${state}`);
    },
    commonFolders: [game],
    releaseKey: options.key,
    download: async (url) => {
      served.push(url);
      const body = url.endsWith("addon.zip") ? zipBytes : exe;
      const bytes = options.tamper ? Buffer.concat([body, Buffer.from("!")]) : body;
      return { ok: true, status: 200, arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length) as ArrayBuffer };
    },
    runInstaller: (path) => { installers.push(path); },
  };
  const controller = new Controller(deps);
  await controller.start();
  await controller.chooseGameFolder();
  await controller.signIn("public");
  const waitFor = async (what: string, check: (status: Status) => boolean) => {
    for (let waited = 0; waited < 8000; waited += 50) {
      if (check(controller.status())) return controller.status();
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    return assert.fail(`timed out waiting for ${what}: ${JSON.stringify(controller.status())}`);
  };
  await waitFor("the first sync", (status) => status.lastSyncAt !== null);
  return {
    controller, dir, installers, served, waitFor, dataFolder,
    cleanup: async () => { await controller.stop(); for (const folder of [scratch, game, dataFolder]) await rm(folder, { recursive: true, force: true }); },
  };
}

test("with no trusted key built in, updates are announced but nothing can be installed", async () => {
  const w = await world({ key: null });
  try {
    await w.waitFor("the versions", (status) => status.updates?.addon.latest === "0.5.0");
    assert.deepEqual(w.controller.status().canUpdate, { addon: false, app: false });
    await w.controller.updateAddon();
    await w.controller.updateApp();
    assert.deepEqual(w.served, []);
    assert.deepEqual(w.installers, []);
  } finally {
    await w.cleanup();
  }
});

test("a manifest signed with another key offers nothing", async () => {
  const w = await world({ key: stranger.publicKey });
  try {
    await w.waitFor("the versions", (status) => status.updates?.addon.latest === "0.5.0");
    assert.deepEqual(w.controller.status().canUpdate, { addon: false, app: false });
    assert.equal(w.controller.status().newer, null);
  } finally {
    await w.cleanup();
  }
});

test("the add-on can be updated from the window: downloaded, checked, installed, and the old copy kept", { skip: !tarZip }, async () => {
  const w = await world({ key: trusted.publicKey });
  try {
    await w.waitFor("an update to offer", (status) => status.canUpdate.addon);
    assert.equal(w.controller.status().newer?.addon, "0.5.0");
    await w.controller.updateAddon();
    assert.match(w.controller.status().message ?? "", /Add-on 0\.5\.0 is installed\. Use \/reload/);
    assert.equal(w.controller.status().updating, null);
    assert.equal(await readFile(join(w.dir, "Main.lua"), "utf8"), "new");
    assert.equal(await readFile(join(w.dir, "Data", "Sync.lua"), "utf8").then((text) => text.includes("releases")), true, "the next pass rewrote Sync.lua, which is the app's");
    assert.equal((await readdir(join(w.dataFolder, "addon-backups"))).length, 1);
    await w.waitFor("the installed version to show", (status) => status.updates?.addon.installed === "0.5.0");
    assert.equal(w.controller.status().canUpdate.addon, false, "nothing newer is left to install");
    assert.deepEqual(await readdir(join(w.dataFolder, "updates")).catch(() => []), [], "the download is not kept");
  } finally {
    await w.cleanup();
  }
});

test("a tampered add-on download is refused and the add-on is left as it was", { skip: !tarZip }, async () => {
  const w = await world({ key: trusted.publicKey, tamper: true });
  try {
    await w.waitFor("an update to offer", (status) => status.canUpdate.addon);
    await w.controller.updateAddon();
    assert.match(w.controller.status().message ?? "", /could not be updated: the download is not the size/);
    assert.equal(await readFile(join(w.dir, "Old.lua"), "utf8"), "old");
    assert.equal(w.controller.status().updating, null);
  } finally {
    await w.cleanup();
  }
});

test("the companion updates itself only after the player agrees and the installer is exactly the one that was signed", async () => {
  const declined = await world({ key: trusted.publicKey, agree: false });
  try {
    await declined.waitFor("an update to offer", (status) => status.canUpdate.app);
    await declined.controller.updateApp();
    assert.deepEqual(declined.installers, []);
    assert.deepEqual(declined.served, [], "nothing is downloaded before the player says yes");
    assert.equal(declined.controller.status().message, "Nothing was changed.");
  } finally {
    await declined.cleanup();
  }
  const agreed = await world({ key: trusted.publicKey });
  try {
    await agreed.waitFor("an update to offer", (status) => status.canUpdate.app);
    await agreed.controller.updateApp();
    assert.equal(agreed.installers.length, 1);
    assert.match(agreed.installers[0] as string, /World-of-Warcards-Setup-9\.0\.0\.exe$/);
    assert.equal(await readFile(agreed.installers[0] as string, "utf8"), "pretend installer");
  } finally {
    await agreed.cleanup();
  }
  const tampered = await world({ key: trusted.publicKey, tamper: true });
  try {
    await tampered.waitFor("an update to offer", (status) => status.canUpdate.app);
    await tampered.controller.updateApp();
    assert.deepEqual(tampered.installers, [], "a download that does not match the signature is never run");
    assert.match(tampered.controller.status().message ?? "", /could not be updated/);
  } finally {
    await tampered.cleanup();
  }
});
