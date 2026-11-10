"use strict";
// Plays a binder history through the real Lua add-on code and checks that what it writes is accepted by the
// reference ledger and rules implementations: the add-on's hashes equal the reference hashes, its events obey the
// meaning rules, and its snapshot equals the replay. Run: node --test tests/addon-ledger.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const ledger = require("../packages/shared/src/ledger.js");
const rules = require("../packages/shared/src/rules.js");
const catalog = require("../packages/shared/catalog.json");

const root = path.join(__dirname, "..");
const played = spawnSync(process.env.LUAJIT || "luajit", ["tests/tools/play-ledger.lua"], { cwd: root, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
if (played.status !== 0) throw new Error("the Lua scenario failed: " + (played.error || played.stderr));
const run = JSON.parse(played.stdout);

test("the add-on's chain verifies under the reference implementation, hash for hash", () => {
    assert.ok(run.events.length > 8);
    assert.deepEqual(ledger.verifyChain(run.events), { ok: true, head: run.head });
    for (const kind of ["drop", "craft", "recycle", "tradeIn", "tradeOut", "set"]) {
        assert.ok(run.events.some((event) => event.kind === kind), `the scenario wrote no ${kind} event`);
    }
});

test("the add-on's events mean something the rules accept, and its snapshot equals the replay", () => {
    const result = rules.replay(run.events, catalog);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.deepEqual(rules.snapshotDifferences(run.snapshot, result.state), []);
    assert.equal(result.state.sets[run.set], true);
});

test("tampering with what the add-on wrote is caught by the same checks", () => {
    const edited = JSON.parse(JSON.stringify(run.events));
    edited[3].count += 1;
    assert.equal(ledger.verifyChain(edited).error, "bad-hash");
    const skipped = run.events.filter((event, index) => index !== 2);
    assert.equal(ledger.verifyChain(skipped).error, "gap");
});
