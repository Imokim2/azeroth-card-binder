// Drop balance version 2 (ledger marker mode/chase2): critters four times as likely, other ordinary cards 20% more, limited chase
// cards unchanged. A history is replayed at the rates it was rolled at, so everything before chase2 must be exactly as it was.
const test = require('node:test');
const assert = require('node:assert/strict');
const catalog = require('../packages/shared/catalog.json');
const vectors = require('../packages/shared/vectors/balance.json');
const { replay, newState } = require('../packages/shared/src/rules.js');
const { chanceFor, profileChance } = require('../packages/shared/src/drops.js');
const harness = import('../server/test/harness.ts');
const event = (kind, key, count = 0, tape = 0, extra = {}) => ({ seq: 1, t: 1700000000, char: 'Alice-RealmName',
    kind, key, count, tape, dust: 0, shiny: 0, partner: '', trade: '', ...extra });

test('every card has rate2 by the published rule, and critter editions inherit it', () => {
    const base = Object.values(catalog.cards).filter(card => !card.baseKey);
    let critters = 0, limited = 0;
    for (const card of base) {
        const p = card.dropProfile;
        assert.ok(Number.isInteger(p.rate2) && p.rate2 >= p.rate && p.rate2 <= 10000, card.name);
        if (p.tier === 'critter') { assert.equal(p.rate2, Math.min(10000, p.rate * 4), card.name); critters++; }
        else if (p.tier === 'chase' && p.style !== 'chase') { assert.equal(p.rate2, p.rate, card.name); limited++; }
        else assert.equal(p.rate2, Math.round(p.rate * 1.2), card.name);
        if (p.style === 'chase') {
            const second = { ...p, rate: p.rate2 }, limit = Math.ceil(10000 / p.rate2);
            assert.equal(profileChance(second, Math.floor(limit * .75)), p.rate2);
            assert.equal(profileChance(second, limit - 1), 10000);
        }
    }
    assert.equal(critters, 31);
    assert.ok(limited > 0);
    for (const card of Object.values(catalog.cards)) if (card.baseKey) assert.deepEqual(card.dropProfile, catalog.cards[card.baseKey].dropProfile);
});

test('generation 2 chances come from rate2; generation 1 and the original rank rates are exactly as before', () => {
    for (const item of vectors.chances) {
        assert.equal(chanceFor(catalog, item.key, item.misses), item.legacy);
        assert.equal(chanceFor(catalog, item.key, item.misses, true), item.balanced);
        assert.equal(chanceFor(catalog, item.key, item.misses, 1), item.balanced);
        assert.equal(chanceFor(catalog, item.key, item.misses, 2), item.balanced2);
    }
    const critter = catalog.cards['npc:721'].dropProfile;
    assert.equal(chanceFor(catalog, 'npc:721', 0, 1), critter.rate);
    assert.equal(chanceFor(catalog, 'npc:721', 0, 2), critter.rate * 4);
    assert.equal(chanceFor(catalog, 'npc:721', Math.ceil(10000 / critter.rate2) - 1, 2), 10000);
    assert.ok(chanceFor(catalog, 'npc:721', Math.ceil(10000 / critter.rate2) - 1, 1) < 10000);
});

test('mode/chase2 comes once, only after chase1, with nothing else in it; chase1 cannot follow it', () => {
    const marker = key => event('mode', key);
    assert.equal(replay([marker('chase2')], catalog).rule, 'mode', 'not before chase1');
    const both = replay([marker('chase1'), marker('chase2')], catalog);
    assert.equal(both.ok, true, JSON.stringify(both));
    assert.equal(both.state.balance, 2);
    assert.deepEqual([both.state.balanceAttempts, both.state.balanceDrops, both.state.balanceReady], [{}, {}, {}]);
    assert.equal(replay([marker('chase1'), marker('chase2'), marker('chase2')], catalog).rule, 'mode', 'only once');
    assert.equal(replay([marker('chase1'), marker('chase2'), marker('chase1')], catalog).rule, 'mode', 'chase1 only once either');
    assert.equal(replay([marker('chase1'), event('mode', 'chase2', 1)], catalog).rule, 'mode', 'count must be zero');
    assert.notEqual(replay([marker('chase1'), event('mode', 'chase2', 0, 5)], catalog).ok, true, 'it uses no tape entry');
    // The restrictions of the first generation carry on: chase and critter cards still cannot be crafted.
    const state = newState(); state.dust = 100000;
    const craft = event('craft', 'npc:721', 1, 0, { dust: -catalog.dust.craft[catalog.cards['npc:721'].rarity] });
    assert.equal(replay([marker('chase1'), marker('chase2'), craft], catalog, state).rule, 'craft');
    // A history that stops at chase1 replays exactly as it did before this change.
    assert.equal(replay([marker('chase1')], catalog).state.balance, 1);
});

test('the luck statistics start afresh at chase2: the first drop afterwards is skipped, later cycles are counted', () => {
    const state = newState(); state.mode = 'ranked2'; state.exact = true;
    const result = replay([event('mode', 'chase1'), event('drop', 'npc:721', 1, 1), event('miss', 'npc:721', 4, 5),
        event('mode', 'chase2'), event('miss', 'npc:721', 3, 8), event('drop', 'npc:721', 2, 9),
        event('miss', 'npc:721', 5, 14), event('drop', 'npc:721', 3, 15)], catalog, state);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.state.balance, 2);
    assert.deepEqual(result.state.balanceAttempts, { 'npc:721': 6 });
    assert.deepEqual(result.state.balanceDrops, { 'npc:721': 1 });
    const resumed = replay([event('miss', 'npc:721', 2, 17)], catalog, result.state);
    assert.equal(resumed.ok, true);
    assert.equal(resumed.state.balance, 2, 'a replay resumed from a stored state stays on generation 2');
});

test('Ranked at generation 2 accepts a roll that only the new rates allow; generation 1 still refuses it', async () => {
    const { tapeKey, tapeEntry, rollValue, shinyValue, checkTape } = await import('../server/src/tape.ts');
    const h = await harness, key = await tapeKey(h.TAPE_SECRET), owner = 'rates-second-generation';
    const p = catalog.cards['npc:721'].dropProfile;
    let position = 0, entry;
    do { entry = await tapeEntry(key, owner, ++position); } while (rollValue(entry) <= p.rate || rollValue(entry) > p.rate2);
    const state = newState(); state.mode = 'ranked2'; state.exact = true; state.lastTape = position - 1;
    const drop = event('drop', 'npc:721', 1, position, { shiny: shinyValue(entry, catalog.shinyOdds) === 1 ? 1 : 0 });
    const args = { key, playerId: owner, catalog, issuedEnd: position, tapeNext: position + 1, stack: {}, events: [drop] };
    assert.equal((await checkTape({ ...args, stateBefore: { ...state, balance: 1 } })).failure.reason, 'roll', 'generation 1: a miss was required');
    assert.equal((await checkTape({ ...args, stateBefore: { ...state, balance: 2 } })).failure, null, 'generation 2: the same roll is a drop');
    const miss = await checkTape({ ...args, stateBefore: { ...state, balance: 2 }, events: [event('miss', 'npc:721', 1, position)] });
    assert.equal(miss.failure.reason, 'roll', 'and a miss on it is refused');
    // A marker inside the batch changes the rates for what follows it, and not for what came before.
    const switched = await checkTape({ ...args, stateBefore: { ...state, balance: 0 }, events: [event('mode', 'chase1'), event('mode', 'chase2'), drop] });
    assert.equal(switched.failure, null);
    const early = await checkTape({ ...args, stateBefore: { ...state, balance: 0 }, events: [event('mode', 'chase1'), drop, event('mode', 'chase2')] });
    assert.equal(early.failure.reason, 'roll', 'a drop rolled before chase2 is checked at the first-generation rates');
});

test('luck is judged against the rates in force: the same drops are less remarkable at generation 2', async () => {
    const { luckScore } = await import('../server/src/integrity.ts');
    const attempts = { 'npc:721': 3000 }, drops = { 'npc:721': 12 };
    assert.ok(luckScore(catalog, attempts, drops, 1) > 0, 'remarkable at the first-generation rates');
    assert.ok(luckScore(catalog, attempts, drops, 2) < luckScore(catalog, attempts, drops, 1));
});
