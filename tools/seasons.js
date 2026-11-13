// Maintainer tool. Preview locally before scheduling; never puts an admin token in a file or command argument.
// node tools/seasons.js preview docs/seasons/example.json
// node tools/seasons.js schedule path/to/season.json --env staging|production
const fs = require("node:fs");
const path = require("node:path");
async function main() {
    const [command, file, ...args] = process.argv.slice(2);
    if (!["preview", "schedule"].includes(command) || !file) throw new Error("Usage: node tools/seasons.js preview|schedule <json> [--env staging|production]");
    const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, "../packages/shared/catalog.json"), "utf8"));
    const input = JSON.parse(fs.readFileSync(file, "utf8"));
    for (const field of ["startsAt", "endsAt"]) if (typeof input[field] === "string") input[field] = Math.floor(Date.parse(input[field]) / 1000);
    const { seasonDefinition } = await import("../server/src/seasons.ts");
    const season = await seasonDefinition(input, catalog, Math.floor(Date.now() / 1000));
    console.log(`${season.title}: ${new Date(season.startsAt * 1000).toISOString()} to ${new Date(season.endsAt * 1000).toISOString()}`);
    console.log(season.cards.map(key => `${key}  ${catalog.cards[key].name} (${catalog.cards[key].set}, ${catalog.cards[key].rarity})`).join("\n"));
    console.log("Completion rewards:", JSON.stringify(season.rewards.completion));
    console.log("First-finisher bonus:", JSON.stringify(season.rewards.first));
    if (command === "preview") return;
    const target = args[args.indexOf("--env") + 1];
    if (!args.includes("--env") || !["staging", "production"].includes(target)) throw new Error("Choose --env staging or --env production explicitly.");
    const token = process.env.WARCARDS_ADMIN_TOKEN;
    if (!token) throw new Error("Set WARCARDS_ADMIN_TOKEN in your environment. Never put it in the season JSON.");
    const base = target === "staging" ? "https://staging.worldofwarcards.co.uk" : "https://worldofwarcards.co.uk";
    // Access-protected production admins may use a Cloudflare Access service token, held only in the environment.
    const headers = { "content-type": "application/json", authorization: "Bearer " + token };
    if (process.env.CF_ACCESS_CLIENT_ID && process.env.CF_ACCESS_CLIENT_SECRET) {
        headers["CF-Access-Client-Id"] = process.env.CF_ACCESS_CLIENT_ID;
        headers["CF-Access-Client-Secret"] = process.env.CF_ACCESS_CLIENT_SECRET;
    }
    const response = await fetch(base + "/v1/admin/seasons", { method: "POST", headers, body: JSON.stringify({ ...input, expectedCards: season.cards }) });
    if (response.status !== 201) throw new Error("Season was not scheduled (HTTP " + response.status + "). Check admin/Access permissions and the dates; existing season ids cannot be overwritten.");
    const result = await response.json();
    console.log("Scheduled " + result.season.id + " on " + target + ". The selected cards and rewards are now fixed.");
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
