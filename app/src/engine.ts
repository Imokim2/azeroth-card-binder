// The sync engine: one pass that reads every account's saved data, uploads what the server has not stored, brings back
// the roll tape for Ranked and the standings for the Ladder tab, and writes the one file the add-on reads (docs/ROADMAP.md,
// 2.2 and 2.4). `start` runs a pass whenever the game finishes writing a saved file, and on a timer.
//
// Nothing is kept that the files do not already hold: the saved-data file is the upload queue, and Sync.lua is rebuilt
// whole on every pass, so a crash, a restart or a failed request cannot leave the two out of step.
import { readBinder, BinderFileError } from "./binderFile.ts";
import type { Binder } from "./binderFile.ts";
import { fetchStandings, fetchTape, syncBinder, uploadWanted } from "./client.ts";
import type { ClientOptions, Outcome, Standings } from "./client.ts";
import { readText, watchSettled, writeFileAtomic } from "./files.ts";
import type { Install } from "./files.ts";
import { LuaSyntaxError } from "./luaTable.ts";
import { syncFileText } from "./syncFile.ts";
import type { Ack } from "./syncFile.ts";

export type EngineOptions = {
  install: Install;
  client: ClientOptions;
  // The player's id once the key is registered (for "your place"); null before that.
  playerId: () => string | null;
  standingsEveryMs?: number; // at most this often (default five minutes)
  quietMs?: number; // how long the game's file must stay unchanged before it is read (default 1.5 seconds)
  everyMs?: number; // a pass on a timer even with no change, to refill the tape and refresh standings (default ten minutes)
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
};

export class Engine {
  readonly #options: EngineOptions;
  #running: Promise<PassReport> | null = null;
  #acks = new Map<string, Ack>();
  #tape: { start: number; entries: string[] } | undefined;
  #standings: Standings | undefined;
  #standingsAt = 0;
  #wantedSent: string | null = null; // the wanted list the server last accepted, so it is only sent when it changes

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
    const wanted = new Set<string>();
    for (const file of install.savedFiles) {
      let binder: Binder;
      try {
        binder = readBinder(await readText(file.path));
      } catch (error) {
        const reason = error instanceof BinderFileError || error instanceof LuaSyntaxError || error instanceof Error ? error.message : String(error);
        accounts.push({ account: file.account, result: { status: "unreadable", reason }, mode: null });
        continue;
      }
      if (binder.mode === "ranked") anyRanked = true;
      for (const key of binder.wanted) wanted.add(key);
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

    // The tape is asked for after the uploads, so the server knows how far the add-on has got.
    let tape: PassReport["tape"] = null;
    if (anyRanked) {
      const reply = await fetchTape(client);
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
    if (!this.#standings || now - this.#standingsAt >= (this.#options.standingsEveryMs ?? 300_000)) {
      const reply = await fetchStandings(client, this.#options.playerId());
      if (reply.status === "standings") {
        this.#standings = reply.standings;
        this.#standingsAt = now;
        standings = "fresh";
      }
    }

    // Sync.lua is always written whole from what is known now.
    const written = await this.#writeSync(client.now());
    const report: PassReport = { accounts, tape, standings, wroteSync: written };
    this.#options.onReport?.(report);
    return report;
  }

  async #writeSync(syncedAt: number): Promise<boolean> {
    const text = syncFileText({
      syncedAt, acks: [...this.#acks.values()],
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
