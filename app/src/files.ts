// Finding the game's files, writing ours safely, and noticing when the game rewrites its saved data.
//
// The game writes SavedVariables when the player reloads the interface or logs out, so a change means "the player
// just finished a session". The file is written all at once, but not instantly: wait until it has stopped changing
// before reading, and never read a half-written file.
import { mkdir, readFile, readdir, rename, stat, writeFile } from "node:fs/promises";
import { watch } from "node:fs";
import { basename, dirname, join } from "node:path";

export const ADDON_NAME = "AzerothCardBinder";

export type Install = {
  root: string; // the game folder that holds WTF and Interface
  savedFiles: { account: string; path: string }[]; // one saved-data file per WoW account
  syncPath: string; // where the app writes Data/Sync.lua for the add-on
};

async function isDirectory(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isDirectory();
  } catch {
    return false;
  }
}

// Look for the game folder: `start` itself, or a folder up to two levels below it, that contains WTF/Account.
// (The exact layout of World of Warcraft: Forever is not confirmed yet, so this does not assume a folder name.)
export async function findGameFolders(start: string): Promise<string[]> {
  const found: string[] = [];
  const visit = async (folder: string, depth: number): Promise<void> => {
    if (await isDirectory(join(folder, "WTF", "Account"))) found.push(folder);
    if (depth === 0) return;
    let names: string[];
    try {
      names = await readdir(folder);
    } catch {
      return;
    }
    for (const name of names.sort()) {
      if (name === "WTF" || name === "Interface" || name.startsWith(".")) continue;
      const child = join(folder, name);
      if (await isDirectory(child)) await visit(child, depth - 1);
    }
  };
  await visit(start, 2);
  return found;
}

export async function describeInstall(root: string): Promise<Install> {
  const accounts = join(root, "WTF", "Account");
  const savedFiles: Install["savedFiles"] = [];
  for (const account of (await readdir(accounts)).sort()) {
    const path = join(accounts, account, "SavedVariables", `${ADDON_NAME}.lua`);
    try {
      if ((await stat(path)).isFile()) savedFiles.push({ account, path });
    } catch {
      // This account has never used the add-on.
    }
  }
  return { root, savedFiles, syncPath: join(root, "Interface", "AddOns", ADDON_NAME, "Data", "Sync.lua") };
}

// Write a file so a reader never sees half of it: write beside it, then rename over it.
export async function writeFileAtomic(path: string, data: string | Uint8Array): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const temporary = join(dirname(path), `.${basename(path)}.${process.pid}.tmp`);
  await (typeof data === "string" ? writeFile(temporary, data, "utf8") : writeFile(temporary, data));
  await rename(temporary, path);
}

export const readText = (path: string): Promise<string> => readFile(path, "utf8");

// Call `onChange` once after `path` has been written and has then stayed unchanged for `quietMs`. Returns a function
// that stops watching. A busy writer (many events in a burst) causes one call, not many.
export function watchSettled(path: string, onChange: () => void, quietMs = 1500): () => void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const watcher = watch(dirname(path), (_event, name) => {
    if (name !== null && name !== basename(path)) return;
    if (timer) clearTimeout(timer);
    timer = setTimeout(onChange, quietMs);
  });
  return () => {
    if (timer) clearTimeout(timer);
    watcher.close();
  };
}
