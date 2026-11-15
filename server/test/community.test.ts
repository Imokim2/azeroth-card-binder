import assert from "node:assert/strict";
import test from "node:test";
import { communityRedirect } from "../src/community.ts";
import { setup } from "./harness.ts";

test("community links accept only clean HTTPS Discord invites", () => {
  for (const url of ["https://discord.gg/WarCards123", "https://discord.com/invite/WarCards123"]) {
    assert.equal(communityRedirect(url).headers.get("location"), url);
  }
  for (const url of [undefined, "", "https://example.com/invite/hello", "http://discord.gg/hello", "https://discord.gg.evil.test/hello", "https://discord.gg@evil.test/hello", "https://user:pass@discord.gg/hello", "https://discord.com/channels/@me", "https://discord.gg/hello?next=evil", "https://discord.gg/hello#fragment", "https://discord.gg:8443/hello", "https://discord.gg/hello/extra"]) {
    const response = communityRedirect(url);
    assert.equal(response.status, 302);
    assert.equal(response.headers.get("location"), "/help#community", String(url));
    assert.equal(response.headers.get("cache-control"), "no-store");
  }
});

test("the community route needs no account or database and ignores destination query parameters", async () => {
  const env = setup();
  env.deps.discordInviteUrl = "https://discord.gg/WarCards123";
  env.raw.close();
  const response = await env.call("/discord?next=https://evil.test");
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), env.deps.discordInviteUrl);
  assert.equal((await env.call("/discord", { method: "POST", body: {} })).status, 405);
});

test("help shows the community only when an invite exists, with a useful fallback otherwise", async () => {
  const env = setup();
  assert.equal((await env.call("/discord")).headers.get("location"), "/help#community");
  const pending = await (await env.call("/help")).text();
  assert.match(pending, /id="community"/);
  assert.match(pending, /Discord is being set up/);
  env.deps.discordInviteUrl = "https://discord.gg/WarCards123";
  const ready = await (await env.call("/help")).text();
  assert.match(ready, /href="\/discord">Join Discord/);
  assert.doesNotMatch(ready, /Discord is being set up/);
  assert.match(ready, /Settings → Help → Report a bug/);
  assert.match(ready, /KNOWN-ISSUES.md/);
});
