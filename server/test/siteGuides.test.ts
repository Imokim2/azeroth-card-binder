import assert from "node:assert/strict";
import test from "node:test";
import { setup } from "./harness.ts";

test("the homepage introduces the project and the setup pages do not advertise unpublished downloads", async () => {
  const env = setup();
  const home = await (await env.call("/")).text();
  assert.match(home, /src="\/images\/binder\.png"/);
  for (const path of ["/download", "/help", "/faq", "/ladder", "/status"]) assert.ok(home.includes(`href="${path}"`), path);
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

test("the download page shows real downloads, with their size and checksum, only from a manifest it can read, and links GitHub only when told to", async () => {
  const sha = (letter: string) => letter.repeat(64);
  const manifest = JSON.stringify({
    format: 1, issuedAt: 1,
    app: { version: "0.3.0", url: "https://github.com/Imokim2/azeroth-card-binder/releases/download/v0.3.0/Setup.exe", size: 3 * 1024 * 1024, sha256: sha("a"), notes: "" },
    addon: { version: "0.5.0", url: "https://github.com/Imokim2/azeroth-card-binder/releases/download/v0.3.0/AzerothCardBinder-0.5.0.zip", size: 2 * 1024 * 1024, sha256: sha("b"), notes: "" },
  });
  const env = setup();
  env.deps.releases = { latestApp: "0.3.0", latestAddon: "0.5.0", minAddon: "0.0.0", signed: { manifest, signature: "ab".repeat(64) } };
  const page = await (await env.call("/download")).text();
  assert.ok(!/not available yet/.test(page));
  assert.match(page, /Download the companion 0\.3\.0 \(3\.0 MB\)/);
  assert.match(page, /Download the addon 0\.5\.0 \(2\.0 MB\)/);
  assert.ok(page.includes('href="https://github.com/Imokim2/azeroth-card-binder/releases/download/v0.3.0/Setup.exe"'));
  assert.ok(page.includes("<code>" + sha("a") + "</code>") && page.includes("<code>" + sha("b") + "</code>"));

  // A link that is not https, or a file with a bad checksum, is not shown.
  const bad = JSON.stringify({
    app: { version: "0.3.0", url: "http://example.test/Setup.exe", size: 5, sha256: sha("a") },
    addon: { version: "0.5.0", url: "https://example.test/a.zip", size: 5, sha256: "nope" },
  });
  env.deps.releases = { latestApp: "0.3.0", latestAddon: "0.5.0", minAddon: "0.0.0", signed: { manifest: bad, signature: "ab".repeat(64) } };
  const refused = await (await env.call("/download")).text();
  assert.match(refused, /not available yet/);
  assert.ok(!/href="[^"]+\.(exe|zip)"/.test(refused));

  // The GitHub link appears only when the setting names a GitHub releases page.
  env.deps.releases = undefined as never;
  env.deps.releasesUrl = "https://github.com/Imokim2/azeroth-card-binder/releases/latest";
  const linked = await (await env.call("/download")).text();
  assert.ok(linked.includes('href="https://github.com/Imokim2/azeroth-card-binder/releases/latest"'));
  assert.ok(!/not available yet/.test(linked));
  env.deps.releasesUrl = "https://evil.test/releases/latest";
  assert.match(await (await env.call("/download")).text(), /not available yet/);
});

test("the help and FAQ pages describe the public release: real downloads, the unsigned-installer warning, and GitHub for reports", async () => {
  const env = setup();
  const help = await (await env.call("/help")).text();
  assert.ok(!/testing build|supplied by the maintainers|before launch/i.test(help), "no leftover testing-build wording");
  assert.ok(help.includes('href="https://github.com/Imokim2/azeroth-card-binder/issues/new/choose"'));
  assert.match(help, /More info/);
  const faq = await (await env.call("/faq")).text();
  assert.match(faq, /More info/);
  assert.ok(!/not available on this site yet|testers should use/i.test(faq));
});

test("the privacy page tells people how to get a copy of their data, and shows a contact address only when one is set and well formed", async () => {
  const env = setup();
  const without = await (await env.call("/privacy")).text();
  assert.match(without, /Download my data/);
  assert.match(without, /Questions about your data/);
  assert.ok(!without.includes("mailto:"));
  assert.ok(without.includes("issues/new/choose"), "falls back to the issue tracker, with a warning about personal details");
  env.deps.privacyEmail = "privacy@worldofwarcards.co.uk";
  const withAddress = await (await env.call("/privacy")).text();
  assert.ok(withAddress.includes('<a href="mailto:privacy@worldofwarcards.co.uk">privacy@worldofwarcards.co.uk</a>'));
  for (const bad of ['x"><script>alert(1)</script>@a.co', "no at sign", "a@b", "<b>@x.co", "a b@c.co"]) {
    env.deps.privacyEmail = bad;
    assert.ok(!(await (await env.call("/privacy")).text()).includes("mailto:"), bad);
  }
});
