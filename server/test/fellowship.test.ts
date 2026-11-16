// The Fellowship cards end to end (docs/FELLOWSHIP.md, ledger spec 12): the real add-on code trades, gifts and sits at a camp, earning rolls for the
// Fellowship cards, with the server's own roll tape; the server accepts exactly what it wrote, and refuses an attempt no activity paid for.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { TAPE_SECRET, catalog, chain, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import { tapeEntry, tapeKey } from "../src/tape.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };
type Body = Record<string, unknown> & { error?: { code: string; detail?: Record<string, unknown> } };
type Run = { events: Record<string, unknown>[]; owed: Record<string, number>; tapeNext: number; snapshot: { counts: Record<string, number>; dust: number; sets: Record<string, boolean> } };

async function played(id: string): Promise<Run> {
  const key = await tapeKey(TAPE_SECRET);
  const entries: string[] = [];
  for (let position = 1; position <= 80; position++) entries.push(await tapeEntry(key, id, position));
  const folder = mkdtempSync(join(tmpdir(), "warcards-fellowship-"));
  try {
    const file = join(folder, "tape.txt");
    writeFileSync(file, entries.join("\n"));
    const result = spawnSync(process.env["LUAJIT"] || "luajit", ["tests/tools/play-fellowship.lua", file], { cwd: root, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
    assert.equal(result.status, 0, String(result.stderr));
    return JSON.parse(result.stdout) as Run;
  } finally { rmSync(folder, { recursive: true, force: true }); }
}
const strip = (event: Record<string, unknown>) => { const { prev, h, ...rest } = event; void prev; void h; return rest; };

async function world() {
  const env = setup();
  const player = newPlayer("fellow");
  const registered = (await (await env.call("/v1/register", { body: registration(player) })).json()) as Body;
  const request = { key: player.publicKeyHex, sentAt: 1_700_000_000 };
  await env.call("/v1/tape", { body: { ...request, sig: reference.signBatch({ ...request, purpose: "tape" }, player.privateKey) } });
  return { env, player, id: registered["playerId"] as string };
}
const upload = (w: Awaited<ReturnType<typeof world>>, run: Run, events: Record<string, unknown>[]) => w.env.call("/v1/ledger", {
  body: signedUpload(w.player, events, { specVersion: 12, character: "Alice", realm: "RealmName", tapeIndex: run.tapeNext, snapshot: { ...run.snapshot, attempts: {}, titles: {} } }),
});

test("what the add-on writes for trades, gifts and a camp is accepted, with every roll spent", async () => {
  const w = await world();
  const run = await played(w.id);
  const kinds = run.events.map((event) => `${event["kind"]}:${event["key"]}`);
  assert.ok(kinds.includes("mode:fellow1") && kinds.includes("mode:camp1") && kinds.includes("camp:violet"), kinds.join(" "));
  // Each activity made its roll, as a miss or a drop on the activity's own card.
  const activityCards = run.events.filter((event) => catalog.cards[String(event["key"])]?.activity && (event["kind"] === "miss" || event["kind"] === "drop"));
  assert.ok(activityCards.length >= 5, "gift, gift, trade, gift and camp each rolled once: " + activityCards.length);
  assert.deepEqual(run.owed, {}, "nothing is left owed");
  const response = await upload(w, run, run.events);
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  const state = JSON.parse((w.env.raw.prepare("SELECT state_json FROM ledger_state").get() as { state_json: string }).state_json) as { fellow: number; credits: Record<string, number>; camp: number; campBoosted: number };
  assert.equal(state.fellow, 1);
  assert.deepEqual(state.credits, { trade: 0, gift: 0, donate: 0, camp: 0 }, "the server counted the same rolls the add-on did");
  assert.ok(state.campBoosted >= 2, "the creature attempt and the camp's own roll were both boosted");
});

test("an attempt on a Fellowship card that no activity paid for is refused", async () => {
  const w = await world();
  const run = await played(w.id);
  // The roll for the donation card, with no donation: take the last gift roll and say it was for The Benefactor instead.
  const list = run.events.map(strip);
  const index = list.findIndex((event) => event["key"] === "npc:900000002" && event["kind"] === "miss");
  assert.ok(index > 0);
  list[index] = { ...list[index], key: "npc:900000003" };
  const response = await upload(w, run, chain(list));
  assert.equal(response.status, 422);
  const body = (await response.json()) as Body;
  assert.equal(body.error?.code, "rule_broken", JSON.stringify(body));
  assert.equal(body.error?.detail?.["rule"], "activity");
});

test("a roll cannot be used twice: a second attempt for one trade is refused", async () => {
  const w = await world();
  const run = await played(w.id);
  const list = run.events.map(strip);
  // Find the trade roll (The Trader) and write it a second time straight after, on the next tape entry.
  const index = list.findIndex((event) => event["key"] === "npc:900000001");
  assert.ok(index > 0, "the scenario trades once");
  const first = list[index] as { tape: number; seq: number; t: number };
  void first;
  const extra = { ...list[index], tape: (list[index]!["tape"] as number) + 1 };
  // Insert the extra attempt and move everything after it down by one position on the tape.
  const shifted = list.map((event, at) => (at > index && Number(event["tape"]) > 0 ? { ...event, tape: Number(event["tape"]) + 1 } : event));
  shifted.splice(index + 1, 0, extra);
  const renumbered = shifted.map((event, at) => ({ ...event, seq: at + 1 }));
  const response = await upload(w, run, chain(renumbered));
  assert.equal(response.status, 422, JSON.stringify(await response.clone().json()));
  assert.ok(["activity", "tape_invalid", "rule_broken"].includes(((await response.json()) as Body).error?.code ?? ""));
});

test("a binder that has not recorded mode/fellow1 cannot try for a Fellowship card at all", async () => {
  const w = await world();
  const run = await played(w.id);
  const list = run.events.map(strip).filter((event) => !(event["kind"] === "mode" && event["key"] === "fellow1"));
  const renumbered = list.map((event, at) => ({ ...event, seq: at + 1 }));
  const response = await upload(w, run, chain(renumbered));
  assert.equal(response.status, 422);
  assert.equal((((await response.json()) as Body).error?.detail ?? {})["rule"], "activity");
});

test("a server on spec 11 does not know the Fellowship rules: an older companion cannot upload a binder that has them", async () => {
  const w = await world();
  const run = await played(w.id);
  const response = await w.env.call("/v1/ledger", { body: signedUpload(w.player, run.events, { specVersion: 11, character: "Alice", realm: "RealmName", tapeIndex: run.tapeNext, snapshot: { ...run.snapshot, attempts: {}, titles: {} } }) });
  assert.equal(response.status, 426);
});
