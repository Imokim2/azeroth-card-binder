// Where the app finds the server. Public addresses only: nothing secret ever belongs in this file.
export const SERVERS = {
  // The test server (Cloudflare Workers, deployed from server/wrangler.toml with --env staging). The older
  // workers.dev address, warcards-api-staging.worldofwarcards.workers.dev, still answers for apps installed before the domain.
  staging: "https://staging.worldofwarcards.co.uk",
  // The real server: the website and the API, on the project's own domain.
  production: "https://worldofwarcards.co.uk",
} as const;

// What a normal install talks to. Set WARCARDS_SERVER to use another server (the staging one, say).
export const DEFAULT_SERVER: ServerName = "production";

export type ServerName = keyof typeof SERVERS;
