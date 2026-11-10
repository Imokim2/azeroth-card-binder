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
import type { IngestStore, Player } from "./store.ts";

export const SUPPORTED_SPEC_VERSIONS = [1];
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
  deps: { ingest: IngestStore; catalog: Catalog; now: () => number },
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
  if (events.length === 0) return { ackSeq: stored.head.seq, ackHash: stored.head.hash, accepted: 0, duplicate: false };

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
  if (!chain.ok) {
    // Where the stored chain stands is included so the app can work out what to send next.
    throw new ApiError(CHAIN_ERRORS[chain.error] ?? "bad_field", { index: chain.index, ackSeq: stored.head.seq, ackHash: stored.head.hash });
  }
  const played = replay(events, deps.catalog, stored.state);
  if (!played.ok) throw new ApiError("rule_broken", { rule: played.rule, index: played.index });

  const flags: { id: string; kind: string; notes: string }[] = [];
  const differences = snapshotDifferences(upload.snapshot, played.state);
  if (differences.length > 0) flags.push({ id: newId(deps.now() * 1000), kind: "snapshot-mismatch", notes: differences.join(",") });
  const attempts = Object.values(upload.snapshot.attempts).reduce((sum, value) => sum + value, 0);
  const score = scoreOf(deps.catalog, played.state);
  try {
    await deps.ingest.commit(player.id, {
      events: events as unknown as LedgerEvent[], head: chain.head, state: played.state, receivedAt: deps.now(),
      character: { name: upload.character, realm: upload.realm },
      score: { displayName: `${upload.character}-${upload.realm}`, ...score, attempts, rulesVersion: RULES_VERSION },
      flags,
    });
  } catch (error) {
    if (error instanceof StoreConflict) throw new ApiError("conflict", undefined, 1);
    throw error;
  }
  return { ackSeq: chain.head.seq, ackHash: chain.head.hash, accepted: events.length, duplicate: false };
}
