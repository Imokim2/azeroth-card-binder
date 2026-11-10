// The server's half of the Discord sign-in, against a pretend Discord.
import assert from "node:assert/strict";
import test from "node:test";
import { discordIdentity } from "../src/discord.ts";
import { newPlayer, registration, setup } from "./harness.ts";

type Call = { url: string; init: RequestInit | undefined };

function pretendDiscord(options: { scope?: string; tokenStatus?: number; meStatus?: number; id?: unknown } = {}) {
  const calls: Call[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    const address = String(url);
    calls.push({ url: address, init });
    if (address.endsWith("/oauth2/token")) {
      const body = new URLSearchParams(String(init?.body));
      if (body.get("code") !== "goodcode1234" || options.tokenStatus) return new Response("{}", { status: options.tokenStatus ?? 400 });
      return Response.json({ access_token: "token-abc", token_type: "Bearer", scope: options.scope ?? "identify" });
    }
    if (address.endsWith("/users/@me")) {
      if (options.meStatus) return new Response("{}", { status: options.meStatus });
      return Response.json({ id: options.id ?? "123456789012345678", username: "alice" });
    }
    return new Response("{}", { status: 200 }); // the revoke call
  }) as typeof fetch;
  return { calls, identity: discordIdentity({ clientId: "1569844563957260298", clientSecret: "secret-value", redirectUri: "http://127.0.0.1:53682/callback", fetch: fetcher }) };
}

test("a good code becomes the player's Discord id, and the token is given back", async () => {
  const { calls, identity } = pretendDiscord();
  assert.equal(await identity.verify("goodcode1234"), "123456789012345678");
  const exchange = calls[0]!;
  assert.equal(exchange.url, "https://discord.com/api/v10/oauth2/token");
  const form = new URLSearchParams(String(exchange.init?.body));
  assert.deepEqual([form.get("client_id"), form.get("grant_type"), form.get("redirect_uri"), form.get("client_secret")],
    ["1569844563957260298", "authorization_code", "http://127.0.0.1:53682/callback", "secret-value"]);
  assert.equal((calls[1]!.init?.headers as Record<string, string>)["authorization"], "Bearer token-abc");
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.ok(calls.some((call) => call.url.endsWith("/oauth2/token/revoke")), "the token is revoked");
});

test("anything that goes wrong is a refusal, never an id", async () => {
  assert.equal(await pretendDiscord().identity.verify("wrongcode123"), null);
  assert.equal(await pretendDiscord({ tokenStatus: 401 }).identity.verify("goodcode1234"), null);
  assert.equal(await pretendDiscord({ meStatus: 401 }).identity.verify("goodcode1234"), null);
  assert.equal(await pretendDiscord({ scope: "email" }).identity.verify("goodcode1234"), null, "the sign-in must grant identify");
  assert.equal(await pretendDiscord({ id: "not a number" }).identity.verify("goodcode1234"), null);
  assert.equal(await pretendDiscord({ id: 12345678 }).identity.verify("goodcode1234"), null);
  // Codes that cannot be real never reach Discord at all.
  const { calls, identity } = pretendDiscord();
  for (const code of ["", "short", "has space in it", "x".repeat(201), "semi;colon&grant_type=x"]) assert.equal(await identity.verify(code), null, code);
  assert.equal(calls.length, 0);
  // Discord unreachable.
  const broken = discordIdentity({ clientId: "1", clientSecret: "s", redirectUri: "r", fetch: (async () => { throw new Error("offline"); }) as typeof fetch });
  assert.equal(await broken.verify("goodcode1234"), null);
});

test("registering through the API works with the Discord check in place", async () => {
  const env = setup();
  env.deps.identity = pretendDiscord().identity;
  const player = newPlayer("alice");
  const ok = await env.call("/v1/register", { body: registration(player, { identityToken: "goodcode1234" }) });
  assert.equal(ok.status, 200);
  const refused = await env.call("/v1/register", { body: registration(newPlayer("bob"), { identityToken: "wrongcode123" }) });
  assert.equal(refused.status, 401);
  assert.equal(((await refused.json()) as { error: { code: string } }).error.code, "bad_identity");
});
