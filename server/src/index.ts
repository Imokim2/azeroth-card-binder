// The Cloudflare Worker entry point. It only wires configuration to the pieces in the other files; there is no
// logic here. Settings come from wrangler.toml (variables) and the dashboard or `wrangler secret` (secrets).
import { createApi } from "./api.ts";
import type { Deps } from "./api.ts";
import { discordIdentity } from "./discord.ts";
import { bindingLimiter } from "./limit.ts";
import type { RateLimitBinding } from "./limit.ts";
import { fromD1 } from "./db.ts";
import { runMaintenance } from "./maintenance.ts";
import type { D1Like } from "./db.ts";
import { SqlStore } from "./sqlStore.ts";
import type { Catalog } from "./shared.ts";
import catalog from "../../packages/shared/catalog.json";
import bundledRelease from "./releases.json";
import { accessVerifier, teamHost } from "./access.ts";
import { withEdgeCache } from "./cache.ts";
import type { EdgeCache } from "./cache.ts";
import { releasesFrom } from "./releases.ts";
import type { BundledRelease } from "./releases.ts";

export interface Env {
  DB: D1Like;
  MIN_CLIENT: string;
  LATEST_APP?: string; // the newest companion app and add-on, and the oldest add-on, as x.y.z (see /v1/releases)
  LATEST_ADDON?: string;
  MIN_ADDON?: string;
  RELEASES_URL?: string; // the project's public releases page on GitHub, once the repository is public (the download page links to it)
  PRIVACY_EMAIL?: string; // where people can write about their data (shown on the privacy page), once the address exists
  SUPPORT_PAYPAL_ACCOUNT?: string; // recipient email or merchant ID, set with wrangler secret put; never printed in site HTML
  VERSION: string;
  TAPE_SECRET?: string; // a secret (wrangler secret put TAPE_SECRET); without it Ranked is closed
  RATE_GENERAL?: RateLimitBinding; // Cloudflare rate-limit bindings (wrangler.toml); without them nothing is limited
  RATE_STRICT?: RateLimitBinding;
  DISCORD_CLIENT_ID?: string; // the Discord application (a public variable, see wrangler.toml)
  DISCORD_REDIRECT_URI?: string; // the address the companion app listens on while signing in
  DISCORD_CLIENT_SECRET?: string; // a secret (wrangler secret put DISCORD_CLIENT_SECRET); without it registration stays closed
  ADMIN_TOKEN?: string; // a secret (wrangler secret put ADMIN_TOKEN); without it the admin routes do not exist
  ACCESS_TEAM_DOMAIN?: string; // Cloudflare Access in front of the admin panel (docs/runbooks/ADMIN.md): the team domain, e.g. myteam.cloudflareaccess.com
  ACCESS_AUD?: string; // ... and the application's audience tag. Set both, or neither; if either is set the panel needs a good Access sign-in.
}

const log: Deps["log"] = (entry) => console.log(JSON.stringify({ at: new Date().toISOString(), ...entry }));

// The Workers runtime provides these; the type checker is not told about them.
declare const caches: { default: EdgeCache } | undefined;
type Context = { waitUntil(work: Promise<unknown>): void };

// Access is switched on by its two settings. Half-set or malformed, it refuses everyone (the panel closes) rather than opening up.
// The verifier keeps Access's public keys, so it lives as long as the Worker instance and not one request.
let accessKept: { team: string; audience: string; verify: NonNullable<Deps["access"]> } | undefined;
function accessFrom(env: Env): Deps["access"] {
  if (!env.ACCESS_TEAM_DOMAIN && !env.ACCESS_AUD) return undefined;
  const team = teamHost(env.ACCESS_TEAM_DOMAIN);
  const audience = (env.ACCESS_AUD ?? "").trim();
  if (!team || !/^[0-9a-f]{32,128}$/i.test(audience)) return async () => null;
  if (accessKept?.team !== team || accessKept.audience !== audience) {
    accessKept = { team, audience, verify: accessVerifier({ team, audience }, () => Math.floor(Date.now() / 1000)) };
  }
  return accessKept.verify;
}

export default {
  async fetch(request: Request, env: Env, context: Context): Promise<Response> {
    const db = fromD1(env.DB);
    const store = new SqlStore(db);
    const handle = createApi({
      players: store, ingest: store, board: store, tapes: store, trades: store, moderation: store, admin: store, access: accessFrom(env), rebuild: store, wanted: store, reports: store, catalog: catalog as Catalog, tapeSecret: env.TAPE_SECRET, adminToken: env.ADMIN_TOKEN,
      now: () => Math.floor(Date.now() / 1000), log,
      health: async () => { await db.all("SELECT 1"); },
      minClient: env.MIN_CLIENT, version: env.VERSION,
      releases: releasesFrom(env, bundledRelease as BundledRelease),
      ...(env.RELEASES_URL ? { releasesUrl: env.RELEASES_URL } : {}),
      ...(env.PRIVACY_EMAIL ? { privacyEmail: env.PRIVACY_EMAIL } : {}),
      ...(env.SUPPORT_PAYPAL_ACCOUNT ? { supportPayPalAccount: env.SUPPORT_PAYPAL_ACCOUNT } : {}),
      ...(env.RATE_GENERAL && env.RATE_STRICT ? { limits: { general: bindingLimiter(env.RATE_GENERAL), strict: bindingLimiter(env.RATE_STRICT) } } : {}),
      // Registration opens only when the Discord application is fully configured.
      ...(env.DISCORD_CLIENT_ID && env.DISCORD_CLIENT_SECRET && env.DISCORD_REDIRECT_URI
        ? { identity: discordIdentity({ clientId: env.DISCORD_CLIENT_ID, clientSecret: env.DISCORD_CLIENT_SECRET, redirectUri: env.DISCORD_REDIRECT_URI, log }) }
        : {}),
      // identity: added with the Discord sign-in (roadmap B7); until then registration answers "registration_closed".
    });
    // Public answers are shared at the edge (src/cache.ts); everything else goes straight to the API.
    return withEdgeCache(request, typeof caches === "undefined" ? undefined : caches.default, () => handle(request), (work) => context.waitUntil(work));
  },
  // Hourly (see wrangler.toml): pair up trades and write off the ones nobody confirmed.
  async scheduled(_event: unknown, env: Env): Promise<void> {
    const store = new SqlStore(fromD1(env.DB));
    const result = await runMaintenance({ ingest: store, trades: store, catalog: catalog as Catalog, now: () => Math.floor(Date.now() / 1000) });
    log({ level: "info", msg: "maintenance", ...result });
  },
};
