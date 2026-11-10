// The server's own ledger code against the shared test vectors (docs/LEDGER-SPEC.md, section 10). The Lua add-on and
// the JavaScript reference pass the same vectors; if this fails, the server and the spec disagree.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { canonicalJson, fromHex, newId, sha256Hex, verifySignature } from "../../packages/shared/src/crypto.ts";
import { GENESIS, checkChain, eventText } from "../src/ledger.ts";
import type { LedgerEvent } from "../src/ledger.ts";
import { gunzip, gzip } from "../src/gzip.ts";

const dir = new URL("../../packages/shared/vectors/", import.meta.url);
const load = (name: string) => JSON.parse(readFileSync(new URL(name, dir), "utf8"));

test("SHA-256 gives every vector, including the padding edge cases", async () => {
  for (const vector of load("sha256.json") as { input: string; hex: string }[]) {
    assert.equal(await sha256Hex(vector.input), vector.hex, vector.input.slice(0, 20));
  }
});

test("canonical JSON gives every vector and refuses what it cannot write", () => {
  for (const item of load("canonical-json.json") as { input: unknown; expected: string }[]) {
    assert.equal(canonicalJson(item.input), item.expected);
  }
  assert.throws(() => canonicalJson({ a: 1.5 }));
  assert.throws(() => canonicalJson({ a: null }));
  assert.throws(() => canonicalJson({ a: undefined }));
});

test("the valid ledger verifies as one batch and as two, and its text matches", async () => {
  const valid = load("ledger-valid.json") as { events: LedgerEvent[]; head: { seq: number; hash: string }; texts: string[] };
  valid.events.forEach((event, index) => assert.equal(eventText(event), valid.texts[index]));
  assert.deepEqual(await checkChain(valid.events), { ok: true, head: valid.head });
  const first = await checkChain(valid.events.slice(0, 5));
  assert.ok(first.ok);
  if (first.ok) assert.deepEqual(await checkChain(valid.events.slice(5), first.head), { ok: true, head: valid.head });
  assert.deepEqual(await checkChain([]), { ok: true, head: { seq: 0, hash: GENESIS } });
});

test("every invalid ledger fails for the stated reason at the stated event", async () => {
  const cases = load("ledger-invalid.json") as { name: string; events: Record<string, unknown>[]; head: { seq: number; hash: string } | null; error: string; index: number }[];
  assert.ok(cases.length >= 10);
  for (const item of cases) {
    const result = await checkChain(item.events, item.head ?? undefined);
    assert.equal(result.ok, false, item.name);
    if (!result.ok) {
      assert.equal(result.error, item.error, item.name);
      assert.equal(result.index, item.index, item.name);
    }
  }
});

test("the signed upload verifies under Web Crypto, and a forged copy, another key or a short signature do not", async () => {
  const signed = load("batch-signed.json") as { publicKeyHex: string; canonical: string; batch: Record<string, unknown> & { sig: string }; forged: Record<string, unknown> & { sig: string } };
  const { sig, ...body } = signed.batch;
  assert.equal(canonicalJson(body), signed.canonical);
  assert.equal(await verifySignature(signed.publicKeyHex, sig, signed.canonical), true);
  const { sig: forgedSig, ...forgedBody } = signed.forged;
  assert.equal(await verifySignature(signed.publicKeyHex, forgedSig, canonicalJson(forgedBody)), false);
  assert.equal(await verifySignature("00".repeat(32), sig, signed.canonical), false);
  assert.equal(await verifySignature(signed.publicKeyHex, "00", signed.canonical), false);
  assert.equal(await verifySignature("zz", sig, signed.canonical), false);
});

test("hex helpers are strict", () => {
  assert.deepEqual(fromHex("00ff"), new Uint8Array([0, 255]));
  assert.equal(fromHex("00FF"), null);
  assert.equal(fromHex("0"), null);
  assert.equal(fromHex("00ff", 2), null);
});

test("ids are 26 characters, sort by time, and are not repeated", () => {
  const first = newId(1_000_000);
  const later = newId(2_000_000);
  assert.match(first, /^[0-9A-HJKMNP-TV-Z]{26}$/);
  assert.ok(first < later);
  assert.notEqual(newId(1_000_000), first);
});

test("gzip round-trips text, including non-ASCII", async () => {
  const sample = JSON.stringify({ name: "Zul'Gurub – Ünïcöde", events: Array.from({ length: 50 }, (_, index) => index) });
  const packed = await gzip(sample);
  assert.ok(packed.length < sample.length);
  assert.equal(await gunzip(packed), sample);
});
