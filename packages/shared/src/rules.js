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
// Spec 12, the campfire (docs/CAMPFIRE.md): standing at a camp with its buff doubles the chance of a card drop. A boosted attempt is written with partner
// "camp". The camp event says how long the buff has left, which can be at most the buff's own length.
const CAMP_SECONDS = { welcoming: 3600, violet: 7200 };
const CAMP_GRACE = 120; // a boosted drop may be written this long after the claimed buff ended (the add-on notices a buff ending a moment later)
const CAMP_FACTOR = 2;
// The boost is for ordinary creatures: the cards of common and rare rarity. Elites, rare spawns and bosses (epic and legendary cards) are not boosted.
const CAMP_RARITIES = ["common", "rare"];
const { familyCount } = require("./editions.js");
const { packInfo } = require("./packs.js");
const bonusEvents = require("./bonus-events.js");

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
    ...(state.faction === 1 ? { faction: 1, sides: { ...(state.sides || {}) } } : {}),
    ...(state.balance >= 1 ? { balance: state.balance, balanceAttempts: { ...(state.balanceAttempts || {}) },
        balanceDrops: { ...(state.balanceDrops || {}) }, balanceReady: { ...(state.balanceReady || {}) } } : {}),
    ...(state.packOutputs ? { packOutputs: Object.fromEntries(Object.entries(state.packOutputs).map(([zone, cards]) => [zone, { ...cards }])) } : {}),
    ...(state.packType ? { packType: state.packType } : {}),
    ...(state.tieredPacks ? { tieredPacks: true } : {}),
    ...(state.seasonClaims ? { seasonClaims: { ...state.seasonClaims } } : {}),
    ...(state.guild === 1 ? { guild: 1, donations: { ...(state.donations || {}) } } : {}),
    ...(state.camp === 1 ? { camp: 1, campEnd: state.campEnd || 0, campBoosted: state.campBoosted || 0 } : {}),
    ...(state.fellow === 1 ? { fellow: 1, credits: { ...(state.credits || {}) }, ...(state.lastOut ? { lastOut: { ...state.lastOut } } : {}) } : {}),
});

// An activity card (Fellowship) can be tried for only as often as its activity was completed. Returns true when this attempt has no roll to use; otherwise
// spends `attempts` rolls. (Called only once the rest of the event is known to be fine, so a refused event changes nothing.)
function spendActivity(state, catalog, event, attempts) {
    const activity = catalog.cards[event.key]?.activity;
    if (!activity) return false;
    if (state.fellow !== 1 || (state.credits?.[activity] || 0) < attempts) return true;
    state.credits = { ...state.credits, [activity]: state.credits[activity] - attempts };
    return false;
}

// Returns the name of the rule an event breaks, or null. Mutates `state` only when the event is fine.
// `available(baseKey, t)`, when given, says whether a card held back for seasons (catalog card.seasonal) may be acquired at time t. It is
// consulted only on a binder that has recorded mode/launch1; the server supplies it from the scheduled seasons (a card is available from the
// start of the first season that features it, for good).
function applyEvent(state, event, catalog, strict = false, available = null, bonuses = {}, serverNow = Infinity) {
    if (event.t < state.lastT) return "time";
    const card = catalog.cards[event.key];
    const isPackKey = event.key.startsWith("pack:");
    const pack = isPackKey ? packInfo(catalog, event.key.slice(5)) : null;
    const packZone = pack?.id;
    const packTrade = isPackKey && (event.kind === "tradeIn" || event.kind === "tradeOut");
    if (packTrade && !pack) return "unknown-set";
    const before = packTrade ? state.packs[packZone] || 0 : state.counts[event.key] || 0;
    const isCardEvent = event.kind !== "set" && event.kind !== "mode" && event.kind !== "packFind" && event.kind !== "packOpen" && event.kind !== "seasonReward" && event.kind !== "camp";
    if (isCardEvent && !card && !packTrade) return "unknown-card";
    if (card && card.baseKey && (event.kind === "miss" || event.kind === "craft")) return "edition";
    if (card && card.baseKey && !state.editions && (event.kind === "drop" || event.kind === "packCard")) return "edition";
    if (state.launch === 1 && available && card && (event.kind === "drop" || event.kind === "miss" || event.kind === "packCard" || event.kind === "craft")) {
        const baseKey = card.baseKey || event.key;
        const base = catalog.cards[baseKey];
        const seasonal = state.faction === 1 ? base?.seasonal : (base?.seasonalBeforeFaction ?? base?.seasonal);
        if (seasonal && !available(baseKey, event.t)) return "retired";
    }
    // Cards added in spec 10 (catalog card.since) are not acquired before mode/faction1, and a card only one faction can win (card.faction) is
    // acquired only by a character that has declared that faction (mode/side:alliance or mode/side:horde, once per character).
    if (card && (event.kind === "drop" || event.kind === "miss" || event.kind === "packCard" || event.kind === "craft")) {
        const added = catalog.cards[card.baseKey || event.key];
        if (added?.since && state.faction !== 1) return "retired";
        if (added?.faction && state.sides?.[event.char] !== added.faction) return "faction";
    }
    // An activity card is earned by its activity and nothing else: it cannot be crafted. (A pack never holds one, and a trade or a donation of it is fine.)
    if (card?.activity && event.kind === "craft") return "activity";
    if (card && card.balanceOnly && !(state.balance >= 1) && (event.kind === "drop" || event.kind === "packCard")) return "balance";
    // Only a drop may be shiny; only a drop, a miss or the switch into ranked2 may use the tape; only a recycle or a craft moves dust.
    const usesTape = event.kind === "drop" || event.kind === "miss" || event.kind === "packFind" || event.kind === "packOpen" || event.kind === "packCard"
        || (event.kind === "mode" && event.key === "ranked2");
    if (event.kind !== "drop" && event.kind !== "packCard" && event.shiny !== 0) return "field";
    // While a pack is being opened nothing else may happen until its five cards are written.
    if (state.packLeft > 0 && event.kind !== "packCard") return "pack";
    if (!usesTape && event.tape !== 0) return "field";
    if (event.kind !== "recycle" && event.kind !== "craft" && event.dust !== 0) return "dust";
    // An attempt made at a camp with its buff says so in `partner`. Only a Ranked attempt can be boosted, and a boosted drop must fall within the buff the
    // binder claimed (a run of misses is written when something else happens, so its own time says nothing about when its attempts were made).
    const bonus = bonusEvents.isBonus(event) ? bonusEvents.forEvent(event, catalog, bonuses, state.lastT, serverNow) : null;
    if (bonusEvents.isBonus(event) && (!bonus || state.mode !== "ranked2")) return "bonus";
    const boosted = (event.kind === "drop" || event.kind === "miss") && ((event.partner === "camp" && event.trade === "") || (event.partner === "camp-bonus" && bonus));
    if (boosted) {
        if (state.camp !== 1 || state.mode !== "ranked2" || event.tape < 1) return "camp";
        if (!CAMP_RARITIES.includes(catalog.cards[card.baseKey || event.key]?.rarity)) return "camp";
        if (event.kind === "drop" && event.t > (state.campEnd || 0) + CAMP_GRACE) return "camp";
    }
    if (!boosted && !bonus && event.kind !== "tradeIn" && event.kind !== "tradeOut" && event.kind !== "seasonReward" && event.kind !== "donate" && event.kind !== "donateReturn" && (event.partner !== "" || event.trade !== "")) return "trade";
    let counts = state.counts;
    switch (event.kind) {
        // Spec 12: the binder says it is standing at a camp with its buff, and how long the buff has left. Only a Ranked binder that has recorded
        // mode/camp1. The buff cannot have more time left than it lasts, and the claim can only reach further than the one before.
        case "camp": {
            if (state.camp !== 1 || state.mode !== "ranked2") return "camp";
            const longest = CAMP_SECONDS[event.key];
            if (!longest || event.count < 1 || event.count > longest) return "camp";
            state.campEnd = Math.max(state.campEnd || 0, event.t + event.count);
            break;
        }
        // Spec 11: a Ranked binder gives one copy of a card to its guild (docs/proposals/GUILD-BINDERS-DESIGN.md). `partner` is the guild's id and
        // `trade` an operation id made up by the add-on, used once. The copy leaves the binder at once. The server credits the guild, or
        // refuses and issues the copy back, which the binder then writes as donateReturn (the same operation, guild and card).
        case "donate": {
            if (state.guild !== 1 || isPackKey || (state.mode !== "ranked" && state.mode !== "ranked2")) return "donate";
            if (before < 1 || event.count !== before - 1) return "donate";
            if (!/^[0-9A-Z]{26}$/.test(event.partner) || !/^[0-9a-f]{32}$/.test(event.trade) || state.donations?.[event.trade]) return "donate";
            state.donations = { ...(state.donations || {}), [event.trade]: event.partner + "|" + event.key };
            break;
        }
        case "donateReturn": {
            if (state.guild !== 1 || isPackKey || event.count !== before + 1) return "donate";
            if (state.donations?.[event.trade] !== event.partner + "|" + event.key) return "donate";
            state.donations = { ...state.donations, [event.trade]: "returned" };
            break;
        }
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
            if (spendActivity(state, catalog, event, 1)) return "activity";
            if (event.shiny === 1) state.shiny[event.key] = true;
            if (event.tape > 0) { state.lastTape = event.tape; state.lastAttempt = { key: event.key, tape: event.tape }; }
            break;
        }
        case "miss": {
            // A run of `count` attempts on this card that all missed, using the `count` tape entries that end at `tape`.
            if (state.mode !== "ranked2") return "mode";
            if (event.count < 1) return "miss";
            if (event.tape - event.count !== state.lastTape) return "tape";
            if (spendActivity(state, catalog, event, event.count)) return "activity";
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
            const required = state.faction === 1 ? set.required : (set.requiredBeforeFaction || set.required);
            if (!(required || set.cards).every((key) => familyCount(catalog, counts, key) > 0)) return "set";
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
            if (event.key === "faction1") {
                // Spec 10: the cards added with factions exist from here on, and a character declares its faction. Only after launch1, once.
                if (event.count !== 0 || state.launch !== 1 || state.faction === 1) return "mode";
                state.faction = 1;
                state.sides = {};
                break;
            }
            if (event.key === "side:alliance" || event.key === "side:horde") {
                // A character's faction, declared once, before it acquires a card only one faction can win.
                if (event.count !== 0 || state.faction !== 1 || state.sides[event.char]) return "mode";
                state.sides = { ...state.sides, [event.char]: event.key.slice(5) };
                break;
            }
            if (event.key === "guild1") {
                // Spec 11: a binder may donate to its guild from here on. Only after faction1, once.
                if (event.count !== 0 || state.faction !== 1 || state.guild === 1) return "mode";
                state.guild = 1;
                state.donations = {};
                break;
            }
            if (event.key === "fellow1") {
                // Spec 12: activities earn rolls for the Fellowship cards from here on. Only after faction1, once.
                if (event.count !== 0 || state.faction !== 1 || state.fellow === 1) return "mode";
                state.fellow = 1;
                state.credits = { trade: 0, gift: 0, donate: 0, camp: 0 };
                break;
            }
            if (event.key === "camp1") {
                // Spec 12: campfire boosts are allowed from here on. Only after faction1, once.
                if (event.count !== 0 || state.faction !== 1 || state.camp === 1) return "mode";
                state.camp = 1;
                state.campEnd = 0;
                state.campBoosted = 0;
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
    // Spec 12, the Fellowship cards (docs/FELLOWSHIP.md): each completed activity earns one roll for its card, and a drop or miss of an activity card
    // spends one. A swap is a tradeOut with its tradeIn straight after; a tradeOut with none is a gift given, a tradeIn with no tradeOut before it a
    // gift received. Both sides of a swap, and both ends of a gift, earn a roll. Nothing is earned before mode/fellow1.
    if (state.fellow === 1) {
        const earn = (activity, amount = 1) => { state.credits = { ...(state.credits || {}), [activity]: (state.credits?.[activity] || 0) + amount }; };
        if (event.kind === "tradeOut") { earn("gift"); state.lastOut = { trade: event.trade, seq: event.seq }; }
        else if (event.kind === "tradeIn") {
            if (state.lastOut && state.lastOut.trade === event.trade && state.lastOut.seq === event.seq - 1) { earn("gift", -1); earn("trade"); } else earn("gift");
        } else if (event.kind === "donate") earn("donate");
        else if (event.kind === "camp") earn("camp");
    }
    if (state.balance >= 1 && event.tape > 0 && (event.kind === "drop" || event.kind === "miss")) {
        const source = card.baseKey || event.key;
        // The first cycle may have inherited old pity. Start statistics after its
        // first drop, so only complete cycles under this policy are compared.
        if (state.balanceReady[source]) {
            // A boosted attempt had double the chance, so it counts double in the luck statistics: a camper is not mistaken for a lucky player.
            const attempts = event.kind === "miss" ? event.count : 1;
            state.balanceAttempts[source] = (state.balanceAttempts[source] || 0) + attempts * (boosted ? CAMP_FACTOR : 1) * (bonus ? bonus.percent / 100 : 1);
            if (event.kind === "drop") state.balanceDrops[source] = (state.balanceDrops[source] || 0) + 1;
        } else if (event.kind === "drop") state.balanceReady[source] = true;
    }
    if (boosted) state.campBoosted = (state.campBoosted || 0) + (event.kind === "miss" ? event.count : 1);
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
        const rule = applyEvent(state, event, catalog, options.strict === true && !quiet, options.available || null, options.bonuses || {}, options.serverNow ?? Infinity);
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

module.exports = { newState, copyState, applyEvent, replay, snapshotDifferences, BASELINE_GAP, CAMP_SECONDS, CAMP_GRACE, CAMP_FACTOR, CAMP_RARITIES };
