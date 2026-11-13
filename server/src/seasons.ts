import type { Db, Statement } from "./db.ts";
import type { Catalog } from "./shared.ts";
import type { LedgerEvent } from "./ledger.ts";
import { packInfo } from "./shared.ts";
import { sha256Hex } from "../../packages/shared/src/crypto.ts";
import { ApiError } from "./errors.ts";

export type SeasonReward = { title: string; packs: { pack: string; count: number }[] };
export type Season = { id: string; title: string; startsAt: number; endsAt: number; cards: string[];
  rewards: { completion: SeasonReward; first: SeasonReward & { places: number } }; selection: Record<string, unknown> };
export type SeasonStatus = Season & { collected: string[]; place: number; completedAt: number; titles: string[] };
export type SeasonSync = { at: number; seasons: SeasonStatus[]; titles: string[]; knownTitles: string[]; grants: { id: string; pack: string }[];
  released: string[] }; // the cards held back for seasons that a season has already released: available for good (docs/proposals/SMALLER-LAUNCH-COLLECTION.md)
type Row = { id: string; title: string; starts_at: number; ends_at: number; cards_json: string; rewards_json: string; selection_json: string };
const unpack = (row: Row): Season => ({ id: row.id, title: row.title, startsAt: row.starts_at, endsAt: row.ends_at,
  cards: JSON.parse(row.cards_json) as string[], rewards: JSON.parse(row.rewards_json) as Season["rewards"], selection: JSON.parse(row.selection_json) as Record<string, unknown> });
const fail = (field: string): never => { throw new ApiError("bad_request", { field }); };
const record = (v: unknown): Record<string, unknown> => v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};
const text = (v: unknown, field: string, max = 70): string => typeof v === "string" && v.length > 0 && v.length <= max && !/[|\x00-\x1f]/.test(v) ? v : fail(field);

// Resolve random selection once, before scheduling. Persist the actual list; clients never reroll it.
export async function seasonDefinition(input: unknown, catalog: Catalog, now: number): Promise<Season> {
  const body = record(input), selection = record(body["selection"]);
  const id = text(body["id"], "id", 40);
  if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) fail("id");
  const title = text(body["title"], "title");
  const startsAt = Number(body["startsAt"]), endsAt = Number(body["endsAt"]);
  if (!Number.isSafeInteger(startsAt) || startsAt < now || !Number.isSafeInteger(endsAt) || endsAt <= startsAt || endsAt - startsAt > 90 * 86400) fail("dates");
  let cards: string[];
  if (selection["mode"] === "manual") {
    if (!Array.isArray(selection["cards"]) || selection["cards"].some(key => typeof key !== "string" || !catalog.cards[key])) fail("cards");
    cards = [...new Set(selection["cards"] as string[])];
    if (cards.length !== (selection["cards"] as unknown[]).length) fail("duplicate cards");
  } else if (selection["mode"] === "random") {
    const seed = text(selection["seed"], "seed"), count = Number(selection["count"]);
    const sets = selection["sets"], rarities = selection["rarities"];
    if (!Array.isArray(sets) || !sets.length || sets.some(code => !catalog.sets.some(set => set.code === code))) fail("sets");
    if (rarities !== undefined && (!Array.isArray(rarities) || rarities.some(r => !["common", "rare", "epic", "legendary"].includes(String(r))))) fail("rarities");
    const pool = Object.entries(catalog.cards).filter(([, card]) => (sets as unknown[]).includes(card.set) && !card.baseKey &&
      (!rarities || (rarities as unknown[]).includes(card.rarity)) && (selection["bossesOnly"] !== true || card.boss));
    if (!Number.isInteger(count) || count < 1 || count > 64 || count > pool.length) fail("count");
    const ranked = await Promise.all(pool.map(async ([key]) => ({ key, hash: await sha256Hex(id + ":" + seed + ":" + key) })));
    ranked.sort((a, b) => a.hash.localeCompare(b.hash) || a.key.localeCompare(b.key));
    cards = ranked.slice(0, count).map(row => row.key);
  } else return fail("selection.mode");
  if (!cards.length || cards.length > 64) fail("cards");
  if (body["expectedCards"] !== undefined && JSON.stringify(body["expectedCards"]) !== JSON.stringify(cards)) fail("preview differs from server catalog");
  const reward = (value: unknown): SeasonReward => {
    const row = record(value), title = row["title"] === undefined || row["title"] === "" ? "" : text(row["title"], "reward title");
    const packs = row["packs"] ?? [];
    if (!Array.isArray(packs) || packs.length > 5) return fail("packs");
    return { title, packs: packs.map(value => {
      const pack = record(value), id = String(pack["pack"]), count = Number(pack["count"]);
      if (!packInfo(catalog, id) || !Number.isInteger(count) || count < 1 || count > 5) return fail("pack reward");
      return { pack: id, count };
    }) };
  };
  const rewards = record(body["rewards"]), first = record(rewards["first"]), places = Number(first["places"] ?? 0);
  if (!Number.isInteger(places) || places < 0 || places > 100) fail("places");
  return { id, title, startsAt, endsAt, cards, selection,
    rewards: { completion: reward(rewards["completion"]), first: { ...reward(first), places } } };
}

// Only fresh, verified acquisitions. Owning a card before the season never creates an entry.
export function seasonalCandidates(events: LedgerEvent[], mode: string): LedgerEvent[] {
  const result: LedgerEvent[] = [];
  for (const event of events) {
    if (event.kind === "mode" && ["casual", "ranked", "ranked2"].includes(event.key)) mode = event.key;
    if (mode === "ranked2" && ((["drop", "packCard"].includes(event.kind) && event.tape > 0) ||
      (event.kind === "tradeIn" && !event.key.startsWith("pack:")))) result.push(event);
  }
  return result;
}

export class SqlSeasons {
  readonly db: Db;
  readonly catalog: Catalog;
  constructor(db: Db, catalog: Catalog) { this.db = db; this.catalog = catalog; }

  async schedule(input: unknown, now: number): Promise<Season> {
    const season = await seasonDefinition(input, this.catalog, now);
    if ((await this.db.all("SELECT id FROM seasons WHERE id = ?", [season.id])).length) fail("season already scheduled");
    const overlapping = await this.db.all("SELECT id FROM seasons WHERE starts_at < ? AND ends_at > ?", [season.endsAt, season.startsAt]);
    if (overlapping.length >= 3) fail("at most three concurrent seasons");
    await this.db.batch([{ sql: "INSERT INTO seasons VALUES (?, ?, ?, ?, ?, ?, ?, ?)", params: [season.id, season.title, season.startsAt, season.endsAt,
      JSON.stringify(season.cards), JSON.stringify(season.rewards), JSON.stringify(season.selection), now] }]);
    return season;
  }

  // The cards held back for seasons that a season has released, and when each was: the start of the first season that features it (an
  // edition counts for its base card). A released card stays available for good, after its season ends too.
  async released(): Promise<Record<string, number>> {
    const released: Record<string, number> = {};
    for (const row of await this.db.all<{ starts_at: number; cards_json: string }>("SELECT starts_at, cards_json FROM seasons")) {
      for (const key of JSON.parse(row.cards_json) as string[]) {
        const base = this.catalog.cards[key]?.baseKey ?? key;
        if (released[base] === undefined || row.starts_at < released[base]) released[base] = row.starts_at;
      }
    }
    return released;
  }

  async list(now = 0): Promise<Season[]> {
    return (await this.db.all<Row>(`SELECT * FROM seasons ORDER BY
      CASE WHEN starts_at <= ? AND ends_at > ? THEN 0 WHEN starts_at > ? THEN 1 ELSE 2 END,
      CASE WHEN starts_at > ? THEN starts_at END ASC, starts_at DESC LIMIT 12`, [now, now, now, now])).map(unpack);
  }

  async collected(season: Season, playerId: string): Promise<string[]> {
    // Require a clean Ranked binder. Incoming trades need both matching halves and no Casual provenance.
    // Pack pulls from a zone with pending/untrusted received packs wait until those trades are verified.
    const rows = await this.db.all<{ card_key: string }>(`SELECT DISTINCT a.card_key FROM season_acquisitions a
      JOIN players p ON p.id = a.player_id JOIN ledger_state l ON l.player_id = p.id
      WHERE a.season_id = ? AND a.player_id = ? AND a.epoch = p.epoch AND p.status = 'active' AND p.archived_from IS NULL
      AND l.casual_drops = 0 AND NOT EXISTS(SELECT 1 FROM flags f WHERE f.player_id = p.id AND f.state = 'open')
      AND (a.kind != 'tradeIn' OR EXISTS(SELECT 1 FROM trades t WHERE t.player_id = p.id AND t.seq = a.seq AND t.state = 'matched'
        AND NOT EXISTS(SELECT 1 FROM trade_taint x WHERE x.player_id = p.id AND x.seq = t.seq)))
      AND (a.kind != 'packCard' OR NOT EXISTS(SELECT 1 FROM trades t WHERE t.player_id = p.id AND t.direction = 'in'
        AND (t.card_key = 'pack:' || a.zone OR t.card_key LIKE 'pack:' || a.zone || ':%')
        AND (t.state != 'matched' OR EXISTS(SELECT 1 FROM trade_taint x WHERE x.player_id = p.id AND x.seq = t.seq))))`,
      [season.id, playerId]);
    return rows.map(row => row.card_key);
  }

  async settle(playerId: string, now: number): Promise<void> {
    const waiting = await this.db.all<Row>(`SELECT DISTINCT s.* FROM seasons s
      JOIN season_acquisitions a ON a.season_id = s.id JOIN players p ON p.id = a.player_id AND p.epoch = a.epoch
      WHERE a.player_id = ? AND NOT EXISTS(SELECT 1 FROM season_completions c WHERE c.season_id = s.id AND c.player_id = a.player_id)
      ORDER BY s.starts_at, s.id`, [playerId]);
    for (const season of waiting.map(unpack)) {
      const have = new Set(await this.collected(season, playerId));
      if (!season.cards.every(key => have.has(key))) continue;
      // SQLite serialises this statement: places are unique even when two completions arrive together.
      await this.db.batch([{ sql: `INSERT OR IGNORE INTO season_completions (season_id, player_id, place, completed_at, titles_json)
        SELECT ?, ?, COALESCE(MAX(place), 0) + 1, ?, '[]' FROM season_completions WHERE season_id = ?`, params: [season.id, playerId, now, season.id] }]);
    }
    await this.rewards(playerId);
  }

  async rewards(playerId: string): Promise<void> {
    const statements: Statement[] = [];
    const rows = await this.db.all<{ season_id: string; place: number }>("SELECT season_id, place FROM season_completions WHERE player_id = ? AND rewards_issued = 0", [playerId]);
    for (const done of rows) {
      const row = (await this.db.all<Row>("SELECT * FROM seasons WHERE id = ?", [done.season_id]))[0];
      if (!row) continue;
      const season = unpack(row), rewards = [season.rewards.completion];
      if (done.place <= season.rewards.first.places) rewards.push(season.rewards.first);
      const titles = rewards.map(r => r.title).filter(Boolean);
      statements.push({ sql: "UPDATE season_completions SET titles_json = ?, rewards_issued = 1 WHERE season_id = ? AND player_id = ?", params: [JSON.stringify(titles), season.id, playerId] });
      let slot = 0;
      for (const reward of rewards) for (const pack of reward.packs) for (let copy = 0; copy < pack.count; copy++) {
        const id = (await sha256Hex(season.id + ":" + playerId + ":" + slot++)).slice(0, 32);
        statements.push({ sql: "INSERT OR IGNORE INTO season_grants VALUES (?, ?, ?, ?)", params: [id, season.id, playerId, pack.pack] });
      }
    }
    if (statements.length) await this.db.batch(statements);
  }

  async sync(playerId: string, now: number): Promise<SeasonSync> {
    await this.settle(playerId, now);
    const seasons: SeasonStatus[] = [];
    for (const season of await this.list(now)) {
      const done = (await this.db.all<{ place: number; completed_at: number; titles_json: string }>(
        "SELECT place, completed_at, titles_json FROM season_completions WHERE season_id = ? AND player_id = ?", [season.id, playerId]))[0];
      seasons.push({ ...season, collected: done ? season.cards : await this.collected(season, playerId), place: done?.place ?? 0,
        completedAt: done?.completed_at ?? 0, titles: done ? JSON.parse(done.titles_json) as string[] : [] });
    }
    const grants = await this.db.all<{ id: string; pack: string }>(`SELECT g.id, g.pack FROM season_grants g
      WHERE g.player_id = ? AND NOT EXISTS(SELECT 1 FROM season_redemptions r WHERE r.grant_id = g.id) ORDER BY g.id LIMIT 100`, [playerId]);
    const titles = (await this.db.all<{ titles_json: string }>("SELECT titles_json FROM season_completions WHERE player_id = ? ORDER BY completed_at DESC LIMIT 500", [playerId]))
      .flatMap(row => JSON.parse(row.titles_json) as string[]);
    const knownTitles = (await this.db.all<{ rewards_json: string }>("SELECT rewards_json FROM seasons ORDER BY starts_at DESC LIMIT 500"))
      .flatMap(row => { const r = JSON.parse(row.rewards_json) as Season["rewards"]; return [r.completion.title, r.first.title].filter(Boolean); });
    const releasedAt = await this.released();
    const released = Object.keys(releasedAt).filter(key => (releasedAt[key] as number) <= now && this.catalog.cards[key]?.seasonal).sort();
    return { at: now, seasons, grants, titles: [...new Set(titles)], knownTitles: [...new Set(knownTitles)], released };
  }

  async checkGrants(playerId: string, events: LedgerEvent[]): Promise<boolean> {
    for (const event of events) if (event.kind === "seasonReward") {
      const rows = await this.db.all("SELECT 1 FROM season_grants g WHERE g.id = ? AND g.player_id = ? AND g.pack = ? AND NOT EXISTS(SELECT 1 FROM season_redemptions r WHERE r.grant_id = g.id)", [event.trade, playerId, event.key]);
      if (!rows.length) return false;
    }
    return true;
  }

  async settlePending(now: number): Promise<void> {
    const rows = await this.db.all<{ player_id: string }>(`SELECT DISTINCT a.player_id FROM season_acquisitions a
      WHERE NOT EXISTS(SELECT 1 FROM season_completions c WHERE c.season_id = a.season_id AND c.player_id = a.player_id)
      AND a.season_id IN (SELECT id FROM seasons WHERE ends_at > ?) LIMIT 200`, [now - 7 * 86400]);
    for (const row of rows) await this.settle(row.player_id, now);
  }
}
