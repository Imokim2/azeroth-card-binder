// Check the exact ASAR and start the real packaged executable using isolated data and a loopback-only server.
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const http = require("node:http");
const { spawn, spawnSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");
const asar = require("@electron/asar");
const root = path.resolve(__dirname, "..");
const packaged = path.resolve(process.argv[2] || path.join(root, "release", "win-unpacked"));

async function main() {
  const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "warcards-packaged-check-"));
  const extracted = path.join(scratch, "archive"), data = path.join(scratch, "data");
  let server;
  try {
    asar.extractAll(path.join(packaged, "resources", "app.asar"), extracted);
    const pkg = JSON.parse(await fs.readFile(path.join(extracted, "package.json"), "utf8"));
    for (const file of [pkg.main, "electron/preload.cjs", "electron/renderer/index.html", "electron/renderer/renderer.js", "assets/icon.png", "assets/tray.png"]) {
      await fs.access(path.join(extracted, file));
    }
    const catalog = JSON.parse(await fs.readFile(path.join(packaged, "resources", "catalog.json"), "utf8"));
    if (!catalog.catalogVersion) throw new Error("Packaged catalog missing");
    // Imports run outside the repository, so undeclared source files cannot rescue the package.
    const entries = ["dist/app/src/controller.js", "dist/app/src/recovery.js", "dist/app/electron/gameProcess.js"].map(file => pathToFileURL(path.join(extracted, file)).href);
    const imported = spawnSync(process.execPath, ["--input-type=module", "-e", "for(const entry of process.argv.slice(1)) await import(entry)", ...entries], {
      cwd: scratch, encoding: "utf8", timeout: 20_000, env: { ...process.env, NODE_PATH: "" }, windowsHide: true,
    });
    if (imported.status !== 0) throw new Error("Packaged imports failed:\n" + imported.stderr);
    console.log("PASS actual ASAR imports, renderer/preload assets and packaged catalog");
    if (process.platform !== "win32") throw new Error("The Windows executable startup check must run on Windows");
    server = http.createServer((_request, response) => { response.writeHead(503, { "content-type": "application/json" }); response.end('{"error":{"code":"unavailable"}}'); });
    await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
    await fs.mkdir(data);
    const env = { ...process.env, WARCARDS_DATA: data, WARCARDS_SERVER: `http://127.0.0.1:${server.address().port}` };
    for (const name of ["ELECTRON_RUN_AS_NODE", "WARCARDS_SCREENSHOT", "WARCARDS_DEMO"]) delete env[name];
    const executable = path.join(packaged, "World of Warcards.exe");
    const result = await new Promise((resolve, reject) => {
      const child = spawn(executable, ["--warcards-smoke-test"], { cwd: scratch, env, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
      let output = "";
      child.stdout.on("data", bytes => { output += bytes; }); child.stderr.on("data", bytes => { output += bytes; });
      const timer = setTimeout(() => {
        // Only the fixture process tree started above is terminated on timeout.
        if (child.pid) spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
        reject(new Error("Packaged startup timed out:\n" + output));
      }, 45_000);
      child.once("error", error => { clearTimeout(timer); reject(error); });
      child.once("exit", code => { clearTimeout(timer); resolve({ code, output }); });
    });
    if (result.code !== 0) throw new Error("Packaged executable failed:\n" + result.output);
    const proof = JSON.parse(await fs.readFile(path.join(data, "startup-proof.json"), "utf8"));
    if (proof.version !== pkg.version || proof.catalogVersion !== catalog.catalogVersion || proof.ready !== true) throw new Error("Packaged startup proof did not match the release");
    console.log(`PASS real packaged executable ${proof.version}: main process, preload bridge, renderer and isolated fresh setup`);
  } finally {
    if (server) await new Promise(resolve => server.close(resolve));
    if (!path.resolve(scratch).startsWith(path.resolve(os.tmpdir()) + path.sep) || !path.basename(scratch).startsWith("warcards-packaged-check-")) throw new Error("Invalid temporary cleanup target");
    await fs.rm(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
