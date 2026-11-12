// The public website (roadmap B8): the ladder, a player's page with a read-only view of their binder, the fair-play rules and
// the privacy page. Plain HTML made on the server from the same data as the API, with no scripts, no outside resources and
// no game art (card names and numbers only, as the policy notes require). Every piece of text that came from a player or the
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
    : `<div class="panel empty-state"><span class="empty-symbol" aria-hidden="true">◇</span><div><h2>A place for the first adventurers.</h2><p class="empty">Nobody is on the ladder yet. Only players whose every drop was rolled in Ranked mode are listed. <a href="/help#companion">Connect your collection</a> to get started.</p></div></div>`;
  const first = firsts.length > 0
    ? `<ul>${firsts.map((row) => `<li><strong>${escapeHtml(row.title)}</strong>: <a href="/player/${escapeHtml(row.playerId)}">${escapeHtml(row.displayName)}</a> <span class="copies">${date(row.at)}</span></li>`).join("")}</ul>`
    : `<p class="empty">No set has been finished yet.</p>`;
  return layout("World of Warcards: the ladder", `
<div class="page-heading"><p class="eyebrow">THE COLLECTOR’S CORNER</p><h1>The ladder</h1>
<p class="lede">Explore public collections and follow the first collectors to complete a set. Only <a href="/fair-play">Ranked</a> play counts for the ladder.</p></div><div class="page-content">
${table}
<div class="subheading"><h2>First to finish a set</h2><span>Collection milestones, recorded as they happen.</span></div>
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
<div class="page-heading"><p class="eyebrow">A COLLECTOR'S BINDER</p><h1>${escapeHtml(player.displayName)}</h1>
<p class="lede">Last updated ${date(player.updatedAt)}. This is a read-only view of the binder the server has on record.</p></div><div class="page-content">
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

export const fairPlayHeadings = ["How Ranked works", "What the server checks", "What happens when something looks wrong", "What this cannot promise", "Trading", "Starting over"] as const;

export function fairPlayPage(): string {
  return layout("Fair play: World of Warcards", `
<article class="prose page-content"><p class="eyebrow">A COLLECTION YOU CAN TRUST</p><h1>Fair play</h1>
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
<p>A new binder can be started once a day. The old one stays on record, stops counting, and the new one gets new random numbers from its first drop.</p></article>
`, "/fair-play");
}

export const privacyHeadings = ["What is stored", "What is shown to others", "What is not collected", "Your choices", "Technical logs", "Where it lives"] as const;

export function privacyPage(): string {
  return layout("Privacy: World of Warcards", `
<article class="prose page-content"><p class="eyebrow">YOUR COLLECTION. YOUR CHOICE.</p><h1>Privacy</h1>
<p class="lede">What the service holds about you, what other people see, and how to remove it.</p>

<h2>What is stored</h2>
<ul>
<li><strong>Your Discord id</strong>, and nothing else from Discord: not your name, avatar, email or servers. Signing in asks for the identify permission only, and the one-time token is thrown away straight away.</li>
<li><strong>A public key</strong> made on your computer. The matching private key never leaves it.</li>
<li><strong>Your characters' names and realms</strong>, taken from your history.</li>
<li><strong>Your history</strong>: every card found, crafted, recycled and traded, with times, the trade partner's character name and the trade id.</li>
<li><strong>Your score</strong> and when it last changed.</li>
<li><strong>The cards you are looking for</strong> (your wanted list), only if you are public. A private player's list is not kept.</li>
<li><strong>Reports</strong> you send about other players (the character's name, a reason and a short note you wrote) and reports other players sent about you. Only the people who run the service read them; they are not shown to anyone else, and they are erased with the rest when you delete your data.</li>
<li><strong>Counts the server needs to check play</strong>: attempts per card, random-number positions used, and any fair-play flags with a reviewer's note.</li>
</ul>

<h2>What is shown to others</h2>
<p>Only if you chose <strong>public</strong> when you signed up: your character name and realm, your rank and score, your sets finished, the cards in your binder and the cards you are looking for, on this site and with a "verified" mark beside your name in the game. A <strong>private</strong> player is stored but never listed.</p>

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
<p>On Cloudflare (Workers and D1). Secrets are kept as Worker secrets, never in the project's code.</p></article>
`, "/privacy");
}

// What public players are looking for: the most wanted cards first, then each player's list. Names and card names only.
export function wantedPage(entries: { playerId: string; displayName: string; cards: string[]; updatedAt: number }[], catalog: Catalog): string {
  const wantedBy = new Map<string, string[]>();
  for (const entry of entries) for (const key of entry.cards) wantedBy.set(key, [...(wantedBy.get(key) ?? []), entry.displayName]);
  const ranked = [...wantedBy.entries()].filter(([key]) => catalog.cards[key]).sort((a, b) => b[1].length - a[1].length || (catalog.cards[a[0]]?.name ?? "").localeCompare(catalog.cards[b[0]]?.name ?? ""));
  const cardRows = ranked.map(([key, names]) => {
    const card = catalog.cards[key]!;
    const rarity = ["common", "rare", "epic", "legendary"].includes(card.rarity) ? card.rarity : "common";
    return `<tr><td class="${rarity}">${escapeHtml(card.name)}</td><td class="num">${names.length}</td><td>${names.map(escapeHtml).join(", ")}</td></tr>`;
  }).join("\n");
  const cards = ranked.length > 0
    ? `<table><caption class="empty">Cards players are looking for</caption>\n<thead><tr><th>Card</th><th class="num">Wanted by</th><th>Who</th></tr></thead>\n<tbody>\n${cardRows}\n</tbody></table>`
    : `<div class="panel empty-state"><span class="empty-symbol" aria-hidden="true">◇</span><div><h2>Every collection has a missing piece.</h2><p class="empty">Nobody has listed a card they are looking for yet. Mark the cards you want in your binder and sync with public visibility to share your list.</p></div></div>`;
  const people = entries.map((entry) => `<details><summary>${escapeHtml(entry.displayName)}: ${entry.cards.length} card${entry.cards.length === 1 ? "" : "s"}</summary><ul>${entry.cards.flatMap((key) => (catalog.cards[key] ? [`<li>${escapeHtml(catalog.cards[key]!.name)}</li>`] : [])).join("")}</ul></details>`).join("\n");
  return layout("Wanted: World of Warcards", `
<div class="page-heading"><p class="eyebrow">A GOOD TRADE STARTS HERE</p><h1>Wanted cards</h1>
<p class="lede">Find the missing piece for someone's collection. Arrange a swap in the game: target the other player and use the Trade tab. Public players can share their wanted list here and clear it at any time.</p></div><div class="page-content">
${cards}
<h2>By player</h2>
${people || '<p class="empty">No lists yet.</p>'}</div>
`, "/wanted");
}

export function notFoundPage(): string {
  return layout("Not found: World of Warcards", `<div class="page-heading"><p class="eyebrow">A PATH LESS TRAVELLED</p><h1>Not found</h1><p class="lede">There is nothing at this address. The page may be private or no longer available.</p><div class="actions"><a class="button primary" href="/">Back to home</a><a class="button" href="/ladder">Explore the ladder</a></div></div>`, "");
}
