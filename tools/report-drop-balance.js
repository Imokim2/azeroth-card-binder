// Developer-only pacing report. Exact rates are intentionally absent from player UI.
const catalog = require('../packages/shared/catalog.json');
const { profileChance } = require('../packages/shared/src/drops.js');
function meanWait(profile) {
    let survival = 1, mean = 0;
    for (let misses = 0; survival > 1e-15; misses++) {
        mean += survival;
        survival *= 1 - profileChance(profile, misses, catalog.stackFactor) / 10000;
    }
    return mean;
}
const tiers = {};
const second = {}; // the same cards at the second generation's rates (dropProfile.rate2, mode/chase2)
for (const [key, card] of Object.entries(catalog.cards)) {
    if (card.baseKey) continue;
    const profile = card.dropProfile;
    const group = tiers[profile.tier] ||= { cards: 0, waits: [], relative: [] };
    const wait = meanWait(profile);
    group.cards++; group.waits.push(wait);
    (second[profile.tier] ||= []).push(meanWait({ ...profile, rate: profile.rate2 }));
    group.relative.push(wait / meanWait({ rate: catalog.rates[card.rank], style: 'stack' }));
}
const median = (values) => values.sort((a, b) => a - b)[Math.floor(values.length / 2)];
for (const [tier, group] of Object.entries(tiers)) {
    console.log(`${tier}: ${group.cards} cards; expected attempts ${Math.min(...group.waits).toFixed(1)}–${Math.max(...group.waits).toFixed(1)}; median ${median(group.waits).toFixed(1)}; median wait vs old ${median(group.relative).toFixed(2)}x`);
}
console.log('\nSecond generation (mode/chase2, dropProfile.rate2): median expected attempts');
for (const [tier, waits] of Object.entries(second)) console.log(`${tier}: median ${median(waits).toFixed(1)} (was ${median(tiers[tier].waits.slice()).toFixed(1)}); range ${Math.min(...waits).toFixed(1)}–${Math.max(...waits).toFixed(1)}`);
