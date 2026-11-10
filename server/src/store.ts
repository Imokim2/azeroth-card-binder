// What the API needs from storage, as interfaces (roadmap B11). The rules code only ever talks to these, never to
// a database, so storage can be sharded, queued or replaced without touching the rules. src/sqlStore.ts is the
// implementation for D1 (and SQLite in tests).
import type { Head, LedgerEvent } from "./ledger.ts";
import type { LedgerState } from "./shared.ts";

export type Visibility = "private" | "public";
export type Player = {
  id: string;
  discordId: string | null;
  status: "active" | "banned";
  visibility: Visibility;
  createdAt: number;
};

export interface PlayerStore {
  // The player who holds this public key, if the key is active.
  findByActiveKey(key: string): Promise<Player | null>;
  findById(id: string): Promise<Player | null>;
  // Register a key for a Discord account. A new account gets a new player; an account that already has a player
  // keeps it, its older keys are revoked and the new one becomes active. Registering the same key twice changes nothing.
  registerKey(input: { discordId: string; key: string; visibility: Visibility; at: number; newPlayerId: string }): Promise<Player>;
  characters(playerId: string): Promise<{ name: string; realm: string }[]>;
}

export type StoredLedger = { head: Head; state: LedgerState };

export type Commit = {
  events: LedgerEvent[];
  head: Head;
  state: LedgerState;
  receivedAt: number;
  character: { name: string; realm: string };
  score: { displayName: string; score: number; uniqueCards: number; setsDone: number; attempts: number; rulesVersion: number };
  flags: { id: string; kind: string; notes: string }[];
};

// Thrown by commit when another upload for the same player got there first.
export class StoreConflict extends Error {}

export interface IngestStore {
  // Where the player's chain stands (a new binder if nothing is stored yet).
  load(playerId: string): Promise<StoredLedger>;
  // A stored batch with exactly this range, if there is one: lets a retried upload succeed.
  findBatch(playerId: string, firstSeq: number, lastSeq: number): Promise<{ lastHash: string } | null>;
  // Store a verified batch, the new head and state, the score and any flags, all together or not at all.
  commit(playerId: string, commit: Commit): Promise<void>;
}

export type BoardEntry = {
  playerId: string;
  displayName: string;
  score: number;
  uniqueCards: number;
  setsDone: number;
  attempts: number;
  updatedAt: number;
};

export interface LeaderboardStore {
  // The best public players, highest score first (earlier update wins a tie).
  top(limit: number): Promise<BoardEntry[]>;
  // One player's entry and rank among public players, or null when they are private or have no score.
  entry(playerId: string): Promise<{ entry: BoardEntry; rank: number } | null>;
}
