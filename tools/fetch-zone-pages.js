// Saves every zone, dungeon, raid and battleground page of wowforever.ninja (the fan database the catalog is built from), the input of
// tools/build-catalog.js. See docs/FACTION-CARDS.md for the whole routine.
//
//   node tools/fetch-zone-pages.js <folder to save into>
//
// It writes <folder>/zones-index.html and one <slug>.html for each zone the index lists. It can be stopped and run again: pages already saved are
// kept. Pages are fetched four at a time with a short pause between requests.
const fs = require("fs");
const path = require("path");

const folder = process.argv[2];
if (!folder) throw new Error("Usage: node tools/fetch-zone-pages.js <folder to save into>");
fs.mkdirSync(folder, { recursive: true });
const headers = { "User-Agent": "Mozilla/5.0 (World of Warcards catalog build)" };

(async () => {
    const response = await fetch("https://wowforever.ninja/zones/", { headers });
    if (!response.ok) throw new Error("the zones index answered " + response.status);
    const index = await response.text();
    fs.writeFileSync(path.join(folder, "zones-index.html"), index);
    const slugs = [...new Set([...index.matchAll(/href="\/zones\/([a-z0-9-]+)\/"/g)].map((match) => match[1]))];
    const todo = slugs.filter((slug) => !fs.existsSync(path.join(folder, slug + ".html")));
    console.log(`${slugs.length} zones, ${todo.length} to fetch`);
    let next = 0, failed = 0;
    async function worker() {
        while (next < todo.length) {
            const slug = todo[next++];
            try {
                const page = await fetch(`https://wowforever.ninja/zones/${slug}/`, { headers });
                if (!page.ok) throw new Error("HTTP " + page.status);
                fs.writeFileSync(path.join(folder, slug + ".html"), await page.text());
            } catch (error) {
                failed++;
                console.log(`${slug}: ${error.message}`);
            }
            await new Promise((done) => setTimeout(done, 150));
        }
    }
    await Promise.all([worker(), worker(), worker(), worker()]);
    console.log(`done, ${failed} failed. Next: node tools/fetch-reactions.js ${folder} <reactions file>`);
    process.exit(failed ? 1 : 0);
})().catch((error) => { console.error(error.message); process.exit(2); });
