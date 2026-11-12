"use strict";
// tools/backup-db.js: the checks around the export (what counts as a backup, where it may be written, which copies are kept).
// The export itself is a parameter here, so nothing talks to Cloudflare. Run: node --test tests/backup-db.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { backup, backupName, looksLikeABackup, prune } = require("../tools/backup-db.js");

const TABLES = ["players", "keys", "batches", "drops", "ledger_state", "tapes", "trades"];
const dump = (tables = TABLES) => tables.map((table) => `CREATE TABLE ${table} (id TEXT PRIMARY KEY, note TEXT);\nINSERT INTO ${table} VALUES ('a', '${"x".repeat(40)}');`).join("\n");

test("backup names sort the way time runs and say which database they are of", () => {
  const a = backupName("production", new Date("2026-11-12T09:05:03.250Z"));
  const b = backupName("production", new Date("2026-11-12T10:00:00.000Z"));
  assert.equal(a, "warcards-production-2026-11-12T09-05-03Z.sql");
  assert.ok(a < b);
});

test("only a real dump with the service's tables counts as a backup", () => {
  assert.equal(looksLikeABackup(dump()), null);
  assert.match(looksLikeABackup("-- nothing"), /almost empty/);
  assert.match(looksLikeABackup(dump(TABLES.filter((table) => table !== "drops"))), /no drops table/);
  assert.match(looksLikeABackup(dump(TABLES.filter((table) => table !== "ledger_state"))), /no ledger_state table/);
});

test("a backup is written, checked, and the oldest copies beyond the number to keep are removed, for that database only", () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), "warcards-backups-"));
  try {
    const at = (day) => new Date(`2026-11-${String(day).padStart(2, "0")}T03:00:00Z`);
    for (const day of [1, 2, 3, 4]) backup({ env: "production", folder, keep: 3, now: at(day), exportTo: (file) => fs.writeFileSync(file, dump()) });
    backup({ env: "staging", folder, keep: 3, now: at(1), exportTo: (file) => fs.writeFileSync(file, dump()) });
    fs.writeFileSync(path.join(folder, "notes.txt"), "not a backup");
    const left = fs.readdirSync(folder).sort();
    assert.deepEqual(left, [
      "notes.txt",
      "warcards-production-2026-11-02T03-00-00Z.sql", "warcards-production-2026-11-03T03-00-00Z.sql", "warcards-production-2026-11-04T03-00-00Z.sql",
      "warcards-staging-2026-11-01T03-00-00Z.sql",
    ]);
    assert.deepEqual(prune(folder, "production", 1), ["warcards-production-2026-11-02T03-00-00Z.sql", "warcards-production-2026-11-03T03-00-00Z.sql"]);
  } finally {
    fs.rmSync(folder, { recursive: true, force: true });
  }
});

test("an export that is not a backup is discarded, and a folder inside the repository is refused", () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), "warcards-backups-"));
  try {
    assert.throws(() => backup({ env: "production", folder, keep: 3, now: new Date(), exportTo: (file) => fs.writeFileSync(file, "oops") }), /discarded/);
    assert.deepEqual(fs.readdirSync(folder), [], "the bad file is not left behind");
    assert.throws(() => backup({ env: "production", folder: path.join(__dirname, "..", "backups"), keep: 3, now: new Date(), exportTo: () => {} }), /outside the repository/);
    assert.throws(() => backup({ env: "production", folder: path.join(__dirname, ".."), keep: 3, now: new Date(), exportTo: () => {} }), /outside the repository/);
    assert.throws(() => backup({ env: "elsewhere", folder, keep: 3, now: new Date(), exportTo: () => {} }), /production or staging/);
  } finally {
    fs.rmSync(folder, { recursive: true, force: true });
  }
});
