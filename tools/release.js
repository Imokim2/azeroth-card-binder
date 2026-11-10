// Checks, tests, versions and packages the add-on.
//
//   node tools/release.js check          syntax-check every Lua and JavaScript file and the add-on's file list
//   node tools/release.js test           run the Lua tests and the shared-contract tests
//   node tools/release.js build          check, test, then build dist/AzerothCardBinder-<version>.zip
//   node tools/release.js bump <x.y.z>   set the version in the .toc and open a section in CHANGELOG.md
//
// It needs LuaJIT on the PATH (or set LUAJIT to its location). Nothing here talks to the network.
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.join(__dirname, "..");
const addonDir = path.join(root, "AzerothCardBinder");
const tocPath = path.join(addonDir, "AzerothCardBinder.toc");
const luajit = process.env.LUAJIT || "luajit";

const run = (command, args, options = {}) =>
    spawnSync(command, args, { cwd: root, encoding: "utf8", stdio: options.show ? "inherit" : "pipe" });

function files(dir, extension, skip = []) {
    const found = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (skip.includes(entry.name)) continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) found.push(...files(full, extension, skip));
        else if (entry.name.endsWith(extension)) found.push(full);
    }
    return found;
}

const relative = (file) => path.relative(root, file).replace(/\\/g, "/");

function version() {
    const match = fs.readFileSync(tocPath, "utf8").match(/^## Version:\s*(\S+)/m);
    if (!match) throw new Error("no Version line in the .toc");
    return match[1];
}

function check() {
    const problems = [];
    const skip = ["node_modules", ".git", "dist"];

    // Every Lua file must compile.
    const probe = run(luajit, ["-e", "print(1)"]);
    if (probe.error || probe.status !== 0) {
        throw new Error(`LuaJIT was not found (tried "${luajit}"). Install it or set LUAJIT.`);
    }
    const lua = files(root, ".lua", skip);
    for (const file of lua) {
        const result = run(luajit, ["-bl", file]);
        if (result.status !== 0) problems.push(`${relative(file)}: ${(result.stderr || "").trim().split("\n")[0]}`);
    }

    // Every JavaScript file must parse.
    const js = files(root, ".js", skip);
    for (const file of js) {
        const result = run(process.execPath, ["--check", file]);
        if (result.status !== 0) problems.push(`${relative(file)}: ${(result.stderr || "").trim().split("\n").slice(0, 3).join(" ")}`);
    }

    // Every JSON file must parse.
    const json = files(root, ".json", skip);
    for (const file of json) {
        try { JSON.parse(fs.readFileSync(file, "utf8")); } catch (error) { problems.push(`${relative(file)}: ${error.message}`); }
    }

    // The .toc must list real files, and every add-on Lua file must be listed (an unlisted file is never loaded).
    const toc = fs.readFileSync(tocPath, "utf8").split(/\r?\n/);
    const listed = toc.filter((line) => line.trim() && !line.startsWith("#")).map((line) => line.trim());
    for (const name of listed) {
        if (!fs.existsSync(path.join(addonDir, name))) problems.push(`.toc lists ${name}, which does not exist`);
    }
    for (const file of files(addonDir, ".lua")) {
        const name = path.relative(addonDir, file).replace(/\\/g, "/");
        if (!listed.includes(name)) problems.push(`${name} is not listed in the .toc, so the game would never load it`);
    }
    const v = version();
    if (!/^\d+\.\d+\.\d+$/.test(v)) problems.push(`the .toc version "${v}" is not x.y.z`);

    if (problems.length > 0) {
        console.error("Checks failed:\n  " + problems.join("\n  "));
        process.exit(1);
    }
    console.log(`checks passed: ${lua.length} Lua files, ${js.length} JavaScript files, ${json.length} JSON files, ${listed.length} files in the .toc, version ${v}`);
}

function test() {
    for (const [command, args] of [[luajit, ["tests/run.lua"]], [process.execPath, ["--test", "tests/vectors.test.js"]]]) {
        const result = run(command, args, { show: true });
        if (result.status !== 0) {
            console.error(`\nTests failed: ${path.basename(command)} ${args.join(" ")}`);
            process.exit(1);
        }
    }
}

function build() {
    check();
    test();
    const v = version();
    const dist = path.join(root, "dist");
    const stage = path.join(dist, "stage");
    fs.rmSync(stage, { recursive: true, force: true });
    fs.mkdirSync(stage, { recursive: true });
    // Notes for developers are not shipped to players.
    const notShipped = new Set(["Portrait-Backdrops.txt", "Portrait-Backdrops-Needed.txt"]);
    fs.cpSync(addonDir, path.join(stage, "AzerothCardBinder"), {
        recursive: true, filter: (source) => !notShipped.has(path.basename(source)),
    });
    const zip = path.join(dist, `AzerothCardBinder-${v}.zip`);
    fs.rmSync(zip, { force: true });
    const result = process.platform === "win32"
        // Windows ships a tar that writes real zip files with forward slashes in the names.
        ? run(path.join(process.env.SystemRoot || "C:\\Windows", "System32", "tar.exe"), ["-a", "-c", "-f", zip, "-C", stage, "AzerothCardBinder"])
        : spawnSync("zip", ["-r", "-q", zip, "AzerothCardBinder"], { cwd: stage, encoding: "utf8" });
    fs.rmSync(stage, { recursive: true, force: true });
    if (result.status !== 0 || !fs.existsSync(zip)) {
        console.error("Could not build the ZIP: " + ((result.stderr || String(result.error)) || "").trim());
        process.exit(1);
    }
    console.log(`built ${relative(zip)} (${(fs.statSync(zip).size / 1024 / 1024).toFixed(1)} MB)`);
}

function bump(next) {
    if (!/^\d+\.\d+\.\d+$/.test(next || "")) throw new Error("usage: node tools/release.js bump <x.y.z>");
    const current = version();
    if (next === current) throw new Error(`the version is already ${current}`);
    const toc = fs.readFileSync(tocPath, "utf8");
    fs.writeFileSync(tocPath, toc.replace(/^## Version:.*$/m, `## Version: ${next}`));
    const changelogPath = path.join(root, "CHANGELOG.md");
    const log = fs.readFileSync(changelogPath, "utf8").replace(/\r\n/g, "\n");
    const today = new Date().toISOString().slice(0, 10);
    if (!log.includes("## Unreleased")) throw new Error("CHANGELOG.md has no Unreleased section");
    fs.writeFileSync(changelogPath, log.replace("## Unreleased", `## Unreleased\n\nNothing yet.\n\n## ${next} - ${today}`));
    console.log(`version ${current} -> ${next}. Move the Unreleased notes under the new heading in CHANGELOG.md, then commit.`);
}

const [command, argument] = process.argv.slice(2);
try {
    ({ check, test, build, bump: () => bump(argument) })[command]();
} catch (error) {
    if (error instanceof TypeError) {
        console.error("usage: node tools/release.js check | test | build | bump <x.y.z>");
    } else {
        console.error(error.message);
    }
    process.exit(1);
}
