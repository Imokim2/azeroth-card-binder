// A shared copy of public answers, kept at Cloudflare's edge by the Workers Cache API, so the ladder, the first-to-finish list, the
// wanted board, public player pages, the site pages and the release announcement are worked out once a minute (or five) however many
// people ask, instead of once per request. Every refresh of the companion app used to read a few hundred database rows; now most
// of them are answered from here without touching the database or running the code.
//
// What is kept is decided by the answer itself: a successful GET that the server marked \`cache-control: public, max-age=N\`. Anything
// private, per-player, signed, an error, a POST or a health check carries no such mark (or is excluded by name) and is never kept.
// The Cache API only works on a custom domain: on the workers.dev address it quietly keeps nothing, which does no harm.

export type EdgeCache = {
  match(request: Request): Promise<Response | undefined>;
  put(request: Request, response: Response): Promise<void>;
};

// Never kept, whatever they say: health and status must be live, and the admin screen is not for sharing.
const NEVER = new Set(["/v1/health", "/status", "/status/badge.svg", "/admin"]);

// Is this answer one to keep for others? A 200 to a GET that asks to be shared and has no cookie.
export function worthKeeping(request: Request, response: Response): boolean {
  if (request.method !== "GET" || response.status !== 200) return false;
  if (NEVER.has(new URL(request.url).pathname)) return false;
  if (response.headers.has("set-cookie")) return false;
  const control = response.headers.get("cache-control") ?? "";
  const age = /(?:^|,)\s*max-age=(\d+)/.exec(control);
  return /(?:^|,)\s*public(?:\s*,|$)/.test(control) && !/no-store|private/.test(control) && age !== null && Number(age[1]) > 0;
}

export async function withEdgeCache(
  request: Request, cache: EdgeCache | undefined, run: () => Promise<Response>, waitUntil: (work: Promise<unknown>) => void,
): Promise<Response> {
  const pathname = new URL(request.url).pathname;
  // Only plain GETs without credentials are looked up, so a signed or admin request can never be answered from, or into, the cache.
  if (!cache || request.method !== "GET" || NEVER.has(pathname) || request.headers.has("authorization")) return run();
  const key = new Request(request.url, { method: "GET" });
  const hit = await cache.match(key);
  if (hit) {
    const answer = new Response(hit.body, hit);
    answer.headers.set("x-cache", "hit");
    return answer;
  }
  const response = await run();
  if (!worthKeeping(request, response)) return response;
  waitUntil(cache.put(key, response.clone()));
  const answer = new Response(response.body, response);
  answer.headers.set("x-cache", "miss");
  return answer;
}
