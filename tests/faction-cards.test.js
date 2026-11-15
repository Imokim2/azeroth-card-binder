// Cards only one faction can win (docs/FACTION-CARDS.md, ledger spec 10): the rules in packages/shared/src/rules.js.
//   mode/faction1   once, only after launch1: the cards added in spec 10 (catalog card.since) exist from here on
//   mode/side:alliance|horde   once per character, only after faction1
//   a card with card.faction is acquired (drop, miss, pack card, craft) only by a character that declared that faction
// Trading, recycling and everything before the markers never look at factions.
const test = require('node:test');
const assert = require('node:assert/strict');
const catalog = require('../packages/shared/catalog.json');
const { replay, newState } = require('../packages/shared/src/rules.js');
const { packPick } = require('../packages/shared/src/packs.js');

const event = (kind, key, extra = {}) => ({ seq: 1, t: 1700000000, char: 'Ann-Realm', kind, key, count: kind === 'mode' || kind === 'set' ? 0 : 1,
    tape: 0, dust: 0, shiny: 0, partner: '', trade: '', ...extra });
const base = Object.entries(catalog.cards).filter(([, card]) => !card.baseKey);
const alliance = base.find(([, card]) => card.faction === 'alliance')[0];
const horde = base.find(([, card]) => card.faction === 'horde')[0];
const shared = base.find(([, card]) => card.since === 10 && !card.faction && !card.unobtainable)[0];
const older = base.find(([, card]) => !card.since && !card.seasonal)[0];
const mark = key => event('mode', key);
const upTo = ['chase1', 'chase2', 'launch1'].map(mark);
const ready = [...upTo, mark('faction1')];
const side = (name, char = 'Ann-Realm') => event('mode', 'side:' + name, { char });
const run = (...events) => replay(events, catalog);

test('the catalog: 162 cards for each side, all added in spec 10, never held back, never needed to finish a page', () => {
    for (const side of ['alliance', 'horde']) {
        const list = base.filter(([, card]) => card.faction === side);
        assert.equal(list.length, 162, side);
        for (const [key, card] of list) {
            assert.equal(card.since, 10, key);
            assert.ok(!card.seasonal && !card.unobtainable, key);
            assert.ok(key.startsWith('npc:'), 'a creature: ' + key);
        }
    }
    for (const set of catalog.sets) {
        for (const key of set.required || []) assert.ok(!catalog.cards[key].faction, key + ' is required by ' + set.title);
    }
    const added = base.filter(([, card]) => card.since === 10);
    assert.equal(added.filter(([, card]) => !card.faction).length, 36, 'the dungeon and raid creatures that are friendly to both sides');
    for (const [key, card] of base) if (card.since) assert.equal(card.since, 10, key);
});

test('faction1 comes once, only after launch1, with nothing else in it; a side only after faction1, once per character', () => {
    assert.equal(run(mark('faction1')).rule, 'mode', 'not on a binder with no launch collection');
    assert.equal(run(mark('chase1'), mark('chase2'), mark('faction1')).rule, 'mode', 'not before launch1');
    assert.equal(run(...ready).ok, true);
    assert.equal(replay(ready, catalog).state.faction, 1);
    assert.equal(run(...ready, mark('faction1')).rule, 'mode', 'once');
    assert.equal(run(...upTo, event('mode', 'faction1', { count: 1 })).rule, 'mode', 'count must be zero');
    assert.equal(run(...upTo, side('alliance')).rule, 'mode', 'no side before faction1');
    assert.equal(run(...ready, side('alliance')).ok, true);
    assert.equal(run(...ready, side('alliance'), side('alliance')).rule, 'mode', 'once per character');
    assert.equal(run(...ready, side('alliance'), side('horde')).rule, 'mode', 'a character keeps its faction');
    assert.equal(run(...ready, side('alliance'), side('horde', 'Hal-Realm')).ok, true, 'another character may be the other faction');
    assert.equal(run(...ready, event('mode', 'side:neutral')).rule, 'mode', 'only the two factions');
    assert.equal(run(...ready, event('mode', 'side:alliance', { count: 1 })).rule, 'mode');
});

test('a card only one faction can win is acquired only by a character of that faction', () => {
    const history = [...ready, side('alliance'), side('horde', 'Hal-Realm')];
    assert.equal(run(...history, event('drop', alliance)).ok, true);
    assert.equal(run(...history, event('drop', horde)).rule, 'faction', 'an Alliance character cannot win a card of a creature the Horde kills');
    assert.equal(run(...history, event('drop', horde, { char: 'Hal-Realm' })).ok, true);
    assert.equal(run(...history, event('drop', alliance, { char: 'Hal-Realm' })).rule, 'faction');
    assert.equal(run(...ready, event('drop', alliance)).rule, 'faction', 'a character that has declared nothing wins none');
    assert.equal(run(...history, event('drop', alliance, { char: 'Stranger-Realm' })).rule, 'faction');
    // Misses, pack cards and crafts follow the same rule.
    assert.equal(run(...history, event('craft', horde, { dust: -catalog.dust.craft[catalog.cards[horde].rarity] })).rule, 'faction');
    const state = newState();
    state.dust = 100000;
    const crafted = replay([...history, event('craft', alliance, { dust: -catalog.dust.craft[catalog.cards[alliance].rarity] })], catalog, state);
    assert.equal(crafted.ok, true, JSON.stringify(crafted));
});

test('a card added in spec 10 needs faction1; one both sides can win needs no side', () => {
    assert.equal(run(...upTo, event('drop', shared)).rule, 'retired');
    assert.equal(run(...ready, event('drop', shared)).ok, true, 'either faction, with no side declared');
    assert.equal(run(...ready, event('drop', older)).ok, true);
    assert.equal(run(event('drop', older)).ok, true, 'history before the markers is untouched');
    assert.equal(run(event('drop', alliance)).rule, 'retired', 'a faction card does not exist before the markers');
});

test('trading and recycling a card only one faction can win is never refused, and a card from a trade needs no faction', () => {
    const history = [...ready, side('alliance')];
    const received = run(...history, event('tradeIn', horde, { partner: 'bob-realm', trade: '1-1-1' }));
    assert.equal(received.ok, true, JSON.stringify(received));
    const duplicate = replay([event('tradeIn', horde, { partner: 'bob-realm', trade: '1-1-2', count: 2 }), event('recycle', horde, { count: 1, dust: catalog.dust.recycle[catalog.cards[horde].rarity] })],
        catalog, { ...replay(history, catalog).state, counts: { [horde]: 1 } });
    assert.equal(duplicate.ok, true, JSON.stringify(duplicate));
});

test('the pack pool of a character leaves out the other faction\'s cards and, before faction1, every card added in spec 10', () => {
    const zone = catalog.sets.find(set => set.cards.some(key => catalog.cards[key].faction === 'alliance') && set.cards.some(key => catalog.cards[key].faction === 'horde')).code;
    const pool = filter => {
        const seen = new Set();
        for (let draw = 0; draw < 4000; draw++) {
            const entry = ('0000' + ((draw * 2654435761) >>> 0).toString(16)).slice(-8).padStart(8, '0') + ((draw * 40503 + 7) >>> 0).toString(16).padStart(8, '0');
            seen.add(packPick(catalog, zone, entry, catalog.shinyOdds, 2, filter));
        }
        return seen;
    };
    const forAlliance = pool(key => !catalog.cards[key].faction || catalog.cards[key].faction === 'alliance');
    assert.ok([...forAlliance].some(key => catalog.cards[key].faction === 'alliance'));
    assert.ok(![...forAlliance].some(key => catalog.cards[key].faction === 'horde'));
    const beforeMarker = pool(key => !catalog.cards[key].since);
    assert.ok(![...beforeMarker].some(key => catalog.cards[key].since));
});
