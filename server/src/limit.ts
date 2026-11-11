// Rate limiting (roadmap, launch hardening). The API asks a `Limiter` whether a client may make another request; what
// stands behind it is decided in src/index.ts: Cloudflare's own rate-limit binding in production (it needs no database
// writes, which matter on the free plan), and an in-memory counter in tests. With no limiter configured nothing is limited.
export interface Limiter {
  // True if this key may make a request now; counts it.
  allow(key: string): Promise<boolean>;
}

// A fixed window of `periodSeconds`: at most `limit` requests per key in each. Cheap, and exact enough for a guard.
export function memoryLimiter(options: { limit: number; periodSeconds: number; now: () => number }): Limiter {
  const windows = new Map<string, { start: number; count: number }>();
  return {
    async allow(key: string): Promise<boolean> {
      const now = options.now();
      const start = now - (now % options.periodSeconds);
      // Forget windows that have ended, so the table cannot grow without bound.
      if (windows.size > 10_000) for (const [name, window] of windows) if (window.start < start) windows.delete(name);
      const window = windows.get(key);
      if (!window || window.start < start) {
        windows.set(key, { start, count: 1 });
        return true;
      }
      window.count += 1;
      return window.count <= options.limit;
    },
  };
}

// Cloudflare's rate-limit binding (wrangler.toml, [[ratelimits]]): `limit({ key })` answers whether the key is within its limit.
export type RateLimitBinding = { limit(options: { key: string }): Promise<{ success: boolean }> };

export function bindingLimiter(binding: RateLimitBinding): Limiter {
  return {
    async allow(key: string): Promise<boolean> {
      try {
        return (await binding.limit({ key })).success;
      } catch {
        return true; // if the limiter itself fails, the service stays up rather than refusing everyone
      }
    },
  };
}
