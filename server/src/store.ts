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
  epoch: number; // how many times the player has started a new binder
  resetAt: number | null;
};

export interface PlayerStore {
  // The player who holds this public key, if the key is active.
  findByActiveKey(key: string): Promise<Player | null>;
  findById(id: string): Promise<Player | null>;
  // Register a key for a Discord account. A new account gets a new player; an account that already has a player
  // keeps it, its older keys are revoked and the new one becomes active. Registering the same key twice changes nothing.
  registerKey(input: { discordId: string; key: string; visibility: Visibility; at: number; newPlayerId: string }): Promise<Player>;
  characters(playerId: string): Promise<{ name: string; realm: string }[]>;
  // Start over: everything stored for the player is kept, under a new private id that nothing lists, and the player
  // begins again with nothing (and a new epoch). Their keys, Discord link and visibility stay.
  resetBinder(playerId: string, archivedId: string, at: number): Promise<void>;
}

// pity (kept under its old column name): the attempts that each card's ranked drops have needed so far, checked against its counted attempts; tapeNext: the tape position
// the add-on said it will use next, at its last upload.
// drops: drop events per card so far; lastUpload: when the last upload was stored (null if never); openFlags: kinds of
// flags still open for this player.
export type StoredLedger = {
  head: Head; state: LedgerState; pity: Record<string, number>; tapeNext: number;
  drops: Record<string, number>; lastUpload: number | null; openFlags: string[];
  // The highest luck score a reviewer has already cleared for this player, so the same luck is not flagged again.
  clearedLuck: number;
};

export type Commit = {
  events: LedgerEvent[];
  head: Head;
  state: LedgerState;
  pity: Record<string, number>;
  drops: Record<string, number>;
  tapeNext: number;
  receivedAt: number;
  character: { name: string; realm: string };
  score: { displayName: string; score: number; uniqueCards: number; setsDone: number; attempts: number; rulesVersion: number };
  flags: { id: string; kind: string; notes: string }[];
  // Each tradeIn and tradeOut in the batch, and each set finished, for trade matching and the firsts feed.
  trades: TradeRow[];
  completions: { setCode: string; t: number }[];
  // Drop events in this batch that were rolled in Casual mode (tape position 0); added to the player's running count.
  casualDrops: number;
};

export type TradeRow = { seq: number; tradeId: string; direction: "in" | "out"; key: string; char: string; partner: string; t: number };

// Thrown by commit when another upload for the same player got there first.
export class StoreConflict extends Error {}

export interface IngestStore {
  // Where the player's chain stands (a new binder if nothing is stored yet).
  load(playerId: string): Promise<StoredLedger>;
  // A stored batch with exactly this range, if there is one: lets a retried upload succeed.
  findBatch(playerId: string, firstSeq: number, lastSeq: number): Promise<{ lastHash: string } | null>;
  // Remember the tape position the add-on says it will use next, when an upload brings no new events.
  noteTapeNext(playerId: string, tapeNext: number, at: number): Promise<void>;
  // Store a verified batch, the new head and state, the score and any flags, all together or not at all.
  commit(playerId: string, commit: Commit): Promise<void>;
}

// Trade matching (roadmap C5). A trade is two halves, one from each player: a tradeOut of a card against the other's
// tradeIn of the same card, with the same trade id and each naming the other.
export interface TradeStore {
  // Mark every trade half that has its other half as matched. Returns the players who had halves written off
  // as unmatched that are matched now, so their scores can be put right.
  matchOpen(): Promise<string[]>;
  // Mark the halves still open from before `before` (seconds) as unmatched, and say whose they were.
  expire(before: number): Promise<{ playerId: string; direction: "in" | "out"; key: string }[]>;
  // The copies of each card the player received in trades that do not count towards the score: halves never matched,
  // and copies that came from a player who has unverified Casual drops.
  excluded(playerId: string): Promise<Record<string, number>>;
  // Players with copies received from a player who has unverified Casual drops, so their scores can be put right.
  receivedFromCasual(): Promise<string[]>;
  // Replace the score numbers after the excluded copies changed.
  setScore(playerId: string, score: { score: number; uniqueCards: number; setsDone: number }): Promise<void>;
  // Raise a flag outside an upload.
  addFlag(playerId: string, flag: { id: string; kind: string; notes: string }, at: number): Promise<void>;
}

// Flag review and bans (roadmap D4), for the admin endpoints only.
export type FlagRecord = {
  id: string; playerId: string; displayName: string; kind: string; state: "open" | "cleared" | "confirmed"; notes: string;
  createdAt: number; reviewedAt: number | null; reviewNote: string;
};
export interface ModerationStore {
  flags(state: FlagRecord["state"] | "all", limit: number): Promise<FlagRecord[]>;
  // Mark a flag cleared or confirmed. False when there is no such flag.
  review(id: string, state: "cleared" | "confirmed", note: string, at: number): Promise<boolean>;
  // Ban or unban a player. False when there is no such player.
  setBanned(playerId: string, banned: boolean): Promise<boolean>;
}

// Rebuilding everything derived from the stored batches (roadmap D8).
export type Derived = {
  state: LedgerState; drops: Record<string, number>; score: { score: number; uniqueCards: number; setsDone: number };
  casualDrops: number; dropRows: LedgerEvent[]; trades: (TradeRow & { receivedAt: number })[]; completions: { setCode: string; t: number; receivedAt: number }[]; rulesVersion: number;
};
export interface RebuildStore {
  // Player ids in order, after `after` (or from the start), at most `limit`.
  playerIds(after: string | null, limit: number): Promise<string[]>;
  // Every stored batch of a player, oldest first.
  batchesOf(playerId: string): Promise<{ events: LedgerEvent[]; receivedAt: number }[]>;
  // The derived data as it is stored now, to compare with a rebuild.
  derivedNow(playerId: string): Promise<{ state: LedgerState; drops: Record<string, number>; score: number | null; casualDrops: number } | null>;
  // Replace the derived data for a player.
  writeDerived(playerId: string, derived: Derived): Promise<void>;
}

export type IssuedTape = { start: number; end: number; commitment: string };

export interface TapeStore {
  // The last tape position issued to this player (0 if none), and the position the add-on said it will use next.
  issuedEnd(playerId: string): Promise<number>;
  tapeNext(playerId: string): Promise<number>;
  recordIssue(playerId: string, issued: IssuedTape, at: number): Promise<void>;
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
  // The characters each of these players has played, in the form partners use ("name-realmname").
  charactersOf(playerIds: string[]): Promise<Record<string, string[]>>;
  // Who finished each set first among the players who may appear on the ladder (roadmap C6).
  firsts(): Promise<{ setCode: string; playerId: string; displayName: string; receivedAt: number }[]>;
}
