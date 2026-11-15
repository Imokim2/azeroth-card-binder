// Collects how each creature treats the two factions, from its page on wowforever.ninja.
//
//   node tools/fetch-reactions.js <folder with the saved zone pages> <reactions file to write>
//
// Each NPC page has an "At a glance" line such as "Alliance Friendly Horde Hostile". The result is a JSON
// file { "<npc id>": "<Alliance reaction><Horde reaction>" } using F friendly, N neutral, H hostile
// (so "FH" is a guard that the Alliance can not attack). It is saved as it goes, so an interrupted run
// carries on where it stopped. Pages are fetched a few at a time with a short pause between requests.
const fs = require("fs");
const path = require("path");

const [pagesDir, outFile] = process.argv.slice(2);
if (!pagesDir || !outFile) throw new Error("Usage: node tools/fetch-reactions.js <pages folder> <reactions file>");

// Slugs for the links, from the zone pages (the site needs the whole link, not just the id).
const slugs = {};
for (const file of fs.readdirSync(pagesDir)) {
    const html = fs.readFileSync(path.join(pagesDir, file), "utf8");
    for (const match of html.matchAll(/\/npcs\/(\d+)-([a-z0-9-]+)\//g)) slugs[match[1]] = match[2];
}

// The ids to look up: every creature the zone pages list among those a player fights ("Rares, elites and bosses" and "Everything else, by
// level", the groups tools/build-catalog.js reads), whether or not it is a card yet, and the hand-made cards. A creature friendly to one
// faction is a card only the other faction can win (docs/FACTION-CARDS.md), so the creatures that are not cards yet matter too.
const ids = new Set();
const catalog = path.join(__dirname, "..", "AzerothCardBinder");
for (const file of fs.readdirSync(pagesDir)) {
    const html = fs.readFileSync(path.join(pagesDir, file), "utf8");
    const start = html.indexOf('id="npcs"');
    if (start < 0) continue;
    const next = html.indexOf('id="', start + 10);
    for (const group of html.slice(start, next < 0 ? undefined : next).split(/<details/).slice(1)) {
        const title = ((group.match(/<summary[^>]*>([\s\S]*?)<\/summary>/) || [])[1] || "").replace(/<[^>]+>/g, " ").replace(/\(\d+\)/, "").replace(/\s+/g, " ").trim();
        if (title !== "Rares, elites and bosses" && title !== "Everything else, by level") continue;
        for (const match of group.matchAll(/<a href="\/npcs\/(\d+)-/g)) ids.add(match[1]);
    }
}
for (const match of fs.readFileSync(path.join(catalog, "CatalogForever.lua"), "utf8").matchAll(/^\s+\{ (\d+), "/gm)) ids.add(match[1]);
for (const match of fs.readFileSync(path.join(catalog, "Catalog.lua"), "utf8").matchAll(/^card\(\d+, "[^"]+", (\d+), /gm)) ids.add(match[1]);

const results = fs.existsSync(outFile) ? JSON.parse(fs.readFileSync(outFile, "utf8")) : {};
const todo = [...ids].filter((id) => !results[id] && slugs[id]);
console.log(`${ids.size} creatures, ${Object.keys(results).length} already done, ${todo.length} to fetch,` +
    ` ${[...ids].filter((id) => !slugs[id]).length} with no link`);

const letter = { Friendly: "F", Neutral: "N", Hostile: "H" };
async function look(id) {
    const response = await fetch(`https://wowforever.ninja/npcs/${id}-${slugs[id]}/`, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (!response.ok) throw new Error(response.status);
    const text = (await response.text()).replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, "")
        .replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
    const match = text.match(/Alliance (Friendly|Neutral|Hostile) Horde (Friendly|Neutral|Hostile)/);
    if (!match) throw new Error("no reaction line");
    return letter[match[1]] + letter[match[2]];
}

(async () => {
    let next = 0, failed = 0;
    const save = () => fs.writeFileSync(outFile, JSON.stringify(results));
    async function worker() {
        while (next < todo.length) {
            const id = todo[next++];
            try {
                results[id] = await look(id);
            } catch (error) {
                failed++;
                console.log(`${id} ${slugs[id]}: ${error.message}`);
            }
            if (next % 100 === 0) { save(); console.log(`${next}/${todo.length}`); }
            await new Promise((done) => setTimeout(done, 150));
        }
    }
    await Promise.all([worker(), worker(), worker(), worker()]);
    save();
    console.log(`done, ${Object.keys(results).length} reactions, ${failed} failed`);
})();
