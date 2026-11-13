// The rules shared with the app (packages/shared/src/rules.js), with types. Plain JavaScript on purpose: the same
// file is used by the server and the app, and checked by the same test vectors.
import * as shared from "../../packages/shared/src/rules.js";
import * as packs from "../../packages/shared/src/packs.js";
import * as editions from "../../packages/shared/src/editions.js";

export type Catalog = {
  catalogVersion: string;
  cards: Record<string, { name: string; rarity: string; rank: string; set: string; boss?: boolean; profession?: string; baseKey?: string; editionTitle?: string;
    critter?: boolean; balanceOnly?: boolean; dropProfile?: { rate: number; rate2?: number; style: string; packWeight: number; tier: string; noCraft: boolean } }>;
  editions?: Record<string, { key: string; weight: number }[]>;
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
  exact?: boolean; // the binder has entered ranked2, in which every attempt is written down
  editions?: boolean;
  balance?: number;
  balanceAttempts?: Record<string, number>;
  balanceDrops?: Record<string, number>;
  balanceReady?: Record<string, boolean>;
  packOutputs?: Record<string, Record<string, number>>;
  packType?: string;
  tieredPacks?: boolean;
  seasonClaims?: Record<string, boolean>;
  packs?: Record<string, number>; // packs held, by zone (set code)
  packZone?: string; // the zone of the pack being opened
  packLeft?: number; // cards still to come from it
  packFound?: number; // the tape position of the last pack found
  lastAttempt?: { key: string; tape: number }; // the last attempt written down
};

export type ReplayResult =
  | { ok: true; state: LedgerState }
  | { ok: false; error: "rule"; rule: string; index: number };

export const newState = shared.newState as () => LedgerState;
export const replay = shared.replay as (events: unknown[], catalog: Catalog, start?: LedgerState, options?: { strict?: boolean }) => ReplayResult;
export const snapshotDifferences = shared.snapshotDifferences as (
  snapshot: { counts?: Record<string, number>; dust?: number; sets?: Record<string, boolean> },
  state: LedgerState,
) => string[];

export const PACK_SIZE = packs.PACK_SIZE as number;
export const PACK_ODDS = packs.PACK_ODDS as number;
export const packInfo = packs.packInfo as (catalog: Catalog, id: string) => { id: string; zone: string; tier: string; size: number } | null;
export const packTier = packs.packTier as (entry: string, shinyOdds: number) => string;
export const baseCardKey = editions.baseKey as (catalog: Catalog, key: string) => string;
export const editionKeys = editions.editionKeys as (catalog: Catalog, key: string) => string[];
export const familyCount = editions.familyCount as (catalog: Catalog, counts: Record<string, number>, key: string) => number;
export const pickEdition = editions.pickEdition as (catalog: Catalog, key: string, roll: number, balanced?: boolean | number) => string;
// 1 on the attempts that found a pack; the card a tape entry gives from a zone's pack, or null for an unknown zone.
export const packValue = packs.packValue as (entry: string, shinyOdds: number) => number;
export const packPick = packs.packPick as (catalog: Catalog, zone: string, entry: string, shinyOdds: number, balanced?: boolean | number) => string | null;
