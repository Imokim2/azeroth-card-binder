// Exercise the actual NSIS hook with harmless fixture processes, never a live companion installation.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const appRoot = fileURLToPath(new URL("../", import.meta.url));
const cache = process.env["WARCARDS_NSIS_CACHE"] ?? join(process.env["LOCALAPPDATA"] ?? "", "electron-builder", "Cache");
const cachedFiles = process.platform === "win32" && existsSync(cache) ? readdirSync(cache, { recursive: true, encoding: "utf8" }) : [];
const compiler = cachedFiles.find((path) => path.endsWith("makensis.exe") && !path.includes("Bin"));
const plugin = cachedFiles.find((path) => path.endsWith("x86-unicode\\nsProcess.dll"));
const available = Boolean(compiler && plugin);
if (process.env["WARCARDS_REQUIRE_INSTALLER_TESTS"] === "1" && !available) throw new Error("Build the Windows installer before running native process checks");

test("NSIS ignores an unrelated program in the target folder but detects a moved companion", { skip: !available, timeout: 90_000 }, async () => {
  const root = await mkdtemp(join(tmpdir(), "warcards-installer-process-"));
  const target = join(root, "install"), moved = join(root, "moved");
  await mkdir(target); await mkdir(moved);
  const name = `Warcards-fixture-${process.pid}.exe`;
  const children: ReturnType<typeof spawn>[] = [];
  const nsis = (path: string) => path;
  async function compile(filename: string, source: string): Promise<string> {
    const script = join(root, filename + ".nsi");
    const exe = join(root, filename + ".exe");
    await writeFile(script, `Unicode true\nRequestExecutionLevel user\nSilentInstall silent\nOutFile "${nsis(exe)}"\n${source}`);
    const result = spawnSync(join(cache, compiler!), ["/V2", script], { encoding: "utf8", windowsHide: true });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    return exe;
  }
  function run(exe: string): Promise<number | null> {
    return new Promise((resolve, reject) => {
      const child = spawn(exe, ["/S"], { windowsHide: true });
      children.push(child); child.once("error", reject); child.once("exit", resolve);
    });
  }
  try {
    const fixture = await compile("fixture", "Section\nSleep 60000\nSectionEnd\n");
    const { copyFile } = await import("node:fs/promises");
    const unrelated = join(target, "Unrelated.exe"), companion = join(moved, name);
    await copyFile(fixture, unrelated); await copyFile(fixture, companion);
    const harness = await compile("check", `!include "LogicLib.nsh"\n!addincludedir "${nsis(join(appRoot, "node_modules/app-builder-lib/templates/nsis/include"))}"\n!addplugindir /x86-unicode "${nsis(dirname(join(cache, plugin!)))}"\n!include "nsProcess.nsh"\n!define APP_EXECUTABLE_FILENAME "${name}"\n!include "${nsis(join(appRoot, "installer.nsh"))}"\nSection\nStrCpy $INSTDIR "${nsis(target)}"\n!insertmacro customCheckAppRunning\nSectionEnd\n`);
    const other = spawn(unrelated, ["/S"], { windowsHide: true }); children.push(other);
    await new Promise((resolve) => setTimeout(resolve, 500));
    assert.equal(other.exitCode, null);
    assert.equal(await run(harness), 0, "another executable in the install folder must not block setup");
    const running = spawn(companion, ["/S"], { windowsHide: true }); children.push(running);
    await new Promise((resolve) => setTimeout(resolve, 500));
    assert.equal(await run(harness), 2, "a companion moved outside the target folder must still block replacement");
    assert.equal(running.exitCode, null, "setup must not forcibly kill the companion");
    const exited = new Promise((resolve) => running.once("exit", resolve)); running.kill(); await exited;
    assert.equal(await run(harness), 0, "setup can continue after the moved companion exits");
  } finally {
    await Promise.all(children.map((child) => child.exitCode !== null || child.signalCode !== null ? Promise.resolve() : new Promise((resolve) => { child.once("exit", resolve); child.kill(); })));
    // root is a newly created test-only temporary directory.
    await rm(root, { recursive: true, force: true });
  }
});
