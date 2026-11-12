// The review page for the people who run the service: the open flags (players the checks held back for a look), the reports
// about each player, and the decisions: clear a flag, confirm it, ban or unban. It is a thin screen over the admin API
// (docs/API.md, "Admin routes"): the page itself holds no data and no secret, so anyone may load it, and nothing works until
// the admin token is typed in. The token lives in the page's memory only (never in the address, a cookie or browser storage) and
// is sent as the Authorization header; closing the tab forgets it.
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
button{cursor:pointer;background:#33271a}
button:hover{background:#4a3722}
button.danger{border-color:#8a4a3a;background:#3a1f19}
button[disabled]{opacity:.5;cursor:default}
.card{border:1px solid #3d3226;border-radius:6px;padding:12px 14px;margin:0 0 12px;background:#1a1816}
.card h2{font-size:16px;margin:0 0 2px}
.meta{color:#a39b8b;font-size:13px;margin:0 0 8px}
.notes{white-space:pre-wrap;word-break:break-word;background:#11100f;border-radius:4px;padding:8px;margin:0 0 8px;font:13px/1.4 ui-monospace,Consolas,monospace}
.tag{display:inline-block;border:1px solid #5a4a36;border-radius:10px;padding:0 8px;font-size:12px;margin-left:6px}
.tag.open{border-color:#b9893c;color:#e0b066}.tag.confirmed{border-color:#8a4a3a;color:#e8a090}.tag.cleared{border-color:#4a6a4a;color:#a6c4ab}
.row{display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start}
.row textarea{flex:1 1 260px;min-height:38px}
.reports{margin:8px 0 0;padding-left:18px;color:#cfc8b8}
#message{min-height:1.4em}#message.bad{color:#e8a090}#message.good{color:#a6c4ab}
.empty{color:#a39b8b;padding:24px 0}
`;

// The page's only script. Plain browser JavaScript, no libraries; every value from the server goes through textContent.
export const ADMIN_SCRIPT = `
(function () {
  "use strict";
  var token = "";
  var $ = function (id) { return document.getElementById(id); };
  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function say(text, kind) { var m = $("message"); m.textContent = text || ""; m.className = kind || ""; }
  function when(seconds) { return seconds ? new Date(seconds * 1000).toISOString().replace("T", " ").replace(/\\.\\d+Z$/, " UTC") : "-"; }

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

  async function showReports(flag, into, button) {
    button.disabled = true;
    try {
      var body = await api("/v1/admin/reports?player=" + encodeURIComponent(flag.playerId) + "&limit=50");
      into.replaceChildren();
      if (!body.reports.length) { into.appendChild(el("li", "", "No reports about this player.")); return; }
      body.reports.forEach(function (report) {
        into.appendChild(el("li", "", when(report.createdAt) + " - " + report.reason + " - about " + report.targetName + (report.note ? ": " + report.note : "")));
      });
    } catch (error) {
      into.replaceChildren(el("li", "", "Could not load the reports: " + error.message));
    } finally { button.disabled = false; }
  }

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
      var banButton = el("button", "danger", "Ban");
      var unbanButton = el("button", "", "Unban");
      var decisionButtons = [clear, confirm];
      clear.addEventListener("click", function () { decide(flag, "cleared", noteBox, card, decisionButtons); });
      confirm.addEventListener("click", function () { decide(flag, "confirmed", noteBox, card, decisionButtons); });
      showReportsButton.addEventListener("click", function () { showReports(flag, reports, showReportsButton); });
      banButton.addEventListener("click", function () { ban(flag, true); });
      unbanButton.addEventListener("click", function () { ban(flag, false); });
      if (flag.state === "open") { row.appendChild(noteBox); row.appendChild(clear); row.appendChild(confirm); }
      row.appendChild(showReportsButton); row.appendChild(banButton); row.appendChild(unbanButton);
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
      say(body.flags.length + (body.flags.length === 1 ? " flag." : " flags."), "good");
    } catch (error) {
      $("flags").replaceChildren();
      say(error.code === "unauthorized" ? "That token is not right." : "Could not load: " + error.message, "bad");
    }
  }

  $("signin").addEventListener("submit", function (event) {
    event.preventDefault();
    token = $("token").value.trim();
    $("token").value = "";
    if (token) load();
  });
  $("state").addEventListener("change", function () { if (token) load(); });
  $("refresh").addEventListener("click", function () { if (token) load(); });
})();
`;

export const ADMIN_HTML = (): string => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow">
<title>Review - World of Warcards</title><style>${STYLE}</style></head>
<body><main>
<h1>Review</h1>
<p class="lede">Flags and reports for the people who run World of Warcards. Nothing loads until you enter the admin token; it is kept only in this tab.</p>
<form id="signin" class="bar" autocomplete="off">
<input id="token" type="password" placeholder="Admin token" aria-label="Admin token" autocomplete="off">
<button type="submit">Load flags</button>
<select id="state" aria-label="Which flags"><option value="open">Open</option><option value="cleared">Cleared</option><option value="confirmed">Confirmed</option><option value="all">All</option></select>
<button type="button" id="refresh">Refresh</button>
</form>
<p id="message" role="status"></p>
<div id="flags"></div>
</main>
<script>${ADMIN_SCRIPT}</script></body></html>`;

// base64 of the script's SHA-256, for the content security policy (the page may run this script and no other).
export async function scriptHash(): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ADMIN_SCRIPT)));
  let binary = "";
  for (const byte of digest) binary += String.fromCharCode(byte);
  return btoa(binary);
}
