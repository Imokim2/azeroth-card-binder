// Reports from one player about another (a suspected cheat, a trade that went wrong). A report is a note for a person to
// read: several different players reporting the same player opens a review flag, and that is all it ever does by itself.
// Nothing here hides anyone from the ladder, so a handful of accounts cannot push a rival off it by reporting them.
import { ApiError } from "./errors.ts";
import { newId } from "../../packages/shared/src/crypto.ts";
import { peerName } from "./names.ts";
import type { Player, ReportStore, TradeStore } from "./store.ts";

export const REPORT_REASONS = ["cheating", "trading", "other"] as const;
export const MAX_REPORTS_PER_REQUEST = 10;
export const MAX_REPORTS_PER_DAY = 20; // by one player
export const REPORTS_TO_OPEN_A_FLAG = 3; // different players, within a week
const DAY = 86_400;
const WEEK = 7 * DAY;

export type ReportInput = { token: string; target: string; reason: (typeof REPORT_REASONS)[number]; note: string };

// The reports in a request, checked. Anything that is not exactly the expected shape refuses the whole request.
export function parseReports(value: unknown): ReportInput[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_REPORTS_PER_REQUEST) throw new ApiError("bad_request", { field: "reports" });
  const seen = new Set<string>();
  return value.map((item) => {
    const entry = (typeof item === "object" && item !== null ? item : {}) as Record<string, unknown>;
    const { token, target, reason, note } = entry;
    if (typeof token !== "string" || !/^[0-9a-z]{6,40}$/.test(token) || seen.has(token)) throw new ApiError("bad_request", { field: "token" });
    seen.add(token);
    // A character as the add-on names them to each other: name-realmname, lower case, nothing that could be markup or a separator.
    if (typeof target !== "string" || target.length > 80 || !/^[^\s|,<>&"'`]{1,40}-[^\s|,<>&"'`]{1,40}$/.test(target)) throw new ApiError("bad_request", { field: "target" });
    if (!REPORT_REASONS.includes(reason as never)) throw new ApiError("bad_request", { field: "reason" });
    if (typeof note !== "string" || note.length > 120 || /[\u0000-\u001f]/.test(note)) throw new ApiError("bad_request", { field: "note" });
    return { token, target: peerName(target), reason: reason as ReportInput["reason"], note: note.trim() };
  });
}

// Store the reports of one player. Returns the tokens that are settled (stored, repeated, or about themselves), so the
// companion app can tell the add-on to forget them; a report left out because the player has reached today's limit is not settled.
export async function acceptReports(
  deps: { reports: ReportStore; trades: TradeStore; now: () => number },
  reporter: Player,
  reports: ReportInput[],
): Promise<{ done: string[]; stored: number }> {
  const now = deps.now();
  const done: string[] = [];
  let stored = 0;
  let today = await deps.reports.countSince(reporter.id, now - DAY);
  for (const report of reports) {
    const target = await deps.reports.playerOfCharacter(report.target);
    if (target === reporter.id) { done.push(report.token); continue; } // reporting yourself says nothing
    if (today >= MAX_REPORTS_PER_DAY) break;
    const result = await deps.reports.add({
      id: newId(now * 1000), reporterId: reporter.id, token: report.token, targetName: report.target, targetId: target,
      reason: report.reason, note: report.note, createdAt: now,
    }, now - DAY);
    done.push(report.token);
    if (result === "duplicate") continue;
    stored++;
    today++;
    if (target) {
      const reporters = await deps.reports.reportersOf(target, now - WEEK);
      if (reporters >= REPORTS_TO_OPEN_A_FLAG && !(await deps.reports.hasOpenFlag(target, "reported"))) {
        await deps.trades.addFlag(target, { id: newId(now * 1000), kind: "reported", notes: `${reporters} players reported them` }, now);
      }
    }
  }
  return { done, stored };
}
