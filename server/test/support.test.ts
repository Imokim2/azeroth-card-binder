import assert from "node:assert/strict";
import test from "node:test";
import { paypalSupport } from "../src/support.ts";
import { setup } from "./harness.ts";

test("support uses the configured account-generated link and ignores visitor payment parameters", async () => {
  const env=setup();
  env.deps.supportPayPalUrl="https://paypal.me/WarcardsTest";
  const response=await env.call("/support?business=another-account&amount=100&return=https://elsewhere.test");
  assert.equal(response.status,302);
  assert.equal(response.headers.get("location"),"https://paypal.me/WarcardsTest");
  assert.equal(response.headers.get("cache-control"),"no-store");
  assert.equal(response.headers.get("referrer-policy"),"no-referrer");
  assert.equal(response.headers.get("set-cookie"),null);
  assert.equal(await response.text(),"");
  assert.ok(!JSON.stringify(env.logs).includes("WarcardsTest"));
  for(const method of ["POST","DELETE"]) assert.equal((await env.call("/support",{method})).status,405);
});

test("email-only donation links and arbitrary destinations cannot become support redirects", () => {
  for(const link of [undefined,"","someone@example.test","https://elsewhere.test","https://paypal.me.evil.test/name","http://paypal.me/name","https://user:password@paypal.me/name","https://paypal.me/name/100","https://www.paypal.com/donate/?business=someone%40example.test"]) {
    assert.equal(paypalSupport(link),null,link);
  }
  assert.equal(paypalSupport("https://www.paypal.com/paypalme/Example")?.headers.get("location"),"https://www.paypal.com/paypalme/Example");
  assert.equal(paypalSupport("https://www.paypal.com/ncp/payment/ABCD123456789")?.status,302);
  assert.equal(paypalSupport("https://www.paypal.com/donate/?hosted_button_id=ABCD123456789&amount=100")?.headers.get("location"),"https://www.paypal.com/donate/?hosted_button_id=ABCD123456789");
});

test("header and footer offer the same support route without a payment script", async () => {
  const env=setup();
  env.deps.supportPayPalUrl="https://paypal.me/WarcardsTest";
  for(const path of ["/","/download","/help","/faq","/fair-play","/privacy","/status"]) {
    const page=await(await env.call(path)).text();
    assert.match(page,/<header>[\s\S]*class="button header-support" href="\/support"/);
    assert.match(page,/<footer>[\s\S]*href="\/support"/);
    assert.match(page,/It’s completely optional/);
    assert.ok(!page.includes("WarcardsTest"));
    assert.ok(!/<script/i.test(page));
  }
  env.breakHealth();
  assert.equal((await env.call("/support")).status,302);
});

test("missing configuration gives a branded explanation without sending visitors to a broken checkout", async () => {
  const env=setup();
  const response=await env.call("/support");
  assert.equal(response.status,200);
  assert.equal(response.headers.get("cache-control"),"no-store");
  assert.equal(response.headers.get("location"),null);
  assert.match(await response.text(),/We’re updating the PayPal support link/);
});
