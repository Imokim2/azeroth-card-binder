// Guild binders in the companion app (docs/proposals/GUILD-BINDERS-DESIGN.md): the server's answers are checked before they reach Sync.lua, the add-on's
// pending donations are read from the saved file, and the engine asks the server about the guild only when it has a reason to.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { CLIENT, NOW, catalog, setup } from "../../server/test/harness.ts";
import { readBinder } from "../src/binderFile.ts";
import { fetchGuild, guildAction, registerKey } from "../src/client.ts";
import type { ClientOptions } from "../src/client.ts";
import { Engine } from "../src/engine.ts";
import { describeInstall } from "../src/files.ts";
import { loadOrCreateIdentity } from "../src/identity.ts";
import { parseGuildData, parseRoster } from "../src/guild.ts";
import { parseSavedVariables } from "../src/luaTable.ts";
import { syncFileText } from "../src/syncFile.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const GUILD = "01HF7YAT00QKSEP5RCNMPTQ3KN";
const op = (letter: string) => letter.repeat(32);
const guildReply = () => ({
  guilds: [{ id: GUILD, name: "Knights of Light", realm: "Realm Name", side: "alliance", status: "refused", character: "ann-realmname", requestedAt: 100, decidedAt: 200, note: "name is taken" }],
  membership: { id: "0".repeat(26), role: "member", state: "active", character: "ann-realmname", requestedAt: 100, decidedAt: 150, guild: { id: GUILD, name: "Knights of Light", realm: "Realm Name", side: "alliance", members: 3 } },
  donations: { results: { [op("a")]: "credited", [op("b")]: "refunded" }, refunds: [{ operation: op("b"), guild: GUILD, card: "npc:589" }] },
});

test("the server's guild answer is checked field by field, and a bad one never reaches Sync.lua", () => {
  const parsed = parseGuildData(guildReply(), ["c".repeat(32)], 500);
  assert.equal(parsed.membership?.guild.name, "Knights of Light");
  assert.equal(parsed.requests[0]?.note, "name is taken");
  assert.deepEqual(parsed.donations.refunds, [{ operation: op("b"), guild: GUILD, card: "npc:589" }]);
  assert.deepEqual(parseGuildData({ guilds: [], membership: null, donations: { results: {}, refunds: [] } }, [], 1).membership, null);
  const bad: [string, (reply: ReturnType<typeof guildReply>) => void][] = [
    ["a guild id", (reply) => { reply.membership.guild.id = 'bad"; os.execute("x")'; }],
    ["a name that is too long", (reply) => { reply.membership.guild.name = "x".repeat(25); }],
    ["a side", (reply) => { reply.membership.guild.side = "neutral"; }],
    ["a state", (reply) => { reply.membership.state = "banned"; }],
    ["a role", (reply) => { reply.membership.role = "admin" as never; }],
    ["an operation id", (reply) => { reply.donations.refunds[0]!.operation = "nope"; }],
    ["a result", (reply) => { (reply.donations.results as Record<string, string>)[op("c")] = "maybe"; }],
    ["a card", (reply) => { reply.donations.refunds[0]!.card = 'npc:1"]]; os.execute("x")'; }],
    ["a count", (reply) => { reply.membership.guild.members = -1; }],
    ["a control character", (reply) => { reply.guilds[0]!.note = "line\nbreak"; }],
  ];
  for (const [what, change] of bad) {
    const reply = guildReply();
    change(reply);
    assert.throws(() => parseGuildData(reply, [], 1), Error, what);
  }
  assert.throws(() => parseGuildData(guildReply(), ["not-a-binder"], 1));
  assert.throws(() => parseGuildData({ ...guildReply(), guilds: Array(11).fill(guildReply().guilds[0]) }, [], 1));
  assert.deepEqual(parseRoster({ guild: { id: GUILD, name: "G", realm: "R", side: "horde" }, members: [{ id: "owner-" + GUILD, character: "ann-r", role: "owner", state: "active", requestedAt: 1 }] }).members[0]?.role, "owner");
  assert.throws(() => parseRoster({ guild: { id: GUILD, name: "G", realm: "R", side: "horde" }, members: [{ id: "x", character: "a", role: "owner", state: "active", requestedAt: 1 }] }));
});

test("guild data survives safe Lua serialization as text, paired to the binder, and carries only what the add-on reads", () => {
  const reply = guildReply();
  reply.membership.guild.name = 'Knights "of" Light\\n';
  const lua = syncFileText({ syncedAt: 100, acks: [], guild: parseGuildData(reply, ["c".repeat(32)], 500) });
  const synced = parseSavedVariables(lua.replace("local _, ACB = ...", "").replace("ACB.sync =", "SYNC =").replace(/--.*$/gm, ""))["SYNC"] as Record<string, unknown>;
  const guild = synced["guild"] as { binders: string[]; membership: { state: string; role: string; guild: { name: string } }; donations: { results: Record<string, string>; refunds: { operation: string }[] }; guilds?: unknown };
  assert.deepEqual(Object.values(guild.binders), ["c".repeat(32)]);
  assert.equal(guild.membership.guild.name, reply.membership.guild.name, "network text stays text");
  assert.equal(guild.membership.state, "active");
  assert.equal(guild.donations.results[op("b")], "refunded");
  assert.equal(Object.values(guild.donations.refunds)[0]!.operation, op("b"));
  assert.equal(guild.guilds, undefined, "the add-on does not need the player's own requests");
  assert.ok(!lua.includes("name is taken"));
  assert.throws(() => syncFileText({ syncedAt: 1, acks: [], guild: { ...parseGuildData(reply, [], 1), binders: ["bad"] } }));
});

test("the donations the add-on is waiting to hear about are read from the saved file", () => {
  const file = (donations: string) => `AzerothCardBinderDB = { ["schema"] = 2, ["mode"] = "ranked", ["guildDonations"] = ${donations}, ["ledger"] = {}, ["head"] = { ["seq"] = 0, ["hash"] = "${"0".repeat(32)}" } }`;
  const donation = '{ ["key"] = "npc:589", ["guild"] = "' + GUILD + '", ["t"] = 5 }';
  assert.deepEqual(readBinder(file(`{ ["${op("b")}"] = ${donation}, ["${op("a")}"] = ${donation}, ["short"] = ${donation} }`)).guildOps, [op("a"), op("b")]);
  assert.deepEqual(readBinder(file("{}")).guildOps, []);
  assert.deepEqual(readBinder(file('"junk"')).guildOps, []);
});

async function fixture(guilds: boolean) {
  const folder = await mkdtemp(join(tmpdir(), "warcards-guild-"));
  const saved = join(folder, "WTF", "Account", "ACCOUNT1", "SavedVariables", "AzerothCardBinder.lua");
  await mkdir(join(saved, ".."), { recursive: true });
  const result = spawnSync(process.env["LUAJIT"] || "luajit", ["tests/tools/write-saved.lua", saved, "0"], { cwd: root, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  const env = setup({ guilds });
  let key: string | null = null;
  const identity = await loadOrCreateIdentity({ async get() { return key; }, async set(value) { key = value; } });
  const calls: string[] = [];
  const bodies: Record<string, unknown>[] = [];
  const client: ClientOptions = {
    baseUrl: "https://warcards.test", identity, clientVersion: CLIENT, catalogVersion: catalog.catalogVersion, now: () => NOW, sleep: async () => {}, attempts: 1,
    fetch: async (url, init) => {
      calls.push(`${init.method} ${new URL(url).pathname}`);
      if (new URL(url).pathname.startsWith("/v1/guilds/") && typeof init.body === "string") bodies.push(JSON.parse(init.body) as Record<string, unknown>);
      return env.api(new Request(url, init));
    },
  };
  const registered = await registerKey(client, "discord:guild-test", "public");
  if (registered.status !== "registered") throw new Error("fixture registration failed");
  const nonce = "b".repeat(32);
  const source = await readFile(saved, "utf8");
  const donations = `{ ["${op("d")}"] = { ["key"] = "npc:589", ["guild"] = "${GUILD}", ["t"] = 5 } }`;
  await writeFile(saved, source.replace("AzerothCardBinderDB = {", `AzerothCardBinderDB = { ["modeSetupID"] = "${nonce}", ["guildDonations"] = ${donations},`));
  return { env, client, calls, bodies, nonce, playerId: registered.playerId, install: await describeInstall(folder), identity, cleanup: () => rm(folder, { recursive: true, force: true }) };
}

test("the engine asks about the guild with the donations it is waiting on, and writes the answer paired to the binder", { timeout: 30_000 }, async () => {
  const f = await fixture(true);
  try {
    const engine = new Engine({ install: f.install, client: f.client, playerId: () => f.playerId });
    assert.equal((await engine.syncOnce({ saved: true })).wroteSync, true);
    assert.ok(f.calls.includes("POST /v1/guilds/mine"));
    assert.deepEqual(f.bodies[0]!["operations"], [op("d")], "the add-on's pending donation is asked about");
    const sync = await readFile(f.install.syncPath, "utf8");
    assert.ok(sync.includes("guild = "), "the answer is written for the add-on");
    assert.ok(sync.includes(f.nonce));
    assert.equal(engine.guildState().available, true);
    assert.deepEqual(engine.guildState().characters.length > 0, true, "the screens know the characters in the saved files");
    // A donation waits on the server, so every pass asks again until it is settled.
    const before = f.calls.filter((call) => call === "POST /v1/guilds/mine").length;
    await engine.syncOnce();
    assert.equal(f.calls.filter((call) => call === "POST /v1/guilds/mine").length, before + 1);
  } finally { await f.cleanup(); }
});

test("a server with guilds switched off is asked once, and nothing about guilds is written", { timeout: 30_000 }, async () => {
  const f = await fixture(false);
  try {
    const engine = new Engine({ install: f.install, client: f.client, playerId: () => f.playerId });
    await engine.syncOnce({ saved: true });
    await engine.syncOnce({ saved: true });
    assert.equal(f.calls.filter((call) => call === "POST /v1/guilds/mine").length, 1);
    assert.equal(engine.guildState().available, false);
    assert.ok(!(await readFile(f.install.syncPath, "utf8")).includes("guild = "));
  } finally { await f.cleanup(); }
});

test("the guild actions are signed and reach the server, and a refresh asks again at once", { timeout: 30_000 }, async () => {
  const f = await fixture(true);
  try {
    const engine = new Engine({ install: f.install, client: f.client, playerId: () => f.playerId });
    await engine.syncOnce({ saved: true });
    const asked = await guildAction(f.client, "request", { character: "nobody-realmname", name: "Knights of Light" });
    assert.deepEqual([asked.status, asked.status === "rejected" ? asked.code : ""], ["rejected", "bad_request"], "a character the player has not played is refused");
    const mine = await fetchGuild(f.client, [f.nonce], []);
    assert.equal(mine.status, "guild");
    assert.equal(mine.status === "guild" ? mine.data.membership : "x", null);
    const left = await guildAction(f.client, "leave");
    assert.deepEqual([left.status, left.status === "rejected" ? left.code : ""], ["rejected", "not_found"]);
    const before = f.calls.filter((call) => call === "POST /v1/guilds/mine").length;
    await engine.refreshGuild();
    assert.equal(f.calls.filter((call) => call === "POST /v1/guilds/mine").length > before, true);
  } finally { await f.cleanup(); }
});
