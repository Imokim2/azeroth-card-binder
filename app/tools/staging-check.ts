// A hand-run check of the real services, not a test: sign in with the real Discord, register a key on the staging
// server, and ask it for a roll tape (which shows whether the free plan's CPU limit is enough).
//
//   node app/tools/staging-check.ts
//
// It opens Discord in your browser; click Authorize. The player it creates is private, so it never appears on the
// ladder. The key lives only in memory, so each run registers a new key for the same Discord account (the old one is
// revoked, which is exactly how a lost key is replaced).
import { spawn } from "node:child_process";
import { fetchStandings, fetchTape } from "../src/client.ts";
import type { ClientOptions, FetchLike } from "../src/client.ts";
import { SERVERS } from "../src/config.ts";
import { loadOrCreateIdentity } from "../src/identity.ts";
import { signInAndRegister } from "../src/signIn.ts";

function openInBrowser(url: string): void {
  // rundll32 hands the whole address to the default browser, "&" characters included.
  const command = process.platform === "win32" ? ["rundll32", ["url.dll,FileProtocolHandler", url]] as const
    : process.platform === "darwin" ? ["open", [url]] as const : ["xdg-open", [url]] as const;
  spawn(command[0], [...command[1]], { detached: true, stdio: "ignore" }).unref();
  console.log("If no browser opened, paste this address into one:\n" + url + "\n");
}

let secret: string | null = null;
const identity = await loadOrCreateIdentity({ async get() { return secret; }, async set(value: string) { secret = value; } });
const fetchLike: FetchLike = async (url, init) => fetch(url, init as RequestInit);
const client: ClientOptions = {
  baseUrl: SERVERS.staging, fetch: fetchLike, identity, clientVersion: "0.1.0", catalogVersion: "", now: () => Math.floor(Date.now() / 1000),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)), attempts: 2,
};

console.log("Waiting for you to sign in with Discord in the browser (up to five minutes)...");
const registered = await signInAndRegister(client, "private", { open: openInBrowser });
console.log("sign-in and registration:", JSON.stringify(registered));
if (registered.status !== "registered") process.exit(1);

const started = Date.now();
const tape = await fetchTape(client);
console.log(`roll tape: ${tape.status}${tape.status === "tape" ? `, ${tape.entries.length} entries from ${tape.start}` : " " + JSON.stringify(tape)} in ${Date.now() - started} ms`);

const standings = await fetchStandings(client, registered.playerId);
console.log("standings:", standings.status === "standings" ? `${standings.standings.leaderboard.length} on the ladder` : JSON.stringify(standings));
