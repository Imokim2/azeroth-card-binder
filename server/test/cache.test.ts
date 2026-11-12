// The edge cache for public answers: shared answers are kept and reused, and nothing private, signed, failed or live ever is.
import assert from "node:assert/strict";
import test from "node:test";
import { withEdgeCache, worthKeeping } from "../src/cache.ts";
import type { EdgeCache } from "../src/cache.ts";
import { ADMIN_TOKEN, setup } from "./harness.ts";

// A stand-in for Cloudflare's cache: keeps a copy of what is put, by address.
function fakeCache() {
  const store = new Map<string, Response>();
  const cache: EdgeCache = {
    async match(request) { return store.get(request.url)?.clone(); },
    async put(request, response) { store.set(request.url, response.clone()); },
  };
  return { cache, store };
}

const BASE = "https://cache.test";

test("retired wanted routes bypass old edge-cached lists", async () => {
  const { cache, store } = fakeCache();
  for (const path of ["/wanted", "/v1/wanted"]) {
    const request = new Request(BASE + path);
    store.set(request.url, new Response("old wanted data", {headers:{"cache-control":"public, max-age=60"}}));
    const response = await withEdgeCache(request, cache, async () => new Response("retired", {headers:{"cache-control":"no-store"}}), () => {});
    assert.equal(await response.text(), "retired");
  }
});

// The real API behind the cache, counting how often it is actually asked.
function front() {
  const env = setup();
  const { cache, store } = fakeCache();
  const pending: Promise<unknown>[] = [];
  let runs = 0;
  const get = async (path: string, init: RequestInit = {}) => {
    const request = new Request(BASE + path, init);
    const response = await withEdgeCache(request, cache, async () => { runs += 1; return env.api(request); }, (work) => pending.push(work));
    await Promise.all(pending);
    return response;
  };
  return { env, store, get, runs: () => runs };
}

test("a public answer is worked out once and then served from the cache, with the same body", async () => {
  const { get, runs, store } = front();
  const first = await get("/v1/leaderboard");
  assert.equal(first.status, 200);
  assert.equal(first.headers.get("x-cache"), "miss");
  const body = await first.text();
  const second = await get("/v1/leaderboard");
  assert.equal(second.headers.get("x-cache"), "hit");
  assert.equal(await second.text(), body);
  assert.equal(runs(), 1, "the API ran once for two requests");
  assert.equal(store.size, 1);
  // Other public routes and pages are shared the same way.
  for (const path of ["/v1/firsts", "/v1/releases", "/ladder", "/", "/download", "/privacy"]) {
    assert.equal((await get(path)).headers.get("x-cache"), "miss", path + " first");
    assert.equal((await get(path)).headers.get("x-cache"), "hit", path + " second");
  }
});

test("each address is kept on its own: a different query is a different answer", async () => {
  const { get, runs } = front();
  await get("/v1/leaderboard?limit=5");
  await get("/v1/leaderboard?limit=5");
  await get("/v1/leaderboard?limit=6");
  assert.equal(runs(), 2);
});

test("live, private, failed and non-GET requests are never kept", async () => {
  const { get, runs, store, env } = front();
  for (const path of ["/v1/health", "/status", "/status/badge.svg"]) {
    await get(path);
    assert.equal((await get(path)).headers.get("x-cache"), null, path + " is always live");
  }
  // An admin request carries the token: it is neither looked up nor stored.
  const admin = { headers: { authorization: "Bearer " + ADMIN_TOKEN } };
  await get("/v1/admin/flags", admin);
  await get("/v1/admin/flags", admin);
  await get("/admin");
  assert.equal(store.size, 0, "nothing of the above was kept");
  // A missing page, a refused method and a POST are not kept either.
  assert.equal((await get("/v1/player/01ARZ3NDEKTSV4RRFFQ69G5FAV")).status, 404);
  await get("/v1/player/01ARZ3NDEKTSV4RRFFQ69G5FAV");
  await get("/v1/ledger");
  await get("/v1/ledger", { method: "POST", body: "{}", headers: { "content-type": "application/json" } });
  assert.equal(store.size, 0);
  assert.ok(runs() > 5, "every one of those reached the API");
  // A public player who turns private stops being served after the cached copy expires; here the copy is simply gone with the store.
  void env;
});

test("worthKeeping accepts only successful GETs that ask to be shared", () => {
  const get = new Request(BASE + "/x");
  const answer = (control: string | null, status = 200, extra: Record<string, string> = {}) => new Response("ok", { status, headers: { ...(control ? { "cache-control": control } : {}), ...extra } });
  assert.equal(worthKeeping(get, answer("public, max-age=60")), true);
  assert.equal(worthKeeping(get, answer("public,max-age=300")), true);
  assert.equal(worthKeeping(get, answer("no-store")), false);
  assert.equal(worthKeeping(get, answer("private, max-age=60")), false);
  assert.equal(worthKeeping(get, answer("public, max-age=0")), false);
  assert.equal(worthKeeping(get, answer("public")), false, "no lifetime, no keeping");
  assert.equal(worthKeeping(get, answer(null)), false);
  assert.equal(worthKeeping(get, answer("public, max-age=60", 404)), false);
  assert.equal(worthKeeping(get, answer("public, max-age=60", 200, { "set-cookie": "a=b" })), false);
  assert.equal(worthKeeping(new Request(BASE + "/x", { method: "POST", body: "{}" }), answer("public, max-age=60")), false);
});

test("with no cache available (a local run, or the workers.dev address) every request just goes to the API", async () => {
  const env = setup();
  let runs = 0;
  const request = new Request(BASE + "/v1/leaderboard");
  for (let count = 0; count < 3; count++) {
    const response = await withEdgeCache(request, undefined, async () => { runs += 1; return env.api(request); }, () => {});
    assert.equal(response.status, 200);
  }
  assert.equal(runs, 3);
});
