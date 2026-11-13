// tools/staging-walkthrough.js: it passes for this checkout and a server that is this release, says what is wrong when they are not, and
// drafts a staging season the scheduler accepts.
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { SqlSeasons } from "../src/seasons.ts";
import { NOW, catalog, setup } from "./harness.ts";

type Item = { name: string; status: string; detail: string };
const walk = createRequire(import.meta.url)("../../tools/staging-walkthrough.js") as {
  checkout(options?: { read?: (relative: string) => string }): { items: Item[]; versions: Record<string, string | number> };
  walkthrough(options: Record<string, unknown>): Promise<{ sections: { title: string; items: Item[] }[]; hand: [string, string[]][] }>;
  seasonDraft(file: string, options?: { now?: number }): Promise<{ draft: Record<string, unknown>; names: string[]; page: string }>;
  print(report: unknown, write?: (line: string) => void): number;
};

const BASE = "https://walkthrough.test";
const real = (relative: string) => readFileSync(new URL("../../" + relative, import.meta.url), "utf8");
const failing = (items: Item[]) => items.filter((item) => item.status === "fail");

function server(options: { seasons?: boolean; version?: string } = {}) {
  const env = setup();
  env.deps.version = options.version ?? (JSON.parse(real("server/package.json")) as { version: string }).version;
  if (options.seasons !== false) env.deps.seasons = new SqlSeasons(env.db, catalog);
  const get = (async (input: string | URL | Request, init?: RequestInit) => env.api(new Request(String(input), init))) as typeof fetch;
  return { env, get };
}

test("this checkout is ready: versions agree, the protocol matches, the catalog and its held-back list are current", () => {
  const result = walk.checkout();
  assert.deepEqual(failing(result.items), []);
  assert.ok(result.items.length >= 6);
  assert.equal(result.versions["protocol"], Number(/const SPEC_VERSION = (\d+);/.exec(real("packages/shared/src/ledger.js"))![1]));
});

test("a checkout that is not ready is called out, with the reason", () => {
  const edited = (change: (relative: string, text: string) => string) => (relative: string) => change(relative, real(relative));
  const wrongServer = walk.checkout({ read: edited((relative, text) => relative === "server/wrangler.toml" ? text.replace(/VERSION = "[\d.]+"/, 'VERSION = "0.0.1"') : text) });
  assert.ok(failing(wrongServer.items).some((item) => /versions are set/.test(item.name) && /wrangler VERSION 0\.0\.1/.test(item.detail)));
  const wrongProtocol = walk.checkout({ read: edited((relative, text) => relative === "app/src/client.ts" ? text.replace("specVersion: 9,", "specVersion: 8,") : text) });
  assert.ok(failing(wrongProtocol.items).some((item) => /ledger protocol/.test(item.name) && /companion sends 8/.test(item.detail)));
  const staleList = walk.checkout({ read: edited((relative, text) => relative === "AzerothCardBinder/LaunchCollection.lua" ? text.replace('"npc:100", ', "") : text) });
  assert.ok(failing(staleList.items).some((item) => /held-back list/.test(item.name) && /OUT OF DATE/.test(item.detail)));
  const version = String(walk.checkout().versions["addon"]);
  const noNotes = walk.checkout({ read: edited((relative, text) => relative === "CHANGELOG.md" ? text.split("## " + version).join("## 0.0.0") : text) });
  assert.ok(failing(noNotes.items).some((item) => /changelog/.test(item.name)));
  const tooHigh = walk.checkout({ read: edited((relative, text) => relative === "server/wrangler.toml" ? text.replace(/MIN_ADDON = "[\d.]+"/, 'MIN_ADDON = "9.0.0"') : text) });
  assert.ok(failing(tooHigh.items).some((item) => /minimum versions/.test(item.name)));
});

test("a server that is this release passes every deployed check", async () => {
  const { get } = server();
  const report = await walk.walkthrough({ base: BASE, get, smoke: false, now: () => NOW });
  const deployed = report.sections.find((section) => section.title.startsWith("The deployed server"))!;
  assert.deepEqual(failing(deployed.items), []);
  const protocol = deployed.items.find((item) => /ledger protocol/.test(item.name))!;
  assert.match(protocol.detail, /1: client_too_old/);
  assert.match(protocol.detail, /9: unknown_key/);
  assert.match(protocol.detail, /10: client_too_old/);
  assert.ok(report.hand.length >= 4 && report.hand.every(([, lines]) => lines.length > 0), "the by-hand list is there");
});

test("a server that is an older release, or has no seasons, or a migration still waiting, is called out", async () => {
  const old = server({ seasons: false, version: "0.4.1" });
  const report = await walk.walkthrough({ base: BASE, get: old.get, smoke: false, now: () => NOW, wrangler: () => ({ ok: false, detail: "still to apply: 0014_seasons.sql" }) });
  const bad = failing(report.sections.find((section) => section.title.startsWith("The deployed server"))!.items);
  assert.ok(bad.some((item) => /is this release/.test(item.name) && /server 0\.4\.1/.test(item.detail)));
  assert.ok(bad.some((item) => /seasons routes/.test(item.name) && /404/.test(item.detail)));
  assert.ok(bad.some((item) => /migration/.test(item.name) && /0014_seasons\.sql/.test(item.detail)));
});

test("--offline looks only at the checkout, and the printed report counts failures for the exit status", async () => {
  const offline = await walk.walkthrough({ base: "", offline: true });
  assert.equal(offline.sections.length, 1);
  const lines: string[] = [];
  assert.equal(walk.print(offline, (line) => lines.push(line)), 0);
  assert.match(lines.join("\n"), /All \d+ automated checks passed\./);
  assert.match(lines.join("\n"), /\[ \] /);
  const broken = { sections: [{ title: "x", items: [{ name: "a", status: "fail", detail: "d" }, { name: "b", status: "ok", detail: "" }] }], hand: [] };
  assert.equal(walk.print(broken, () => {}), 1);
});

test("the staging season draft names two held-back cards from one page and is accepted by the scheduler's own checks", async () => {
  const folder = await mkdtemp(join(tmpdir(), "warcards-walkthrough-"));
  try {
    const file = join(folder, "season.json");
    const made = await walk.seasonDraft(file, { now: Date.UTC(2026, 10, 13, 12, 0, 0) });
    const written = JSON.parse(await readFile(file, "utf8")) as { id: string; startsAt: string; endsAt: string; selection: { mode: string; cards: string[] }; rewards: { completion: { packs: { pack: string }[] } } };
    assert.equal(written.id, "staging-walkthrough");
    assert.equal(written.startsAt, "2026-11-13T12:15:00Z", "it starts fifteen minutes from now");
    assert.equal(written.endsAt, "2026-11-16T12:15:00Z", "and runs three days");
    assert.equal(written.selection.mode, "manual");
    assert.equal(written.selection.cards.length, 2);
    for (const key of written.selection.cards) assert.ok(catalog.cards[key]?.seasonal, key + " is held back");
    assert.equal(new Set(written.selection.cards.map((key) => catalog.cards[key]?.set)).size, 1, "both come from one page");
    assert.match(written.rewards.completion.packs[0]!.pack, /^[A-Z0-9]+:common$/);
    assert.equal(made.names.length, 2);
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});
