// The public website (roadmap B8): the ladder, a player's page with a read-only view of their binder, the fair-play rules and
// the privacy page. Plain HTML made on the server from the same data as the API, with no scripts, no outside resources and
// no game art (card names and numbers only, as the policy notes require). Every piece of text that came from a player or the
// data is escaped before it goes into a page.
import type { Catalog } from "./shared.ts";

const ESCAPES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
export const escapeHtml = (value: unknown): string => String(value).replace(/[&<>"']/g, (character) => ESCAPES[character] as string);

const STYLE = `
:root{--bg:#16110d;--panel:#211812;--edge:#4d3a22;--brass:#e0b066;--ink:#ecdcb4;--muted:#a89a7e;--green:#7fd18a}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.55 "Segoe UI",system-ui,sans-serif}
a{color:var(--brass)}
a:focus-visible,summary:focus-visible{outline:2px solid var(--brass);outline-offset:2px}
header,main,footer{max-width:960px;margin:0 auto;padding:0 16px}
header{display:flex;flex-wrap:wrap;align-items:center;gap:8px 24px;padding-top:20px;padding-bottom:12px;border-bottom:1px solid var(--edge)}
header .brand{font:26px Georgia,"Times New Roman",serif;color:var(--brass);text-decoration:none}
nav{display:flex;gap:16px;margin-left:auto}
h1,h2,h3{font-family:Georgia,"Times New Roman",serif;font-weight:normal;color:var(--brass)}
h1{font-size:30px;margin:28px 0 6px}
h2{font-size:22px;margin:28px 0 8px}
p,li{max-width:70ch}
.lede{color:var(--muted)}
table{width:100%;border-collapse:collapse;margin:12px 0;background:var(--panel);border:1px solid var(--edge)}
th,td{padding:8px 12px;text-align:left;border-bottom:1px solid var(--edge)}
th{color:var(--muted);font-weight:normal;font-size:13px;text-transform:uppercase;letter-spacing:1px}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
.panel{background:var(--panel);border:1px solid var(--edge);padding:12px 16px;margin:12px 0}
.stats{display:flex;flex-wrap:wrap;gap:12px;margin:16px 0}
.stats div{flex:1 1 140px;background:var(--panel);border:1px solid var(--edge);padding:10px 14px}
.stats dt{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:1px}
.stats dd{margin:2px 0 0;font-size:24px}
details{background:var(--panel);border:1px solid var(--edge);margin:8px 0;padding:8px 14px}
summary{cursor:pointer}
details ul{columns:2 240px;margin:8px 0 4px;padding-left:20px}
.common{color:#fff}.rare{color:#4aa3ff}.epic{color:#b57bff}.legendary{color:#ff9a2e}
.shiny::after{content:" (shiny)";color:#8fe3ff;font-size:13px}
.copies{color:var(--muted);font-size:13px}
footer{margin-top:40px;padding-top:16px;padding-bottom:32px;border-top:1px solid var(--edge);color:var(--muted);font-size:13px}
.empty{color:var(--muted)}
@media (max-width:560px){th:nth-child(4),td:nth-child(4),th:nth-child(5),td:nth-child(5){display:none}}
`;

export function layout(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="A card collecting ladder for World of Warcraft: Forever.">
<style>${STYLE}</style>
</head>
<body>
<header>
<a class="brand" href="/">World of Warcards</a>
<nav aria-label="Main"><a href="/">Ladder</a><a href="/fair-play">Fair play</a><a href="/privacy">Privacy</a></nav>
</header>
<main>
${body}
</main>
<footer>
<p>World of Warcards is a fan project. It is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment. Card names are shown as text; no game art is used on this site.</p>
</footer>
</body>
</html>
`;
}

const date = (seconds: number): string => new Date(seconds * 1000).toISOString().slice(0, 10);

export type LadderEntry = { rank: number; playerId: string; displayName: string; scoreTenths: number; uniqueCards: number; setsDone: number };
export type First = { title: string; displayName: string; playerId: string; at: number };

export function homePage(entries: LadderEntry[], firsts: First[]): string {
  const rows = entries.map((entry) =>
    `<tr><td class="num">${entry.rank}</td><td><a href="/player/${escapeHtml(entry.playerId)}">${escapeHtml(entry.displayName)}</a></td><td class="num">${(entry.scoreTenths / 10).toFixed(1)}</td><td class="num">${entry.uniqueCards}</td><td class="num">${entry.setsDone}</td></tr>`).join("\n");
  const table = entries.length > 0
    ? `<table><caption class="empty">The top ${entries.length} ranked players</caption>\n<thead><tr><th class="num">#</th><th>Player</th><th class="num">Points</th><th class="num">Cards</th><th class="num">Sets</th></tr></thead>\n<tbody>\n${rows}\n</tbody></table>`
    : `<p class="panel empty">Nobody is on the ladder yet. Only players whose every drop was rolled in Ranked mode are listed.</p>`;
  const first = firsts.length > 0
    ? `<ul>${firsts.map((row) => `<li><strong>${escapeHtml(row.title)}</strong>: <a href="/player/${escapeHtml(row.playerId)}">${escapeHtml(row.displayName)}</a> <span class="copies">${date(row.at)}</span></li>`).join("")}</ul>`
    : `<p class="empty">No set has been finished yet.</p>`;
  return layout("World of Warcards: the ladder", `
<h1>The ladder</h1>
<p class="lede">Collect a card for every creature and node in the world. Only <a href="/fair-play">Ranked</a> play counts, so every drop on this page was checked by the server.</p>
${table}
<h2>First to finish a set</h2>
${first}
`);
}

export type BinderSet = { title: string; owned: number; total: number; cards: { name: string; rarity: string; copies: number; shiny: boolean }[] };

export function playerPage(player: { displayName: string; rank: number; scoreTenths: number; uniqueCards: number; setsDone: number; updatedAt: number }, sets: BinderSet[]): string {
  const stats = `<dl class="stats"><div><dt>Rank</dt><dd>#${player.rank}</dd></div><div><dt>Points</dt><dd>${(player.scoreTenths / 10).toFixed(1)}</dd></div><div><dt>Cards</dt><dd>${player.uniqueCards}</dd></div><div><dt>Sets finished</dt><dd>${player.setsDone}</dd></div></dl>`;
  const list = sets.length > 0
    ? sets.map((set) => `<details><summary>${escapeHtml(set.title)}: ${set.owned} of ${set.total}</summary><ul>${set.cards.map((card) =>
        `<li class="${["common", "rare", "epic", "legendary"].includes(card.rarity) ? card.rarity : "common"}${card.shiny ? " shiny" : ""}">${escapeHtml(card.name)}${card.copies > 1 ? ` <span class="copies">x${card.copies}</span>` : ""}</li>`).join("")}</ul></details>`).join("\n")
    : `<p class="empty">No cards yet.</p>`;
  return layout(`${player.displayName} on World of Warcards`, `
<h1>${escapeHtml(player.displayName)}</h1>
<p class="lede">Last updated ${date(player.updatedAt)}. This is a read-only view of the binder the server has on record.</p>
${stats}
<h2>Binder</h2>
${list}
<p><a href="/">Back to the ladder</a></p>
`);
}

// The sets a binder has started, most complete first, with the cards owned in each (names and counts only).
export function binderSets(catalog: Catalog, counts: Record<string, number>, shiny: Record<string, boolean>): BinderSet[] {
  const sets: BinderSet[] = [];
  for (const set of catalog.sets) {
    const cards = set.cards.flatMap((key) => {
      const card = catalog.cards[key];
      const copies = counts[key] ?? 0;
      return card && copies > 0 ? [{ name: card.name, rarity: card.rarity, copies, shiny: shiny[key] === true }] : [];
    });
    if (cards.length > 0) sets.push({ title: set.title, owned: cards.length, total: set.cards.length, cards });
  }
  return sets.sort((a, b) => b.owned / b.total - a.owned / a.total || b.owned - a.owned || a.title.localeCompare(b.title));
}

export const fairPlayHeadings = ["How Ranked works", "What the server checks", "What happens when something looks wrong", "What this cannot promise", "Trading", "Starting over"] as const;

export function fairPlayPage(): string {
  return layout("Fair play: World of Warcards", `
<h1>Fair play</h1>
<p class="lede">A card collecting ladder only means something if the numbers can be trusted. Here is how that is attempted, and where it stops.</p>

<h2>How Ranked works</h2>
<p>Only <strong>Ranked</strong> play counts for the ladder. In Casual mode the game uses your own computer's random numbers, which nobody else can check, so a player with even one Casual drop is not listed. In Ranked mode the server issues the random numbers, and the add-on uses them in order, one for every attempt, win or lose. The server can therefore recompute every drop you claim.</p>
<p>Every card found, crafted, recycled or traded is written to an append-only history, chained together so that no entry can be changed or removed after the server has seen it.</p>

<h2>What the server checks</h2>
<ul>
<li><strong>The chain:</strong> any broken link rejects the upload. No gaps, no repeats.</li>
<li><strong>The rules:</strong> the history must describe a binder that can exist (for example, dust paid for a craft must match, and a set can only be finished once every card is held).</li>
<li><strong>The random numbers:</strong> every Ranked drop must match the number the server issued for it, in order, and be affordable in attempts.</li>
<li><strong>Luck:</strong> the chance of seeing as many drops as you did from as many attempts as you made. Very unlikely results are looked at by a person.</li>
<li><strong>Pace:</strong> attempts faster than a person could plausibly play, and very large collections from brand new accounts, are looked at.</li>
</ul>

<h2>What happens when something looks wrong</h2>
<p>Most checks raise a <em>flag</em> rather than refusing anything. A person reviews flags. The most serious one hides a player from the ladder until it has been reviewed, and nothing is deleted. A reviewer can clear a flag (you were just lucky) or confirm it. Luck that has been cleared is not flagged again until it becomes far more extreme. An appeals contact will be published before any prizes are given.</p>

<h2>What this cannot promise</h2>
<p>A game add-on runs on your computer and its saved data is a text file you can edit. The server never sees the game, only what the app says. Cheating cannot be made impossible, only bounded, visible and not worth it. A person who modifies the add-on can still read ahead in their random numbers, but skipped numbers have to be explained by plausible attempts, and attempts are limited to what a person could do in an hour. Their advantage is bounded, not zero. Seasons and human review exist for that reason.</p>

<h2>Trading</h2>
<p>A trade has two halves, one from each player, and both must agree. A half that nobody confirms within a week stops counting. A card that came from a player with Casual drops, directly or through other players, does not count for whoever received it.</p>

<h2>Starting over</h2>
<p>A new binder can be started once a day. The old one stays on record, stops counting, and the new one gets new random numbers from its first drop.</p>
`);
}

export const privacyHeadings = ["What is stored", "What is shown to others", "What is not collected", "Your choices", "Technical logs", "Where it lives"] as const;

export function privacyPage(): string {
  return layout("Privacy: World of Warcards", `
<h1>Privacy</h1>
<p class="lede">What the service holds about you, what other people see, and how to remove it.</p>

<h2>What is stored</h2>
<ul>
<li><strong>Your Discord id</strong>, and nothing else from Discord: not your name, avatar, email or servers. Signing in asks for the identify permission only, and the one-time token is thrown away straight away.</li>
<li><strong>A public key</strong> made on your computer. The matching private key never leaves it.</li>
<li><strong>Your characters' names and realms</strong>, taken from your history.</li>
<li><strong>Your history</strong>: every card found, crafted, recycled and traded, with times, the trade partner's character name and the trade id.</li>
<li><strong>Your score</strong> and when it last changed.</li>
<li><strong>Counts the server needs to check play</strong>: attempts per card, random-number positions used, and any fair-play flags with a reviewer's note.</li>
</ul>

<h2>What is shown to others</h2>
<p>Only if you chose <strong>public</strong> when you signed up: your character name and realm, your rank and score, your sets finished and the cards in your binder, on this site and with a "verified" mark beside your name in the game. A <strong>private</strong> player is stored but never listed.</p>

<h2>What is not collected</h2>
<p>Nothing about what is on your screen, in the game's memory or in your chat. The companion app reads one file the game writes and writes one file the add-on reads. It does not touch the game process or its network traffic.</p>

<h2>Your choices</h2>
<ul>
<li>Choose public or private when you sign up, and change it by signing in again.</li>
<li>Delete your data from the server at any time with <strong>Delete my data</strong> in the companion app. Your record, history, characters, Discord link and any archived binders are erased and cannot be recovered. Your cards in the game and the files on your computer are not touched. You can sign up again later, from nothing.</li>
<li>A banned account's record is kept, so that a ban cannot be undone by deleting the account.</li>
</ul>

<h2>Technical logs</h2>
<p>The server keeps a log of each request (the route, the result and how long it took, with a request id) so that problems can be found. It does not log your Discord id, your cards or what you uploaded. Cloudflare, which runs the server, also keeps its own technical logs, which include the address a request came from, for a limited time.</p>

<h2>Where it lives</h2>
<p>On Cloudflare (Workers and D1). Secrets are kept as Worker secrets, never in the project's code.</p>
`);
}

export function notFoundPage(): string {
  return layout("Not found: World of Warcards", `<h1>Not found</h1><p>There is nothing at this address. <a href="/">Back to the ladder</a>.</p>`);
}
