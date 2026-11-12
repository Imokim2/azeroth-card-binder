// Already-installed companions can still call these endpoints, but wanted data stays in game.
import assert from "node:assert/strict";
import test from "node:test";
import { setup } from "./harness.ts";

test("legacy wanted requests return an empty result without accessing the wanted store", async () => {
  const env = setup();
  env.deps.wanted = {
    async board() { assert.fail("retired feed must not read wanted data"); },
    async setWanted() { assert.fail("retired uploads must not store wanted data"); },
  };
  const get = await env.call("/v1/wanted");
  assert.equal(get.status, 200);
  assert.deepEqual((await get.json() as {players: unknown[]}).players, []);
  assert.equal(get.headers.get("cache-control"), "no-store");
  const post = await env.call("/v1/wanted", { body: { cards: ["npc:589"] } });
  assert.equal(post.status, 200);
  assert.deepEqual(await post.json(), { stored: 0, listed: false, retired: true });
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM wanted").get()?.["n"], 0);
  assert.equal((await env.call("/v1/wanted", { method: "DELETE" })).status, 405);
});

test("old wanted-page links lead to in-game instructions and the site has no wanted navigation", async () => {
  const env = setup();
  const response = await env.call("/wanted");
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "/help#trading");
  assert.equal(response.headers.get("cache-control"), "no-store");
  for (const path of ["/", "/help", "/privacy", "/ladder"]) {
    const html = await (await env.call(path)).text();
    assert.ok(!html.includes('href="/wanted"'));
  }
  assert.match(await (await env.call("/help")).text(), /Wanted lists stay in the addon/);
});
