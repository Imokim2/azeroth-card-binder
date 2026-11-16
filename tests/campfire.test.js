"use strict";
// Ledger spec 12 (docs/CAMPFIRE.md): mode/camp1, the camp event and boosted attempts. Standing at a camp with its buff doubles the chance of a card
// drop; an attempt made under the buff is written with partner "camp". The server cannot see the camp, so the ledger only keeps the claims honest
// in shape: how long the buff can last, that a boosted drop falls within the claim, and that a boosted attempt counts double in the luck statistics.
const assert = require("node:assert/strict");
const test = require("node:test");
const rules = require("../packages/shared/src/rules.js");
const ledger = require("../packages/shared/src/ledger.js");
const catalog = require("../packages/shared/catalog.json");

const card = "npc:589";
const build = (steps) => steps.map((step, index) => ({
    seq: index + 1, t: 1000 + index * 10, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Ann-Realm", count: 0, ...step,
}));
const mode = (key, extra = {}) => ({ kind: "mode", key, ...extra });
const markers = ["chase1", "chase2", "launch1", "faction1", "camp1"].map((key) => mode(key));
const ranked = mode("ranked2");
const camp = (key, count, extra = {}) => ({ kind: "camp", key, count, ...extra });
const drop = (count, tape, extra = {}) => ({ kind: "drop", key: card, count, tape, ...extra });
const miss = (count, tape, extra = {}) => ({ kind: "miss", key: card, count, tape, ...extra });
const rule = (...steps) => { const result = rules.replay(build(steps.flat()), catalog); return result.ok ? null : result.rule; };
const state = (...steps) => { const result = rules.replay(build(steps.flat()), catalog); assert.equal(result.ok, true, JSON.stringify(result)); return result.state; };

test("a camp claim and a boosted drop replay, and the state remembers the window", () => {
    // t is 1000 + 10 per event: the camp event is the 7th (t 1060), so a violet claim of 7200 seconds reaches 8260.
    const made = state(markers, ranked, camp("violet", 7200), drop(1, 1, { partner: "camp" }));
    assert.equal(made.camp, 1);
    assert.equal(made.campEnd, 1060 + 7200);
    assert.equal(made.campBoosted, 1);
    assert.equal(made.counts[card], 1);
    const welcoming = state(markers, ranked, camp("welcoming", 3600));
    assert.equal(welcoming.campEnd, 1060 + 3600);
    // A later claim reaches further; an earlier one never shortens it.
    const longer = state(markers, ranked, camp("violet", 7200), camp("welcoming", 60));
    assert.equal(longer.campEnd, 1060 + 7200);
});

test("a boosted attempt counts double in the luck statistics, and a plain one counts once", () => {
    // The first drop of a card starts its statistics; after that every attempt is counted.
    const plain = state(markers, ranked, drop(1, 1), miss(1, 2), drop(2, 3));
    assert.equal(plain.balanceAttempts[card], 2); // the miss and the drop after the first
    const boosted = state(markers, ranked, camp("violet", 7200), drop(1, 1), miss(2, 3, { partner: "camp" }), drop(2, 4, { partner: "camp" }));
    assert.equal(boosted.balanceAttempts[card], 2 * 2 + 1 * 2, "two boosted misses and a boosted drop, each counted twice");
    assert.equal(boosted.campBoosted, 3, "the boosted attempts themselves, once each");
});

test("mode/camp1 comes once, after faction1, and carries no count", () => {
    assert.equal(rule(markers), null);
    assert.equal(rule(markers.slice(0, 4), mode("camp1"), mode("camp1")), "mode");
    assert.equal(rule(markers.slice(0, 3), mode("camp1")), "mode", "not before faction1");
    assert.equal(rule(markers.slice(0, 4), mode("camp1", { count: 1 })), "mode");
    assert.equal(rule(mode("camp1")), "mode");
});

test("a camp claim needs camp1, Ranked, a known buff and a length the buff can have", () => {
    assert.equal(rule(markers.slice(0, 4), ranked, camp("violet", 60)), "camp", "before camp1");
    assert.equal(rule(markers, camp("violet", 60)), "camp", "in Casual");
    assert.equal(rule(markers, ranked, camp("welcoming", 3601)), "camp", "the welcoming buff lasts an hour");
    assert.equal(rule(markers, ranked, camp("welcoming", 3600)), null);
    assert.equal(rule(markers, ranked, camp("violet", 7201)), "camp", "the violet one lasts two");
    assert.equal(rule(markers, ranked, camp("violet", 7200)), null);
    assert.equal(rule(markers, ranked, camp("violet", 0)), "camp");
    assert.equal(rule(markers, ranked, camp("fireside", 60)), "camp", "no other buff");
    assert.equal(rule(markers, ranked, camp("violet", 60, { shiny: 1 })), "field");
    assert.equal(rule(markers, ranked, camp("violet", 60, { tape: 1 })), "field");
    assert.equal(rule(markers, ranked, camp("violet", 60, { dust: 1 })), "dust");
    assert.equal(rule(markers, ranked, camp("violet", 60, { partner: "camp" })), "trade");
    assert.equal(rule(markers, ranked, camp("violet", 60, { trade: "x" })), "trade");
});

test("a boosted attempt needs camp1 and Ranked, and a boosted drop falls within the claimed buff", () => {
    assert.equal(rule(markers.slice(0, 4), ranked, drop(1, 1, { partner: "camp" })), "camp", "before camp1");
    assert.equal(rule(markers, ranked, drop(1, 1, { partner: "camp" })), "camp", "with no claim at all");
    assert.equal(rule(markers, [mode("casual")], drop(1, 0, { partner: "camp" })), "camp", "Casual rolls are not recorded as boosted");
    // The claim reaches 1060 + 120 = 1180. A drop at t 1070 is inside; one more than the grace past it is not.
    assert.equal(rule(markers, ranked, camp("violet", 120), drop(1, 1, { partner: "camp" })), null);
    const late = build([...markers, ranked, camp("violet", 120), drop(1, 1, { partner: "camp" })]);
    late[late.length - 1].t = 1060 + 120 + 120;
    assert.equal(rules.replay(late, catalog).ok, true, "the grace is two minutes");
    late[late.length - 1].t = 1060 + 120 + 121;
    assert.equal(rules.replay(late, catalog).rule, "camp");
    // A run of misses says nothing about when its attempts were made, so only its roll check (on the server) holds it.
    const run = build([...markers, ranked, camp("violet", 60), miss(2, 2, { partner: "camp" })]);
    run[run.length - 1].t = 99999;
    assert.equal(rules.replay(run, catalog).ok, true);
    assert.equal(rule(markers, ranked, camp("violet", 600), drop(1, 0, { partner: "camp" })), "camp", "a boosted attempt uses a tape entry");
    assert.equal(rule(markers, ranked, camp("violet", 600), drop(1, 1, { partner: "camp", trade: "x" })), "trade");
    assert.equal(rule(markers, ranked, camp("violet", 600), drop(1, 1, { partner: "party" })), "trade", "no other partner on a drop");
});

test("only common and rare cards are boosted: an elite, a rare spawn or a boss is refused as boosted", () => {
    const epic = "npc:10000", legendary = "npc:10162", common = "npc:589";
    assert.equal(catalog.cards[epic].rarity, "epic");
    assert.equal(catalog.cards[legendary].rarity, "legendary");
    for (const key of [epic, legendary]) {
        assert.equal(rule(markers, ranked, camp("violet", 600), { kind: "drop", key, count: 1, tape: 1, partner: "camp" }), "camp", key + " drop");
        assert.equal(rule(markers, ranked, camp("violet", 600), { kind: "miss", key, count: 2, tape: 2, partner: "camp" }), "camp", key + " miss");
        assert.equal(rule(markers, ranked, camp("violet", 600), { kind: "drop", key, count: 1, tape: 1 }), null, "the same attempt unboosted is fine");
    }
    assert.equal(rule(markers, ranked, camp("violet", 600), { kind: "drop", key: common, count: 1, tape: 1, partner: "camp" }), null);
    assert.deepEqual(rules.CAMP_RARITIES, ["common", "rare"]);
});

test("the state carries across batches: replaying in two parts gives the same state", () => {
    const events = build([...markers, ranked, camp("violet", 7200), drop(1, 1, { partner: "camp" }), miss(1, 2, { partner: "camp" })]);
    const whole = rules.replay(events, catalog);
    const first = rules.replay(events.slice(0, 8), catalog);
    const second = rules.replay(events.slice(8), catalog, first.state);
    assert.equal(whole.ok && first.ok && second.ok, true);
    assert.deepEqual(second.state, whole.state);
});

test("spec 12 is the current version and the camp kind is listed", () => {
    assert.ok(ledger.SPEC_VERSION >= 12);
    assert.ok(ledger.KINDS.includes("camp"));
    assert.deepEqual(rules.CAMP_SECONDS, { welcoming: 3600, violet: 7200 });
    assert.equal(rules.CAMP_FACTOR, 2);
});
