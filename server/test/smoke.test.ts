// tools/smoke.js, run against the real API code with no network: it passes for a healthy, correctly signed release, and says what
// is wrong when the signature, a download or a page is not as it should be.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { createRequire } from "node:module";
import test from "node:test";
import { setup } from "./harness.ts";

const { smoke } = createRequire(import.meta.url)("../../tools/smoke.js") as {
  smoke(options: { base: string; get: typeof fetch; key: string | null; deep?: boolean }): Promise<{ name: string; ok: boolean; detail: string }[]>;
};

const BASE = "https://smoke.test";
const FILES = { app: Buffer.from("the installer"), addon: Buffer.from("the addon zip") };

function keys() {
  const pair = generateKeyPairSync("ed25519");
  return { publicKey: pair.publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("hex"), sign: (text: string) => sign(null, Buffer.from(text), pair.privateKey).toString("hex") };
}
const trusted = keys();

function world(options: { signer?: ReturnType<typeof keys>; appSize?: number; appMissing?: boolean } = {}) {
  const env = setup();
  const item = (version: string, name: string, bytes: Buffer, size = bytes.length) => ({
    version, url: `https://files.test/${name}`, size, sha256: createHash("sha256").update(bytes).digest("hex"), notes: "",
  });
  const manifest = JSON.stringify({ format: 1, issuedAt: 1, app: item("0.3.0", "setup.exe", FILES.app, options.appSize), addon: item("0.5.0", "addon.zip", FILES.addon) });
  env.deps.releases = { latestApp: "0.3.0", latestAddon: "0.5.0", minAddon: "0.0.0", signed: { manifest, signature: (options.signer ?? trusted).sign(manifest) } };
  const get = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.startsWith(BASE)) return env.api(new Request(url, init));
    if (options.appMissing && url.endsWith("setup.exe")) return new Response("", { status: 404 });
    const bytes = url.endsWith("setup.exe") ? FILES.app : FILES.addon;
    return new Response(init?.method === "HEAD" ? null : new Uint8Array(bytes), { status: 200, headers: { "content-length": String(bytes.length) } });
  }) as typeof fetch;
  return { env, get };
}

const failures = (results: { name: string; ok: boolean; detail: string }[]) => results.filter((result) => !result.ok);

test("a healthy server with a correctly signed, downloadable release passes every check", async () => {
  const { get } = world();
  const results = await smoke({ base: BASE, get, key: trusted.publicKey, deep: true });
  assert.deepEqual(failures(results), []);
  assert.ok(results.length >= 18);
  assert.match(results.find((result) => result.name.startsWith("downloads: the app"))?.detail ?? "", /checksum matches/);
});

test("a manifest signed with another key is called out", async () => {
  const { get } = world({ signer: keys() });
  const bad = failures(await smoke({ base: BASE, get, key: trusted.publicKey }));
  assert.ok(bad.some((result) => /signed with the key built into the app/.test(result.name) && /does NOT match/.test(result.detail)), JSON.stringify(bad));
});

test("a file that is missing, or the wrong size, is called out", async () => {
  const missing = failures(await smoke({ base: BASE, get: world({ appMissing: true }).get, key: trusted.publicKey }));
  assert.ok(missing.some((result) => /the app file/.test(result.name) && /404/.test(result.detail)), JSON.stringify(missing));
  const wrongSize = failures(await smoke({ base: BASE, get: world({ appSize: 999 }).get, key: trusted.publicKey }));
  assert.ok(wrongSize.some((result) => /the app file/.test(result.name) && /manifest says 999/.test(result.detail)), JSON.stringify(wrongSize));
});

test("an announcement with no signed manifest, or a database that is down, fails with a reason", async () => {
  const { env, get } = world();
  env.deps.releases = { latestApp: "0.3.0", latestAddon: "0.5.0", minAddon: "0.0.0" };
  const unsigned = failures(await smoke({ base: BASE, get, key: trusted.publicKey }));
  assert.ok(unsigned.some((result) => /no signed manifest/.test(result.detail)));
  env.breakHealth();
  const down = failures(await smoke({ base: BASE, get, key: trusted.publicKey }));
  assert.ok(down.some((result) => /^health/.test(result.name)));
});
