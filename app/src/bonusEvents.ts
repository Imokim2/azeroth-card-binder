export type BonusEvent = { id: string; title: string; startsAt: number; endsAt: number; effect: "card-drops"; percent: number; sets: string[] };
export type BonusData = { at: number; events: BonusEvent[]; binders: string[] };
// Keep the packaged app self-contained: no runtime import of uncompiled shared JS.
function definition(value: unknown): BonusEvent {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid bonus event");
  const event = value as Record<string, unknown>;
  const { id, title, startsAt, endsAt, percent, sets } = event;
  if (typeof id !== "string" || !/^[a-z0-9][a-z0-9-]{0,31}$/.test(id) || typeof title !== "string" || !title.trim() || new TextEncoder().encode(title).length > 60 || /[|\x00-\x1f\x7f]/.test(title)) throw new Error("invalid bonus text");
  if (typeof startsAt !== "number" || typeof endsAt !== "number" || !Number.isSafeInteger(startsAt) || !Number.isSafeInteger(endsAt) || startsAt < 1 || endsAt > 4102444800 || endsAt-startsAt < 300 || endsAt-startsAt > 86400) throw new Error("invalid bonus window");
  if (event["effect"] !== "card-drops" || typeof percent !== "number" || !Number.isInteger(percent) || percent < 101 || percent > 500) throw new Error("invalid bonus effect");
  if (!Array.isArray(sets) || sets.length > 30 || sets.some(code => typeof code !== "string" || !/^[a-zA-Z0-9_-]{1,20}$/.test(code)) || new Set(sets).size !== sets.length) throw new Error("invalid bonus sets");
  return { id, title: title.trim(), startsAt, endsAt, percent, effect: "card-drops", sets: (sets as string[]).slice().sort() };
}
export function parseBonusData(input: unknown, binders: string[] = []): BonusData {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("invalid event schedule");
  const row = input as Record<string, unknown>;
  if (!Number.isSafeInteger(row["at"]) || Number(row["at"]) < 0 || !Array.isArray(row["events"]) || row["events"].length > 64) throw new Error("invalid event schedule");
  if (binders.length > 100 || binders.some(id => !/^[0-9a-f]{32}$/.test(id))) throw new Error("invalid event pairing");
  const events = row["events"].map(definition);
  if (new Set(events.map(event => event.id)).size !== events.length) throw new Error("duplicate event id");
  return { at: Number(row["at"]), events, binders: [...new Set(binders)] };
}
