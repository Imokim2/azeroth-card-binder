// The three stores (store.ts) on top of any SQL database that speaks SQLite's dialect: Cloudflare D1 in production,
// SQLite in tests. The schema is in migrations/. Whole uploads are written with one transaction.
import type { Db, Statement } from "./db.ts";
import { GENESIS } from "./ledger.ts";
import { gzip } from "./gzip.ts";
import { newState } from "./shared.ts";
import type { LedgerState } from "./shared.ts";
import { StoreConflict } from "./store.ts";
import { peerName } from "./names.ts";
import type { BoardEntry, Commit, IngestStore, IssuedTape, LeaderboardStore, Player, PlayerStore, StoredLedger, TapeStore, TradeStore, Visibility } from "./store.ts";
import type { AdminPlayerDetail, AdminPlayerRow, AdminStore, AuditEntry, Derived, FlagRecord, ModerationStore, RebuildStore, ReportRecord, ReportStore, WantedEntry, WantedStore } from "./store.ts";
import type { LedgerEvent } from "./ledger.ts";
import { gunzip } from "./gzip.ts";

type PlayerRow = { id: string; discord_id: string | null; status: "active" | "banned"; visibility: Visibility; created_at: number; epoch: number; reset_at: number | null; barred_before: number | null };

const toPlayer = (row: PlayerRow): Player => ({
  id: row.id, discordId: row.discord_id, status: row.status, visibility: row.visibility, createdAt: row.created_at, epoch: row.epoch, resetAt: row.reset_at, barredBefore: row.barred_before,
});

// A key that already belongs to another account, or one that was revoked and can never be used again.
export class KeyUnavailable extends Error {}

const PLAYER_COLUMNS = "p.id, p.discord_id, p.status, p.visibility, p.created_at, p.epoch, p.reset_at, p.barred_before";

// What belongs to one binder and moves with it when the binder is archived or restored.
const BINDER_TABLES = ["batches", "drops", "ledger_state", "scores", "characters", "tapes", "flags", "trades", "set_completions", "trade_taint"];

export class SqlStore implements PlayerStore, IngestStore, LeaderboardStore, TapeStore, TradeStore, ModerationStore, RebuildStore, WantedStore, ReportStore, AdminStore {
  readonly #db: Db;
  constructor(db: Db) {
    this.#db = db;
  }

  async findByActiveKey(key: string): Promise<Player | null> {
    const rows = await this.#db.all<PlayerRow>(
      `SELECT ${PLAYER_COLUMNS} FROM keys k JOIN players p ON p.id = k.player_id WHERE k.public_key = ? AND k.status = 'active'`, [key]);
    return rows[0] ? toPlayer(rows[0]) : null;
  }

  async findById(id: string): Promise<Player | null> {
    const rows = await this.#db.all<PlayerRow>(`SELECT ${PLAYER_COLUMNS} FROM players p WHERE p.id = ?`, [id]);
    return rows[0] ? toPlayer(rows[0]) : null;
  }

  async registerKey(input: { discordId: string; key: string; visibility: Visibility; at: number; newPlayerId: string }): Promise<Player> {
    const known = await this.#db.all<{ player_id: string; status: string; discord_id: string | null }>(
      "SELECT k.player_id, k.status, p.discord_id FROM keys k JOIN players p ON p.id = k.player_id WHERE k.public_key = ?", [input.key]);
    const existing = known[0];
    if (existing) {
      if (existing.discord_id !== input.discordId || existing.status !== "active") throw new KeyUnavailable("key unavailable");
      const same = await this.findById(existing.player_id);
      if (same) return same;
    }
    const owner = await this.#db.all<PlayerRow>(`SELECT ${PLAYER_COLUMNS} FROM players p WHERE p.discord_id = ?`, [input.discordId]);
    const statements: Statement[] = [];
    let id = input.newPlayerId;
    if (owner[0]) {
      id = owner[0].id;
      // A new key replaces the old ones; the player and the ledger stay.
      statements.push({ sql: "UPDATE keys SET status = 'revoked' WHERE player_id = ? AND status = 'active'", params: [id] });
      statements.push({ sql: "UPDATE players SET visibility = ? WHERE id = ?", params: [input.visibility, id] });
    } else {
      statements.push({
        sql: "INSERT INTO players (id, discord_id, created_at, status, visibility) VALUES (?, ?, ?, 'active', ?)",
        params: [id, input.discordId, input.at, input.visibility],
      });
    }
    statements.push({ sql: "INSERT INTO keys (public_key, player_id, status, created_at) VALUES (?, ?, 'active', ?)", params: [input.key, id, input.at] });
    await this.#db.batch(statements);
    const created = await this.findById(id);
    if (!created) throw new Error("player was not stored");
    return created;
  }

  async characters(playerId: string): Promise<{ name: string; realm: string }[]> {
    return this.#db.all<{ name: string; realm: string }>(
      "SELECT name, realm FROM characters WHERE player_id = ? ORDER BY last_seen DESC, name, realm", [playerId]);
  }

  async exportPlayer(playerId: string): Promise<Record<string, unknown> | null> {
    const account = (await this.#db.all<{ id: string; discord_id: string | null; created_at: number; status: string; visibility: string; epoch: number }>(
      "SELECT id, discord_id, created_at, status, visibility, epoch FROM players WHERE id = ?", [playerId]))[0];
    if (!account) return null;
    const archives = await this.#db.all<{ id: string }>("SELECT id FROM players WHERE archived_from = ? ORDER BY created_at, id", [playerId]);
    const binder = async (id: string, archived: boolean) => {
      const where = "WHERE player_id = ?";
      const events = (await this.batchesOf(id)).flatMap((batch) => batch.events);
      const state = (await this.#db.all<{ head_seq: number; head_hash: string; state_json: string; tape_next: number; casual_drops: number; updated_at: number }>(
        `SELECT head_seq, head_hash, state_json, tape_next, casual_drops, updated_at FROM ledger_state ${where}`, [id]))[0];
      const row = (sql: string) => this.#db.all<Record<string, unknown>>(sql, [id]);
      return {
        binderId: id, archived, events,
        saved: state ? { headSeq: state.head_seq, headHash: state.head_hash, state: JSON.parse(state.state_json) as unknown, tapeNext: state.tape_next, casualDrops: state.casual_drops, updatedAt: state.updated_at } : null,
        score: (await row(`SELECT display_name AS displayName, score AS scoreTenths, unique_cards AS uniqueCards, sets_done AS setsDone, attempts, updated_at AS updatedAt FROM scores ${where}`))[0] ?? null,
        trades: await row(`SELECT seq, trade_id AS tradeId, direction, card_key AS card, char AS character, partner, t, received_at AS receivedAt, state FROM trades ${where} ORDER BY seq`),
        completedSets: await row(`SELECT set_code AS setCode, t, received_at AS receivedAt FROM set_completions ${where} ORDER BY set_code`),
        wanted: await row(`SELECT card_key AS card, added_at AS addedAt FROM wanted ${where} ORDER BY card_key`),
        flags: await row(`SELECT kind, state, created_at AS createdAt, reviewed_at AS reviewedAt FROM flags ${where} ORDER BY created_at`),
        tapeRanges: await row(`SELECT start_idx AS first, end_idx AS last, commitment, issued_at AS issuedAt FROM tapes ${where} ORDER BY start_idx`),
      };
    };
    return {
      account: { playerId: account.id, discordId: account.discord_id, createdAt: account.created_at, status: account.status, visibility: account.visibility, epoch: account.epoch },
      keys: await this.#db.all("SELECT public_key AS publicKey, status, created_at AS createdAt FROM keys WHERE player_id = ? ORDER BY created_at", [playerId]),
      characters: await this.#db.all("SELECT name, realm, first_seen AS firstSeen, last_seen AS lastSeen FROM characters WHERE player_id = ? ORDER BY name, realm", [playerId]),
      binders: [await binder(playerId, false), ...(await Promise.all(archives.map((archive) => binder(archive.id, true))))],
      reportsSent: await this.#db.all("SELECT target_name AS targetName, reason, note, created_at AS createdAt FROM reports WHERE reporter_id = ? ORDER BY created_at", [playerId]),
      seasonal: {
        acquisitions: await this.#db.all("SELECT * FROM season_acquisitions WHERE player_id = ?", [playerId]),
        completions: await this.#db.all("SELECT * FROM season_completions WHERE player_id = ?", [playerId]),
        grants: await this.#db.all("SELECT * FROM season_grants WHERE player_id = ?", [playerId]),
        redemptions: await this.#db.all("SELECT * FROM season_redemptions WHERE player_id = ?", [playerId]),
      },
    };
  }

  async resetBinder(playerId: string, archivedId: string, at: number): Promise<void> {
    const found = await this.findById(playerId);
    if (!found) throw new Error("no such player");
    // The old record moves to a private player of its own with no Discord link and no key, so it can never be listed or
    // uploaded to; the player keeps their keys and begins again with an empty chain.
    const moved = BINDER_TABLES;
    await this.#db.batch([
      {
        sql: "INSERT INTO players (id, discord_id, created_at, status, visibility, epoch, reset_at, archived_from) VALUES (?, NULL, ?, 'active', 'private', ?, NULL, ?)",
        params: [archivedId, found.createdAt, found.epoch, playerId],
      },
      ...moved.map((table) => ({ sql: `UPDATE ${table} SET player_id = ? WHERE player_id = ?`, params: [archivedId, playerId] })),
      { sql: "UPDATE players SET epoch = epoch + 1, reset_at = ? WHERE id = ?", params: [at, playerId] },
    ]);
  }

  async deletePlayer(playerId: string): Promise<void> {
    const archives = await this.#db.all<{ id: string }>("SELECT id FROM players WHERE archived_from = ?", [playerId]);
    const ids = [playerId, ...archives.map((row) => row.id)];
    const marks = ids.map(() => "?").join(", ");
    // Children before parents, so nothing is left pointing at a player that is gone.
    const tables = ["wanted", "trade_taint", "trades", "set_completions", "flags", "drops", "batches", "tapes", "characters", "scores", "ledger_state", "keys"];
    await this.#db.batch([
      // Reports the player sent and reports about them, before the player they point at goes.
      { sql: `DELETE FROM reports WHERE reporter_id IN (${marks}) OR target_id IN (${marks})`, params: [...ids, ...ids] },
      ...tables.map((table) => ({ sql: `DELETE FROM ${table} WHERE player_id IN (${marks})`, params: ids })),
      { sql: `DELETE FROM players WHERE id IN (${marks})`, params: ids },
    ]);
  }

  async load(playerId: string): Promise<StoredLedger> {
    const rows = await this.#db.all<{ head_seq: number; head_hash: string; state_json: string; tape_next: number; pity_json: string; drops_json: string; updated_at: number }>(
      "SELECT head_seq, head_hash, state_json, tape_next, pity_json, drops_json, updated_at FROM ledger_state WHERE player_id = ?", [playerId]);
    const flags = await this.#db.all<{ kind: string }>("SELECT DISTINCT kind FROM flags WHERE player_id = ? AND state != 'cleared'", [playerId]);
    const openFlags = flags.map((flag) => flag.kind);
    // Luck that a reviewer has already looked at and cleared: only clearly more than that is flagged again.
    const cleared = await this.#db.all<{ notes: string }>("SELECT notes FROM flags WHERE player_id = ? AND state = 'cleared' AND kind IN ('luck-review', 'luck-hold')", [playerId]);
    const clearedLuck = Math.max(0, ...cleared.map((flag) => Number(/luck ([\d.]+)/.exec(flag.notes)?.[1] ?? 0)));
    const row = rows[0];
    if (!row) return { head: { seq: 0, hash: GENESIS }, state: newState(), pity: {}, tapeNext: 1, drops: {}, lastUpload: null, openFlags, clearedLuck };
    return {
      head: { seq: row.head_seq, hash: row.head_hash }, state: JSON.parse(row.state_json) as LedgerState,
      pity: JSON.parse(row.pity_json) as Record<string, number>, tapeNext: row.tape_next,
      drops: JSON.parse(row.drops_json) as Record<string, number>, lastUpload: row.updated_at, openFlags, clearedLuck,
    };
  }

  async noteTapeNext(playerId: string, tapeNext: number, at: number): Promise<void> {
    await this.#db.batch([{
      sql: `INSERT INTO ledger_state (player_id, head_seq, head_hash, state_json, updated_at, tape_next) VALUES (?, 0, ?, ?, ?, ?)
            ON CONFLICT (player_id) DO UPDATE SET tape_next = MAX(ledger_state.tape_next, excluded.tape_next),
            updated_at = excluded.updated_at`,
      params: [playerId, GENESIS, JSON.stringify(newState()), at, tapeNext],
    }]);
  }

  async findBatch(playerId: string, firstSeq: number, lastSeq: number): Promise<{ lastHash: string } | null> {
    const rows = await this.#db.all<{ last_hash: string }>(
      "SELECT last_hash FROM batches WHERE player_id = ? AND first_seq = ? AND last_seq = ?", [playerId, firstSeq, lastSeq]);
    return rows[0] ? { lastHash: rows[0].last_hash } : null;
  }

  async commit(playerId: string, commit: Commit): Promise<void> {
    const first = commit.events[0];
    const last = commit.events[commit.events.length - 1];
    if (!first || !last) throw new Error("commit needs at least one event");
    const statements: Statement[] = [
      {
        // Two uploads racing for the same position collide here and the second one fails whole.
        sql: "INSERT INTO batches (player_id, first_seq, last_seq, last_hash, events_gzip, received_at) VALUES (?, ?, ?, ?, ?, ?)",
        params: [playerId, first.seq, last.seq, last.h, await gzip(JSON.stringify(commit.events)), commit.receivedAt],
      },
    ];
    for (const { event, zone } of commit.seasonal?.cards ?? []) {
      statements.push({ sql: `INSERT OR IGNORE INTO season_acquisitions (season_id, player_id, epoch, seq, card_key, zone, kind, received_at)
        SELECT s.id, ?, ?, ?, ?, ?, ?, ? FROM seasons s
        WHERE s.starts_at <= ? AND s.ends_at > ? AND s.starts_at <= ? AND s.ends_at > ?
        AND EXISTS(SELECT 1 FROM json_each(s.cards_json) c WHERE c.value = ?)`,
        params: [playerId, commit.seasonal!.epoch, event.seq, event.key, zone, event.kind, commit.receivedAt,
          event.t, event.t, commit.receivedAt, commit.receivedAt, event.key] });
    }
    for (const event of commit.events) if (event.kind === "seasonReward") {
      statements.push({ sql: "INSERT INTO season_redemptions (grant_id, player_id, seq) VALUES (?, ?, ?)", params: [event.trade, playerId, event.seq] });
    }
    // Drops are small rows for fast queries. A statement may bind at most 100 values, so 16 rows of 6 per statement.
    const drops = commit.events.filter((event) => event.kind === "drop");
    for (let from = 0; from < drops.length; from += 16) {
      const group = drops.slice(from, from + 16);
      statements.push({
        sql: "INSERT INTO drops (player_id, seq, card_key, t, shiny, tape_idx) VALUES " + group.map(() => "(?, ?, ?, ?, ?, ?)").join(", "),
        params: group.flatMap((event) => [playerId, event.seq, event.key, event.t, event.shiny, event.tape]),
      });
    }
    statements.push({
      sql: `INSERT INTO ledger_state (player_id, head_seq, head_hash, state_json, updated_at, tape_next, pity_json, drops_json, casual_drops)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (player_id) DO UPDATE SET head_seq = excluded.head_seq, head_hash = excluded.head_hash,
            state_json = excluded.state_json, updated_at = excluded.updated_at, tape_next = excluded.tape_next,
            pity_json = excluded.pity_json, drops_json = excluded.drops_json,
            casual_drops = ledger_state.casual_drops + excluded.casual_drops`,
      params: [playerId, commit.head.seq, commit.head.hash, JSON.stringify(commit.state), commit.receivedAt, commit.tapeNext,
        JSON.stringify(commit.pity), JSON.stringify(commit.drops), commit.casualDrops],
    });
    const score = commit.score;
    statements.push({
      sql: `INSERT INTO scores (player_id, display_name, score, unique_cards, sets_done, attempts, rules_version, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (player_id) DO UPDATE SET display_name = excluded.display_name, score = excluded.score,
            unique_cards = excluded.unique_cards, sets_done = excluded.sets_done, attempts = excluded.attempts,
            rules_version = excluded.rules_version, updated_at = excluded.updated_at`,
      params: [playerId, score.displayName, score.score, score.uniqueCards, score.setsDone, score.attempts, score.rulesVersion, commit.receivedAt],
    });
    statements.push({
      sql: `INSERT INTO characters (player_id, name, realm, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (player_id, name, realm) DO UPDATE SET last_seen = excluded.last_seen`,
      params: [playerId, commit.character.name, commit.character.realm, commit.receivedAt, commit.receivedAt],
    });
    for (const flag of commit.flags) {
      statements.push({
        sql: "INSERT INTO flags (id, player_id, kind, notes, created_at) VALUES (?, ?, ?, ?, ?)",
        params: [flag.id, playerId, flag.kind, flag.notes, commit.receivedAt],
      });
    }
    // Trade halves, ten rows to a statement (a statement may bind at most 100 values).
    for (let from = 0; from < commit.trades.length; from += 10) {
      const group = commit.trades.slice(from, from + 10);
      statements.push({
        sql: "INSERT INTO trades (player_id, seq, trade_id, direction, card_key, char, partner, t, received_at) VALUES " + group.map(() => "(?, ?, ?, ?, ?, ?, ?, ?, ?)").join(", "),
        params: group.flatMap((row) => [playerId, row.seq, row.tradeId, row.direction, row.key, row.char, row.partner, row.t, commit.receivedAt]),
      });
    }
    for (const done of commit.completions) {
      statements.push({
        sql: "INSERT OR IGNORE INTO set_completions (set_code, player_id, t, received_at) VALUES (?, ?, ?, ?)",
        params: [done.setCode, playerId, done.t, commit.receivedAt],
      });
    }
    try {
      await this.#db.batch(statements);
    } catch (error) {
      if (error instanceof Error && /UNIQUE constraint failed: batches|batches\.player_id/i.test(error.message)) {
        throw new StoreConflict("another upload for this player was stored first");
      }
      throw error;
    }
  }

  async issuedEnd(playerId: string): Promise<number> {
    const rows = await this.#db.all<{ last: number | null }>("SELECT MAX(end_idx) AS last FROM tapes WHERE player_id = ?", [playerId]);
    return rows[0]?.last ?? 0;
  }

  async tapeNext(playerId: string): Promise<number> {
    const rows = await this.#db.all<{ tape_next: number }>("SELECT tape_next FROM ledger_state WHERE player_id = ?", [playerId]);
    return rows[0]?.tape_next ?? 1;
  }

  async recordIssue(playerId: string, issued: IssuedTape, at: number): Promise<void> {
    await this.#db.batch([{
      sql: "INSERT INTO tapes (player_id, start_idx, end_idx, commitment, issued_at) VALUES (?, ?, ?, ?, ?)",
      params: [playerId, issued.start, issued.end, issued.commitment, at],
    }]);
  }

  async flags(state: FlagRecord["state"] | "all", limit: number): Promise<FlagRecord[]> {
    const rows = await this.#db.all<{
      id: string; player_id: string; display_name: string | null; kind: string; state: FlagRecord["state"]; notes: string;
      created_at: number; reviewed_at: number | null; review_note: string;
    }>(
      `SELECT f.id, f.player_id, s.display_name, f.kind, f.state, f.notes, f.created_at, f.reviewed_at, f.review_note
       FROM flags f LEFT JOIN scores s ON s.player_id = f.player_id
       WHERE (? = 'all' OR f.state = ?) ORDER BY f.created_at ASC, f.id ASC LIMIT ?`, [state, state, limit]);
    return rows.map((row) => ({
      id: row.id, playerId: row.player_id, displayName: row.display_name ?? "", kind: row.kind, state: row.state, notes: row.notes,
      createdAt: row.created_at, reviewedAt: row.reviewed_at, reviewNote: row.review_note,
    }));
  }

  async review(id: string, state: "cleared" | "confirmed", note: string, at: number): Promise<boolean> {
    const found = await this.#db.all<{ id: string }>("SELECT id FROM flags WHERE id = ?", [id]);
    if (!found[0]) return false;
    await this.#db.batch([{ sql: "UPDATE flags SET state = ?, review_note = ?, reviewed_at = ? WHERE id = ?", params: [state, note, at, id] }]);
    return true;
  }

  async setBanned(playerId: string, banned: boolean): Promise<boolean> {
    const found = await this.#db.all<{ id: string }>("SELECT id FROM players WHERE id = ?", [playerId]);
    if (!found[0]) return false;
    await this.#db.batch([{ sql: "UPDATE players SET status = ? WHERE id = ?", params: [banned ? "banned" : "active", playerId] }]);
    return true;
  }

  async setWanted(playerId: string, cards: string[], at: number): Promise<void> {
    const statements: Statement[] = [{ sql: "DELETE FROM wanted WHERE player_id = ?", params: [playerId] }];
    for (let from = 0; from < cards.length; from += 30) {
      const group = cards.slice(from, from + 30);
      statements.push({ sql: "INSERT INTO wanted (player_id, card_key, added_at) VALUES " + group.map(() => "(?, ?, ?)").join(", "), params: group.flatMap((key) => [playerId, key, at]) });
    }
    await this.#db.batch(statements);
  }

  async board(limit: number): Promise<WantedEntry[]> {
    const players = await this.#db.all<{ id: string; updated: number }>(
      `SELECT p.id AS id, MAX(w.added_at) AS updated FROM players p JOIN wanted w ON w.player_id = p.id
       WHERE p.visibility = 'public' AND p.status = 'active' GROUP BY p.id ORDER BY updated DESC, p.id ASC LIMIT ?`, [limit]);
    if (players.length === 0) return [];
    const ids = players.map((row) => row.id);
    const marks = ids.map(() => "?").join(", ");
    const cards = await this.#db.all<{ player_id: string; card_key: string }>(`SELECT player_id, card_key FROM wanted WHERE player_id IN (${marks}) ORDER BY card_key`, ids);
    const names = await this.#db.all<{ player_id: string; name: string; realm: string }>(`SELECT player_id, name, realm FROM characters WHERE player_id IN (${marks}) ORDER BY last_seen DESC, name`, ids);
    const entries: WantedEntry[] = [];
    for (const row of players) {
      const own = names.filter((name) => name.player_id === row.id);
      const first = own[0];
      if (!first) continue; // nobody to trade with by name yet
      entries.push({
        playerId: row.id, displayName: `${first.name}-${first.realm}`, characters: own.map((name) => peerName(name.name, name.realm)),
        cards: cards.filter((card) => card.player_id === row.id).map((card) => card.card_key), updatedAt: row.updated,
      });
    }
    return entries;
  }

  async playerOfCharacter(peer: string): Promise<string | null> {
    const rows = await this.#db.all<{ player_id: string }>(
      `SELECT c.player_id FROM characters c JOIN players p ON p.id = c.player_id
       WHERE p.archived_from IS NULL AND lower(c.name) || '-' || lower(replace(replace(replace(c.realm, ' ', ''), '''', ''), '-', '')) = ?
       ORDER BY c.last_seen DESC LIMIT 1`, [peer]);
    return rows[0]?.player_id ?? null;
  }

  async add(report: ReportRecord, since: number): Promise<"stored" | "duplicate"> {
    const repeated = await this.#db.all<{ n: number }>(
      `SELECT COUNT(*) AS n FROM reports WHERE reporter_id = ? AND (token = ? OR (target_name = ? AND created_at > ?))`,
      [report.reporterId, report.token, report.targetName, since]);
    if ((repeated[0]?.n ?? 0) > 0) return "duplicate";
    await this.#db.batch([{
      sql: "INSERT INTO reports (id, reporter_id, token, target_name, target_id, reason, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      params: [report.id, report.reporterId, report.token, report.targetName, report.targetId, report.reason, report.note, report.createdAt],
    }]);
    return "stored";
  }

  async countSince(reporterId: string, since: number): Promise<number> {
    const rows = await this.#db.all<{ n: number }>("SELECT COUNT(*) AS n FROM reports WHERE reporter_id = ? AND created_at > ?", [reporterId, since]);
    return rows[0]?.n ?? 0;
  }

  async reportersOf(targetId: string, since: number): Promise<number> {
    const rows = await this.#db.all<{ n: number }>("SELECT COUNT(DISTINCT reporter_id) AS n FROM reports WHERE target_id = ? AND created_at > ?", [targetId, since]);
    return rows[0]?.n ?? 0;
  }

  async hasOpenFlag(playerId: string, kind: string): Promise<boolean> {
    const rows = await this.#db.all<{ n: number }>("SELECT COUNT(*) AS n FROM flags WHERE player_id = ? AND kind = ? AND state = 'open'", [playerId, kind]);
    return (rows[0]?.n ?? 0) > 0;
  }

  async about(targetId: string, limit: number): Promise<ReportRecord[]> {
    const rows = await this.#db.all<{ id: string; reporter_id: string; token: string; target_name: string; target_id: string | null; reason: string; note: string; created_at: number }>(
      "SELECT id, reporter_id, token, target_name, target_id, reason, note, created_at FROM reports WHERE target_id = ? ORDER BY created_at DESC LIMIT ?", [targetId, limit]);
    return rows.map((row) => ({ id: row.id, reporterId: row.reporter_id, token: row.token, targetName: row.target_name, targetId: row.target_id, reason: row.reason, note: row.note, createdAt: row.created_at }));
  }

  async playerIds(after: string | null, limit: number): Promise<string[]> {
    const rows = await this.#db.all<{ id: string }>("SELECT id FROM players WHERE id > ? ORDER BY id ASC LIMIT ?", [after ?? "", limit]);
    return rows.map((row) => row.id);
  }

  async batchesOf(playerId: string): Promise<{ events: LedgerEvent[]; receivedAt: number }[]> {
    const rows = await this.#db.all<{ events_gzip: ArrayBuffer | Uint8Array; received_at: number }>(
      "SELECT events_gzip, received_at FROM batches WHERE player_id = ? ORDER BY first_seq ASC", [playerId]);
    const out: { events: LedgerEvent[]; receivedAt: number }[] = [];
    for (const row of rows) out.push({ events: JSON.parse(await gunzip(new Uint8Array(row.events_gzip))) as LedgerEvent[], receivedAt: row.received_at });
    return out;
  }

  async derivedNow(playerId: string): Promise<{ state: LedgerState; drops: Record<string, number>; score: number | null; casualDrops: number } | null> {
    const rows = await this.#db.all<{ state_json: string; drops_json: string; casual_drops: number }>("SELECT state_json, drops_json, casual_drops FROM ledger_state WHERE player_id = ?", [playerId]);
    if (!rows[0]) return null;
    const score = await this.#db.all<{ score: number }>("SELECT score FROM scores WHERE player_id = ?", [playerId]);
    return { state: JSON.parse(rows[0].state_json) as LedgerState, drops: JSON.parse(rows[0].drops_json) as Record<string, number>, score: score[0]?.score ?? null, casualDrops: rows[0].casual_drops };
  }

  async writeDerived(playerId: string, derived: Derived): Promise<void> {
    const statements: Statement[] = [
      { sql: "UPDATE ledger_state SET state_json = ?, drops_json = ?, casual_drops = ? WHERE player_id = ?", params: [JSON.stringify(derived.state), JSON.stringify(derived.drops), derived.casualDrops, playerId] },
      { sql: "DELETE FROM drops WHERE player_id = ?", params: [playerId] },
      { sql: "DELETE FROM trades WHERE player_id = ?", params: [playerId] },
      { sql: "DELETE FROM set_completions WHERE player_id = ?", params: [playerId] },
      {
        sql: "UPDATE scores SET score = ?, unique_cards = ?, sets_done = ?, rules_version = ? WHERE player_id = ?",
        params: [derived.score.score, derived.score.uniqueCards, derived.score.setsDone, derived.rulesVersion, playerId],
      },
    ];
    for (let from = 0; from < derived.dropRows.length; from += 16) {
      const group = derived.dropRows.slice(from, from + 16);
      statements.push({
        sql: "INSERT INTO drops (player_id, seq, card_key, t, shiny, tape_idx) VALUES " + group.map(() => "(?, ?, ?, ?, ?, ?)").join(", "),
        params: group.flatMap((event) => [playerId, event.seq, event.key, event.t, event.shiny, event.tape]),
      });
    }
    // Trade halves go back as open: matching them again is the hourly job's work, not the rebuild's.
    for (let from = 0; from < derived.trades.length; from += 10) {
      const group = derived.trades.slice(from, from + 10);
      statements.push({
        sql: "INSERT INTO trades (player_id, seq, trade_id, direction, card_key, char, partner, t, received_at) VALUES " + group.map(() => "(?, ?, ?, ?, ?, ?, ?, ?, ?)").join(", "),
        params: group.flatMap((row) => [playerId, row.seq, row.tradeId, row.direction, row.key, row.char, row.partner, row.t, row.receivedAt]),
      });
    }
    for (const done of derived.completions) {
      statements.push({ sql: "INSERT OR IGNORE INTO set_completions (set_code, player_id, t, received_at) VALUES (?, ?, ?, ?)", params: [done.setCode, playerId, done.t, done.receivedAt] });
    }
    await this.#db.batch(statements);
  }

  async matchOpen(): Promise<string[]> {
    const pair = `EXISTS (SELECT 1 FROM trades o WHERE o.trade_id = trades.trade_id AND o.direction != trades.direction
      AND o.card_key = trades.card_key AND o.player_id != trades.player_id AND o.partner = trades.char AND o.char = trades.partner)`;
    // Halves that were written off but whose other half has since arrived are taken back, and their score changes.
    const recovered = await this.#db.all<{ player_id: string }>(`SELECT DISTINCT player_id FROM trades WHERE state = 'unmatched' AND ${pair}`);
    await this.#db.batch([{ sql: `UPDATE trades SET state = 'matched' WHERE state IN ('open', 'unmatched') AND ${pair}`, params: [] }]);
    return recovered.map((row) => row.player_id);
  }

  async expire(before: number): Promise<{ playerId: string; direction: "in" | "out"; key: string; partnerUploadedSince: string | null }[]> {
    // The partner's player, found by the character name the trade half names, when they have uploaded after this half was recorded.
    const rows = await this.#db.all<{ player_id: string; direction: "in" | "out"; card_key: string; partner_player: string | null }>(
      `SELECT t.player_id, t.direction, t.card_key,
              (SELECT c.player_id FROM characters c JOIN ledger_state l ON l.player_id = c.player_id
               WHERE lower(c.name) || '-' || lower(replace(replace(replace(c.realm, ' ', ''), '''', ''), '-', '')) = t.partner
               AND c.player_id != t.player_id AND l.updated_at > t.received_at LIMIT 1) AS partner_player
       FROM trades t WHERE t.state = 'open' AND t.received_at < ?`, [before]);
    if (rows.length > 0) await this.#db.batch([{ sql: "UPDATE trades SET state = 'unmatched' WHERE state = 'open' AND received_at < ?", params: [before] }]);
    return rows.map((row) => ({ playerId: row.player_id, direction: row.direction, key: row.card_key, partnerUploadedSince: row.partner_player }));
  }

  async excluded(playerId: string): Promise<Record<string, number>> {
    const rows = await this.#db.all<{ card_key: string; n: number }>(
      `SELECT t.card_key, COUNT(*) AS n FROM trades t WHERE t.player_id = ? AND t.direction = 'in'
       AND (t.state = 'unmatched' OR (t.card_key LIKE 'pack:%' AND t.state != 'matched') OR ${FROM_CASUAL}
            OR EXISTS (SELECT 1 FROM trade_taint x WHERE x.player_id = t.player_id AND x.seq = t.seq)) GROUP BY t.card_key`, [playerId]);
    return Object.fromEntries(rows.map((row) => [row.card_key, row.n]));
  }

  async tradeGraph() {
    const halves = await this.#db.all<{ player_id: string; seq: number; card_key: string; state: "open" | "matched" | "unmatched"; source: string | null }>(
      `SELECT t.player_id, t.seq, t.card_key, t.state,
              (SELECT o.player_id FROM trades o WHERE o.trade_id = t.trade_id AND o.direction = 'out' AND o.card_key = t.card_key
               AND o.player_id != t.player_id AND o.partner = t.char AND o.char = t.partner LIMIT 1) AS source
       FROM trades t WHERE t.direction = 'in'`);
    const casual = await this.#db.all<{ player_id: string }>("SELECT player_id FROM ledger_state WHERE casual_drops > 0");
    const packed = await this.#db.all<{ player_id: string; state_json: string }>("SELECT player_id, state_json FROM ledger_state WHERE state_json LIKE '%\"packOutputs\"%'");
    return {
      halves: halves.map((row) => ({ playerId: row.player_id, seq: row.seq, key: row.card_key, state: row.state, source: row.source })),
      casualPlayers: casual.map((row) => row.player_id),
      outputs: packed.flatMap(row => Object.entries((JSON.parse(row.state_json) as LedgerState).packOutputs || {})
        .map(([zone, cards]) => ({ playerId: row.player_id, zone, keys: Object.keys(cards) }))),
    };
  }

  async replaceTaint(rows: { playerId: string; seq: number }[]): Promise<string[]> {
    const before = await this.#db.all<{ player_id: string; seq: number }>("SELECT player_id, seq FROM trade_taint");
    const had = new Set(before.map((row) => `${row.player_id}:${row.seq}`));
    const will = new Set(rows.map((row) => `${row.playerId}:${row.seq}`));
    const changed = new Set<string>();
    for (const row of before) if (!will.has(`${row.player_id}:${row.seq}`)) changed.add(row.player_id);
    for (const row of rows) if (!had.has(`${row.playerId}:${row.seq}`)) changed.add(row.playerId);
    if (changed.size === 0) return [];
    const statements: Statement[] = [{ sql: "DELETE FROM trade_taint", params: [] }];
    for (let from = 0; from < rows.length; from += 40) {
      const group = rows.slice(from, from + 40);
      statements.push({ sql: "INSERT INTO trade_taint (player_id, seq) VALUES " + group.map(() => "(?, ?)").join(", "), params: group.flatMap((row) => [row.playerId, row.seq]) });
    }
    await this.#db.batch(statements);
    return [...changed];
  }

  async setScore(playerId: string, score: { score: number; uniqueCards: number; setsDone: number }): Promise<void> {
    await this.#db.batch([{
      sql: "UPDATE scores SET score = ?, unique_cards = ?, sets_done = ? WHERE player_id = ?",
      params: [score.score, score.uniqueCards, score.setsDone, playerId],
    }]);
  }

  async addFlag(playerId: string, flag: { id: string; kind: string; notes: string }, at: number): Promise<void> {
    await this.#db.batch([{
      sql: "INSERT INTO flags (id, player_id, kind, notes, created_at) VALUES (?, ?, ?, ?, ?)",
      params: [flag.id, playerId, flag.kind, flag.notes, at],
    }]);
  }

  async binder(playerId: string): Promise<{ counts: Record<string, number>; shiny: Record<string, boolean> } | null> {
    if (!(await this.entry(playerId))) return null;
    const rows = await this.#db.all<{ state_json: string }>("SELECT state_json FROM ledger_state WHERE player_id = ?", [playerId]);
    if (!rows[0]) return null;
    const state = JSON.parse(rows[0].state_json) as LedgerState;
    return { counts: state.counts, shiny: state.shiny };
  }

  async charactersOf(playerIds: string[]): Promise<Record<string, string[]>> {
    const out: Record<string, string[]> = {};
    if (playerIds.length === 0) return out;
    const rows = await this.#db.all<{ player_id: string; name: string; realm: string }>(
      `SELECT player_id, name, realm FROM characters WHERE player_id IN (${playerIds.map(() => "?").join(", ")}) ORDER BY last_seen DESC, name, realm`, playerIds);
    for (const row of rows) (out[row.player_id] ??= []).push(peerName(row.name, row.realm));
    return out;
  }

  async firsts(): Promise<{ setCode: string; playerId: string; displayName: string; receivedAt: number }[]> {
    const rows = await this.#db.all<{ set_code: string; player_id: string; display_name: string; received_at: number }>(
      `SELECT set_code, player_id, display_name, received_at FROM (
         SELECT c.set_code, c.player_id, s.display_name, c.received_at,
                ROW_NUMBER() OVER (PARTITION BY c.set_code ORDER BY c.received_at ASC, c.player_id ASC) AS n
         FROM set_completions c JOIN players p ON p.id = c.player_id JOIN scores s ON s.player_id = c.player_id
         WHERE p.visibility = 'public' AND p.status = 'active'
         AND NOT EXISTS (SELECT 1 FROM flags f WHERE f.player_id = p.id AND f.kind = 'luck-hold' AND f.state != 'cleared')
       AND COALESCE((SELECT l.casual_drops FROM ledger_state l WHERE l.player_id = p.id), 0) = 0
       ) WHERE n = 1 ORDER BY received_at ASC, set_code ASC`);
    return rows.map((row) => ({ setCode: row.set_code, playerId: row.player_id, displayName: row.display_name, receivedAt: row.received_at }));
  }

  async top(limit: number): Promise<BoardEntry[]> {
    const rows = await this.#db.all<ScoreRow>(
      `SELECT ${SCORE_COLUMNS} FROM scores s JOIN players p ON p.id = s.player_id
       WHERE p.visibility = 'public' AND p.status = 'active'
       AND NOT EXISTS (SELECT 1 FROM flags f WHERE f.player_id = p.id AND f.kind = 'luck-hold' AND f.state != 'cleared')
       AND COALESCE((SELECT l.casual_drops FROM ledger_state l WHERE l.player_id = p.id), 0) = 0
       ORDER BY s.score DESC, s.updated_at ASC, s.player_id ASC LIMIT ?`, [limit]);
    return rows.map(toEntry);
  }

  async entry(playerId: string): Promise<{ entry: BoardEntry; rank: number } | null> {
    const rows = await this.#db.all<ScoreRow>(
      `SELECT ${SCORE_COLUMNS} FROM scores s JOIN players p ON p.id = s.player_id
       WHERE s.player_id = ? AND p.visibility = 'public' AND p.status = 'active'
       AND NOT EXISTS (SELECT 1 FROM flags f WHERE f.player_id = p.id AND f.kind = 'luck-hold' AND f.state != 'cleared')
       AND COALESCE((SELECT l.casual_drops FROM ledger_state l WHERE l.player_id = p.id), 0) = 0`, [playerId]);
    const row = rows[0];
    if (!row) return null;
    const ahead = await this.#db.all<{ n: number }>(
      `SELECT COUNT(*) AS n FROM scores s JOIN players p ON p.id = s.player_id
       WHERE p.visibility = 'public' AND p.status = 'active'
       AND NOT EXISTS (SELECT 1 FROM flags f WHERE f.player_id = p.id AND f.kind = 'luck-hold' AND f.state != 'cleared')
       AND COALESCE((SELECT l.casual_drops FROM ledger_state l WHERE l.player_id = p.id), 0) = 0
       AND (s.score > ? OR (s.score = ? AND s.updated_at < ?) OR (s.score = ? AND s.updated_at = ? AND s.player_id < ?))`,
      [row.score, row.score, row.updated_at, row.score, row.updated_at, row.player_id]);
    return { entry: toEntry(row), rank: (ahead[0]?.n ?? 0) + 1 };
  }
  async search(text: string, limit: number): Promise<AdminPlayerRow[]> {
    const like = "%" + text.toLowerCase().replace(/[!%_]/g, "!$&") + "%";
    const ids = (await this.#db.all<{ id: string }>(
      `SELECT p.id FROM players p WHERE p.archived_from IS NULL AND (? = '' OR p.id = ?
         OR EXISTS (SELECT 1 FROM scores s WHERE s.player_id IN (SELECT p.id UNION SELECT a.id FROM players a WHERE a.archived_from = p.id) AND lower(s.display_name) LIKE ? ESCAPE '!')
         OR EXISTS (SELECT 1 FROM characters c WHERE c.player_id IN (SELECT p.id UNION SELECT a.id FROM players a WHERE a.archived_from = p.id) AND (lower(c.name) LIKE ? ESCAPE '!' OR lower(c.name || ' ' || c.realm) LIKE ? ESCAPE '!')))
       ORDER BY p.created_at DESC, p.id DESC LIMIT ?`, [text, text.toUpperCase(), like, like, like, limit])).map((row) => row.id);
    if (ids.length === 0) return [];
    const rows = await this.#db.all<{ id: string; status: "active" | "banned"; visibility: Visibility; created_at: number; display_name: string | null; score: number | null }>(
      `SELECT p.id, p.status, p.visibility, p.created_at, s.score,
         COALESCE(s.display_name, (SELECT s2.display_name FROM players a JOIN scores s2 ON s2.player_id = a.id WHERE a.archived_from = p.id ORDER BY a.epoch DESC LIMIT 1)) AS display_name
       FROM players p LEFT JOIN scores s ON s.player_id = p.id
       WHERE p.id IN (${ids.map(() => "?").join(", ")})`, ids);
    const characters = await this.charactersOf(ids);
    return ids.flatMap((id) => {
      const row = rows.find((candidate) => candidate.id === id);
      return row ? [{ playerId: id, displayName: row.display_name ?? "", status: row.status, visibility: row.visibility, createdAt: row.created_at,
        characters: characters[id] ?? [], scoreTenths: row.score }] : [];
    });
  }

  async detail(playerId: string): Promise<AdminPlayerDetail | null> {
    const account = (await this.#db.all<{ id: string; discord_id: string | null; status: "active" | "banned"; visibility: Visibility; created_at: number; epoch: number; reset_at: number | null; barred_before: number | null }>(
      "SELECT id, discord_id, status, visibility, created_at, epoch, reset_at, barred_before FROM players WHERE id = ? AND archived_from IS NULL", [playerId]))[0];
    if (!account) return null;
    const one = async <T>(sql: string): Promise<T | undefined> => (await this.#db.all<T>(sql, [playerId]))[0];
    const count = async (sql: string) => (await one<{ n: number }>(sql))?.n ?? 0;
    const keys = await this.#db.all<{ status: string; n: number }>("SELECT status, COUNT(*) AS n FROM keys WHERE player_id = ? GROUP BY status", [playerId]);
    const score = await one<{ display_name: string; score: number; unique_cards: number; sets_done: number; attempts: number; rules_version: number; updated_at: number }>(
      "SELECT display_name, score, unique_cards, sets_done, attempts, rules_version, updated_at FROM scores WHERE player_id = ?");
    const state = await one<{ head_seq: number; state_json: string; casual_drops: number; updated_at: number }>(
      "SELECT head_seq, state_json, casual_drops, updated_at FROM ledger_state WHERE player_id = ?");
    const parsed = state ? (JSON.parse(state.state_json) as LedgerState) : null;
    const uploads = await one<{ n: number; first: number | null; last: number | null }>("SELECT COUNT(*) AS n, MIN(received_at) AS first, MAX(received_at) AS last FROM batches WHERE player_id = ?");
    const trades = await this.#db.all<{ state: "open" | "matched" | "unmatched"; n: number }>("SELECT state, COUNT(*) AS n FROM trades WHERE player_id = ? GROUP BY state", [playerId]);
    const flags = (await this.flags("all", 500)).filter((flag) => flag.playerId === playerId);
    return {
      playerId, createdAt: account.created_at, status: account.status, visibility: account.visibility, epoch: account.epoch, resetAt: account.reset_at,
      hasDiscord: account.discord_id !== null,
      barredBefore: account.barred_before,
      archives: await this.#archivesOf(playerId),
      keys: { active: keys.find((row) => row.status === "active")?.n ?? 0, revoked: keys.find((row) => row.status === "revoked")?.n ?? 0 },
      characters: await this.#db.all<{ name: string; realm: string; firstSeen: number; lastSeen: number }>(
        "SELECT name, realm, first_seen AS firstSeen, last_seen AS lastSeen FROM characters WHERE player_id = ? ORDER BY last_seen DESC, name, realm", [playerId]),
      score: score ? { displayName: score.display_name, scoreTenths: score.score, uniqueCards: score.unique_cards, setsDone: score.sets_done, attempts: score.attempts, rulesVersion: score.rules_version, updatedAt: score.updated_at } : null,
      binder: state && parsed ? { mode: parsed.mode, cardsOwned: Object.values(parsed.counts).filter((owned) => owned > 0).length, headSeq: state.head_seq, casualDrops: state.casual_drops, updatedAt: state.updated_at } : null,
      uploads: { batches: uploads?.n ?? 0, first: uploads?.first ?? null, last: uploads?.last ?? null },
      trades: { open: trades.find((row) => row.state === "open")?.n ?? 0, matched: trades.find((row) => row.state === "matched")?.n ?? 0, unmatched: trades.find((row) => row.state === "unmatched")?.n ?? 0 },
      flags,
      reportsAbout: await count("SELECT COUNT(*) AS n FROM reports WHERE target_id = ?"),
    };
  }

  // The admin's reset: the player's binder goes to a private archive exactly as when they start over themselves, and their old
  // history is refused afterwards (barred_before), because their add-on still holds it and would otherwise upload it again.
  // False when there is no such player or they have no binder to archive.
  async adminReset(playerId: string, archivedId: string, at: number): Promise<boolean> {
    const account = (await this.#db.all<{ created_at: number; epoch: number }>("SELECT created_at, epoch FROM players WHERE id = ? AND archived_from IS NULL", [playerId]))[0];
    if (!account || (await this.#db.all("SELECT 1 AS found FROM ledger_state WHERE player_id = ?", [playerId])).length === 0) return false;
    await this.#db.batch([
      { sql: "INSERT INTO players (id, discord_id, created_at, status, visibility, epoch, reset_at, archived_from) VALUES (?, NULL, ?, 'active', 'private', ?, NULL, ?)", params: [archivedId, account.created_at, account.epoch, playerId] },
      ...BINDER_TABLES.map((table) => ({ sql: `UPDATE ${table} SET player_id = ? WHERE player_id = ?`, params: [archivedId, playerId] })),
      // reset_at stays empty: the player's own once-a-day limit on starting over is about their choices, not ours.
      { sql: "UPDATE players SET epoch = epoch + 1, reset_at = NULL, barred_before = ? WHERE id = ?", params: [at, playerId] },
    ]);
    return true;
  }

  // Put an archived binder back as the player's current one. Whatever binder they have now is archived in its turn (so nothing is
  // lost and this can be undone the same way), and the player's epoch goes back to the one the restored binder was written under,
  // so its roll tape and chain carry on as they were. False when the player or the archive (theirs) does not exist.
  async restoreBinder(playerId: string, archiveId: string, newArchiveId: string): Promise<boolean> {
    const account = (await this.#db.all<{ created_at: number; epoch: number }>("SELECT created_at, epoch FROM players WHERE id = ? AND archived_from IS NULL", [playerId]))[0];
    const archive = (await this.#db.all<{ epoch: number }>("SELECT epoch FROM players WHERE id = ? AND archived_from = ?", [archiveId, playerId]))[0];
    if (!account || !archive) return false;
    const empty = BINDER_TABLES.map((table) => `NOT EXISTS (SELECT 1 FROM ${table} WHERE player_id = ?)`).join(" AND ");
    await this.#db.batch([
      { sql: "INSERT INTO players (id, discord_id, created_at, status, visibility, epoch, reset_at, archived_from) VALUES (?, NULL, ?, 'active', 'private', ?, NULL, ?)", params: [newArchiveId, account.created_at, account.epoch, playerId] },
      ...BINDER_TABLES.map((table) => ({ sql: `UPDATE ${table} SET player_id = ? WHERE player_id = ?`, params: [newArchiveId, playerId] })),
      ...BINDER_TABLES.map((table) => ({ sql: `UPDATE ${table} SET player_id = ? WHERE player_id = ?`, params: [playerId, archiveId] })),
      { sql: "UPDATE players SET epoch = ?, reset_at = NULL, barred_before = NULL WHERE id = ?", params: [archive.epoch, playerId] },
      { sql: "DELETE FROM players WHERE id = ?", params: [archiveId] },
      // If there was nothing to put aside, do not leave an empty archive behind.
      { sql: `DELETE FROM players WHERE id = ? AND ${empty}`, params: [newArchiveId, ...BINDER_TABLES.map(() => newArchiveId)] },
    ]);
    return true;
  }

  async #archivesOf(playerId: string): Promise<AdminPlayerDetail["archives"]> {
    const rows = await this.#db.all<{ id: string; epoch: number }>("SELECT id, epoch FROM players WHERE archived_from = ? ORDER BY epoch DESC, created_at DESC, id DESC", [playerId]);
    return Promise.all(rows.map(async (row) => {
      const one = async <T>(sql: string): Promise<T | undefined> => (await this.#db.all<T>(sql, [row.id]))[0];
      const uploads = await one<{ n: number; last: number | null }>("SELECT COUNT(*) AS n, MAX(received_at) AS last FROM batches WHERE player_id = ?");
      const state = await one<{ state_json: string }>("SELECT state_json FROM ledger_state WHERE player_id = ?");
      const score = await one<{ score: number; display_name: string }>("SELECT score, display_name FROM scores WHERE player_id = ?");
      const counts = state ? (JSON.parse(state.state_json) as LedgerState).counts : {};
      return { archiveId: row.id, displayName: score?.display_name ?? "", epoch: row.epoch, batches: uploads?.n ?? 0, cardsOwned: Object.values(counts).filter((owned) => owned > 0).length, scoreTenths: score?.score ?? null, lastUpload: uploads?.last ?? null };
    }));
  }

  async record(entry: AuditEntry): Promise<void> {
    await this.#db.batch([{
      sql: "INSERT INTO admin_audit (id, at, actor, action, target, detail) VALUES (?, ?, ?, ?, ?, ?)",
      params: [entry.id, entry.at, entry.actor, entry.action, entry.target, entry.detail],
    }]);
  }

  async audit(limit: number): Promise<AuditEntry[]> {
    return this.#db.all<AuditEntry>("SELECT id, at, actor, action, target, detail FROM admin_audit ORDER BY at DESC, rowid DESC LIMIT ?", [limit]);
  }
}

// A trade half received from a player whose own ledger has Casual drops: the other half is a tradeOut of the same card,
// naming each other, by a player with a non-zero casual_drops. Those copies cannot be trusted, so they do not count.
const FROM_CASUAL = `EXISTS (SELECT 1 FROM trades o JOIN ledger_state l ON l.player_id = o.player_id
  WHERE o.trade_id = t.trade_id AND o.direction = 'out' AND o.card_key = t.card_key AND o.player_id != t.player_id
  AND o.partner = t.char AND o.char = t.partner AND l.casual_drops > 0)`;

type ScoreRow = {
  player_id: string; display_name: string; score: number; unique_cards: number; sets_done: number; attempts: number; updated_at: number;
};
const SCORE_COLUMNS = "s.player_id, s.display_name, s.score, s.unique_cards, s.sets_done, s.attempts, s.updated_at";
const toEntry = (row: ScoreRow): BoardEntry => ({
  playerId: row.player_id, displayName: row.display_name, score: row.score, uniqueCards: row.unique_cards,
  setsDone: row.sets_done, attempts: row.attempts, updatedAt: row.updated_at,
});
