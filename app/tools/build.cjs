const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const root = path.resolve(__dirname, "..");
const output = path.join(root, "dist");
if (path.dirname(output) !== root || path.basename(output) !== "dist") throw new Error("Invalid build output");
// A clean output prevents old compiled files from hiding a missing dependency.
fs.rmSync(output, { recursive: true, force: true });
const result = spawnSync(process.execPath, [require.resolve("typescript/lib/tsc.js"), "-p", path.join(root, "tsconfig.build.json")], { stdio: "inherit" });
process.exit(result.status ?? 1);
