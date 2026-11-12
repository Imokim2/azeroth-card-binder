// tools/release-manifest.js against the app's own check: what the tool signs is exactly what the app believes, the private key
// never goes inside the repository, and the tool says so when the key the app trusts is not the one that signed.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { verifiedManifest } from "../src/updates.ts";

const root = fileURLToPath(new URL("../../", import.meta.url));
const tool = (args: string[], env: Record<string, string> = {}) =>
  spawnSync(process.execPath, ["tools/release-manifest.js", ...args], { cwd: root, encoding: "utf8", env: { ...process.env, ...env } });

test("the tool signs a manifest the app accepts, with the hashes of the real files, and verify agrees", async () => {
  const folder = await mkdtemp(join(tmpdir(), "warcards-release-"));
  try {
    const keyFile = join(folder, "release-key.json");
    const made = tool(["keygen", keyFile]);
    assert.equal(made.status, 0, made.stderr);
    const key = JSON.parse(await readFile(keyFile, "utf8")) as { publicKey: string };
    assert.match(key.publicKey, /^[0-9a-f]{64}$/);
    assert.equal(tool(["keygen", keyFile]).status, 1, "an existing key is never replaced");

    const version = /^## Version:\s*(\S+)/m.exec(await readFile(join(root, "AzerothCardBinder", "AzerothCardBinder.toc"), "utf8"))?.[1] as string;
    const installer = join(folder, "Setup.exe");
    const zip = join(folder, `AzerothCardBinder-${version}.zip`);
    await writeFile(installer, "installer bytes");
    await writeFile(zip, "zip bytes");
    const output = join(folder, "releases.json");
    const embedded = join(folder, "releaseKey.ts");
    await writeFile(embedded, `export const RELEASE_PUBLIC_KEY: string | null = "${key.publicKey}";\n`);
    const env = { WARCARDS_RELEASES_FILE: output, WARCARDS_RELEASE_KEY_MODULE: embedded };
    const signed = tool(["sign", "--key", keyFile, "--app", installer, "--app-url", "https://example.test/Setup.exe", "--addon", zip,
      "--addon-url", "https://example.test/addon.zip", "--app-notes", "Faster sync"], env);
    assert.equal(signed.status, 0, signed.stderr);
    assert.ok(!signed.stdout.includes("Warning"), signed.stdout);

    const written = JSON.parse(await readFile(output, "utf8")) as { manifest: string; signature: string };
    const manifest = await verifiedManifest(written, key.publicKey);
    assert.ok(manifest, "the app believes what the tool signed");
    assert.equal(manifest?.addon.version, version);
    assert.equal(manifest?.app.notes, "Faster sync");
    assert.equal(manifest?.app.size, "installer bytes".length);
    assert.equal(manifest?.addon.sha256, (await import("node:crypto")).createHash("sha256").update("zip bytes").digest("hex"));
    assert.equal(tool(["verify"], env).status, 0);

    // Another key's signature is refused by verify, and the tool warns when the app does not trust the signing key.
    await writeFile(embedded, `export const RELEASE_PUBLIC_KEY: string | null = "${"ab".repeat(32)}";\n`);
    assert.equal(tool(["verify"], env).status, 1);
    assert.match(tool(["sign", "--key", keyFile, "--app", installer, "--app-url", "https://example.test/Setup.exe", "--addon", zip, "--addon-url", "https://example.test/addon.zip"], env).stdout, /Warning: .*does not hold this key/);
    assert.equal(await verifiedManifest(written, "ab".repeat(32)), null, "the app refuses a key it was not built with");
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});

test("the tool refuses a private key inside the repository, an http download address and a zip named for another version", async () => {
  const folder = await mkdtemp(join(tmpdir(), "warcards-release-"));
  try {
    assert.equal(tool(["keygen", join(root, "release-key.json")]).status, 1);
    const keyFile = join(folder, "k.json");
    assert.equal(tool(["keygen", keyFile]).status, 0);
    const installer = join(folder, "Setup.exe");
    const zip = join(folder, "AzerothCardBinder-0.0.1.zip");
    await writeFile(installer, "a");
    await writeFile(zip, "b");
    const env = { WARCARDS_RELEASES_FILE: join(folder, "out.json") };
    const common = ["--key", keyFile, "--app", installer, "--addon", zip];
    assert.equal(tool(["sign", ...common, "--app-url", "http://example.test/Setup.exe", "--addon-url", "https://example.test/a.zip"], env).status, 1);
    assert.equal(tool(["sign", ...common, "--app-url", "https://example.test/Setup.exe", "--addon-url", "https://example.test/a.zip"], env).status, 1, "the zip's name does not hold the add-on's version");
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});
