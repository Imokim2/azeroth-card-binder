// What the companion app does, with no window in it: remembers the settings, signs the player in with Discord, picks the
// game folder, runs the sync engine and keeps a plain description of how things stand (`status()`) for whatever draws the
// window. The Electron shell only supplies the parts that need Electron (opening the browser, a folder dialog, the
// system's key protection), so all of this is tested without a screen.
import { deleteAccount, resetBinder } from "./client.ts";
import type { ClientOptions, FetchLike } from "./client.ts";
import { Engine } from "./engine.ts";
import type { PassReport } from "./engine.ts";
import { describeInstall, findGameFolders } from "./files.ts";
import type { Install } from "./files.ts";
import { loadOrCreateIdentity } from "./identity.ts";
import type { Identity, SecretStore } from "./identity.ts";
import { loadSettings, saveSettings } from "./settings.ts";
import type { Settings } from "./settings.ts";
import { SecretStorageUnavailable } from "./secrets.ts";
import { signInAndRegister } from "./signIn.ts";
import type { SignInOptions } from "./signIn.ts";
import { join } from "node:path";

export type Deps = {
  dataFolder: string; // where settings.json lives
  secrets: SecretStore;
  server: string;
  version: string;
  catalogVersion: string;
  open: SignInOptions["open"]; // opens a page in the player's browser
  chooseFolder: () => Promise<string | null>; // asks the player to pick a folder
  confirm: (message: string, button: string) => Promise<boolean>; // asks the player to agree to something that cannot be undone
  fetch: FetchLike;
  now: () => number; // seconds
  sleep: (milliseconds: number) => Promise<void>;
  signInPort?: number; // for tests
  engineTimings?: { quietMs?: number; everyMs?: number; standingsEveryMs?: number };
  applyStartAtLogin?: (on: boolean) => void;
  commonFolders?: string[]; // where to look for the game when asked to find it
};

export type Status = {
  version: string;
  server: string;
  problem: string | null; // the app itself cannot work (for example the key cannot be stored)
  signedIn: boolean;
  visibility: "public" | "private";
  startAtLogin: boolean;
  gameFolder: string | null;
  accounts: { account: string; mode: string | null; state: string }[];
  lastSyncAt: number | null;
  tapeEntries: number | null; // roll-tape entries ready for the add-on, when any account plays Ranked
  standings: "fresh" | "kept" | "unavailable" | null;
  needsNewBinder: boolean; // the saved data is a different binder from the one the server holds
  message: string | null; // the latest thing worth telling the player
  busy: boolean;
};

const SIGN_IN_FAILURES: Record<string, string> = {
  denied: "Sign-in was cancelled.",
  timeout: "Sign-in timed out. Click Sign in with Discord to try again.",
  "port-busy": "Another program is using port 53682, which the sign-in needs. Close it and try again.",
  closed: "The sign-in window could not be started.",
  browser: "Your browser could not be opened. Open it yourself and try again.",
};

const accountState = (result: PassReport["accounts"][number]["result"]): string => {
  switch (result.status) {
    case "synced": return result.uploaded > 0 ? `Synced (${result.uploaded} new events)` : "Up to date";
    case "unreadable": return `Cannot read the saved data: ${result.reason}`;
    case "not-registered": return "Not registered: sign in with Discord";
    case "retry-later": return "The server could not be reached; trying again soon";
    case "rejected": return `The server refused it (${result.code})`;
    case "history-missing": return "Older events are missing from the saved data";
    case "diverged": return "This is a new binder: it does not continue the one the server has";
  }
};

export class Controller {
  readonly #deps: Deps;
  #settings: Settings = { gameFolder: null, visibility: "public", playerId: null, startAtLogin: false };
  #identity: Identity | null = null;
  #engine: Engine | null = null;
  #stopEngine: (() => void) | null = null;
  #listeners = new Set<(status: Status) => void>();
  #problem: string | null = null;
  #message: string | null = null;
  #busy = false;
  #lastReport: PassReport | null = null;
  #lastSyncAt: number | null = null;

  constructor(deps: Deps) {
    this.#deps = deps;
  }

  get #settingsPath(): string {
    return join(this.#deps.dataFolder, "settings.json");
  }

  #options(): ClientOptions | null {
    if (!this.#identity) return null;
    return {
      baseUrl: this.#deps.server, fetch: this.#deps.fetch, identity: this.#identity, clientVersion: this.#deps.version,
      catalogVersion: this.#deps.catalogVersion, now: this.#deps.now, sleep: this.#deps.sleep,
    };
  }

  status(): Status {
    const report = this.#lastReport;
    return {
      version: this.#deps.version, server: this.#deps.server, problem: this.#problem, signedIn: this.#settings.playerId !== null,
      visibility: this.#settings.visibility, startAtLogin: this.#settings.startAtLogin, gameFolder: this.#settings.gameFolder,
      accounts: report?.accounts.map((entry) => ({ account: entry.account, mode: entry.mode, state: accountState(entry.result) })) ?? [],
      lastSyncAt: this.#lastSyncAt,
      tapeEntries: report?.tape && "count" in report.tape ? report.tape.count : null,
      standings: report?.standings ?? null,
      needsNewBinder: report?.accounts.some((entry) => entry.result.status === "diverged") ?? false,
      message: this.#message, busy: this.#busy,
    };
  }

  // Be told whenever the status changes. Returns a function that stops the listening.
  onStatus(listener: (status: Status) => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  #changed(): void {
    const status = this.status();
    for (const listener of this.#listeners) listener(status);
  }

  #say(message: string | null): void {
    this.#message = message;
    this.#changed();
  }

  // Load the settings and the key, and start syncing if the player has already signed in and picked a folder.
  async start(): Promise<void> {
    this.#settings = await loadSettings(this.#settingsPath);
    try {
      this.#identity = await loadOrCreateIdentity(this.#deps.secrets);
      this.#problem = null;
    } catch (error) {
      this.#identity = null;
      this.#problem = error instanceof SecretStorageUnavailable
        ? `Your key cannot be stored safely on this computer (${error.message}). The app cannot sign in or upload until that is fixed.`
        : `The key could not be loaded: ${error instanceof Error ? error.message : String(error)}`;
    }
    await this.#restartEngine();
    this.#changed();
  }

  async stop(): Promise<void> {
    this.#stopEngine?.();
    this.#stopEngine = null;
    this.#engine = null;
  }

  async #save(): Promise<void> {
    await saveSettings(this.#settingsPath, this.#settings);
  }

  async #restartEngine(): Promise<void> {
    this.#stopEngine?.();
    this.#stopEngine = null;
    this.#engine = null;
    const options = this.#options();
    const folder = this.#settings.gameFolder;
    if (!options || !folder || !this.#settings.playerId) return;
    let install: Install;
    try {
      install = await describeInstall(folder);
    } catch {
      this.#say("The game folder could not be read. Choose it again.");
      return;
    }
    if (install.savedFiles.length === 0) this.#message = "No saved data from the add-on yet. Log in to the game once with the add-on installed, then reload.";
    const timings = this.#deps.engineTimings ?? {};
    this.#engine = new Engine({
      install, client: options, playerId: () => this.#settings.playerId,
      ...(timings.quietMs !== undefined ? { quietMs: timings.quietMs } : {}),
      ...(timings.everyMs !== undefined ? { everyMs: timings.everyMs } : {}),
      ...(timings.standingsEveryMs !== undefined ? { standingsEveryMs: timings.standingsEveryMs } : {}),
      onReport: (report) => {
        this.#lastReport = report;
        this.#lastSyncAt = this.#deps.now();
        this.#busy = false;
        this.#changed();
      },
    });
    this.#stopEngine = this.#engine.start();
  }

  // Sign in with Discord in the player's browser, then register this computer's key against that account.
  async signIn(visibility: "public" | "private"): Promise<void> {
    const options = this.#options();
    if (!options) return this.#say(this.#problem ?? "The key is not ready yet.");
    this.#busy = true;
    this.#say("Waiting for you to sign in with Discord in your browser...");
    const result = await signInAndRegister(options, visibility, {
      open: this.#deps.open, ...(this.#deps.signInPort !== undefined ? { port: this.#deps.signInPort } : {}),
    });
    this.#busy = false;
    if (result.status === "registered") {
      this.#settings = { ...this.#settings, playerId: result.playerId, visibility };
      await this.#save();
      this.#say("Signed in. " + (this.#settings.gameFolder ? "Syncing now." : "Now choose your game folder."));
      await this.#restartEngine();
      this.#changed();
      return;
    }
    if (result.status === "failed") return this.#say(SIGN_IN_FAILURES[result.reason] ?? "Sign-in failed.");
    if (result.status === "rejected") {
      return this.#say(result.code === "bad_identity" ? "Discord's answer could not be verified. Try again."
        : result.code === "registration_closed" ? "Registration is not open yet." : `The server refused the sign-in (${result.code}).`);
    }
    this.#say("The server could not be reached. Check your connection and try again.");
  }

  async signOut(): Promise<void> {
    this.#settings = { ...this.#settings, playerId: null };
    await this.#save();
    this.#lastReport = null;
    await this.#restartEngine();
    this.#say("Signed out. Your key stays on this computer; sign in again to carry on.");
  }

  // The game folder is the one that holds WTF and Interface; the player may pick it or a folder above it.
  async chooseGameFolder(): Promise<void> {
    const picked = await this.#deps.chooseFolder();
    if (!picked) return;
    const found = await findGameFolders(picked);
    const first = found[0];
    if (!first) return this.#say("No game folder found there. Choose the folder that contains WTF and Interface.");
    await this.#useFolder(first, found.length > 1 ? `Found ${found.length} game folders; using ${first}.` : null);
  }

  // Look in the usual places for the game.
  async findGame(): Promise<void> {
    for (const start of this.#deps.commonFolders ?? []) {
      const found = await findGameFolders(start);
      if (found[0]) return this.#useFolder(found[0], `Found the game at ${found[0]}.`);
    }
    this.#say("The game was not found in the usual places. Choose its folder yourself.");
  }

  async #useFolder(folder: string, message: string | null): Promise<void> {
    this.#settings = { ...this.#settings, gameFolder: folder };
    await this.#save();
    this.#message = message;
    await this.#restartEngine();
    this.#changed();
  }

  async syncNow(): Promise<void> {
    if (!this.#settings.playerId) return this.#say("Sign in with Discord first.");
    if (!this.#settings.gameFolder) return this.#say("Choose your game folder first.");
    // Looking at the folder again also picks up an account that has used the add-on since the app started.
    await this.#restartEngine();
    this.#busy = true;
    this.#changed();
    await this.#engine?.syncOnce();
  }

  // The saved data is a new binder (the player started over in the game). After they agree, the server archives the old
  // binder and takes the new one from its first event; the old roll tape is dropped, as it belonged to the old binder.
  async startNewBinder(): Promise<void> {
    const options = this.#options();
    if (!options || !this.#settings.playerId) return this.#say("Sign in with Discord first.");
    const agreed = await this.#deps.confirm(
      "Start a new binder on the server?\n\nYour old binder stays on record but stops counting, and your ranked score starts again from nothing. Do this only if you started over in the game. It can be done once a day.",
      "Start a new binder",
    );
    if (!agreed) return this.#say("Nothing was changed.");
    this.#busy = true;
    this.#say("Starting a new binder...");
    const result = await resetBinder(options);
    this.#busy = false;
    if (result.status === "reset") {
      this.#engine?.forgetTape();
      this.#say("A new binder was started. Syncing it now.");
      await this.syncNow();
      return;
    }
    if (result.status === "rejected" && result.code === "too_soon") {
      const wait = Number(result.detail?.["retryAfter"] ?? 0);
      return this.#say(`You started a new binder recently. Try again in about ${Math.max(1, Math.ceil(wait / 3600))} hour(s).`);
    }
    this.#say(result.status === "rejected" ? `The server refused it (${result.code}).` : "The server could not be reached. Try again.");
  }

  // Delete everything the server holds about the player. Their cards in the game and on this computer are not touched.
  async deleteMyData(): Promise<void> {
    const options = this.#options();
    if (!options || !this.#settings.playerId) return this.#say("You are not signed in, so the server holds nothing about you from this computer.");
    const agreed = await this.#deps.confirm(
      "Delete all your data from the server?\n\nYour record, your ladder place, your Discord link and any archived binders are erased for good. Your cards in the game and the files on this computer are not touched. You can sign up again later, from nothing.",
      "Delete my data",
    );
    if (!agreed) return this.#say("Nothing was changed.");
    this.#busy = true;
    this.#say("Deleting your data...");
    const result = await deleteAccount(options);
    this.#busy = false;
    if (result.status === "deleted") {
      this.#settings = { ...this.#settings, playerId: null };
      await this.#save();
      this.#lastReport = null;
      await this.#restartEngine();
      return this.#say("Your data was deleted from the server. You are signed out.");
    }
    this.#say(result.status === "rejected" && result.code === "banned" ? "A banned account's record is kept, so it cannot be deleted." : result.status === "rejected" ? `The server refused it (${result.code}).` : "The server could not be reached. Try again.");
  }

  async setStartAtLogin(on: boolean): Promise<void> {
    this.#settings = { ...this.#settings, startAtLogin: on };
    await this.#save();
    this.#deps.applyStartAtLogin?.(on);
    this.#changed();
  }
}
