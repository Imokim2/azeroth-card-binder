"use strict";
// Reference implementation of docs/LEDGER-SPEC.md. The Lua add-on, the server and the companion app each have
// their own implementation; all of them must produce exactly the results in ../vectors. This file is the one the
// vectors are generated from and checked against, and the server and app may import it directly.
const crypto = require("node:crypto");

const SPEC_VERSION = 9;
const GENESIS = "0".repeat(32);
const KINDS = ["drop", "craft", "recycle", "tradeIn", "tradeOut", "set", "mode", "miss", "packFind", "packOpen", "packCard", "seasonReward"];
// The order the fields are joined in when an event is hashed.
const FIELDS = ["seq", "t", "kind", "key", "count", "dust", "shiny", "tape", "partner", "trade", "char", "prev"];
const STRING_FIELDS = ["kind", "key", "partner", "trade", "char", "prev"];

const sha256Hex = (text) => crypto.createHash("sha256").update(text, "utf8").digest("hex");

const isInt = (value) => Number.isSafeInteger(value);

// Returns the name of the first field that breaks the rules, or null.
function badField(event) {
    if (!isInt(event.seq) || event.seq < 1) return "seq";
    if (!isInt(event.t) || event.t < 0) return "t";
    if (!KINDS.includes(event.kind)) return "kind";
    if (!isInt(event.count) || event.count < 0) return "count";
    if (!isInt(event.dust)) return "dust";
    if (event.shiny !== 0 && event.shiny !== 1) return "shiny";
    if (!isInt(event.tape) || event.tape < 0) return "tape";
    for (const name of STRING_FIELDS) {
        if (typeof event[name] !== "string" || /[|\r\n]/.test(event[name])) return name;
    }
    if (event.key === "") return "key";
    if (event.char === "") return "char";
    if (!/^[0-9a-f]{32}$/.test(event.prev)) return "prev";
    return null;
}

// The exact text that is hashed for an event.
function eventText(event) {
    return FIELDS.map((name) => String(event[name])).join("|");
}

const eventHash = (event) => sha256Hex(eventText(event)).slice(0, 32);

// Build the next event in a chain. `partial` holds every field except prev and h.
function makeEvent(partial, prev) {
    const event = { ...partial, prev };
    return { ...event, h: eventHash(event) };
}

// Check a batch of events against the last event already stored (or the start of a new chain).
// Returns { ok: true, head } or { ok: false, error, index } where error is one of
// replay, gap, bad-field, bad-prev, bad-hash.
function verifyChain(events, head = { seq: 0, hash: GENESIS }) {
    let expected = head.seq + 1;
    let previous = head.hash;
    for (let index = 0; index < events.length; index++) {
        const event = events[index];
        if (isInt(event.seq) && event.seq < expected) return { ok: false, error: "replay", index };
        if (event.seq !== expected) return { ok: false, error: "gap", index };
        if (badField(event)) return { ok: false, error: "bad-field", index, field: badField(event) };
        if (event.prev !== previous) return { ok: false, error: "bad-prev", index };
        if (event.h !== eventHash(event)) return { ok: false, error: "bad-hash", index };
        expected = event.seq + 1;
        previous = event.h;
    }
    return { ok: true, head: { seq: expected - 1, hash: previous } };
}

// Canonical JSON: keys sorted, no spaces, integers only, strings as JSON.stringify writes them.
function canonicalJson(value) {
    if (value === null || value === undefined) throw new Error("canonical JSON has no null or undefined");
    if (typeof value === "number") {
        if (!Number.isSafeInteger(value)) throw new Error("canonical JSON has integers only");
        return String(value);
    }
    if (typeof value === "boolean") return value ? "true" : "false";
    if (typeof value === "string") return JSON.stringify(value);
    if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
    const keys = Object.keys(value).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    return "{" + keys.map((key) => JSON.stringify(key) + ":" + canonicalJson(value[key])).join(",") + "}";
}

// Ed25519 keys are handled as raw hex: 32 bytes of seed (private) and 32 bytes (public).
const PKCS8_PREFIX = Buffer.from("302e020100300506032b657004220420", "hex");
const SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");

function keyPairFromSeed(seedHex) {
    const privateKey = crypto.createPrivateKey({
        key: Buffer.concat([PKCS8_PREFIX, Buffer.from(seedHex, "hex")]), format: "der", type: "pkcs8",
    });
    const spki = crypto.createPublicKey(privateKey).export({ format: "der", type: "spki" });
    return { privateKey, publicKeyHex: spki.subarray(spki.length - 32).toString("hex") };
}

const publicKeyFromHex = (hex) => crypto.createPublicKey({
    key: Buffer.concat([SPKI_PREFIX, Buffer.from(hex, "hex")]), format: "der", type: "spki",
});

// The signature covers the canonical JSON of the batch without its `sig` field.
function signBatch(batch, privateKey) {
    const { sig, ...body } = batch;
    return crypto.sign(null, Buffer.from(canonicalJson(body), "utf8"), privateKey).toString("hex");
}

function verifyBatch(batch, publicKeyHex) {
    const { sig, ...body } = batch;
    if (typeof sig !== "string" || !/^[0-9a-f]{128}$/.test(sig)) return false;
    return crypto.verify(null, Buffer.from(canonicalJson(body), "utf8"), publicKeyFromHex(publicKeyHex), Buffer.from(sig, "hex"));
}

// Ranked random numbers. A tape entry is 16 hex characters; the first 8 decide the drop and the next 8 decide
// whether a first copy is shiny. Rates are in hundredths of a percent (100 is 1%).
const rollValue = (entry) => (parseInt(entry.slice(0, 8), 16) % 10000) + 1;
const shinyValue = (entry, odds) => (parseInt(entry.slice(8, 16), 16) % odds) + 1;
const tapeDrops = (entry, rate, guaranteed) => guaranteed === true || rollValue(entry) <= rate;
const tapeIsShiny = (entry, odds) => shinyValue(entry, odds) === 1;
const tapeCommitment = (entries) => sha256Hex(entries.join("\n"));

module.exports = {
    SPEC_VERSION, GENESIS, KINDS, FIELDS, sha256Hex, badField, eventText, eventHash, makeEvent, verifyChain,
    canonicalJson, keyPairFromSeed, signBatch, verifyBatch, rollValue, shinyValue, tapeDrops, tapeIsShiny,
    tapeCommitment,
};
