"use strict";
// Checks the shared contract in packages/shared: the reference implementation against the test vectors, and the
// vectors against the generator. Run with: node --test tests/vectors.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const ledger = require("../packages/shared/src/ledger.js");

const dir = path.join(__dirname, "..", "packages", "shared", "vectors");
const load = (name) => JSON.parse(fs.readFileSync(path.join(dir, name), "utf8"));

test("SHA-256 matches the published standard answers and every vector", () => {
    // Anchored to FIPS 180-4 so the vectors cannot drift together with the code.
    assert.equal(ledger.sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    assert.equal(ledger.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    assert.equal(ledger.sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    for (const vector of load("sha256.json")) assert.equal(ledger.sha256Hex(vector.input), vector.hex, vector.input.slice(0, 20));
});

test("the valid ledger verifies, in one batch and in two", () => {
    const valid = load("ledger-valid.json");
    assert.equal(valid.events.length, 12);
    valid.events.forEach((event, index) => assert.equal(ledger.eventText(event), valid.texts[index]));
    const whole = ledger.verifyChain(valid.events);
    assert.deepEqual(whole, { ok: true, head: valid.head });
    const first = ledger.verifyChain(valid.events.slice(0, 5));
    assert.equal(first.ok, true);
    const second = ledger.verifyChain(valid.events.slice(5), first.head);
    assert.deepEqual(second, { ok: true, head: valid.head });
    assert.equal(ledger.verifyChain([]).ok, true);
    // Every kind of event is covered.
    assert.deepEqual([...new Set(valid.events.map((event) => event.kind))].sort(), [...ledger.KINDS].sort());
});

test("every invalid ledger is rejected for the stated reason", () => {
    const cases = load("ledger-invalid.json");
    assert.ok(cases.length >= 10);
    for (const item of cases) {
        const result = ledger.verifyChain(item.events, item.head || undefined);
        assert.equal(result.ok, false, item.name);
        assert.equal(result.error, item.error, item.name);
        assert.equal(result.index, item.index, item.name);
    }
});

test("canonical JSON is stable and refuses what it cannot represent", () => {
    for (const item of load("canonical-json.json")) assert.equal(ledger.canonicalJson(item.input), item.expected);
    assert.throws(() => ledger.canonicalJson({ a: 1.5 }));
    assert.throws(() => ledger.canonicalJson({ a: null }));
    assert.throws(() => ledger.canonicalJson({ a: undefined }));
});

test("a signed upload verifies, and any change to it or its key does not", () => {
    const signed = load("batch-signed.json");
    assert.equal(signed.seed, ledger.sha256Hex(signed.testKeySeedFrom));
    assert.equal(ledger.keyPairFromSeed(signed.seed).publicKeyHex, signed.publicKeyHex);
    const { sig, ...body } = signed.batch;
    assert.equal(ledger.canonicalJson(body), signed.canonical);
    assert.equal(ledger.verifyBatch(signed.batch, signed.publicKeyHex), true);
    assert.equal(ledger.verifyBatch(signed.forged, signed.publicKeyHex), false);
    const other = ledger.keyPairFromSeed(ledger.sha256Hex("another key")).publicKeyHex;
    assert.equal(ledger.verifyBatch(signed.batch, other), false);
    assert.equal(ledger.verifyBatch({ ...signed.batch, sig: "00" }, signed.publicKeyHex), false);
    assert.equal(ledger.verifyChain(signed.batch.events).ok, true);
    // Signing again gives the same signature (Ed25519 is deterministic).
    const { privateKey } = ledger.keyPairFromSeed(signed.seed);
    assert.equal(ledger.signBatch(signed.batch, privateKey), signed.batch.sig);
});

test("ranked random numbers follow the tape rules", () => {
    const tape = load("tape.json");
    assert.equal(ledger.tapeCommitment(tape.entries), tape.commitment);
    for (const item of tape.cases) {
        assert.equal(ledger.rollValue(item.entry), item.roll);
        assert.ok(item.roll >= 1 && item.roll <= 10000);
        assert.equal(ledger.shinyValue(item.entry, tape.shinyOdds), item.shiny);
        assert.equal(ledger.tapeDrops(item.entry, 100, false), item.dropsAt100);
        assert.equal(ledger.tapeDrops(item.entry, 1000, false), item.dropsAt1000);
        assert.equal(ledger.tapeDrops(item.entry, 100, true), true);
        assert.equal(ledger.tapeIsShiny(item.entry, tape.shinyOdds), item.firstCopyShiny);
    }
    // A higher rate can only add drops, never remove them.
    for (const item of tape.cases) assert.ok(!item.dropsAt100 || item.dropsAt1000);
});

test("the committed vectors are exactly what the generator writes", () => {
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), "vectors-"));
    execFileSync(process.execPath, [path.join(__dirname, "..", "tools", "build-vectors.js")],
        { env: { ...process.env, VECTORS_OUT: temp }, stdio: "pipe" });
    for (const name of fs.readdirSync(temp)) {
        assert.equal(fs.readFileSync(path.join(dir, name), "utf8").replace(/\r\n/g, "\n"),
            fs.readFileSync(path.join(temp, name), "utf8"), name + " is out of date: run node tools/build-vectors.js");
    }
    assert.deepEqual(fs.readdirSync(dir).sort(), fs.readdirSync(temp).sort());
    fs.rmSync(temp, { recursive: true, force: true });
});
