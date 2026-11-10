// The HTTP API (docs/API.md). `createApi` turns the dependencies it is given into a function from a standard
// Request to a standard Response, so the same code runs in a Cloudflare Worker and in plain Node tests.
import { ApiError, ERRORS } from "./errors.ts";
import type { ErrorCode } from "./errors.ts";
import { canonicalJson, newId, verifySignature } from "../../packages/shared/src/crypto.ts";
import type { Catalog } from "./shared.ts";
import { KeyUnavailable } from "./sqlStore.ts";
import type { IngestStore, LeaderboardStore, PlayerStore, Visibility } from "./store.ts";
import { SUPPORTED_SPEC_VERSIONS, acceptUpload, parseUpload } from "./upload.ts";

export const MAX_BODY_BYTES = 2_000_000;
const PUBLIC_CACHE_SECONDS = 60;

export type Logger = (entry: Record<string, unknown>) => void;

export type Deps = {
  players: PlayerStore;
  ingest: IngestStore;
  board: LeaderboardStore;
  catalog: Catalog;
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
    return json(200, {
      generatedAt: deps.now(),
      entries: entries.map((entry, index) => ({
        rank: index + 1, playerId: entry.playerId, displayName: entry.displayName, scoreTenths: entry.score,
        uniqueCards: entry.uniqueCards, setsDone: entry.setsDone,
      })),
    }, { "cache-control": `public, max-age=${PUBLIC_CACHE_SECONDS}` });
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
    const chosen =
      url.pathname === "/v1/health" ? allow("health", ["GET"], health)
      : url.pathname === "/v1/register" ? allow("register", ["POST"], () => register(request))
      : url.pathname === "/v1/ledger" ? allow("ledger", ["POST"], () => ledger(request))
      : url.pathname === "/v1/leaderboard" ? allow("leaderboard", ["GET"], () => leaderboard(url))
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
