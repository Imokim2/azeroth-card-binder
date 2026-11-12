"use strict";
function baseKey(catalog, key) { return catalog.cards[key]?.baseKey || key; }
function editionKeys(catalog, key) {
    const base = baseKey(catalog, key);
    return [base, ...(catalog.editions?.[base] || []).map((edition) => edition.key)];
}
function familyCount(catalog, counts, key) { return editionKeys(catalog, key).reduce((total, item) => total + (counts[item] || 0), 0); }
function pickEdition(catalog, key, roll) {
    const base = baseKey(catalog, key);
    let upTo = 0;
    for (const edition of catalog.editions?.[base] || []) {
        upTo += edition.weight;
        if (roll <= upTo) return edition.key;
    }
    return base;
}
module.exports = { baseKey, editionKeys, familyCount, pickEdition };
