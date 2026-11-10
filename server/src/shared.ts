// The rules shared with the app (packages/shared/src/rules.js), with types. Plain JavaScript on purpose: the same
// file is used by the server and the app, and checked by the same test vectors.
import * as shared from "../../packages/shared/src/rules.js";

export type Catalog = {
  catalogVersion: string;
  cards: Record<string, { name: string; rarity: string; rank: string; set: string; boss?: boolean; profession?: string }>;
  sets: { code: string; title: string; group: string; reward: string; cards: string[] }[];
  dust: { recycle: Record<string, number>; craft: Record<string, number> };
  rates: Record<string, number>;
  stackFactor: number;
  shinyOdds: number;
};

// What the rules remember between events. Stored per player so a new upload only replays its own events.
export type LedgerState = {
  counts: Record<string, number>;
  dust: number;
  shiny: Record<string, boolean>;
  sets: Record<string, boolean>;
  mode: string;
  lastTape: number;
  lastT: number;
};

export type ReplayResult =
  | { ok: true; state: LedgerState }
  | { ok: false; error: "rule"; rule: string; index: number };

export const newState = shared.newState as () => LedgerState;
export const replay = shared.replay as (events: unknown[], catalog: Catalog, start?: LedgerState) => ReplayResult;
export const snapshotDifferences = shared.snapshotDifferences as (
  snapshot: { counts?: Record<string, number>; dust?: number; sets?: Record<string, boolean> },
  state: LedgerState,
) => string[];
