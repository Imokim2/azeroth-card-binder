// Where the app finds the server. Public addresses only: nothing secret ever belongs in this file.
export const SERVERS = {
  // The test server (Cloudflare Workers, deployed from server/wrangler.toml with --env staging).
  staging: "https://warcards-api-staging.worldofwarcards.workers.dev",
  // Not created yet.
  production: "",
} as const;

export type ServerName = keyof typeof SERVERS;
