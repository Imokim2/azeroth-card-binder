// The HTTP API (docs/API.md). `createApi` turns the dependencies it is given into a function from a standard
// Request to a standard Response, so the same code runs in a Cloudflare Worker and in plain Node tests.
import { ApiError, ERRORS } from "./errors.ts";
import type { ErrorCode } from "./errors.ts";
import { canonicalJson, newId, verifySignature } from "../../packages/shared/src/crypto.ts";
import type { Catalog } from "./shared.ts";
import { downloadsFrom, releasesPageFrom } from "./releases.ts";
import type { Releases } from "./releases.ts";
import { KeyUnavailable } from "./sqlStore.ts";
import type { Limiter } from "./limit.ts";
import { binderSets, fairPlayPage, ladderPage, notFoundPage, playerPage, privacyPage, wantedPage } from "./site.ts";
import { codeSigningPage, downloadPage, faqPage, helpPage, landingPage, statusBadge, statusPage } from "./sitePages.ts";
import { ADMIN_HTML, scriptHash } from "./adminPage.ts";
import { rebuild } from "./rebuild.ts";
import { acceptReports, parseReports } from "./reports.ts";
import type { FlagRecord, IngestStore, LeaderboardStore, ModerationStore, PlayerStore, RebuildStore, ReportStore, TapeStore, TradeStore, Visibility, WantedStore } from "./store.ts";
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
  // Rate limits per client address: `general` for everything, `strict` for the routes that create or destroy things.
  // Absent means no limiting.
  limits?: { general: Limiter; strict: Limiter } | undefined;
  rebuild: RebuildStore;
  wanted: WantedStore;
  reports: ReportStore;
  adminToken?: string | undefined; // the secret that opens /v1/admin/*; without it those routes do not exist
  catalog: Catalog;
  tapeSecret?: string | undefined; // derives the roll tape; Ranked is closed (ranked_unavailable) without it
  now: () => number; // seconds
  log: Logger;
  health: () => Promise<void>; // throws when the database cannot be reached
  minClient: string; // the oldest companion app version still accepted, as x.y.z
  // The newest and the oldest accepted version of the add-on, and the newest companion app (the oldest is minClient), as
  // x.y.z. Served by /v1/releases so the app can say what is out of date. Absent: nothing is announced.
  releases?: Releases;
  releasesUrl?: string; // the public page of the project's releases (GitHub), once there is one: the download page links to it
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
    const { key, sentAt, sig, addon } = body ?? {};
    if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key) || !Number.isSafeInteger(sentAt) || typeof sig !== "string") throw new ApiError("bad_request");
    // The add-on version the player last ran, as the add-on wrote it (self-reported: it keeps honest players from rolling on
    // a version the server no longer accepts, it is not a defence against cheating). Signed with the rest when present.
    if (addon !== undefined && (typeof addon !== "string" || !/^\d+\.\d+\.\d+$/.test(addon))) throw new ApiError("bad_request", { field: "addon" });
    if (Math.abs(deps.now() - (sentAt as number)) > 86_400) throw new ApiError("bad_request", { field: "sentAt" });
    const holder = await deps.players.findByActiveKey(key);
    if (!holder) throw new ApiError("unknown_key");
    if (holder.status !== "active") throw new ApiError("banned");
    const signedBody = addon === undefined ? { key, sentAt, purpose: "tape" } : { key, sentAt, addon, purpose: "tape" };
    if (!(await verifySignature(key, sig, canonicalJson(signedBody)))) throw new ApiError("bad_signature");
    // Tape comes only to an add-on the server still accepts. Tape already handed out stays valid, so nothing earned is lost.
    if (typeof addon === "string" && deps.releases && compareVersions(addon, deps.releases.minAddon) < 0) {
      throw new ApiError("addon_too_old", { minAddon: deps.releases.minAddon, latestAddon: deps.releases.latestAddon });
    }
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

  // ---- The website (src/site.ts): plain HTML from the same data as the API ----
  const html = (status: number, body: string): Response => new Response(body, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": status === 200 ? `public, max-age=${PUBLIC_CACHE_SECONDS}` : "no-store",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "x-content-type-options": "nosniff", "x-frame-options": "DENY", "referrer-policy": "no-referrer",
    },
  });

  async function siteLadder(): Promise<Response> {
    const entries = await deps.board.top(100);
    const titles = new Map(deps.catalog.sets.map((set) => [set.code, set.title]));
    const firsts = (await deps.board.firsts()).flatMap((row) => (titles.has(row.setCode) ? [{ title: titles.get(row.setCode) as string, displayName: row.displayName, playerId: row.playerId, at: row.receivedAt }] : []));
    return html(200, ladderPage(entries.map((entry, index) => ({ rank: index + 1, playerId: entry.playerId, displayName: entry.displayName, scoreTenths: entry.score, uniqueCards: entry.uniqueCards, setsDone: entry.setsDone })), firsts));
  }

  async function siteStatus(badge = false): Promise<Response> {
    let healthy = true;
    try { await deps.health(); } catch { healthy = false; }
    if (badge) return new Response(statusBadge(healthy), {
      // A red badge is still a successfully rendered image, not a broken-image error.
      headers: { "content-type": "image/svg+xml; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "content-security-policy": "default-src 'none'; sandbox", "referrer-policy": "no-referrer" },
    });
    const response = html(healthy ? 200 : 503, statusPage(healthy, deps.now(), deps.version));
    response.headers.set("cache-control", "no-store");
    return response;
  }

  async function sitePlayer(id: string): Promise<Response> {
    const found = await deps.board.entry(id);
    const binder = found ? await deps.board.binder(id) : null;
    // A private, held, banned or unknown player all get the same page, so privacy cannot be probed.
    if (!found || !binder) return html(404, notFoundPage());
    const { entry, rank } = found;
    return html(200, playerPage({ displayName: entry.displayName, rank, scoreTenths: entry.score, uniqueCards: entry.uniqueCards, setsDone: entry.setsDone, updatedAt: entry.updatedAt }, binderSets(deps.catalog, binder.counts, binder.shiny)));
  }

  // ---- The wanted board ----
  const MAX_WANTED = 60;

  // A player uploads the cards they are looking for. Signed by their key. Only public players are listed; a private player's
  // list is not kept.
  async function setWanted(request: Request): Promise<Response> {
    checkClient(request, deps);
    const body = (await readJson(request)) as Record<string, unknown> | null;
    const { key, sentAt, cards, sig } = body ?? {};
    if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key) || !Number.isSafeInteger(sentAt) || typeof sig !== "string") throw new ApiError("bad_request");
    if (!Array.isArray(cards) || cards.length > MAX_WANTED || new Set(cards).size !== cards.length) throw new ApiError("bad_request", { field: "cards" });
    for (const card of cards) if (typeof card !== "string" || !deps.catalog.cards[card]) throw new ApiError("bad_request", { field: "cards" });
    if (Math.abs(deps.now() - (sentAt as number)) > 86_400) throw new ApiError("bad_request", { field: "sentAt" });
    const holder = await deps.players.findByActiveKey(key);
    if (!holder) throw new ApiError("unknown_key");
    if (holder.status !== "active") throw new ApiError("banned");
    if (!(await verifySignature(key, sig, canonicalJson({ key, sentAt, cards, purpose: "wanted" })))) throw new ApiError("bad_signature");
    const listed = holder.visibility === "public";
    await deps.wanted.setWanted(holder.id, listed ? (cards as string[]) : [], deps.now());
    return json(200, { stored: listed ? cards.length : 0, listed }, { "cache-control": "no-store" });
  }

  // Reports about other players. Signed by the reporter's key. Stored as notes for a person to read.
  async function report(request: Request): Promise<Response> {
    checkClient(request, deps);
    const body = (await readJson(request)) as Record<string, unknown> | null;
    const { key, sentAt, sig } = body ?? {};
    if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key) || !Number.isSafeInteger(sentAt) || typeof sig !== "string") throw new ApiError("bad_request");
    const reports = parseReports(body?.["reports"]); // checked and tidied; the signature covers what was sent
    if (Math.abs(deps.now() - (sentAt as number)) > 86_400) throw new ApiError("bad_request", { field: "sentAt" });
    const holder = await deps.players.findByActiveKey(key);
    if (!holder) throw new ApiError("unknown_key");
    if (holder.status !== "active") throw new ApiError("banned");
    if (!(await verifySignature(key, sig, canonicalJson({ key, sentAt, reports: body?.["reports"], purpose: "report" })))) throw new ApiError("bad_signature");
    return json(200, await acceptReports(deps, holder, reports), { "cache-control": "no-store" });
  }

  // For the people who review: what was reported about one player.
  async function adminReports(request: Request, url: URL): Promise<Response> {
    await requireAdmin(request);
    const player = url.searchParams.get("player") ?? "";
    if (!/^[0-9A-Z]{26}$/.test(player)) throw new ApiError("bad_request", { field: "player" });
    const asked = Number(url.searchParams.get("limit") ?? 50);
    const limit = Number.isInteger(asked) && asked >= 1 ? Math.min(asked, 200) : 50;
    const reports = (await deps.reports.about(player, limit)).map(({ token, ...rest }) => { void token; return rest; });
    return json(200, { reports }, { "cache-control": "no-store" });
  }

  // The review screen. It holds no data and no secret, so it needs no token to load; every call it makes does. With no admin
  // token configured it does not exist, like the routes it uses. Not cached, not indexed, and it may run only its own script.
  async function adminScreen(): Promise<Response> {
    if (!deps.adminToken) throw new ApiError("not_found");
    return new Response(ADMIN_HTML(), {
      headers: {
        "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex, nofollow",
        "content-security-policy": `default-src 'none'; script-src 'sha256-${await scriptHash()}'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
        "x-content-type-options": "nosniff", "x-frame-options": "DENY", "referrer-policy": "no-referrer",
      },
    });
  }

  async function wantedBoard(): Promise<Response> {
    const entries = await deps.wanted.board(100);
    return json(200, { generatedAt: deps.now(), players: entries.map((entry) => ({ playerId: entry.playerId, displayName: entry.displayName, characters: entry.characters, cards: entry.cards, updatedAt: entry.updatedAt })) }, { "cache-control": `public, max-age=${PUBLIC_CACHE_SECONDS}` });
  }

  async function siteWanted(): Promise<Response> {
    const entries = await deps.wanted.board(100);
    return html(200, wantedPage(entries, deps.catalog));
  }

  // What is current: the app and add-on versions. Public and cacheable; the app asks at start-up and now and then.
  function releases(): Response {
    const known = deps.releases;
    return json(200, {
      app: { latest: known?.latestApp ?? deps.minClient, min: deps.minClient },
      addon: { latest: known?.latestAddon ?? "0.0.0", min: known?.minAddon ?? "0.0.0" },
      ...(known?.signed ? { signed: known.signed } : {}),
    }, { "cache-control": "public, max-age=300" });
  }

  async function health(): Promise<Response> {
    try {
      await deps.health();
      return json(200, { ok: true, db: true, version: deps.version, catalogVersion: deps.catalog.catalogVersion }, { "cache-control": "no-store" });
    } catch {
      return json(503, { ok: false, db: false, version: deps.version }, { "cache-control": "no-store" });
    }
  }

  // The routes that make or remove things, or take secrets, get the tighter limit.
  const STRICT = /^\/v1\/(register|reset|delete|report|admin\/.*)$/;
  async function enforceLimits(request: Request, pathname: string): Promise<void> {
    if (!deps.limits || pathname === "/v1/health") return;
    const client = request.headers.get("cf-connecting-ip") ?? "unknown";
    const limiter = request.method === "POST" && STRICT.test(pathname) ? deps.limits.strict : deps.limits.general;
    const key = (limiter === deps.limits.strict ? "strict:" : "general:") + client;
    if (!(await limiter.allow(key))) throw new ApiError("rate_limited", undefined, 60);
  }

  // Delete everything held about the player. Signed by their key and confirmed by the exact words, because it cannot be undone.
  async function deleteAccount(request: Request): Promise<Response> {
    checkClient(request, deps);
    const body = (await readJson(request)) as Record<string, unknown> | null;
    const { key, sentAt, confirm, sig } = body ?? {};
    if (typeof key !== "string" || !/^[0-9a-f]{64}$/.test(key) || !Number.isSafeInteger(sentAt) || typeof sig !== "string") throw new ApiError("bad_request");
    if (confirm !== "delete my data") throw new ApiError("bad_request", { field: "confirm" });
    if (Math.abs(deps.now() - (sentAt as number)) > 86_400) throw new ApiError("bad_request", { field: "sentAt" });
    const holder = await deps.players.findByActiveKey(key);
    if (!holder) throw new ApiError("unknown_key");
    // A banned player's record is kept, so a ban cannot be wiped by deleting the account and signing up again.
    if (holder.status !== "active") throw new ApiError("banned");
    if (!(await verifySignature(key, sig, canonicalJson({ key, sentAt, confirm, purpose: "delete" })))) throw new ApiError("bad_signature");
    await deps.players.deletePlayer(holder.id);
    return json(200, { deleted: true }, { "cache-control": "no-store" });
  }

  async function route(request: Request): Promise<{ route: string; response: Response }> {
    const url = new URL(request.url);
    const method = request.method;
    await enforceLimits(request, url.pathname);
    const allow = (name: string, methods: string[], run: () => Promise<Response>) => {
      if (!methods.includes(method)) {
        const response = errorResponse("method_not_allowed");
        response.headers.set("allow", methods.join(", "));
        return { route: name, response: Promise.resolve(response) };
      }
      return { route: name, response: run() };
    };
    const playerMatch = /^\/v1\/player\/([0-9A-Z]{26})$/.exec(url.pathname);
    const pageMatch = /^\/player\/([0-9A-Z]{26})$/.exec(url.pathname);
    const reviewMatch = /^\/v1\/admin\/flags\/([0-9A-Za-z]{1,40})$/.exec(url.pathname);
    const banMatch = /^\/v1\/admin\/players\/([0-9A-Z]{26})\/ban$/.exec(url.pathname);
    const chosen =
      url.pathname === "/" ? allow("site-home", ["GET"], async () => html(200, landingPage()))
      : url.pathname === "/ladder" ? allow("site-ladder", ["GET"], siteLadder)
      : url.pathname === "/download" ? allow("site-download", ["GET"], async () => html(200, downloadPage({ ...downloadsFrom(deps.releases), releasesUrl: releasesPageFrom(deps.releasesUrl) })))
      : url.pathname === "/help" ? allow("site-help", ["GET"], async () => html(200, helpPage()))
      : url.pathname === "/faq" ? allow("site-faq", ["GET"], async () => html(200, faqPage()))
      : url.pathname === "/status" ? allow("site-status", ["GET"], () => siteStatus())
      : url.pathname === "/status/badge.svg" ? allow("site-status-badge", ["GET"], () => siteStatus(true))
      : url.pathname === "/wanted" ? allow("site-wanted", ["GET"], siteWanted)
      : url.pathname === "/fair-play" ? allow("site-fair-play", ["GET"], async () => html(200, fairPlayPage()))
      : url.pathname === "/code-signing-policy" ? allow("site-code-signing", ["GET"], async () => html(200, codeSigningPage()))
      : url.pathname === "/privacy" ? allow("site-privacy", ["GET"], async () => html(200, privacyPage()))
      : pageMatch ? allow("site-player", ["GET"], () => sitePlayer(pageMatch[1] as string))
      : url.pathname === "/v1/health" ? allow("health", ["GET"], health)
      : url.pathname === "/v1/releases" ? allow("releases", ["GET"], async () => releases())
      : url.pathname === "/v1/register" ? allow("register", ["POST"], () => register(request))
      : url.pathname === "/v1/ledger" ? allow("ledger", ["POST"], () => ledger(request))
      : url.pathname === "/v1/tape" ? allow("tape", ["POST"], () => tape(request))
      : url.pathname === "/v1/reset" ? allow("reset", ["POST"], () => reset(request))
      : url.pathname === "/v1/delete" ? allow("delete", ["POST"], () => deleteAccount(request))
      : url.pathname === "/v1/leaderboard" ? allow("leaderboard", ["GET"], () => leaderboard(url))
      : url.pathname === "/v1/firsts" ? allow("firsts", ["GET"], firsts)
      : url.pathname === "/v1/wanted" ? allow("wanted", ["GET", "POST"], () => (method === "POST" ? setWanted(request) : wantedBoard()))
      : url.pathname === "/v1/report" ? allow("report", ["POST"], () => report(request))
      : url.pathname === "/admin" ? allow("admin-screen", ["GET"], adminScreen)
      : url.pathname === "/v1/admin/reports" ? allow("admin-reports", ["GET"], () => adminReports(request, url))
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
