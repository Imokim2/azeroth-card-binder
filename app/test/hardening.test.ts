// The client's side of the server's launch hardening: it waits out a rate limit, and can delete the account.
import assert from "node:assert/strict";
import test from "node:test";
import { deleteAccount, fetchStandings } from "../src/client.ts";
import type { ClientOptions, FetchLike } from "../src/client.ts";
import { loadOrCreateIdentity } from "../src/identity.ts";
import { CLIENT, NOW, catalog, setup } from "../../server/test/harness.ts";
import { discordIdentity } from "../../server/src/discord.ts";
import { registerKey } from "../src/client.ts";
import { memoryLimiter } from "../../server/src/limit.ts";

const secrets = () => { let value: string | null = null; return { async get() { return value; }, async set(secret: string) { value = secret; } }; };

test("a rate-limited reply is waited out for as long as the server asks, then the request is repeated", async () => {
  const sleeps: number[] = [];
  let calls = 0;
  const fetch: FetchLike = async () => {
    calls += 1;
    if (calls < 3) return { status: 429, headers: { get: (name) => (name.toLowerCase() === "retry-after" ? "7" : null) }, json: async () => ({ error: { code: "rate_limited" } }) };
    return { status: 200, headers: { get: () => null }, json: async () => ({ entries: [], firsts: [] }) };
  };
  const options: ClientOptions = {
    baseUrl: "https://x.test", fetch, identity: { publicKeyHex: "0".repeat(64), sign: async () => "0".repeat(128) }, clientVersion: "0.1.0",
    catalogVersion: "t", now: () => NOW, sleep: async (ms) => { sleeps.push(ms); },
  };
  const result = await fetchStandings(options, null);
  assert.equal(result.status, "standings");
  assert.ok(sleeps.length >= 2 && sleeps.every((ms) => ms >= 7000), `waited ${JSON.stringify(sleeps)}`);
});

test("deleting the account removes the player on the server, and the same key can sign up again", async () => {
  const env = setup();
  env.deps.identity = discordIdentity({
    clientId: "1", clientSecret: "s", redirectUri: "r",
    fetch: (async (url: string | URL | Request) => String(url).endsWith("/users/@me") ? Response.json({ id: "777777777777" }) : String(url).endsWith("/oauth2/token") ? Response.json({ access_token: "t", scope: "identify" }) : new Response("{}")) as typeof fetch,
  });
  const fetchLike: FetchLike = async (url, init) => env.api(new Request(url, init));
  const client: ClientOptions = {
    baseUrl: "https://warcards.test", fetch: fetchLike, identity: await loadOrCreateIdentity(secrets()), clientVersion: CLIENT,
    catalogVersion: catalog.catalogVersion, now: () => NOW, sleep: async () => {},
  };
  const first = await registerKey(client, "goodcode-1234", "public");
  assert.equal(first.status, "registered");
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM players").get() as { n: number }).n, 1);

  assert.deepEqual(await deleteAccount(client), { status: "deleted" });
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM players").get() as { n: number }).n, 0);
  // The key is no longer known: deleting again is refused, and signing up again makes a new player.
  const again = await deleteAccount(client);
  assert.deepEqual([again.status, "code" in again ? again.code : null], ["rejected", "unknown_key"]);
  const second = await registerKey(client, "goodcode-1234", "private");
  assert.equal(second.status, "registered");
  assert.notEqual(first.status === "registered" && second.status === "registered" ? first.playerId : "", second.status === "registered" ? second.playerId : "x");

  // A limited server tells the client to wait rather than failing.
  env.deps.limits = { general: memoryLimiter({ limit: 3, periodSeconds: 60, now: () => env.clock.now }), strict: memoryLimiter({ limit: 100, periodSeconds: 60, now: () => env.clock.now }) };
  const limited = await fetchStandings({ ...client, attempts: 1 }, null);
  assert.equal(limited.status, "standings", "the first call (three requests) is within the limit");
  const refused = await fetchStandings({ ...client, attempts: 1 }, null);
  assert.equal(refused.status, "retry-later");
});
