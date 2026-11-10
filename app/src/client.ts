// Talking to the server (docs/API.md): registering a key and uploading new ledger events.
//
// There is no separate upload queue. The add-on keeps every event in its saved-data file until the server has
// acknowledged it, so the file IS the queue: after any failure, the next sync simply sends what is still unacknowledged.
// Uploads are safe to repeat (the server stores a batch once), so retrying after a lost reply cannot double anything.
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import type { Binder, BinderEvent } from "./binderFile.ts";
import type { Identity } from "./identity.ts";
import type { Ack } from "./syncFile.ts";

export type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{
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

async function send(options: ClientOptions, path: string, body: Record<string, unknown>): Promise<Reply | { network: string }> {
  try {
    const response = await options.fetch(options.baseUrl + path, {
      method: "POST",
      headers: { "content-type": "application/json", "x-warcards-client": options.clientVersion },
      body: JSON.stringify(body),
    });
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
async function sendWithRetries(options: ClientOptions, path: string, body: Record<string, unknown>): Promise<Reply | { later: number; reason: string }> {
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
    events, snapshot: binder.snapshot, tapeIndex: 0, sentAt: options.now(),
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

// Link this key to a Discord account (the sign-in itself is obtained by the app's window; here it is just a token).
export async function registerKey(options: ClientOptions, identityToken: string, visibility: "public" | "private"): Promise<Outcome | { status: "registered"; playerId: string }> {
  const body: Record<string, unknown> = { key: options.identity.publicKeyHex, sentAt: options.now(), identityToken, visibility };
  const proof = await options.identity.sign(canonicalJson({ ...body, purpose: "register" }));
  const reply = await sendWithRetries(options, "/v1/register", { ...body, proof });
  if ("later" in reply) return { status: "retry-later", afterMs: reply.later, reason: reply.reason };
  if (reply.status !== 200) return { status: "rejected", ...errorOf(reply) };
  return { status: "registered", playerId: String(reply.body["playerId"]) };
}
