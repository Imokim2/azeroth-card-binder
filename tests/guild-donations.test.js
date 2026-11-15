"use strict";
// Ledger spec 11 (docs/proposals/GUILD-BINDERS-DESIGN.md): mode/guild1, donate and donateReturn. A Ranked binder gives one copy of a card to
// its guild; the copy leaves at once and comes back only when the server refused the donation.
const assert = require("node:assert/strict");
const test = require("node:test");
const rules = require("../packages/shared/src/rules.js");
const ledger = require("../packages/shared/src/ledger.js");
const catalog = require("../packages/shared/catalog.json");

const GUILD = "01HF7YAT00QKSEP5RCNMPTQ3KN";
const OTHER_GUILD = "01HF7YAT00QKSEP5RCNMPTQ3KP";
const OP = "a".repeat(32);
const card = "npc:589";
const other = "npc:590";

const build = (steps) => steps.map((step, index) => ({
    seq: index + 1, t: 1000 + index * 10, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Ann-Realm", count: 0, ...step,
}));
const mode = (key) => ({ kind: "mode", key });
const markers = [mode("chase1"), mode("chase2"), mode("launch1"), mode("faction1"), mode("guild1")];
const ranked = [mode("ranked2")];
let trades = 0;
const gain = (key, count) => ({ kind: "tradeIn", key, count, partner: "bob-realm", trade: "t" + ++trades });
const donate = (key, count, extra = {}) => ({ kind: "donate", key, count, partner: GUILD, trade: OP, ...extra });
const back = (key, count, extra = {}) => ({ kind: "donateReturn", key, count, partner: GUILD, trade: OP, ...extra });
const history = (...parts) => build(parts.flat());
const rule = (steps) => { const result = rules.replay(history(...steps), catalog); return result.ok ? null : result.rule; };
const setup = [markers, ranked, gain(card, 1), gain(card, 2)];

test("a copy is donated and, when the server refuses, comes back", () => {
    const given = rules.replay(history(...setup, donate(card, 1)), catalog);
    assert.equal(given.ok, true);
    assert.equal(given.state.counts[card], 1);
    assert.deepEqual(given.state.donations, { [OP]: GUILD + "|" + card });
    const returned = rules.replay(history(...setup, donate(card, 1), back(card, 2)), catalog);
    assert.equal(returned.ok, true);
    assert.equal(returned.state.counts[card], 2);
    assert.deepEqual(returned.state.donations, { [OP]: "returned" });
    // The last copy can be donated, leaving the card at nothing.
    const last = rules.replay(history(markers, ranked, gain(card, 1), donate(card, 0)), catalog);
    assert.equal(last.ok, true);
    assert.equal(last.state.counts[card], 0);
});

test("the state carries across batches: replaying in two parts gives the same state", () => {
    const events = history(...setup, donate(card, 1), gain(other, 1), donate(other, 0, { trade: "c".repeat(32), partner: OTHER_GUILD }));
    const whole = rules.replay(events, catalog);
    assert.equal(whole.ok, true);
    const first = rules.replay(events.slice(0, 8), catalog);
    const second = rules.replay(events.slice(8), catalog, first.state);
    assert.equal(first.ok && second.ok, true);
    assert.deepEqual(second.state, whole.state);
    // The same operation cannot be reused in a later batch either.
    const later = rules.replay(build([donate(card, 0)]).map((event, index) => ({ ...event, seq: 9 + index, t: 2000 })), catalog, first.state);
    assert.equal(later.ok, false);
    assert.equal(later.rule, "donate");
});

test("mode/guild1 comes once, after faction1, and carries no count", () => {
    assert.equal(rule([markers]), null);
    assert.equal(rule([markers.slice(0, 4), mode("guild1"), mode("guild1")]), "mode"); // once
    assert.equal(rule([markers.slice(0, 3), mode("guild1")]), "mode"); // not before faction1
    assert.equal(rule([markers.slice(0, 4), { kind: "mode", key: "guild1", count: 1 }]), "mode");
    assert.equal(rule([[mode("guild1")]]), "mode");
    assert.equal(rule([markers.slice(0, 4), { ...mode("guild1"), shiny: 1 }]), "field");
});

test("a donation needs guild1, Ranked, a copy owned and an operation not used before", () => {
    assert.equal(rule([markers.slice(0, 4), ranked, gain(card, 1), donate(card, 0)]), "donate", "before guild1");
    assert.equal(rule([markers, [gain(card, 1)], donate(card, 0)]), "donate", "in Casual");
    assert.equal(rule([markers, ranked, [donate(card, 0)]]), "donate", "no copy to give");
    assert.equal(rule([markers, ranked, gain(card, 1), donate(card, 1)]), "donate", "the count must fall by one");
    assert.equal(rule([markers, ranked, gain(card, 1), donate(card, 2)]), "donate");
    assert.equal(rule([...setup, donate(card, 1), donate(card, 0)]), "donate", "an operation is used once");
    assert.equal(rule([...setup, donate(card, 1), donate(card, 0, { trade: "d".repeat(32) })]), null, "a new operation is fine");
    assert.equal(rule([...setup, donate(card, 1, { partner: "not-a-guild-id" })]), "donate");
    assert.equal(rule([...setup, donate(card, 1, { partner: "" })]), "donate");
    assert.equal(rule([...setup, donate(card, 1, { trade: "xyz" })]), "donate");
    assert.equal(rule([...setup, donate(card, 1, { trade: "" })]), "donate");
    assert.equal(rule([...setup, donate("npc:999999999", 1)]), "unknown-card");
    assert.equal(rule([...setup, donate("pack:AQT", 1)]), "unknown-card", "a pack is not a card");
    assert.equal(rule([...setup, donate(card, 1, { dust: 5 })]), "dust");
    assert.equal(rule([...setup, donate(card, 1, { shiny: 1 })]), "field");
    assert.equal(rule([...setup, donate(card, 1, { tape: 3 })]), "field");
    assert.equal(rule([...setup, mode("casual"), donate(card, 1)]), "donate", "back in Casual");
});

test("a copy comes back only for a donation that was made, once, with the same guild and card", () => {
    assert.equal(rule([...setup, back(card, 3)]), "donate", "nothing was donated");
    assert.equal(rule([...setup, donate(card, 1), back(card, 3)]), "donate", "the count must rise by one");
    assert.equal(rule([...setup, donate(card, 1), back(other, 1)]), "donate", "another card");
    assert.equal(rule([...setup, donate(card, 1), back(card, 2, { partner: OTHER_GUILD })]), "donate", "another guild");
    assert.equal(rule([...setup, donate(card, 1), back(card, 2, { trade: "e".repeat(32) })]), "donate", "another operation");
    assert.equal(rule([...setup, donate(card, 1), back(card, 2), back(card, 3)]), "donate", "only once");
    assert.equal(rule([...setup, donate(card, 1), back(card, 2), donate(card, 1)]), "donate", "a returned operation is not reused");
    assert.equal(rule([...setup, donate(card, 1), back(card, 2, { dust: 1 })]), "dust");
    assert.equal(rule([...setup, donate(card, 1), back(card, 2, { shiny: 1 })]), "field");
    assert.equal(rule([...setup, donate(card, 1), mode("casual"), back(card, 2)]), null, "a return needs no Ranked mode: the copy is the player's again");
});

test("a partner or a trade id is still refused on every other kind of event", () => {
    assert.equal(rule([markers, ranked, [{ ...gain(card, 1), kind: "drop", tape: 1 }]]), "trade");
    assert.equal(rule([markers, [{ kind: "recycle", key: card, count: 0, partner: GUILD }]]), "trade");
});

test("spec 11 is the current version and the kinds are listed", () => {
    assert.equal(ledger.SPEC_VERSION, 11);
    assert.ok(ledger.KINDS.includes("donate") && ledger.KINDS.includes("donateReturn"));
    const event = ledger.makeEvent({ ...build([donate(card, 0)])[0] }, ledger.GENESIS);
    assert.equal(ledger.badField(event), null);
    assert.equal(ledger.badField({ ...event, kind: "donation" }), "kind");
});
