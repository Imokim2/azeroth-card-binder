"use strict";
// The Fellowship cards (docs/FELLOWSHIP.md, ledger spec 12): four cards earned only by completing an activity. mode/fellow1 starts the count; each activity
// event earns one roll for its card (a swap earns a trade, an unpaired tradeOut or tradeIn a gift, a donation a donation, a camp claim a camp), and each drop
// or run of misses on an activity card spends them.
const assert = require("node:assert/strict");
const test = require("node:test");
const rules = require("../packages/shared/src/rules.js");
const { chanceFor } = require("../packages/shared/src/drops.js");
const catalog = require("../packages/shared/catalog.json");

const [TRADER, GIFTER, BENEFACTOR, FIRESIDE] = ["npc:900000001", "npc:900000002", "npc:900000003", "npc:900000004"];
const GUILD = "01HF7YAT00QKSEP5RCNMPTQ3KN";
const build = (steps) => steps.map((step, index) => ({
    seq: index + 1, t: 1000 + index * 10, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Ann-Realm", count: 0, ...step,
}));
const mode = (key) => ({ kind: "mode", key });
const base = ["chase1", "chase2", "launch1", "faction1"].map(mode);
const fellow = [...base, mode("fellow1"), mode("ranked2")];
let ids = 0;
const out = (key, count, trade) => ({ kind: "tradeOut", key, count, partner: "bob-realm", trade });
const into = (key, count, trade) => ({ kind: "tradeIn", key, count, partner: "bob-realm", trade });
const swap = (give, take) => { const id = "swap" + ++ids; return [out(give, 0, id), into(take, 1, id)]; };
const owned = (key) => ({ kind: "tradeIn", key, count: 1, partner: "bob-realm", trade: "own" + ++ids });
const drop = (key, count, tape, extra = {}) => ({ kind: "drop", key, count, tape, ...extra });
const miss = (key, count, tape, extra = {}) => ({ kind: "miss", key, count, tape, ...extra });
const result = (steps) => rules.replay(build(steps.flat()), catalog);
const rule = (...steps) => { const r = result(steps); return r.ok ? null : r.rule; };
const credits = (...steps) => { const r = result(steps); assert.equal(r.ok, true, JSON.stringify(r)); return r.state.credits; };

test("the Fellowship set is four cards, each tied to an activity, flat at one in a hundred", () => {
    const set = catalog.sets.find((entry) => entry.code === "FW");
    assert.deepEqual(set.cards.slice().sort(), [TRADER, GIFTER, BENEFACTOR, FIRESIDE].sort());
    assert.equal(set.required, undefined, "a page needs all four");
    assert.deepEqual([TRADER, GIFTER, BENEFACTOR, FIRESIDE].map((key) => catalog.cards[key].activity), ["trade", "gift", "donate", "camp"]);
    for (const key of set.cards) {
        const card = catalog.cards[key];
        assert.equal(card.since, 12);
        assert.equal(card.rarity, "rare");
        assert.equal(card.seasonal, undefined);
        assert.equal(card.faction, undefined);
        assert.deepEqual([card.dropProfile.style, card.dropProfile.rate, card.dropProfile.rate2], ["flat", 100, 100]);
        // No build-up after misses, in any generation.
        for (const balanced of [false, true, 2]) for (const misses of [0, 1, 50, 500]) assert.equal(chanceFor(catalog, key, misses, balanced), balanced ? 100 : 0, `${key} ${balanced} ${misses}`);
    }
});

test("a swap earns a trade roll, an unpaired tradeOut or tradeIn a gift roll, and nothing is earned before mode/fellow1", () => {
    assert.deepEqual(credits(fellow), { trade: 0, gift: 0, donate: 0, camp: 0 });
    assert.deepEqual(credits(fellow, owned("npc:589"), swap("npc:589", "npc:590")), { trade: 1, gift: 1, donate: 0, camp: 0 }, "the owned card came in as a gift; the swap is a trade");
    assert.deepEqual(credits(fellow, owned("npc:589"), out("npc:589", 0, "g1")), { trade: 0, gift: 2, donate: 0, camp: 0 }, "gifts given and received are both gifts");
    // Nothing earned before the marker: the same events in a binder that has not recorded fellow1.
    const before = result([...base, mode("ranked2"), owned("npc:589"), swap("npc:589", "npc:590")]);
    assert.equal(before.ok, true);
    assert.equal(before.state.credits, undefined);
    assert.equal(rule(base, mode("ranked2"), owned("npc:589"), swap("npc:589", "npc:590"), drop(TRADER, 1, 1)), "activity");
    // Both sides of a swap hold a pair, but a tradeIn that is not straight after its tradeOut is a gift, not a swap.
    const apart = credits(fellow, owned("npc:589"), out("npc:589", 0, "t9"), owned("npc:590"), into("npc:114", 1, "t9"));
    assert.deepEqual(apart, { trade: 0, gift: 4, donate: 0, camp: 0 });
    // A tradeIn with a different trade id straight after is not a swap either.
    assert.deepEqual(credits(fellow, owned("npc:589"), out("npc:589", 0, "ta"), into("npc:590", 1, "tb")), { trade: 0, gift: 3, donate: 0, camp: 0 });
});

test("each attempt on an activity card spends a roll of its own activity, and a miss run spends one for every attempt", () => {
    const traded = [fellow, owned("npc:589"), swap("npc:589", "npc:590")]; // a trade roll and a gift roll
    assert.equal(rule(...traded, drop(TRADER, 1, 1)), null);
    assert.equal(rule(...traded, drop(TRADER, 1, 1), drop(TRADER, 2, 2)), "activity", "one roll, one attempt");
    assert.equal(rule(...traded, drop(GIFTER, 1, 1)), null, "the gift roll pays for the gift card");
    assert.equal(rule(...traded, drop(BENEFACTOR, 1, 1)), "activity", "a donation was not made");
    assert.equal(rule(...traded, drop(FIRESIDE, 1, 1)), "activity", "no camp");
    assert.equal(rule(...traded, miss(TRADER, 1, 1)), null);
    assert.equal(rule(...traded, miss(TRADER, 2, 2)), "activity", "two attempts need two rolls");
    assert.equal(rule(...traded, miss(GIFTER, 1, 1), drop(TRADER, 1, 2)), null, "each activity has its own rolls");
    assert.deepEqual(credits(...traded, miss(GIFTER, 1, 1), drop(TRADER, 1, 2)), { trade: 0, gift: 0, donate: 0, camp: 0 });
    assert.equal(rule(...traded, miss(TRADER, 1, 1), miss(TRADER, 1, 2)), "activity");
    // Two swaps are two rolls.
    assert.equal(rule(...traded, swap("npc:590", "npc:114"), miss(TRADER, 2, 2)), null);
});

test("a donation earns a donation roll and a camp claim earns a camp roll", () => {
    const guild = [...fellow.slice(0, 5), mode("guild1"), fellow[5]];
    const donated = [...guild, owned("npc:589"), { kind: "donate", key: "npc:589", count: 0, partner: GUILD, trade: "a".repeat(32) }];
    assert.equal(rule(donated, drop(BENEFACTOR, 1, 1)), null);
    assert.equal(rule(donated, drop(BENEFACTOR, 1, 1), drop(BENEFACTOR, 2, 2)), "activity");
    const camped = [...base, mode("fellow1"), mode("camp1"), mode("ranked2"), { kind: "camp", key: "violet", count: 7200 }];
    assert.equal(rule(camped, drop(FIRESIDE, 1, 1)), null);
    assert.equal(rule(camped, drop(FIRESIDE, 1, 1), drop(FIRESIDE, 2, 2)), "activity");
    // A second camp claim is a second roll.
    const claim = { kind: "camp", key: "violet", count: 7200 };
    assert.equal(rule(camped, claim, miss(FIRESIDE, 2, 2)), null, "two claims, two rolls");
    assert.equal(rule(camped, claim, miss(FIRESIDE, 3, 3)), "activity");
});

test("an activity card at a camp can be boosted like any common or rare card, and cannot be crafted", () => {
    const camped = [...base, mode("fellow1"), mode("camp1"), mode("ranked2"), { kind: "camp", key: "violet", count: 7200 }];
    assert.equal(rule(camped, drop(FIRESIDE, 1, 1, { partner: "camp" })), null);
    assert.equal(rule(fellow, owned("npc:589"), swap("npc:589", "npc:590"), { kind: "craft", key: TRADER, count: 1, dust: -10 }), "activity");
    assert.equal(rule(fellow, { kind: "craft", key: TRADER, count: 1, dust: -10 }), "activity");
});

test("mode/fellow1 comes once, after faction1, and carries no count", () => {
    assert.equal(rule(fellow), null);
    assert.equal(rule(base, mode("fellow1"), mode("fellow1")), "mode");
    assert.equal(rule(base.slice(0, 3), mode("fellow1")), "mode");
    assert.equal(rule(base, { ...mode("fellow1"), count: 1 }), "mode");
    assert.equal(rule(mode("fellow1")), "mode");
});

test("a refused event earns nothing, and the state carries across batches", () => {
    // A tradeOut that breaks a rule (a card not owned) must not have earned its roll in a state the caller keeps.
    const start = result([...fellow]).state;
    const bad = rules.replay(build([out("npc:589", 0, "x")]).map((event, index) => ({ ...event, seq: 7 + index, t: 2000 })), catalog, start);
    assert.equal(bad.ok, false);
    assert.deepEqual(start.credits, { trade: 0, gift: 0, donate: 0, camp: 0 });
    const events = build([...fellow, owned("npc:589"), ...swap("npc:589", "npc:590"), drop(TRADER, 1, 1)]);
    const whole = rules.replay(events, catalog);
    const first = rules.replay(events.slice(0, 8), catalog);
    const second = rules.replay(events.slice(8), catalog, first.state);
    assert.equal(whole.ok && first.ok && second.ok, true);
    assert.deepEqual(second.state, whole.state);
});

test("the Fellowship cards keep out of seasons, packs and the launch split", () => {
    for (const key of [TRADER, GIFTER, BENEFACTOR, FIRESIDE]) assert.equal(catalog.cards[key].seasonal, undefined);
    const set = catalog.sets.find((entry) => entry.code === "FW");
    assert.equal(set.title, "Fellowship");
    assert.equal(set.group, "Social");
});
