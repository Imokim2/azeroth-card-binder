// Conservative, opt-in recovery of an exact server-matching .bak. Never merge branches or manufacture history.
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { mkdir, readFile, readdir, unlink, writeFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { readBinder } from "./binderFile.ts";
import { parseSavedVariables } from "./luaTable.ts";
import type { LuaValue } from "./luaTable.ts";
import { writeFileAtomic } from "./files.ts";

type RecordValue = Record<string, unknown>;
const record = (value: unknown): RecordValue => value && typeof value === "object" && !Array.isArray(value) ? value as RecordValue : {};
const hash = (text: string) => createHash("sha256").update(text).digest("hex");
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as {
  verifyChain(events: unknown[], head: { seq: number; hash: string }): { ok: boolean; head?: { seq: number; hash: string } };
};
const mapText = (value: unknown) => JSON.stringify(Object.entries(record(value)).sort(([a], [b]) => a.localeCompare(b)));
const progressKeys = new Set(("schema counts shiny dust sets titles achievements tradeCount history ledger head stateSum tape run mode modeChoice casualDrops attempts misses rolledGuids rolledNext legacy exactMode balancedDrops balanceLedger editionDrops editionLedger tieredPacks packTiersLedger packs levels").split(" "));

export type RecoveryServer = {
  head: { seq: number; hash: string }; tapeNext: number; casualDrops: number; state: RecordValue; events: RecordValue[];
};
export function recoveryServer(text: string): RecoveryServer | null {
  const data = record(JSON.parse(text));
  if (data["format"] !== 1 || !Array.isArray(data["binders"])) return null;
  const live = data["binders"].map(record).find(b => b["archived"] === false);
  const saved = record(live?.["saved"]), seq = saved["headSeq"], digest = saved["headHash"], next = saved["tapeNext"];
  if (!Number.isSafeInteger(seq) || Number(seq) < 1 || typeof digest !== "string" || !/^[0-9a-f]{32}$/.test(digest)
    || !Number.isSafeInteger(next) || Number(next) < 1) return null;
  const state = record(saved["state"]);
  if (Number(state["packLeft"]) > 0) return null;
  if (!Number.isSafeInteger(saved["casualDrops"]) || Number(saved["casualDrops"]) < 0) return null;
  return { head: { seq: Number(seq), hash: digest }, tapeNext: Number(next), casualDrops: Number(saved["casualDrops"]), state,
    events: Array.isArray(live?.["events"]) ? live["events"].map(record) : [] };
}

function stateSum(raw: RecordValue): string {
  let high = 0, low = 0;
  for (const [key, count] of [...Object.entries(record(raw["counts"])), ["dust", raw["dust"]] as [string, unknown]]) {
    if (!Number.isSafeInteger(count) || Number(count) < 0) throw new Error("invalid inventory");
    if (Number(count) === 0) continue;
    const part = hash(key + "=" + count);
    high = (high + parseInt(part.slice(0, 6), 16)) % 16777216;
    low = (low + parseInt(part.slice(6, 12), 16)) % 16777216;
  }
  return high.toString(16).padStart(6, "0") + low.toString(16).padStart(6, "0");
}

export type RecoveryPlan = { path: string; current: string; backup: string; backupPath: string; restored: string; head: RecoveryServer["head"]; tapeNext: number; mode: string; copies: number };

export function planRecovery(path: string, current: string, backup: string, server: RecoveryServer): RecoveryPlan | null {
  try {
    const before = readBinder(current), candidate = readBinder(backup);
    const raw = record(parseSavedVariables(current)["AzerothCardBinderDB"]);
    const restored = record(parseSavedVariables(backup)["AzerothCardBinderDB"]);
    if (candidate.head.seq !== server.head.seq || candidate.head.hash !== server.head.hash || candidate.tapeNext !== server.tapeNext) return null;
    if (before.head.seq > candidate.head.seq || raw["run"] || restored["run"] || restored["legacy"] === true) return null;
    if (before.head.seq === 0 && (before.head.hash !== "0".repeat(32) || before.events.length > 0)) return null;
    if (before.events.length > 0) {
      const first = before.events[0]!;
      const checked = reference.verifyChain(before.events, { seq: first.seq - 1, hash: first.prev });
      if (!checked.ok || checked.head?.seq !== before.head.seq || checked.head.hash !== before.head.hash) return null;
    }
    if (before.head.seq > 0) {
      const expected = before.head.seq === server.head.seq ? server.head.hash : server.events.find(e => e["seq"] === before.head.seq)?.["h"];
      if (before.head.hash !== expected) return null;
    } else if (Object.keys(before.snapshot.counts).length > 0 || before.snapshot.dust > 0 || Object.keys(record(raw["packs"])).length > 0) return null;
    for (const key of ["counts", "shiny", "packs", "sets"]) if (mapText(restored[key]) !== mapText(server.state[key])) return null;
    if (restored["dust"] !== server.state["dust"] || restored["stateSum"] !== stateSum(restored)) return null;
    if (Number(restored["casualDrops"] ?? 0) !== server.casualDrops) return null;
    if (candidate.mode !== (server.state["mode"] === "casual" ? "casual" : "ranked")) return null;
    const first = candidate.events[0];
    const verified = reference.verifyChain(candidate.events, first ? { seq: first.seq - 1, hash: first.prev } : candidate.head);
    if (!verified.ok || verified.head?.seq !== candidate.head.seq || verified.head.hash !== candidate.head.hash) return null;
    // Refuse even a matching backup if any local inventory, achievement or attempt would be lost.
    for (const field of ["counts", "shiny", "packs", "titles", "sets", "achievements", "attempts", "misses"]) {
      const target = record(restored[field]);
      for (const [key, value] of Object.entries(record(raw[field]))) {
        if (value === true && target[key] !== true) return null;
        if (typeof value === "number" && (typeof target[key] !== "number" || Number(target[key]) < value)) return null;
      }
    }
    for (const field of ["dust", "tradeCount", "casualDrops"]) if (Number(raw[field] ?? 0) > Number(restored[field] ?? 0)) return null;
    // Keep the player's current preferences, wanted list, reports and layout. Progress comes from the verified backup.
    for (const [key, value] of Object.entries(raw)) if (!progressKeys.has(key)) restored[key] = value;
    const text = "AzerothCardBinderDB = " + luaLiteral(restored as LuaValue) + "\n";
    if (readBinder(text).head.hash !== server.head.hash) return null;
    return { path, current, backup, backupPath: path + ".bak", restored: text, head: server.head, tapeNext: server.tapeNext, mode: candidate.mode,
      copies: Object.values(candidate.snapshot.counts).reduce((sum, value) => sum + value, 0) };
  } catch { return null; }
}

// Re-serialize parsed values, never run or copy executable Lua from a saved file into a repair.
export function luaLiteral(value: LuaValue, depth = 0): string {
  if (depth > 64) throw new Error("save nesting is too deep");
  if (value === null) return "nil";
  if (typeof value === "boolean") return String(value);
  if (typeof value === "number") { if (!Number.isFinite(value)) throw new Error("invalid number"); return String(value); }
  if (typeof value === "string") return '"' + [...Buffer.from(value, "utf8")].map(byte =>
    (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || " _.-".includes(String.fromCharCode(byte))
      ? String.fromCharCode(byte) : "\\" + String(byte).padStart(3, "0")).join("") + '"';
  const rows = Array.isArray(value) ? value.map((entry, index) => `[${index + 1}]=${luaLiteral(entry, depth + 1)}`)
    : Object.entries(value).map(([key, entry]) => `[${luaLiteral(key)}]=${luaLiteral(entry, depth + 1)}`);
  return "{" + rows.join(",") + "}";
}

export async function findRecovery(path: string, server: RecoveryServer, additional: string[] = []): Promise<RecoveryPlan | null> {
  let current: string;
  try { current = await readFile(path, "utf8"); } catch { return null; }
  for (const backupPath of [path + ".bak", ...additional]) {
    try {
      const plan = planRecovery(path, current, await readFile(backupPath, "utf8"), server);
      if (plan) return { ...plan, backupPath };
    } catch { /* another saved copy may still be usable */ }
  }
  return null;
}

const backupDirectory = (root: string, account: string) => join(root, hash(account).slice(0, 16));
const backupName = /^\d+-[0-9a-f]{32}\.lua$/;
export async function savedBackups(root: string, account: string): Promise<string[]> {
  const folder = backupDirectory(root, account);
  try { return (await readdir(folder)).filter(name => backupName.test(name))
    .sort((a, b) => Number(b.split("-")[0]) - Number(a.split("-")[0])).map(name => join(folder, name)); }
  catch { return []; }
}

// Local copies are made only after the complete head was acknowledged. No extra server requests.
export async function keepSavedBackup(root: string, account: string, source: string): Promise<void> {
  const { head } = readBinder(source);
  if (head.seq < 1 || !/^[0-9a-f]{32}$/.test(head.hash)) return;
  const folder = backupDirectory(root, account);
  await mkdir(folder, { recursive: true });
  try { await writeFile(join(folder, `${head.seq}-${head.hash}.lua`), source, { encoding: "utf8", flag: "wx" }); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
  // Paths come only from the strict filename filter inside this account's hashed backup directory.
  for (const older of (await savedBackups(root, account)).slice(5)) await unlink(older);
}

export async function restoreRecovery(plan: RecoveryPlan, backupFolder: string, gameClosed: () => Promise<boolean>): Promise<void> {
  if (!(await gameClosed())) throw new Error("Close World of Warcraft before restoring a backup.");
  if (await readFile(plan.path, "utf8") !== plan.current || await readFile(plan.backupPath, "utf8") !== plan.backup) {
    throw new Error("The saved data changed. Check the backup again before restoring.");
  }
  await mkdir(backupFolder, { recursive: true });
  // Exclusive writes retain both originals, and no existing recovery copy is ever overwritten.
  await writeFile(join(backupFolder, basename(plan.path)), plan.current, { encoding: "utf8", flag: "wx" });
  const originalBak = await readFile(plan.path + ".bak", "utf8").catch(() => null);
  if (originalBak !== null) await writeFile(join(backupFolder, basename(plan.path) + ".bak"), originalBak, { encoding: "utf8", flag: "wx" });
  await writeFile(join(backupFolder, "verified-source.lua"), plan.backup, { encoding: "utf8", flag: "wx" });
  if (!(await gameClosed()) || await readFile(plan.path, "utf8") !== plan.current) throw new Error("The game or saved data changed. Nothing was restored.");
  await writeFileAtomic(plan.path, plan.restored);
}
