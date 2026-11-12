// Cloudflare Access in front of the admin panel (docs/runbooks/ADMIN.md). Access puts a sign-in (Google, GitHub, a one-time code
// to an allowed email) in front of /admin and /v1/admin/*, and sends the Worker a signed token with who signed in. The Worker
// checks that token itself, so a request that did not come through Access (the workers.dev address, or a forged header) is refused,
// and the panel can say who did what.
//
// The token is a JWT signed RS256 by the team's keys, published at https://<team>/cdn-cgi/access/certs. It is accepted only if
// its signature is good, it is not expired, it was issued by this team and it is for this application (the "audience" tag).

export type AccessConfig = { team: string; audience: string }; // team: "yourteam.cloudflareaccess.com"
type Jwk = { kid?: string; kty: string; n: string; e: string; alg?: string };
type FetchLike = (url: string) => Promise<Response>;

const KEYS_KEPT_FOR = 3600; // seconds; the keys rotate every few weeks, and an unknown key id forces a look sooner

function base64url(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (text.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function readJson(part: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(new TextDecoder().decode(base64url(part))) as unknown;
    return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

// The team domain as typed in the settings, as a bare host name ("team.cloudflareaccess.com"), or null if it is not one.
export function teamHost(value: string | undefined): string | null {
  const host = (value ?? "").trim().replace(/^https:\/\//, "").replace(/\/+$/, "");
  return /^[a-z0-9-]+(\.[a-z0-9-]+)*\.cloudflareaccess\.com$/i.test(host) ? host.toLowerCase() : null;
}

// Returns a function that says who signed in through Access for a request, or null when the request carries no good token.
export function accessVerifier(config: AccessConfig, now: () => number, fetchKeys: FetchLike = (url) => fetch(url)) {
  let keys: Jwk[] = [];
  let fetchedAt = -Infinity;

  async function load(): Promise<void> {
    const response = await fetchKeys(`https://${config.team}/cdn-cgi/access/certs`);
    if (!response.ok) throw new Error("the Access keys could not be fetched");
    const body = (await response.json()) as { keys?: Jwk[] };
    keys = Array.isArray(body.keys) ? body.keys.filter((key) => key.kty === "RSA" && typeof key.n === "string" && typeof key.e === "string") : [];
    fetchedAt = now();
  }

  async function keyFor(kid: string): Promise<Jwk | null> {
    if (now() - fetchedAt > KEYS_KEPT_FOR) await load();
    let key = keys.find((candidate) => candidate.kid === kid);
    // An unknown key id may mean the keys just rotated: look once more, but not for every forged token in a flood.
    if (!key && now() - fetchedAt > 60) {
      await load();
      key = keys.find((candidate) => candidate.kid === kid);
    }
    return key ?? null;
  }

  return async function who(request: Request): Promise<string | null> {
    try {
      const token = request.headers.get("cf-access-jwt-assertion");
      const parts = token ? token.split(".") : [];
      if (parts.length !== 3 || token!.length > 8192) return null;
      const [headerPart, payloadPart, signaturePart] = parts as [string, string, string];
      const header = readJson(headerPart);
      const payload = readJson(payloadPart);
      if (!header || !payload || header["alg"] !== "RS256" || typeof header["kid"] !== "string") return null;
      const jwk = await keyFor(header["kid"]);
      if (!jwk) return null;
      const key = await crypto.subtle.importKey("jwk", { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
      const signed = new TextEncoder().encode(`${headerPart}.${payloadPart}`);
      if (!(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, base64url(signaturePart), signed))) return null;
      const at = now();
      const audience = payload["aud"];
      if (payload["iss"] !== `https://${config.team}`) return null;
      if (!(Array.isArray(audience) ? audience.includes(config.audience) : audience === config.audience)) return null;
      if (typeof payload["exp"] !== "number" || payload["exp"] <= at) return null;
      if (typeof payload["nbf"] === "number" && payload["nbf"] > at + 60) return null;
      // A person has an email; a service token (a script) has a common name.
      const name = typeof payload["email"] === "string" && payload["email"] ? payload["email"] : typeof payload["common_name"] === "string" ? payload["common_name"] : "";
      return name && name.length <= 200 ? name : null;
    } catch {
      return null;
    }
  };
}
