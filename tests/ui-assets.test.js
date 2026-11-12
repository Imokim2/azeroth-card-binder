const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..', 'AzerothCardBinder');

test('every declared custom cue ships as a short mono 44.1 kHz Vorbis file', () => {
    const source = fs.readFileSync(path.join(root, 'Sounds.lua'), 'utf8').split('local groups')[0];
    const names = [...source.matchAll(/(?:^\s*|,\s*)([a-z_]+)\s*=\s*\{/gm)].map(match => match[1]);
    assert.equal(names.length, 13);
    let total = 0;
    for (const name of names) {
        const bytes = fs.readFileSync(path.join(root, 'Sounds', name + '.ogg'));
        total += bytes.length;
        assert.equal(bytes.toString('ascii', 0, 4), 'OggS', name);
        const ident = bytes.indexOf(Buffer.from([1, ...Buffer.from('vorbis')]));
        assert.ok(ident > 0, name);
        assert.equal(bytes[ident + 11], 1, name);
        assert.equal(bytes.readUInt32LE(ident + 12), 44100, name);
        let at = 0, samples = 0n;
        while (at < bytes.length) {
            assert.equal(bytes.toString('ascii', at, at + 4), 'OggS', name);
            const segments = bytes[at + 26];
            const body = bytes.subarray(at + 27, at + 27 + segments).reduce((sum, value) => sum + value, 0);
            const position = bytes.readBigUInt64LE(at + 6);
            if (position !== 0xffffffffffffffffn) samples = position;
            at += 27 + segments + body;
        }
        assert.ok(Number(samples) / 44100 >= .1 && Number(samples) / 44100 <= 2.1, name);
    }
    assert.ok(total < 150000, 'the sound set should stay small');
});

test('custom icon and portrait card back ship in client-readable power-of-two TGA textures', () => {
    for (const [name, width, height] of [['CardStack.tga', 128, 128], ['CardBack.tga', 256, 512]]) {
        const data = fs.readFileSync(path.join(root, 'Art', name));
        assert.equal(data[2], 2, name);
        assert.equal(data.readUInt16LE(12), width, name);
        assert.equal(data.readUInt16LE(14), height, name);
        assert.equal(data[16], 32, name);
        assert.ok(data.length >= 18 + width * height * 4, name);
    }
});
