"use strict";

function profileChance(profile, misses, factor = 1) {
    const rate = profile.rate;
    if (profile.style !== "chase") return Math.min(10000, rate + rate * factor * misses);
    const limit = Math.ceil(10000 / rate), start = Math.floor(limit * .75);
    if (misses >= limit - 1) return 10000;
    if (misses <= start) return rate;
    return rate + Math.floor((10000 - rate) * (misses - start) / (limit - 1 - start));
}

// `balanced` is the drop generation a binder is on: false for the original rank rates, 1 (or true) after mode/chase1, which uses each
// card's dropProfile, and 2 after mode/chase2, which uses dropProfile.rate2 in place of dropProfile.rate (docs/LEDGER-SPEC.md).
/** @param {any} catalog @param {string} key @param {boolean | number} [balanced] */
function profileFor(catalog, key, balanced = false) {
    const entry = catalog.cards[key];
    const source = entry && catalog.cards[entry.baseKey || key];
    if (!(balanced && source && source.dropProfile)) return { rate: source ? catalog.rates[source.rank] || 0 : 0, style: "stack", packWeight: 100 };
    const profile = source.dropProfile;
    return balanced === 2 && Number.isInteger(profile.rate2) ? { ...profile, rate: profile.rate2 } : profile;
}

/** @param {any} catalog @param {string} key @param {number} misses @param {boolean | number} [balanced] */
const chanceFor = (catalog, key, misses, balanced = false) => profileChance(profileFor(catalog, key, balanced), misses, catalog.stackFactor);
module.exports = { profileChance, profileFor, chanceFor };
