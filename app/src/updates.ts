// Installing updates, without trusting the network: a manifest is believed only when its Ed25519 signature matches the key
// built into the app; a download is kept only when its size and SHA-256 are exactly what the signed manifest says; the
// add-on is unpacked into a scratch folder and checked before it replaces anything, with the old copy kept aside so a
// failed install can be put back. Nothing here runs a file it did not verify.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cp, mkdir, mkdtemp, readdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, relative, sep } from "node:path";
import { verifySignature } from "../../packages/shared/src/crypto.ts";
import { ADDON_NAME } from "./files.ts";
import { isVersion } from "./versions.ts";

export type Artifact = { version: string; url: string; sha256: string; size: number; notes: string };
export type Manifest = { issuedAt: number; app: Artifact; addon: Artifact };

export const MAX_INSTALLER_BYTES = 400 * 1024 * 1024;
export const MAX_ADDON_BYTES = 50 * 1024 * 1024;
const MAX_ADDON_FILES = 600;

function artifact(value: unknown, limit: number): Artifact | null {
  if (typeof value !== "object" || value === null) return null;
  const item = value as Record<string, unknown>;
  const { version, url, sha256, size, notes } = item;
  if (!isVersion(version) || typeof url !== "string" || !/^https:\/\/[^\s"]+$/.test(url)) return null;
  if (typeof sha256 !== "string" || !/^[0-9a-f]{64}$/.test(sha256)) return null;
  if (typeof size !== "number" || !Number.isSafeInteger(size) || size < 1 || size > limit) return null;
  return { version, url, sha256, size, notes: typeof notes === "string" ? notes.slice(0, 500) : "" };
}

// The manifest, if (and only if) it was signed with the key the app trusts.
export async function verifiedManifest(signed: { manifest: string; signature: string } | undefined, publicKey: string | null): Promise<Manifest | null> {
  if (!signed || !publicKey) return null;
  if (!(await verifySignature(publicKey, signed.signature, signed.manifest))) return null;
  try {
    const parsed = JSON.parse(signed.manifest) as Record<string, unknown>;
    if (parsed["format"] !== 1) return null;
    const app = artifact(parsed["app"], MAX_INSTALLER_BYTES);
    const addon = artifact(parsed["addon"], MAX_ADDON_BYTES);
    const issuedAt = parsed["issuedAt"];
    if (!app || !addon || typeof issuedAt !== "number") return null;
    return { issuedAt, app, addon };
  } catch {
    return null;
  }
}

export type Download = (url: string) => Promise<{ ok: boolean; status: number; arrayBuffer(): Promise<ArrayBuffer> }>;

// Fetch a file and keep it only if it is exactly the one the signed manifest describes.
export async function downloadVerified(download: Download, item: Artifact, destination: string): Promise<void> {
  const response = await download(item.url);
  if (!response.ok) throw new Error(`the download failed (${response.status})`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length !== item.size) throw new Error("the download is not the size the release says");
  if (createHash("sha256").update(bytes).digest("hex") !== item.sha256) throw new Error("the download does not match the release's checksum");
  await mkdir(dirname(destination), { recursive: true });
  await writeFile(destination + ".part", bytes);
  await rename(destination + ".part", destination);
}

// Windows 10 and later ship a tar (bsdtar) in System32 that reads zip files. It is named by its full path, so a different tar
// that happens to be earlier on the PATH (Git's, for one) is never the one that unpacks an update.
export const TAR = process.platform === "win32" ? join(process.env["SystemRoot"] ?? "C:\\Windows", "System32", "tar.exe") : "tar";

// The names inside a zip.
function listZip(zip: string): string[] {
  const listed = spawnSync(TAR, ["-tf", zip], { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  if (listed.status !== 0) throw new Error("the add-on file could not be read");
  return listed.stdout.split(/\r?\n/).filter((name) => name !== "");
}

// Every name must sit inside AzerothCardBinder/: no absolute paths, no drive letters, no "..", no backslashes.
export function entriesAreSafe(names: string[]): boolean {
  if (names.length === 0 || names.length > MAX_ADDON_FILES) return false;
  return names.every((name) => name.startsWith(ADDON_NAME + "/") && !name.includes("\\") && !name.includes(":") && !name.split("/").includes(".."));
}

// Every regular file under a folder, as "a/b.lua". With `noLinks`, a link anywhere is an error: an unpacked update must hold
// plain files only, so nothing in it can point out of the folder it is copied from.
async function files(folder: string, base = folder, noLinks = false): Promise<string[]> {
  const out: string[] = [];
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    const full = join(folder, entry.name);
    if (noLinks && entry.isSymbolicLink()) throw new Error("the add-on file holds a link");
    if (entry.isDirectory()) out.push(...(await files(full, base, noLinks)));
    else if (entry.isFile()) out.push(relative(base, full).split(sep).join("/"));
  }
  return out;
}

const SYNC_FILE = "Data/Sync.lua"; // written by the companion app, never by an add-on release: it is kept as it is

async function tocVersion(folder: string): Promise<string | null> {
  try {
    const toc = await readFile(join(folder, `${ADDON_NAME}.toc`), "utf8");
    return /^## Version:[ \t]*(\d+\.\d+\.\d+)[ \t]*\r?$/m.exec(toc)?.[1] ?? null;
  } catch {
    return null;
  }
}

// Put a verified add-on zip into the game folder. The old copy is saved in `backups` first; if anything goes wrong the old
// files are put back. Data/Sync.lua is never replaced.
export async function installAddon(zip: string, gameRoot: string, backups: string, expectedVersion: string): Promise<{ backup: string | null }> {
  if (!entriesAreSafe(listZip(zip))) throw new Error("the add-on file holds paths it should not");
  const scratch = await mkdtemp(join(tmpdir(), "warcards-addon-"));
  const target = join(gameRoot, "Interface", "AddOns", ADDON_NAME);
  let backup: string | null = null;
  try {
    const extracted = spawnSync(TAR, ["-xf", zip, "-C", scratch], { encoding: "utf8" });
    if (extracted.status !== 0) throw new Error("the add-on file could not be unpacked");
    const fresh = join(scratch, ADDON_NAME);
    if ((await tocVersion(fresh)) !== expectedVersion) throw new Error("the add-on file is not the version the release says");
    const incoming = await files(fresh, fresh, true);
    let existing: string[] = [];
    try {
      if ((await stat(target)).isDirectory()) existing = await files(target);
    } catch {
      // Not installed yet: a first install.
    }
    if (existing.length > 0) {
      const old = (await tocVersion(target)) ?? "unknown";
      backup = join(backups, `${ADDON_NAME}-${old}-${Date.now()}`);
      await mkdir(backups, { recursive: true });
      await cp(target, backup, { recursive: true });
    }
    try {
      for (const name of incoming) {
        if (name === SYNC_FILE && existing.includes(SYNC_FILE)) continue;
        const destination = join(target, ...name.split("/"));
        await mkdir(dirname(destination), { recursive: true });
        await cp(join(fresh, ...name.split("/")), destination);
      }
      // Files an older release had and this one does not are removed, so no stale code stays loaded.
      for (const name of existing) {
        if (name !== SYNC_FILE && !incoming.includes(name)) await rm(join(target, ...name.split("/")), { force: true });
      }
      if ((await tocVersion(target)) !== expectedVersion) throw new Error("the install did not leave the version it should");
    } catch (error) {
      if (backup) {
        for (const name of await files(target).catch(() => [] as string[])) if (name !== SYNC_FILE) await rm(join(target, ...name.split("/")), { force: true });
        await cp(backup, target, { recursive: true, force: true });
      }
      throw error;
    }
    return { backup };
  } finally {
    await rm(scratch, { recursive: true, force: true });
  }
}
