// Signing in with Discord: the loopback server, and the whole path to a registered key against the real server.
import assert from "node:assert/strict";
import { createServer, request as httpRequest } from "node:http";
import test from "node:test";
import { discordIdentity } from "../../server/src/discord.ts";
import { CLIENT, NOW, catalog, setup } from "../../server/test/harness.ts";
import type { ClientOptions, FetchLike } from "../src/client.ts";
import { loadOrCreateIdentity } from "../src/identity.ts";
import { DISCORD_CLIENT_ID, REDIRECT_PORT, authorizeUrl, signIn, signInAndRegister } from "../src/signIn.ts";

const fixed = (state: string) => () => state;
const callbackOf = (url: string): string => new URL(url).searchParams.get("redirect_uri") as string;

test("the sign-in page asks for nothing but who the player is, and names the registered address", () => {
  const url = new URL(authorizeUrl(DISCORD_CLIENT_ID, `http://127.0.0.1:${REDIRECT_PORT}/callback`, "abc"));
  assert.equal(url.origin + url.pathname, "https://discord.com/oauth2/authorize");
  assert.equal(url.searchParams.get("client_id"), "1569844563957260298");
  assert.equal(url.searchParams.get("scope"), "identify");
  assert.equal(url.searchParams.get("response_type"), "code");
  assert.equal(url.searchParams.get("redirect_uri"), "http://127.0.0.1:53682/callback");
  assert.equal(url.searchParams.get("state"), "abc");
});

test("the code Discord sends back is returned, and a sign-in that did not start here is refused", async () => {
  let wrong = 0;
  const result = await signIn({
    port: 0, state: fixed("state-1234"),
    open: async (url) => {
      const callback = callbackOf(url);
      // Another sign-in's state, a missing state and the wrong path are all turned away.
      assert.equal((await fetch(`${callback}?code=stolen-code-1&state=other`)).status, 400);
      assert.equal((await fetch(`${callback}?code=stolen-code-1`)).status, 400);
      assert.equal((await fetch(callback.replace("/callback", "/elsewhere"))).status, 404);
      assert.equal((await fetch(`${callback}?state=state-1234&code=x`)).status, 400, "a code that cannot be real");
      wrong = 4;
      const good = await fetch(`${callback}?code=goodcode-1234&state=state-1234`);
      assert.equal(good.status, 200);
      assert.match(await good.text(), /Signed in/);
    },
  });
  assert.equal(wrong, 4);
  assert.deepEqual(result, { status: "code", code: "goodcode-1234" });
});

test("cancelling, waiting too long, a busy port and a browser that will not open are each reported", async () => {
  const denied = await signIn({ port: 0, state: fixed("s"), open: async (url) => { await fetch(`${callbackOf(url)}?error=access_denied&state=s`); } });
  assert.deepEqual(denied, { status: "failed", reason: "denied" });

  const timeout = await signIn({ port: 0, state: fixed("s"), timeoutMs: 50, open: () => undefined });
  assert.deepEqual(timeout, { status: "failed", reason: "timeout" });

  const browser = await signIn({ port: 0, state: fixed("s"), open: () => { throw new Error("no browser"); } });
  assert.deepEqual(browser, { status: "failed", reason: "browser" });

  // Something else already holds the port.
  const holder = createServer();
  await new Promise<void>((resolve) => holder.listen(0, "127.0.0.1", resolve));
  const port = (holder.address() as { port: number }).port;
  const busy = await signIn({ port, open: () => undefined });
  assert.deepEqual(busy, { status: "failed", reason: "port-busy" });
  holder.close();
});

test("only this computer's own address is accepted as the host, and the server is gone once it is done", async () => {
  let port = 0;
  const result = await signIn({
    port: 0, state: fixed("s"),
    open: async (url) => {
      port = Number(new URL(callbackOf(url)).port);
      // A page that got the browser to resolve another name to this address sends a different Host header.
      const status = await new Promise<number>((resolve, reject) => {
        const req = httpRequest({ host: "127.0.0.1", port, path: "/callback?code=goodcode-1234&state=s", headers: { host: "evil.example" } }, (res) => { res.resume(); resolve(res.statusCode ?? 0); });
        req.on("error", reject);
        req.end();
      });
      assert.equal(status, 400);
      await fetch(`${callbackOf(url)}?code=goodcode-5678&state=s`);
    },
  });
  assert.deepEqual(result, { status: "code", code: "goodcode-5678" });
  await assert.rejects(fetch(`http://127.0.0.1:${port}/callback`), "nothing listens after sign-in");
});

test("sign in, then register: the code goes to the server, which asks Discord who it is", async () => {
  const env = setup();
  // A pretend Discord that accepts exactly one code.
  env.deps.identity = discordIdentity({
    clientId: DISCORD_CLIENT_ID, clientSecret: "s", redirectUri: "unused",
    fetch: (async (url: string | URL | Request, init?: RequestInit) => {
      const address = String(url);
      if (address.endsWith("/oauth2/token")) return new URLSearchParams(String(init?.body)).get("code") === "goodcode-1234" ? Response.json({ access_token: "t", scope: "identify" }) : new Response("{}", { status: 400 });
      if (address.endsWith("/users/@me")) return Response.json({ id: "424242424242" });
      return new Response("{}");
    }) as typeof fetch,
  });
  const secrets = { value: null as string | null, async get() { return this.value; }, async set(secret: string) { this.value = secret; } };
  const fetchLike: FetchLike = async (url, init) => env.api(new Request(url, init));
  const client: ClientOptions = {
    baseUrl: "https://warcards.test", fetch: fetchLike, identity: await loadOrCreateIdentity(secrets), clientVersion: CLIENT,
    catalogVersion: catalog.catalogVersion, now: () => NOW, sleep: async () => {},
  };
  const registered = await signInAndRegister(client, "public", {
    port: 0, state: fixed("s"), open: async (url) => { await fetch(`${callbackOf(url)}?code=goodcode-1234&state=s`); },
  });
  assert.equal(registered.status, "registered");
  const row = env.raw.prepare("SELECT discord_id AS d FROM players").get() as { d: string };
  assert.equal(row.d, "424242424242");
  // A sign-in that never completes is not an upload and registers nothing.
  const cancelled = await signInAndRegister(client, "public", { port: 0, state: fixed("s"), timeoutMs: 30, open: () => undefined });
  assert.deepEqual(cancelled, { status: "failed", reason: "timeout" });
  assert.equal((env.raw.prepare("SELECT COUNT(*) AS n FROM players").get() as { n: number }).n, 1);
});
