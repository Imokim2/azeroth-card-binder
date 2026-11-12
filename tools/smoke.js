#!/usr/bin/env node
// A quick look at a running server after a deploy: is it up, is the release it announces genuine and downloadable, do the public
// pages answer, and are the doors that should be shut shut. It changes nothing (every request is a GET or a refused POST).
//
//   node tools/smoke.js                      production (https://worldofwarcards.co.uk)
//   node tools/smoke.js --env staging        staging
//   node tools/smoke.js --url https://example.test
//   node tools/smoke.js --deep               also download the release files and check their SHA-256 (about 120 MB)
//
// Exit status 0 means every check passed, 1 means something needs a look.
"use strict";
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const SERVERS = { production: "https://worldofwarcards.co.uk", staging: "https://staging.worldofwarcards.co.uk" };
const SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");
const PAGES = ["/", "/download", "/help", "/faq", "/privacy", "/fair-play", "/ladder", "/status"];

// The public key the app trusts, read from the app's own source so the check is against what players actually run.
function embeddedKey() {
  const text = fs.readFileSync(path.join(root, "app", "src", "releaseKey.ts"), "utf8");
  const found = /RELEASE_PUBLIC_KEY[^=]*=\s*"([0-9a-f]{64})"/.exec(text);
  return found ? found[1] : null;
}

function verifies(keyHex, manifest, signatureHex) {
  const key = crypto.createPublicKey({ key: Buffer.concat([SPKI_PREFIX, Buffer.from(keyHex, "hex")]), format: "der", type: "spki" });
  return crypto.verify(null, Buffer.from(manifest), key, Buffer.from(signatureHex, "hex"));
}

// Runs every check against `base` and returns [{ name, ok, detail }]. `get` is a fetch (a parameter so tests can use no network).
async function smoke({ base, get = fetch, key = embeddedKey(), deep = false }) {
  const results = [];
  const check = async (name, work) => {
    try {
      const detail = await work();
      results.push({ name, ok: true, detail: detail || "" });
    } catch (error) {
      results.push({ name, ok: false, detail: error instanceof Error ? error.message : String(error) });
    }
  };
  const need = (condition, message) => { if (!condition) throw new Error(message); };
  const fetchJson = async (route) => {
    const response = await get(base + route, { redirect: "follow" });
    need(response.status === 200, `${route} answered ${response.status}`);
    return response.json();
  };

  await check("health: the server answers and reaches its database", async () => {
    const body = await fetchJson("/v1/health");
    need(body.ok === true && body.db === true, JSON.stringify(body));
    return `version ${body.version}, catalog ${body.catalogVersion}`;
  });

  let releases = null;
  await check("releases: versions are announced", async () => {
    releases = await fetchJson("/v1/releases");
    for (const part of ["app", "addon"]) {
      for (const field of ["latest", "min"]) need(/^\d+\.\d+\.\d+$/.test(releases[part]?.[field] ?? ""), `${part}.${field} is not x.y.z`);
    }
    return `companion ${releases.app.latest} (min ${releases.app.min}), add-on ${releases.addon.latest} (min ${releases.addon.min})`;
  });

  let manifest = null;
  await check("releases: the manifest is signed with the key built into the app", async () => {
    need(releases?.signed, "no signed manifest is announced");
    need(key, "app/src/releaseKey.ts holds no public key");
    need(verifies(key, releases.signed.manifest, releases.signed.signature), "the signature does NOT match the key the app trusts");
    manifest = JSON.parse(releases.signed.manifest);
    need(manifest.app.version === releases.app.latest && manifest.addon.version === releases.addon.latest, "the manifest and the announced versions disagree");
    return "signature is good";
  });

  for (const part of ["app", "addon"]) {
    await check(`downloads: the ${part} file is where the manifest says, at the size it says`, async () => {
      need(manifest, "no manifest to read");
      const item = manifest[part];
      need(/^https:\/\//.test(item.url), "the address is not https");
      const response = await get(item.url, { method: "HEAD", redirect: "follow" });
      need(response.status === 200, `${item.url} answered ${response.status}`);
      const length = Number(response.headers.get("content-length"));
      need(!length || length === item.size, `the file is ${length} bytes, the manifest says ${item.size}`);
      if (deep) {
        const bytes = Buffer.from(await (await get(item.url, { redirect: "follow" })).arrayBuffer());
        need(bytes.length === item.size, `downloaded ${bytes.length} bytes, expected ${item.size}`);
        need(crypto.createHash("sha256").update(bytes).digest("hex") === item.sha256, "the file's SHA-256 is not the one that was signed");
        return `${item.version}, checksum matches`;
      }
      return `${item.version}, ${item.size} bytes`;
    });
  }

  await check("download page: offers the announced versions", async () => {
    const page = await (await get(base + "/download")).text();
    need(manifest, "no manifest to compare with");
    need(page.includes(manifest.app.version) && page.includes(manifest.addon.version), "the page does not show the announced versions");
    need(!/not available yet/.test(page), "the page still says downloads are not available");
    need(page.includes(manifest.app.sha256) && page.includes(manifest.addon.sha256), "the page does not show the checksums");
  });

  for (const route of PAGES) {
    await check(`page ${route}`, async () => {
      const response = await get(base + route);
      need(response.status === 200, `answered ${response.status}`);
      need((response.headers.get("content-type") ?? "").includes("text/html"), "not HTML");
      need(response.headers.get("x-content-type-options") === "nosniff", "no x-content-type-options: nosniff");
      need(/default-src/.test(response.headers.get("content-security-policy") ?? ""), "no content security policy");
    });
  }

  for (const route of ["/v1/leaderboard", "/v1/firsts"]) {
    await check(`public data ${route}`, async () => { await fetchJson(route); });
  }

  await check("the admin doors are shut without the token", async () => {
    for (const route of ["/v1/admin/flags", "/v1/admin/reports", "/v1/admin/players", "/v1/admin/audit", "/v1/admin/me"]) {
      const response = await get(base + route);
      need(response.status === 401 || response.status === 404, `${route} answered ${response.status}`);
    }
  });

  await check("a wrong method or an unknown route is refused", async () => {
    const wrong = await get(base + "/v1/ledger");
    need(wrong.status === 405, `GET /v1/ledger answered ${wrong.status}`);
    const none = await get(base + "/v1/no-such-route");
    need(none.status === 404, `an unknown route answered ${none.status}`);
  });

  return results;
}

module.exports = { smoke, verifies, embeddedKey };

if (require.main === module) {
  const args = process.argv.slice(2);
  const option = (name) => (args.includes("--" + name) ? args[args.indexOf("--" + name) + 1] : undefined);
  const base = option("url") || SERVERS[option("env") || "production"];
  if (!base) {
    console.error("Usage: node tools/smoke.js [--env production|staging | --url <address>] [--deep]");
    process.exit(1);
  }
  smoke({ base: base.replace(/\/$/, ""), deep: args.includes("--deep") }).then((results) => {
    console.log("Smoke test of " + base + "\n");
    for (const result of results) console.log((result.ok ? "  ok   " : "  FAIL ") + result.name + (result.detail ? "  [" + result.detail + "]" : ""));
    const failed = results.filter((result) => !result.ok).length;
    console.log("\n" + (failed === 0 ? "All " + results.length + " checks passed." : failed + " of " + results.length + " checks FAILED."));
    process.exit(failed === 0 ? 0 : 1);
  });
}
