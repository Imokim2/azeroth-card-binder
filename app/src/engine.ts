// The sync engine: one pass that reads every account's saved data, uploads what the server has not stored, brings back
// the roll tape for Ranked and the standings for the Ladder tab, and writes the one file the add-on reads (docs/ROADMAP.md,
// 2.2 and 2.4). `start` runs a pass whenever the game finishes writing a saved file, and on a timer.
//
// Nothing is kept that the files do not already hold: the saved-data file is the upload queue, and Sync.lua is rebuilt
// whole on every pass, so a crash, a restart or a failed request cannot leave the two out of step.
import { readBinder, BinderFileError } from "./binderFile.ts";
import type { Binder } from "./binderFile.ts";
import { fetchReleases, fetchStandings, fetchTape, sendReports, syncBinder, uploadWanted } from "./client.ts";
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
  standingsEveryMs?: number; // at most this often (default half an hour: the ladder moves slowly, and every refresh costs the server reads)
  quietMs?: number; // how long the game's file must stay unchanged before it is read (default 1.5 seconds)
  everyMs?: number; // a pass on a timer even with no change, to refill the tape and refresh standings (default ten minutes)
  releasesEveryMs?: number; // how often to ask the server which versions are current (default half an hour)
  log?: (message: string) => void;
  onReport?: (report: PassReport) => void; // told after every pass, whoever asked for it
};

export type AccountReport = {
  account: string;
  // What happened to this account's file: an upload outcome, or why it could not be read.
  result: Outcome | { status: "unreadable"; reason: string } | { status: "not-registered" };
  mode: string | null;
};

export type PassReport = {
  accounts: AccountReport[];
  tape: { start: number; count: number } | { status: string } | null;
  standings: "fresh" | "kept" | "unavailable";
  wroteSync: boolean;
  updates: UpdateReport; // whether the app and the add-on are out of date
  signedRelease?: { manifest: string; signature: string }; // the server's signed release manifest, for the controller to check
};

export class Engine {
  readonly #options: EngineOptions;
  #running: Promise<PassReport> | null = null;
  #acks = new Map<string, Ack>();
  #tape: { start: number; entries: string[] } | undefined;
  #standings: Standings | undefined;
  #standingsAt = 0;
  #releases: Releases | undefined; // the versions the server last announced
  #releasesAt = 0;
  #wantedSent: string | null = null; // the wanted list the server last accepted, so it is only sent when it changes
  #reportsDone: string[] = []; // tokens of reports the server has settled, newest last; written to Sync.lua for the add-on

  constructor(options: EngineOptions) {
    this.#options = options;
  }

  // The roll tape held for the player belongs to the binder they had; after a new binder it must not be written again.
  forgetTape(): void {
    this.#tape = undefined;
  }

  // One pass. Passes never overlap: asking while one is running returns that one.
  syncOnce(): Promise<PassReport> {
    if (!this.#running) {
      this.#running = this.#pass().finally(() => {
        this.#running = null;
      });
    }
    return this.#running;
  }

  async #pass(): Promise<PassReport> {
    const { install, client } = this.#options;
    const accounts: AccountReport[] = [];
    let anyRanked = false;
    let tapeNext = 1; // the furthest tape position any Ranked add-on file says it will use next
    const wanted = new Set<string>();
    const reports = new Map<string, PendingReport>();
    let running: string | null = null; // the oldest add-on version that last wrote an account's file
    for (const file of install.savedFiles) {
      let binder: Binder;
      try {
        binder = readBinder(await readText(file.path));
      } catch (error) {
        const reason = error instanceof BinderFileError || error instanceof LuaSyntaxError || error instanceof Error ? error.message : String(error);
        accounts.push({ account: file.account, result: { status: "unreadable", reason }, mode: null });
        continue;
      }
      if (binder.mode === "ranked") {
        anyRanked = true;
        tapeNext = Math.max(tapeNext, binder.tapeNext);
      }
      if (binder.addonVersion && (running === null || compareVersions(binder.addonVersion, running) < 0)) running = binder.addonVersion;
      for (const key of binder.wanted) wanted.add(key);
      for (const report of binder.reports) reports.set(report.token, report);
      const result = await syncBinder(client, binder, this.#acks.get(file.account) ?? null);
      if (result.status === "synced" && result.ack) this.#acks.set(file.account, result.ack);
      accounts.push({
        account: file.account, mode: binder.mode,
        result: result.status === "rejected" && result.code === "unknown_key" ? { status: "not-registered" } : result,
      });
    }

    // The player's wanted list goes up when it has changed since the server last took it.
    const list = [...wanted].sort().slice(0, 60);
    const fingerprint = JSON.stringify(list);
    if (accounts.length > 0 && fingerprint !== this.#wantedSent) {
      const sent = await uploadWanted(client, list);
      if (sent.status === "stored") this.#wantedSent = fingerprint;
    }

    // Reports the player made in the game go up once; the ones the server has settled are written for the add-on to forget.
    const pending = [...reports.values()].filter((report) => !this.#reportsDone.includes(report.token));
    if (accounts.length > 0 && pending.length > 0) {
      const sent = await sendReports(client, pending);
      if (sent.status === "reported") this.#reportsDone = [...this.#reportsDone, ...sent.done.filter((token) => !this.#reportsDone.includes(token))].slice(-200);
      else this.#options.log?.(`reports could not be sent: ${JSON.stringify(sent)}`);
    }

    // The tape is asked for after the uploads, so the server knows how far the add-on has got.
    let tape: PassReport["tape"] = null;
    let rankedPaused = false;
    // It is asked for only when the add-on is running low (or has none), not on every pass: the server issues more only below this
    // many unused entries anyway, and a tape request is the most expensive one it answers.
    const held = this.#tape ? this.#tape.start + this.#tape.entries.length - 1 : 0; // the last position the app holds
    const left = held - (tapeNext - 1); // held entries the add-on has not used
    const lowOnTape = !this.#tape || tapeNext < this.#tape.start || left <= TAPE_REFILL_BELOW;
    if (anyRanked && !lowOnTape && this.#tape) {
      tape = { start: this.#tape.start, count: left };
    } else if (anyRanked) {
      const reply = await fetchTape(client, running ?? undefined);
      if (reply.status === "rejected" && reply.code === "addon_too_old") rankedPaused = true;
      if (reply.status === "tape") {
        this.#tape = { start: reply.start, entries: reply.entries };
        tape = { start: reply.start, count: reply.entries.length };
      } else {
        tape = { status: reply.status };
        this.#options.log?.(`the roll tape could not be fetched: ${JSON.stringify(reply)}`);
      }
    }

    let standings: PassReport["standings"] = this.#standings ? "kept" : "unavailable";
    const now = client.now() * 1000;
    if (!this.#standings || now - this.#standingsAt >= (this.#options.standingsEveryMs ?? 1_800_000)) {
      const reply = await fetchStandings(client, this.#options.playerId());
      if (reply.status === "standings") {
        this.#standings = reply.standings;
        this.#standingsAt = now;
        standings = "fresh";
      }
    }

    // Which versions are current: asked every so often, and kept when the server cannot be reached.
    if (!this.#releases || now - this.#releasesAt >= (this.#options.releasesEveryMs ?? 1_800_000)) {
      const reply = await fetchReleases(client);
      if (reply.status === "releases") {
        this.#releases = reply.releases;
        this.#releasesAt = now;
      }
    }
    const updates = updateReport(client.clientVersion, this.#releases, await readAddonVersion(install.root), running, rankedPaused);

    // Sync.lua is always written whole from what is known now.
    const written = await this.#writeSync(client.now());
    const report: PassReport = { accounts, tape, standings, wroteSync: written, updates, ...(this.#releases?.signed ? { signedRelease: this.#releases.signed } : {}) };
    this.#options.onReport?.(report);
    return report;
  }

  async #writeSync(syncedAt: number): Promise<boolean> {
    const text = syncFileText({
      syncedAt, acks: [...this.#acks.values()], reportsDone: this.#reportsDone,
      ...(this.#releases ? { releases: { latestAddon: this.#releases.addon.latest, minAddon: this.#releases.addon.min } } : {}),
      ...(this.#tape ? { tape: this.#tape } : {}),
      ...(this.#standings ? { leaderboard: this.#standings.leaderboard, you: this.#standings.you, verified: this.#standings.verified, firsts: this.#standings.firsts, wanted: this.#standings.wanted } : {}),
    });
    try {
      await writeFileAtomic(this.#options.install.syncPath, text);
      return true;
    } catch (error) {
      this.#options.log?.(`Sync.lua could not be written: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }

  // Run a pass now, then again whenever the game finishes writing a saved file, and every `everyMs`. A pass that is told to
  // come back later (the server asked to wait, or it was unreachable) is retried after that wait. Returns a function that stops.
  start(): () => void {
    const { install } = this.#options;
    let stopped = false;
    let retry: ReturnType<typeof setTimeout> | undefined;
    const run = (): void => {
      if (stopped) return;
      void this.syncOnce().then((report) => {
        if (stopped) return;
        const wait = report.accounts.flatMap((account) => (account.result.status === "retry-later" ? [account.result.afterMs] : []));
        if (wait.length > 0) {
          if (retry) clearTimeout(retry);
          retry = setTimeout(run, Math.max(...wait));
        }
      }, (error: unknown) => this.#options.log?.(`a pass failed: ${error instanceof Error ? error.message : String(error)}`));
    };
    const stops = install.savedFiles.map((file) => watchSettled(file.path, run, this.#options.quietMs ?? 1500));
    const timer = setInterval(run, this.#options.everyMs ?? 600_000);
    run();
    return () => {
      stopped = true;
      if (retry) clearTimeout(retry);
      clearInterval(timer);
      for (const stop of stops) stop();
    };
  }
}
