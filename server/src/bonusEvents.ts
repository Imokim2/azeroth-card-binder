import * as shared from "../../packages/shared/src/bonus-events.js";
import type { Db } from "./db.ts";
import type { Catalog } from "./shared.ts";
import { ApiError } from "./errors.ts";
export type BonusEvent = { id: string; title: string; startsAt: number; endsAt: number; effect: "card-drops"; percent: number; sets: string[] };
export type BonusDefinitions = Record<string, BonusEvent>;
export function bonusDefinition(input: unknown, catalog: Catalog, now: number): BonusEvent {
  let event: BonusEvent;
  try { event = shared.definition(input, catalog) as BonusEvent; } catch (error) { throw new ApiError("bad_request", { field: error instanceof Error ? error.message : "bonus event" }); }
  if (event.startsAt < now || event.startsAt > now + 30 * 86400) throw new ApiError("bad_request", { field: "choose a future start within 30 days" });
  return event;
}
export class SqlBonusEvents {
  readonly db: Db;
  readonly catalog: Catalog;
  constructor(db: Db, catalog: Catalog) { this.db = db; this.catalog = catalog; }
  async schedule(input: unknown, now: number): Promise<BonusEvent> {
    const event = bonusDefinition(input, this.catalog, now);
    const existing = await this.db.all<{ id: string }>("SELECT id FROM bonus_events WHERE id = ?", [event.id]);
    if (existing.length) throw new ApiError("bad_request", { field: "event id is already published; schedules cannot be overwritten" });
    const upcoming = await this.db.all<{ id: string }>("SELECT id FROM bonus_events WHERE ends_at > ? AND starts_at <= ? LIMIT 64", [now, now + 30 * 86400]);
    if (upcoming.length >= 64) throw new ApiError("bad_request", { field: "too many upcoming events" });
    try { await this.db.batch([{ sql: "INSERT INTO bonus_events (id, starts_at, ends_at, definition_json) VALUES (?, ?, ?, ?)", params: [event.id, event.startsAt, event.endsAt, JSON.stringify(event)] }]); }
    catch { throw new ApiError("bad_request", { field: "event id is already published" }); }
    return event;
  }
  async upcoming(now: number): Promise<BonusEvent[]> {
    const rows = await this.db.all<{ definition_json: string }>("SELECT definition_json FROM bonus_events WHERE ends_at > ? AND starts_at <= ? ORDER BY starts_at, id LIMIT 64", [now, now + 30 * 86400]);
    return rows.map(row => shared.definition(JSON.parse(row.definition_json), this.catalog) as BonusEvent);
  }
  async forEvents(events: { kind: string; partner: string; trade: string }[]): Promise<BonusDefinitions> {
    const ids = shared.eventIDs(events) as string[], result: BonusDefinitions = {};
    for (let index = 0; index < ids.length; index += 80) {
      const chunk = ids.slice(index, index + 80);
      const rows = await this.db.all<{ definition_json: string }>(`SELECT definition_json FROM bonus_events WHERE id IN (${chunk.map(() => "?").join(",")})`, chunk);
      for (const row of rows) { const event = shared.definition(JSON.parse(row.definition_json), this.catalog) as BonusEvent; result[event.id] = event; }
    }
    return result;
  }
}
