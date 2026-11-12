"use strict";

function profileChance(profile, misses, factor = 1) {
    const rate = profile.rate;
    if (profile.style !== "chase") return Math.min(10000, rate + rate * factor * misses);
    const limit = Math.ceil(10000 / rate), start = Math.floor(limit * .75);
    if (misses >= limit - 1) return 10000;
    if (misses <= start) return rate;
    return rate + Math.floor((10000 - rate) * (misses - start) / (limit - 1 - start));
}

function profileFor(catalog, key, balanced = false) {
    const entry = catalog.cards[key];
    const source = entry && catalog.cards[entry.baseKey || key];
    return balanced && source && source.dropProfile
        ? source.dropProfile
        : { rate: source ? catalog.rates[source.rank] || 0 : 0, style: "stack", packWeight: 100 };
}

const chanceFor = (catalog, key, misses, balanced = false) => profileChance(profileFor(catalog, key, balanced), misses, catalog.stackFactor);
module.exports = { profileChance, profileFor, chanceFor };
