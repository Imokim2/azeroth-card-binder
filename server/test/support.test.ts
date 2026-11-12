import assert from "node:assert/strict";
import test from "node:test";
import { paypalSupport } from "../src/support.ts";
import { setup } from "./harness.ts";

test("support redirects only to the configured PayPal recipient with no amount or player details", async () => {
  const env = setup();
  env.deps.supportPayPalAccount = "supporter@example.test";
  const response = await env.call("/support?business=someone-else@example.test&amount=100&return=https://elsewhere.test");
  assert.equal(response.status, 302);
  const destination = new URL(response.headers.get("location")!);
  assert.equal(destination.origin, "https://www.paypal.com");
  assert.equal(destination.pathname, "/donate/");
  assert.equal(destination.searchParams.get("business"), "supporter@example.test");
  assert.equal(destination.searchParams.get("currency_code"), "GBP");
  assert.equal(destination.searchParams.get("item_name"), "World of Warcards server costs");
  assert.equal(destination.searchParams.size, 3);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("set-cookie"), null);
  assert.equal(await response.text(), "");
  assert.ok(!JSON.stringify(env.logs).includes("supporter@example.test"));
  assert.equal((await env.call("/support", { method: "POST", body: {} })).status, 405);
  assert.equal((await env.call("/support", { method: "DELETE" })).status, 405);
});

test("an absent or invalid recipient fails closed and cannot create an arbitrary redirect", async () => {
  for (const recipient of [undefined, "", "https://elsewhere.test", "a@example.test\r\nLocation: https://elsewhere.test", "a".repeat(260)]) {
    const response = paypalSupport(recipient);
    assert.equal(response.status, 503);
    assert.equal(response.headers.get("location"), null);
    assert.equal(response.headers.get("cache-control"), "no-store");
  }
  assert.equal(paypalSupport("ABCD123456789").status, 302);
});

test("the shared footer offers optional support without embedding the recipient or a payment script", async () => {
  const env = setup();
  env.deps.supportPayPalAccount = "supporter@example.test";
  for (const path of ["/", "/download", "/help", "/faq", "/fair-play", "/privacy", "/status"]) {
    const response = await env.call(path);
    const page = await response.text();
    assert.match(page, /<footer>[\s\S]*href="\/support"/);
    assert.match(page, /Support via PayPal/);
    assert.match(page, /It’s completely optional/);
    assert.ok(!page.includes("supporter@example.test"));
    assert.ok(!/<script/i.test(page));
  }
  env.breakHealth();
  assert.equal((await env.call("/support")).status, 302);
});
