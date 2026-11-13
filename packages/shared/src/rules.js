"use strict";
// What the events of a ledger must mean (docs/LEDGER-SPEC.md, section 3.1), checked by replaying them.
//
// ledger.js checks that a chain is intact (hashes, order, field shapes). This file checks that the chain
// describes a binder that could really exist: counts go up and down by one, dust balances, a card is crafted only
// when missing, a set is finished only when every card is owned, and so on. The server runs it on every upload;
// the app may run it before uploading. It is pure: no clock, no network, no storage. The catalog is passed in.
//
// A "state" is everything the rules need to remember between events. It is plain data so a server can store it
// and resume from it: { counts, dust, shiny, sets, mode, lastTape, lastT, exact, packs, packZone, packLeft, packFound,
// lastAttempt }. Packs are in section 8.2 of the spec: `packFind` adds a pack of a zone, `packOpen` spends one, and the
// `packCard` events that follow (five, with nothing in between) are its cards.
//
// Ranked comes in two kinds. "ranked" is the first version, in which only drops were written down and the misses
// between them were not; it is only ever replayed from history. "ranked2" writes down every attempt: a drop, or a
// `miss` event for a run of consecutive misses on one card, so the tape positions used follow each other without a
// gap and the server can check every roll. `strict` (used when an upload is accepted) refuses the first kind.

const SET_MODES = ["casual", "ranked", "ranked2"];
const PACK_SIZE = 5;
// The first time a binder enters ranked2 it may name a tape position this far past the last one it recorded, for the
// misses a binder kept before attempts were written down. Afterwards no gap is allowed at all.
const BASELINE_GAP = 2000;
const { familyCount } = require("./editions.js");
const { packInfo } = require("./packs.js");

function newState() {
    return {
        counts: {}, dust: 0, shiny: {}, sets: {}, mode: "casual", lastTape: 0, lastT: 0, exact: false,
        packs: {}, packZone: "", packLeft: 0, packFound: 0, lastAttempt: { key: "", tape: 0 },
    };
}

const copyState = (state) => ({
    counts: { ...state.counts }, dust: state.dust, shiny: { ...state.shiny }, sets: { ...state.sets },
    mode: state.mode, lastTape: state.lastTape, lastT: state.lastT, exact: state.exact === true,
    packs: { ...(state.packs || {}) }, packZone: state.packZone || "", packLeft: state.packLeft || 0, packFound: state.packFound || 0,
    lastAttempt: { key: (state.lastAttempt && state.lastAttempt.key) || "", tape: (state.lastAttempt && state.lastAttempt.tape) || 0 },
    ...(state.editions === true ? { editions: true } : {}),
    ...(state.launch === 1 ? { launch: 1 } : {}),
    ...(state.balance >= 1 ? { balance: state.balance, balanceAttempts: { ...(state.balanceAttempts || {}) },
        balanceDrops: { ...(state.balanceDrops || {}) }, balanceReady: { ...(state.balanceReady || {}) } } : {}),
    ...(state.packOutputs ? { packOutputs: Object.fromEntries(Object.entries(state.packOutputs).map(([zone, cards]) => [zone, { ...cards }])) } : {}),
    ...(state.packType ? { packType: state.packType } : {}),
    ...(state.tieredPacks ? { tieredPacks: true } : {}),
    ...(state.seasonClaims ? { seasonClaims: { ...state.seasonClaims } } : {}),
});

// Returns the name of the rule an event breaks, or null. Mutates `state` only when the event is fine.
// `available(baseKey, t)`, when given, says whether a card held back for seasons (catalog card.seasonal) may be acquired at time t. It is
// consulted only on a binder that has recorded mode/launch1; the server supplies it from the scheduled seasons (a card is available from the
// start of the first season that features it, for good).
function applyEvent(state, event, catalog, strict = false, available = null) {
    if (event.t < state.lastT) return "time";
    const card = catalog.cards[event.key];
    const isPackKey = event.key.startsWith("pack:");
    const pack = isPackKey ? packInfo(catalog, event.key.slice(5)) : null;
    const packZone = pack?.id;
    const packTrade = isPackKey && (event.kind === "tradeIn" || event.kind === "tradeOut");
    if (packTrade && !pack) return "unknown-set";
    const before = packTrade ? state.packs[packZone] || 0 : state.counts[event.key] || 0;
    const isCardEvent = event.kind !== "set" && event.kind !== "mode" && event.kind !== "packFind" && event.kind !== "packOpen" && event.kind !== "seasonReward";
    if (isCardEvent && !card && !packTrade) return "unknown-card";
    if (card && card.baseKey && (event.kind === "miss" || event.kind === "craft")) return "edition";
    if (card && card.baseKey && !state.editions && (event.kind === "drop" || event.kind === "packCard")) return "edition";
    if (state.launch === 1 && available && card && (event.kind === "drop" || event.kind === "miss" || event.kind === "packCard" || event.kind === "craft")) {
        const baseKey = card.baseKey || event.key;
        if (catalog.cards[baseKey]?.seasonal && !available(baseKey, event.t)) return "retired";
    }
    if (card && card.balanceOnly && !(state.balance >= 1) && (event.kind === "drop" || event.kind === "packCard")) return "balance";
    // Only a drop may be shiny; only a drop, a miss or the switch into ranked2 may use the tape; only a recycle or a craft moves dust.
    const usesTape = event.kind === "drop" || event.kind === "miss" || event.kind === "packFind" || event.kind === "packOpen" || event.kind === "packCard"
        || (event.kind === "mode" && event.key === "ranked2");
    if (event.kind !== "drop" && event.kind !== "packCard" && event.shiny !== 0) return "field";
    // While a pack is being opened nothing else may happen until its five cards are written.
    if (state.packLeft > 0 && event.kind !== "packCard") return "pack";
    if (!usesTape && event.tape !== 0) return "field";
    if (event.kind !== "recycle" && event.kind !== "craft" && event.dust !== 0) return "dust";
    if (event.kind !== "tradeIn" && event.kind !== "tradeOut" && event.kind !== "seasonReward" && (event.partner !== "" || event.trade !== "")) return "trade";
    let counts = state.counts;
    switch (event.kind) {
        case "seasonReward": {
            if (!packInfo(catalog, event.key) || event.partner !== "" || !/^[0-9a-f]{32}$/.test(event.trade)) return "season-reward";
            if (state.seasonClaims?.[event.trade] || event.count !== (state.packs[event.key] || 0) + 1) return "season-reward";
            state.seasonClaims = { ...(state.seasonClaims || {}), [event.trade]: true };
            state.packs[event.key] = event.count;
            break;
        }
        case "drop": {
            if (event.count !== before + 1) return "count";
            if (event.shiny === 1 && state.shiny[event.key]) return "shiny";
            if (state.mode === "ranked2") {
                if (event.tape !== state.lastTape + 1) return "tape";
            } else if (state.mode === "ranked") {
                if (strict || event.tape < 1 || event.tape <= state.lastTape) return "tape";
            } else if (event.tape !== 0) {
                return "tape";
            }
            if (event.shiny === 1) state.shiny[event.key] = true;
            if (event.tape > 0) { state.lastTape = event.tape; state.lastAttempt = { key: event.key, tape: event.tape }; }
            break;
        }
        case "miss": {
            // A run of `count` attempts on this card that all missed, using the `count` tape entries that end at `tape`.
            if (state.mode !== "ranked2") return "mode";
            if (event.count < 1) return "miss";
            if (event.tape - event.count !== state.lastTape) return "tape";
            state.lastTape = event.tape;
            state.lastAttempt = { key: event.key, tape: event.tape };
            break;
        }
        case "packFind": {
            // A pack found on the attempt just written down: it belongs to that creature's zone. `count` is the packs held
            // of that zone afterwards.
            const info = packInfo(catalog, event.key);
            if (!info) return "unknown-set";
            if (!state.tieredPacks && info.tier !== "epic") return "pack";
            const held = state.packs[event.key] || 0;
            if (event.count !== held + 1) return "pack";
            if (state.mode === "ranked2") {
                const last = catalog.cards[state.lastAttempt.key];
                if (event.tape < 1 || event.tape !== state.lastAttempt.tape || event.tape <= state.packFound) return "tape";
                if (!last || last.profession || last.set !== info.zone) return "pack";
                state.packFound = event.tape;
            } else if (event.tape !== 0) {
                return "tape";
            }
            state.packs[event.key] = held + 1;
            break;
        }
        case "packOpen": {
            const info = packInfo(catalog, event.key);
            if (!info) return "unknown-set";
            const held = state.packs[event.key] || 0;
            if (held < 1 || event.count !== held - 1) return "pack";
            if (state.mode === "ranked2") {
                if (event.tape !== state.lastTape) return "tape"; // names the last entry used so far, like the switch into ranked2
            } else if (event.tape !== 0) {
                return "tape";
            }
            if (held === 1) delete state.packs[event.key]; else state.packs[event.key] = held - 1;
            state.packZone = info.zone;
            state.packType = info.id;
            state.packLeft = info.size;
            break;
        }
        case "packCard": {
            if (state.packLeft < 1 || card.set !== state.packZone) return "pack";
            if (event.count !== before + 1) return "count";
            if (event.shiny === 1 && state.shiny[event.key]) return "shiny";
            if (state.mode === "ranked2") {
                if (event.tape !== state.lastTape + 1) return "tape";
            } else if (event.tape !== 0) {
                return "tape";
            }
            if (event.shiny === 1) state.shiny[event.key] = true;
            if (event.tape > 0) state.lastTape = event.tape;
            state.packLeft -= 1;
            // Once packs have been received, preserve a conservative dependency from
            // that zone's pack trades to their opened cards, including later trades.
            if (state.packOutputs?.[state.packType || state.packZone]) {
                const outputs = state.packOutputs[state.packType || state.packZone];
                outputs[event.key] = (outputs[event.key] || 0) + 1;
            }
            break;
        }
        case "craft": {
            if (state.balance >= 1 && card.dropProfile?.noCraft) return "craft";
            if (before !== 0 || event.count !== 1) return "craft";
            if (event.dust !== -catalog.dust.craft[card.rarity]) return "dust";
            break;
        }
        case "recycle": {
            if (before < 2 || event.count !== before - 1) return "recycle";
            if (event.dust !== catalog.dust.recycle[card.rarity]) return "dust";
            break;
        }
        case "tradeOut": {
            if (before < 1 || event.count !== before - 1) return "trade";
            if (event.partner === "" || event.trade === "") return "trade";
            break;
        }
        case "tradeIn": {
            if (event.count !== before + 1) return "trade";
            if (event.partner === "" || event.trade === "") return "trade";
            if (packTrade) {
                state.packOutputs ||= {};
                state.packOutputs[packZone] ||= {};
            }
            break;
        }
        case "set": {
            const set = catalog.sets.find((entry) => entry.code === event.key);
            if (!set) return "unknown-set";
            if (event.count !== 0 || state.sets[set.code]) return "set";
            if (!(set.required || set.cards).every((key) => familyCount(catalog, counts, key) > 0)) return "set"; // a page is finished by its launch cards (set.required, when the catalog names them)
            state.sets[set.code] = true;
            break;
        }
        case "mode": {
            if (event.key === "packs2") {
                if (event.count !== 0 || state.tieredPacks) return "mode";
                state.tieredPacks = true;
                break;
            }
            if (event.key === "chase1") {
                if (event.count !== 0 || state.balance >= 1) return "mode";
                state.balance = 1;
                state.balanceAttempts = {}; state.balanceDrops = {}; state.balanceReady = {};
                break;
            }
            if (event.key === "chase2") {
                // The second drop generation (rates in dropProfile.rate2). Only after chase1, once. Miss runs carry over; the luck statistics
                // start afresh, because the chances they compare against have changed.
                if (event.count !== 0 || state.balance !== 1) return "mode";
                state.balance = 2;
                state.balanceAttempts = {}; state.balanceDrops = {}; state.balanceReady = {};
                break;
            }
            if (event.key === "launch1") {
                // The launch collection: from here on a card held back for seasons is not acquired until a season has released it. Only after
                // chase2, once. Nothing already owned changes.
                if (event.count !== 0 || state.balance !== 2 || state.launch === 1) return "mode";
                state.launch = 1;
                break;
            }
            if (event.key === "editions1") {
                if (event.count !== 0) return "mode";
                state.editions = true;
                break;
            }
            if (!SET_MODES.includes(event.key) || event.count !== 0) return "mode";
            if (event.key === "ranked" && strict) return "mode";
            if (event.key === "ranked2") {
                // `tape` is the last entry used so far: recording starts after it.
                const gap = event.tape - state.lastTape;
                if (gap < 0 || (state.exact ? gap !== 0 : gap > BASELINE_GAP)) return "tape";
                state.lastTape = event.tape;
                state.exact = true;
            }
            state.mode = event.key;
            break;
        }
        default:
            return "kind";
    }
    if (state.balance >= 1 && event.tape > 0 && (event.kind === "drop" || event.kind === "miss")) {
        const source = card.baseKey || event.key;
        // The first cycle may have inherited old pity. Start statistics after its
        // first drop, so only complete cycles under this policy are compared.
        if (state.balanceReady[source]) {
            state.balanceAttempts[source] = (state.balanceAttempts[source] || 0) + (event.kind === "miss" ? event.count : 1);
            if (event.kind === "drop") state.balanceDrops[source] = (state.balanceDrops[source] || 0) + 1;
        } else if (event.kind === "drop") state.balanceReady[source] = true;
    }
    if (packTrade) {
        if (event.count === 0) delete state.packs[packZone]; else state.packs[packZone] = event.count;
    } else if (isCardEvent && event.kind !== "miss") counts[event.key] = event.count;
    const dust = state.dust + event.dust;
    if (dust < 0) return "dust";
    state.dust = dust;
    state.lastT = event.t;
    return null;
}

// Replay events from `start` (default: a new binder). Returns { ok: true, state } or
// { ok: false, error: "rule", rule, index }. The state passed in is never changed.
function replay(events, catalog, start = newState(), options = {}) {
    const state = copyState(start);
    for (let index = 0; index < events.length; index++) {
        // An old "ranked" switch is let through for a new upload only when the very next event is another mode switch: nothing
        // was rolled under the first kind of Ranked, which the server could not check. (A player who switched to Ranked on the
        // old add-on and then updated has one of these in their history, written before the update.) Any roll that follows it
        // without a switch is still refused.
        const event = events[index];
        const next = events[index + 1];
        const quiet = event.kind === "mode" && event.key === "ranked" && next !== undefined && next.kind === "mode";
        const rule = applyEvent(state, event, catalog, options.strict === true && !quiet, options.available || null);
        if (rule) return { ok: false, error: "rule", rule, index };
    }
    return { ok: true, state };
}

// The snapshot in an upload against the state the replay reached. Returns the names that differ.
function snapshotDifferences(snapshot, state) {
    const wrong = [];
    const same = (a, b) => {
        const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
        for (const key of keys) if ((a[key] || 0) !== (b[key] || 0)) return false;
        return true;
    };
    if (!same(snapshot.counts || {}, state.counts)) wrong.push("counts");
    if ((snapshot.dust || 0) !== state.dust) wrong.push("dust");
    const sets = Object.keys(snapshot.sets || {}).sort().join(",");
    if (sets !== Object.keys(state.sets).sort().join(",")) wrong.push("sets");
    return wrong;
}

module.exports = { newState, copyState, applyEvent, replay, snapshotDifferences, BASELINE_GAP };
