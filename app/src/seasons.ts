// Keep seasonal data bounded and declarative before it reaches executable Sync.lua.
export type SeasonReward = { title: string; packs: { pack: string; count: number }[] };
export type SeasonData = { at: number; binders: string[]; titles: string[]; knownTitles: string[]; seasons: {
  id: string; title: string; startsAt: number; endsAt: number; cards: string[]; collected: string[];
  place: number; completedAt: number; titles: string[];
  rewards: { completion: SeasonReward; first: SeasonReward & { places: number } };
}[]; grants: { id: string; pack: string }[]; released: string[] };
const row = (v: unknown): Record<string, unknown> => v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};
const whole = (v: unknown) => { if (!Number.isSafeInteger(v) || Number(v) < 0) throw new Error("invalid seasonal number"); return Number(v); };
const text = (v: unknown) => { if (typeof v !== "string" || v.length > 80) throw new Error("invalid seasonal text"); return v; };
const list = (v: unknown, max: number) => { if (!Array.isArray(v) || v.length > max) throw new Error("invalid seasonal list"); return v as unknown[]; };
const card = (v: unknown) => { const s = text(v); if (!/^(npc|node|edition):\d{1,9}$/.test(s)) throw new Error("invalid seasonal card"); return s; };
const pack = (v: unknown) => { const s = text(v); if (!/^[A-Z][A-Z0-9]*(?::(?:common|rare))?$/.test(s)) throw new Error("invalid seasonal pack"); return s; };
const token = (v: unknown) => { const s = text(v); if (!/^[0-9a-f]{32}$/.test(s)) throw new Error("invalid seasonal token"); return s; };

export function parseSeasonData(input: unknown, binders: string[] = []): SeasonData {
  const data = row(input);
  const reward = (v: unknown): SeasonReward => {
    const r = row(v);
    return { title: text(r["title"]), packs: list(r["packs"], 5).map(v => {
      const p = row(v), count = whole(p["count"]);
      if (count < 1 || count > 5) throw new Error("invalid seasonal pack count");
      return { pack: pack(p["pack"]), count };
    }) };
  };
  return { at: whole(data["at"]), binders: list(binders, 100).map(token), titles: list(data["titles"] ?? [], 1000).map(text),
    knownTitles: list(data["knownTitles"] ?? [], 1000).map(text), seasons: list(data["seasons"], 12).map(v => {
    const s = row(v), r = row(s["rewards"]), first = row(r["first"]), id = text(s["id"]);
    if (!/^[a-z0-9][a-z0-9-]{0,39}$/.test(id)) throw new Error("invalid season id");
    const startsAt = whole(s["startsAt"]), endsAt = whole(s["endsAt"]), places = whole(first["places"]);
    const cards = list(s["cards"], 64).map(card), collected = list(s["collected"], 64).map(card);
    if (!cards.length || startsAt >= endsAt || places > 100 || collected.some(k => !cards.includes(k))) throw new Error("invalid season");
    return { id, title: text(s["title"]), startsAt, endsAt, cards, collected, place: whole(s["place"]), completedAt: whole(s["completedAt"]),
      titles: list(s["titles"], 2).map(text), rewards: { completion: reward(r["completion"]), first: { ...reward(first), places } } };
  }), grants: list(data["grants"], 100).map(v => { const g = row(v); return { id: token(g["id"]), pack: pack(g["pack"]) }; }),
    // The cards held back for seasons that are available now (a season released them). Old servers send none.
    released: list(data["released"] ?? [], 2000).map(card) };
}
