// "Download my data" in the companion window: the controller asks the server for the player's copy (signed with their key), hands
// it to a save dialog, says where it went, and never saves when the player cancels or the server refuses.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
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

const root = fileURLToPath(new URL("../../", import.meta.url));
const luajit = process.env["LUAJIT"] || "luajit";
const fakeCrypt = (): Crypt => ({
  available: () => true,
  encrypt: (text) => new TextEncoder().encode(text).map((byte) => byte ^ 0x5a),
  decrypt: (bytes) => new TextDecoder().decode(bytes.map((byte) => byte ^ 0x5a)),
});

async function world(options: { save?: "ok" | "cancel"; withSave?: boolean } = {}) {
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
  const game = await mkdtemp(join(tmpdir(), "warcards-export-game-"));
  const saved = join(game, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  const written = spawnSync(luajit, ["tests/tools/write-saved.lua", saved, "0"], { cwd: root, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
  if (written.status !== 0) throw new Error(written.stderr);
  const dataFolder = await mkdtemp(join(tmpdir(), "warcards-export-data-"));
  const fetchLike: FetchLike = async (url, init) => env.api(new Request(url, init));
  const saves: { name: string; text: string }[] = [];
  const deps: Deps = {
    dataFolder, secrets: encryptedFileStore(join(dataFolder, "key.bin"), fakeCrypt()), server: "https://warcards.test",
    version: CLIENT, catalogVersion: "test", fetch: fetchLike, now: () => NOW, sleep: async () => {}, signInPort: 0,
    engineTimings: { quietMs: 40, everyMs: 3_600_000 },
    chooseFolder: async () => game, confirm: async () => true, commonFolders: [game],
    open: async (url) => {
      const callback = new URL(url).searchParams.get("redirect_uri") as string;
      const state = new URL(url).searchParams.get("state") as string;
      await fetch(`${callback}?code=goodcode-1234&state=${state}`);
    },
    ...(options.withSave === false ? {} : {
      saveFile: async (name: string, text: string) => {
        saves.push({ name, text });
        return options.save === "cancel" ? null : join(game, name);
      },
    }),
  };
  const controller = new Controller(deps);
  await controller.start();
  await controller.chooseGameFolder();
  await controller.signIn("public");
  for (let waited = 0; waited < 8000 && controller.status().lastSyncAt === null; waited += 50) await new Promise((resolve) => setTimeout(resolve, 50));
  return { controller, env, saves, status: (): Status => controller.status(), cleanup: async () => { await controller.stop(); for (const folder of [game, dataFolder]) await rm(folder, { recursive: true, force: true }); } };
}

test("the player's copy is fetched with their key, offered to the save dialog and reported", async () => {
  const w = await world();
  try {
    await w.controller.exportMyData();
    assert.equal(w.saves.length, 1);
    assert.equal(w.saves[0]?.name, "worldofwarcards-my-data.json");
    const data = JSON.parse(w.saves[0]?.text ?? "{}") as { format: number; account: { discordId: string }; binders: { events: unknown[] }[] };
    assert.equal(data.format, 1);
    assert.equal(data.account.discordId, "555555555555");
    assert.ok((data.binders[0]?.events.length ?? 0) > 0, "the uploaded events are in it");
    assert.match(w.status().message ?? "", /Your data was saved to .*worldofwarcards-my-data\.json\. It holds personal information/);
    assert.equal(w.status().busy, false);
  } finally {
    await w.cleanup();
  }
});

test("cancelling the dialog saves nothing and says so; with no save dialog available the player is told", async () => {
  const cancelled = await world({ save: "cancel" });
  try {
    await cancelled.controller.exportMyData();
    assert.equal(cancelled.status().message, "Nothing was saved.");
  } finally {
    await cancelled.cleanup();
  }
  const none = await world({ withSave: false });
  try {
    await none.controller.exportMyData();
    assert.equal(none.status().message, "Saving a file is not available here.");
  } finally {
    await none.cleanup();
  }
});

test("when the server refuses (for example the account is gone) nothing is saved and the player is told", async () => {
  const w = await world();
  try {
    w.env.raw.prepare("DELETE FROM keys").run();
    await w.controller.exportMyData();
    assert.equal(w.saves.length, 0);
    assert.match(w.status().message ?? "", /The server refused it \(unknown_key\)/);
  } finally {
    await w.cleanup();
  }
});
