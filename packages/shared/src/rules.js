"use strict";
// What the events of a ledger must mean (docs/LEDGER-SPEC.md, section 3.1), checked by replaying them.
//
// ledger.js checks that a chain is intact (hashes, order, field shapes). This file checks that the chain
// describes a binder that could really exist: counts go up and down by one, dust balances, a card is crafted only
// when missing, a set is finished only when every card is owned, and so on. The server runs it on every upload;
// the app may run it before uploading. It is pure: no clock, no network, no storage. The catalog is passed in.
//
// A "state" is everything the rules need to remember between events. It is plain data so a server can store it
// and resume from it: { counts, dust, shiny, sets, mode, lastTape, lastT, exact }.
//
// Ranked comes in two kinds. "ranked" is the first version, in which only drops were written down and the misses
// between them were not; it is only ever replayed from history. "ranked2" writes down every attempt: a drop, or a
// `miss` event for a run of consecutive misses on one card, so the tape positions used follow each other without a
// gap and the server can check every roll. `strict` (used when an upload is accepted) refuses the first kind.

const SET_MODES = ["casual", "ranked", "ranked2"];
// The first time a binder enters ranked2 it may name a tape position this far past the last one it recorded, for the
// misses a binder kept before attempts were written down. Afterwards no gap is allowed at all.
const BASELINE_GAP = 2000;

function newState() {
    return { counts: {}, dust: 0, shiny: {}, sets: {}, mode: "casual", lastTape: 0, lastT: 0, exact: false };
}

const copyState = (state) => ({
    counts: { ...state.counts }, dust: state.dust, shiny: { ...state.shiny }, sets: { ...state.sets },
    mode: state.mode, lastTape: state.lastTape, lastT: state.lastT, exact: state.exact === true,
});

// Returns the name of the rule an event breaks, or null. Mutates `state` only when the event is fine.
function applyEvent(state, event, catalog, strict = false) {
    if (event.t < state.lastT) return "time";
    const card = catalog.cards[event.key];
    const before = state.counts[event.key] || 0;
    const isCardEvent = event.kind !== "set" && event.kind !== "mode";
    if (isCardEvent && !card) return "unknown-card";
    // Only a drop may be shiny; only a drop, a miss or the switch into ranked2 may use the tape; only a recycle or a craft moves dust.
    const usesTape = event.kind === "drop" || event.kind === "miss" || (event.kind === "mode" && event.key === "ranked2");
    if (event.kind !== "drop" && event.shiny !== 0) return "field";
    if (!usesTape && event.tape !== 0) return "field";
    if (event.kind !== "recycle" && event.kind !== "craft" && event.dust !== 0) return "dust";
    if (event.kind !== "tradeIn" && event.kind !== "tradeOut" && (event.partner !== "" || event.trade !== "")) return "trade";
    let counts = state.counts;
    switch (event.kind) {
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
            if (event.tape > 0) state.lastTape = event.tape;
            break;
        }
        case "miss": {
            // A run of `count` attempts on this card that all missed, using the `count` tape entries that end at `tape`.
            if (state.mode !== "ranked2") return "mode";
            if (event.count < 1) return "miss";
            if (event.tape - event.count !== state.lastTape) return "tape";
            state.lastTape = event.tape;
            break;
        }
        case "craft": {
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
            break;
        }
        case "set": {
            const set = catalog.sets.find((entry) => entry.code === event.key);
            if (!set) return "unknown-set";
            if (event.count !== 0 || state.sets[set.code]) return "set";
            if (!set.cards.every((key) => (counts[key] || 0) > 0)) return "set";
            state.sets[set.code] = true;
            break;
        }
        case "mode": {
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
    if (isCardEvent && event.kind !== "miss") counts[event.key] = event.count;
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
        const rule = applyEvent(state, events[index], catalog, options.strict === true);
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
