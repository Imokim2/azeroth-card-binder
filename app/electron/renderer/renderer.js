"use strict";
// Draws the status the controller reports, and passes the buttons on. All text from the app is put on the page as text
// (never as HTML), so nothing it says, including a name from a saved file, can ever act as markup or script.

const $ = (id) => document.getElementById(id);

// With "#demo-<name>" in the address (used only to take pictures of each screen) the page shows a made-up status.
const demos = {
  setup: { version: "0.1.0", server: "", problem: null, signedIn: false, visibility: "public", startAtLogin: false, gameFolder: null, accounts: [], lastSyncAt: null, tapeEntries: null, standings: null, message: null, busy: false },
  syncing: {
    version: "0.1.0", server: "", problem: null, signedIn: true, visibility: "public", startAtLogin: true, gameFolder: "D:\\Games\\World of Warcraft Forever",
    accounts: [{ account: "HARRYACCOUNT", mode: "ranked", state: "Synced (42 new events)" }, { account: "ALTACCOUNT", mode: "casual", state: "Up to date" }],
    lastSyncAt: Math.floor(Date.now() / 1000) - 95, tapeEntries: 9710, standings: "fresh", message: "Signed in. Syncing now.", busy: false,
  },
  problem: {
    version: "0.1.0", server: "", problem: "Your key cannot be stored safely on this computer. The app cannot sign in or upload until that is fixed.",
    signedIn: false, visibility: "public", startAtLogin: false, gameFolder: null, accounts: [], lastSyncAt: null, tapeEntries: null, standings: null, message: null, busy: false,
  },
};

function ago(seconds) {
  if (seconds === null) return "–";
  const gap = Math.max(0, Math.floor(Date.now() / 1000) - seconds);
  if (gap < 60) return "just now";
  if (gap < 3600) return Math.floor(gap / 60) + " min ago";
  return Math.floor(gap / 3600) + " h ago";
}

function render(status) {
  const ready = status.signedIn && status.gameFolder !== null;
  const pill = $("pill");
  pill.className = "pill " + (status.problem ? "bad" : status.busy ? "warn" : ready ? "ok" : "warn");
  pill.textContent = status.problem ? "Needs attention" : status.busy ? "Working…" : ready ? "Syncing" : "Set-up needed";

  $("problem").hidden = !status.problem;
  $("problem").textContent = status.problem || "";

  // 1. Discord
  $("discord-text").textContent = status.signedIn ? "You are signed in. " + (status.visibility === "private" ? "You are kept off the ladder." : "You are listed on the ladder.") : "Sign in so your cards and rank belong to you.";
  $("visibility").hidden = status.signedIn;
  $("discord-note").hidden = status.signedIn;
  $("sign-in").hidden = status.signedIn;
  $("sign-out").hidden = !status.signedIn;
  $("sign-in").disabled = status.busy || status.problem !== null;

  // 2. Game folder
  const folder = $("folder-path");
  folder.textContent = status.gameFolder || "Not chosen yet";
  folder.classList.toggle("empty", !status.gameFolder);

  // 3. Syncing
  const list = $("accounts");
  list.replaceChildren();
  for (const entry of status.accounts) {
    const item = document.createElement("li");
    const left = document.createElement("span");
    const name = document.createElement("span");
    name.className = "name";
    name.textContent = entry.account;
    const mode = document.createElement("span");
    mode.className = "mode" + (entry.mode === "ranked" ? " ranked" : "");
    mode.textContent = entry.mode === "ranked" ? "Ranked" : entry.mode === "casual" ? "Casual" : "?";
    left.append(name, mode);
    const state = document.createElement("span");
    state.className = "state" + (/^(Synced|Up to date)/.test(entry.state) ? " good" : /Cannot|refused|missing|Not registered/.test(entry.state) ? " bad" : "");
    state.textContent = entry.state;
    item.append(left, state);
    list.append(item);
  }
  $("sync-empty").hidden = status.accounts.length > 0;
  $("facts").hidden = status.lastSyncAt === null;
  $("last-sync").textContent = ago(status.lastSyncAt);
  $("standings").textContent = status.standings === "fresh" ? "Up to date" : status.standings === "kept" ? "Recent" : "Not available";
  $("tape").textContent = status.tapeEntries === null ? "Not needed (Casual)" : status.tapeEntries + " entries ready";
  $("sync-now").disabled = !ready || status.busy;

  const message = $("message");
  message.hidden = !status.message;
  message.textContent = status.message || "";
  $("start-at-login").checked = status.startAtLogin;
  $("version").textContent = "Version " + status.version;
}

const demo = /^#demo-(\w+)$/.exec(location.hash);
if (demo && demos[demo[1]]) {
  render(demos[demo[1]]);
} else {
  const api = window.warcards;
  $("sign-in").addEventListener("click", () => {
    const chosen = document.querySelector('input[name="visibility"]:checked');
    api.signIn(chosen && chosen.value === "private" ? "private" : "public");
  });
  $("sign-out").addEventListener("click", () => api.signOut());
  $("find-game").addEventListener("click", () => api.findGame());
  $("choose-folder").addEventListener("click", () => api.chooseGameFolder());
  $("sync-now").addEventListener("click", () => api.syncNow());
  $("start-at-login").addEventListener("change", (event) => api.setStartAtLogin(event.target.checked));
  api.onStatus(render);
  api.status().then(render);
  // "5 min ago" should keep ticking even when nothing else changes.
  setInterval(() => api.status().then(render), 30000);
}
