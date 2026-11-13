// Cards held back for seasons (docs/proposals/SMALLER-LAUNCH-COLLECTION.md; ledger marker mode/launch1, spec 9): the catalog names them,
// a page is finished by its launch cards alone, and on a binder that has recorded the marker an unreleased held-back card cannot be
// acquired, found in a pack or crafted. Everything before the marker, and every card that is not held back, is exactly as it was.
const test = require('node:test');
const assert = require('node:assert/strict');
const catalog = require('../packages/shared/catalog.json');
const { replay, newState } = require('../packages/shared/src/rules.js');
const { packPick } = require('../packages/shared/src/packs.js');
const event = (kind, key, count = 0, tape = 0, extra = {}) => ({ seq: 1, t: 1700000000, char: 'Alice-RealmName',
    kind, key, count, tape, dust: 0, shiny: 0, partner: '', trade: '', ...extra });

const base = Object.entries(catalog.cards).filter(([, card]) => !card.baseKey);
const seasonal = base.filter(([, card]) => card.seasonal).map(([key]) => key);
const launch = base.filter(([, card]) => !card.seasonal).map(([key]) => key);
const markers = ['chase1', 'chase2', 'launch1'].map(key => event('mode', key, 0, 0, { t: 1000 }));
const nobody = () => false;
const everybody = () => true;

test('the catalog holds back exactly half the base cards and never an elite, boss, critter or gathering card', () => {
    assert.equal(seasonal.length, 1712);
    assert.equal(launch.length, 1711);
    for (const [key, card] of base) {
        if (card.rank === 'elite' || card.rank === 'rareelite' || card.boss || card.dropProfile.tier === 'critter' || card.rank === 'gathering') {
            assert.ok(!card.seasonal, key + ' ' + card.name);
        }
    }
    for (const card of Object.values(catalog.cards)) if (card.baseKey) assert.ok(!card.seasonal, 'an edition follows its base card');
});

test('a page lists its launch cards as required, only where that differs from all its cards, and every page can be finished', () => {
    for (const set of catalog.sets) {
        const needed = set.required || set.cards;
        assert.ok(needed.length > 0, set.title);
        assert.deepEqual(needed.slice().sort(), set.cards.filter(key => !catalog.cards[key].seasonal).sort(), set.title);
        if (set.required) assert.ok(set.required.length < set.cards.length, set.title);
    }
    assert.equal(catalog.sets.reduce((sum, set) => sum + (set.required || set.cards).length, 0), launch.length);
});

test('mode/launch1 comes once, only after chase2, with nothing else in it', () => {
    const marker = key => event('mode', key);
    assert.equal(replay([marker('launch1')], catalog).rule, 'mode', 'not on a binder with no drop generation');
    assert.equal(replay([marker('chase1'), marker('launch1')], catalog).rule, 'mode', 'not on generation 1');
    const done = replay(markers, catalog);
    assert.equal(done.ok, true, JSON.stringify(done));
    assert.equal(done.state.launch, 1);
    assert.equal(done.state.balance, 2);
    assert.equal(replay([...markers, marker('launch1')], catalog).rule, 'mode', 'once');
    assert.equal(replay([marker('chase1'), marker('chase2'), event('mode', 'launch1', 1)], catalog).rule, 'mode', 'count must be zero');
    assert.equal(replay(markers, catalog, done.state).rule, 'mode', 'a stored state that already has it');
    assert.equal(replay([event('drop', seasonal[0], 1)], catalog).ok, true, 'history before the marker is untouched');
});

test('after the marker an unreleased held-back card cannot be dropped, missed on, found in a pack or crafted; released ones and others can', () => {
    const held = seasonal.find(key => catalog.cards[key].dropProfile.noCraft === false);
    const free = launch[0];
    const state = newState(); state.dust = 1000;
    const after = (...events) => replay([...markers, ...events], catalog, state, { available: nobody });
    for (const rule of [['drop', held, 1], ['miss', held, 1], ['craft', held, 1, 0, { dust: -catalog.dust.craft[catalog.cards[held].rarity] }]]) {
        assert.equal(after(event(...rule)).rule, 'retired', rule[0]);
    }
    assert.equal(after(event('drop', free, 1)).ok, true, 'a launch card is unaffected');
    const released = replay([...markers, event('drop', held, 1)], catalog, state, { available: everybody });
    assert.equal(released.ok, true, JSON.stringify(released));
    const byTime = (key, t) => t >= 1700000000;
    assert.equal(replay([...markers, event('drop', held, 1, 0, { t: 1699999999 })], catalog, state, { available: byTime }).rule, 'retired', 'before its release time');
    assert.equal(replay([...markers, event('drop', held, 1, 0, { t: 1700000001 })], catalog, state, { available: byTime }).ok, true, 'after it');
    // Trading or recycling a copy someone already owns is never refused, and without a way to ask, nothing is enforced.
    assert.equal(replay([...markers, event('drop', held, 1)], catalog, state).ok, true, 'no availability function: not enforced');
    const owned = newState(); owned.counts[held] = 1;
    assert.equal(replay([...markers, event('tradeOut', held, 0, 0, { partner: 'bob-realm', trade: 't1' })], catalog, owned, { available: nobody }).ok, true);
    assert.equal(replay([...markers, event('recycle', held, 1, 0, { dust: catalog.dust.recycle[catalog.cards[held].rarity] })], catalog, { ...owned, counts: { [held]: 2 } }, { available: nobody }).ok, true);
});

test('a page is finished by its launch cards alone', () => {
    const set = catalog.sets.find(entry => entry.required && entry.required.length <= 12);
    assert.ok(set);
    const state = newState();
    for (const key of set.required) state.counts[key] = 1;
    const done = replay([event('set', set.code)], catalog, state);
    assert.equal(done.ok, true, set.title + ' ' + JSON.stringify(done));
    const short = newState();
    for (const key of set.required.slice(1)) short.counts[key] = 1;
    assert.equal(replay([event('set', set.code)], catalog, short).rule, 'set', 'still needs every launch card');
});

test('packs leave out cards that may not be found yet, and are exactly as before when nothing is asked', () => {
    const zone = catalog.sets.find(set => set.required && set.cards.some(key => catalog.cards[key].seasonal)).code;
    const heldHere = new Set(catalog.sets.find(set => set.code === zone).cards.filter(key => catalog.cards[key].seasonal));
    const isOk = key => !heldHere.has(key);
    let differed = 0;
    for (let draw = 0; draw < 400; draw++) {
        const entry = ('0000' + ((draw * 2654435761) >>> 0).toString(16)).slice(-8).padStart(8, '0') + ((draw * 40503) >>> 0).toString(16).padStart(8, '0');
        const plain = packPick(catalog, zone, entry, catalog.shinyOdds, true);
        const filtered = packPick(catalog, zone, entry, catalog.shinyOdds, true, isOk);
        assert.ok(!heldHere.has(filtered), 'a held-back card came out of a pack');
        assert.equal(packPick(catalog, zone, entry, catalog.shinyOdds, true, null), plain, 'no predicate, no change');
        assert.equal(packPick(catalog, zone, entry, catalog.shinyOdds, true, () => true), plain, 'everything available, no change');
        if (plain !== filtered) differed++;
    }
    assert.ok(differed > 0, 'the filter changed some picks');
});
