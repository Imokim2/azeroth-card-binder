"use strict";
// Card packs (docs/LEDGER-SPEC.md, section 8.2). Any attempt on a creature can find a pack, and a pack holds five cards
// from the zone (a set of the catalog) it was found in. Both are decided by tape entries, so the server can recheck them.
//
// A tape entry is 16 hex characters: the first 8 give the roll (1 to 10000) and the next 8 are split two ways, because the
// shiny roll and these draws must not depend on each other: `hex2 mod shinyOdds` is the shiny remainder (spec 8), and
// `floor(hex2 / shinyOdds)` is what is used here.

const PACK_ODDS = 500; // a pack is found on 1 attempt in 500
const PACK_SIZE = 5; // cards in a pack
// Chance of each rarity, out of 10000, before the rarities a zone does not have are left out.
const PACK_RARITIES = [["common", 7000], ["rare", 2000], ["epic", 800], ["legendary", 200]];

const secondHalf = (entry) => parseInt(entry.slice(8, 16), 16);
const rollOf = (entry) => (parseInt(entry.slice(0, 8), 16) % 10000) + 1;

// 1 when the attempt that used this entry found a pack.
const packValue = (entry, shinyOdds) => (Math.floor(secondHalf(entry) / shinyOdds) % PACK_ODDS) + 1;
const packFound = (entry, shinyOdds) => packValue(entry, shinyOdds) === 1;
const PACK_TIERS = { common: 1, rare: 3, epic: 5 };
function packInfo(catalog, id) {
    if (typeof id !== 'string') return null;
    const match = /^([A-Z][A-Z0-9]*)(?::(common|rare))?$/.exec(id);
    if (!match || !catalog.sets.some(set => set.code === match[1])) return null;
    const tier = match[2] || 'epic';
    return { id, zone: match[1], tier, size: PACK_TIERS[tier] };
}
function packTier(entry, shinyOdds) {
    const draw = Math.floor(secondHalf(entry) / shinyOdds / PACK_ODDS) % 100;
    return draw < 70 ? 'common' : draw < 95 ? 'rare' : 'epic';
}

const byNumber = (a, b) => (Number(a.split(":")[1]) - Number(b.split(":")[1])) || (a < b ? -1 : a > b ? 1 : 0);

// The cards of a zone by rarity, each rarity in order of card number (then key), leaving out rarities the zone has none of.
// The order is fixed here so that every implementation numbers the cards of a pool the same way.
// `available(key)`, when given, leaves out cards that may not be found yet (cards held back for seasons: see rules.js).
function packPools(catalog, zone, available = null) {
    const set = catalog.sets.find((entry) => entry.code === zone);
    if (!set) return [];
    return PACK_RARITIES
        .map(([rarity, weight]) => ({
            rarity, weight,
            cards: set.cards.filter((key) => catalog.cards[key] && catalog.cards[key].rarity === rarity && (!available || available(key))).sort(byNumber),
        }))
        .filter((pool) => pool.cards.length > 0);
}

// The card a tape entry gives from a zone's pack: the rarity from the roll, then a card of that rarity from the rest.
// Only whole numbers are used, so every implementation gets the same answer. Returns the card key, or null for an unknown zone.
function packPick(catalog, zone, entry, shinyOdds, balanced = false, available = null) {
    const pools = packPools(catalog, zone, available);
    if (pools.length === 0) return null;
    const total = pools.reduce((sum, pool) => sum + pool.weight, 0);
    const scaled = (rollOf(entry) - 1) * total; // 0 up to 10000 * total, compared with weights scaled by 10000
    let upTo = 0;
    let chosen = pools[pools.length - 1];
    for (const pool of pools) {
        upTo += pool.weight * 10000;
        if (scaled < upTo) { chosen = pool; break; }
    }
    const draw = Math.floor(secondHalf(entry) / shinyOdds);
    if (!balanced) return chosen.cards[draw % chosen.cards.length];
    const weights = chosen.cards.map(key => catalog.cards[key].dropProfile?.packWeight ?? 100);
    let index = draw % weights.reduce((sum, weight) => sum + weight, 0);
    for (let i = 0; i < chosen.cards.length; i++) {
        index -= weights[i];
        if (index < 0) return chosen.cards[i];
    }
    return null;
}

module.exports = { PACK_ODDS, PACK_SIZE, PACK_RARITIES, PACK_TIERS, packInfo, packTier, packValue, packFound, packPools, packPick };
