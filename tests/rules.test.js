"use strict";
// The meaning of ledger events (docs/LEDGER-SPEC.md, section 3.1) against packages/shared/vectors/rules.json.
// Run: node --test tests/rules.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const rules = require("../packages/shared/src/rules.js");
const catalog = require("../packages/shared/catalog.json");

const vectors = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "packages", "shared", "vectors", "rules.json"), "utf8"));

test("the vectors were made against the committed catalog", () => {
    assert.equal(vectors.catalogVersion, catalog.catalogVersion, "run: node tools/build-vectors.js");
});

test("a valid history replays to the stated final state and matches its snapshot", () => {
    const result = rules.replay(vectors.valid.events, catalog);
    assert.equal(result.ok, true);
    assert.deepEqual(result.state, vectors.valid.finalState);
    assert.deepEqual(rules.snapshotDifferences(vectors.valid.snapshot, result.state), []);
    assert.equal(result.state.sets[vectors.set], true);
    assert.equal(result.state.mode, "casual");
});

test("every history that breaks a rule is stopped at the right event with the right rule", () => {
    assert.ok(vectors.invalid.length >= 20);
    const seen = new Set();
    for (const item of vectors.invalid) {
        const result = rules.replay(item.events, catalog);
        assert.equal(result.ok, false, item.name);
        assert.equal(result.rule, item.rule, item.name);
        assert.equal(result.index, item.index, item.name);
        seen.add(item.rule);
    }
    for (const rule of ["count", "shiny", "craft", "recycle", "trade", "set", "mode", "tape", "time", "dust", "unknown-card", "unknown-set"]) {
        assert.ok(seen.has(rule), `no vector for the "${rule}" rule`);
    }
});

test("a replay can resume from a stored state, and never changes the state it was given", () => {
    const events = vectors.valid.events;
    const first = rules.replay(events.slice(0, 6), catalog);
    assert.equal(first.ok, true);
    const frozen = JSON.stringify(first.state);
    const rest = rules.replay(events.slice(6), catalog, first.state);
    assert.equal(rest.ok, true);
    assert.equal(JSON.stringify(first.state), frozen);
    assert.deepEqual(rest.state, vectors.valid.finalState);
    // A failure part-way leaves the starting state alone too.
    const broken = rules.replay([...events.slice(6, 8), { ...events[8], count: 99 }], catalog, first.state);
    assert.equal(broken.ok, false);
    assert.equal(JSON.stringify(first.state), frozen);
});

test("a snapshot that disagrees with the replay is reported by name", () => {
    const state = rules.replay(vectors.valid.events, catalog).state;
    const key = Object.keys(state.counts)[0];
    assert.deepEqual(rules.snapshotDifferences({ counts: { ...state.counts, [key]: 99 }, dust: state.dust, sets: state.sets }, state), ["counts"]);
    assert.deepEqual(rules.snapshotDifferences({ counts: state.counts, dust: state.dust + 1, sets: state.sets }, state), ["dust"]);
    assert.deepEqual(rules.snapshotDifferences({ counts: state.counts, dust: state.dust, sets: {} }, state), ["sets"]);
    // An owned-zero entry in the snapshot is the same as no entry.
    assert.deepEqual(rules.snapshotDifferences({ counts: { ...state.counts, "npc:1": 0 }, dust: state.dust, sets: state.sets }, state), []);
});

test("a new upload may carry an old Ranked switch only when another switch follows it directly, and no roll under it", () => {
    const base = { t: 1000, count: 0, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char: "Alice-RealmName" };
    const old = { ...base, seq: 1, kind: "mode", key: "ranked" };
    const second = { ...base, seq: 2, t: 1001, kind: "mode", key: "ranked2" };
    const casual = { ...base, seq: 2, t: 1001, kind: "mode", key: "casual" };
    const drop = { ...base, seq: 2, t: 1001, kind: "drop", key: "npc:589", count: 1, tape: 1 };
    // Strict is how a new upload is checked: the old switch followed by the new kind, or by Casual, is fine.
    assert.equal(rules.replay([old, second], catalog, undefined, { strict: true }).ok, true);
    assert.equal(rules.replay([old, second], catalog, undefined, { strict: true }).state.mode, "ranked2");
    assert.equal(rules.replay([old, casual], catalog, undefined, { strict: true }).ok, true);
    // Alone (or the last event of an upload), or followed by a roll, it is still refused.
    const alone = rules.replay([old], catalog, undefined, { strict: true });
    assert.deepEqual([alone.ok, alone.rule], [false, "mode"]);
    const rolled = rules.replay([old, drop], catalog, undefined, { strict: true });
    assert.equal(rolled.ok, false);
    assert.ok(rolled.rule === "mode" || rolled.rule === "tape", rolled.rule);
    // Old history that is already stored is read as it always was.
    assert.equal(rules.replay([old], catalog).ok, true);
});
