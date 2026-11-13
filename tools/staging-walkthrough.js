#!/usr/bin/env node
// A walkthrough for a staging test of a release (docs/launch/RELEASE-0.7.0.md): everything that can be checked without a player is
// checked, a staging season is drafted, and what needs people and a game client is listed. It changes nothing on any server (every
// request is a GET or a POST that the server refuses for want of a registered key).
//
//   node tools/staging-walkthrough.js                    check this checkout, then staging, then print what is left to do by hand
//   node tools/staging-walkthrough.js --env production   or --url <address>
//   node tools/staging-walkthrough.js --offline          only this checkout
//   node tools/staging-walkthrough.js --wrangler         also ask Cloudflare which database migrations are still to apply (needs wrangler login)
//   node tools/staging-walkthrough.js --season-draft draft.json   write a draft season that releases two held-back cards, starting in 15 minutes
//   node tools/staging-walkthrough.js --no-smoke         skip tools/smoke.js (which this otherwise runs against the server first)
//
// Exit status 0: every automated check passed. 1: something needs a look. The "by hand" list never affects it.
"use strict";
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const SERVERS = { production: "https://worldofwarcards.co.uk", staging: "https://staging.worldofwarcards.co.uk" };

const HAND = [
  ["Upgrade, with an existing collection (back up the saved file first)", [
    "Install the companion, then the add-on, over an account that already has cards, packs, dust and titles: nothing is lost.",
    "After the first roll the saved file's ledger gains chase1 (if it was missing), chase2 and launch1, in that order, once each.",
    "Sync: the companion uploads and the server accepts; the ladder and standings still refresh.",
    "An old companion (0.4.5) with the new add-on shows \"The server refused it (client_too_old)\".",
  ]],
  ["Drop rates", [
    "/acb diag shows the new first-attempt chances; a critter's guarantee arrives far sooner than before.",
    "Casual and Ranked use the same rates.",
  ]],
  ["Launch collection (two Ranked accounts: one fresh, one with an existing collection)", [
    "A held-back creature (docs/seasons/launch-collection-draft.csv) gives no card and no attempt; a launch creature does.",
    "A fresh binder shows launch cards only; the existing binder still shows a held-back card it owns.",
    "Packs never contain a held-back card. Every page can be finished from its launch cards.",
    "Look at the sparse leveling-zone pages in the game (Teldrassil, Ashenvale, Duskwood, Mulgore) and say how they read.",
  ]],
  ["A season releases cards (schedule the draft this tool wrote, on staging)", [
    "After it starts and the companion syncs, Data/Sync.lua has seasonal.released; after /reload the two cards drop, appear in packs and can be crafted.",
    "After the season ends they still do. Cards that were not featured stay held back.",
    "Completion, the title and the pack reward arrive; claiming twice gives nothing extra.",
  ]],
  ["Trading and the rest", [
    "A trade or gift of a held-back card someone already owns still works, and the other player's binder view shows it.",
    "Wanted lists, chat links, sounds and the saved-progress sync behave as in the group-test table (docs/launch/V1-RELEASE.md).",
  ]],
];

// ---- this checkout ----

function checkout(options = {}) {
  const read = options.read || ((relative) => fs.readFileSync(path.join(root, relative), "utf8"));
  const items = [];
  const add = (name, ok, detail, kind) => items.push({ name, status: ok ? "ok" : kind || "fail", detail: detail || "" });
  const guard = (name, work) => { try { work(); } catch (error) { add(name, false, error instanceof Error ? error.message : String(error)); } };

  let versions = {};
  guard("the add-on, companion and server versions are set and the server's two environments agree", () => {
    const addon = /^## Version:\s*(\S+)/m.exec(read("AzerothCardBinder/AzerothCardBinder.toc"))[1];
    const app = JSON.parse(read("app/package.json")).version;
    const server = JSON.parse(read("server/package.json")).version;
    const toml = read("server/wrangler.toml");
    const deployed = [...toml.matchAll(/VERSION = "([\d.]+)"/g)].map((match) => match[1]);
    versions = { addon, app, server };
    add("the add-on, companion and server versions are set and the server's two environments agree",
      deployed.length === 2 && deployed.every((value) => value === server), `add-on ${addon}, companion ${app}, server ${server}; wrangler VERSION ${deployed.join(" and ")}`);
  });
  guard("the changelog has a section for this add-on version", () => {
    const log = read("CHANGELOG.md");
    add("the changelog has a section for this add-on version", new RegExp("^## " + versions.addon.replace(/\./g, "\\.") + "\\b", "m").test(log), versions.addon);
  });
  guard("the ledger protocol is the same in the rules, the server and the companion", () => {
    const rules = Number(/const SPEC_VERSION = (\d+);/.exec(read("packages/shared/src/ledger.js"))[1]);
    const supported = /SUPPORTED_SPEC_VERSIONS = \[([\d, ]+)\]/.exec(read("server/src/upload.ts"))[1].split(",").map(Number);
    const sent = Number(/specVersion: (\d+),/.exec(read("app/src/client.ts"))[1]);
    add("the ledger protocol is the same in the rules, the server and the companion", rules === Math.max(...supported) && rules === sent,
      `rules ${rules}, server accepts up to ${Math.max(...supported)}, companion sends ${sent}`);
    versions.protocol = rules;
  });
  guard("the catalog carries both sets of rates and the held-back list, and the committed list is what the rule gives", () => {
    const catalog = JSON.parse(read("packages/shared/catalog.json"));
    const base = Object.values(catalog.cards).filter((card) => !card.baseKey);
    const withRates = base.filter((card) => Number.isInteger(card.dropProfile.rate2)).length;
    const held = base.filter((card) => card.seasonal).length;
    const { draft, files } = require("./launch-collection.js");
    const out = files(catalog, draft(catalog));
    const same = [["docs/seasons/launch-collection-draft.json", out.json], ["docs/seasons/launch-collection-draft.csv", out.csv], ["AzerothCardBinder/LaunchCollection.lua", out.lua]]
      .every(([file, text]) => read(file).replace(/\r\n/g, "\n") === text);
    add("the catalog carries both sets of rates and the held-back list, and the committed list is what the rule gives",
      withRates === base.length && held === Math.ceil(base.length / 2) && same, `${withRates} of ${base.length} cards have rate2; ${held} held back; list ${same ? "current" : "OUT OF DATE (node tools/launch-collection.js --write)"}; catalog ${catalog.catalogVersion}`);
    versions.catalogVersion = catalog.catalogVersion;
  });
  guard("the minimum versions do not shut out this release", () => {
    const toml = read("server/wrangler.toml");
    const minClient = /MIN_CLIENT = "([\d.]+)"/.exec(toml)[1], minAddon = /MIN_ADDON = "([\d.]+)"/.exec(toml)[1];
    const atMost = (a, b) => a.split(".").map(Number).reduce((result, part, index) => result !== 0 ? result : part - Number(b.split(".")[index]), 0) <= 0;
    add("the minimum versions do not shut out this release", atMost(minClient, versions.app) && atMost(minAddon, versions.addon), `MIN_CLIENT ${minClient}, MIN_ADDON ${minAddon} (raise them about a week after release, not on the day)`);
  });
  guard("the next database migration is named", () => {
    const names = fs.readdirSync(path.join(root, "server", "migrations")).filter((name) => name.endsWith(".sql")).sort();
    versions.migration = names[names.length - 1];
    add("the next database migration is named", names.length > 0, `${names.length} migrations; the newest is ${versions.migration}: apply it to the database before deploying the code`, "info");
  });
  return { items, versions };
}

// ---- the deployed server ----

const HEX = (length) => "a".repeat(length);

async function deployed({ base, get, versions, wrangler, now = () => Math.floor(Date.now() / 1000) }) {
  const items = [];
  const add = (name, ok, detail, kind) => items.push({ name, status: ok ? "ok" : kind || "fail", detail: detail || "" });
  const guard = async (name, work) => { try { await work(); } catch (error) { add(name, false, error instanceof Error ? error.message : String(error)); } };
  const header = { "x-warcards-client": versions.app || "0.5.0", "content-type": "application/json" };
  const post = (route, body) => get(base + route, { method: "POST", headers: header, body: JSON.stringify(body) });
  const codeOf = async (response) => { try { return (await response.json()).error?.code; } catch { return undefined; } };

  await guard("the server is this release", async () => {
    const response = await get(base + "/v1/health");
    const health = await response.json();
    const sameServer = health.version === versions.server, sameCatalog = health.catalogVersion === versions.catalogVersion;
    add("the server is this release", response.status === 200 && health.ok === true && sameServer && sameCatalog,
      `server ${health.version} (this checkout ${versions.server}); catalog ${health.catalogVersion} (this checkout ${versions.catalogVersion})`);
  });

  await guard("the server accepts every ledger protocol this release uses and refuses the ones it does not", async () => {
    const wanted = versions.protocol || 9; // the newest protocol this checkout speaks
    const body = (specVersion) => ({ specVersion, key: HEX(64), character: "Walkthrough", realm: "Test", schema: 1, catalogVersion: versions.catalogVersion || "x",
      events: [], snapshot: { counts: {}, attempts: {}, dust: 0, sets: {}, titles: {} }, tapeIndex: 0, sentAt: 1, sig: HEX(128) });
    const outcomes = {};
    for (const spec of [1, 2, 5, 8, wanted, wanted + 1]) outcomes[spec] = await codeOf(await post("/v1/ledger", body(spec)));
    // A supported version is turned away only at the key (nobody is registered under it); an unsupported one at the version.
    const good = [2, 5, 8, wanted].every((spec) => outcomes[spec] === "unknown_key");
    const refused = outcomes[1] === "client_too_old" && outcomes[wanted + 1] === "client_too_old";
    add("the server accepts every ledger protocol this release uses and refuses the ones it does not", good && refused,
      Object.entries(outcomes).map(([spec, code]) => `${spec}: ${code}`).join(", "));
  });

  await guard("the seasons routes are in place and need a registered key", async () => {
    const response = await post("/v1/seasons", { key: HEX(64), sentAt: now(), sig: HEX(128) });
    const code = await codeOf(response);
    add("the seasons routes are in place and need a registered key", response.status === 401 && code === "unknown_key", `POST /v1/seasons answered ${response.status} ${code ?? ""}`);
  });

  await guard("the scheduling door is shut without credentials", async () => {
    const response = await get(base + "/v1/admin/seasons", { redirect: "manual" });
    const toAccess = response.status >= 300 && response.status < 400 && /cloudflareaccess\.com/i.test(response.headers.get("location") ?? "");
    add("the scheduling door is shut without credentials", response.status === 401 || response.status === 404 || toAccess, `GET /v1/admin/seasons answered ${response.status}`);
  });

  await guard("what the server announces", async () => {
    const releases = await (await get(base + "/v1/releases")).json();
    add("what the server announces", true, `companion ${releases.app?.latest} (minimum ${releases.app?.min}), add-on ${releases.addon?.latest} (minimum ${releases.addon?.min}), ${releases.signed ? "a signed manifest" : "no signed manifest yet"}`, "info");
  });

  if (wrangler) {
    await guard("no database migration is waiting", async () => {
      const result = wrangler();
      add("no database migration is waiting", result.ok, result.detail);
    });
  }
  return items;
}

// ---- a staging season ----

async function seasonDraft(file, { catalogPath = path.join(root, "packages", "shared", "catalog.json"), now = Date.now() } = {}) {
  const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  // Two plain held-back creature cards from the same page, so one place is enough to test them.
  const byPage = new Map();
  for (const set of catalog.sets) {
    const easy = set.cards.filter((key) => { const card = catalog.cards[key]; return card.seasonal && card.rank === "normal" && !card.boss && card.dropProfile.tier === "regular" && key.startsWith("npc:"); });
    if (easy.length >= 2 && set.group === "Zone") byPage.set(set, easy);
  }
  const [set, cards] = [...byPage.entries()].sort((a, b) => b[1].length - a[1].length || a[0].code.localeCompare(b[0].code))[0];
  const picked = cards.slice().sort().slice(0, 2);
  const when = (offsetSeconds) => new Date(Math.floor(now / 1000) * 1000 + offsetSeconds * 1000).toISOString().replace(/\.\d+Z$/, "Z");
  const draft = {
    id: "staging-walkthrough", title: "Staging Walkthrough",
    startsAt: when(15 * 60), endsAt: when(3 * 86400 + 15 * 60),
    selection: { mode: "manual", cards: picked },
    rewards: { completion: { title: "Walkthrough Tester", packs: [{ pack: set.code + ":common", count: 1 }] }, first: { places: 1, title: "First Through", packs: [] } },
  };
  // Check it the way the scheduler will.
  const { seasonDefinition } = await import("../server/src/seasons.ts");
  const season = await seasonDefinition({ ...draft, startsAt: Date.parse(draft.startsAt) / 1000, endsAt: Date.parse(draft.endsAt) / 1000 }, catalog, Math.floor(now / 1000));
  fs.writeFileSync(file, JSON.stringify(draft, null, 2) + "\n");
  return { draft, season, page: set.title, names: picked.map((key) => `${key}  ${catalog.cards[key].name}`) };
}

// ---- running it ----

function wranglerCheck(environment) {
  return () => {
    const result = spawnSync(process.platform === "win32" ? "npx.cmd" : "npx", ["wrangler", "d1", "migrations", "list", "DB", "--env", environment, "--remote"], { cwd: path.join(root, "server"), encoding: "utf8", shell: process.platform === "win32" });
    const text = (result.stdout || "") + (result.stderr || "");
    if (/No migrations to apply/i.test(text)) return { ok: true, detail: "every migration is applied" };
    const pending = [...text.matchAll(/(\d{4}_[a-z0-9_]+\.sql)/g)].map((match) => match[1]);
    if (/Migrations to be applied/i.test(text) && pending.length) return { ok: false, detail: "still to apply: " + [...new Set(pending)].join(", ") };
    return { ok: false, detail: "could not ask Cloudflare (" + (result.status === 0 ? "unexpected answer" : "is wrangler logged in?") + ")" };
  };
}

async function walkthrough(options = {}) {
  const sections = [];
  const here = checkout({ read: options.read });
  sections.push({ title: "This checkout", items: here.items });
  if (!options.offline) {
    const smokeItems = [];
    if (options.smoke !== false) {
      const run = options.smokeFn || require("./smoke.js").smoke;
      for (const result of await run({ base: options.base, ...(options.get ? { get: options.get } : {}), ...(options.smokeOptions || {}) })) {
        smokeItems.push({ name: result.name, status: result.ok ? "ok" : "fail", detail: result.detail });
      }
      sections.push({ title: "Smoke test (tools/smoke.js)", items: smokeItems });
    }
    sections.push({ title: "The deployed server, " + options.base, items: await deployed({ base: options.base, get: options.get || fetch, versions: here.versions, wrangler: options.wrangler, now: options.now }) });
  }
  return { sections, hand: HAND };
}

function print(report, write = console.log) {
  let failed = 0, total = 0;
  for (const section of report.sections) {
    write("\n" + section.title);
    for (const item of section.items) {
      total++;
      if (item.status === "fail") failed++;
      write("  " + ({ ok: "ok   ", fail: "FAIL ", info: "info " }[item.status] || item.status) + " " + item.name + (item.detail ? "  [" + item.detail + "]" : ""));
    }
  }
  write("\nBy hand: the rest needs people and a game client");
  for (const [title, lines] of report.hand) {
    write("\n  " + title);
    for (const line of lines) write("    [ ] " + line);
  }
  write("\n" + (failed === 0 ? "All " + total + " automated checks passed." : failed + " of " + total + " automated checks FAILED."));
  return failed;
}

module.exports = { checkout, deployed, seasonDraft, walkthrough, print, HAND };

if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    const option = (name) => (args.includes("--" + name) ? args[args.indexOf("--" + name) + 1] : undefined);
    const environment = option("env") || "staging";
    const base = (option("url") || SERVERS[environment] || "").replace(/\/$/, "");
    if (!args.includes("--offline") && !base) { console.error("Usage: node tools/staging-walkthrough.js [--env staging|production | --url <address>] [--offline] [--wrangler] [--no-smoke] [--season-draft <file>]"); process.exit(1); }
    console.log("Staging walkthrough" + (args.includes("--offline") ? " (this checkout only)" : " of " + base));
    const report = await walkthrough({ base, offline: args.includes("--offline"), smoke: !args.includes("--no-smoke"),
      wrangler: args.includes("--wrangler") && SERVERS[environment] ? wranglerCheck(environment) : undefined });
    const failed = print(report);
    const draftFile = option("season-draft");
    if (draftFile) {
      const made = await seasonDraft(path.resolve(draftFile));
      console.log("\nWrote a draft season to " + draftFile + ": it releases two held-back cards from " + made.page + ", starting in 15 minutes and running three days.");
      for (const line of made.names) console.log("    " + line);
      console.log("  Preview:   node tools/seasons.js preview " + draftFile);
      console.log("  Schedule:  node tools/seasons.js schedule " + draftFile + " --env staging   (WARCARDS_ADMIN_TOKEN in the environment; for Access also CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET)");
      console.log("  Then wait for it to start, let the companion sync, /reload, and go through \"A season releases cards\" above.");
    }
    process.exit(failed === 0 ? 0 : 1);
  })().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exit(1); });
}
