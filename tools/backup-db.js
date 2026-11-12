#!/usr/bin/env node
// A copy of the database, outside Cloudflare.
//
//   node tools/backup-db.js --env production --out D:\warcards-backups [--keep 14]
//
// Writes warcards-<env>-<date>.sql (every table and row, as SQL that `wrangler d1 execute --file` can load again), checks it
// holds what a backup should, and deletes the oldest copies beyond --keep (default 14). The export holds players' Discord
// account ids and every ledger event: keep the folder private, outside the repository, and never upload it anywhere public.
// Cloudflare's own point-in-time restore (docs/runbooks/BACKUPS.md) is the first line of defence; this is the second, for the
// case where the account itself is the problem. Schedule it daily (Windows Task Scheduler: see the runbook).
"use strict";
const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const DATABASES = { production: "warcards", staging: "warcards-staging" };
const NAME = /^warcards-(production|staging)-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z)\.sql$/;

// The file name for a backup taken at `date`, so names sort the way time runs.
function backupName(env, date) {
  return `warcards-${env}-${date.toISOString().replace(/\.\d+Z$/, "Z").replace(/:/g, "-")}.sql`;
}

// A backup is only believed if it is a real, non-trivial dump that has the tables the service cannot live without.
function looksLikeABackup(text) {
  if (text.length < 200) return "the export is almost empty";
  for (const table of ["players", "keys", "batches", "drops", "ledger_state", "tapes", "trades"]) {
    if (!new RegExp("CREATE TABLE\\s+[\"`']?" + table + "[\"`'\\s(]", "i").test(text)) return "the export has no " + table + " table";
  }
  return null;
}

// Delete the oldest backups of this environment beyond `keep`. Returns the names removed.
function prune(folder, env, keep) {
  const mine = fs.readdirSync(folder).filter((name) => {
    const found = NAME.exec(name);
    return found && found[1] === env;
  }).sort();
  const doomed = mine.slice(0, Math.max(0, mine.length - keep));
  for (const name of doomed) fs.rmSync(path.join(folder, name));
  return doomed;
}

// `exportTo(file)` runs the real export; it is a parameter so the checks above can be tested without Cloudflare.
function backup({ env, folder, keep, now, exportTo }) {
  if (!DATABASES[env]) throw new Error("--env is production or staging");
  const target = path.resolve(folder);
  const relative = path.relative(root, target);
  if (relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative))) throw new Error("keep backups outside the repository: " + target);
  fs.mkdirSync(target, { recursive: true });
  const file = path.join(target, backupName(env, now));
  exportTo(file);
  const problem = looksLikeABackup(fs.readFileSync(file, "utf8"));
  if (problem) {
    fs.rmSync(file, { force: true });
    throw new Error("the backup was discarded: " + problem);
  }
  return { file, removed: prune(target, env, keep) };
}

function wranglerExport(env, file) {
  // One command line, not an argument list: Windows needs a shell to run npx. `env` is one of two known names and `file` was
  // built here, but a quote in the path would still break the line, so it is refused.
  if (file.includes('"')) throw new Error("the backup folder's path holds a quote");
  const line = `npx wrangler d1 export ${DATABASES[env]} --remote --env ${env} --output "${file}"`;
  const run = spawnSync(line, { cwd: path.join(root, "server"), encoding: "utf8", shell: true });
  if (run.status !== 0) throw new Error("wrangler d1 export failed: " + (run.stderr || run.stdout || run.error));
}

module.exports = { backupName, looksLikeABackup, prune, backup };

if (require.main === module) {
  const args = process.argv.slice(2);
  const option = (name) => (args.indexOf("--" + name) >= 0 ? args[args.indexOf("--" + name) + 1] : undefined);
  const env = option("env") || "production";
  const folder = option("out");
  if (!folder) {
    console.error("Usage: node tools/backup-db.js --env production --out <folder outside the repository> [--keep 14]");
    process.exit(1);
  }
  try {
    const keep = Number(option("keep") || 14);
    if (!Number.isInteger(keep) || keep < 1) throw new Error("--keep is a whole number, 1 or more");
    const result = backup({ env, folder, keep, now: new Date(), exportTo: (file) => wranglerExport(env, file) });
    console.log("Backup written: " + result.file);
    if (result.removed.length > 0) console.log("Removed the oldest: " + result.removed.join(", "));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
