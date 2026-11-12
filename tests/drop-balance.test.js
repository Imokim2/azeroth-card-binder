const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const catalog = require('../packages/shared/catalog.json');
const vectors = require('../packages/shared/vectors/balance.json');
const ledger = require('../packages/shared/src/ledger.js');
const { replay, newState } = require('../packages/shared/src/rules.js');
const { chanceFor, profileChance } = require('../packages/shared/src/drops.js');
const { packPick } = require('../packages/shared/src/packs.js');
const { pickEdition } = require('../packages/shared/src/editions.js');
const harness = import('../server/test/harness.ts');
const event = (kind, key, count = 0, tape = 0, extra = {}) => ({ seq: 1, t: 1700000000, char: 'Alice-RealmName',
    kind, key, count, tape, dust: 0, shiny: 0, partner: '', trade: '', ...extra });

test('balance vectors cover both policies, late guarantee boundaries and weighted packs', () => {
    assert.equal(vectors.catalogVersion, catalog.catalogVersion);
    for (const item of vectors.chances) {
        assert.equal(chanceFor(catalog, item.key, item.misses), item.legacy);
        assert.equal(chanceFor(catalog, item.key, item.misses, true), item.balanced);
    }
    for (const item of vectors.packs) assert.equal(packPick(catalog, item.zone, item.entry, catalog.shinyOdds, true), item.key);
    for (const card of Object.values(catalog.cards)) {
        const p = card.dropProfile;
        assert.ok(Number.isInteger(p.rate) && p.rate > 0 && p.rate <= 10000);
        assert.ok(Number.isInteger(p.packWeight) && p.packWeight > 0);
        if (card.baseKey) assert.deepEqual(p, catalog.cards[card.baseKey].dropProfile);
        if (p.style === 'chase') {
            const limit = Math.ceil(10000 / p.rate);
            assert.equal(profileChance(p, Math.floor(limit * .75)), p.rate);
            assert.equal(profileChance(p, limit - 1), 10000);
        }
    }
});

test('critter editions and crafting restrictions activate only in the new policy', () => {
    assert.equal(pickEdition(catalog, 'npc:721', 1), 'npc:721');
    assert.equal(pickEdition(catalog, 'npc:721', 250, true), 'edition:7211');
    assert.equal(pickEdition(catalog, 'npc:721', 251, true), 'npc:721');
    const state = newState(); state.dust = 100000;
    const craft = event('craft', 'npc:721', 1, 0, { dust: -catalog.dust.craft[catalog.cards['npc:721'].rarity] });
    assert.equal(replay([craft], catalog, state).ok, true);
    assert.equal(replay([event('mode', 'chase1'), craft], catalog, state).rule, 'craft');
    assert.equal(replay([event('mode', 'chase1'), event('mode', 'chase1')], catalog).rule, 'mode');
    assert.equal(replay([event('mode', 'editions1'), event('drop', 'edition:7211', 1)], catalog).rule, 'balance');
});

test('post-policy integrity counters ignore inherited pity and historic easy critter drops', async () => {
    const { integrityFlags } = await import('../server/src/integrity.ts');
    const state = newState(); state.mode = 'ranked2'; state.exact = true;
    const result = replay([event('mode', 'chase1'), event('drop', 'npc:721', 1, 1),
        event('miss', 'npc:721', 10, 11), event('drop', 'npc:721', 2, 12)], catalog, state);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.deepEqual(result.state.balanceAttempts, { 'npc:721': 11 });
    assert.deepEqual(result.state.balanceDrops, { 'npc:721': 1 });
    const before = replay([event('mode', 'chase1')], catalog, state);
    const flags = integrityFlags({ catalog, state: before.state, attempts: { 'npc:721': 1000 }, drops: { 'npc:721': 500 },
        tapeNextBefore: 0, tapeNextNow: 0, lastUploadAt: null, now: 1700004000, playerCreatedAt: 1700000000, openKinds: [] });
    assert.equal(flags.some(flag => flag.kind.startsWith('luck')), false);
});

test('real Lua legacy and balanced drops, editions and weighted packs upload across policy and pack boundaries', async () => {
    const h = await harness, env = h.setup(), player = h.newPlayer('balanced-player');
    await env.store.registerKey({ discordId: player.discord, key: player.publicKeyHex, visibility: 'public', at: h.NOW,
        newPlayerId: '01ARZ3NDEKTSV4RRFFQ69G5FAV' });
    const request = { key: player.publicKeyHex, sentAt: h.NOW };
    const response = await env.call('/v1/tape', { body: { ...request, sig: ledger.signBatch({ ...request, purpose: 'tape' }, player.privateKey) } });
    assert.equal(response.status, 200);
    const tape = await response.json();
    const folder = await fs.mkdtemp(path.join(os.tmpdir(), 'warcards-balance-'));
    let run;
    try {
        const file = path.join(folder, 'entries.lua');
        await fs.writeFile(file, 'return {' + tape.entries.map(entry => JSON.stringify(entry)).join(',') + '}');
        const result = spawnSync(process.env.LUAJIT || 'luajit', ['tests/tools/play-balance.lua', file], { cwd: path.resolve(__dirname, '..'), encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
        assert.equal(result.status, 0, result.stderr); run = JSON.parse(result.stdout);
    } finally { await fs.rm(folder, { recursive: true, force: true }); }
    assert.equal(ledger.verifyChain(run.events).ok, true);
    const marker = run.events.findIndex(item => item.key === 'chase1');
    assert.ok(marker > 1);
    const pack = run.events.findIndex(item => item.kind === 'packCard');
    assert.ok(pack > marker, 'fixture must exercise a real weighted pack');
    const cuts = [marker, marker + 1, pack + 2, run.events.length];
    let from = 0;
    for (const to of cuts) {
        const state = replay(run.events.slice(0, to), catalog);
        assert.equal(state.ok, true, JSON.stringify(state));
        const body = h.signedUpload(player, run.events.slice(from, to), { specVersion: 5,
            tapeIndex: state.state.lastTape + 1,
            snapshot: { counts: state.state.counts, dust: state.state.dust, sets: state.state.sets, attempts: run.attempts, titles: {} } });
        const accepted = await env.call('/v1/ledger', { body });
        assert.equal(accepted.status, 200, await accepted.text()); from = to;
    }
    const rebuilt = replay(run.events, catalog);
    assert.deepEqual(rebuilt.state.counts, run.counts);
    const downgraded = await env.call('/v1/ledger', { body: h.signedUpload(player, [], { specVersion: 4,
        tapeIndex: run.tapeIndex, snapshot: { counts: run.counts, dust: run.dust, sets: run.sets, attempts: run.attempts, titles: {} } }) });
    assert.equal(downgraded.status, 426);
});

test('Ranked rejects easy legacy-rate wins after the marker and keeps carried protection', async () => {
    const { tapeKey, tapeEntry, rollValue, shinyValue, checkTape } = await import('../server/src/tape.ts');
    const h = await harness, key = await tapeKey(h.TAPE_SECRET), owner = 'balance-forgery';
    const state = newState(); state.mode = 'ranked2'; state.exact = true; state.balance = 1;
    let position = 0, entry;
    do { entry = await tapeEntry(key, owner, ++position); } while (rollValue(entry) <= 5 || rollValue(entry) > 100);
    state.lastTape = position - 1;
    const args = { key, playerId: owner, stateBefore: state, catalog, issuedEnd: position,
        tapeNext: position + 1, stack: {}, events: [event('drop', 'npc:721', 1, position, { shiny: shinyValue(entry, catalog.shinyOdds) === 1 ? 1 : 0 })] };
    assert.equal((await checkTape(args)).failure.reason, 'roll');
    const carried = Math.ceil(10000 / catalog.cards['npc:721'].dropProfile.rate) - 1;
    assert.equal((await checkTape({ ...args, stack: { 'npc:721': carried } })).failure, null);
    const miss = await checkTape({ ...args, stack: { 'npc:721': carried }, events: [event('miss', 'npc:721', 1, position)] });
    assert.equal(miss.failure.reason, 'roll');
});
