#!/usr/bin/env node
// The signed release manifest: what the companion app trusts when it updates itself or the add-on.
//
//   node tools/release-manifest.js keygen <file>     make a signing key (once). The file holds the private key: keep it
//                                                    out of the repository, backed up, and nowhere shared.
//   node tools/release-manifest.js sign --key <file> --app <installer.exe> --app-url <https url>
//                                       --addon <zip> --addon-url <https url> [--app-notes "..."] [--addon-notes "..."]
//                                                    hash both files, sign a manifest and write server/src/releases.json
//   node tools/release-manifest.js verify            check server/src/releases.json against the key the app trusts
//
// The manifest is plain JSON text; the signature is Ed25519 over exactly those bytes. The server passes both on untouched;
// the app checks the signature against the public key in app/src/releaseKey.ts and refuses anything that does not match.
"use strict";
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
// The two files can be pointed elsewhere (the tests do, so they never touch the real ones).
const manifestPath = process.env.WARCARDS_RELEASES_FILE || path.join(root, "server", "src", "releases.json");
const keyModule = process.env.WARCARDS_RELEASE_KEY_MODULE || path.join(root, "app", "src", "releaseKey.ts");
const SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex"); // what turns 32 raw key bytes into a public key Node reads

function fail(message) {
  console.error(message);
  process.exit(1);
}

function option(args, name) {
  const at = args.indexOf("--" + name);
  return at >= 0 ? args[at + 1] : undefined;
}

const publicKeyObject = (hex) => crypto.createPublicKey({ key: Buffer.concat([SPKI_PREFIX, Buffer.from(hex, "hex")]), format: "der", type: "spki" });

function keygen(file) {
  if (!file) fail("Usage: node tools/release-manifest.js keygen <file>");
  const target = path.resolve(file);
  if (!path.relative(root, target).startsWith("..")) fail("Keep the private key outside the repository: " + target);
  if (fs.existsSync(target)) fail(target + " already exists. Refusing to replace a signing key.");
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
  const publicHex = publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("hex");
  const privateHex = privateKey.export({ format: "der", type: "pkcs8" }).toString("hex");
  fs.writeFileSync(target, JSON.stringify({ publicKey: publicHex, privateKeyPkcs8: privateHex }, null, 2) + "\n", { mode: 0o600 });
  console.log("Wrote " + target + " (private: back it up, never commit or share it).");
  console.log("Put this public key in app/src/releaseKey.ts:\n\n" + publicHex);
}

function sha256(file) {
  const bytes = fs.readFileSync(file);
  return { sha256: crypto.createHash("sha256").update(bytes).digest("hex"), size: bytes.length };
}

function tocVersion() {
  const toc = fs.readFileSync(path.join(root, "AzerothCardBinder", "AzerothCardBinder.toc"), "utf8");
  const found = /^## Version:\s*(\d+\.\d+\.\d+)\s*$/m.exec(toc);
  if (!found) fail("No version in AzerothCardBinder.toc");
  return found[1];
}

function sign(args) {
  const keyFile = option(args, "key");
  const appFile = option(args, "app");
  const addonFile = option(args, "addon");
  const appUrl = option(args, "app-url");
  const addonUrl = option(args, "addon-url");
  if (!keyFile || !appFile || !addonFile || !appUrl || !addonUrl) fail("Usage: see the top of tools/release-manifest.js");
  for (const url of [appUrl, addonUrl]) if (!/^https:\/\/[^\s"]+$/.test(url)) fail("Download addresses must be https: " + url);
  const key = JSON.parse(fs.readFileSync(keyFile, "utf8"));
  const privateKey = crypto.createPrivateKey({ key: Buffer.from(key.privateKeyPkcs8, "hex"), format: "der", type: "pkcs8" });
  const app = JSON.parse(fs.readFileSync(path.join(root, "app", "package.json"), "utf8")).version;
  const addon = tocVersion();
  if (!path.basename(addonFile).includes(addon)) fail("The add-on zip's name does not contain the version " + addon + ": " + addonFile);
  const manifest = JSON.stringify({
    format: 1,
    issuedAt: Math.floor(Date.now() / 1000),
    app: { version: app, url: appUrl, ...sha256(appFile), notes: option(args, "app-notes") || "" },
    addon: { version: addon, url: addonUrl, ...sha256(addonFile), notes: option(args, "addon-notes") || "" },
  });
  const signature = crypto.sign(null, Buffer.from(manifest), privateKey).toString("hex");
  fs.writeFileSync(manifestPath, JSON.stringify({ manifest, signature }, null, 2) + "\n");
  console.log("Wrote " + path.relative(root, manifestPath) + ": companion " + app + ", add-on " + addon + ".");
  if (readEmbeddedKey() !== key.publicKey) console.log("Warning: app/src/releaseKey.ts does not hold this key's public key (" + key.publicKey + "); installed apps will refuse this manifest.");
  console.log("Deploy the server (cd server; npx wrangler deploy --env staging) to announce it.");
}

function readEmbeddedKey() {
  const text = fs.readFileSync(keyModule, "utf8");
  const found = /RELEASE_PUBLIC_KEY[^=]*=\s*"([0-9a-f]{64})"/.exec(text);
  return found ? found[1] : null;
}

function verify() {
  const key = readEmbeddedKey();
  if (!key) fail("app/src/releaseKey.ts holds no public key yet: run keygen and put it there.");
  const { manifest, signature } = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (!manifest) fail("server/src/releases.json holds no manifest yet: run sign.");
  const ok = crypto.verify(null, Buffer.from(manifest), publicKeyObject(key), Buffer.from(signature, "hex"));
  if (!ok) fail("The signature does NOT match the key the app trusts.");
  const parsed = JSON.parse(manifest);
  console.log("Signature is good: companion " + parsed.app.version + ", add-on " + parsed.addon.version + ".");
}

const [command, ...rest] = process.argv.slice(2);
if (command === "keygen") keygen(rest[0]);
else if (command === "sign") sign(rest);
else if (command === "verify") verify();
else fail("Usage: node tools/release-manifest.js keygen|sign|verify (see the top of the file)");
