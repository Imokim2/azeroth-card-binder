// What the companion app does, with no window in it: remembers the settings, signs the player in with Discord, picks the
// game folder, runs the sync engine and keeps a plain description of how things stand (`status()`) for whatever draws the
// window. The Electron shell only supplies the parts that need Electron (opening the browser, a folder dialog, the
// system's key protection), so all of this is tested without a screen.
import { deleteAccount, exportAccount, fetchReleases, resetBinder } from "./client.ts";
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
import { RELEASE_PUBLIC_KEY } from "./releaseKey.ts";
import { downloadVerified, installAddon, verifiedManifest } from "./updates.ts";
import type { Download, Manifest } from "./updates.ts";
import { compareVersions, readAddonVersion, updateReport } from "./versions.ts";
import type { Releases, UpdateReport } from "./versions.ts";
import { rm } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { findRecovery, keepSavedBackup, recoveryServer, restoreRecovery, savedBackups } from "./recovery.ts";

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
  releaseKey?: string | null; // the public key release manifests must be signed with (default: the one built into the app)
  download?: Download; // fetches a file for an update; absent, nothing is downloaded
  runInstaller?: (path: string) => void; // starts the new companion installer and quits this app
  saveFile?: (suggestedName: string, text: string) => Promise<string | null>; // asks where to save a file and writes it; null when cancelled
  gameClosed?: (folder: string) => Promise<boolean>; // a failed process check must return false
  onSyncIssue?: () => void; // bring the repair prompt into view once per changed history conflict
};

export type Status = {
  version: string;
  server: string;
  problem: string | null; // the app itself cannot work (for example the key cannot be stored)
  signedIn: boolean;
  visibility: "public" | "private";
  startAtLogin: boolean;
  gameFolder: string | null;
  accounts: { account: string; mode: string | null; state: string; setupReady?: boolean }[];
  lastSyncAt: number | null;
  tapeEntries: number | null; // roll-tape entries ready for the add-on, when any account plays Ranked
  standings: "fresh" | "kept" | "unavailable" | null;
  needsNewBinder: boolean; // the saved data is a different binder from the one the server holds
  message: string | null; // the latest thing worth telling the player
  busy: boolean;
  repairing?: boolean;
  updates: UpdateReport | null; // whether the app and the add-on are out of date, once a sync has looked
  canUpdate: { addon: boolean; app: boolean }; // an update can be installed from here: it is signed, and newer than what is installed
  updating: "addon" | "app" | null; // an update is being downloaded or installed
  checkingUpdates: boolean;
  updateCheckMessage: string | null;
  newer: { addon: string | null; app: string | null; notes: { addon: string; app: string } } | null; // what the signed manifest offers
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
    case "rejected": return result.code === "tape_position_mismatch"
      ? "Your saved binder and Ranked supply are out of step. Your cards have been kept; check the selected game folder and saved-data backup."
      : `The server refused it (${result.code})`;
    case "history-missing": return "Older events are missing from the saved data";
    case "diverged": return "This saved binder differs from the server record. Your cards have been kept.";
  }
};

export class Controller {
  readonly #deps: Deps;
  #settings: Settings = { gameFolder: null, visibility: "public", playerId: null, startAtLogin: false };
  #identity: Identity | null = null;
  #engine: Engine | null = null;
  #stopEngine: (() => Promise<void>) | null = null;
  #listeners = new Set<(status: Status) => void>();
  #problem: string | null = null;
  #message: string | null = null;
  #busy = false;
  #repairing = false;
  #lastSyncConflict = "";
  #lastReport: PassReport | null = null;
  #lastSyncAt: number | null = null;
  #manifest: Manifest | null = null; // the release manifest, once its signature has been checked against the trusted key
  #updating: "addon" | "app" | null = null;
  #checkingUpdates = false;
  #updateCheckMessage: string | null = null;
  #releases: Releases | undefined;
  #releasesAt = 0;
  #lastUpdateAttempt = 0;
  #updates: UpdateReport | null = null;

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
      accounts: report?.accounts.map((entry) => {
        const ready = entry.rankedSetup && entry.result.status === "synced" && report.tape && "count" in report.tape && report.tape.count > 0;
        return { account: entry.account, mode: entry.mode, state: !report.wroteSync && entry.result.status === "synced"
          ? "Cannot write the addon sync file. Check folder access; retrying automatically."
          : ready ? "Reload the game UI to start in Ranked." : accountState(entry.result),
          ...(ready ? { setupReady: true } : {}) };
      }) ?? [],
      lastSyncAt: this.#lastSyncAt,
      tapeEntries: report?.tape && "count" in report.tape ? report.tape.count : null,
      standings: report?.standings ?? null,
      needsNewBinder: report?.accounts.some((entry) => entry.result.status === "diverged") ?? false,
      message: this.#message, busy: this.#busy, repairing: this.#repairing, updates: this.#updates ?? report?.updates ?? null,
      canUpdate: this.#canUpdate(), updating: this.#updating,
      checkingUpdates: this.#checkingUpdates,
      updateCheckMessage: this.#updateCheckMessage,
      newer: this.#manifest ? { addon: this.#manifest.addon.version, app: this.#manifest.app.version, notes: { addon: this.#manifest.addon.notes, app: this.#manifest.app.notes } } : null,
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
    await this.checkForUpdates();
    await this.#restartEngine();
    this.#changed();
  }

  async #readUpdates(): Promise<void> {
    const folder = this.#settings.gameFolder;
    this.#updates = updateReport(this.#deps.version, this.#releases,
      folder ? await readAddonVersion(folder) : null, this.#lastReport?.updates.addon.running ?? null,
      this.#lastReport?.updates.addon.rankedPaused ?? false);
  }

  // Public update checks also work before sign-in or choosing a game folder.
  // They do not upload a binder or refresh the leaderboard.
  async checkForUpdates(force = true): Promise<void> {
    if (this.#checkingUpdates || this.#updating) return;
    const now = this.#deps.now() * 1000;
    if (!force && this.#lastUpdateAttempt > 0 && now - this.#lastUpdateAttempt < 60_000) return;
    this.#lastUpdateAttempt = now;
    this.#checkingUpdates = true;
    this.#updateCheckMessage = null;
    this.#changed();
    try {
      const reply = await fetchReleases({ baseUrl: this.#deps.server, fetch: this.#deps.fetch,
        clientVersion: this.#deps.version, sleep: this.#deps.sleep, attempts: 1 });
      if (reply.status === "releases") {
        this.#releases = reply.releases;
        this.#releasesAt = this.#deps.now() * 1000;
        this.#engine?.useReleases(reply.releases, this.#releasesAt);
        await this.#trustRelease(reply.releases.signed);
        await this.#readUpdates();
        this.#updateCheckMessage = this.#canUpdate().app || this.#canUpdate().addon ? "Updates are available." : "Update check complete.";
      } else {
        this.#updateCheckMessage = "Could not check for updates. Check your connection and try again.";
      }
    } catch {
      this.#updateCheckMessage = "Could not check for updates. Check your connection and try again.";
    } finally {
      this.#checkingUpdates = false;
      this.#changed();
    }
  }

  async stop(): Promise<void> {
    await this.#stopEngine?.();
    this.#stopEngine = null;
    this.#engine = null;
  }

  async #save(): Promise<void> {
    await saveSettings(this.#settingsPath, this.#settings);
  }

  async #restartEngine(): Promise<void> {
    await this.#stopEngine?.();
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
      keepSavedBackup: (account, source) => keepSavedBackup(join(this.#deps.dataFolder, "binder-backups"), account, source),
      ...(timings.quietMs !== undefined ? { quietMs: timings.quietMs } : {}),
      ...(timings.everyMs !== undefined ? { everyMs: timings.everyMs } : {}),
      ...(timings.standingsEveryMs !== undefined ? { standingsEveryMs: timings.standingsEveryMs } : {}),
      ...(this.#releases ? { initialReleases: this.#releases, initialReleasesAt: this.#releasesAt } : {}),
      onReport: (report) => {
        const conflict = (report.wroteSync ? "" : "sync-file|") + report.accounts.filter(a => ["diverged", "history-missing", "unreadable"].includes(a.result.status)
          || (a.result.status === "rejected" && a.result.code === "tape_position_mismatch"))
          .map(a => a.account + ":" + a.result.status).join("|");
        const newlyConflicted = conflict !== "" && conflict !== this.#lastSyncConflict;
        this.#lastSyncConflict = conflict;
        this.#lastReport = report;
        this.#updates = report.updates;
        if (report.releases) this.#releases = report.releases;
        if (report.releasesCheckedAt !== undefined) this.#releasesAt = report.releasesCheckedAt;
        this.#lastSyncAt = this.#deps.now();
        this.#busy = false;
        void this.#trustRelease(report.signedRelease);
        this.#changed();
        if (newlyConflicted && !this.#repairing) this.#deps.onSyncIssue?.();
      },
    });
    this.#stopEngine = this.#engine.start();
  }

  // The server's release manifest is believed only when it is signed with the key built into the app.
  async #trustRelease(signed: PassReport["signedRelease"]): Promise<void> {
    const key = this.#deps.releaseKey === undefined ? RELEASE_PUBLIC_KEY : this.#deps.releaseKey;
    const manifest = await verifiedManifest(signed, key);
    if (JSON.stringify(manifest) !== JSON.stringify(this.#manifest)) {
      this.#manifest = manifest;
      this.#changed();
    }
  }

  #canUpdate(): { addon: boolean; app: boolean } {
    if (this.#repairing) return { addon: false, app: false };
    const manifest = this.#manifest;
    const installed = this.#updates?.addon.installed ?? null;
    return {
      addon: manifest !== null && this.#deps.download !== undefined && this.#settings.gameFolder !== null
        && (installed === null || compareVersions(manifest.addon.version, installed) > 0),
      app: manifest !== null && this.#deps.download !== undefined && this.#deps.runInstaller !== undefined
        && compareVersions(manifest.app.version, this.#deps.version) > 0,
    };
  }

  // Download the add-on the signed manifest names, check it, and put it in the game folder (the old copy is kept aside).
  async updateAddon(): Promise<void> {
    const manifest = this.#manifest;
    const folder = this.#settings.gameFolder;
    if (this.#updating || !manifest || !folder || !this.#canUpdate().addon || !this.#deps.download) return;
    this.#updating = "addon";
    this.#say("Downloading add-on " + manifest.addon.version + "...");
    const file = join(this.#deps.dataFolder, "updates", "AzerothCardBinder-" + manifest.addon.version + ".zip");
    try {
      await downloadVerified(this.#deps.download, manifest.addon, file);
      this.#message = "Installing add-on " + manifest.addon.version + "...";
      this.#changed();
      await installAddon(file, folder, join(this.#deps.dataFolder, "addon-backups"), manifest.addon.version);
      await this.#readUpdates();
      this.#updating = null;
      this.#say("Add-on " + manifest.addon.version + " is installed. Use /reload in the game, or restart it, to start using it.");
      void this.#engine?.syncOnce();
    } catch (error) {
      this.#updating = null;
      this.#say("The add-on could not be updated: " + (error instanceof Error ? error.message : "an unknown problem") + ". Your add-on was left as it was.");
    } finally {
      await rm(file, { force: true });
    }
  }

  // Download the new companion installer the signed manifest names, check it, and run it; this app then closes.
  async updateApp(): Promise<void> {
    const manifest = this.#manifest;
    if (this.#updating || !manifest || !this.#canUpdate().app || !this.#deps.download || !this.#deps.runInstaller) return;
    this.#updating = "app";
    this.#changed();
    let agreed: boolean;
    try {
      agreed = await this.#deps.confirm("Install World of Warcards " + manifest.app.version + " now? This app will close and open again. Your binder progress and settings will be kept.", "Install and restart");
    } catch {
      this.#updating = null;
      return this.#say("The update confirmation could not be opened. Nothing was changed.");
    }
    if (!agreed) { this.#updating = null; return this.#say("Nothing was changed."); }
    this.#say("Downloading companion " + manifest.app.version + "...");
    const updates = join(this.#deps.dataFolder, "updates");
    const file = join(updates, "World-of-Warcards-Setup-" + manifest.app.version + ".exe");
    try {
      await rm(updates, { recursive: true, force: true });
      await downloadVerified(this.#deps.download, manifest.app, file);
      this.#say("Installing companion " + manifest.app.version + "...");
      this.#deps.runInstaller(file);
    } catch (error) {
      this.#updating = null;
      this.#say("The companion could not be updated: " + (error instanceof Error ? error.message : "an unknown problem") + ". Nothing was changed.");
    }
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
    await this.#readUpdates();
    await this.#restartEngine();
    this.#changed();
  }

  async syncNow(): Promise<void> {
    if (this.#repairing) return;
    await this.checkForUpdates();
    if (!this.#settings.playerId) return this.#say("Sign in with Discord first.");
    if (!this.#settings.gameFolder) return this.#say("Choose your game folder first.");
    // Looking at the folder again also picks up an account that has used the add-on since the app started.
    await this.#restartEngine();
    this.#busy = true;
    this.#changed();
    await this.#engine?.syncOnce();
  }

  async repairSync(): Promise<void> {
    const options = this.#options(), folder = this.#settings.gameFolder;
    const player = this.#settings.playerId;
    if (this.#repairing || this.#updating) return;
    if (!options || !this.#settings.playerId) return this.#say("Sign in with Discord to repair syncing.");
    if (!folder) return this.#say("Choose your World of Warcraft folder first.");
    this.#repairing = true; this.#busy = true;
    this.#say("Checking your saved collection and rebuilding sync data...");
    try {
      await this.#restartEngine();
      const report = await this.#engine?.syncOnce();
      const issues = report?.accounts.filter(a => a.result.status !== "synced") ?? [];
      if (report && report.wroteSync && report.accounts.length > 0 && issues.length === 0 && (!report.tape || "count" in report.tape)) {
        return this.#say("Sync data rebuilt. Your cards and settings are unchanged. Reload the game UI to load it.");
      }
      const conflicts = issues.filter(a => ["diverged", "history-missing", "unreadable"].includes(a.result.status)
        || (a.result.status === "rejected" && a.result.code === "tape_position_mismatch"));
      if (conflicts.length !== 1 || issues.length !== 1) {
        return this.#say("Automatic repair could not finish. Check the account message, sign-in and game folder. Your collection has not been reset.");
      }
      await this.#stopEngine?.(); this.#stopEngine = null; this.#engine = null;
      this.#busy = true;
      this.#say("Checking whether your saved backup matches the server...");
      const exported = await exportAccount(options);
      if (exported.status !== "exported") return this.#say("The server backup check could not finish. Try again when connected. No saved data was changed.");
      const server = recoveryServer(exported.text);
      const install = await describeInstall(folder);
      const file = install.savedFiles.find(f => f.account === conflicts[0]!.account);
      const copies = file ? await savedBackups(join(this.#deps.dataFolder, "binder-backups"), file.account) : [];
      const plan = file && server ? await findRecovery(file.path, server, copies) : null;
      if (!plan) return this.#say("No backup could be proved safe to restore automatically. Your files and server collection are unchanged. Keep your backups and ask for help; do not start over to repair this.");
      const closed = () => this.#deps.gameClosed?.(folder) ?? Promise.resolve(false);
      if (!(await closed())) return this.#say("A verified backup is available. Close World of Warcraft, then click Repair sync again to restore it safely.");
      const agreed = await this.#deps.confirm(
        `Restore the verified backup for ${conflicts[0]!.account}?\n\nIt contains ${plan.copies} card copies in ${plan.mode === "ranked" ? "Ranked" : "Casual"} mode and matches your synced server record. It keeps all progress in the current save and your current settings. Both original files will be copied to the companion's recovery-backups folder first. Keep World of Warcraft closed until this finishes. This does not reset your binder or ranking.`,
        "Restore verified backup",
      );
      if (!agreed) return this.#say("Nothing was restored. Your current collection and backup are unchanged.");
      if (this.#settings.gameFolder !== folder || this.#settings.playerId !== player || this.#updating) {
        return this.#say("Your account or game folder changed. Nothing was restored.");
      }
      // Recheck both the server and local files after the confirmation; a newer session may have arrived.
      const checked = await exportAccount(options);
      const latest = checked.status === "exported" ? recoveryServer(checked.text) : null;
      const fresh = latest && file ? await findRecovery(file.path, latest, copies) : null;
      if (!fresh || fresh.current !== plan.current || fresh.backup !== plan.backup || fresh.head.hash !== plan.head.hash || fresh.tapeNext !== plan.tapeNext) {
        return this.#say("The collection changed during the backup check. Nothing was restored. Click Repair sync to check again.");
      }
      await restoreRecovery(fresh, join(this.#deps.dataFolder, "recovery-backups", randomUUID()), closed);
      this.#say("Verified backup restored. Your settings and original files were kept. You can start the game again after syncing finishes.");
    } catch {
      this.#say("Repair stopped without resetting your collection. Close the game and check folder access, then try again. Original recovery copies are kept if any were created.");
    } finally {
      try {
        if (!this.#engine) await this.#restartEngine();
        await this.#engine?.syncOnce();
      } catch { this.#say("The repair check finished, but syncing could not restart yet. Your recovery copies have been kept."); }
      this.#repairing = false;
      this.#busy = false;
      this.#changed();
    }
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
  // A copy of everything the server holds about the player, saved where they choose.
  async exportMyData(): Promise<void> {
    const options = this.#options();
    if (!options || !this.#settings.playerId) return this.#say("You are not signed in, so the server holds nothing about you from this computer.");
    if (!this.#deps.saveFile) return this.#say("Saving a file is not available here.");
    this.#busy = true;
    this.#say("Asking the server for your data...");
    const result = await exportAccount(options);
    this.#busy = false;
    if (result.status !== "exported") {
      return this.#say(result.status === "rejected" ? `The server refused it (${result.code}).` : "The server could not be reached. Try again.");
    }
    const where = await this.#deps.saveFile("worldofwarcards-my-data.json", result.text);
    this.#say(where ? `Your data was saved to ${where}. It holds personal information: keep it somewhere private.` : "Nothing was saved.");
  }

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
