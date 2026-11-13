"use strict";
// The DRAFT smaller-launch-collection split (docs/proposals/SMALLER-LAUNCH-COLLECTION.md): the rule keeps what it says it keeps,
// is exactly half, is repeatable, and the committed draft files are what the rule produces from the current catalog.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const catalog = require("../packages/shared/catalog.json");
const { draft, files } = require("../tools/launch-collection.js");

const base = Object.keys(catalog.cards).filter((key) => !catalog.cards[key].baseKey);

test("the launch collection is exactly half of the base cards, and every held-back card is a real base card", () => {
    const result = draft(catalog);
    assert.equal(result.launch.length, Math.floor(base.length / 2));
    assert.equal(result.launch.length + result.seasons.length, base.length);
    assert.deepEqual([...result.launch, ...result.seasons].sort(), [...base].sort());
    assert.equal(new Set([...result.launch, ...result.seasons]).size, base.length, "no card is in both lists");
});

test("every elite, rare-elite, boss, critter and gathering card stays; chase cards on ordinary creatures are held back unless asked", () => {
    const result = draft(catalog);
    const launch = new Set(result.launch);
    for (const key of base) {
        const card = catalog.cards[key];
        if (card.rank === "elite" || card.rank === "rareelite" || card.boss || card.dropProfile.tier === "critter" || card.rank === "gathering") {
            assert.ok(launch.has(key), key + " " + card.name + " must stay at launch");
        }
        if (card.dropProfile.tier === "chase" && card.rank === "normal") assert.ok(!launch.has(key), key + " is held back by default");
    }
    const kept = new Set(draft(catalog, { chase: "keep" }).launch);
    for (const key of base) {
        const card = catalog.cards[key];
        if (card.dropProfile.tier === "chase" && card.rank === "normal") assert.ok(kept.has(key), key + " stays with --chase keep");
    }
    assert.equal(kept.size, result.launch.length, "still exactly half");
});

test("every page keeps a card at launch, the split repeats exactly, and it does not depend on the order of the cards", () => {
    const result = draft(catalog);
    for (const [code, page] of Object.entries(result.byPage)) assert.ok(page.launch > 0, code + " " + page.title + " would be empty at launch");
    assert.deepEqual(draft(catalog), result);
    const shuffled = JSON.parse(JSON.stringify(catalog));
    shuffled.sets = [...shuffled.sets].reverse().map((set) => ({ ...set, cards: [...set.cards].reverse() }));
    assert.deepEqual(draft(shuffled).launch.slice().sort(), result.launch.slice().sort());
});

test("the committed draft files are what the rule produces from the current catalog", () => {
    const out = files(catalog, draft(catalog));
    const dir = path.join(__dirname, "..", "docs", "seasons");
    const read = (name) => fs.readFileSync(path.join(dir, name), "utf8").replace(/\r\n/g, "\n");
    const how = " is out of date: run `node tools/launch-collection.js --write` (or delete the draft if the proposal was adopted or dropped)";
    assert.equal(read("launch-collection-draft.json"), out.json, "launch-collection-draft.json" + how);
    assert.equal(read("launch-collection-draft.csv"), out.csv, "launch-collection-draft.csv" + how);
});
