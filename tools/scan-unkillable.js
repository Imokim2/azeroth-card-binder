#!/usr/bin/env node
// Looks for cards that can never be won because their creature cannot be killed. Each creature card is checked against its page on
// wowforever.ninja (the unofficial fan database the catalog was built from; see tools/build-catalog.js), which gives a creature's level, type,
// health, reaction to each faction and where it spawns. It does not say "cannot be attacked", so the scan flags what the data points to and a
// person confirms in the game; what has been decided lives in AzerothCardBinder/UnobtainableCards.lua (docs/UNOBTAINABLE-CARDS.md).
//
//   node tools/scan-unkillable.js [--cache <file>] [--report <markdown file>] [--offline]
//
// It reads about 3,400 pages, four at a time with a short pause (the way tools/fetch-reactions.js does), and saves as it goes in the cache file
// (default: warcards-creature-scan.json in the system temp folder), so it can be stopped and carried on. --offline uses the cache and reads nothing.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");

const root = path.resolve(__dirname, "..");
const PET = /Non-combat Pet/i;

const slugs = (name) => {
  const lower = name.toLowerCase().replace(/&/g, "and");
  return [...new Set([
    lower.replace(/['’]/g, "").replace(/[^a-z0-9]+/g, "-"),
    lower.replace(/['’]/g, "-").replace(/[^a-z0-9]+/g, "-"),
    lower.replace(/[^a-z0-9 ]/g, "").replace(/ +/g, "-"),
  ].map((slug) => slug.replace(/^-+|-+$/g, "")))];
};
const strip = (html) => html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, " ").replace(/<[^>]+>/g, " ")
  .replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/\s+/g, " ").trim();

// What one creature's page says: the "At a glance" line and the section headings.
async function readPage(id, name, get = fetch) {
  let last = "no page";
  for (const slug of slugs(name)) {
    const response = await get(`https://wowforever.ninja/npcs/${id}-${slug}/`, { headers: { "User-Agent": "Mozilla/5.0 (World of Warcards catalog check)" } });
    if (response.status === 404) { last = "404"; continue; }
    if (!response.ok) throw new Error("HTTP " + response.status);
    const html = await response.text();
    const glance = /At a glance (.*?) NPC id (\d+)/.exec(strip(html));
    return { name, glance: glance ? glance[1] : null, headings: [...html.matchAll(/<h[23][^>]*>([^<]*)/g)].map((match) => match[1].trim()).filter((heading) => heading && heading !== "At a glance") };
  }
  return { name, error: last };
}

// "Level 21 Rare elite Type Humanoid Alliance Hostile Horde Hostile Health 33,344 Zone Deadmines" into fields.
function parse(glance) {
  const g = glance || "";
  const afterHorde = /Horde \S+ (.*?)(?: Zones?|$)/.exec(g);
  return {
    level: (/^Level (.+?) (?:Rare|Elite|Boss|Type)/.exec(g) || /^Level (\S+)/.exec(g) || [])[1] || "",
    type: (/Type (.+?) Alliance /.exec(g) || [])[1] || "",
    alliance: (/Alliance (\S+)/.exec(g) || [])[1] || "",
    horde: (/Horde (\S+)/.exec(g) || [])[1] || "",
    healthText: afterHorde ? afterHorde[1].trim() : "",
    zones: (/Zones? (.+)$/.exec(g) || [])[1] || "",
  };
}

// Sorts the creature cards into what the data says. `pages` is { "<npc id>": page }, `catalog` the shared catalog, `listed` the keys already in
// UnobtainableCards.lua. Returns { certain, likely, unknown, listedNoReason, notListed }.
function analyse(pages, catalog, listed = []) {
  const certain = [], likely = [], unknown = [];
  for (const [id, page] of Object.entries(pages)) {
    const key = "npc:" + id;
    const card = catalog.cards[key];
    if (!card) continue;
    const item = { key, name: card.name, set: card.set, held: card.seasonal === true };
    if (page.error) { unknown.push({ ...item, why: "no page on the site (" + page.error + ")" }); continue; }
    const f = parse(page.glance);
    const critter = /Critter/.test(f.type);
    const noData = /not known/i.test(f.level) || f.alliance === "Unknown" || f.horde === "Unknown";
    if (PET.test(f.type)) certain.push({ ...item, why: "a companion pet (type \"Non-combat Pet\"): cannot be attacked" });
    else if (noData) unknown.push({ ...item, why: "no level, reaction or location in the data (a new Forever creature)" });
    // A dungeon or raid creature the data lists as friendly to both (card.since) is often a scripted event creature that can be fought, so it is
    // reported as unknown; the ones known to be story characters are on UnobtainableCards.lua. Anywhere else, friendly to both cannot be killed.
    else if (f.alliance === "Friendly" && f.horde === "Friendly") (card.since ? unknown : certain).push({ ...item, why: card.since ? "a dungeon or raid creature friendly to both in the data: check in game" : "friendly to both factions" });
    else if (!critter && (f.healthText === "0" || /^Health\s*0$/.test(f.healthText))) likely.push({ ...item, why: "no health in the data" });
    else if (/Totem/.test(f.type) && /^1$/.test(f.level)) likely.push({ ...item, why: "a level 1 totem" });
    else if (/\bportal$/i.test(card.name)) likely.push({ ...item, why: "a portal, not a creature" }); // "C'Thun Portal", not "Portal Seeker"
  }
  const flagged = new Set([...certain, ...likely].map((item) => item.key));
  const known = new Set(listed);
  return {
    certain, likely, unknown,
    notListed: [...certain, ...likely].filter((item) => !known.has(item.key)),
    listedNoReason: [...known].filter((key) => !flagged.has(key)), // on the list by someone's judgement (for example an event spirit)
  };
}

function report(result, catalog, scanned) {
  const row = (item) => `| ${item.name} (${item.key}) | ${(catalog.sets.find((set) => set.code === item.set) || { title: item.set }).title} | ${item.why} | ${item.held ? "held back" : "launch card"} |`;
  const section = (title, items) => [`## ${title} (${items.length})`, "", "| Card | Page | Why | Status |", "|---|---|---|---|", ...items.map(row), ""];
  return [
    "# Cards that cannot be won by killing: scan report", "", `${scanned} creature cards read.`, "",
    ...section("The data says they cannot be fought", result.certain),
    ...section("Likely, check in the game", result.likely),
    ...section("Cannot be checked: the source has no data", result.unknown),
    `Flagged by the scan but not yet in UnobtainableCards.lua: ${result.notListed.length ? result.notListed.map((item) => item.key).join(", ") : "none"}.`,
    `In UnobtainableCards.lua by judgement, not by anything the scan checks: ${result.listedNoReason.length ? result.listedNoReason.join(", ") : "none"}.`, "",
  ].join("\n");
}

module.exports = { readPage, parse, analyse, report, slugs };

if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const option = (name) => (args.includes("--" + name) ? args[args.indexOf("--" + name) + 1] : undefined);
    const cacheFile = option("cache") || path.join(os.tmpdir(), "warcards-creature-scan.json");
    const catalog = JSON.parse(fs.readFileSync(path.join(root, "packages", "shared", "catalog.json"), "utf8"));
    const pages = fs.existsSync(cacheFile) ? JSON.parse(fs.readFileSync(cacheFile, "utf8")) : {};
    const ids = Object.entries(catalog.cards).filter(([key, card]) => key.startsWith("npc:") && !card.baseKey).map(([key, card]) => [key.slice(4), card.name]);
    const todo = args.includes("--offline") ? [] : ids.filter(([id]) => !pages[id]);
    console.log(`${ids.length} creature cards, ${ids.length - todo.length} in ${path.basename(cacheFile)}, ${todo.length} to read`);
    let next = 0;
    const worker = async () => {
      while (next < todo.length) {
        const [id, name] = todo[next++];
        try { pages[id] = await readPage(id, name); } catch (error) { pages[id] = { name, error: String(error.message || error) }; }
        if (next % 200 === 0) { fs.writeFileSync(cacheFile, JSON.stringify(pages)); console.log(`${next}/${todo.length}`); }
        await new Promise((done) => setTimeout(done, 120));
      }
    };
    await Promise.all([worker(), worker(), worker(), worker()]);
    fs.writeFileSync(cacheFile, JSON.stringify(pages));
    const lua = fs.readFileSync(path.join(root, "AzerothCardBinder", "UnobtainableCards.lua"), "utf8");
    const listed = [...lua.matchAll(/^\s*\["(npc:\d+)"\]/gm)].map((match) => match[1]);
    const result = analyse(pages, catalog, listed);
    const text = report(result, catalog, Object.keys(pages).length);
    if (option("report")) fs.writeFileSync(path.resolve(option("report")), text);
    console.log(`\ncertain ${result.certain.length}, likely ${result.likely.length}, no data ${result.unknown.length}; not yet listed: ${result.notListed.length}`);
    for (const item of result.notListed) console.log("  not listed: " + item.key + " " + item.name + " (" + item.why + ")");
    process.exit(result.notListed.length ? 1 : 0);
  })().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exit(2); });
}
