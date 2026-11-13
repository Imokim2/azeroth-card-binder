import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { cp, mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

const output = fileURLToPath(new URL("../dist", import.meta.url));
test("compiled startup imports work outside the repository with only build outputs", { skip: !existsSync(output) }, async () => {
  const root = await mkdtemp(join(tmpdir(), "warcards-built-startup-"));
  try {
    await cp(output, join(root, "dist"), { recursive: true });
    await writeFile(join(root, "package.json"), '{"type":"module"}');
    const files = ["controller.js", "recovery.js"].map(name => pathToFileURL(join(root, "dist", "app", "src", name)).href);
    files.push(pathToFileURL(join(root, "dist", "app", "electron", "gameProcess.js")).href);
    const result = spawnSync(process.execPath, ["--input-type=module", "-e", "for(const file of process.argv.slice(1)) await import(file)", ...files], {
      cwd: root, encoding: "utf8", env: { ...process.env, NODE_PATH: "" }, timeout: 20_000,
    });
    assert.equal(result.status, 0, result.stderr);
  } finally {
    assert.ok(resolve(root).startsWith(resolve(tmpdir()) + sep) && root.includes("warcards-built-startup-"));
    await rm(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  }
});
