// How much processor time the heaviest requests cost, to judge whether they fit the free Workers plan (10 ms of CPU per request;
// the paid plan allows far more). Run: node bench/cpu.bench.ts
//
// It runs the real API code against an in-memory SQLite database, so the numbers are an estimate: Node's crypto is not workerd's,
// and SQLite here runs on the same thread (on Cloudflare a database wait costs no CPU), which makes the figures a little high. They
// are good for the order of magnitude and for which request is the expensive one.
import { performance } from "node:perf_hooks";
import { REFILL_BELOW, TAPE_SIZE, tapeEntry, tapeKey } from "../src/tape.ts";
import { sha256Hex } from "../../packages/shared/src/crypto.ts";
import { NOW, TAPE_SECRET, newPlayer, registration, rankedHistory, setup, signedUpload } from "../test/harness.ts";
import { createRequire } from "node:module";
import { canonicalJson } from "../../packages/shared/src/crypto.ts";

const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

type Row = { what: string; cpuMs: number; wallMs: number; note: string };
const rows: Row[] = [];

// CPU time (user + system) and wall time of `work`, the median of `runs` runs.
async function measure(what: string, note: string, runs: number, work: () => Promise<unknown>): Promise<void> {
  const cpu: number[] = [];
  const wall: number[] = [];
  for (let run = 0; run < runs; run++) {
    const before = process.cpuUsage();
    const start = performance.now();
    await work();
    wall.push(performance.now() - start);
    const used = process.cpuUsage(before);
    cpu.push((used.user + used.system) / 1000);
  }
  const median = (list: number[]) => [...list].sort((a, b) => a - b)[Math.floor(list.length / 2)] as number;
  rows.push({ what, cpuMs: median(cpu), wallMs: median(wall), note });
}

const tapeRequest = (player: ReturnType<typeof newPlayer>) => {
  const body = { key: player.publicKeyHex, sentAt: NOW };
  return { ...body, sig: reference.signBatch({ ...body, purpose: "tape" }, player.privateKey) };
};

// Warm up the JIT, then measure.
const secret = await tapeKey(TAPE_SECRET);
for (let index = 1; index <= 300; index++) await tapeEntry(secret, "warmup", index);

await measure(`${TAPE_SIZE.toLocaleString("en-US")} tape entries (HMAC-SHA256)`, "the cost inside a tape request", 15, async () => {
  for (let index = 1; index <= TAPE_SIZE; index++) await tapeEntry(secret, "01ARZ3NDEKTSV4RRFFQ69G5FAV", index);
});
await measure("SHA-256 of one tape batch", "the tape commitment", 15, async () => { await sha256Hex("a".repeat(TAPE_SIZE * 17 - 1)); });

// A fresh player and a real tape request: the first issues a full batch, a later one only returns what is unused.
const env = setup();
const alice = newPlayer("alice");
const registered = (await (await env.call("/v1/register", { body: registration(alice) })).json()) as { playerId: string };
await measure("POST /v1/tape, first (issues a full batch)", "the worst tape request: derive, commit, store, return", 1, async () => { await env.call("/v1/tape", { body: tapeRequest(alice) }); });
await measure("POST /v1/tape, again (returns unused batch)", "a repeated request, not an idle poll", 15, async () => { await env.call("/v1/tape", { body: tapeRequest(alice) }); });

// Uploads: a small Casual history, and a Ranked history that uses most of an issued tape (the largest an upload can be).
const casual = newPlayer("casual");
await env.call("/v1/register", { body: registration(casual) });
await measure("POST /v1/ledger, a short Casual history", "a typical small upload", 10, async () => { await env.call("/v1/ledger", { body: signedUpload(casual, []) }); });

async function rankedUpload(wins: number, label: string) {
  const bench = setup();
  const player = newPlayer("ranked" + wins);
  const reg = (await (await bench.call("/v1/register", { body: registration(player) })).json()) as { playerId: string };
  for (let round = 0; round < 2; round++) await bench.call("/v1/tape", { body: tapeRequest(player) });
  const { events, tapeNext, attempts } = await rankedHistory(reg.playerId, wins);
  const snapshot = { counts: { "npc:589": wins }, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} };
  const body = signedUpload(player, events, { tapeIndex: tapeNext, snapshot });
  canonicalJson(body);
  await measure(`POST /v1/ledger, Ranked: ${events.length} events, ${attempts} attempts`, label, 1, async () => {
    const response = await bench.call("/v1/ledger", { body });
    if (response.status !== 200) throw new Error("the upload was refused: " + JSON.stringify(await response.json()));
  });
}
await rankedUpload(2, "a few attempts");
await rankedUpload(8, "hundreds of attempts");
await rankedUpload(14, "a longer session sample");

console.log(`\nTape batch: ${TAPE_SIZE} entries, refilled below ${REFILL_BELOW}.\n`);
console.log("What".padEnd(62) + "CPU ms".padStart(9) + "wall ms".padStart(9) + "  note");
for (const row of rows) console.log(row.what.padEnd(62) + row.cpuMs.toFixed(1).padStart(9) + row.wallMs.toFixed(1).padStart(9) + "  " + row.note);
console.log("\nFree plan: 10 ms of CPU per request. Anything near or over that needs the paid plan (or a cheaper way to do it).");
