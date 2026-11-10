// Talking to the server (docs/API.md): registering a key and uploading new ledger events.
//
// There is no separate upload queue. The add-on keeps every event in its saved-data file until the server has
// acknowledged it, so the file IS the queue: after any failure, the next sync simply sends what is still unacknowledged.
// Uploads are safe to repeat (the server stores a batch once), so retrying after a lost reply cannot double anything.
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import type { Binder, BinderEvent } from "./binderFile.ts";
import type { Identity } from "./identity.ts";
import type { Ack } from "./syncFile.ts";

export type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body?: string }) => Promise<{
  status: number;
  headers: { get(name: string): string | null };
  json(): Promise<unknown>;
}>;

export type ClientOptions = {
  baseUrl: string;
  fetch: FetchLike;
  identity: Identity;
  clientVersion: string;
  catalogVersion: string;
  now: () => number; // seconds
  sleep: (milliseconds: number) => Promise<void>;
  batchSize?: number; // events per upload
  attempts?: number; // tries for one request before giving up until later
};

export type Outcome =
  | { status: "synced"; ack: Ack | null; uploaded: number }
  | { status: "retry-later"; afterMs: number; reason: string }
  | { status: "rejected"; code: string; detail?: Record<string, unknown> }
  | { status: "history-missing"; haveFrom: number; needFrom: number };

type Reply = { status: number; body: Record<string, unknown>; retryAfter: number | null };

// `body` is absent for a GET (the public pages: standings, firsts).
async function send(options: ClientOptions, path: string, body?: Record<string, unknown>): Promise<Reply | { network: string }> {
  try {
    const response = await options.fetch(options.baseUrl + path, body === undefined
      ? { method: "GET", headers: { "x-warcards-client": options.clientVersion } }
      : { method: "POST", headers: { "content-type": "application/json", "x-warcards-client": options.clientVersion }, body: JSON.stringify(body) });
    const parsed = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    const retry = Number(response.headers.get("retry-after"));
    return { status: response.status, body: parsed, retryAfter: Number.isFinite(retry) && retry > 0 ? retry : null };
  } catch (error) {
    return { network: error instanceof Error ? error.message : "network error" };
  }
}

const errorOf = (reply: Reply): { code: string; detail?: Record<string, unknown> } => {
  const error = reply.body["error"] as { code?: unknown; detail?: Record<string, unknown> } | undefined;
  return { code: typeof error?.code === "string" ? error.code : `http_${reply.status}`, ...(error?.detail ? { detail: error.detail } : {}) };
};

// Failures that a later attempt can fix: nothing to do with the contents of the upload.
const worthRetrying = (reply: Reply): boolean => reply.status >= 500 || errorOf(reply).code === "conflict";

// Send with a few retries and growing pauses; honours the server's Retry-After. Returns the reply, or why to wait.
async function sendWithRetries(options: ClientOptions, path: string, body?: Record<string, unknown>): Promise<Reply | { later: number; reason: string }> {
  const attempts = options.attempts ?? 4;
  let pause = 500;
  for (let attempt = 1; ; attempt++) {
    const reply = await send(options, path, body);
    const failed = "network" in reply || worthRetrying(reply);
    if (!failed) return reply as Reply;
    const waitMs = "network" in reply ? pause : Math.max(pause, (reply.retryAfter ?? 0) * 1000);
    if (attempt >= attempts) return { later: Math.max(waitMs, 30_000), reason: "network" in reply ? reply.network : errorOf(reply).code };
    await options.sleep(waitMs);
    pause = Math.min(pause * 2, 30_000);
  }
}

async function uploadBody(options: ClientOptions, binder: Binder, events: BinderEvent[]): Promise<Record<string, unknown>> {
  const body: Record<string, unknown> = {
    specVersion: 1, key: options.identity.publicKeyHex, character: binder.character?.name ?? "Unknown",
    realm: binder.character?.realm ?? "Unknown", schema: binder.schema, catalogVersion: options.catalogVersion,
    events, snapshot: binder.snapshot, tapeIndex: binder.tapeNext, sentAt: options.now(),
  };
  return { ...body, sig: await options.identity.sign(canonicalJson(body)) };
}

// Upload what the server has not stored yet. `known` is the last acknowledgement we saw (or null).
export async function syncBinder(options: ClientOptions, binder: Binder, known: Ack | null): Promise<Outcome> {
  const batchSize = options.batchSize ?? 500;
  let ack: Ack | null = known;
  let uploaded = 0;
  let resyncs = 0;
  for (;;) {
    const have = ack?.seq ?? 0;
    const pending = binder.events.filter((event) => event.seq > have);
    if (pending.length === 0) return { status: "synced", ack, uploaded };
    const first = pending[0] as BinderEvent;
    if (first.seq !== have + 1) {
      // The file's oldest event comes after the server's newest: ask where the server really is, once.
      if (resyncs++ >= 2) return { status: "history-missing", haveFrom: have + 1, needFrom: first.seq };
      const probe = await sendWithRetries(options, "/v1/ledger", await uploadBody(options, binder, []));
      if ("later" in probe) return { status: "retry-later", afterMs: probe.later, reason: probe.reason };
      if (probe.status !== 200) return { status: "rejected", ...errorOf(probe) };
      const seq = probe.body["ackSeq"];
      const hash = probe.body["ackHash"];
      ack = typeof seq === "number" && typeof hash === "string" && seq > 0 ? { seq, hash } : null;
      continue;
    }
    const reply = await sendWithRetries(options, "/v1/ledger", await uploadBody(options, binder, pending.slice(0, batchSize)));
    if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
    if (reply.status === 200) {
      const seq = reply.body["ackSeq"];
      const hash = reply.body["ackHash"];
      if (typeof seq !== "number" || typeof hash !== "string") return { status: "rejected", code: "bad_reply" };
      uploaded += Number(reply.body["accepted"] ?? 0);
      ack = { seq, hash };
      continue;
    }
    const { code, detail } = errorOf(reply);
    // Told where the server stands (events already stored, or missing): take that and carry on, a couple of times.
    if ((code === "replay" || code === "gap") && resyncs++ < 2 && typeof detail?.["ackSeq"] === "number" && typeof detail["ackHash"] === "string") {
      ack = detail["ackSeq"] > 0 ? { seq: detail["ackSeq"], hash: detail["ackHash"] } : null;
      continue;
    }
    return { status: "rejected", code, ...(detail ? { detail } : {}) };
  }
}

// Ask for the roll tape: every entry not used yet, and a refill when the player is running low. The reply can be
// requested again at any time and is the same, so a lost reply is harmless.
export async function fetchTape(options: ClientOptions): Promise<{ status: "tape"; start: number; entries: string[] } | Outcome> {
  const body: Record<string, unknown> = { key: options.identity.publicKeyHex, sentAt: options.now() };
  const sig = await options.identity.sign(canonicalJson({ ...body, purpose: "tape" }));
  const reply = await sendWithRetries(options, "/v1/tape", { ...body, sig });
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  const { start, entries } = reply.body;
  if (typeof start !== "number" || !Array.isArray(entries) || !entries.every((entry) => typeof entry === "string")) return { status: "rejected", code: "bad_reply" };
  return { status: "tape", start, entries: entries as string[] };
}

// Link this key to a Discord account (the sign-in itself is obtained by the app's window; here it is just a token).
export async function registerKey(options: ClientOptions, identityToken: string, visibility: "public" | "private"): Promise<Outcome | { status: "registered"; playerId: string }> {
  const body: Record<string, unknown> = { key: options.identity.publicKeyHex, sentAt: options.now(), identityToken, visibility };
  const proof = await options.identity.sign(canonicalJson({ ...body, purpose: "register" }));
  const reply = await sendWithRetries(options, "/v1/register", { ...body, proof });
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  return { status: "registered", playerId: String(reply.body["playerId"]) };
}

// What the add-on shows in its leaderboard tab (roadmap C3, C4, C6): the top 100, where this player stands, the
// characters of ranked players (for the "verified" mark) and who finished each set first. All of it is public, so
// nothing here is signed; the player's own standing is read from their public page, which is absent when they are
// private or held off the ladder.
export type Standings = {
  leaderboard: { rank: number; name: string; score: number; cards: number; sets: number }[];
  verified: string[];
  firsts: { setCode: string; title: string; by: string; at: number }[];
  you: { rank: number; score: number; cards: number; sets: number } | null;
};

const record = (value: unknown): Record<string, unknown> => (typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {});
const whole = (value: unknown): number => (typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0);

export async function fetchStandings(options: ClientOptions, playerId: string | null): Promise<{ status: "standings"; standings: Standings } | Outcome> {
  const board = await sendWithRetries(options, "/v1/leaderboard?limit=100");
  if ("later" in board) return { status: "retry-later", afterMs: board.later, reason: board.reason };
  if (board.status !== 200) return { status: "rejected", ...errorOf(board) };
  const feed = await sendWithRetries(options, "/v1/firsts");
  if ("later" in feed) return { status: "retry-later", afterMs: feed.later, reason: feed.reason };
  if (feed.status !== 200) return { status: "rejected", ...errorOf(feed) };
  const entries = Array.isArray(board.body["entries"]) ? (board.body["entries"] as unknown[]).map(record) : [];
  const verified = new Set<string>();
  const leaderboard = entries.map((entry) => {
    if (Array.isArray(entry["characters"])) for (const name of entry["characters"]) if (typeof name === "string") verified.add(name);
    return { rank: whole(entry["rank"]), name: String(entry["displayName"] ?? ""), score: whole(entry["scoreTenths"]), cards: whole(entry["uniqueCards"]), sets: whole(entry["setsDone"]) };
  });
  const rows = Array.isArray(feed.body["firsts"]) ? (feed.body["firsts"] as unknown[]).map(record) : [];
  const firsts = rows.map((row) => ({ setCode: String(row["setCode"] ?? ""), title: String(row["title"] ?? ""), by: String(row["displayName"] ?? ""), at: whole(row["at"]) }));
  let you: Standings["you"] = null;
  if (playerId) {
    const page = await sendWithRetries(options, "/v1/player/" + playerId);
    if (!("later" in page) && page.status === 200) you = { rank: whole(page.body["rank"]), score: whole(page.body["scoreTenths"]), cards: whole(page.body["uniqueCards"]), sets: whole(page.body["setsDone"]) };
  }
  return { status: "standings", standings: { leaderboard, verified: [...verified], firsts, you } };
}
