// The standings: fetched from the real server, written into Sync.lua, and read back by the real Lua interpreter.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { CLIENT, NOW, catalog, chainedHistory, newPlayer, registration, setup, signedUpload } from "../../server/test/harness.ts";
import { fetchStandings } from "../src/client.ts";
import type { ClientOptions, FetchLike } from "../src/client.ts";
import { syncFileText } from "../src/syncFile.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const luajit = process.env["LUAJIT"] || "luajit";
const hex = (text: string) => Buffer.from(text, "utf8").toString("hex");

async function lua(text: string): Promise<string[]> {
  const folder = await mkdtemp(join(tmpdir(), "warcards-sync-"));
  const file = join(folder, "Sync.lua");
  await writeFile(file, text);
  const result = spawnSync(luajit, ["tests/tools/read-sync.lua", file], { cwd: root, encoding: "utf8" });
  await rm(folder, { recursive: true, force: true });
  if (result.status !== 0) throw new Error(result.stderr);
  return result.stdout.split(/\r?\n/); // Lua writes the platform's line ending
}

const options = (env: ReturnType<typeof setup>): ClientOptions => {
  const fetch: FetchLike = async (url, init) => env.api(new Request(url, init));
  return {
    baseUrl: "https://warcards.test", fetch, identity: { publicKeyHex: "0".repeat(64), sign: async () => "0".repeat(128) },
    clientVersion: CLIENT, catalogVersion: catalog.catalogVersion, now: () => NOW, sleep: async () => {},
  };
};

test("standings come from the server, go through Sync.lua and are read back exactly by Lua", async () => {
  const env = setup();
  const alice = newPlayer("alice");
  const bob = newPlayer("bob");
  const ids: string[] = [];
  for (const [player, name] of [[alice, "Alice"], [bob, "Bob"]] as const) {
    const registered = (await (await env.call("/v1/register", { body: registration(player) })).json()) as { playerId: string };
    ids.push(registered.playerId);
    // Bob plays less: only the first events of the same history.
    const events = name === "Alice" ? chainedHistory() : chainedHistory(1, 3);
    const response = await env.call("/v1/ledger", { body: signedUpload(player, events, { character: name, realm: "Realm Name" }) });
    void response;
  }
  const result = await fetchStandings(options(env), ids[1] as string);
  assert.equal(result.status, "standings");
  if (result.status !== "standings") return;
  const { standings } = result;
  assert.ok(standings.leaderboard.length >= 1);
  assert.equal(standings.leaderboard[0]?.rank, 1);
  assert.ok(standings.verified.every((name) => /^[a-z]+-[a-z]+$/.test(name)), JSON.stringify(standings.verified));

  // Through the file and back: the same numbers, and the names byte for byte.
  const text = syncFileText({ syncedAt: NOW, acks: [], ...standings });
  const lines = await lua(text);
  for (const [index, row] of standings.leaderboard.entries()) {
    assert.ok(lines.includes(`row ${index + 1} ${row.rank} ${hex(row.name)} ${row.score} ${row.cards} ${row.sets}`), lines.join("\n"));
  }
  assert.ok(lines.includes("verified " + standings.verified.map(hex).sort().join(",")));
  if (standings.you) assert.ok(lines.includes(`you ${standings.you.rank} ${standings.you.score} ${standings.you.cards} ${standings.you.sets}`));
});

test("a player the server does not list has no place of their own, and an empty ladder is still a valid file", async () => {
  const env = setup();
  const result = await fetchStandings(options(env), "01ARZ3NDEKTSV4RRFFQ69G5FAV");
  assert.equal(result.status, "standings");
  if (result.status !== "standings") return;
  assert.deepEqual(result.standings, { leaderboard: [], verified: [], firsts: [], you: null });
  const lines = await lua(syncFileText({ syncedAt: NOW, acks: [], ...result.standings }));
  assert.deepEqual(lines.filter((line) => line.startsWith("row") || line.startsWith("you")), []);
});

test("names from the network can only ever be text in Sync.lua", async () => {
  const nasty = ['"}; os.execute("x") --', "line\nbreak", "back\slash\\", "é日本 ' \u0000 \u001b", "]]; x = 1 --[["];
  const text = syncFileText({
    syncedAt: NOW, acks: [],
    leaderboard: nasty.map((name, index) => ({ rank: index + 1, name, score: 10, cards: 1, sets: 0 })),
    verified: nasty, firsts: nasty.map((name) => ({ setCode: "DM", title: name, by: name, at: 5 })),
  });
  assert.ok(!/os\.execute\("x"\)/.test(text), "no raw quote can end the string");
  const lines = await lua(text);
  nasty.forEach((name, index) => assert.ok(lines.includes(`row ${index + 1} ${index + 1} ${hex(name)} 10 1 0`), name));
  assert.ok(lines.includes("verified " + nasty.map(hex).sort().join(",")));
  assert.equal(lines.at(-1), "globals os-present"); // the reader's own environment, untouched: nothing in the file ran
  // Numbers must be whole and sizes bounded.
  assert.throws(() => syncFileText({ syncedAt: 1, acks: [], leaderboard: [{ rank: 1.5, name: "x", score: 1, cards: 1, sets: 0 }] }));
  assert.throws(() => syncFileText({ syncedAt: 1, acks: [], leaderboard: [{ rank: 1, name: "x".repeat(81), score: 1, cards: 1, sets: 0 }] }));
  assert.throws(() => syncFileText({ syncedAt: 1, acks: [], leaderboard: Array.from({ length: 101 }, (_, index) => ({ rank: index, name: "x", score: 1, cards: 1, sets: 0 })) }));
});
