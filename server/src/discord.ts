// Discord sign-in, the server's half (roadmap B7). The companion app sends the one-time code Discord gave the player's
// browser; this exchanges it, with the application's secret (which never leaves the server), for a token that can read
// the player's own Discord id, and returns that id. Nothing else is asked for (scope "identify") and nothing from
// Discord is stored except the id. The token is thrown away at once.
export type DiscordConfig = {
  clientId: string;
  clientSecret: string;
  redirectUri: string; // exactly as registered in the Discord developer portal
  fetch?: typeof fetch; // for tests
  // Told why a sign-in was refused: which step, Discord's HTTP status and its error name. Never a secret or a token.
  log?: (entry: Record<string, unknown>) => void;
};

const API = "https://discord.com/api/v10";
const AGENT = "WorldOfWarcards (https://github.com/Imokim2/azeroth-card-binder, 0.1)";

type FetchLike = typeof fetch;

export function discordIdentity(config: DiscordConfig): { verify(code: string): Promise<string | null> } {
  const call: FetchLike = config.fetch ?? fetch;
  return {
    async verify(code: string): Promise<string | null> {
      // A code is a short run of letters and digits; anything else is refused before it goes anywhere.
      if (!/^[A-Za-z0-9._-]{8,200}$/.test(code)) return null;
      try {
        const tokenResponse = await call(`${API}/oauth2/token`, {
          method: "POST",
          headers: { "content-type": "application/x-www-form-urlencoded", "user-agent": AGENT },
          body: new URLSearchParams({
            client_id: config.clientId, client_secret: config.clientSecret, grant_type: "authorization_code",
            code, redirect_uri: config.redirectUri,
          }).toString(),
        });
        if (!tokenResponse.ok) {
          const failure = (await tokenResponse.json().catch(() => ({}))) as { error?: unknown; error_description?: unknown };
          config.log?.({ level: "warn", msg: "discord token exchange refused", status: tokenResponse.status, error: String(failure.error ?? "").slice(0, 60), description: String(failure.error_description ?? "").slice(0, 120) });
          return null;
        }
        const token = (await tokenResponse.json()) as { access_token?: unknown; scope?: unknown };
        if (typeof token.access_token !== "string" || typeof token.scope !== "string" || !token.scope.split(/[ ,]+/).includes("identify")) return null;
        const meResponse = await call(`${API}/users/@me`, { headers: { authorization: `Bearer ${token.access_token}`, "user-agent": AGENT } });
        if (!meResponse.ok) {
          config.log?.({ level: "warn", msg: "discord user lookup refused", status: meResponse.status });
          return null;
        }
        const me = (await meResponse.json()) as { id?: unknown };
        // Give the token back so nothing is left behind that could be used later; failure here changes nothing.
        void call(`${API}/oauth2/token/revoke`, {
          method: "POST",
          headers: { "content-type": "application/x-www-form-urlencoded", "user-agent": AGENT },
          body: new URLSearchParams({ client_id: config.clientId, client_secret: config.clientSecret, token: token.access_token }).toString(),
        }).catch(() => undefined);
        return typeof me.id === "string" && /^\d{5,25}$/.test(me.id) ? me.id : null;
      } catch (error) {
        config.log?.({ level: "warn", msg: "discord could not be reached", error: error instanceof Error ? error.message.slice(0, 120) : "unknown" });
        return null;
      }
    },
  };
}
