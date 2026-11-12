// Read only display data from the last generated Sync.lua, without executing Lua.
// This keeps the last leaderboard visible across companion restarts without polling.
import { parseSavedVariables } from "./luaTable.ts";
import { syncFileText } from "./syncFile.ts";
import type { Standings } from "./client.ts";

export function cachedStandings(text: string): Standings | undefined {
  try {
    const source = text.replace(/^local _, ACB = \.\.\.\s*/, "").replace(/^ACB\.sync\s*=/m, "SavedSync =");
    const value = parseSavedVariables(source)["SavedSync"];
    if (!value || typeof value !== "object" || Array.isArray(value)) return;
    const data = value as Record<string, unknown>;
    if (!Array.isArray(data["leaderboard"]) || !Array.isArray(data["firsts"]) || !data["verified"] || typeof data["verified"] !== "object") return;
    const result: Standings = {
      leaderboard: data["leaderboard"] as Standings["leaderboard"],
      firsts: (data["firsts"] as Record<string, unknown>[]).map(row => ({ setCode: row["set"] as string, title: row["title"] as string, by: row["by"] as string, at: row["at"] as number })),
      verified: Object.entries(data["verified"] as Record<string, unknown>).filter(([, flag]) => flag === true).map(([name]) => name),
      you: (data["you"] ?? null) as Standings["you"],
    };
    // Reuse the writer's complete length, type and escaping checks. Invalid cache data is discarded.
    syncFileText({ syncedAt: 0, acks: [], ...result });
    return result;
  } catch { return; }
}
