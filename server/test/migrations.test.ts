// The migrations folder rules (roadmap B13): numbered without gaps, never edited once published, and the result
// is the schema the code expects, with foreign keys enforced.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import test from "node:test";
import { openTestDb } from "./sqliteDb.ts";

const dir = new URL("../migrations/", import.meta.url);
const files = readdirSync(dir).filter((name) => name.endsWith(".sql")).sort();

test("migrations are numbered from 0001 without gaps, with a name", () => {
  assert.ok(files.length >= 1);
  files.forEach((name, index) => assert.match(name, new RegExp(`^${String(index + 1).padStart(4, "0")}_[a-z0-9_]+\\.sql$`), name));
});

test("a published migration is never edited: its checksum is on record", () => {
  const recorded = new Map(
    readFileSync(new URL("CHECKSUMS.txt", dir), "utf8").split(/\r?\n/).filter(Boolean).map((line) => {
      const [hash, name] = line.split(/\s+/);
      return [name, hash] as const;
    }),
  );
  for (const name of files) {
    const sql = readFileSync(new URL(name, dir), "utf8").replace(/\r\n/g, "\n");
    const hash = createHash("sha256").update(sql).digest("hex");
    assert.equal(recorded.get(name), hash, `${name} changed or is not in CHECKSUMS.txt. Never edit a migration that has shipped: add a new one.`);
  }
  assert.equal(recorded.size, files.length, "CHECKSUMS.txt lists a migration that does not exist");
});

test("applying every migration gives the tables and indexes the code relies on", () => {
  const { raw } = openTestDb();
  const names = (type: string) => (raw.prepare("SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'").all(type) as { name: string }[]).map((row) => row.name).sort();
  assert.deepEqual(names("table"), ["batches", "characters", "drops", "flags", "keys", "ledger_state", "players", "scores", "set_completions", "tapes", "trade_taint", "trades", "wanted"]);
  assert.ok(names("index").includes("scores_by_score"));
  // Every table is keyed by player, as the scalability plan requires.
  for (const table of ["batches", "characters", "drops", "flags", "keys", "ledger_state", "scores", "set_completions", "tapes", "trades"]) {
    const columns = (raw.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[]).map((column) => column.name);
    assert.ok(columns.includes("player_id"), `${table} has no player_id`);
  }
});

test("foreign keys and checks are enforced", () => {
  const { raw } = openTestDb();
  assert.throws(() => raw.prepare("INSERT INTO keys (public_key, player_id, created_at) VALUES ('k', 'nobody', 1)").run());
  assert.throws(() => raw.prepare("INSERT INTO players (id, created_at, status) VALUES ('p', 1, 'wizard')").run());
  raw.prepare("INSERT INTO players (id, discord_id, created_at) VALUES ('p', 'd1', 1)").run();
  assert.throws(() => raw.prepare("INSERT INTO players (id, discord_id, created_at) VALUES ('q', 'd1', 1)").run()); // one player per Discord account
  assert.throws(() => raw.prepare("INSERT INTO batches VALUES ('p', 1, 1, 'h', x'00', 1), ('p', 1, 2, 'h', x'00', 1)").run()); // one batch per start position
});
