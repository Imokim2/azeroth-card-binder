import assert from "node:assert/strict";
import test from "node:test";
import { setup } from "./harness.ts";

test("the homepage introduces the project and the setup pages do not advertise unpublished downloads", async () => {
  const env = setup();
  const home = await (await env.call("/")).text();
  assert.match(home, /ILLUSTRATED BINDER PREVIEW/);
  for (const path of ["/download", "/help", "/faq", "/ladder", "/wanted", "/status"]) assert.ok(home.includes(`href="${path}"`), path);
  const download = await (await env.call("/download")).text();
  assert.match(download, /Public downloads are not available yet/);
  assert.match(download, /currently unsigned/);
  assert.ok(!/href="[^"]+\.(exe|zip)"/.test(download));
  const help = await (await env.call("/help")).text();
  for (const id of ["how-it-works", "install", "companion", "sync", "drops", "report"]) assert.ok(help.includes(`id="${id}"`), id);
  const faq = await (await env.call("/faq")).text();
  assert.match(faq, /What is the difference between Ranked and Casual/);
  assert.match(faq, /Can I keep my collection private/);
  for (const path of ["/download", "/help", "/faq", "/status", "/status/badge.svg", "/ladder"]) assert.equal((await env.call(path, { method: "POST", body: {} })).status, 405, path);
});

test("status and its badge check the database, are never cached and show failure without inventing uptime", async () => {
  const env = setup();
  const check = async (healthy: boolean) => {
    const status = await env.call("/status");
    assert.equal(status.status, healthy ? 200 : 503);
    assert.equal(status.headers.get("cache-control"), "no-store");
    const html = await status.text();
    assert.match(html, healthy ? /Server and database are online/ : /The database needs attention/);
    assert.match(html, /Discord sign-in/);
    assert.match(html, /Not monitored by this check/);
    assert.match(html, /2023-11-14 22:13:20 UTC/);
    const badge = await env.call("/status/badge.svg");
    assert.equal(badge.status, 200);
    assert.match(badge.headers.get("content-type") ?? "", /^image\/svg\+xml/);
    assert.equal(badge.headers.get("cache-control"), "no-store");
    assert.equal(badge.headers.get("x-content-type-options"), "nosniff");
    assert.match(await badge.text(), healthy ? /Server online/ : /Server issue/);
  };
  await check(true);
  env.breakHealth();
  await check(false);
  // Help remains available when the collection database is down.
  for (const path of ["/", "/help", "/faq", "/download"]) assert.equal((await env.call(path)).status, 200, path);
});
