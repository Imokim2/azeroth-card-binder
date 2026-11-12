// Cloudflare Access in front of the admin panel: the Worker checks Access's signed token itself, so only a request that came through
// Access, for this application, from this team, and not expired, is let in; and with Access set up the panel needs it as well as the token.
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import test from "node:test";
import { accessVerifier, teamHost } from "../src/access.ts";
import { ADMIN_TOKEN, setup } from "./harness.ts";

const TEAM = "warcards.cloudflareaccess.com";
const AUD = "a".repeat(64);
const NOW = 1_700_000_000;

const b64 = (data: string | Uint8Array) => Buffer.from(data).toString("base64url");

async function newKey(kid: string) {
  const pair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]) as webcrypto.CryptoKeyPair;
  const jwk = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as { n: string; e: string; kty: string };
  return { kid, privateKey: pair.privateKey, jwk: { kid, kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256" } };
}
type Key = Awaited<ReturnType<typeof newKey>>;

async function token(key: Key, claims: Record<string, unknown> = {}, header: Record<string, unknown> = {}) {
  const head = b64(JSON.stringify({ alg: "RS256", kid: key.kid, typ: "JWT", ...header }));
  const body = b64(JSON.stringify({ iss: `https://${TEAM}`, aud: [AUD], exp: NOW + 600, iat: NOW, email: "ollie@example.com", ...claims }));
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, new TextEncoder().encode(`${head}.${body}`)));
  return `${head}.${body}.${b64(signature)}`;
}

function verifierWith(keys: Key[]) {
  const state = { fetches: 0, now: NOW, keys };
  const verify = accessVerifier({ team: TEAM, audience: AUD }, () => state.now, async (url) => {
    state.fetches += 1;
    assert.equal(url, `https://${TEAM}/cdn-cgi/access/certs`);
    return Response.json({ keys: state.keys.map((key) => key.jwk) });
  });
  const ask = (jwt: string | null) => verify(new Request("https://warcards.test/admin", { headers: jwt ? { "cf-access-jwt-assertion": jwt } : {} }));
  return { state, ask, verify };
}

test("a token signed by the team's key, for this application and not expired, says who signed in", async () => {
  const key = await newKey("k1");
  const { ask, state } = verifierWith([key]);
  assert.equal(await ask(await token(key)), "ollie@example.com");
  assert.equal(await ask(await token(key, { aud: AUD })), "ollie@example.com", "a single audience is as good as a list");
  assert.equal(await ask(await token(key, { email: undefined, common_name: "deploy-script.access" })), "deploy-script.access", "a service token has a name, not an email");
  assert.equal(state.fetches, 1, "the keys are fetched once and kept");
});

test("a token that is missing, forged, expired, for another application or from another team is refused", async () => {
  const key = await newKey("k1");
  const other = await newKey("k1"); // same key id, different key: a forgery
  const { ask } = verifierWith([key]);
  assert.equal(await ask(null), null);
  assert.equal(await ask("not.a.jwt"), null);
  assert.equal(await ask("a.b"), null);
  assert.equal(await ask(await token(other)), null, "signed by a key that is not Access's");
  assert.equal(await ask(await token(key, { exp: NOW - 1 })), null, "expired");
  assert.equal(await ask(await token(key, { exp: undefined })), null, "no expiry");
  assert.equal(await ask(await token(key, { nbf: NOW + 3600 })), null, "not yet valid");
  assert.equal(await ask(await token(key, { aud: ["b".repeat(64)] })), null, "another application");
  assert.equal(await ask(await token(key, { iss: "https://evil.cloudflareaccess.com" })), null, "another team");
  assert.equal(await ask(await token(key, { email: "", common_name: undefined })), null, "nobody in particular");
  assert.equal(await ask(await token(key, {}, { alg: "none" })), null, "no signature algorithm");
  assert.equal(await ask(await token(key, {}, { alg: "HS256" })), null, "not the algorithm Access uses");
  // A token whose body was changed after signing no longer verifies.
  const good = await token(key);
  const [head, , signature] = good.split(".") as [string, string, string];
  const swapped = `${head}.${b64(JSON.stringify({ iss: `https://${TEAM}`, aud: [AUD], exp: NOW + 600, email: "mallory@example.com" }))}.${signature}`;
  assert.equal(await ask(swapped), null);
});

test("when Access rotates its keys the new one is found, but a flood of unknown key ids does not hammer Access", async () => {
  const first = await newKey("k1");
  const second = await newKey("k2");
  const { ask, state } = verifierWith([first]);
  assert.equal(await ask(await token(first)), "ollie@example.com");
  state.keys = [first, second];
  state.now += 120;
  assert.equal(await ask(await token(second)), "ollie@example.com", "a new key id makes the keys be fetched again");
  const stranger = await newKey("k9");
  const before = state.fetches;
  for (let count = 0; count < 5; count++) assert.equal(await ask(await token(stranger)), null);
  assert.ok(state.fetches - before <= 1, "an unknown key id is looked up at most once a minute");
  state.now += 7200;
  assert.equal(await ask(await token(first, { exp: NOW + 100_000 })), "ollie@example.com");
  assert.ok(state.fetches > before, "old keys are fetched again after an hour");
});

test("the team domain must be a Cloudflare Access address", () => {
  assert.equal(teamHost("warcards.cloudflareaccess.com"), "warcards.cloudflareaccess.com");
  assert.equal(teamHost(" https://Warcards.cloudflareaccess.com/ "), "warcards.cloudflareaccess.com");
  for (const bad of [undefined, "", "evil.com", "warcards.cloudflareaccess.com.evil.com", "https://evil.com/warcards.cloudflareaccess.com", "a b.cloudflareaccess.com"]) {
    assert.equal(teamHost(bad), null, String(bad));
  }
});

test("with Access set up the panel and every admin route need a good sign-in as well as the token", async () => {
  const key = await newKey("k1");
  const env = setup();
  const { verify } = verifierWith([key]);
  env.deps.access = verify;
  const withToken = { authorization: "Bearer " + ADMIN_TOKEN };
  const signedIn = { ...withToken, "cf-access-jwt-assertion": await token(key) };
  // Token alone (for instance through the workers.dev address, which Access does not cover): refused.
  assert.equal((await env.call("/v1/admin/flags", { headers: withToken })).status, 401);
  assert.equal((await env.call("/v1/admin/players", { headers: withToken })).status, 401);
  assert.equal((await env.call("/admin")).status, 401);
  // Sign-in alone: refused. Both: let in, and the panel says who.
  assert.equal((await env.call("/v1/admin/flags", { headers: { "cf-access-jwt-assertion": signedIn["cf-access-jwt-assertion"] } })).status, 401);
  assert.equal((await env.call("/v1/admin/flags", { headers: signedIn })).status, 200);
  assert.equal((await env.call("/admin", { headers: { "cf-access-jwt-assertion": signedIn["cf-access-jwt-assertion"] } })).status, 200);
  const me = (await (await env.call("/v1/admin/me", { headers: signedIn })).json()) as { actor: string; access: boolean };
  assert.deepEqual(me, { actor: "ollie@example.com", access: true });
  // Without Access configured the token alone works, and the actor is the token.
  env.deps.access = undefined;
  const plain = (await (await env.call("/v1/admin/me", { headers: withToken })).json()) as { actor: string; access: boolean };
  assert.deepEqual(plain, { actor: "token", access: false });
});
