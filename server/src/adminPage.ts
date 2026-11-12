// The admin panel for the people who run the service: the open flags (players the checks held back for a look) and the decisions on
// them, a way to find any player and see what is held about them (with ban, unban and delete), and the record of what reviewers
// did. It is a thin screen over the admin API (docs/API.md, "Admin routes"): the page itself holds no data and no secret, so anyone
// may load it, and nothing works until the admin token is typed in (and, when Cloudflare Access is set up, the visitor has signed
// in through it: docs/runbooks/ADMIN.md). The token lives in the page's memory only (never in the address, a cookie or browser
// storage) and is sent as the Authorization header; closing the tab forgets it.
//
// Everything that comes back from the server is put on the screen as text, never as markup, and the page may run only the one
// script below (its hash is in the content security policy).

const STYLE = `
:root{color-scheme:dark}
body{margin:0;background:#141416;color:#e7e1d4;font:15px/1.5 system-ui,Segoe UI,sans-serif}
main{max-width:980px;margin:0 auto;padding:24px 16px 64px}
h1{font:600 22px Georgia,serif;margin:0 0 4px;color:#e0b066}
p.lede{margin:0 0 20px;color:#a39b8b}
.bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:16px}
input,select,textarea,button{font:inherit;color:inherit;background:#1f1d1a;border:1px solid #5a4a36;border-radius:4px;padding:7px 10px}
input[type=password]{min-width:260px}
input[type=search]{min-width:260px}
button{cursor:pointer;background:#33271a}
button:hover{background:#4a3722}
button.danger{border-color:#8a4a3a;background:#3a1f19}
button[disabled]{opacity:.5;cursor:default}
[hidden]{display:none!important}
.tabs{display:flex;gap:6px;margin:0 0 16px;border-bottom:1px solid #3d3226;padding-bottom:8px}
.tab{background:#1f1d1a}.tab.on{background:#4a3722;border-color:#b9893c;color:#e0b066}
.who{color:#a39b8b;font-size:13px;margin:0 0 12px}
.card{border:1px solid #3d3226;border-radius:6px;padding:12px 14px;margin:0 0 12px;background:#1a1816}
.card h2{font-size:16px;margin:0 0 2px}
.meta{color:#a39b8b;font-size:13px;margin:0 0 6px;word-break:break-word}
.notes{white-space:pre-wrap;word-break:break-word;background:#11100f;border-radius:4px;padding:8px;margin:0 0 8px;font:13px/1.4 ui-monospace,Consolas,monospace}
.tag{display:inline-block;border:1px solid #5a4a36;border-radius:10px;padding:0 8px;font-size:12px;margin-left:6px}
.tag.open{border-color:#b9893c;color:#e0b066}.tag.confirmed{border-color:#8a4a3a;color:#e8a090}.tag.cleared{border-color:#4a6a4a;color:#a6c4ab}
.row{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start}
.row textarea{flex:1 1 260px;min-height:38px}
.reports{margin:8px 0 0;padding-left:18px;color:#cfc8b8}
.result{display:block;width:100%;text-align:left;margin:0 0 6px}
h3{font-size:14px;margin:12px 0 4px;color:#e0b066}
#message{min-height:1.4em}#message.bad{color:#e8a090}#message.good{color:#a6c4ab}
.empty{color:#a39b8b;padding:24px 0}
`;

// The page's only script. Plain browser JavaScript, no libraries; every value from the server goes through textContent.
export const ADMIN_SCRIPT = `
(function () {
  "use strict";
  var token = "";
  var views = ["flags", "players", "activity"];
  var $ = function (id) { return document.getElementById(id); };
  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function say(text, kind) { var m = $("message"); m.textContent = text || ""; m.className = kind || ""; }
  function when(seconds) { return seconds ? new Date(seconds * 1000).toISOString().replace("T", " ").slice(0, 19) + " UTC" : "-"; }
  function line(parent, label, value) { parent.appendChild(el("p", "meta", label + ": " + value)); }
  function plural(count, one, many) { return count + " " + (count === 1 ? one : many); }

  async function api(path, options) {
    var response = await fetch(path, Object.assign({ cache: "no-store", headers: { "authorization": "Bearer " + token, "content-type": "application/json" } }, options || {}));
    var body = {};
    try { body = await response.json(); } catch (e) { body = {}; }
    if (!response.ok) {
      var error = new Error((body.error && body.error.message) || ("The server answered " + response.status));
      error.code = body.error && body.error.code;
      throw error;
    }
    return body;
  }

  function show(name) {
    views.forEach(function (view) {
      $("view-" + view).hidden = view !== name;
      $("tab-" + view).className = view === name ? "tab on" : "tab";
    });
    if (name === "players" && !$("players").children.length) search();
    if (name === "activity") loadAudit();
  }

  async function showReports(playerId, into, button) {
    button.disabled = true;
    try {
      var body = await api("/v1/admin/reports?player=" + encodeURIComponent(playerId) + "&limit=50");
      into.replaceChildren();
      if (!body.reports.length) { into.appendChild(el("li", "", "No reports about this player.")); return; }
      body.reports.forEach(function (report) {
        into.appendChild(el("li", "", when(report.createdAt) + " - " + report.reason + " - about " + report.targetName + (report.note ? ": " + report.note : "")));
      });
    } catch (error) {
      into.replaceChildren(el("li", "", "Could not load the reports: " + error.message));
    } finally { button.disabled = false; }
  }

  // ---- Flags ----

  async function decide(flag, state, noteBox, card, buttons) {
    buttons.forEach(function (b) { b.disabled = true; });
    try {
      await api("/v1/admin/flags/" + encodeURIComponent(flag.id), { method: "POST", body: JSON.stringify({ state: state, note: noteBox.value.slice(0, 500) }) });
      say("Flag " + state + ".", "good");
      card.remove();
    } catch (error) {
      say("Could not save the decision: " + error.message, "bad");
      buttons.forEach(function (b) { b.disabled = false; });
    }
  }

  async function ban(flag, banned) {
    var question = banned ? "Ban " + flag.displayName + "? They will be hidden from the ladder and unable to upload." : "Lift the ban on " + flag.displayName + "?";
    if (!window.confirm(question)) return;
    try {
      await api("/v1/admin/players/" + encodeURIComponent(flag.playerId) + "/ban", { method: "POST", body: JSON.stringify({ banned: banned }) });
      say((banned ? "Banned " : "Unbanned ") + flag.displayName + ".", "good");
    } catch (error) { say("Could not change the ban: " + error.message, "bad"); }
  }

  function render(flags) {
    var list = $("flags");
    list.replaceChildren();
    if (!flags.length) { list.appendChild(el("p", "empty", "Nothing here.")); return; }
    flags.forEach(function (flag) {
      var card = el("section", "card");
      var title = el("h2", "", flag.displayName + " - " + flag.kind);
      title.appendChild(el("span", "tag " + flag.state, flag.state));
      card.appendChild(title);
      card.appendChild(el("p", "meta", "Flagged " + when(flag.createdAt) + (flag.reviewedAt ? " - reviewed " + when(flag.reviewedAt) : "") + " - player " + flag.playerId));
      if (flag.notes) card.appendChild(el("pre", "notes", flag.notes));
      if (flag.reviewNote) card.appendChild(el("p", "meta", "Review note: " + flag.reviewNote));
      var reports = el("ul", "reports");
      var row = el("div", "row");
      var noteBox = el("textarea"); noteBox.placeholder = "A note for the record (optional, up to 500 characters)"; noteBox.maxLength = 500;
      var clear = el("button", "", "Clear (back on the ladder)");
      var confirm = el("button", "danger", "Confirm (keep off)");
      var showReportsButton = el("button", "", "Reports about them");
      var playerButton = el("button", "", "Player page");
      var banButton = el("button", "danger", "Ban");
      var unbanButton = el("button", "", "Unban");
      var decisionButtons = [clear, confirm];
      clear.addEventListener("click", function () { decide(flag, "cleared", noteBox, card, decisionButtons); });
      confirm.addEventListener("click", function () { decide(flag, "confirmed", noteBox, card, decisionButtons); });
      showReportsButton.addEventListener("click", function () { showReports(flag.playerId, reports, showReportsButton); });
      playerButton.addEventListener("click", function () { show("players"); openPlayer(flag.playerId); });
      banButton.addEventListener("click", function () { ban(flag, true); });
      unbanButton.addEventListener("click", function () { ban(flag, false); });
      if (flag.state === "open") { row.appendChild(noteBox); row.appendChild(clear); row.appendChild(confirm); }
      row.appendChild(showReportsButton); row.appendChild(playerButton); row.appendChild(banButton); row.appendChild(unbanButton);
      card.appendChild(row);
      card.appendChild(reports);
      list.appendChild(card);
    });
  }

  async function load() {
    say("Loading...");
    try {
      var body = await api("/v1/admin/flags?state=" + encodeURIComponent($("state").value) + "&limit=200");
      render(body.flags);
      say(plural(body.flags.length, "flag", "flags") + ".", "good");
    } catch (error) {
      $("flags").replaceChildren();
      say(error.code === "unauthorized" ? "That is not accepted: the token is wrong, or you are not signed in through Cloudflare Access." : "Could not load: " + error.message, "bad");
    }
  }

  // ---- Players ----

  async function setBan(player, name, banned) {
    var reason = "";
    if (banned) {
      reason = window.prompt("Ban " + name + "? They will be hidden from the ladder and unable to upload. Why? (kept in the activity record)", "");
      if (reason === null) return;
    } else if (!window.confirm("Lift the ban on " + name + "?")) return;
    try {
      await api("/v1/admin/players/" + encodeURIComponent(player.playerId) + "/ban", { method: "POST", body: JSON.stringify({ banned: banned, reason: reason.slice(0, 200) }) });
      await openPlayer(player.playerId);
      say((banned ? "Banned " : "Unbanned ") + name + ".", "good");
    } catch (error) { say("Could not change the ban: " + error.message, "bad"); }
  }

  async function deletePlayer(player, name) {
    var typed = window.prompt("This permanently deletes everything held about " + name + " and cannot be undone (backups age out within 14 days). To go ahead, type their player id: " + player.playerId, "");
    if (typed === null) return;
    if (typed.trim() !== player.playerId) { say("Not deleted: that was not the player id.", "bad"); return; }
    try {
      await api("/v1/admin/players/" + encodeURIComponent(player.playerId) + "/delete", { method: "POST", body: JSON.stringify({ confirm: player.playerId }) });
      $("player").replaceChildren();
      await search();
      say("Deleted " + name + ".", "good");
    } catch (error) { say("Could not delete: " + error.message, "bad"); }
  }

  async function resetBinder(player, name) {
    var reason = window.prompt("Reset " + name + "'s binder? It is put aside, not deleted, and can be restored. They come off the ladder, and their old history is refused until they start a new binder. Why? (kept in the activity record; OK to go ahead, Cancel to stop)", "");
    if (reason === null) return;
    try {
      await api("/v1/admin/players/" + encodeURIComponent(player.playerId) + "/reset", { method: "POST", body: JSON.stringify({ confirm: player.playerId, reason: reason.slice(0, 200) }) });
      await openPlayer(player.playerId);
      say("Reset " + name + "'s binder. It is in their archived binders.", "good");
    } catch (error) { say("Could not reset the binder: " + error.message, "bad"); }
  }

  async function restoreBinder(player, name, archive) {
    var reason = window.prompt("Bring this binder back for " + name + "? Their current binder, if they have one, is put aside instead and can be restored in turn. Why? (kept in the activity record; OK to go ahead, Cancel to stop)", "");
    if (reason === null) return;
    try {
      await api("/v1/admin/players/" + encodeURIComponent(player.playerId) + "/restore", { method: "POST", body: JSON.stringify({ confirm: player.playerId, archiveId: archive.archiveId, reason: reason.slice(0, 200) }) });
      await openPlayer(player.playerId);
      say("Restored the binder for " + name + ".", "good");
    } catch (error) { say("Could not restore the binder: " + error.message, "bad"); }
  }

  async function openPlayer(id) {
    var box = $("player");
    box.replaceChildren();
    say("Loading the player...");
    var player;
    try { player = (await api("/v1/admin/players/" + encodeURIComponent(id))).player; }
    catch (error) { say("Could not load the player: " + error.message, "bad"); return; }
    var name = player.score ? player.score.displayName : (player.archives.length && player.archives[0].displayName) || "(no name yet)";
    var card = el("section", "card");
    var title = el("h2", "", name);
    title.appendChild(el("span", "tag " + (player.status === "banned" ? "confirmed" : "cleared"), player.status));
    card.appendChild(title);
    line(card, "Player id", player.playerId);
    line(card, "Joined", when(player.createdAt) + " - " + player.visibility + " - signed in with Discord: " + (player.hasDiscord ? "yes" : "no"));
    line(card, "Keys", player.keys.active + " active, " + player.keys.revoked + " revoked - binder restarts: " + player.epoch);
    card.appendChild(el("h3", "", "Characters"));
    if (!player.characters.length) line(card, "None", "no upload yet");
    player.characters.forEach(function (character) { card.appendChild(el("p", "meta", character.name + " (" + character.realm + ") - first seen " + when(character.firstSeen) + ", last " + when(character.lastSeen))); });
    card.appendChild(el("h3", "", "Score and binder"));
    if (player.score) line(card, "Score", (player.score.scoreTenths / 10).toFixed(1) + " points - " + plural(player.score.uniqueCards, "card", "cards") + ", " + plural(player.score.setsDone, "set", "sets") + ", " + plural(player.score.attempts, "attempt", "attempts") + " - rules version " + player.score.rulesVersion + ", updated " + when(player.score.updatedAt));
    if (player.binder) line(card, "Binder", player.binder.mode + " mode - " + plural(player.binder.cardsOwned, "card owned", "cards owned") + " - Casual drops: " + player.binder.casualDrops + " - last upload " + when(player.binder.updatedAt));
    card.appendChild(el("h3", "", "Archived binders"));
    if (!player.archives.length) line(card, "None", "no binder has been put aside");
    player.archives.forEach(function (archive) {
      var archiveRow = el("div", "row");
      archiveRow.appendChild(el("p", "meta", plural(archive.cardsOwned, "card", "cards") + ", " + plural(archive.batches, "upload", "uploads") + ", last " + when(archive.lastUpload) + (archive.scoreTenths !== null ? ", " + (archive.scoreTenths / 10).toFixed(1) + " points" : "") + " - epoch " + archive.epoch + " - " + archive.archiveId));
      var restoreButton = el("button", "", "Restore this binder...");
      restoreButton.addEventListener("click", function () { restoreBinder(player, name, archive); });
      archiveRow.appendChild(restoreButton);
      card.appendChild(archiveRow);
    });
    if (player.barredBefore) line(card, "Old history refused", "anything written before " + when(player.barredBefore) + " (cleared by a restore)");
    line(card, "Uploads", plural(player.uploads.batches, "batch", "batches") + (player.uploads.batches ? ", from " + when(player.uploads.first) + " to " + when(player.uploads.last) : ""));
    line(card, "Trades", player.trades.matched + " matched, " + player.trades.open + " open, " + player.trades.unmatched + " unmatched");
    card.appendChild(el("h3", "", "Flags and reports"));
    if (!player.flags.length) line(card, "Flags", "none");
    player.flags.forEach(function (flag) {
      card.appendChild(el("p", "meta", flag.kind + " - " + flag.state + " - " + when(flag.createdAt) + (flag.notes ? " - " + flag.notes : "") + (flag.reviewNote ? " - review note: " + flag.reviewNote : "")));
    });
    line(card, "Reports about them", String(player.reportsAbout));
    var reports = el("ul", "reports");
    var row = el("div", "row");
    var reportsButton = el("button", "", "Read the reports");
    var banButton = el("button", "danger", "Ban...");
    var unbanButton = el("button", "", "Unban");
    var resetButton = el("button", "danger", "Reset their binder...");
    var deleteButton = el("button", "danger", "Delete their data...");
    reportsButton.addEventListener("click", function () { showReports(player.playerId, reports, reportsButton); });
    banButton.addEventListener("click", function () { setBan(player, name, true); });
    unbanButton.addEventListener("click", function () { setBan(player, name, false); });
    resetButton.addEventListener("click", function () { resetBinder(player, name); });
    deleteButton.addEventListener("click", function () { deletePlayer(player, name); });
    row.appendChild(reportsButton);
    if (player.status === "banned") row.appendChild(unbanButton); else row.appendChild(banButton);
    if (player.binder) row.appendChild(resetButton);
    row.appendChild(deleteButton);
    card.appendChild(row);
    card.appendChild(reports);
    box.appendChild(card);
    say("", "");
  }

  async function search() {
    say("Searching...");
    try {
      var body = await api("/v1/admin/players?limit=25&q=" + encodeURIComponent($("query").value.trim()));
      var list = $("players");
      list.replaceChildren();
      if (!body.players.length) list.appendChild(el("p", "empty", "No players match."));
      body.players.forEach(function (found) {
        var text = (found.displayName || "(no name yet)") + " - " + (found.characters.length ? found.characters.join(", ") : "no character") + " - " + found.visibility + (found.status === "banned" ? " - BANNED" : "");
        var button = el("button", "result", text);
        button.addEventListener("click", function () { openPlayer(found.playerId); });
        list.appendChild(button);
      });
      say(plural(body.players.length, "player", "players") + (body.players.length === 25 ? " (the first 25: narrow the search)." : "."), "good");
    } catch (error) { say("Could not search: " + error.message, "bad"); }
  }

  // ---- Activity ----

  async function loadAudit() {
    try {
      var body = await api("/v1/admin/audit?limit=100");
      var list = $("audit");
      list.replaceChildren();
      if (!body.entries.length) list.appendChild(el("p", "empty", "Nothing has been done in the panel yet."));
      body.entries.forEach(function (entry) {
        var row = el("div", "row");
        row.appendChild(el("p", "meta", when(entry.at) + " - " + entry.actor + " - " + entry.action + (entry.target ? " - " + entry.target : "") + (entry.detail ? ": " + entry.detail : "")));
        if (entry.target.length === 26 && entry.action !== "delete-player") {
          var open = el("button", "", "Player page");
          open.addEventListener("click", function () { show("players"); openPlayer(entry.target); });
          row.appendChild(open);
        }
        list.appendChild(row);
      });
    } catch (error) { say("Could not load the activity: " + error.message, "bad"); }
  }

  // ---- Signing in ----

  $("signin").addEventListener("submit", async function (event) {
    event.preventDefault();
    token = $("token").value.trim();
    $("token").value = "";
    if (!token) return;
    try {
      var me = await api("/v1/admin/me");
      $("who").textContent = "Signed in as " + me.actor + (me.access ? " (Cloudflare Access)" : " (admin token only)");
      $("app").hidden = false;
    } catch (error) {
      $("app").hidden = true;
      $("flags").replaceChildren();
      say(error.code === "unauthorized" ? "That is not accepted: the token is wrong, or you are not signed in through Cloudflare Access." : "Could not sign in: " + error.message, "bad");
      return;
    }
    show("flags");
    load();
  });
  views.forEach(function (view) { $("tab-" + view).addEventListener("click", function () { show(view); }); });
  $("state").addEventListener("change", function () { if (token) load(); });
  $("refresh").addEventListener("click", function () { if (token) load(); });
  $("find").addEventListener("submit", function (event) { event.preventDefault(); if (token) search(); });
  $("refresh-activity").addEventListener("click", function () { if (token) loadAudit(); });
})();
`;

export const ADMIN_HTML = (): string => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow">
<title>Admin - World of Warcards</title><style>${STYLE}</style></head>
<body><main>
<h1>Admin</h1>
<p class="lede">Flags, players and activity for the people who run World of Warcards. Nothing loads until you enter the admin token; it is kept only in this tab.</p>
<form id="signin" class="bar" autocomplete="off">
<input id="token" type="password" placeholder="Admin token" aria-label="Admin token" autocomplete="off">
<button type="submit">Sign in</button>
</form>
<p id="message" role="status"></p>
<div id="app" hidden>
<p id="who" class="who"></p>
<div class="tabs"><button type="button" id="tab-flags" class="tab on">Flags</button><button type="button" id="tab-players" class="tab">Players</button><button type="button" id="tab-activity" class="tab">Activity</button></div>
<section id="view-flags">
<div class="bar"><select id="state" aria-label="Which flags"><option value="open">Open</option><option value="cleared">Cleared</option><option value="confirmed">Confirmed</option><option value="all">All</option></select><button type="button" id="refresh">Refresh</button></div>
<div id="flags"></div>
</section>
<section id="view-players" hidden>
<form id="find" class="bar" autocomplete="off"><input id="query" type="search" placeholder="Name, character or player id" aria-label="Find a player" maxlength="64"><button type="submit">Search</button></form>
<div id="players"></div>
<div id="player"></div>
</section>
<section id="view-activity" hidden>
<div class="bar"><button type="button" id="refresh-activity">Refresh</button></div>
<div id="audit"></div>
</section>
</div>
</main>
<script>${ADMIN_SCRIPT}</script></body></html>`;

// base64 of the script's SHA-256, for the content security policy (the page may run this script and no other).
export async function scriptHash(): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ADMIN_SCRIPT)));
  let binary = "";
  for (const byte of digest) binary += String.fromCharCode(byte);
  return btoa(binary);
}
