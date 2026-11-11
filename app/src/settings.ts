// The app's own settings, kept in one small JSON file in its data folder. Nothing secret is in it (the key is stored
// separately, encrypted). A missing or damaged file gives the defaults rather than an error, and every field is checked
// on the way in, so an edited file can only ever change what the settings screen could.
import { readFile } from "node:fs/promises";
import { writeFileAtomic } from "./files.ts";

export type Settings = {
  gameFolder: string | null; // the game folder that holds WTF and Interface
  visibility: "public" | "private"; // chosen at sign-in: whether the player is listed on the ladder
  playerId: string | null; // set once the key is registered
  startAtLogin: boolean;
};

export const defaultSettings: Settings = { gameFolder: null, visibility: "public", playerId: null, startAtLogin: false };

export async function loadSettings(path: string): Promise<Settings> {
  let raw: unknown;
  try {
    raw = JSON.parse(await readFile(path, "utf8"));
  } catch {
    return { ...defaultSettings };
  }
  const object = typeof raw === "object" && raw !== null ? (raw as Record<string, unknown>) : {};
  const folder = object["gameFolder"];
  const id = object["playerId"];
  return {
    gameFolder: typeof folder === "string" && folder.length > 0 && folder.length < 1000 && !folder.includes("\u0000") ? folder : null,
    visibility: object["visibility"] === "private" ? "private" : "public",
    playerId: typeof id === "string" && /^[0-9A-Z]{26}$/.test(id) ? id : null,
    startAtLogin: object["startAtLogin"] === true,
  };
}

export async function saveSettings(path: string, settings: Settings): Promise<void> {
  await writeFileAtomic(path, JSON.stringify(settings, null, 2) + "\n");
}
