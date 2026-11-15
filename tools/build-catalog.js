// Builds AzerothCardBinder/CatalogForever.lua from the zone, dungeon and raid pages of
// wowforever.ninja, an unofficial fan database for World of Warcraft: Forever.
//
//   node tools/build-catalog.js <folder with the saved zone pages> <saved zones index page> <reactions file>
//
// The reactions file comes from tools/fetch-reactions.js. A creature that is neutral or hostile to both factions is a
// card both can win. A creature friendly to one faction is a card only the other faction can win (the row is tagged
// "A" when the Alliance can kill it, "H" when the Horde can; docs/FACTION-CARDS.md), with the Horde's capped to the
// Alliance's number so the two sides have the same count of their own. In a dungeon or raid a creature friendly to
// both (a scripted event creature, a quest giver inside) still gets a card, tagged "S"; the ones that cannot be killed
// are on AzerothCardBinder/UnobtainableCards.lua. Anything the site has no reaction for is left out.
//
// Only creatures that Forever's world has are used. Each page lists a place's creatures with a level and,
// for rares, elites and bosses, a rank. Friendly groups (quest givers, vendors and trainers) are skipped.
// Places the site has no creature data for yet (Forever's new zones and dungeons) are skipped too.
//
// Credit: the baseline data on that site comes from cMaNGOS classic-db (GPL-3.0) and Forever's own
// client files, as the site's "Where the data comes from" page explains.
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const [pagesDir, indexFile, reactionsFile] = process.argv.slice(2);
if (!pagesDir || !indexFile || !reactionsFile) throw new Error("Usage: node tools/build-catalog.js <pages folder> <zones index page> <reactions file>");
const reactions = JSON.parse(fs.readFileSync(reactionsFile, "utf8"));
// "" neutral or hostile to both (a card both factions can win); "A" the Alliance can kill it and the Horde cannot (a Horde
// guard); "H" the Horde can kill it and the Alliance cannot; "FF" friendly to both; null the site has no reaction for it.
const sideOf = (id) => {
    const reaction = reactions[id] || "";
    if (/^[NH][NH]$/.test(reaction)) return "";
    if (/^[NH]F$/.test(reaction)) return "A";
    if (/^F[NH]$/.test(reaction)) return "H";
    return reaction === "FF" ? "FF" : null;
};
let leftOut = 0;

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
const NOT_MONSTERS = /\btrigger\b|combat dummy|monster generator|invisible|mark of detonation|garden gas|^riding |\bbunny\b|\bvisual\b|\(dnd\)|\bunused\b|fire target/i;
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
            if (NOT_MONSTERS.test(creature)) continue;
            const side = sideOf(id);
            const inInstance = kindOf[slug] === "Dungeon" || kindOf[slug] === "Raid";
            if (side === null || (side === "FF" && !inInstance)) { leftOut++; continue; }
            creatures.push({ id, name: creature, rank: RANKS[rank] || "n", level, side: side === "FF" ? "S" : side });
        }
    }
    const kind = kindOf[slug] || "Zone";
    if (kind === "City") continue; // towns hold friendly townsfolk, not monsters
    const instance = kind === "Dungeon" || kind === "Raid";
    const known = creatures.filter((c) => !c.side).map((c) => c.level) // the levels of the cards added later do not move a page.filter((level) => level >= (instance ? 8 : 1)).sort((a, b) => a - b);
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
// The two sides get the same number of cards of their own. The Alliance's are all kept; the Horde's are cut down to that number
// by a rule that does not depend on order: every dungeon and raid creature stays (a dungeon mob always has a card), then every rare,
// elite and boss, then ordinary creatures spread over the places in proportion to what each has, first by SHA-256 of
// "faction-v1|<npc id>".
{
    const everything = places.flatMap((place) => place.creatures.map((c) => ({ place, c })));
    const alliance = everything.filter(({ c }) => c.side === "A").length;
    const horde = everything.filter(({ c }) => c.side === "H");
    const keep = new Set(horde.filter(({ place, c }) => place.kind === "Dungeon" || place.kind === "Raid" || c.rank !== "n").map(({ c }) => c.id));
    const need = alliance - keep.size;
    const pool = horde.filter(({ c }) => !keep.has(c.id));
    if (need < 0 || need > pool.length) throw new Error(`Cannot match the Alliance's ${alliance} cards: ${keep.size} Horde cards are always kept, ${pool.length} could be added.`);
    const byPlace = new Map();
    for (const item of pool) byPlace.set(item.place.slug, [...(byPlace.get(item.place.slug) || []), item]);
    const shares = [...byPlace.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([slug, items]) => ({ slug, items, exact: (need * items.length) / pool.length }));
    for (const share of shares) share.take = Math.floor(share.exact);
    let left = need - shares.reduce((sum, share) => sum + share.take, 0);
    for (const share of [...shares].sort((a, b) => (b.exact - Math.floor(b.exact)) - (a.exact - Math.floor(a.exact)) || a.slug.localeCompare(b.slug))) {
        if (left <= 0) break;
        share.take++;
        left--;
    }
    const order = (id) => crypto.createHash("sha256").update("faction-v1|" + id).digest("hex");
    for (const share of shares) {
        for (const item of share.items.sort((a, b) => order(a.c.id).localeCompare(order(b.c.id)) || a.c.id - b.c.id).slice(0, share.take)) keep.add(item.c.id);
    }
    for (const place of places) place.creatures = place.creatures.filter((c) => c.side !== "H" || keep.has(c.id));
    console.log(`Faction cards: ${alliance} the Alliance can win, ${places.reduce((n, p) => n + p.creatures.filter((c) => c.side === "H").length, 0)} the Horde can win (${horde.length - keep.size} cut to match).`);
}
const kept = places.filter((p) => p.creatures.length > 0);
kept.sort((a, b) => priority[a.kind] - priority[b.kind] || order.indexOf(a.slug) - order.indexOf(b.slug));

const lua = [];
lua.push("-- GENERATED by tools/build-catalog.js from wowforever.ninja. Do not edit by hand.");
lua.push("-- Every creature in World of Warcraft: Forever's zones, dungeons and raids that the site has data for.");
lua.push("-- Rows are { npc id, name, rank, level, tag } with rank n normal, e elite, r rare, R rare elite, b boss. A row with a tag is a card added in");
lua.push("-- ledger spec 10: \"A\" only the Alliance can win it (a Horde creature), \"H\" only the Horde can, \"S\" both (a dungeon creature that is friendly in the data).");
lua.push("local _, ACB = ...");
lua.push("");
const quote = (text) => '"' + text.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
let total = 0;
for (const place of kept) {
    lua.push(`ACB.addPlace(${quote(place.slug)}, ${quote(place.name)}, ${quote(place.kind)}, ${quote(place.levels)}, {`);
    for (const c of place.creatures) lua.push(`    { ${c.id}, ${quote(c.name)}, "${c.rank}", ${c.level}${c.side ? `, "${c.side}"` : ""} },`);
    lua.push("})");
    lua.push("");
    total += place.creatures.length;
}
fs.writeFileSync(path.join(__dirname, "..", "AzerothCardBinder", "CatalogForever.lua"), lua.join("\n"));
console.log(`${kept.length} places, ${total} creatures, ${leftOut} left out as friendly or unknown`);
const byKind = {};
for (const p of kept) byKind[p.kind] = (byKind[p.kind] || 0) + p.creatures.length;
console.log(JSON.stringify(byKind));
console.log("largest:", kept.map((p) => [p.name, p.creatures.length]).sort((a, b) => b[1] - a[1]).slice(0, 6).map((x) => x.join(" ")).join("; "));
