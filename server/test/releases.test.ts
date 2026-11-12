// /v1/releases: what the newest and the oldest accepted versions are, so the companion app can say what is out of date.
import assert from "node:assert/strict";
import test from "node:test";
import { setup } from "./harness.ts";

type Body = Record<string, { latest: string; min: string }>;

test("releases says nothing is out of date when no versions are configured: the minimum app and no add-on limit", async () => {
  const env = setup();
  const response = await env.call("/v1/releases");
  assert.equal(response.status, 200);
  const body = (await response.json()) as Body;
  assert.deepEqual(body["app"], { latest: "0.1.0", min: "0.1.0" });
  assert.deepEqual(body["addon"], { latest: "0.0.0", min: "0.0.0" });
});

test("releases serves the configured versions, publicly and cacheable for a few minutes", async () => {
  const env = setup();
  env.deps.releases = { latestApp: "0.3.0", latestAddon: "0.5.2", minAddon: "0.4.0" };
  const response = await env.call("/v1/releases");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "public, max-age=300");
  const body = (await response.json()) as Body;
  assert.deepEqual(body["app"], { latest: "0.3.0", min: "0.1.0" });
  assert.deepEqual(body["addon"], { latest: "0.5.2", min: "0.4.0" });
  // Only GET is allowed.
  const wrong = await env.call("/v1/releases", { body: {} });
  assert.equal(wrong.status, 405);
});
