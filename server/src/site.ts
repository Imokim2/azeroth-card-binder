// The public website (roadmap B8): the ladder, a player's page with a read-only view of their binder, the fair-play rules and
// the privacy page. Plain HTML made on the server from the same data as the API, with no scripts, no outside resources and
// supplied screenshots on the homepage. Every piece of text that came from a player or the
// data is escaped before it goes into a page.
import type { Catalog } from "./shared.ts";
import { editionKeys, familyCount } from "./shared.ts";

import { escapeHtml, layout } from "./siteShell.ts";
export { escapeHtml, layout } from "./siteShell.ts";

const date = (seconds: number): string => new Date(seconds * 1000).toISOString().slice(0, 10);

export type LadderEntry = { rank: number; playerId: string; displayName: string; scoreTenths: number; uniqueCards: number; setsDone: number };
export type First = { title: string; displayName: string; playerId: string; at: number };

export function ladderPage(entries: LadderEntry[], firsts: First[]): string {
  const rows = entries.map((entry) =>
    `<tr><td class="num">${entry.rank}</td><td><a href="/player/${escapeHtml(entry.playerId)}">${escapeHtml(entry.displayName)}</a></td><td class="num">${(entry.scoreTenths / 10).toFixed(1)}</td><td class="num">${entry.uniqueCards}</td><td class="num">${entry.setsDone}</td></tr>`).join("\n");
  const table = entries.length > 0
    ? `<table class="ladder-table"><caption class="empty">The top ${entries.length} ranked players</caption>\n<thead><tr><th class="num">#</th><th>Player</th><th class="num">Points</th><th class="num">Cards</th><th class="num">Sets</th></tr></thead>\n<tbody>\n${rows}\n</tbody></table>`
    : `<div class="panel empty-state"><span class="empty-symbol" aria-hidden="true">◇</span><div><h2>No Ranked collections yet</h2><p class="empty">Nobody is on the ladder yet. Only players whose every drop was rolled in Ranked mode are listed. <a href="/help#companion">Connect your collection</a> to get started.</p></div></div>`;
  const first = firsts.length > 0
    ? `<ul>${firsts.map((row) => `<li><strong>${escapeHtml(row.title)}</strong>: <a href="/player/${escapeHtml(row.playerId)}">${escapeHtml(row.displayName)}</a> <span class="copies">${date(row.at)}</span></li>`).join("")}</ul>`
    : `<p class="empty">No set has been finished yet.</p>`;
  return layout("World of Warcards: the ladder", `
<div class="page-heading"><h1>The ladder</h1>
<p class="lede">Compare public Ranked collections and see who finished each set first. Only <a href="/fair-play">Ranked</a> play counts towards these scores.</p></div><div class="page-content">
${table}
<div class="subheading"><h2>First to finish a set</h2></div>
${first}</div>
`, "/ladder");
}

export type BinderSet = { title: string; owned: number; total: number; cards: { name: string; rarity: string; copies: number; shiny: boolean }[] };

export function playerPage(player: { displayName: string; rank: number; scoreTenths: number; uniqueCards: number; setsDone: number; updatedAt: number }, sets: BinderSet[]): string {
  const stats = `<dl class="stats"><div><dt>Rank</dt><dd>#${player.rank}</dd></div><div><dt>Points</dt><dd>${(player.scoreTenths / 10).toFixed(1)}</dd></div><div><dt>Cards</dt><dd>${player.uniqueCards}</dd></div><div><dt>Sets finished</dt><dd>${player.setsDone}</dd></div></dl>`;
  const list = sets.length > 0
    ? sets.map((set) => `<details><summary>${escapeHtml(set.title)}: ${set.owned} of ${set.total}</summary><ul>${set.cards.map((card) =>
        `<li class="${["common", "rare", "epic", "legendary"].includes(card.rarity) ? card.rarity : "common"}${card.shiny ? " shiny" : ""}">${escapeHtml(card.name)}${card.copies > 1 ? ` <span class="copies">x${card.copies}</span>` : ""}</li>`).join("")}</ul></details>`).join("\n")
    : `<p class="empty">No cards yet.</p>`;
  return layout(`${player.displayName} on World of Warcards`, `
<div class="page-heading"><h1>${escapeHtml(player.displayName)}</h1>
<p class="lede">Last synced ${date(player.updatedAt)}. Cards and counts shown here come from this player’s saved binder.</p></div><div class="page-content">
${stats}
<h2>Binder</h2>
${list}
<p><a href="/ladder">Back to the ladder</a></p></div>
`, "/ladder");
}

// The sets a binder has started, most complete first, with the cards owned in each (names and counts only).
export function binderSets(catalog: Catalog, counts: Record<string, number>, shiny: Record<string, boolean>): BinderSet[] {
  const sets: BinderSet[] = [];
  for (const set of catalog.sets) {
    const cards = set.cards.flatMap((base) => editionKeys(catalog, base).flatMap((key) => {
      const card = catalog.cards[key], copies = counts[key] ?? 0;
      return card && copies > 0 ? [{ name: card.name, rarity: card.rarity, copies, shiny: shiny[key] === true }] : [];
    }));
    const owned = set.cards.filter((key) => familyCount(catalog, counts, key) > 0).length;
    if (cards.length > 0) sets.push({ title: set.title, owned, total: set.cards.length, cards });
  }
  return sets.sort((a, b) => b.owned / b.total - a.owned / a.total || b.owned - a.owned || a.title.localeCompare(b.title));
}

export const fairPlayHeadings = ["Playing Ranked", "Play fairly", "Trading and gifts", "Reviews and restrictions", "Starting a new binder", "Report a problem"] as const;

export function fairPlayPage(): string {
  return layout("Ranked rules — World of Warcards", `
<article class="prose page-content"><h1>Ranked rules</h1>
<p class="lede">Collect through normal play, trade fairly and keep your collection genuine.</p>

<h2>Playing Ranked</h2>
<p>Only <strong>Ranked</strong> play counts for the ladder. Choose Ranked before you start collecting and keep the companion app running to sync your progress. A binder containing Casual drops is not eligible for the Ranked ladder.</p>
<p>Your collection must be public to appear on the website’s ladder. Keep your addon and companion app up to date.</p>

<h2>Play fairly</h2>
<ul>
<li>Earn cards through normal gameplay and use the addon’s own collecting, crafting and trading features.</li>
<li>Do not edit your collection, create cards outside the addon’s normal features or submit false progress.</li>
<li>Do not use modified software, bots or scripts to gain an unfair collecting advantage.</li>
<li>Do not deliberately exploit bugs, duplicate cards or help someone else pass off an altered collection as genuine.</li>
<li>If you find a bug, report it. Do not keep using it to gain cards or share instructions for abusing it.</li>
</ul>

<h2>Trading and gifts</h2>
<p>Use the addon’s trade window for exchanges and gifts. Both players must agree to what is offered and complete the trade normally. Both players should sync afterwards.</p>
<p>Cards received through a trade must also be eligible for Ranked play. A trade that is incomplete or under review may not count towards your score. Do not use other accounts or arranged trades to get around these rules.</p>

<h2>Reviews and restrictions</h2>
<p>Collections may be reviewed to keep the ladder fair. A collection can be temporarily hidden while a review is taking place. Confirmed cheating can lead to removal from the ladder or a ban from the service.</p>
<p>If you think your collection has been restricted by mistake, contact the project maintainers. Include your character name, addon version and the message you received. Do not post private account files in a public report.</p>

<h2>Starting a new binder</h2>
<p>If you want to move from Casual to Ranked, type <code>/acb newbinder</code> in game and read the confirmation carefully. Starting again resets your collection progress. Wait for the companion app to confirm the new binder, then choose Ranked before collecting any cards.</p>

<h2>Report a problem</h2>
<p>For bugs and questions, use the <a href="https://github.com/Imokim2/azeroth-card-binder/issues/new/choose">GitHub issue tracker</a>. For a security issue or an exploit, follow the repository’s <a href="https://github.com/Imokim2/azeroth-card-binder/blob/main/SECURITY.md">private reporting instructions</a>.</p></article>
`, "/fair-play");
}

export const privacyHeadings = ["What is stored", "What is shown to others", "What is not collected", "Your choices", "Technical logs", "Where it lives"] as const;

// `contact` is the address people can write to about their data, once there is one (the PRIVACY_EMAIL setting); without it the
// page points to the app's own buttons and the project's issue tracker.
export function privacyPage(contact?: string): string {
  return layout("Privacy: World of Warcards", `
<article class="prose page-content"><h1>Privacy</h1>
<p class="lede">What we store when you use the companion app, what other players can see and how to delete your data.</p>

<h2>What is stored</h2>
<ul>
<li><strong>Your Discord id</strong>, and nothing else from Discord: not your name, avatar, email or servers. Signing in asks for the identify permission only, and the one-time token is thrown away straight away.</li>
<li><strong>A public key</strong> made on your computer. The matching private key never leaves it.</li>
<li><strong>Your characters' names and realms</strong>, taken from your history.</li>
<li><strong>Your history</strong>: every card found, crafted, recycled and traded, with times, the trade partner's character name and the trade id.</li>
<li><strong>Your score</strong> and when it last changed.</li>
<li><strong>Legacy wanted lists</strong> uploaded by older companion versions may remain in your account data. Current companions keep wanted lists in game; they are not published on this site.</li>
<li><strong>Reports</strong> you send about other players (the character's name, a reason and a short note you wrote) and reports other players sent about you. Only the people who run the service read them; they are not shown to anyone else, and they are erased with the rest when you delete your data.</li>
<li><strong>Counts the server needs to check play</strong>: attempts per card, random-number positions used, and any fair-play flags with a reviewer's note.</li>
</ul>

<h2>What is shown to others</h2>
<p>Only if you chose <strong>public</strong> when you signed up: your character name and realm, your rank and score, your sets finished, the cards in your binder, on this site and with a "verified" mark beside your name in the game. A <strong>private</strong> player is stored but never listed.</p>

<h2>What is not collected</h2>
<p>Nothing about what is on your screen, in the game's memory or in your chat. The companion app reads one file the game writes and writes one file the add-on reads. It does not touch the game process or its network traffic.</p>

<h2>Your choices</h2>
<ul>
<li>Choose public or private when you sign up, and change it by signing in again.</li>
<li>Delete your data from the server at any time with <strong>Delete my data</strong> in the companion app. Your record, history, characters, Discord link and any archived binders are erased from the live service at once. Copies kept for recovery after a mistake age out on their own: Cloudflare&rsquo;s recovery history lasts 7 days and our own daily copies are kept for 14. Your cards in the game and the files on your computer are not touched. You can sign up again later, from nothing.</li>
<li>Download a copy of everything held about you with <strong>Download my data</strong> in the companion app: your account, keys, characters, every event of every binder you have had, your saved state, score, trades, finished sets, wanted cards and the reports you sent. It leaves out reports other players made about you, the notes reviewers wrote and the server's secrets.</li>
<li>A banned account's record is kept, so that a ban cannot be undone by deleting the account.</li>
</ul>

<h2>Questions about your data</h2>
<p>${contact ? `Write to <a href="mailto:${escapeHtml(contact)}">${escapeHtml(contact)}</a> to ask what is held about you, to have something corrected, or about anything on this page.` : `Use <strong>Download my data</strong> and <strong>Delete my data</strong> in the companion app, or open an issue on the project's <a href="https://github.com/Imokim2/azeroth-card-binder/issues/new/choose">GitHub tracker</a> (please do not put personal details in a public issue).`}</p>

<h2>Technical logs</h2>
<p>The server keeps a log of each request (the route, the result and how long it took, with a request id) so that problems can be found. It does not log your Discord id, your cards or what you uploaded. Cloudflare, which runs the server, also keeps its own technical logs, which include the address a request came from, for a limited time.</p>

<h2>Where it lives</h2>
<p>On Cloudflare (Workers and D1). Secrets are kept as Worker secrets, never in the project's code.</p></article>
`, "/privacy");
}

export function notFoundPage(): string {
  return layout("Not found: World of Warcards", `<div class="page-heading"><h1>Page not found</h1><p class="lede">There is nothing at this address. The page may be private or no longer available.</p><div class="actions"><a class="button primary" href="/">Back to home</a><a class="button" href="/ladder">View the ladder</a></div></div>`, "");
}
