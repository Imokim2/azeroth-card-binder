// The sync engine: one pass that reads every account's saved data, uploads what the server has not stored, brings back
// the roll tape for Ranked and the standings for the Ladder tab, and writes the one file the add-on reads (docs/ROADMAP.md,
// 2.2 and 2.4). `start` runs a pass at startup and when the game saves, with retries for pending work.
//
// Nothing is kept that the files do not already hold: the saved-data file is the upload queue, and Sync.lua is rebuilt
// whole on every pass, so a crash, a restart or a failed request cannot leave the two out of step.
import { readBinder, BinderFileError } from "./binderFile.ts";
import type { Binder } from "./binderFile.ts";
import { fetchReleases, fetchStandings, fetchTape, fetchSeasons, sendReports, syncBinder } from "./client.ts";
import type { SeasonData } from "./seasons.ts";
import { cachedStandings } from "./communityCache.ts";
import type { PendingReport } from "./binderFile.ts";
import type { ClientOptions, Outcome, Standings } from "./client.ts";
import { readText, watchSettled, writeFileAtomic } from "./files.ts";
import type { Install } from "./files.ts";
import { LuaSyntaxError } from "./luaTable.ts";
import { syncFileText } from "./syncFile.ts";
import type { Ack } from "./syncFile.ts";
import { compareVersions, readAddonVersion, updateReport } from "./versions.ts";
import type { Releases, UpdateReport } from "./versions.ts";

// The server's refill threshold (server/src/tape.ts REFILL_BELOW): below this many unused entries it issues more.
const TAPE_REFILL_BELOW = 250;

export type EngineOptions = {
  install: Install;
  client: ClientOptions;
  // The player's id once the key is registered (for "your place"); null before that.
  playerId: () => string | null;
  standingsEveryMs?: number; // legacy test/config option; standings now refresh only for saved progress
  quietMs?: number; // how long the game's file must stay unchanged before it is read (default 1.5 seconds)
  everyMs?: number; // optional diagnostic polling; no periodic pass by default (zero also disables it)
  releasesEveryMs?: number; // minimum gap between update checks during saved-file syncs (default six hours)
  initialReleases?: Releases; // already checked by the controller on launch/manual check
  initialReleasesAt?: number; // milliseconds; reusing the cache must not extend its age
  log?: (message: string) => void;
  onReport?: (report: PassReport) => void; // told after every pass, whoever asked for it
  keepSavedBackup?: (account: string, source: string) => Promise<void>;
};

export type AccountReport = {
  account: string;
  // What happened to this account's file: an upload outcome, or why it could not be read.
  result: Outcome | { status: "unreadable"; reason: string } | { status: "not-registered" };
  mode: string | null;
  rankedSetup?: boolean;
};

export type PassReport = {
  accounts: AccountReport[];
  tape: { start: number; count: number } | { status: string } | null;
  standings: "fresh" | "kept" | "unavailable";
  wroteSync: boolean;
  updates: UpdateReport; // whether the app and the add-on are out of date
  signedRelease?: { manifest: string; signature: string }; // the server's signed release manifest, for the controller to check
  releases?: Releases; // keep the controller's cache in step with saved-progress checks
  releasesCheckedAt?: number;
  retryAfterMs?: number; // required Ranked data could not be fetched; the automatic runner retries with backoff
};

export class Engine {
  readonly #options: EngineOptions;
  #running: Promise<PassReport> | null = null;
  #acks = new Map<string, Ack>();
  #tape: { start: number; entries: string[] } | undefined;
  #rankedIssue: "binder-mismatch" | "position-mismatch" | undefined;
  #rankedSetups: string[] = [];
  #standings: Standings | undefined;
  #loadedCommunity = false;
  #seasons: SeasonData | undefined;
  #seasonBinders: string[] = [];
  #checkedSeasons = false;
  #releases: Releases | undefined; // the versions the server last announced
  #releasesAt = 0;
  #reportsDone: string[] = []; // tokens of reports the server has settled, newest last; written to Sync.lua for the add-on

  constructor(options: EngineOptions) {
    this.#options = options;
    this.#releases = options.initialReleases;
    if (this.#releases) this.#releasesAt = options.initialReleasesAt ?? options.client.now() * 1000;
  }

  // The roll tape held for the player belongs to the binder they had; after a new binder it must not be written again.
  forgetTape(): void {
    this.#tape = undefined;
  }

  useReleases(releases: Releases, checkedAt: number): void {
    this.#releases = releases;
    this.#releasesAt = checkedAt;
  }

  // One pass. Passes never overlap: asking while one is running returns that one.
  syncOnce(options: { saved?: boolean } = {}): Promise<PassReport> {
    if (!this.#running) {
      this.#running = this.#pass(options.saved === true).finally(() => {
        this.#running = null;
      });
    }
    return this.#running;
  }

  async #pass(savedFileChanged: boolean): Promise<PassReport> {
    const { install, client } = this.#options;
    if (!this.#loadedCommunity) {
      this.#loadedCommunity = true;
      this.#standings = cachedStandings(await readText(install.syncPath).catch(() => ""));
    }
    const accounts: AccountReport[] = [];
    this.#rankedSetups = [];
    let anyRanked = false;
    let rankedBlocked = false;
    let tapeNext = 1; // the furthest tape position any Ranked add-on file says it will use next
    let uploadedProgress = false;
    const reports = new Map<string, PendingReport>();
    const seasonBinders: string[] = [];
    let running: string | null = null; // the oldest add-on version that last wrote an account's file
    for (const file of install.savedFiles) {
      let binder: Binder;
      let source: string;
      try {
        source = await readText(file.path);
        binder = readBinder(source);
      } catch (error) {
        const reason = error instanceof BinderFileError || error instanceof LuaSyntaxError || error instanceof Error ? error.message : String(error);
        accounts.push({ account: file.account, result: { status: "unreadable", reason }, mode: null });
        continue;
      }
      const wantsRanked = binder.mode === "ranked" || binder.rankedStarter === true;
      if (wantsRanked) {
        anyRanked = true;
        tapeNext = Math.max(tapeNext, binder.tapeNext);
      }
      if (binder.addonVersion && (running === null || compareVersions(binder.addonVersion, running) < 0)) running = binder.addonVersion;
      for (const report of binder.reports) reports.set(report.token, report);
      const result = await syncBinder(client, binder, this.#acks.get(file.account) ?? null);
      if (result.status === "diverged" || result.status === "history-missing") {
        this.#acks.delete(file.account);
        if (wantsRanked) rankedBlocked = true;
      }
      if (wantsRanked && result.status === "rejected") rankedBlocked = true;
      if (result.status === "synced" && result.uploaded > 0) uploadedProgress = true;
      if (result.status === "synced" && result.ack) this.#acks.set(file.account, result.ack);
      if (result.status === "synced" && binder.modeSetupID) seasonBinders.push(binder.modeSetupID);
      if (result.status === "synced" && result.ack?.seq === binder.head.seq && result.ack.hash === binder.head.hash) {
        try { await this.#options.keepSavedBackup?.(file.account, source); }
        catch { this.#options.log?.("The local recovery copy could not be saved; the game save is unchanged."); }
      }
      if (result.status === "synced" && binder.rankedStarter && binder.modeSetupID) this.#rankedSetups.push(binder.modeSetupID);
      accounts.push({
        account: file.account, mode: binder.mode,
        ...(binder.rankedStarter && binder.mode !== "ranked" ? { rankedSetup: true } : {}),
        result: result.status === "rejected" && result.code === "unknown_key" ? { status: "not-registered" } : result,
      });
    }

    this.#seasonBinders = seasonBinders;
    // Reports the player made in the game go up once; the ones the server has settled are written for the add-on to forget.
    const pending = [...reports.values()].filter((report) => !this.#reportsDone.includes(report.token));
    if (accounts.length > 0 && pending.length > 0) {
      const sent = await sendReports(client, pending);
      if (sent.status === "reported") this.#reportsDone = [...this.#reportsDone, ...sent.done.filter((token) => !this.#reportsDone.includes(token))].slice(-200);
      else this.#options.log?.(`reports could not be sent: ${JSON.stringify(sent)}`);
    }

    // The tape is asked for after the uploads, so the server knows how far the add-on has got.
    let tape: PassReport["tape"] = null;
    let retryAfterMs: number | undefined;
    let rankedPaused = false;
    // It is asked for only when the add-on is running low (or has none), not on every pass: the server issues more only below this
    // many unused entries anyway, and a tape request is the most expensive one it answers.
    const held = this.#tape ? this.#tape.start + this.#tape.entries.length - 1 : 0; // the last position the app holds
    const left = held - (tapeNext - 1); // held entries the add-on has not used
    const lowOnTape = !this.#tape || tapeNext < this.#tape.start || left <= TAPE_REFILL_BELOW;
    if (rankedBlocked) {
      this.#tape = undefined;
      this.#rankedIssue = "binder-mismatch";
      tape = { status: "binder-mismatch" };
    } else if (anyRanked && !lowOnTape && this.#tape) {
      this.#rankedIssue = undefined;
      tape = { start: this.#tape.start, count: left };
    } else if (anyRanked) {
      const reply = await fetchTape(client, running ?? undefined);
      if (reply.status === "rejected" && reply.code === "addon_too_old") rankedPaused = true;
      if (reply.status === "tape") {
        if (reply.start > tapeNext) {
          this.#tape = undefined;
          this.#rankedIssue = "position-mismatch";
          tape = { status: "position-mismatch" };
          for (const account of accounts) if (account.mode === "ranked") {
            account.result = { status: "rejected", code: "tape_position_mismatch" };
          }
        } else {
          this.#rankedIssue = undefined;
          this.#tape = { start: reply.start, entries: reply.entries };
          tape = { start: reply.start, count: reply.entries.length };
        }
      } else {
        tape = { status: reply.status };
        if (reply.status === "retry-later") retryAfterMs = reply.afterMs;
        this.#options.log?.(`the roll tape could not be fetched: ${JSON.stringify(reply)}`);
      }
    }

    let standings: PassReport["standings"] = this.#standings ? "kept" : "unavailable";
    const now = client.now() * 1000;
    if (savedFileChanged || uploadedProgress) {
      const reply = await fetchStandings(client, this.#options.playerId());
      if (reply.status === "standings") {
        this.#standings = reply.standings;
        standings = "fresh";
      }
    }
    if (seasonBinders.length && (!this.#checkedSeasons || savedFileChanged || uploadedProgress)) {
      const reply = await fetchSeasons(client, seasonBinders);
      if (reply.status === "seasons") this.#seasons = reply.data;
      else if (reply.status === "retry-later") retryAfterMs = Math.max(retryAfterMs ?? 0, reply.afterMs);
      if (reply.status !== "retry-later") this.#checkedSeasons = true;
    }

    // Which versions are current: asked every so often, and kept when the server cannot be reached.
    if (!this.#releases || now - this.#releasesAt >= (this.#options.releasesEveryMs ?? 21_600_000)) {
      const reply = await fetchReleases(client);
      if (reply.status === "releases") {
        this.#releases = reply.releases;
        this.#releasesAt = now;
      }
    }
    const updates = updateReport(client.clientVersion, this.#releases, await readAddonVersion(install.root), running, rankedPaused);

    // Sync.lua is always written whole from what is known now.
    const written = await this.#writeSync(client.now());
    const report: PassReport = { accounts, tape, standings, wroteSync: written, updates,
      ...(this.#releases?.signed ? { signedRelease: this.#releases.signed } : {}),
      ...(this.#releases ? { releases: this.#releases, releasesCheckedAt: this.#releasesAt } : {}),
      ...(retryAfterMs !== undefined ? { retryAfterMs } : {}) };
    this.#options.onReport?.(report);
    return report;
  }

  async #writeSync(syncedAt: number): Promise<boolean> {
    const text = syncFileText({
      syncedAt, companionReady: true, rankedSetups: this.#rankedSetups, acks: [...this.#acks.values()].filter((ack) => ack.seq > 0), reportsDone: this.#reportsDone,
      ...(this.#rankedIssue ? { rankedIssue: this.#rankedIssue } : {}),
      ...(this.#releases ? { releases: { latestAddon: this.#releases.addon.latest, minAddon: this.#releases.addon.min } } : {}),
      ...(this.#tape ? { tape: this.#tape } : {}),
      ...(this.#seasons ? { seasonal: { ...this.#seasons, binders: this.#seasons.binders.filter(id => this.#seasonBinders.includes(id)) } } : {}),
      ...(this.#standings ? { leaderboard: this.#standings.leaderboard, you: this.#standings.you, verified: this.#standings.verified, firsts: this.#standings.firsts } : {}),
    });
    try {
      await writeFileAtomic(this.#options.install.syncPath, text);
      return true;
    } catch (error) {
      this.#options.log?.(`Sync.lua could not be written: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }

  // No network polling while idle. File saves trigger work; a change during an upload queues one more pass.
  // Only failed required work is retried, backing off from a minute to half an hour and respecting Retry-After.
  start(): () => Promise<void> {
    const { install } = this.#options;
    let stopped = false, active = false, queued = false, queuedSave = false, failures = 0;
    let retry: ReturnType<typeof setTimeout> | undefined;
    let pending: Promise<void> = Promise.resolve();
    const scheduleRetry = (afterMs: number): void => {
      failures++;
      const backoff = Math.min(1_800_000, 60_000 * 2 ** Math.min(failures - 1, 5));
      retry = setTimeout(() => run(), Math.max(afterMs, backoff));
    };
    const run = (saved = false): void => {
      if (stopped) return;
      if (active) { queued = true; queuedSave = queuedSave || saved; return; }
      if (retry) { clearTimeout(retry); retry = undefined; }
      active = true;
      pending = this.syncOnce({ saved }).then((report) => {
        if (stopped) return;
        const wait = report.accounts.flatMap((account) => (account.result.status === "retry-later" ? [account.result.afterMs] : []));
        if (!report.wroteSync) wait.push(60_000);
        if (report.retryAfterMs !== undefined) wait.push(report.retryAfterMs);
        if (wait.length > 0) scheduleRetry(Math.max(...wait));
        else failures = 0;
      }, (error: unknown) => {
        this.#options.log?.(`a pass failed: ${error instanceof Error ? error.message : String(error)}`);
        if (!stopped) scheduleRetry(60_000);
      }).finally(() => {
        active = false;
        if (queued && !stopped) { const savedAgain = queuedSave; queued = false; queuedSave = false; run(savedAgain); }
      });
    };
    const stops = install.savedFiles.map((file) => watchSettled(file.path, () => run(true), this.#options.quietMs ?? 1500));
    const interval = this.#options.everyMs;
    const timer = interval !== undefined && interval > 0 ? setInterval(() => run(), interval) : undefined;
    run();
    return () => {
      stopped = true;
      if (retry) clearTimeout(retry);
      if (timer) clearInterval(timer);
      for (const stop of stops) stop();
      return pending;
    };
  }
}
