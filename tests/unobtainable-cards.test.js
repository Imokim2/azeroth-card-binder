// Cards whose creature cannot be killed (AzerothCardBinder/UnobtainableCards.lua, docs/UNOBTAINABLE-CARDS.md): never at launch, never released by a
// season, never needed to finish a page; and the add-on's list, the catalog and the generated launch list all agree.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const catalog = require('../packages/shared/catalog.json');
const { draft } = require('../tools/launch-collection.js');

const listed = [...fs.readFileSync(path.join(__dirname, '..', 'AzerothCardBinder', 'UnobtainableCards.lua'), 'utf8').matchAll(/^\s*\["(npc:\d+)"\] = "([^"]+)"/gm)]
    .map(match => ({ key: match[1], reason: match[2] }));
const flagged = Object.entries(catalog.cards).filter(([, card]) => card.unobtainable).map(([key]) => key);

test('the add-on list and the catalog name the same cards, each with a reason, and every key is a real creature card', () => {
    assert.equal(listed.length, 31);
    assert.deepEqual(flagged.sort(), listed.map(item => item.key).sort());
    for (const { key, reason } of listed) {
        assert.ok(catalog.cards[key] && !catalog.cards[key].baseKey, key + ' is a base card');
        assert.ok(reason.length > 12, key + ' says why');
    }
    assert.equal(listed.filter(item => /companion pet/.test(item.reason)).length, 6, 'the six companion pets');
    assert.equal(listed.filter(item => /one-off/.test(item.reason)).length, 8, 'the eight one-off kills');
    assert.equal(listed.filter(item => /dungeon creature the data lists as friendly/.test(item.reason)).length, 13, 'the thirteen friendly dungeon characters');
});

test('an unobtainable card is held back for good: not at launch, not required by its page, and not counted against the half', () => {
    const result = draft(catalog);
    const launch = new Set(result.launch);
    for (const key of flagged) {
        assert.ok(!launch.has(key), key + ' is not at launch');
        assert.ok(catalog.cards[key].seasonal, key + ' is held back');
        const set = catalog.sets.find(entry => entry.code === catalog.cards[key].set);
        assert.ok(!(set.required || set.cards).includes(key), key + ' is not needed to finish its page');
    }
    assert.deepEqual(result.unobtainable.slice().sort(), flagged.slice().sort());
    assert.equal(result.launch.length, Math.floor((result.launch.length + result.seasons.length) / 2), 'the launch collection is still exactly half of the cards both factions can win');
});

test('the draft files mark them "never" so a reviewer can see them', () => {
    const csv = fs.readFileSync(path.join(__dirname, '..', 'docs', 'seasons', 'launch-collection-draft.csv'), 'utf8');
    assert.equal(csv.split(/\r?\n/).filter(line => /,"never"$/.test(line)).length, flagged.length);
    const json = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'docs', 'seasons', 'launch-collection-draft.json'), 'utf8'));
    assert.deepEqual(json.unobtainable.slice().sort(), flagged.slice().sort());
});
