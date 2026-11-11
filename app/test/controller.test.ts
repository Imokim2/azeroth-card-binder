// What the companion app does, without a window: key storage, settings, signing in, picking the game folder and syncing,
// against the real server, the real sync engine and the real add-on's saved file.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { discordIdentity } from "../../server/src/discord.ts";
import { CLIENT, NOW, setup } from "../../server/test/harness.ts";
import type { FetchLike } from "../src/client.ts";
import { Controller } from "../src/controller.ts";
import type { Deps, Status } from "../src/controller.ts";
import { encryptedFileStore, SecretStorageUnavailable } from "../src/secrets.ts";
import type { Crypt } from "../src/secrets.ts";
import { defaultSettings, loadSettings, saveSettings } from "../src/settings.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const luajit = process.env["LUAJIT"] || "luajit";
const lua = (script: string, ...args: string[]) => {
  const result = spawnSync(luajit, [script, ...args], { cwd: root, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${script} failed: ${result.error ?? result.stderr}`);
  return result.stdout;
};

// A stand-in for the system's key protection: reversible, and plainly not the text itself.
const fakeCrypt = (available = true): Crypt => ({
  available: () => available,
  encrypt: (text) => new TextEncoder().encode(text).map((byte) => byte ^ 0x5a),
  decrypt: (bytes) => { if (bytes[0] === 0xff) throw new Error("not ours"); return new TextDecoder().decode(bytes.map((byte) => byte ^ 0x5a)); },
});

const pretendDiscord = () => discordIdentity({
  clientId: "1", clientSecret: "s", redirectUri: "r",
  fetch: (async (url: string | URL | Request, init?: RequestInit) => {
    const address = String(url);
    if (address.endsWith("/oauth2/token")) return new URLSearchParams(String(init?.body)).get("code") === "goodcode-1234" ? Response.json({ access_token: "t", scope: "identify" }) : new Response("{}", { status: 400 });
    if (address.endsWith("/users/@me")) return Response.json({ id: "555555555555" });
    return new Response("{}");
  }) as typeof fetch,
});

async function app(options: { crypt?: Crypt; opener?: "approve" | "cancel" | "wrong" } = {}) {
  const env = setup();
  env.deps.identity = pretendDiscord();
  const dataFolder = await mkdtemp(join(tmpdir(), "warcards-data-"));
  const folder = await mkdtemp(join(tmpdir(), "warcards-game-"));
  const saved = join(folder, "Games", "Forever", "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  lua("tests/tools/write-saved.lua", saved, "0");
  const fetchLike: FetchLike = async (url, init) => env.api(new Request(url, init));
  const picks = { next: join(folder) as string | null, agree: true };
  const opened: string[] = [];
  const deps: Deps = {
    dataFolder, secrets: encryptedFileStore(join(dataFolder, "key.bin"), options.crypt ?? fakeCrypt()), server: "https://warcards.test",
    version: CLIENT, catalogVersion: "test", fetch: fetchLike, now: () => NOW, sleep: async () => {}, signInPort: 0,
    engineTimings: { quietMs: 40, everyMs: 3_600_000 },
    chooseFolder: async () => picks.next,
    confirm: async () => picks.agree,
    open: async (url) => {
      opened.push(url);
      const callback = new URL(url).searchParams.get("redirect_uri") as string;
      const state = new URL(url).searchParams.get("state") as string;
      const mode = options.opener ?? "approve";
      await fetch(mode === "cancel" ? `${callback}?error=access_denied&state=${state}` : `${callback}?code=${mode === "wrong" ? "wrongcode-123" : "goodcode-1234"}&state=${state}`);
    },
    commonFolders: [join(folder, "Nowhere"), folder],
  };
  const controller = new Controller(deps);
  const statuses: Status[] = [];
  controller.onStatus((status) => statuses.push(status));
  const waitFor = async (what: string, check: (status: Status) => boolean) => {
    for (let waited = 0; waited < 8000; waited += 50) {
      if (check(controller.status())) return controller.status();
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    assert.fail(`timed out waiting for ${what}: ${JSON.stringify(controller.status())}`);
  };
  return { env, controller, dataFolder, folder, saved, picks, opened, statuses, waitFor, cleanup: async () => { await controller.stop(); await rm(dataFolder, { recursive: true, force: true }); await rm(folder, { recursive: true, force: true }); } };
}

test("the key is stored encrypted, and only the same user's protection can read it back", async () => {
  const folder = await mkdtemp(join(tmpdir(), "warcards-key-"));
  try {
    const store = encryptedFileStore(join(folder, "key.bin"), fakeCrypt());
    assert.equal(await store.get(), null, "nothing stored yet");
    await store.set("abc123:def456-the-private-key");
    const onDisk = await readFile(join(folder, "key.bin"));
    assert.ok(!onDisk.includes("the-private-key"), "the secret is not in the file in plain text");
    assert.equal(await store.get(), "abc123:def456-the-private-key");
    // Protection missing: nothing is stored and a stored key is not handed out.
    const none = encryptedFileStore(join(folder, "key.bin"), fakeCrypt(false));
    await assert.rejects(none.set("x"), SecretStorageUnavailable);
    await assert.rejects(none.get(), SecretStorageUnavailable);
    // A file that this user cannot decrypt is refused, not guessed at.
    await writeFile(join(folder, "key.bin"), Uint8Array.from([0xff, 1, 2]));
    await assert.rejects(store.get(), SecretStorageUnavailable);
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});

test("settings survive a restart, and a missing, damaged or edited file can only give defaults or valid values", async () => {
  const folder = await mkdtemp(join(tmpdir(), "warcards-settings-"));
  const path = join(folder, "settings.json");
  try {
    assert.deepEqual(await loadSettings(path), defaultSettings);
    await saveSettings(path, { gameFolder: "C:\\Games\\Forever", visibility: "private", playerId: "01M73XS2TG9HCN3PYAR1C9D3DV", startAtLogin: true });
    assert.deepEqual(await loadSettings(path), { gameFolder: "C:\\Games\\Forever", visibility: "private", playerId: "01M73XS2TG9HCN3PYAR1C9D3DV", startAtLogin: true });
    await writeFile(path, "{ not json");
    assert.deepEqual(await loadSettings(path), defaultSettings);
    await writeFile(path, JSON.stringify({ gameFolder: 5, visibility: "everyone", playerId: "'; DROP TABLE", startAtLogin: "yes" }));
    assert.deepEqual(await loadSettings(path), defaultSettings);
    await writeFile(path, JSON.stringify([1, 2]));
    assert.deepEqual(await loadSettings(path), defaultSettings);
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});

test("a first run: choose the folder, sign in, and the saved data is synced without anyone asking", async () => {
  const a = await app();
  try {
    await a.controller.start();
    let status = a.controller.status();
    assert.deepEqual([status.signedIn, status.gameFolder, status.problem, status.accounts], [false, null, null, []]);
    // Syncing before anything is set up says what to do first.
    await a.controller.syncNow();
    assert.match(a.controller.status().message ?? "", /Sign in with Discord first/);

    await a.controller.chooseGameFolder();
    status = a.controller.status();
    assert.match(status.gameFolder ?? "", /Forever$/);
    assert.equal(status.signedIn, false);

    await a.controller.signIn("public");
    assert.equal(a.opened.length, 1);
    assert.match(a.opened[0] as string, /^https:\/\/discord\.com\/oauth2\/authorize\?/);
    assert.equal(a.controller.status().signedIn, true);
    status = await a.waitFor("the first sync", (s) => s.accounts.length === 1 && s.lastSyncAt !== null);
    assert.equal(status.accounts[0]?.account, "ACCOUNT1");
    assert.match(status.accounts[0]?.state ?? "", /Synced/);
    assert.equal(status.accounts[0]?.mode, "casual");
    assert.equal(status.standings, "fresh");
    assert.equal((a.env.raw.prepare("SELECT discord_id AS d FROM players").get() as { d: string }).d, "555555555555");
    assert.ok(a.statuses.length >= 3, "listeners were told as things changed");

  } finally {
    await a.cleanup();
  }
});

test("settings and the key are kept: a new controller starts already signed in and syncing", async () => {
  const a = await app();
  try {
    await a.controller.start();
    await a.controller.chooseGameFolder();
    await a.controller.signIn("private");
    await a.waitFor("the first sync", (s) => s.lastSyncAt !== null);
    await a.controller.stop();
    const key = await readFile(join(a.dataFolder, "key.bin"));
    // A second controller on the same data folder, as after restarting the app.
    const second = new Controller({
      dataFolder: a.dataFolder, secrets: encryptedFileStore(join(a.dataFolder, "key.bin"), fakeCrypt()), server: "https://warcards.test", version: CLIENT,
      catalogVersion: "test", fetch: async (url, init) => a.env.api(new Request(url, init)), now: () => NOW, sleep: async () => {},
      engineTimings: { quietMs: 40, everyMs: 3_600_000 }, chooseFolder: async () => null, confirm: async () => false, open: () => undefined,
    });
    await second.start();
    const status = second.status();
    assert.deepEqual([status.signedIn, status.visibility, status.problem], [true, "private", null]);
    assert.match(status.gameFolder ?? "", /Forever$/);
    assert.deepEqual(await readFile(join(a.dataFolder, "key.bin")), key, "the same key, not a new one");
    for (let waited = 0; waited < 8000 && second.status().lastSyncAt === null; waited += 50) await new Promise((resolve) => setTimeout(resolve, 50));
    assert.notEqual(second.status().lastSyncAt, null);
    await second.stop();
  } finally {
    await a.cleanup();
  }
});

test("signing out stops syncing and forgets the account but not the key; sign-in problems are explained", async () => {
  const cancelled = await app({ opener: "cancel" });
  try {
    await cancelled.controller.start();
    await cancelled.controller.signIn("public");
    assert.equal(cancelled.controller.status().message, "Sign-in was cancelled.");
    assert.equal(cancelled.controller.status().signedIn, false);
  } finally {
    await cancelled.cleanup();
  }
  const wrong = await app({ opener: "wrong" });
  try {
    await wrong.controller.start();
    await wrong.controller.signIn("public");
    assert.match(wrong.controller.status().message ?? "", /could not be verified/);
  } finally {
    await wrong.cleanup();
  }
  const a = await app();
  try {
    await a.controller.start();
    await a.controller.chooseGameFolder();
    await a.controller.signIn("public");
    await a.waitFor("the first sync", (s) => s.lastSyncAt !== null);
    await a.controller.signOut();
    const status = a.controller.status();
    assert.deepEqual([status.signedIn, status.accounts], [false, []]);
    assert.deepEqual(JSON.parse(await readFile(join(a.dataFolder, "settings.json"), "utf8")).playerId, null);
  } finally {
    await a.cleanup();
  }
});

test("a folder with no game in it is refused, the game is found in the usual places, and a key that cannot be stored is explained", async () => {
  const a = await app();
  try {
    await a.controller.start();
    const empty = await mkdtemp(join(tmpdir(), "warcards-empty-")); // a folder of our own with no game in it (the shared temp folder may hold other tests' games)
    a.picks.next = empty;
    await a.controller.chooseGameFolder();
    await rm(empty, { recursive: true, force: true });
    assert.match(a.controller.status().message ?? "", /No game folder found/);
    assert.equal(a.controller.status().gameFolder, null);
    a.picks.next = null; // the dialog was closed: nothing changes
    await a.controller.chooseGameFolder();
    assert.equal(a.controller.status().gameFolder, null);
    await a.controller.findGame();
    assert.match(a.controller.status().gameFolder ?? "", /Forever$/);
    assert.match(a.controller.status().message ?? "", /Found the game/);
  } finally {
    await a.cleanup();
  }
  const broken = await app({ crypt: fakeCrypt(false) });
  try {
    await broken.controller.start();
    assert.match(broken.controller.status().problem ?? "", /cannot be stored safely/);
    await broken.controller.signIn("public");
    assert.equal(broken.controller.status().signedIn, false);
    assert.equal(broken.opened.length, 0, "no sign-in is started without a safe place for the key");
  } finally {
    await broken.cleanup();
  }
});

test("a new binder in the game is noticed, and starting it on the server archives the old one and syncs the new", async () => {
  const a = await app();
  try {
    await a.controller.start();
    await a.controller.chooseGameFolder();
    await a.controller.signIn("public");
    await a.waitFor("the first binder to sync", (s) => s.lastSyncAt !== null && /Synced|Up to date/.test(s.accounts[0]?.state ?? ""));
    assert.equal(a.controller.status().needsNewBinder, false);
    const playerId = (a.env.raw.prepare("SELECT id FROM players").get() as { id: string }).id;

    // The player starts over in the game: the saved file is a different binder from its very first event.
    process.env["WARCARDS_VARIANT"] = "other";
    try { lua("tests/tools/write-saved.lua", a.saved, "0"); } finally { delete process.env["WARCARDS_VARIANT"]; }
    await a.controller.syncNow();
    const noticed = await a.waitFor("the new binder to be noticed", (s) => s.needsNewBinder);
    assert.match(noticed.accounts[0]?.state ?? "", /new binder/);
    assert.equal((a.env.raw.prepare("SELECT COUNT(*) AS n FROM batches WHERE player_id = ?").get(playerId) as { n: number }).n, 1, "nothing was uploaded on top of the old chain");

    // Not agreeing changes nothing.
    a.picks.agree = false;
    await a.controller.startNewBinder();
    assert.equal(a.controller.status().message, "Nothing was changed.");
    assert.equal(a.controller.status().needsNewBinder, true);

    // Agreeing archives the old binder and the new one is uploaded from its first event.
    a.picks.agree = true;
    await a.controller.startNewBinder();
    const done = await a.waitFor("the new binder to sync", (s) => !s.needsNewBinder && /Synced|Up to date/.test(s.accounts[0]?.state ?? ""));
    assert.equal(done.accounts.length, 1);
    assert.equal((a.env.raw.prepare("SELECT COUNT(*) AS n FROM batches WHERE player_id = ?").get(playerId) as { n: number }).n, 1);
    assert.equal((a.env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get() as { n: number }).n, 2, "the old binder is kept on record");
    assert.equal((a.env.raw.prepare("SELECT epoch FROM players WHERE id = ?").get(playerId) as { epoch: number }).epoch, 1);

    // Asking again the same day is refused politely.
    await a.controller.startNewBinder();
    assert.match(a.controller.status().message ?? "", /started a new binder recently/);
  } finally {
    await a.cleanup();
  }
});

test("deleting your data asks first, erases the server's record and leaves you signed out and able to start again", async () => {
  const a = await app();
  try {
    await a.controller.start();
    await a.controller.chooseGameFolder();
    await a.controller.signIn("public");
    await a.waitFor("the first sync", (s) => s.lastSyncAt !== null);
    assert.equal((a.env.raw.prepare("SELECT COUNT(*) AS n FROM players").get() as { n: number }).n, 1);

    a.picks.agree = false;
    await a.controller.deleteMyData();
    assert.equal(a.controller.status().message, "Nothing was changed.");
    assert.equal(a.controller.status().signedIn, true);
    assert.equal((a.env.raw.prepare("SELECT COUNT(*) AS n FROM players").get() as { n: number }).n, 1);

    a.picks.agree = true;
    await a.controller.deleteMyData();
    const status = a.controller.status();
    assert.deepEqual([status.signedIn, status.accounts], [false, []]);
    assert.match(status.message ?? "", /deleted from the server/);
    assert.equal((a.env.raw.prepare("SELECT COUNT(*) AS n FROM players").get() as { n: number }).n, 0);
    assert.equal((a.env.raw.prepare("SELECT COUNT(*) AS n FROM batches").get() as { n: number }).n, 0);
    assert.equal(JSON.parse(await readFile(join(a.dataFolder, "settings.json"), "utf8")).playerId, null);

    // Not signed in: nothing to delete, and it says so.
    await a.controller.deleteMyData();
    assert.match(a.controller.status().message ?? "", /not signed in/);
    // And signing in again starts from nothing.
    await a.controller.signIn("public");
    assert.equal(a.controller.status().signedIn, true);
  } finally {
    await a.cleanup();
  }
});
