"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const catalog = require("../packages/shared/catalog.json");
const published = require("./fixtures/spec9-packs.json");
const { newState, applyEvent } = require("../packages/shared/src/rules.js");
const { packPick } = require("../packages/shared/src/packs.js");

const event = (kind, key, count = 0) => ({ kind, key, count, char: "Upgrade-Realm", t: 1000, tape: 0, dust: 0, shiny: 0, partner: "", trade: "" });

test("a previously valid launch find remains valid until the faction marker, then uses the new list", () => {
    const state = { ...newState(), launch: 1 };
    assert.equal(applyEvent(state, event("drop", "npc:598", 1), catalog, false, () => false), null, "Defias Miner was available in 1.0.13");
    state.faction = 1; state.sides = {};
    assert.equal(applyEvent(state, event("drop", "npc:598", 2), catalog, false, () => false), "retired", "new finds follow the new held-back list");
    assert.equal(state.counts["npc:598"], 1, "the earlier copy remains owned");
});

test("all frozen published pack results survive the catalog upgrade before mode/faction1", () => {
    assert.equal(published.sourceCatalogVersion, "3d0b62359bee");
    assert.equal(published.cases.length, 336);
    for (const row of published.cases) {
        const allowed = key => {
            const card = catalog.cards[key];
            return !card.since && (!row.launched || !(card.seasonalBeforeFaction ?? card.seasonal));
        };
        assert.equal(packPick(catalog, row.zone, row.entry, catalog.shinyOdds, row.balanced, allowed), row.expected,
            `${row.zone} / ${row.entry} / launch ${row.launched} / rates ${row.balanced}`);
    }
});

test("previously completed pages replay against their original requirements", () => {
    const changed = catalog.sets.filter(set => set.requiredBeforeFaction);
    assert.equal(changed.length, 14);
    for (const set of changed) {
        const state = { ...newState(), launch: 1, counts: Object.fromEntries(set.requiredBeforeFaction.map(key => [key, 1])) };
        assert.equal(applyEvent(state, event("set", set.code), catalog), null, set.code);
        assert.equal(state.sets[set.code], true);
    }
    const expanded = changed.find(set => (set.required || set.cards).some(key => !set.requiredBeforeFaction.includes(key)));
    assert.ok(expanded);
    const upgraded = { ...newState(), launch: 1, faction: 1, sides: {}, counts: Object.fromEntries(expanded.requiredBeforeFaction.map(key => [key, 1])) };
    assert.equal(applyEvent(upgraded, event("set", expanded.code), catalog), "set", "new completions need the current list");
});
