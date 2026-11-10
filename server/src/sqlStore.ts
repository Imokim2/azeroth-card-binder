// The three stores (store.ts) on top of any SQL database that speaks SQLite's dialect: Cloudflare D1 in production,
// SQLite in tests. The schema is in migrations/. Whole uploads are written with one transaction.
import type { Db, Statement } from "./db.ts";
import { GENESIS } from "./ledger.ts";
import { gzip } from "./gzip.ts";
import { newState } from "./shared.ts";
import type { LedgerState } from "./shared.ts";
import { StoreConflict } from "./store.ts";
import type { BoardEntry, Commit, IngestStore, IssuedTape, LeaderboardStore, Player, PlayerStore, StoredLedger, TapeStore, Visibility } from "./store.ts";

type PlayerRow = { id: string; discord_id: string | null; status: "active" | "banned"; visibility: Visibility; created_at: number };

const toPlayer = (row: PlayerRow): Player => ({
  id: row.id, discordId: row.discord_id, status: row.status, visibility: row.visibility, createdAt: row.created_at,
});

// A key that already belongs to another account, or one that was revoked and can never be used again.
export class KeyUnavailable extends Error {}

const PLAYER_COLUMNS = "p.id, p.discord_id, p.status, p.visibility, p.created_at";

export class SqlStore implements PlayerStore, IngestStore, LeaderboardStore, TapeStore {
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

  async load(playerId: string): Promise<StoredLedger> {
    const rows = await this.#db.all<{ head_seq: number; head_hash: string; state_json: string; tape_next: number; pity_json: string }>(
      "SELECT head_seq, head_hash, state_json, tape_next, pity_json FROM ledger_state WHERE player_id = ?", [playerId]);
    const row = rows[0];
    if (!row) return { head: { seq: 0, hash: GENESIS }, state: newState(), pity: {}, tapeNext: 1 };
    return {
      head: { seq: row.head_seq, hash: row.head_hash }, state: JSON.parse(row.state_json) as LedgerState,
      pity: JSON.parse(row.pity_json) as Record<string, number>, tapeNext: row.tape_next,
    };
  }

  async noteTapeNext(playerId: string, tapeNext: number, at: number): Promise<void> {
    await this.#db.batch([{
      sql: `INSERT INTO ledger_state (player_id, head_seq, head_hash, state_json, updated_at, tape_next) VALUES (?, 0, ?, ?, ?, ?)
            ON CONFLICT (player_id) DO UPDATE SET tape_next = MAX(ledger_state.tape_next, excluded.tape_next)`,
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
      sql: `INSERT INTO ledger_state (player_id, head_seq, head_hash, state_json, updated_at, tape_next, pity_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (player_id) DO UPDATE SET head_seq = excluded.head_seq, head_hash = excluded.head_hash,
            state_json = excluded.state_json, updated_at = excluded.updated_at, tape_next = excluded.tape_next,
            pity_json = excluded.pity_json`,
      params: [playerId, commit.head.seq, commit.head.hash, JSON.stringify(commit.state), commit.receivedAt, commit.tapeNext, JSON.stringify(commit.pity)],
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

  async top(limit: number): Promise<BoardEntry[]> {
    const rows = await this.#db.all<ScoreRow>(
      `SELECT ${SCORE_COLUMNS} FROM scores s JOIN players p ON p.id = s.player_id
       WHERE p.visibility = 'public' AND p.status = 'active'
       ORDER BY s.score DESC, s.updated_at ASC, s.player_id ASC LIMIT ?`, [limit]);
    return rows.map(toEntry);
  }

  async entry(playerId: string): Promise<{ entry: BoardEntry; rank: number } | null> {
    const rows = await this.#db.all<ScoreRow>(
      `SELECT ${SCORE_COLUMNS} FROM scores s JOIN players p ON p.id = s.player_id
       WHERE s.player_id = ? AND p.visibility = 'public' AND p.status = 'active'`, [playerId]);
    const row = rows[0];
    if (!row) return null;
    const ahead = await this.#db.all<{ n: number }>(
      `SELECT COUNT(*) AS n FROM scores s JOIN players p ON p.id = s.player_id
       WHERE p.visibility = 'public' AND p.status = 'active'
       AND (s.score > ? OR (s.score = ? AND s.updated_at < ?) OR (s.score = ? AND s.updated_at = ? AND s.player_id < ?))`,
      [row.score, row.score, row.updated_at, row.score, row.updated_at, row.player_id]);
    return { entry: toEntry(row), rank: (ahead[0]?.n ?? 0) + 1 };
  }
}

type ScoreRow = {
  player_id: string; display_name: string; score: number; unique_cards: number; sets_done: number; attempts: number; updated_at: number;
};
const SCORE_COLUMNS = "s.player_id, s.display_name, s.score, s.unique_cards, s.sets_done, s.attempts, s.updated_at";
const toEntry = (row: ScoreRow): BoardEntry => ({
  playerId: row.player_id, displayName: row.display_name, score: row.score, uniqueCards: row.unique_cards,
  setsDone: row.sets_done, attempts: row.attempts, updatedAt: row.updated_at,
});
