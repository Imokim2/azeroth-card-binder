// Maintainer tool: DRAFTS which cards would stay in a smaller launch collection and which would be held back for seasons.
// It reads packages/shared/catalog.json and changes nothing in it. See docs/proposals/SMALLER-LAUNCH-COLLECTION.md.
//
//   node tools/launch-collection.js                 print the summary
//   node tools/launch-collection.js --write         also write docs/seasons/launch-collection-draft.json and .csv
//   node tools/launch-collection.js --chase keep    keep chase cards on ordinary creatures at launch (default: hold them back)
//
// The rule (deterministic, so two people get the same list and a review can be repeated):
//   1. Always kept: every elite, rare-elite and boss card; every critter; every gathering node.
//   2. Held back: chase cards on ordinary creatures (unless --chase keep).
//   3. Of the remaining ordinary-creature cards, enough are kept to make the launch collection exactly half of the base cards.
//      They are spread across the pages in proportion to each page's share (so no page is emptied), and within a page the
//      kept ones are the first by SHA-256 of "launch-v1|<card key>", which is stable and does not depend on card order.
"use strict";
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..");
const catalogPath = path.join(root, "packages", "shared", "catalog.json");
const outputBase = path.join(root, "docs", "seasons", "launch-collection-draft");

function draft(catalog, options = {}) {
  const chase = options.chase === "keep" ? "keep" : "season";
  const baseKeys = Object.keys(catalog.cards).filter((key) => !catalog.cards[key].baseKey);
  const target = Math.floor(baseKeys.length / 2);
  const pageOf = new Map();
  for (const set of catalog.sets) for (const key of set.cards) pageOf.set(key, set);
  const order = (key) => crypto.createHash("sha256").update("launch-v1|" + key).digest("hex");

  const always = (card) => card.rank === "elite" || card.rank === "rareelite" || card.boss === true
    || card.dropProfile.tier === "critter" || card.rank === "gathering";
  const chaseNormal = (card) => card.dropProfile.tier === "chase" && card.rank === "normal";
  const keep = new Set();
  const candidates = new Map(); // page code -> keys that could still be kept
  for (const key of baseKeys) {
    const card = catalog.cards[key];
    if (always(card) || (chase === "keep" && chaseNormal(card))) { keep.add(key); continue; }
    if (chase === "season" && chaseNormal(card)) continue;
    const code = pageOf.get(key).code;
    if (!candidates.has(code)) candidates.set(code, []);
    candidates.get(code).push(key);
  }
  const need = target - keep.size;
  const pool = [...candidates.values()].reduce((sum, keys) => sum + keys.length, 0);
  if (need < 0 || need > pool) throw new Error(`Cannot reach ${target} launch cards: ${keep.size} always kept, ${pool} candidates.`);

  // Largest-remainder shares per page, then make sure no page is left with nothing at all.
  const pages = [...candidates.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  const shares = pages.map(([code, keys]) => ({ code, keys, exact: (need * keys.length) / pool }));
  for (const share of shares) share.take = Math.floor(share.exact);
  let left = need - shares.reduce((sum, share) => sum + share.take, 0);
  for (const share of [...shares].sort((a, b) => (b.exact - Math.floor(b.exact)) - (a.exact - Math.floor(a.exact)) || a.code.localeCompare(b.code))) {
    if (left <= 0) break;
    share.take++;
    left--;
  }
  const keptOnPage = (code) => [...keep].filter((key) => pageOf.get(key).code === code).length;
  for (const share of shares) {
    if (share.take === 0 && keptOnPage(share.code) === 0) { // an otherwise empty page keeps one card, taken from the page with the most
      const donor = [...shares].sort((a, b) => b.take - a.take)[0];
      if (donor.take > 1) { donor.take--; share.take = 1; }
    }
  }
  for (const share of shares) {
    const ranked = [...share.keys].sort((a, b) => order(a).localeCompare(order(b)) || a.localeCompare(b));
    for (const key of ranked.slice(0, share.take)) keep.add(key);
  }
  if (keep.size !== target) throw new Error(`Launch collection has ${keep.size} cards, expected ${target}.`);

  const launch = baseKeys.filter((key) => keep.has(key));
  const seasons = baseKeys.filter((key) => !keep.has(key));
  const byPage = {};
  for (const set of catalog.sets) {
    byPage[set.code] = { title: set.title, group: set.group, launch: set.cards.filter((key) => keep.has(key)).length, seasons: set.cards.filter((key) => !keep.has(key)).length };
  }
  return { launch, seasons, byPage, chase };
}

function summary(catalog, result) {
  const lines = [];
  const kind = (keys) => {
    const out = {};
    for (const key of keys) {
      const card = catalog.cards[key];
      const label = card.dropProfile.tier === "critter" ? "critter" : card.dropProfile.tier === "chase" && card.rank === "normal" ? "chase (ordinary creature)" : card.boss ? "boss" : card.rank;
      out[label] = (out[label] || 0) + 1;
    }
    return out;
  };
  lines.push(`Base cards: ${result.launch.length + result.seasons.length}. Launch collection: ${result.launch.length}. Held back for seasons: ${result.seasons.length}. (chase cards on ordinary creatures: ${result.chase === "keep" ? "kept at launch" : "held back"})`);
  lines.push("Launch by kind:   " + JSON.stringify(kind(result.launch)));
  lines.push("Seasons by kind:  " + JSON.stringify(kind(result.seasons)));
  const groups = {};
  for (const page of Object.values(result.byPage)) {
    const g = (groups[page.group] ||= { pages: 0, launch: 0, seasons: 0 });
    g.pages++; g.launch += page.launch; g.seasons += page.seasons;
  }
  for (const [name, g] of Object.entries(groups)) lines.push(`  ${name.padEnd(13)} ${String(g.pages).padStart(2)} pages: ${String(g.launch).padStart(4)} at launch, ${String(g.seasons).padStart(4)} for seasons`);
  const bare = Object.entries(result.byPage).filter(([, page]) => page.launch === 0).map(([code]) => code);
  lines.push(bare.length ? "Pages with nothing at launch: " + bare.join(", ") : "Every page has at least one card at launch.");
  return lines.join("\n");
}

function files(catalog, result) {
  const decision = new Map();
  for (const key of result.launch) decision.set(key, "launch");
  for (const key of result.seasons) decision.set(key, "seasons");
  const json = JSON.stringify({
    format: 1,
    status: "DRAFT: a proposal for review. Nothing in the catalog, add-on or server uses this file.",
    catalogVersion: catalog.catalogVersion,
    rule: "tools/launch-collection.js (chase cards on ordinary creatures: " + result.chase + ")",
    counts: { launch: result.launch.length, seasons: result.seasons.length },
    pages: result.byPage,
    launch: result.launch,
    seasons: result.seasons,
  }, null, 1) + "\n";
  const csvCell = (value) => '"' + String(value).replace(/"/g, '""') + '"';
  const rows = ["key,name,page,group,rarity,rank,tier,decision"];
  for (const set of catalog.sets) {
    for (const key of set.cards) {
      const card = catalog.cards[key];
      rows.push([key, card.name, set.title, set.group, card.rarity, card.boss ? card.rank + " boss" : card.rank, card.dropProfile.tier, decision.get(key)].map(csvCell).join(","));
    }
  }
  return { json, csv: rows.join("\n") + "\n" };
}

module.exports = { draft, files, summary };

if (require.main === module) {
  const args = process.argv.slice(2);
  const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  const chaseAt = args.indexOf("--chase");
  const result = draft(catalog, { chase: chaseAt >= 0 ? args[chaseAt + 1] : "season" });
  console.log(summary(catalog, result));
  if (args.includes("--write")) {
    const out = files(catalog, result);
    fs.mkdirSync(path.dirname(outputBase), { recursive: true });
    fs.writeFileSync(outputBase + ".json", out.json);
    fs.writeFileSync(outputBase + ".csv", out.csv);
    console.log("Wrote " + path.relative(root, outputBase) + ".json and .csv");
  }
}
