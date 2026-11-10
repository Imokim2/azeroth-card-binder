"use strict";
// The shared catalog (packages/shared/catalog.json) must match the add-on's Lua catalog and be internally consistent.
// Run: node --test tests/catalog.test.js
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { build } = require("../tools/build-catalog-json.js");

const committed = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "packages", "shared", "catalog.json"), "utf8"));

test("the committed catalog is exactly what the generator writes from the Lua files", () => {
    assert.deepStrictEqual(committed, build(), "run: node tools/build-catalog-json.js and commit the result");
    assert.match(committed.catalogVersion, /^[0-9a-f]{12}$/);
});

test("every card is in exactly one set, and every set lists real cards", () => {
    const owner = new Map();
    for (const set of committed.sets) {
        assert.ok(set.cards.length > 0, `${set.code} has no cards`);
        for (const key of set.cards) {
            assert.ok(committed.cards[key], `${set.code} lists ${key}, which is not a card`);
            assert.ok(!owner.has(key), `${key} is in both ${owner.get(key)} and ${set.code}`);
            owner.set(key, set.code);
            assert.strictEqual(committed.cards[key].set, set.code);
        }
    }
    assert.strictEqual(owner.size, Object.keys(committed.cards).length);
    assert.strictEqual(new Set(committed.sets.map((set) => set.code)).size, committed.sets.length, "set codes are unique");
});

test("every card has what the ledger rules need: a name, a known rarity and a known rank", () => {
    for (const [key, card] of Object.entries(committed.cards)) {
        assert.match(key, /^(npc|node):\d+$/);
        assert.ok(card.name && !/[|\r\n]/.test(card.name), `${key} has a bad name`);
        assert.ok(committed.dust.recycle[card.rarity] > 0, `${key}: no dust value for ${card.rarity}`);
        assert.strictEqual(committed.dust.craft[card.rarity], committed.dust.recycle[card.rarity] * 10);
        assert.ok(committed.rates[card.rank] > 0, `${key}: no rate for ${card.rank}`);
    }
    assert.ok(committed.shinyOdds >= 1);
});
