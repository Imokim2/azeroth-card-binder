import assert from "node:assert/strict";
import test from "node:test";
import { setup } from "./harness.ts";

test("real favicon formats and the touch icon are served with caching and no database work", async () => {
  const env = setup();
  env.breakHealth();
  for (const [path, type] of [["/favicon.svg","image/svg+xml"],["/favicon.ico","image/x-icon"],["/apple-touch-icon.png","image/png"]]) {
    const response = await env.call(path!);
    assert.equal(response.status,200);
    assert.equal(response.headers.get("content-type"),type);
    assert.equal(response.headers.get("cache-control"),"public, max-age=86400");
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (path!.endsWith(".ico")) {
      assert.deepEqual([...bytes.slice(0,6)],[0,0,1,0,3,0]);
      assert.deepEqual([bytes[6],bytes[7]],[16,16]);
    } else if (path!.endsWith(".png")) {
      assert.deepEqual([...bytes.slice(0,8)],[137,80,78,71,13,10,26,10]);
      const data = new DataView(bytes.buffer);
      assert.equal(data.getUint32(16),180); assert.equal(data.getUint32(20),180);
    } else assert.match(new TextDecoder().decode(bytes),/^<svg/);
    assert.equal((await env.call(path!,{method:"POST",body:{}})).status,405);
  }
});

test("the shared page head includes desktop and mobile icons", async () => {
  const env=setup();
  for(const path of ["/","/download","/help","/faq","/status"]) {
    const html=await(await env.call(path)).text();
    for(const icon of ["/favicon.ico","/favicon.svg","/apple-touch-icon.png"]) assert.ok(html.includes(`href="${icon}"`));
    assert.match(html,/<meta name="theme-color" content="#141416">/);
  }
});
