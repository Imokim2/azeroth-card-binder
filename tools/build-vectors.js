// Builds the shared test vectors in packages/shared/vectors from the reference implementation.
//
//   node tools/build-vectors.js
//
// The vectors are the contract: the Lua add-on, the server and the app must all reproduce them exactly.
// Everything here is deterministic, so running this twice changes nothing. The key pair below is a TEST key
// published on purpose; it signs nothing real.
const fs = require("fs");
const path = require("path");
const ledger = require("../packages/shared/src/ledger.js");
const rules = require("../packages/shared/src/rules.js");
const packs = require("../packages/shared/src/packs.js");
const { chanceFor } = require("../packages/shared/src/drops.js");
const catalog = require("../packages/shared/catalog.json");

const out = process.env.VECTORS_OUT || path.join(__dirname, "..", "packages", "shared", "vectors");
fs.mkdirSync(out, { recursive: true });
const write = (name, data) => fs.writeFileSync(path.join(out, name), JSON.stringify(data, null, 2) + "\n");

// ---- SHA-256 ----
const sha256 = [
    "", "abc", "abcdbcdecdef", "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
    "World of Warcards", "Zul'Gurub – Ünïcöde", "a".repeat(1000), "x".repeat(55), "x".repeat(56), "x".repeat(64),
].map((input) => ({ input, hex: ledger.sha256Hex(input) }));
write("sha256.json", sha256);

// ---- A valid ledger covering every kind of event ----
const char = "Alice-RealmName";
const base = { dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char };
const plan = [
    { t: 1000, kind: "mode", key: "ranked2", count: 0 },
    { t: 1010, kind: "drop", key: "npc:639", count: 1, shiny: 1, tape: 1 },
    { t: 1015, kind: "miss", key: "npc:589", count: 1, tape: 2 },
    { t: 1020, kind: "drop", key: "npc:589", count: 1, tape: 3 },
    { t: 1030, kind: "drop", key: "npc:589", count: 2, tape: 4 },
    { t: 1040, kind: "recycle", key: "npc:589", count: 1, dust: 1 },
    { t: 1050, kind: "craft", key: "npc:590", count: 1, dust: -10 },
    { t: 1060, kind: "tradeOut", key: "npc:639", count: 0, partner: "bob-realmname", trade: "111-482910-1" },
    { t: 1060, kind: "tradeIn", key: "npc:573", count: 1, partner: "bob-realmname", trade: "111-482910-1" },
    { t: 1070, kind: "drop", key: "node:1731", count: 1, tape: 5 },
    { t: 1080, kind: "set", key: "DM", count: 0 },
    { t: 1090, kind: "drop", key: "npc:1763", count: 1, tape: 6 },
    // A pack found on that attempt (its zone is the creature's), opened straight away: five cards on the next five entries.
    { t: 1092, kind: "packFind", key: catalog.cards["npc:1763"].set, count: 1, tape: 6 },
    { t: 1093, kind: "packOpen", key: catalog.cards["npc:1763"].set, count: 0, tape: 6 },
    ...catalog.sets.find((entry) => entry.code === catalog.cards["npc:1763"].set).cards.slice(0, 5)
        .map((key, index) => ({ t: 1094 + index, kind: "packCard", key, count: key === "npc:1763" ? 2 : 1, tape: 7 + index })),
    { t: 1100, kind: "mode", key: "casual", count: 0 },
];
const events = [];
let prev = ledger.GENESIS;
plan.forEach((partial, index) => {
    const event = ledger.makeEvent({ seq: index + 1, ...base, ...partial }, prev);
    events.push(event);
    prev = event.h;
});
const head = { seq: events.length, hash: prev };
const verified = ledger.verifyChain(events);
if (!verified.ok) throw new Error("the sample ledger does not verify");
write("ledger-valid.json", { genesis: ledger.GENESIS, events, head, texts: events.map(ledger.eventText) });

// Additive protocol-7 vector: retain the historical 20-event ledger unchanged.
const seasonalReward = ledger.makeEvent({ ...base, seq: 1, t: 1200, kind: "seasonReward", key: "WF", count: 1, trade: "a".repeat(32) }, ledger.GENESIS);
write("season-rewards.json", { events: [seasonalReward], head: { seq: 1, hash: seasonalReward.h }, texts: [ledger.eventText(seasonalReward)] });

// ---- Ledgers that must be rejected ----
const copy = (list) => JSON.parse(JSON.stringify(list));
const invalid = [];
const add = (name, batch, error, index, startHead) =>
    invalid.push({ name, events: batch, head: startHead || null, error, index });
{
    const tampered = copy(events.slice(0, 4));
    tampered[2].count = 9;
    add("a count was edited after the event was written", tampered, "bad-hash", 2);

    const retimed = copy(events.slice(0, 3));
    retimed[1].t = 5;
    add("a timestamp was edited", retimed, "bad-hash", 1);

    add("an event is missing from the middle", [events[0], events[1], events[3]], "gap", 2);
    add("the batch starts after the stored head with a gap", events.slice(3, 6), "gap", 0, { seq: 1, hash: events[0].h });
    add("the batch was already stored", events.slice(0, 3), "replay", 0, { seq: 3, hash: events[2].h });

    const reordered = copy(events.slice(0, 3));
    [reordered[1], reordered[2]] = [reordered[2], reordered[1]];
    add("two events swapped places", reordered, "gap", 0 + 1);

    const reprev = copy(events.slice(0, 3));
    reprev[1].prev = "f".repeat(32);
    add("an event points at the wrong previous event", reprev, "bad-prev", 1);

    const wrongKind = copy(events.slice(0, 2));
    wrongKind[1].kind = "gift";
    add("an unknown kind of event", wrongKind, "bad-field", 1);

    const pipe = copy(events.slice(0, 2));
    pipe[1].key = "npc:639|npc:1";
    add("a field holds the separator", pipe, "bad-field", 1);

    const forkedHead = { seq: 2, hash: "a".repeat(32) };
    add("the chain does not continue from the stored head", events.slice(2, 5), "bad-prev", 0, forkedHead);
}
write("ledger-invalid.json", invalid);

// ---- Canonical JSON ----
const canonical = [
    [{ b: 1, a: 2 }, '{"a":2,"b":1}'],
    [{ list: [3, 1, 2], text: 'say "hi"', flag: true }, '{"flag":true,"list":[3,1,2],"text":"say \\"hi\\""}'],
    [{ nested: { z: 1, y: { x: 0 } } }, '{"nested":{"y":{"x":0},"z":1}}'],
    [{ name: "Zul'Gurub – Ünïcöde" }, '{"name":"Zul\'Gurub – Ünïcöde"}'],
    [{ negative: -10, zero: 0 }, '{"negative":-10,"zero":0}'],
].map(([input, expected]) => ({ input, expected }));
for (const item of canonical) {
    if (ledger.canonicalJson(item.input) !== item.expected) throw new Error("canonical JSON vector is wrong: " + item.expected);
}
write("canonical-json.json", canonical);

// ---- A signed upload ----
const seed = ledger.sha256Hex("world-of-warcards test key 1");
const { privateKey, publicKeyHex } = ledger.keyPairFromSeed(seed);
const batch = {
    specVersion: ledger.SPEC_VERSION, key: publicKeyHex, character: "Alice", realm: "RealmName", schema: 2,
    catalogVersion: "test-1", events, tapeIndex: 12, sentAt: 1110,
    snapshot: {
        counts: { "npc:573": 1, "npc:589": 1, "npc:590": 1, "npc:1763": 1, "node:1731": 1 },
        attempts: { "npc:589": 3, "npc:639": 1, "node:1731": 1, "npc:1763": 1 },
        dust: 0, sets: { DM: true }, titles: {},
    },
};
batch.sig = ledger.signBatch(batch, privateKey);
const forged = copy(batch);
forged.snapshot.counts["npc:573"] = 7;
write("batch-signed.json", {
    note: "TEST KEY ONLY. The seed is sha256 of the text in testKeySeedFrom.",
    testKeySeedFrom: "world-of-warcards test key 1", seed, publicKeyHex,
    canonical: ledger.canonicalJson((({ sig, ...body }) => body)(batch)),
    batch, forged,
});

// ---- Ranked random numbers ----
const entries = Array.from({ length: 12 }, (_, index) => ledger.sha256Hex("tape-test|" + index).slice(0, 16));
const cases = [];
for (const entry of entries) {
    cases.push({
        entry, roll: ledger.rollValue(entry), shiny: ledger.shinyValue(entry, 20),
        dropsAt100: ledger.tapeDrops(entry, 100, false), dropsAt1000: ledger.tapeDrops(entry, 1000, false),
        dropsWhenGuaranteed: ledger.tapeDrops(entry, 100, true), firstCopyShiny: ledger.tapeIsShiny(entry, 20),
    });
}
write("tape.json", { shinyOdds: 20, entries, commitment: ledger.tapeCommitment(entries), cases });

// ---- Packs: which attempts find one, and which card a tape entry gives from a zone ----
const packCases = [];
{
    const hex8 = (n) => n.toString(16).padStart(8, "0");
    const zones = ["AQT", "AHX", "ABX", "DM"]; // all of common, epic and legendary; common and epic; common only; a dungeon
    for (const roll of [1, 2, 3000, 6999, 7000, 7001, 7499, 8000, 9999, 10000]) {
        for (const second of [0, 19, 20, 12345, 4294967295]) {
            const entry = hex8(roll - 1) + hex8(second);
            const row = { entry, roll: ledger.rollValue(entry), packValue: packs.packValue(entry, catalog.shinyOdds), found: packs.packFound(entry, catalog.shinyOdds), picks: {} };
            for (const zone of zones) row.picks[zone] = packs.packPick(catalog, zone, entry, catalog.shinyOdds);
            packCases.push(row);
        }
    }
    for (const entry of entries) {
        const row = { entry, roll: ledger.rollValue(entry), packValue: packs.packValue(entry, catalog.shinyOdds), found: packs.packFound(entry, catalog.shinyOdds), picks: {} };
        for (const zone of zones) row.picks[zone] = packs.packPick(catalog, zone, entry, catalog.shinyOdds);
        packCases.push(row);
    }
    write("packs.json", { odds: packs.PACK_ODDS, size: packs.PACK_SIZE, shinyOdds: catalog.shinyOdds, zones, cases: packCases });
}

// ---- What events must mean (section 3.1 of the spec): one valid binder history and many that break a rule ----
// These events are not chained (no prev or h); the rules look only at what each event says.
{
    const owned = (key) => { if (!catalog.cards[key]) throw new Error("not a card: " + key); return key; };
    const common = owned("npc:589"), commonB = owned("npc:590"), epic = owned("npc:573"), legendary = owned("npc:639");
    // The smallest set whose cards are all creatures, to finish in the valid history.
    const set = catalog.sets.filter((entry) => entry.cards.every((key) => key.startsWith("npc:")))
        .sort((a, b) => a.cards.length - b.cards.length || a.code.localeCompare(b.code))[0];
    const recycleLegendary = catalog.dust.recycle[catalog.cards[legendary].rarity];
    const craftCommon = catalog.dust.craft[catalog.cards[commonB].rarity];
    if (recycleLegendary < craftCommon) throw new Error("the sample history needs a legendary recycle to pay for a common craft");
    const trade = { partner: "bob-realmname", trade: "111-482910-1" };
    const trade2 = { partner: "carol-realmname", trade: "111-482910-2" };
    const outside = Object.keys(catalog.cards).filter((key) => key.startsWith("npc:") && !set.cards.includes(key) && ![common, commonB, epic, legendary].includes(key)).sort()[0];
    // Each step is { kind, key, count, ...extras }. seq and t are filled in; every other field defaults to 0 or "".
    const finished = [];
    let n = 0;
    const history = [
        { kind: "drop", key: legendary, count: 1, shiny: 1 },
        { kind: "drop", key: legendary, count: 2 },
        { kind: "recycle", key: legendary, count: 1, dust: recycleLegendary },
        { kind: "craft", key: commonB, count: 1, dust: -craftCommon },
        { kind: "drop", key: common, count: 1 },
        { kind: "drop", key: common, count: 2, shiny: 1 }, // the shiny copy can come on any drop while there is none yet
        { kind: "tradeOut", key: common, count: 1, ...trade },
        { kind: "tradeIn", key: epic, count: 1, ...trade },
        // Any card can be traded, a last copy included: a card from outside the finished set, in and straight out again.
        { kind: "tradeIn", key: outside, count: 1, ...trade2 },
        { kind: "tradeOut", key: outside, count: 0, ...trade2 },
        // Ranked writes every attempt down: a drop, or a run of misses, so the tape entries follow each other without a gap.
        { kind: "mode", key: "ranked2", count: 0 },
        { kind: "drop", key: common, count: 2, tape: 1 },
        { kind: "miss", key: common, count: 2, tape: 3 }, // two misses, entries 2 and 3
        { kind: "drop", key: common, count: 3, tape: 4 },
    ];
    let lastTape = 4;
    for (const key of set.cards) {
        const have = history.filter((step) => step.key === key && step.kind !== "tradeOut" && step.kind !== "recycle" && step.kind !== "miss").length;
        if (have === 0) history.push({ kind: "drop", key, count: 1, tape: ++lastTape });
    }
    const build = (steps) => steps.map((step, index) => ({
        seq: index + 1, t: 1000 + index * 10, dust: 0, shiny: 0, tape: 0, partner: "", trade: "", char, ...step,
    }));
    // Packs: found on the last attempt written down, whose creature decides the zone; opened at once; five cards on the
    // next five entries. Counts are worked out from the history so far.
    const lastDrop = history.filter((step) => step.kind === "drop" && step.tape > 0).pop();
    const packZone = catalog.cards[lastDrop.key].set;
    const packSet = catalog.sets.find((entry) => entry.code === packZone);
    const otherZone = catalog.sets.find((entry) => entry.code !== packZone && entry.code !== "GA").code;
    const otherCard = catalog.sets.find((entry) => entry.code === otherZone).cards[0];
    const have = { ...rules.replay(build(history), catalog).state.counts };
    const shinyHad = { ...rules.replay(build(history), catalog).state.shiny };
    const packCards = (from, tapes) => Array.from({ length: 5 }, (_, index) => {
        const key = packSet.cards[(from + index) % packSet.cards.length];
        have[key] = (have[key] || 0) + 1;
        const shiny = index === 0 && !shinyHad[key] ? 1 : 0;
        if (shiny) shinyHad[key] = true;
        return { kind: "packCard", key, count: have[key], shiny, tape: tapes ? lastTape + 1 + index : 0 };
    });
    const packFindAt = history.length;
    history.push({ kind: "packFind", key: packZone, count: 1, tape: lastTape });
    history.push({ kind: "packOpen", key: packZone, count: 0, tape: lastTape });
    history.push(...packCards(0, true));
    lastTape += 5;
    history.push({ kind: "set", key: set.code, count: 0 });
    history.push({ kind: "mode", key: "casual", count: 0 });
    // And in Casual, with no tape: the same events with every tape position 0.
    const casualFindAt = history.length;
    history.push({ kind: "packFind", key: packZone, count: 1, tape: 0 });
    history.push({ kind: "packOpen", key: packZone, count: 0, tape: 0 });
    history.push(...packCards(5, false));
    // Counts in the steps above are the counts after each event; a drop of an owned card after trading must follow on.
    const validEvents = build(history);
    const checked = rules.replay(validEvents, catalog);
    if (!checked.ok) throw new Error("the sample history breaks a rule: " + JSON.stringify(checked));

    const bad = [];
    // Start from the first `upTo` events of the valid history, then add one event that breaks a rule.
    const breaks = (name, rule, upTo, extra, at = upTo) => {
        const steps = history.slice(0, upTo).concat(extra);
        bad.push({ name, rule, index: at, events: build(steps) });
    };
    const kindAt = (kind, from = 0) => history.findIndex((step, index) => index >= from && step.kind === kind);
    breaks("a drop that skips a copy", "count", 1, [{ kind: "drop", key: legendary, count: 3 }]);
    breaks("a second shiny for the same card", "shiny", 2, [{ kind: "drop", key: legendary, count: 3, shiny: 1 }]);
    breaks("a drop of a card that does not exist", "unknown-card", 0, [{ kind: "drop", key: "npc:999999999", count: 1 }]);
    breaks("a drop that moves dust", "dust", 0, [{ kind: "drop", key: common, count: 1, dust: 5 }]);
    breaks("a craft of a card already owned", "craft", 4, [{ kind: "craft", key: commonB, count: 1, dust: -craftCommon }]);
    breaks("a craft that pays the wrong dust", "dust", 3, [{ kind: "craft", key: commonB, count: 1, dust: -(craftCommon - 1) }]);
    breaks("a craft with too little dust", "dust", 0, [{ kind: "craft", key: commonB, count: 1, dust: -craftCommon }]);
    breaks("a recycle of the last copy", "recycle", 1, [{ kind: "recycle", key: legendary, count: 0, dust: recycleLegendary }]);
    breaks("a recycle that earns the wrong dust", "dust", 2, [{ kind: "recycle", key: legendary, count: 1, dust: recycleLegendary + 1 }]);
    breaks("a trade away of a card not owned", "trade", 4, [{ kind: "tradeOut", key: epic, count: 0, ...trade }]);
    breaks("a trade in with no trade id", "trade", 6, [{ kind: "tradeIn", key: epic, count: 1, partner: "bob-realmname", trade: "" }]);
    breaks("a trade partner on a plain drop", "trade", 0, [{ kind: "drop", key: common, count: 1, partner: "bob-realmname" }]);
    breaks("a set that is not complete", "set", 6, [{ kind: "set", key: set.code, count: 0 }]);
    breaks("a set finished twice", "set", history.findIndex((step) => step.kind === "set") + 1, [{ kind: "set", key: set.code, count: 0 }]);
    breaks("a set code that does not exist", "unknown-set", 0, [{ kind: "set", key: "ZZZZ", count: 0 }]);
    breaks("a mode that does not exist", "mode", 0, [{ kind: "mode", key: "hardcore", count: 0 }]);
    const ranked = kindAt("mode");
    breaks("a second shiny after a later-copy shiny", "shiny", ranked + 4, [{ kind: "drop", key: common, count: 4, tape: 5, shiny: 1 }]);
    breaks("a ranked drop that reuses a tape entry", "tape", ranked + 4, [{ kind: "drop", key: common, count: 4, tape: 4 }]);
    breaks("a ranked drop that leaves an attempt out", "tape", ranked + 4, [{ kind: "drop", key: common, count: 4, tape: 6 }]);
    breaks("a ranked drop with no tape entry", "tape", ranked + 1, [{ kind: "drop", key: common, count: 2, tape: 0 }]);
    // Packs.
    const lastBefore = lastDrop.tape;
    const firstPackCard = history[packFindAt + 2];
    breaks("a pack found for a zone the last attempt was not in", "pack", packFindAt, [{ kind: "packFind", key: otherZone, count: 1, tape: lastBefore }]);
    breaks("a pack found on an attempt that is not the latest", "tape", packFindAt, [{ kind: "packFind", key: packZone, count: 1, tape: lastBefore - 1 }]);
    breaks("a second pack found on the same entry", "tape", packFindAt + 1, [{ kind: "packFind", key: packZone, count: 2, tape: lastBefore }]);
    breaks("a pack found with the wrong count", "pack", packFindAt, [{ kind: "packFind", key: packZone, count: 5, tape: lastBefore }]);
    breaks("a pack of a zone that does not exist", "unknown-set", packFindAt, [{ kind: "packFind", key: "ZZZZ", count: 1, tape: lastBefore }]);
    breaks("a pack found in Ranked with no tape entry", "tape", packFindAt, [{ kind: "packFind", key: packZone, count: 1, tape: 0 }]);
    breaks("a pack opened that was never found", "pack", packFindAt, [{ kind: "packOpen", key: packZone, count: 0, tape: lastBefore }]);
    breaks("a pack opened at the wrong place on the tape", "tape", packFindAt + 1, [{ kind: "packOpen", key: packZone, count: 0, tape: lastBefore + 1 }]);
    breaks("a pack card from outside the zone", "pack", packFindAt + 2, [{ kind: "packCard", key: otherCard, count: 1, tape: lastBefore + 1 }]);
    breaks("a pack card that leaves a tape entry out", "tape", packFindAt + 2, [{ ...firstPackCard, shiny: 0, tape: lastBefore + 2 }]);
    breaks("a pack card with no pack open", "pack", packFindAt, [{ ...firstPackCard, shiny: 0, tape: lastBefore + 1 }]);
    breaks("something else while a pack is half opened", "pack", packFindAt + 3, [{ kind: "mode", key: "casual", count: 0 }]);
    breaks("a sixth card from one pack", "pack", packFindAt + 7, [{ ...firstPackCard, shiny: 0, count: firstPackCard.count + 1, tape: lastBefore + 6 }]);
    breaks("a pack found in Casual that claims a tape entry", "tape", casualFindAt, [{ kind: "packFind", key: packZone, count: 1, tape: 5 }]);
    breaks("a run of misses that leaves an attempt out", "tape", ranked + 2, [{ kind: "miss", key: common, count: 1, tape: 3 }]);
    breaks("a run of misses that reaches back too far", "tape", ranked + 2, [{ kind: "miss", key: common, count: 3, tape: 3 }]);
    breaks("a run of no misses", "miss", ranked + 2, [{ kind: "miss", key: common, count: 0, tape: 1 }]);
    breaks("a run of misses in Casual", "mode", 0, [{ kind: "miss", key: common, count: 1, tape: 1 }]);
    breaks("a run of misses for a card that does not exist", "unknown-card", ranked + 1, [{ kind: "miss", key: "npc:999999999", count: 1, tape: 1 }]);
    breaks("the first switch to ranked2 that skips far ahead", "tape", ranked, [{ kind: "mode", key: "ranked2", count: 0, tape: 5000 }]);
    breaks("a return to ranked2 that skips tape entries", "tape", ranked + 4,
        [{ kind: "mode", key: "casual", count: 0 }, { kind: "mode", key: "ranked2", count: 0, tape: 9 }], ranked + 5);
    breaks("a return to ranked2 that goes back", "tape", ranked + 4,
        [{ kind: "mode", key: "casual", count: 0 }, { kind: "mode", key: "ranked2", count: 0, tape: 2 }], ranked + 5);
    breaks("a casual drop that claims a tape entry", "tape", 0, [{ kind: "drop", key: common, count: 1, tape: 1 }]);
    const clock = build(history.slice(0, 2));
    clock[1].t = clock[0].t - 1;
    bad.push({ name: "time that goes backwards", rule: "time", index: 1, events: clock });
    for (const item of bad) {
        const result = rules.replay(item.events, catalog);
        if (result.ok || result.rule !== item.rule || result.index !== item.index) {
            throw new Error(`rules vector "${item.name}" does not behave as stated: ${JSON.stringify(result)}`);
        }
    }
    const snapshot = { counts: checked.state.counts, dust: checked.state.dust, sets: checked.state.sets };
    write("rules.json", {
        note: "Events here are not chained. catalogVersion is the catalog these were made against.",
        catalogVersion: catalog.catalogVersion, set: set.code,
        valid: { events: validEvents, finalState: checked.state, snapshot },
        invalid: bad,
    });
    console.log(`rules vectors written: ${validEvents.length} valid events, ${bad.length} rule breaks`);
}

// ---- A one-way gift: one outgoing copy and its matching incoming copy ----
function giftChain(char, steps) {
    let prev = ledger.GENESIS;
    const events = steps.map((step, index) => {
        const event = ledger.makeEvent({ seq: index + 1, t: 1000 + index * 10, ...base, char, ...step }, prev);
        prev = event.h;
        return event;
    });
    return { events, head: { seq: events.length, hash: prev } };
}
const gifts = {
    key: "npc:589", trade: "gift-vector-1",
    giver: giftChain("Alice-RealmName", [
        { kind: "drop", key: "npc:589", count: 1 },
        { kind: "tradeOut", key: "npc:589", count: 0, partner: "bob-realmname", trade: "gift-vector-1" },
    ]),
    recipient: giftChain("Bob-RealmName", [
        { kind: "tradeIn", key: "npc:589", count: 1, partner: "alice-realmname", trade: "gift-vector-1" },
    ]),
};
write("gifts.json", gifts);

// ---- Policy cutover: flat chase odds, late pity, and weighted packs ----
const balanceKeys = [...new Set(["npc:589", "npc:639", "node:1731",
    ...Object.keys(catalog.cards).filter(key => !catalog.cards[key].baseKey && catalog.cards[key].critter),
    ...["regular", "uncommon", "chase"].map(tier => Object.keys(catalog.cards).find(key => !catalog.cards[key].baseKey && catalog.cards[key].dropProfile.tier === tier)),
])];
const balance = {
    catalogVersion: catalog.catalogVersion,
    // legacy: the original rank rates; balanced: after mode/chase1; balanced2: after mode/chase2 (dropProfile.rate2).
    chances: balanceKeys.flatMap(key => {
        const boundaries = rate => { const limit = Math.ceil(10000 / rate), start = Math.floor(limit * .75); return [0, 1, start, start + 1, limit - 2, limit - 1]; };
        const profile = catalog.cards[key].dropProfile;
        return [...new Set([...boundaries(profile.rate), ...boundaries(profile.rate2)])].sort((a, b) => a - b).map(misses => ({ key, misses,
            legacy: chanceFor(catalog, key, misses), balanced: chanceFor(catalog, key, misses, true), balanced2: chanceFor(catalog, key, misses, 2) }));
    }),
    packs: packCases.flatMap(item => ["AQT", "AHX", "ABX", "DM"].map(zone => ({ zone, entry: item.entry,
        key: packs.packPick(catalog, zone, item.entry, catalog.shinyOdds, true) }))),
};
write("balance.json", balance);

const satchel = {
    tiers: [0, 69, 70, 94, 95, 99].map(draw => {
        const entry = "0000270f" + (draw * catalog.shinyOdds * packs.PACK_ODDS).toString(16).padStart(8, "0");
        return { entry, tier: packs.packTier(entry, catalog.shinyOdds), found: packs.packFound(entry, catalog.shinyOdds) };
    }),
    gift: {
        giver: giftChain("Alice-RealmName", [
            { kind: "mode", key: "packs2", count: 0 },
            { kind: "packFind", key: "WF:rare", count: 1 },
            { kind: "tradeOut", key: "pack:WF:rare", count: 0, partner: "bob-realmname", trade: "pack-gift-vector" },
        ]),
        recipient: giftChain("Bob-RealmName", [
            { kind: "tradeIn", key: "pack:WF:rare", count: 1, partner: "alice-realmname", trade: "pack-gift-vector" },
            { kind: "packOpen", key: "WF:rare", count: 0 },
            { kind: "packCard", key: "npc:589", count: 1 },
            { kind: "packCard", key: "npc:590", count: 1 },
            { kind: "packCard", key: "npc:589", count: 2 },
        ]),
    },
};
for (const run of Object.values(satchel.gift)) {
    const checked = rules.replay(run.events, catalog);
    if (!checked.ok) throw new Error(JSON.stringify(checked));
    run.finalState = checked.state;
}
write("satchel.json", satchel);

// ---- The same vectors as Lua, for tests that have no JSON parser ----
const lua = (value, indent = "") => {
    if (value === null || value === undefined) return "nil";
    if (typeof value === "string") return JSON.stringify(value).replace(/\\u([0-9a-f]{4})/gi, (_, hex) => "\\" + parseInt(hex, 16));
    if (typeof value === "number" || typeof value === "boolean") return String(value);
    const inner = indent + "    ";
    if (Array.isArray(value)) {
        return value.length === 0 ? "{}" : "{\n" + value.map((v) => inner + lua(v, inner)).join(",\n") + ",\n" + indent + "}";
    }
    const keys = Object.keys(value);
    return keys.length === 0 ? "{}" : "{\n" + keys.map((k) => inner + `[${JSON.stringify(k)}] = ` + lua(value[k], inner)).join(",\n") + ",\n" + indent + "}";
};
fs.writeFileSync(path.join(out, "vectors.lua"),
    "-- GENERATED by tools/build-vectors.js. Do not edit by hand.\n" +
    "-- The shared test vectors for docs/LEDGER-SPEC.md, as a Lua table.\n" +
    "return " + lua({
        genesis: ledger.GENESIS, sha256, valid: { events, head, texts: events.map(ledger.eventText) }, invalid, gifts, balance, satchel,
        tape: { shinyOdds: 20, entries, commitment: ledger.tapeCommitment(entries), cases },
        packs: { odds: packs.PACK_ODDS, size: packs.PACK_SIZE, shinyOdds: catalog.shinyOdds, zones: ["AQT", "AHX", "ABX", "DM"], cases: packCases },
    }) + "\n");
console.log(`vectors written: ${sha256.length} hashes, ${events.length} events, ${invalid.length} invalid ledgers, ${cases.length} tape entries`);
