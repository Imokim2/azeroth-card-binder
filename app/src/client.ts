// Talking to the server (docs/API.md): registering a key and uploading new ledger events.
//
// There is no separate upload queue. The add-on keeps every event in its saved-data file until the server has
// acknowledged it, so the file IS the queue: after any failure, the next sync simply sends what is still unacknowledged.
// Uploads are safe to repeat (the server stores a batch once), so retrying after a lost reply cannot double anything.
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import type { Binder, BinderEvent } from "./binderFile.ts";
import type { Identity } from "./identity.ts";
import type { Ack } from "./syncFile.ts";
import { isVersion } from "./versions.ts";
import type { Releases } from "./versions.ts";
import { parseSeasonData } from "./seasons.ts";
import type { SeasonData } from "./seasons.ts";

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
  | { status: "history-missing"; haveFrom: number; needFrom: number }
  // The saved data is a different binder from the one the server holds (the player started over in the game).
  | { status: "diverged"; serverSeq: number };

type Reply = { status: number; body: Record<string, unknown>; retryAfter: number | null };
export type PublicClientOptions = Pick<ClientOptions, "baseUrl" | "fetch" | "clientVersion" | "sleep" | "attempts">;

// `body` is absent for a GET (the public pages: standings, firsts).
async function send(options: PublicClientOptions, path: string, body?: Record<string, unknown>): Promise<Reply | { network: string }> {
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
const worthRetrying = (reply: Reply): boolean => reply.status >= 500 || errorOf(reply).code === "conflict" || errorOf(reply).code === "rate_limited";

// Send with a few retries and growing pauses; honours the server's Retry-After. Returns the reply, or why to wait.
async function sendWithRetries(options: PublicClientOptions, path: string, body?: Record<string, unknown>): Promise<Reply | { later: number; reason: string }> {
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
    // Spec 8 adds mode/chase2 (the second set of drop rates); 7 added seasonal rewards. The server refuses a binder that needs more than it is told.
    specVersion: 8, key: options.identity.publicKeyHex, character: binder.character?.name ?? "Unknown",
    realm: binder.character?.realm ?? "Unknown", schema: binder.schema, catalogVersion: options.catalogVersion,
    events, snapshot: binder.snapshot, tapeIndex: binder.tapeNext, sentAt: options.now(),
  };
  return { ...body, sig: await options.identity.sign(canonicalJson(body)) };
}

// Does the saved data continue the chain the server says it holds? The server's newest event is (seq, hash): the saved
// data must either have that very event, or not have reached it yet (which a new binder with a short history shows).
// An older event that has been pruned from the file cannot be checked and is given the benefit of the doubt.
function continues(binder: Binder, ack: Ack | null): boolean {
  if (!ack || ack.seq === 0) return true;
  if (binder.head.seq < ack.seq) return false;
  if (binder.head.seq === ack.seq) return binder.head.hash === ack.hash;
  const event = binder.events.find((entry) => entry.seq === ack.seq);
  return event ? event.h === ack.hash : true;
}

// Upload what the server has not stored yet. `known` is the last acknowledgement we saw (or null).
export async function syncBinder(options: ClientOptions, binder: Binder, known: Ack | null): Promise<Outcome> {
  const batchSize = options.batchSize ?? 500;
  let ack: Ack | null = known;
  let uploaded = 0;
  let resyncs = 0;
  for (;;) {
    // Even an empty/pruned file must continue the last server acknowledgement.
    if (!continues(binder, ack)) return { status: "diverged", serverSeq: ack?.seq ?? 0 };
    const have = ack?.seq ?? 0;
    const pending = binder.events.filter((event) => event.seq > have);
    if (pending.length === 0) {
      if (ack) return { status: "synced", ack, uploaded };
      // On a cold start an empty file is not evidence that the server is empty too.
      // Ask once, then cache even a zero acknowledgement for later save-driven passes.
      const probe = await sendWithRetries(options, "/v1/ledger", await uploadBody(options, binder, []));
      if ("later" in probe) return { status: "retry-later", afterMs: probe.later, reason: probe.reason };
      if (probe.status !== 200) return { status: "rejected", ...errorOf(probe) };
      const seq = probe.body["ackSeq"], hash = probe.body["ackHash"];
      if (!Number.isSafeInteger(seq) || (seq as number) < 0 || typeof hash !== "string" || !/^[0-9a-f]{32}$/.test(hash)) return { status: "rejected", code: "bad_reply" };
      ack = { seq: seq as number, hash };
      continue;
    }
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
      if (!continues(binder, ack)) return { status: "diverged", serverSeq: ack?.seq ?? 0 };
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
      // Told the server already has events up to here: are they ours? If not, this is a different binder.
      if (!continues(binder, ack)) return { status: "diverged", serverSeq: ack?.seq ?? 0 };
      continue;
    }
    // The same range stored with different contents: also a different binder, not an attempt to be repaired here.
    if (code === "duplicate_batch") return { status: "diverged", serverSeq: typeof detail?.["ackSeq"] === "number" ? detail["ackSeq"] : 0 };
    return { status: "rejected", code, ...(detail ? { detail } : {}) };
  }
}

// Ask for the roll tape: every entry not used yet, and a refill when the player is running low. The reply can be
// requested again at any time and is the same, so a lost reply is harmless.
// `addon` is the add-on version the player last ran, when known: the server gives no new tape to one it no longer accepts.
export async function fetchTape(options: ClientOptions, addon?: string): Promise<{ status: "tape"; start: number; entries: string[] } | Outcome> {
  const body: Record<string, unknown> = { key: options.identity.publicKeyHex, sentAt: options.now(), ...(addon ? { addon } : {}) };
  const sig = await options.identity.sign(canonicalJson({ ...body, purpose: "tape" }));
  const reply = await sendWithRetries(options, "/v1/tape", { ...body, sig });
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  const { start, entries } = reply.body;
  if (typeof start !== "number" || !Array.isArray(entries) || !entries.every((entry) => typeof entry === "string")) return { status: "rejected", code: "bad_reply" };
  return { status: "tape", start, entries: entries as string[] };
}

export async function fetchSeasons(options: ClientOptions, binders: string[]): Promise<{ status: "seasons"; data: SeasonData } | Outcome> {
  const body = { key: options.identity.publicKeyHex, sentAt: options.now() };
  const sig = await options.identity.sign(canonicalJson({ ...body, purpose: "seasons" }));
  const reply = await sendWithRetries(options, "/v1/seasons", { ...body, sig });
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  try { return { status: "seasons", data: parseSeasonData(reply.body, binders) }; }
  catch { return { status: "rejected", code: "bad_reply" }; }
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

// The newest and oldest accepted versions of the app and the add-on (GET /v1/releases).
export async function fetchReleases(options: PublicClientOptions): Promise<{ status: "releases"; releases: Releases } | Outcome> {
  const reply = await sendWithRetries(options, "/v1/releases");
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  const app = record(reply.body["app"]);
  const addon = record(reply.body["addon"]);
  if (![app["latest"], app["min"], addon["latest"], addon["min"]].every(isVersion)) return { status: "rejected", code: "bad_reply" };
  const signed = record(reply.body["signed"]);
  const found: Releases = { app: { latest: app["latest"] as string, min: app["min"] as string }, addon: { latest: addon["latest"] as string, min: addon["min"] as string } };
  if (typeof signed["manifest"] === "string" && signed["manifest"].length <= 8000 && typeof signed["signature"] === "string" && /^[0-9a-f]{128}$/.test(signed["signature"])) {
    found.signed = { manifest: signed["manifest"], signature: signed["signature"] };
  }
  return { status: "releases", releases: found };
}

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

// Start a new binder: the server archives the old record and the player begins again with an empty chain and a new roll
// tape. Signed by the player's key. At most once a day; `too_soon` says how long to wait.
export async function resetBinder(options: ClientOptions): Promise<{ status: "reset"; epoch: number } | Outcome> {
  const body: Record<string, unknown> = { key: options.identity.publicKeyHex, sentAt: options.now() };
  const sig = await options.identity.sign(canonicalJson({ ...body, purpose: "reset" }));
  const reply = await sendWithRetries(options, "/v1/reset", { ...body, sig });
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  return { status: "reset", epoch: Number(reply.body["epoch"] ?? 0) };
}

// Delete everything the server holds about this player (their record, key link, Discord id and any archived binders). Signed by
// the player's key and confirmed by the exact words. It cannot be undone.
export async function deleteAccount(options: ClientOptions): Promise<{ status: "deleted" } | Outcome> {
  const body: Record<string, unknown> = { key: options.identity.publicKeyHex, sentAt: options.now(), confirm: "delete my data" };
  const sig = await options.identity.sign(canonicalJson({ ...body, purpose: "delete" }));
  const reply = await sendWithRetries(options, "/v1/delete", { ...body, sig });
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  return { status: "deleted" };
}

// A copy of everything the server holds about this player (POST /v1/export), as the text to save. Signed with their key.
export async function exportAccount(options: ClientOptions): Promise<{ status: "exported"; text: string } | Outcome> {
  const body: Record<string, unknown> = { key: options.identity.publicKeyHex, sentAt: options.now() };
  const sig = await options.identity.sign(canonicalJson({ ...body, purpose: "export" }));
  const reply = await sendWithRetries(options, "/v1/export", { ...body, sig });
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  return { status: "exported", text: JSON.stringify(reply.body, null, 2) + "\n" };
}

// Send reports about other players. Signed by the player's key. Returns the tokens the server has settled (stored, repeated,
// or about the player themselves); the rest are kept by the add-on and sent again. At most 10 go in one request.
export async function sendReports(options: ClientOptions, reports: { token: string; target: string; reason: string; note: string }[]): Promise<{ status: "reported"; done: string[] } | Outcome> {
  const done: string[] = [];
  for (let from = 0; from < reports.length; from += 10) {
    const body: Record<string, unknown> = { key: options.identity.publicKeyHex, sentAt: options.now(), reports: reports.slice(from, from + 10) };
    const sig = await options.identity.sign(canonicalJson({ ...body, purpose: "report" }));
    const reply = await sendWithRetries(options, "/v1/report", { ...body, sig });
    if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
    if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
    if (Array.isArray(reply.body["done"])) for (const token of reply.body["done"]) if (typeof token === "string") done.push(token);
  }
  return { status: "reported", done };
}
