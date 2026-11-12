// The website: the ladder, a player's page, fair play and privacy. Plain, safe HTML made from the same data as the API.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { fairPlayHeadings, privacyHeadings } from "../src/site.ts";
import { NOW, catalog, chainedHistory, newPlayer, rankedHistory, registration, setup, signedUpload } from "./harness.ts";

const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

async function rankedPlayer(env: ReturnType<typeof setup>, name: string) {
  const player = newPlayer(name);
  const registered = (await (await env.call("/v1/register", { body: registration(player) })).json()) as { playerId: string };
  const request = { key: player.publicKeyHex, sentAt: NOW };
  await env.call("/v1/tape", { body: { ...request, sig: reference.signBatch({ ...request, purpose: "tape" }, player.privateKey) } });
  const { events, tapeNext, attempts } = await rankedHistory(registered.playerId, 3, "npc:589", `${name}-RealmName`);
  const response = await env.call("/v1/ledger", { body: signedUpload(player, events, { character: name, realm: "RealmName", tapeIndex: tapeNext, snapshot: { counts: { "npc:589": 3 }, dust: 0, sets: {}, attempts: { "npc:589": attempts }, titles: {} } }) });
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  return { player, id: registered.playerId };
}
const page = async (env: ReturnType<typeof setup>, path: string) => { const response = await env.call(path); return { response, text: await response.text() }; };

test("the ladder page lists ranked players, links to them, and says plainly when there are none", async () => {
  const env = setup();
  const empty = await page(env, "/ladder");
  assert.equal(empty.response.status, 200);
  assert.match(empty.response.headers.get("content-type") ?? "", /^text\/html; charset=utf-8/);
  assert.match(empty.text, /Nobody is on the ladder yet/);
  assert.match(empty.text, /<title>World of Warcards: the ladder<\/title>/);

  const alice = await rankedPlayer(env, "Alice");
  const full = await page(env, "/ladder");
  assert.match(full.text, new RegExp(`<a href="/player/${alice.id}">Alice-RealmName</a>`));
  assert.match(full.text, /<td class="num">1<\/td>/);
  assert.ok(!full.text.includes("Nobody is on the ladder yet"));
  // A player with Casual drops is stored but not listed.
  const casual = newPlayer("casual");
  await env.call("/v1/register", { body: registration(casual) });
  await env.call("/v1/ledger", { body: signedUpload(casual, chainedHistory(), { character: "Casual", realm: "RealmName" }) });
  assert.ok(!(await page(env, "/ladder")).text.includes("Casual-RealmName"));
});

test("pages carry safety headers, load nothing from anywhere else and run no script", async () => {
  const env = setup();
  await rankedPlayer(env, "Alice");
  for (const path of ["/", "/ladder", "/wanted", "/download", "/help", "/faq", "/fair-play", "/privacy", "/code-signing-policy"]) {
    const { response, text } = await page(env, path);
    assert.equal(response.status, 200, path);
    assert.match(response.headers.get("content-security-policy") ?? "", /default-src 'none'/);
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.equal(response.headers.get("x-frame-options"), "DENY");
    assert.equal(response.headers.get("cache-control"), "public, max-age=60");
    assert.ok(!/<script/i.test(text), `${path} has a script`);
    // Nothing is ever loaded from another site; the only links out go to the project's own GitHub (issues, releases, downloads).
    assert.ok(!/src="https?:/i.test(text), `${path} loads something from another site`);
    // (and, on the code signing policy page, to the code signing service it names)
    const allowed = ["https://github.com/Imokim2/azeroth-card-binder", "https://github.com/Imokim2", "https://github.com/harrydexter18-afk", "https://signpath.io", "https://signpath.org"];
    assert.ok(![...text.matchAll(/href="(https?:[^"]*)"/gi)].some((link) => !allowed.some((prefix) => (link[1] as string).startsWith(prefix))), `${path} links to another site`);
    assert.match(text, /not affiliated with or endorsed by Blizzard/);
    assert.match(text, /<meta name="viewport"/);
  }
});

test("a name from a player can never become markup", async () => {
  const env = setup();
  const alice = await rankedPlayer(env, "Alice");
  const nasty = `<img src=x onerror=alert(1)>"'&<script>alert(2)</script>`;
  env.raw.prepare("UPDATE scores SET display_name = ? WHERE player_id = ?").run(nasty, alice.id);
  env.raw.prepare("INSERT INTO set_completions (set_code, player_id, t, received_at) VALUES ('DM', ?, 1, ?)").run(alice.id, NOW);
  for (const path of ["/ladder", `/player/${alice.id}`]) {
    const { text } = await page(env, path);
    assert.ok(!text.includes("<img src=x"), `${path} let a tag through`);
    assert.ok(!text.includes("<script>alert"), `${path} let a script through`);
    assert.ok(text.includes("&lt;img src=x onerror=alert(1)&gt;&quot;&#39;&amp;&lt;script&gt;"), `${path} should show the name as text`);
  }
});

test("a player's page shows the sets and cards on their binder, and is the same not-found for everyone who may not be shown", async () => {
  const env = setup();
  const alice = await rankedPlayer(env, "Alice");
  const { response, text } = await page(env, `/player/${alice.id}`);
  assert.equal(response.status, 200);
  const card = catalog.cards["npc:589"]!;
  assert.ok(text.includes(card.name), "the card they hold");
  assert.match(text, /<details><summary>[^<]+: 1 of \d+<\/summary>/);
  assert.match(text, /x3/, "three copies");
  assert.match(text, /Rank<\/dt><dd>#1/);
  // Unknown, private, held, banned and Casual players all look the same.
  const notFound = async (path: string) => { const result = await page(env, path); assert.equal(result.response.status, 404, path); return result.text; };
  const unknown = await notFound("/player/01ARZ3NDEKTSV4RRFFQ69G5FAV");
  env.raw.prepare("UPDATE players SET visibility = 'private' WHERE id = ?").run(alice.id);
  assert.equal(await notFound(`/player/${alice.id}`), unknown);
  env.raw.prepare("UPDATE players SET visibility = 'public', status = 'banned' WHERE id = ?").run(alice.id);
  assert.equal(await notFound(`/player/${alice.id}`), unknown);
  env.raw.prepare("UPDATE players SET status = 'active' WHERE id = ?").run(alice.id);
  env.raw.prepare("UPDATE ledger_state SET casual_drops = 1 WHERE player_id = ?").run(alice.id);
  assert.equal(await notFound(`/player/${alice.id}`), unknown);
  assert.equal((await env.call("/player/not-an-id")).status, 404);
  assert.equal((await env.call("/player/" + alice.id, { method: "POST", body: {} })).status, 405);
  assert.equal((await env.call("/privacy", { method: "POST", body: {} })).status, 405);
});

test("the fair-play and privacy pages say what they must, and the privacy page matches the written draft", async () => {
  const env = setup();
  const fair = (await page(env, "/fair-play")).text;
  for (const heading of fairPlayHeadings) assert.ok(fair.includes(`<h2>${heading}</h2>`), heading);
  assert.match(fair, /Do not edit your collection/);
  assert.doesNotMatch(fair, /roll tape|random numbers|hash.chain|read ahead|within a week|statistical/i);
  assert.match(fair, /only <strong>Ranked<\/strong>/i);
  const privacy = (await page(env, "/privacy")).text;
  for (const heading of privacyHeadings) assert.ok(privacy.includes(`<h2>${heading}</h2>`), heading);
  // The draft in docs/PRIVACY.md and the page cover the same sections, so one cannot drift from the other unnoticed.
  const draft = readFileSync(new URL("../../docs/PRIVACY.md", import.meta.url), "utf8");
  const written = [...draft.matchAll(/^## (.+)$/gm)].map((match) => match[1]);
  assert.deepEqual(written, [...privacyHeadings]);
  assert.match(privacy, /Delete my data/);
  assert.match(privacy, /banned account.s record is kept/);
});
