// Builds AzerothCardBinder/CatalogForever.lua from the zone, dungeon and raid pages of
// wowforever.ninja, an unofficial fan database for World of Warcraft: Forever.
//
//   node tools/build-catalog.js <folder with the saved zone pages> <saved zones index page>
//
// Only creatures that Forever's world has are used. Each page lists a place's creatures with a level and,
// for rares, elites and bosses, a rank. Friendly groups (quest givers, vendors and trainers) are skipped.
// Places the site has no creature data for yet (Forever's new zones and dungeons) are skipped too.
//
// Credit: the baseline data on that site comes from cMaNGOS classic-db (GPL-3.0) and Forever's own
// client files, as the site's "Where the data comes from" page explains.
const fs = require("fs");
const path = require("path");

const [pagesDir, indexFile] = process.argv.slice(2);
if (!pagesDir || !indexFile) throw new Error("Usage: node tools/build-catalog.js <pages folder> <zones index page>");

const decode = (text) => text
    .replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&").replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n))
    .replace(/\s+/g, " ").trim();
const strip = (html) => decode(html.replace(/<[^>]+>/g, " "));

// Which kind of place each page is, from the headings on the index page.
const index = fs.readFileSync(indexFile, "utf8");
const kindOf = {};
const order = [];
{
    const sections = index.split(/<h2[^>]*>/).slice(1);
    for (const section of sections) {
        const heading = strip(section.slice(0, section.indexOf("</h2>")));
        const kind = { "Eastern Kingdoms": "Zone", Kalimdor: "Zone", Capitals: "City", Dungeons: "Dungeon",
            Raids: "Raid", Battlegrounds: "Battleground" }[heading];
        for (const match of section.matchAll(/href="\/zones\/([a-z0-9-]+)\/"/g)) {
            const slug = match[1];
            if (!order.includes(slug)) order.push(slug);
            if (kind && !kindOf[slug]) kindOf[slug] = kind;
        }
    }
}

// Entries that exist for the game's scripts and not as monsters a player could meet.
const NOT_MONSTERS = /\btrigger\b|combat dummy|monster generator|invisible|mark of detonation|garden gas|^riding |\bbunny\b|\bvisual\b|\(dnd\)|\bunused\b/i;
const RANKS = { Elite: "e", Boss: "b", Rare: "r", "Rare elite": "R" };
const places = [];
for (const slug of order) {
    const file = path.join(pagesDir, slug + ".html");
    if (!fs.existsSync(file)) continue;
    const html = fs.readFileSync(file, "utf8");
    const start = html.indexOf('id="npcs"');
    if (start < 0) continue; // no creature data for this place yet
    const name = strip((html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/) || [])[1] || slug);
    const levels = decode(((html.match(/Level\s*(\d+\s*[–-]\s*\d+|\d+)/) || [])[1] || "").replace("-", "–"));
    const next = html.indexOf('id="', start + 10);
    const section = html.slice(start, next < 0 ? undefined : next);
    const creatures = [];
    for (const group of section.split(/<details/).slice(1)) {
        const title = strip((group.match(/<summary[^>]*>([\s\S]*?)<\/summary>/) || [])[1] || "").replace(/\(\d+\)/, "").trim();
        if (title !== "Rares, elites and bosses" && title !== "Everything else, by level") continue;
        for (const row of group.matchAll(/<tr[^>]*>\s*<td[^>]*>\s*<a href="\/npcs\/(\d+)-[^"]*">([\s\S]*?)<\/a>\s*<\/td>\s*<td[^>]*>([\s\S]*?)<\/td>\s*<\/tr>/g)) {
            const id = Number(row[1]);
            const cell = strip(row[3]);
            const rank = (cell.match(/·\s*(.+)$/) || [])[1];
            const level = Number((cell.match(/^(\d+)/) || [])[1]) || 0;
            const creature = strip(row[2]);
            if (!NOT_MONSTERS.test(creature)) creatures.push({ id, name: creature, rank: RANKS[rank] || "n", level });
        }
    }
    const kind = kindOf[slug] || "Zone";
    if (kind === "City") continue; // towns hold friendly townsfolk, not monsters
    const instance = kind === "Dungeon" || kind === "Raid";
    const known = creatures.map((c) => c.level).filter((level) => level >= (instance ? 8 : 1)).sort((a, b) => a - b);
    const range = known.length
        ? `${known[Math.floor(known.length * 0.05)]}–${known[Math.min(known.length - 1, Math.floor(known.length * 0.95))]}` : "";
    if (creatures.length > 0) places.push({ slug, name, kind, levels: levels || range, creatures });
}

// Instances first, so a creature that lives in a dungeon is filed there, then zones and cities.
const rankOrder = { b: 0, R: 1, r: 2, e: 3, n: 4 };
const priority = { Raid: 0, Dungeon: 1, Battleground: 2, Zone: 3, City: 4 };
places.sort((a, b) => priority[a.kind] - priority[b.kind] || order.indexOf(a.slug) - order.indexOf(b.slug));
const claimed = new Set();
for (const place of places) {
    place.creatures = place.creatures.filter((c) => !claimed.has(c.id) && claimed.add(c.id));
    place.creatures.sort((a, b) => rankOrder[a.rank] - rankOrder[b.rank] || a.level - b.level || a.name.localeCompare(b.name));
}
const kept = places.filter((p) => p.creatures.length > 0);
kept.sort((a, b) => priority[a.kind] - priority[b.kind] || order.indexOf(a.slug) - order.indexOf(b.slug));

const lua = [];
lua.push("-- GENERATED by tools/build-catalog.js from wowforever.ninja. Do not edit by hand.");
lua.push("-- Every creature in World of Warcraft: Forever's zones, dungeons and raids that the site has data for.");
lua.push("-- Rows are { npc id, name, rank, level } with rank n normal, e elite, r rare, R rare elite, b boss.");
lua.push("local _, ACB = ...");
lua.push("");
const quote = (text) => '"' + text.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
let total = 0;
for (const place of kept) {
    lua.push(`ACB.addPlace(${quote(place.slug)}, ${quote(place.name)}, ${quote(place.kind)}, ${quote(place.levels)}, {`);
    for (const c of place.creatures) lua.push(`    { ${c.id}, ${quote(c.name)}, "${c.rank}", ${c.level} },`);
    lua.push("})");
    lua.push("");
    total += place.creatures.length;
}
fs.writeFileSync(path.join(__dirname, "..", "AzerothCardBinder", "CatalogForever.lua"), lua.join("\n"));
console.log(`${kept.length} places, ${total} creatures`);
const byKind = {};
for (const p of kept) byKind[p.kind] = (byKind[p.kind] || 0) + p.creatures.length;
console.log(JSON.stringify(byKind));
console.log("largest:", kept.map((p) => [p.name, p.creatures.length]).sort((a, b) => b[1] - a[1]).slice(0, 6).map((x) => x.join(" ")).join("; "));
