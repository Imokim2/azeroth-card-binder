const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const catalog = require('../packages/shared/catalog.json');
const vectors = require('../packages/shared/vectors/satchel.json');
const ledger = require('../packages/shared/src/ledger.js');
const { replay, newState } = require('../packages/shared/src/rules.js');
const { packInfo, packTier } = require('../packages/shared/src/packs.js');
const harness = import('../server/test/harness.ts');
const partial = (kind, key, count, fields = {}) => ({ seq: 1, t: 1700000000, char: 'Bob-RealmName', kind, key, count,
    tape: 0, shiny: 0, dust: 0, partner: '', trade: '', ...fields });
const snapshot = state => ({ counts: state.counts, dust: state.dust, sets: state.sets, attempts: {}, titles: {} });

test('pack boundary and gift vectors verify, replay in pieces, and never put packs in card inventory', () => {
    for (const item of vectors.tiers) assert.equal(packTier(item.entry, catalog.shinyOdds), item.tier);
    for (const run of Object.values(vectors.gift)) {
        assert.equal(ledger.verifyChain(run.events).ok, true);
        const state = replay(run.events, catalog);
        assert.equal(state.ok, true, JSON.stringify(state));
        assert.deepEqual(state.state, run.finalState);
        const first = replay(run.events.slice(0, 2), catalog);
        const second = replay(run.events.slice(2), catalog, first.state);
        assert.deepEqual(second.state, state.state);
        assert.ok(Object.keys(state.state.counts).every(key => !key.startsWith('pack:')));
    }
    for (const [id, size] of [['WF:common', 1], ['WF:rare', 3], ['WF', 5]]) assert.equal(packInfo(catalog, id).size, size);
    for (const id of ['WF:epic', 'WF:legendary', 'WF:rare:extra', 'NOZONE:rare']) assert.equal(packInfo(catalog, id), null);
});

test('pack keys can only be traded, valid offers cannot overspend, and wrong-zone or excess reveals fail', () => {
    for (const kind of ['drop', 'craft', 'recycle', 'packCard', 'miss']) assert.equal(replay([partial(kind, 'pack:WF:rare', 1)], catalog).rule, 'unknown-card');
    assert.equal(replay([partial('tradeOut', 'pack:WF:rare', 0, { partner: 'alice-realmname', trade: 'none' })], catalog).rule, 'trade');
    assert.equal(replay([partial('tradeIn', 'pack:NOZONE:rare', 1, { partner: 'alice-realmname', trade: 'none' })], catalog).rule, 'unknown-set');
    const opened = replay(vectors.gift.recipient.events.slice(0, 2), catalog);
    assert.equal(replay([partial('packCard', 'npc:639', 1)], catalog, opened.state).rule, 'pack');
    const done = replay(vectors.gift.recipient.events, catalog);
    assert.equal(replay([partial('packCard', 'npc:589', 3)], catalog, done.state).rule, 'pack');
    assert.equal(replay([partial('tradeIn', 'pack:WF:rare', 1, { shiny: 1, partner: 'a', trade: 'x' })], catalog).rule, 'field');
});

test('the issued find entry prevents an invented upgrade from Common to Epic', async () => {
    const { tapeKey, tapeEntry, checkTape } = await import('../server/src/tape.ts');
    const { packFound } = require('../packages/shared/src/packs.js');
    const h = await harness, key = await tapeKey(h.TAPE_SECRET), playerId = 'pack-tier-check';
    let position = 0, entry;
    do { entry = await tapeEntry(key, playerId, ++position); } while (!packFound(entry, catalog.shinyOdds) || packTier(entry, catalog.shinyOdds) !== 'common');
    const state = { ...newState(), mode: 'ranked2', tieredPacks: true, lastTape: position };
    const args = { key, playerId, stateBefore: state, catalog, issuedEnd: position, stack: {}, tapeNext: position + 1 };
    assert.equal((await checkTape({ ...args, events: [partial('packFind', 'WF:common', 1, { tape: position })] })).failure, null);
    assert.equal((await checkTape({ ...args, events: [partial('packFind', 'WF', 1, { tape: position })] })).failure.reason, 'pack');
});

for (const [tier, draw, size] of [['common', 1, 1], ['rare', 71, 3], ['epic', 96, 5]]) {
    test(`real Lua two-accept ${tier} pack gift and ${size}-card Ranked reveal upload and retain provenance through resale`, async () => {
        const h = await harness, env = h.setup();
        async function register(name) {
            const player = h.newPlayer(name);
            const response = await env.call('/v1/register', { body: h.registration(player) });
            assert.equal(response.status, 200);
            return { player, id: (await response.json()).playerId };
        }
        const alice = await register('alice-' + tier), bob = await register('bob-' + tier), carl = await register('carl-' + tier);
        const request = { key: bob.player.publicKeyHex, sentAt: h.NOW };
        const response = await env.call('/v1/tape', { body: { ...request, sig: ledger.signBatch({ ...request, purpose: 'tape' }, bob.player.privateKey) } });
        const tape = await response.json();
        const folder = await fs.mkdtemp(path.join(os.tmpdir(), 'warcards-pack-trade-'));
        let run;
        try {
            const file = path.join(folder, 'entries.lua');
            await fs.writeFile(file, 'return {' + tape.entries.map(entry => JSON.stringify(entry)).join(',') + '}');
            const played = spawnSync(process.env.LUAJIT || 'luajit', ['tests/tools/play-pack-trade.lua', file, String(draw)], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
            assert.equal(played.status, 0, played.stderr); run = JSON.parse(played.stdout);
        } finally { await fs.rm(folder, { recursive: true, force: true }); }
        assert.equal(packInfo(catalog, run.zone).tier, tier);
        assert.equal(run.recipient.events.filter(event => event.kind === 'packCard').length, size);
        async function upload(who, character, played) {
            const result = await env.call('/v1/ledger', { body: h.signedUpload(who.player, played.events, { specVersion: 9,
                character, tapeIndex: played.tapeIndex, snapshot: { ...snapshot(played), attempts: played.attempts } }) });
            assert.equal(result.status, 200, await result.text());
        }
        const score = id => env.raw.prepare('SELECT score FROM scores WHERE player_id = ?').get(id).score;
        // Recipient uploads first: a pack with no matching outgoing half must confer no points.
        await upload(bob, 'Bob', run.recipient);
        assert.equal(score(bob.id), 0);
        await upload(alice, 'Alice', run.giver);
        const { runMaintenance } = await import('../server/src/maintenance.ts');
        const maintenance = () => runMaintenance({ ingest: env.store, trades: env.store, catalog, now: () => h.NOW });
        await maintenance();
        assert.equal(score(bob.id), 0, 'a pack found in Casual stays unverified after a Ranked reveal');
        const aStored = await env.store.load(alice.id);
        assert.ok(aStored.state.packs[run.zone] === undefined);
        // Stand in for a verified source to check that matching restores honest pack outputs.
        env.pretendVerified(); await maintenance();
        assert.ok(score(bob.id) > 0);
        const bStored = await env.store.load(bob.id), card = Object.keys(run.recipient.counts)[0];
        const give = h.chain([partial('tradeOut', card, bStored.state.counts[card] - 1, {
            seq: bStored.head.seq + 1, t: 1700000001, partner: 'carl-realmname', trade: 'pack-output-resale' })], bStored.head.hash);
        const bCounts = { ...bStored.state.counts, [card]: bStored.state.counts[card] - 1 };
        const sent = await env.call('/v1/ledger', { body: h.signedUpload(bob.player, give, { specVersion: 9, character: 'Bob', tapeIndex: run.recipient.tapeIndex,
            snapshot: { ...snapshot(bStored.state), counts: bCounts } }) });
        assert.equal(sent.status, 200, await sent.text());
        const receive = h.chain([partial('tradeIn', card, 1, { char: 'Carl-RealmName', t: 1700000001, partner: 'bob-realmname', trade: 'pack-output-resale' })]);
        const taken = await env.call('/v1/ledger', { body: h.signedUpload(carl.player, receive, { specVersion: 9, character: 'Carl', snapshot: { counts: { [card]: 1 }, dust: 0, sets: {}, attempts: {}, titles: {} } }) });
        assert.equal(taken.status, 200, await taken.text());
        await maintenance(); assert.ok(score(carl.id) > 0);
        env.raw.prepare('UPDATE ledger_state SET casual_drops = 1 WHERE player_id = ?').run(alice.id);
        await maintenance();
        assert.equal(score(bob.id), 0);
        assert.equal(score(carl.id), 0, 'opening and retrading must not wash away the pack source');
        const downgraded = await env.call('/v1/ledger', { body: h.signedUpload(bob.player, [], { specVersion: 5, character: 'Bob', tapeIndex: run.recipient.tapeIndex,
            snapshot: snapshot(bStored.state) }) });
        assert.equal(downgraded.status, 426);
    });
}
