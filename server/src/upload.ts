// A ledger upload (docs/LEDGER-SPEC.md, section 6): checking its shape, then verifying and storing it.
import { ApiError } from "./errors.ts";
import type { ErrorCode } from "./errors.ts";
import { canonicalJson, newId, verifySignature } from "../../packages/shared/src/crypto.ts";
import { checkChain } from "./ledger.ts";
import type { LedgerEvent } from "./ledger.ts";
import { replay, snapshotDifferences } from "./shared.ts";
import type { Catalog } from "./shared.ts";
import { RULES_VERSION, scoreOf } from "./score.ts";
import { StoreConflict } from "./store.ts";
import { casualDropsOf, completionsOf, dropCountsOf, tradeRowsOf } from "./derive.ts";
import type { IngestStore, Player, TapeStore, TradeStore } from "./store.ts";
import { checkTape, tapeKey, tapeOwner } from "./tape.ts";
import { integrityFlags } from "./integrity.ts";

export const SUPPORTED_SPEC_VERSIONS = [2, 3, 4]; // 4 adds edition-aware drops and the editions1 activation marker
export const MAX_EVENTS_PER_UPLOAD = 5000;

export type Snapshot = {
  counts: Record<string, number>; attempts: Record<string, number>; dust: number;
  sets: Record<string, boolean>; titles: Record<string, boolean>;
};
export type Upload = {
  specVersion: number; key: string; character: string; realm: string; schema: number; catalogVersion: string;
  events: Record<string, unknown>[]; snapshot: Snapshot; tapeIndex: number; sentAt: number; sig: string;
};

const bad = (field: string): never => {
  throw new ApiError("bad_request", { field });
};
const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const isInt = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value);
const text = (value: unknown, field: string, max = 64): string => {
  if (typeof value !== "string" || value.length < 1 || value.length > max || /[\u0000-\u001f]/.test(value)) return bad(field);
  return value;
};

function numberMap(value: unknown, field: string): Record<string, number> {
  if (!isRecord(value) || Object.keys(value).length > 20000) return bad(field);
  for (const entry of Object.values(value)) if (!isInt(entry) || entry < 0) return bad(field);
  return value as Record<string, number>;
}

function flagMap(value: unknown, field: string): Record<string, boolean> {
  if (!isRecord(value) || Object.keys(value).length > 20000) return bad(field);
  for (const entry of Object.values(value)) if (entry !== true) return bad(field);
  return value as Record<string, boolean>;
}

// Check the shape of an upload. The events themselves are checked later, by the chain and the rules.
export function parseUpload(body: unknown): Upload {
  if (!isRecord(body)) return bad("body");
  const { specVersion, key, schema, events, snapshot, tapeIndex, sentAt, sig } = body;
  if (!isInt(specVersion)) bad("specVersion");
  if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key)) bad("key");
  if (!isInt(schema) || schema < 1) bad("schema");
  if (!Array.isArray(events) || events.length > MAX_EVENTS_PER_UPLOAD) bad("events");
  if (!isInt(tapeIndex) || tapeIndex < 0) bad("tapeIndex");
  if (!isInt(sentAt) || sentAt < 0) bad("sentAt");
  if (typeof sig !== "string" || !/^[0-9a-f]{128}$/.test(sig)) bad("sig");
  if (!isRecord(snapshot)) return bad("snapshot");
  if (!isInt(snapshot["dust"])) bad("snapshot.dust");
  return {
    ...(body as object),
    specVersion: specVersion as number, key: key as string, schema: schema as number,
    character: text(body["character"], "character"), realm: text(body["realm"], "realm"),
    catalogVersion: text(body["catalogVersion"], "catalogVersion"),
    events: events as Record<string, unknown>[], tapeIndex: tapeIndex as number, sentAt: sentAt as number, sig: sig as string,
    snapshot: {
      counts: numberMap(snapshot["counts"], "snapshot.counts"), attempts: numberMap(snapshot["attempts"], "snapshot.attempts"),
      dust: snapshot["dust"] as number, sets: flagMap(snapshot["sets"], "snapshot.sets"), titles: flagMap(snapshot["titles"], "snapshot.titles"),
    },
  };
}

export type Ack = { ackSeq: number; ackHash: string; accepted: number; duplicate: boolean };

const CHAIN_ERRORS: Record<string, ErrorCode> = {
  replay: "replay", gap: "gap", "bad-field": "bad_field", "bad-prev": "bad_prev", "bad-hash": "bad_hash",
};

// Verify a signed upload from a registered player and store it. Uploading the same batch twice is safe: the
// second time nothing is written and the answer is the same.
export async function acceptUpload(
  deps: { ingest: IngestStore; tapes: TapeStore; trades: TradeStore; catalog: Catalog; now: () => number; tapeSecret?: string | undefined },
  player: Player,
  upload: Upload,
): Promise<Ack> {
  const { sig, ...body } = upload;
  let signed: string;
  try {
    signed = canonicalJson(body);
  } catch {
    throw new ApiError("bad_request", { field: "body" });
  }
  if (!(await verifySignature(upload.key, sig, signed))) throw new ApiError("bad_signature");

  const stored = await deps.ingest.load(player.id);
  const events = upload.events;
  // The add-on can never be past the first entry after the last one issued: it only uses entries it was given.
  if (upload.tapeIndex > (await deps.tapes.issuedEnd(player.id)) + 1 && upload.tapeIndex > 1) {
    throw new ApiError("tape_invalid", { reason: "next", index: events.length });
  }
  if (events.length === 0) {
    if (upload.tapeIndex > stored.tapeNext) await deps.ingest.noteTapeNext(player.id, upload.tapeIndex, deps.now());
    return { ackSeq: stored.head.seq, ackHash: stored.head.hash, accepted: 0, duplicate: false };
  }

  const first = events[0] as { seq?: unknown };
  const last = events[events.length - 1] as { seq?: unknown; h?: unknown };
  if (Number.isSafeInteger(first.seq) && Number.isSafeInteger(last.seq) && (first.seq as number) <= stored.head.seq) {
    const earlier = await deps.ingest.findBatch(player.id, first.seq as number, last.seq as number);
    if (earlier && earlier.lastHash === last.h) {
      return { ackSeq: stored.head.seq, ackHash: stored.head.hash, accepted: 0, duplicate: true };
    }
    // The same range with different contents: the player is trying to rewrite history that is already stored.
    if (earlier) throw new ApiError("duplicate_batch", { ackSeq: stored.head.seq, ackHash: stored.head.hash });
  }

  const chain = await checkChain(events, stored.head);
  if (upload.specVersion < 4 && events.some((event) => (event["kind"] === "mode" && event["key"] === "editions1") || deps.catalog.cards[String(event["key"])]?.baseKey)) {
    throw new ApiError("client_too_old", { supported: SUPPORTED_SPEC_VERSIONS });
  }
  if (!chain.ok) {
    // Where the stored chain stands is included so the app can work out what to send next.
    throw new ApiError(CHAIN_ERRORS[chain.error] ?? "bad_field", { index: chain.index, ackSeq: stored.head.seq, ackHash: stored.head.hash });
  }
  const played = replay(events, deps.catalog, stored.state, { strict: true });
  if (!played.ok) throw new ApiError("rule_broken", { rule: played.rule, index: played.index });

  // Every ranked attempt (a drop, or a run of misses) must match the tape entries the server issued, with the chance
  // that the card's own run of misses had built up. Entering ranked2 starts every card's run again.
  let pity = stored.pity;
  const usesTape = (event: Record<string, unknown>): boolean => Number(event["tape"]) > 0 && (event["kind"] === "drop" || event["kind"] === "miss" || event["kind"] === "packFind" || event["kind"] === "packCard" || (event["kind"] === "mode" && event["key"] === "ranked2"));
  if (events.some(usesTape)) {
    if (!deps.tapeSecret) throw new ApiError("ranked_unavailable");
    const checked = await checkTape({
      key: await tapeKey(deps.tapeSecret), playerId: tapeOwner(player), events: events as unknown as LedgerEvent[], stateBefore: stored.state,
      catalog: deps.catalog, issuedEnd: await deps.tapes.issuedEnd(player.id), stack: stored.pity, tapeNext: upload.tapeIndex,
    });
    if (checked.failure) throw new ApiError("tape_invalid", { reason: checked.failure.reason, index: checked.failure.index });
    pity = checked.stack;
  }

  const flags: { id: string; kind: string; notes: string }[] = [];
  const differences = snapshotDifferences(upload.snapshot, played.state);
  if (differences.length > 0) flags.push({ id: newId(deps.now() * 1000), kind: "snapshot-mismatch", notes: differences.join(",") });
  const drops = dropCountsOf(events, stored.drops);
  const tapeNext = Math.max(stored.tapeNext, upload.tapeIndex);
  for (const flag of integrityFlags({
    catalog: deps.catalog, state: played.state, attempts: upload.snapshot.attempts, drops, tapeNextBefore: stored.tapeNext, tapeNextNow: tapeNext,
    lastUploadAt: stored.lastUpload, now: deps.now(), playerCreatedAt: player.createdAt, openKinds: stored.openFlags, clearedLuck: stored.clearedLuck,
  })) flags.push({ id: newId(deps.now() * 1000), ...flag });
  const attempts = Object.values(upload.snapshot.attempts).reduce((sum, value) => sum + value, 0);
  // Copies that came from trades the other player never confirmed do not count (roadmap C5).
  const score = scoreOf(deps.catalog, played.state, await deps.trades.excluded(player.id));
  // The trade halves and finished sets in this batch, for matching and the firsts feed.
  const trades = tradeRowsOf(events);
  const completions = completionsOf(events);
  try {
    await deps.ingest.commit(player.id, {
      events: events as unknown as LedgerEvent[], head: chain.head, state: played.state, pity, drops, tapeNext, receivedAt: deps.now(),
      character: { name: upload.character, realm: upload.realm },
      score: { displayName: `${upload.character}-${upload.realm}`, ...score, attempts, rulesVersion: RULES_VERSION },
      flags, trades, completions, casualDrops: casualDropsOf(events),
    });
  } catch (error) {
    if (error instanceof StoreConflict) throw new ApiError("conflict", undefined, 1);
    throw error;
  }
  return { ackSeq: chain.head.seq, ackHash: chain.head.hash, accepted: events.length, duplicate: false };
}
