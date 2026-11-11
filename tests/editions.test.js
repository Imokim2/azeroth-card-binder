"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const reference = require("../packages/shared/src/ledger.js");
const { replay, newState } = require("../packages/shared/src/rules.js");
const { pickEdition, familyCount } = require("../packages/shared/src/editions.js");
const catalog = require("../packages/shared/catalog.json");
const root = path.resolve(__dirname, "..");
const harness = import("../server/test/harness.ts");
function play(tapePath) {
    const result = spawnSync(process.env.LUAJIT || "luajit", ["tests/tools/play-editions.lua", ...(tapePath ? [tapePath] : [])], { cwd: root, encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
}
const snapshot = (run) => ({ counts: run.counts, dust: run.dust, sets: run.sets, attempts: run.attempts, titles: {} });
async function rankedScenario() {
    const h = await harness, env = h.setup(), player = h.newPlayer("edition-player");
    // A fixed fixture id makes the HMAC tape repeatable, independent of ULID randomness.
    await env.store.registerKey({ discordId: "edition-player", key: player.publicKeyHex, visibility: "public", at: h.NOW,
        newPlayerId: "01ARZ3NDEKTSV4RRFFQ69G5FAV" });
    const request = { key: player.publicKeyHex, sentAt: h.NOW };
    const response = await env.call("/v1/tape", { body: { ...request, sig: reference.signBatch({ ...request, purpose: "tape" }, player.privateKey) } });
    const tape = await response.json();
    const folder = await fs.mkdtemp(path.join(os.tmpdir(), "warcards-editions-"));
    const tapePath = path.join(folder, "entries.lua");
    try {
        await fs.writeFile(tapePath, "return {" + tape.entries.map((entry) => JSON.stringify(entry)).join(",") + "}");
        return { h, env, player, run: play(tapePath) };
    } finally { await fs.rm(folder, { recursive: true, force: true }); }
}

test("edition selection boundaries preserve Signature and two independently owned variants", () => {
    assert.equal(pickEdition(catalog, "npc:4832", 1), "edition:48321");
    assert.equal(pickEdition(catalog, "npc:4832", 150), "edition:48321");
    assert.equal(pickEdition(catalog, "npc:4832", 151), "edition:48322");
    assert.equal(pickEdition(catalog, "npc:4832", 200), "edition:48322");
    assert.equal(pickEdition(catalog, "npc:4832", 201), "npc:4832");
    assert.equal(pickEdition(catalog, "npc:4832", 1000), "npc:4832");
    assert.equal(familyCount(catalog, { "edition:48321": 1, "edition:48322": 2 }, "npc:4832"), 3);
});

test("real addon edition drops, dust and a Blackfathom completion verify and upload intact", async () => {
    const run = play();
    assert.equal(reference.verifyChain(run.events).ok, true);
    const result = replay(run.events, catalog);
    assert.equal(result.ok, true, JSON.stringify(result));
    const bfd = catalog.cards["npc:4832"].set;
    assert.equal(result.state.sets[bfd], true);
    assert.equal(result.state.counts["edition:48321"], 1);
    assert.equal(result.state.counts["npc:4832"] || 0, 0);
    assert.equal(result.state.counts["edition:48291"], 1);
    assert.ok(run.events.some((event) => event.kind === "recycle" && event.key === "edition:48321"));
    const h = await harness, env = h.setup(), player = h.newPlayer("casual-editions");
    await env.call("/v1/register", { body: h.registration(player) });
    const response = await env.call("/v1/ledger", { body: h.signedUpload(player, run.events, { specVersion: 4, snapshot: snapshot(run) }) });
    assert.equal(response.status, 200, await response.text());
});

test("Ranked edition choices made by real Lua agree with the server across upload boundaries", async () => {
    const { h, env, player, run } = await rankedScenario();
    assert.ok(Object.keys(run.counts).some((key) => key.startsWith("edition:")), "the scenario must actually find an alternate edition");
    const split = run.events.findIndex((event) => event.kind === "drop") + 1;
    const first = run.events.slice(0, split), lastTape = first.at(-1).tape;
    const state = replay(first, catalog);
    assert.equal(state.ok, true);
    const upload = async (events, counts, dust, sets, tapeIndex) => {
        const response = await env.call("/v1/ledger", { body: h.signedUpload(player, events, { specVersion: 4, tapeIndex,
            snapshot: { counts, dust, sets, attempts: run.attempts, titles: {} } }) });
        assert.equal(response.status, 200, await response.text());
    };
    await upload(first, state.state.counts, state.state.dust, state.state.sets, lastTape + 1);
    await upload(run.events.slice(split), run.counts, run.dust, run.sets, run.tapeIndex);
});

test("a correctly signed but substituted Ranked edition is rejected by the issued roll", async () => {
    const { h, env, player, run } = await rankedScenario();
    const end = run.events.findIndex((event) => event.kind === "drop") + 1;
    const partials = run.events.slice(0, end).map(({ prev, h, ...event }) => event);
    const drop = partials.at(-1);
    drop.key = drop.key === "edition:48322" ? "edition:48321" : "edition:48322";
    const events = h.chain(partials);
    const response = await env.call("/v1/ledger", { body: h.signedUpload(player, events, { specVersion: 4, tapeIndex: drop.tape + 1,
        snapshot: { counts: { [drop.key]: 1 }, dust: 0, sets: {}, attempts: run.attempts, titles: {} } }) });
    const body = await response.json();
    assert.equal(body.error.code, "tape_invalid");
    assert.equal(body.error.detail.reason, "edition");
});

test("an edition cannot be crafted and collecting every edition does not inflate base-card scoring", async () => {
    const run = play(), craft = { ...run.events[1], seq: 1, kind: "craft", key: "edition:48321", count: 1, dust: -50 };
    assert.equal(replay([craft], catalog).rule, "edition");
    const { scoreOf } = await import("../server/src/score.ts");
    const state = newState();
    state.counts = { "npc:639": 1, "edition:6391": 2, "edition:6392": 1 };
    assert.deepEqual(scoreOf(catalog, state), { score: 100, uniqueCards: 1, setsDone: 0 });
});

test("Ranked pack cards validate the edition as well as the selected creature", async () => {
    const { tapeKey, tapeEntry, editionValue, shinyValue, checkTape } = await import("../server/src/tape.ts");
    const { TAPE_SECRET } = await harness;
    const key = await tapeKey(TAPE_SECRET), playerId = "pack-edition-test";
    // A single-creature pool isolates edition selection from the rarity/card draws.
    const fixture = { ...catalog, sets: [{ code: "DM", cards: ["npc:639"] }] };
    let position = 0, entry, chosen;
    do {
        position++;
        entry = await tapeEntry(key, playerId, position);
        chosen = pickEdition(fixture, "npc:639", await editionValue(entry));
    } while (chosen === "npc:639" && position < 100);
    assert.notEqual(chosen, "npc:639");
    const state = { ...newState(), mode: "ranked2", editions: true, packZone: "DM", packLeft: 1, lastTape: position - 1 };
    const event = { seq: 1, t: 1, kind: "packCard", key: chosen, count: 1, tape: position, shiny: shinyValue(entry, catalog.shinyOdds) === 1 ? 1 : 0 };
    const check = (item) => checkTape({ key, playerId, events: [item], stateBefore: state, catalog: fixture, issuedEnd: position, stack: {}, tapeNext: position + 1 });
    assert.equal((await check(event)).failure, null);
    assert.equal((await check({ ...event, key: "npc:639" })).failure.reason, "pack");
});
