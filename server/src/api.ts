// The HTTP API (docs/API.md). `createApi` turns the dependencies it is given into a function from a standard
// Request to a standard Response, so the same code runs in a Cloudflare Worker and in plain Node tests.
import { ApiError, ERRORS } from "./errors.ts";
import type { ErrorCode } from "./errors.ts";
import { canonicalJson, newId, verifySignature } from "../../packages/shared/src/crypto.ts";
import type { Catalog } from "./shared.ts";
import { KeyUnavailable } from "./sqlStore.ts";
import { rebuild } from "./rebuild.ts";
import type { FlagRecord, IngestStore, LeaderboardStore, ModerationStore, PlayerStore, RebuildStore, TapeStore, TradeStore, Visibility } from "./store.ts";
import { REFILL_BELOW, TAPE_SIZE, tapeCommitment, tapeEntry, tapeKey, tapeOwner } from "./tape.ts";
import { SUPPORTED_SPEC_VERSIONS, acceptUpload, parseUpload } from "./upload.ts";

export const MAX_BODY_BYTES = 2_000_000;
const PUBLIC_CACHE_SECONDS = 60;
export const RESET_COOLDOWN_SECONDS = 86_400;

export type Logger = (entry: Record<string, unknown>) => void;

export type Deps = {
  players: PlayerStore;
  ingest: IngestStore;
  board: LeaderboardStore;
  tapes: TapeStore;
  trades: TradeStore;
  moderation: ModerationStore;
  rebuild: RebuildStore;
  adminToken?: string | undefined; // the secret that opens /v1/admin/*; without it those routes do not exist
  catalog: Catalog;
  tapeSecret?: string | undefined; // derives the roll tape; Ranked is closed (ranked_unavailable) without it
  now: () => number; // seconds
  log: Logger;
  health: () => Promise<void>; // throws when the database cannot be reached
  minClient: string; // the oldest companion app version still accepted, as x.y.z
  version: string; // this server's version, shown by /v1/health
  // Turns the Discord sign-in the app obtained into a Discord account id, or null. Absent until registration opens.
  identity?: { verify(token: string): Promise<string | null> };
};

// -1, 0 or 1 for x.y.z compared with x.y.z.
export function compareVersions(a: string, b: string): number {
  const left = a.split(".").map(Number);
  const right = b.split(".").map(Number);
  for (let index = 0; index < 3; index++) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference !== 0) return difference < 0 ? -1 : 1;
  }
  return 0;
}

const json = (status: number, body: unknown, headers: Record<string, string> = {}): Response =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", ...headers } });

function errorResponse(code: ErrorCode, detail?: Record<string, unknown>, retryAfter?: number): Response {
  const headers: Record<string, string> = {};
  if (retryAfter !== undefined) headers["retry-after"] = String(retryAfter);
  const error = { code, message: ERRORS[code].message, ...(detail ? { detail } : {}), ...(retryAfter !== undefined ? { retryAfter } : {}) };
  return json(ERRORS[code].status, { error }, headers);
}

async function readJson(request: Request): Promise<unknown> {
  if (!(request.headers.get("content-type") ?? "").toLowerCase().startsWith("application/json")) throw new ApiError("unsupported_media");
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > MAX_BODY_BYTES) throw new ApiError("too_large");
  const body = await request.text();
  if (body.length > MAX_BODY_BYTES) throw new ApiError("too_large");
  try {
    return JSON.parse(body);
  } catch {
    throw new ApiError("bad_request", { field: "body" });
  }
}

function checkClient(request: Request, deps: Deps): void {
  const client = request.headers.get("x-warcards-client");
  if (!client || !/^\d+\.\d+\.\d+$/.test(client)) throw new ApiError("bad_request", { field: "x-warcards-client" });
  if (compareVersions(client, deps.minClient) < 0) throw new ApiError("client_too_old", { minClient: deps.minClient });
}

export function createApi(deps: Deps): (request: Request) => Promise<Response> {
  async function register(request: Request): Promise<Response> {
    checkClient(request, deps);
    if (!deps.identity) throw new ApiError("registration_closed");
    const body = await readJson(request);
    const { proof, ...signed } = (typeof body === "object" && body !== null ? body : {}) as Record<string, unknown>;
    const { key, sentAt, identityToken, visibility } = signed;
    if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key)) throw new ApiError("bad_request", { field: "key" });
    if (typeof proof !== "string" || typeof identityToken !== "string" || !Number.isSafeInteger(sentAt)) throw new ApiError("bad_request");
    if (visibility !== "public" && visibility !== "private") throw new ApiError("bad_request", { field: "visibility" });
    if (Math.abs(deps.now() - (sentAt as number)) > 86_400) throw new ApiError("bad_request", { field: "sentAt" });
    // The key proves it is held by the sender; the Discord sign-in proves who the sender is.
    let message: string;
    try {
      message = canonicalJson({ ...signed, purpose: "register" });
    } catch {
      throw new ApiError("bad_request");
    }
    if (!(await verifySignature(key, proof, message))) throw new ApiError("bad_signature");
    const discordId = await deps.identity.verify(identityToken);
    if (!discordId) throw new ApiError("bad_identity");
    try {
      const player = await deps.players.registerKey({
        discordId, key, visibility: visibility as Visibility, at: deps.now(), newPlayerId: newId(deps.now() * 1000),
      });
      return json(200, { playerId: player.id, visibility: player.visibility, minClient: deps.minClient });
    } catch (error) {
      if (error instanceof KeyUnavailable) throw new ApiError("conflict", { reason: "key-unavailable" });
      throw error;
    }
  }

  async function ledger(request: Request): Promise<Response> {
    checkClient(request, deps);
    const upload = parseUpload(await readJson(request));
    if (!SUPPORTED_SPEC_VERSIONS.includes(upload.specVersion)) throw new ApiError("client_too_old", { supported: SUPPORTED_SPEC_VERSIONS });
    const player = await deps.players.findByActiveKey(upload.key);
    if (!player) throw new ApiError("unknown_key");
    if (player.status !== "active") throw new ApiError("banned");
    const ack = await acceptUpload(deps, player, upload);
    return json(200, { ...ack, minClient: deps.minClient, syncVersion: 1 });
  }

  // Ranked random numbers (spec section 8): all the entries this player has not used yet, topped up with 10,000 new
  // ones when 2,000 or fewer remain. Asking again returns the same entries, so a lost reply costs nothing.
  async function tape(request: Request): Promise<Response> {
    checkClient(request, deps);
    if (!deps.tapeSecret) throw new ApiError("ranked_unavailable");
    const body = (await readJson(request)) as Record<string, unknown> | null;
    const { key, sentAt, sig } = body ?? {};
    if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key) || !Number.isSafeInteger(sentAt) || typeof sig !== "string") throw new ApiError("bad_request");
    if (Math.abs(deps.now() - (sentAt as number)) > 86_400) throw new ApiError("bad_request", { field: "sentAt" });
    const holder = await deps.players.findByActiveKey(key);
    if (!holder) throw new ApiError("unknown_key");
    if (holder.status !== "active") throw new ApiError("banned");
    if (!(await verifySignature(key, sig, canonicalJson({ key, sentAt, purpose: "tape" })))) throw new ApiError("bad_signature");
    const secret = await tapeKey(deps.tapeSecret);
    const next = await deps.tapes.tapeNext(holder.id);
    let issuedEnd = await deps.tapes.issuedEnd(holder.id);
    let issued: { start: number; end: number; commitment: string } | null = null;
    if (issuedEnd - (next - 1) <= REFILL_BELOW) {
      const start = issuedEnd + 1;
      const end = issuedEnd + TAPE_SIZE;
      const fresh: string[] = [];
      for (let index = start; index <= end; index++) fresh.push(await tapeEntry(secret, tapeOwner(holder), index));
      issued = { start, end, commitment: await tapeCommitment(fresh) };
      try {
        await deps.tapes.recordIssue(holder.id, issued, deps.now());
      } catch {
        throw new ApiError("conflict", undefined, 1); // another request issued at the same moment; ask again
      }
      issuedEnd = end;
    }
    const entries: string[] = [];
    for (let index = next; index <= issuedEnd; index++) entries.push(await tapeEntry(secret, tapeOwner(holder), index));
    return json(200, { start: next, entries, issued }, { "cache-control": "no-store" });
  }

  // Start a new binder: the old record is archived and the player begins again with an empty chain. Signed by the
  // player's key, and not more than once a day.
  async function reset(request: Request): Promise<Response> {
    checkClient(request, deps);
    const body = (await readJson(request)) as Record<string, unknown> | null;
    const { key, sentAt, sig } = body ?? {};
    if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key) || !Number.isSafeInteger(sentAt) || typeof sig !== "string") throw new ApiError("bad_request");
    if (Math.abs(deps.now() - (sentAt as number)) > 86_400) throw new ApiError("bad_request", { field: "sentAt" });
    const holder = await deps.players.findByActiveKey(key);
    if (!holder) throw new ApiError("unknown_key");
    if (holder.status !== "active") throw new ApiError("banned");
    if (!(await verifySignature(key, sig, canonicalJson({ key, sentAt, purpose: "reset" })))) throw new ApiError("bad_signature");
    if (holder.resetAt !== null && deps.now() - holder.resetAt < RESET_COOLDOWN_SECONDS) {
      throw new ApiError("too_soon", { retryAfter: holder.resetAt + RESET_COOLDOWN_SECONDS - deps.now() }, holder.resetAt + RESET_COOLDOWN_SECONDS - deps.now());
    }
    await deps.players.resetBinder(holder.id, newId(deps.now() * 1000), deps.now());
    return json(200, { playerId: holder.id, epoch: holder.epoch + 1 }, { "cache-control": "no-store" });
  }

  async function player(id: string): Promise<Response> {
    const found = await deps.board.entry(id);
    if (!found) throw new ApiError("not_found");
    const { entry, rank } = found;
    return json(200, {
      playerId: entry.playerId, displayName: entry.displayName, rank, scoreTenths: entry.score, uniqueCards: entry.uniqueCards,
      setsDone: entry.setsDone, attempts: entry.attempts, updatedAt: entry.updatedAt,
    }, { "cache-control": `public, max-age=${PUBLIC_CACHE_SECONDS}` });
  }

  async function leaderboard(url: URL): Promise<Response> {
    const asked = Number(url.searchParams.get("limit") ?? 100);
    const limit = Number.isInteger(asked) && asked >= 1 ? Math.min(asked, 100) : 100;
    const entries = await deps.board.top(limit);
    // The characters of the ranked players, so the add-on can mark them as verified beside their names.
    const characters = await deps.board.charactersOf(entries.map((entry) => entry.playerId));
    return json(200, {
      generatedAt: deps.now(),
      entries: entries.map((entry, index) => ({
        rank: index + 1, playerId: entry.playerId, displayName: entry.displayName, scoreTenths: entry.score,
        uniqueCards: entry.uniqueCards, setsDone: entry.setsDone, characters: characters[entry.playerId] ?? [],
      })),
    }, { "cache-control": `public, max-age=${PUBLIC_CACHE_SECONDS}` });
  }

  // Who finished each set first (roadmap C6), among the players who may appear on the ladder.
  async function firsts(): Promise<Response> {
    const titles = new Map(deps.catalog.sets.map((set) => [set.code, set.title]));
    const rows = await deps.board.firsts();
    return json(200, {
      generatedAt: deps.now(),
      firsts: rows.filter((row) => titles.has(row.setCode)).map((row) => ({
        setCode: row.setCode, title: titles.get(row.setCode), playerId: row.playerId, displayName: row.displayName, at: row.receivedAt,
      })),
    }, { "cache-control": `public, max-age=${PUBLIC_CACHE_SECONDS}` });
  }

  // ---- Admin (roadmap D4): reviewing flags and banning players, behind one secret token ----
  async function sameText(a: string, b: string): Promise<boolean> {
    // Compare hashes, not the texts, so the time taken does not depend on how much of the token was right.
    const encoder = new TextEncoder();
    const [left, right] = await Promise.all([crypto.subtle.digest("SHA-256", encoder.encode(a)), crypto.subtle.digest("SHA-256", encoder.encode(b))]);
    const x = new Uint8Array(left);
    const y = new Uint8Array(right);
    let difference = 0;
    for (let index = 0; index < x.length; index++) difference |= (x[index] as number) ^ (y[index] as number);
    return difference === 0;
  }

  async function requireAdmin(request: Request): Promise<void> {
    if (!deps.adminToken) throw new ApiError("not_found"); // not configured: the routes are not there at all
    const sent = /^Bearer (.+)$/.exec(request.headers.get("authorization") ?? "")?.[1];
    if (!sent || !(await sameText(sent, deps.adminToken))) throw new ApiError("unauthorized");
  }

  async function adminFlags(request: Request, url: URL): Promise<Response> {
    await requireAdmin(request);
    const state = url.searchParams.get("state") ?? "open";
    if (!["open", "cleared", "confirmed", "all"].includes(state)) throw new ApiError("bad_request", { field: "state" });
    const asked = Number(url.searchParams.get("limit") ?? 100);
    const limit = Number.isInteger(asked) && asked >= 1 ? Math.min(asked, 500) : 100;
    const flags = await deps.moderation.flags(state as FlagRecord["state"] | "all", limit);
    return json(200, { flags }, { "cache-control": "no-store" });
  }

  async function adminReview(request: Request, id: string): Promise<Response> {
    await requireAdmin(request);
    const body = (await readJson(request)) as Record<string, unknown> | null;
    const { state, note } = body ?? {};
    if (state !== "cleared" && state !== "confirmed") throw new ApiError("bad_request", { field: "state" });
    if (note !== undefined && (typeof note !== "string" || note.length > 500)) throw new ApiError("bad_request", { field: "note" });
    if (!(await deps.moderation.review(id, state, typeof note === "string" ? note : "", deps.now()))) throw new ApiError("not_found");
    return json(200, { id, state }, { "cache-control": "no-store" });
  }

  async function adminBan(request: Request, playerId: string): Promise<Response> {
    await requireAdmin(request);
    const body = (await readJson(request)) as Record<string, unknown> | null;
    if (typeof body?.["banned"] !== "boolean") throw new ApiError("bad_request", { field: "banned" });
    if (!(await deps.moderation.setBanned(playerId, body["banned"]))) throw new ApiError("not_found");
    return json(200, { playerId, banned: body["banned"] }, { "cache-control": "no-store" });
  }

  // Recompute everything derived from the stored batches (roadmap D8), a page of players at a time.
  async function adminRebuild(request: Request): Promise<Response> {
    await requireAdmin(request);
    const body = ((await readJson(request)) as Record<string, unknown> | null) ?? {};
    const { after, limit, dryRun, force } = body;
    if (after !== undefined && after !== null && (typeof after !== "string" || after.length > 40)) throw new ApiError("bad_request", { field: "after" });
    if (limit !== undefined && (!Number.isInteger(limit) || (limit as number) < 1 || (limit as number) > 200)) throw new ApiError("bad_request", { field: "limit" });
    if ((dryRun !== undefined && typeof dryRun !== "boolean") || (force !== undefined && typeof force !== "boolean")) throw new ApiError("bad_request", { field: "dryRun" });
    const report = await rebuild({ rebuild: deps.rebuild, catalog: deps.catalog }, {
      after: (after as string | null | undefined) ?? null, ...(limit !== undefined ? { limit: limit as number } : {}),
      dryRun: dryRun === true, force: force === true,
    });
    return json(200, report, { "cache-control": "no-store" });
  }

  async function health(): Promise<Response> {
    try {
      await deps.health();
      return json(200, { ok: true, db: true, version: deps.version, catalogVersion: deps.catalog.catalogVersion }, { "cache-control": "no-store" });
    } catch {
      return json(503, { ok: false, db: false, version: deps.version }, { "cache-control": "no-store" });
    }
  }

  async function route(request: Request): Promise<{ route: string; response: Response }> {
    const url = new URL(request.url);
    const method = request.method;
    const allow = (name: string, methods: string[], run: () => Promise<Response>) => {
      if (!methods.includes(method)) {
        const response = errorResponse("method_not_allowed");
        response.headers.set("allow", methods.join(", "));
        return { route: name, response: Promise.resolve(response) };
      }
      return { route: name, response: run() };
    };
    const playerMatch = /^\/v1\/player\/([0-9A-Z]{26})$/.exec(url.pathname);
    const reviewMatch = /^\/v1\/admin\/flags\/([0-9A-Za-z]{1,40})$/.exec(url.pathname);
    const banMatch = /^\/v1\/admin\/players\/([0-9A-Z]{26})\/ban$/.exec(url.pathname);
    const chosen =
      url.pathname === "/v1/health" ? allow("health", ["GET"], health)
      : url.pathname === "/v1/register" ? allow("register", ["POST"], () => register(request))
      : url.pathname === "/v1/ledger" ? allow("ledger", ["POST"], () => ledger(request))
      : url.pathname === "/v1/tape" ? allow("tape", ["POST"], () => tape(request))
      : url.pathname === "/v1/reset" ? allow("reset", ["POST"], () => reset(request))
      : url.pathname === "/v1/leaderboard" ? allow("leaderboard", ["GET"], () => leaderboard(url))
      : url.pathname === "/v1/firsts" ? allow("firsts", ["GET"], firsts)
      : url.pathname === "/v1/admin/flags" ? allow("admin-flags", ["GET"], () => adminFlags(request, url))
      : reviewMatch ? allow("admin-review", ["POST"], () => adminReview(request, reviewMatch[1] as string))
      : url.pathname === "/v1/admin/rebuild" ? allow("admin-rebuild", ["POST"], () => adminRebuild(request))
      : banMatch ? allow("admin-ban", ["POST"], () => adminBan(request, banMatch[1] as string))
      : playerMatch ? allow("player", ["GET"], () => player(playerMatch[1] as string))
      : { route: "unknown", response: Promise.resolve(errorResponse("not_found")) };
    return { route: chosen.route, response: await chosen.response };
  }

  return async function handle(request: Request): Promise<Response> {
    const started = Date.now();
    const requestId = request.headers.get("cf-ray") ?? newId(started);
    let routeName = "unknown";
    let response: Response;
    let code: string | undefined;
    try {
      const routed = await route(request);
      routeName = routed.route;
      response = routed.response;
    } catch (error) {
      if (error instanceof ApiError) {
        code = error.code;
        response = errorResponse(error.code, error.detail, error.retryAfter);
      } else if (error instanceof Error && /overloaded/i.test(error.message)) {
        // D1 answers "D1 DB is overloaded" when its queue is full: tell the client to come back, not that we are broken.
        code = "overloaded";
        deps.log({ level: "warn", msg: "database overloaded", requestId });
        response = errorResponse("overloaded", undefined, 5);
      } else {
        code = "internal";
        deps.log({ level: "error", msg: "unhandled error", requestId, error: error instanceof Error ? error.message : String(error) });
        response = errorResponse("internal");
      }
    }
    response.headers.set("x-request-id", requestId);
    deps.log({
      level: response.status >= 500 ? "error" : "info", msg: "request", requestId, route: routeName, method: request.method,
      status: response.status, ms: Date.now() - started, ...(code ? { code } : {}),
    });
    return response;
  };
}
