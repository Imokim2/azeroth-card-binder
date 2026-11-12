// Which versions are current, and whether the ones installed are out of date. The server says what is newest and what is
// the oldest still accepted (GET /v1/releases); the add-on's installed version is read from its .toc file, and the version
// it last ran as from the saved data it wrote. Nothing here changes a file: it only says what is out of date.
import { join } from "node:path";
import { ADDON_NAME } from "./files.ts";
import { readText } from "./files.ts";

export type Releases = { app: { latest: string; min: string }; addon: { latest: string; min: string } };

// "current": up to date. "update": a newer one exists. "required": older than the oldest still accepted. "unknown": not known.
export type UpdateState = "current" | "update" | "required" | "unknown";

export type UpdateReport = {
  app: { version: string; latest: string | null; min: string | null; state: UpdateState };
  addon: {
    installed: string | null; // the version in the add-on's folder, which the game loads next time
    running: string | null; // the version the add-on last ran as, as it wrote it in the saved data (the oldest, over accounts)
    latest: string | null;
    min: string | null;
    state: UpdateState; // for the installed version
    reloadNeeded: boolean; // the folder holds a newer version than the one the game last ran
  };
};

const VERSION = /^\d+\.\d+\.\d+$/;
export const isVersion = (value: unknown): value is string => typeof value === "string" && VERSION.test(value);

// -1, 0 or 1 for x.y.z compared with x.y.z.
export function compareVersions(a: string, b: string): -1 | 0 | 1 {
  const left = a.split(".").map(Number);
  const right = b.split(".").map(Number);
  for (let index = 0; index < 3; index++) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference !== 0) return difference < 0 ? -1 : 1;
  }
  return 0;
}

export function updateState(have: string | null, latest: string | null, min: string | null): UpdateState {
  if (!have || !latest || !min) return "unknown";
  if (compareVersions(have, min) < 0) return "required";
  return compareVersions(have, latest) < 0 ? "update" : "current";
}

// The version in the add-on's .toc ("## Version: 0.4.0"), or null when the add-on is not in the game folder.
export async function readAddonVersion(root: string): Promise<string | null> {
  try {
    const toc = await readText(join(root, "Interface", "AddOns", ADDON_NAME, `${ADDON_NAME}.toc`));
    const found = /^## Version:[ \t]*(\d+\.\d+\.\d+)[ \t]*\r?$/m.exec(toc);
    return found ? (found[1] as string) : null;
  } catch {
    return null;
  }
}

export function updateReport(app: string, releases: Releases | undefined, installed: string | null, running: string | null): UpdateReport {
  const addonLatest = releases?.addon.latest ?? null;
  const addonMin = releases?.addon.min ?? null;
  return {
    app: { version: app, latest: releases?.app.latest ?? null, min: releases?.app.min ?? null, state: updateState(app, releases?.app.latest ?? null, releases?.app.min ?? null) },
    addon: {
      installed, running, latest: addonLatest, min: addonMin, state: updateState(installed, addonLatest, addonMin),
      reloadNeeded: installed !== null && running !== null && compareVersions(installed, running) > 0,
    },
  };
}
