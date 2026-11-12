"use strict";
// Draws the status the controller reports, and passes the buttons on. All text from the app is put on the page as text
// (never as HTML), so nothing it says, including a name from a saved file, can ever act as markup or script.

const $ = (id) => document.getElementById(id);

// With "#demo-<name>" in the address (used only to take pictures of each screen) the page shows a made-up status.
const demos = {
  newbinder: {
    version: "0.1.0", server: "", problem: null, signedIn: true, visibility: "public", startAtLogin: false, gameFolder: "D:\\Games\\World of Warcraft Forever",
    accounts: [{ account: "Main account", mode: "casual", state: "This is a new binder: it does not continue the one the server has" }],
    lastSyncAt: Math.floor(Date.now() / 1000) - 20, tapeEntries: null, standings: "fresh", message: null, busy: false, needsNewBinder: true,
  },
  setup: { version: "0.1.0", server: "", problem: null, signedIn: false, visibility: "public", startAtLogin: false, gameFolder: null, accounts: [], lastSyncAt: null, tapeEntries: null, standings: null, message: null, busy: false, needsNewBinder: false },
  syncing: {
    version: "0.1.0", server: "", problem: null, signedIn: true, visibility: "public", startAtLogin: true, gameFolder: "D:\\Games\\World of Warcraft Forever",
    accounts: [{ account: "Main account", mode: "ranked", state: "Synced (42 new events)" }, { account: "Second account", mode: "casual", state: "Up to date" }],
    lastSyncAt: Math.floor(Date.now() / 1000) - 95, tapeEntries: 1000, standings: "fresh", message: null, busy: false, needsNewBinder: false,
  },
  problem: {
    version: "0.1.0", server: "", problem: "Your key cannot be stored safely on this computer. The app cannot sign in or upload until that is fixed.",
    signedIn: false, visibility: "public", startAtLogin: false, gameFolder: null, accounts: [], lastSyncAt: null, tapeEntries: null, standings: null, message: null, busy: false, needsNewBinder: false,
  },
};

function ago(seconds) {
  if (seconds === null) return "–";
  const gap = Math.max(0, Math.floor(Date.now() / 1000) - seconds);
  if (gap < 60) return "just now";
  if (gap < 3600) return Math.floor(gap / 60) + " min ago";
  return Math.floor(gap / 3600) + " h ago";
}

// What to tell the player about versions: the add-on first, since it decides whether their cards count, then the app.
function updateNote(updates) {
  if (!updates) return "";
  const addon = updates.addon, app = updates.app;
  if (addon.installed === null) return "The add-on was not found in the game folder. Install it, then use /reload in the game.";
  if (addon.rankedPaused) return "The add-on (" + addon.installed + ") is too old for Ranked: no new roll tape will be given until you update to " + addon.latest + ". Casual still works.";
  if (addon.state === "required") return "The add-on (" + addon.installed + ") is too old. Update to " + addon.latest + " so your Ranked cards keep counting.";
  if (addon.reloadNeeded) return "The add-on was updated to " + addon.installed + ". Use /reload in the game, or restart it, to start using it.";
  if (addon.state === "update") return "Add-on " + addon.latest + " is available (you have " + addon.installed + "). Update it from the Download page, then use /reload in the game.";
  if (app.state === "required") return "This companion (" + app.version + ") is too old. Install " + app.latest + " to keep syncing.";
  if (app.state === "update") return "Companion " + app.latest + " is available (you have " + app.version + ").";
  return "";
}

function render(status) {
  const ready = status.signedIn && status.gameFolder !== null;
  const accountIssues = status.accounts.some((entry) => /Cannot|refused|missing|Not registered|could not be reached/.test(entry.state));
  const attention = status.problem || status.needsNewBinder || accountIssues;
  const synced = ready && status.lastSyncAt !== null && status.accounts.length > 0 && !attention;
  const pill = $("pill");
  pill.className = "pill " + (status.problem ? "bad" : attention || status.busy || !synced ? "warn" : "ok");
  pill.textContent = attention ? "Needs attention" : status.busy ? "Working…" : synced ? "Up to date" : ready ? "Ready to sync" : "Setup needed";
  $("overview-title").textContent = attention ? "Your connection needs attention." : status.busy ? "Updating your companion." : synced ? "Your binder is up to date." : ready ? "Ready for your first sync." : "Set up your companion.";
  $("overview-description").textContent = attention ? "Review the message below to continue syncing your collection."
    : synced ? "Your latest saved collection has been synced."
    : ready ? "Play with the addon enabled, then reload or leave the game to save your cards."
    : "Connect your account and game to sync your binder.";
  const complete = Number(status.signedIn) + Number(status.gameFolder !== null);
  $("setup-count").textContent = complete === 2 ? status.accounts.length + (status.accounts.length === 1 ? " binder found" : " binders found") : complete + " of 2 steps complete";

  $("problem").hidden = !status.problem;
  $("problem").textContent = status.problem || "";

  $("export-data").hidden = !status.signedIn;
  $("export-data").disabled = status.busy;
  $("delete-data").hidden = !status.signedIn;
  $("delete-data").disabled = status.busy;
  $("new-binder").hidden = !status.needsNewBinder;
  $("new-binder-button").disabled = status.busy;
  $("discord-state").textContent = status.signedIn ? "Signed in" : "Sign-in needed";
  $("discord-state").classList.toggle("complete", status.signedIn);

  // 1. Discord
  $("discord-text").textContent = status.signedIn ? "You are signed in. " + (status.visibility === "private" ? "You are kept off the ladder." : "You are listed on the ladder.") : "Sign in so your cards and rank belong to you.";
  $("visibility").hidden = status.signedIn;
  $("discord-note").hidden = status.signedIn;
  $("sign-in").hidden = status.signedIn;
  $("sign-out").hidden = !status.signedIn;
  $("sign-in").disabled = status.busy || status.problem !== null;
  $("sign-out").disabled = status.busy;

  // 2. Game folder
  const folder = $("folder-path");
  folder.textContent = status.gameFolder || "Game folder hasn't been selected";
  folder.classList.toggle("empty", !status.gameFolder);
  $("folder-state").textContent = status.gameFolder ? "Folder selected" : "Choose a folder";
  $("folder-state").classList.toggle("complete", !!status.gameFolder);
  $("find-game").disabled = status.busy;
  $("choose-folder").disabled = status.busy;

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
    state.className = "state" + (/^(Synced|Up to date)/.test(entry.state) ? " good" : /Cannot|refused|missing|Not registered|could not be reached/.test(entry.state) ? " bad" : "");
    state.textContent = entry.state.replace(/^Synced \((\d+) new events\)$/, "$1 updates synced");
    item.append(left, state);
    list.append(item);
  }
  $("sync-empty").hidden = status.accounts.length > 0;
  $("empty-title").textContent = ready ? "Waiting for your saved binder" : "Connect your binder";
  $("empty-description").textContent = ready ? "Enable the addon, then reload or leave the game. Your saved collection will appear here." : "Connect your account and choose your game folder to get started.";
  $("sync-state").textContent = attention ? "Check connection" : status.busy ? "Working" : synced ? "Up to date" : ready ? "Ready" : "Waiting";
  $("sync-state").classList.toggle("complete", synced && !status.busy);
  $("facts").hidden = status.lastSyncAt === null;
  $("last-sync").textContent = ago(status.lastSyncAt);
  $("standings").textContent = status.standings === "fresh" ? "Up to date" : status.standings === "kept" ? "Recent" : "Not available";
  const updates = status.updates || null;
  $("addon-version").textContent = !updates ? "–" : updates.addon.installed === null ? "Not found"
    : updates.addon.installed + (updates.addon.state === "required" ? " (too old)" : updates.addon.state === "update" ? " (update available)" : "");
  const note = updateNote(updates);
  $("update-note").hidden = !note;
  $("update-note").textContent = note;
  const can = status.canUpdate || { addon: false, app: false };
  $("update-actions").hidden = !(can.addon || can.app);
  $("update-addon").hidden = !can.addon;
  $("update-app").hidden = !can.app;
  $("update-addon").disabled = $("update-app").disabled = !!status.updating || status.busy;
  $("update-addon").textContent = status.updating === "addon" ? "Updating…" : "Update add-on" + (status.newer && status.newer.addon ? " to " + status.newer.addon : "");
  $("update-app").textContent = status.updating === "app" ? "Updating…" : "Update companion" + (status.newer && status.newer.app ? " to " + status.newer.app : "");
  $("sync-now").disabled = !ready || status.busy || !!status.problem || status.needsNewBinder;

  const message = $("message");
  message.hidden = !status.message;
  message.textContent = status.message || "";
  $("start-at-login").checked = status.startAtLogin;
  $("start-at-login").disabled = status.busy;
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
  $("update-addon").addEventListener("click", () => api.updateAddon());
  $("update-app").addEventListener("click", () => api.updateApp());
  $("new-binder-button").addEventListener("click", () => api.startNewBinder());
  $("export-data").addEventListener("click", () => api.exportMyData());
  $("delete-data").addEventListener("click", () => api.deleteMyData());
  $("start-at-login").addEventListener("change", (event) => api.setStartAtLogin(event.target.checked));
  api.onStatus(render);
  api.status().then(render);
  // "5 min ago" should keep ticking even when nothing else changes.
  setInterval(() => api.status().then(render), 30000);
}
