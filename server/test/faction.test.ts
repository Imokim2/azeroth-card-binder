// Cards only one faction can win (docs/FACTION-CARDS.md, ledger spec 10): the server checks a pack's cards against the pool of the character that
// opened it, refuses the markers from an older companion, and a season cannot name such a card.
import assert from "node:assert/strict";
import test from "node:test";
import { SUPPORTED_SPEC_VERSIONS } from "../src/upload.ts";
import { seasonDefinition } from "../src/seasons.ts";
import { packPick } from "../src/shared.ts";
import type { LedgerState } from "../src/shared.ts";
import { checkTape, shinyValue, tapeEntry, tapeKey } from "../src/tape.ts";
import { NOW, TAPE_SECRET, catalog } from "./harness.ts";

const cards = Object.entries(catalog.cards).filter(([, card]) => !card.baseKey);
const detail = async (work: Promise<unknown>) => { try { await work; return null; } catch (error) { return (error as { detail?: { field?: string } }).detail?.field ?? "?"; } };

// A zone that has common cards for both sides, so a pack from it can differ between an Alliance and a Horde character.
const zone = catalog.sets.find((set) => set.cards.some((key) => catalog.cards[key]?.faction === "alliance" && catalog.cards[key]?.rarity === "common")
  && set.cards.some((key) => catalog.cards[key]?.faction === "horde" && catalog.cards[key]?.rarity === "common"))!.code;
const side = (name: string) => (key: string): boolean => { const card = catalog.cards[key]; return !card?.faction || card.faction === name; };
const state = (extra: Partial<LedgerState>): LedgerState => ({ counts: {}, dust: 0, shiny: {}, sets: {}, mode: "ranked2", lastTape: 0, lastT: 0, exact: true, balance: 2, launch: 1, packZone: zone, ...extra });
const check = async (events: { kind: string; key: string; tape: number; char: string; shiny: number; t: number }[], stateBefore: LedgerState) => {
  const key = await tapeKey(TAPE_SECRET);
  const full = events.map((event, index) => ({ seq: index + 1, count: 1, dust: 0, partner: "", trade: "", prev: "", h: "", ...event }));
  return checkTape({ key, playerId: "faction-player", events: full, stateBefore, catalog, issuedEnd: 100000, stack: {}, tapeNext: Math.max(...events.map((event) => event.tape)) + 1 });
};

test("the catalog gives each side the same number of cards of its own, none of them held back, unobtainable or required", () => {
  const alliance = cards.filter(([, card]) => card.faction === "alliance"), horde = cards.filter(([, card]) => card.faction === "horde");
  assert.equal(alliance.length, 162);
  assert.equal(horde.length, 162);
  for (const [key, card] of [...alliance, ...horde]) {
    assert.equal(card.since, 10, key);
    assert.ok(!card.seasonal && !card.unobtainable, key);
    for (const set of catalog.sets) assert.ok(!(set.cards.includes(key) && (set as { required?: string[] }).required?.includes(key)), key + " is not required");
  }
});

test("a pack is checked against the pool of the character that opened it", async () => {
  const key = await tapeKey(TAPE_SECRET);
  let tested = 0;
  for (let position = 1; position <= 3000 && tested < 3; position++) {
    const entry = await tapeEntry(key, "faction-player", position);
    const forAlliance = packPick(catalog, zone, entry, catalog.shinyOdds, 2, side("alliance"))!, forHorde = packPick(catalog, zone, entry, catalog.shinyOdds, 2, side("horde"))!;
    if (forAlliance === forHorde || catalog.cards[forHorde]?.faction !== "horde") continue;
    const shiny = shinyValue(entry, catalog.shinyOdds) === 1 ? 1 : 0;
    const ready = state({ faction: 1, sides: { "Ann-Realm": "alliance", "Hal-Realm": "horde" } });
    const event = (card: string, char: string) => ({ kind: "packCard", key: card, tape: position, char, shiny, t: NOW });
    assert.equal((await check([event(forAlliance, "Ann-Realm")], ready)).failure, null, "an Alliance character gets the Alliance pool");
    assert.equal((await check([event(forHorde, "Hal-Realm")], ready)).failure, null, "a Horde character gets the Horde pool");
    assert.equal((await check([event(forHorde, "Ann-Realm")], ready)).failure?.reason, "pack", "a Horde-only card cannot come out of an Alliance character's pack");
    assert.equal((await check([event(forAlliance, "Hal-Realm")], ready)).failure?.reason, "pack");
    tested++;
  }
  assert.ok(tested >= 1, "found a pack that differs between the sides");
});

test("before mode/faction1 the cards added in spec 10 are not in a pack; the markers change the pool when they come", async () => {
  const key = await tapeKey(TAPE_SECRET);
  let tested = 0;
  for (let position = 1; position <= 3000 && tested < 3; position++) {
    const entry = await tapeEntry(key, "faction-player", position);
    const old = packPick(catalog, zone, entry, catalog.shinyOdds, 2, (card) => !catalog.cards[card]?.since)!;
    const added = packPick(catalog, zone, entry, catalog.shinyOdds, 2, side("alliance"))!;
    if (old === added) continue;
    const shiny = shinyValue(entry, catalog.shinyOdds) === 1 ? 1 : 0;
    const event = (card: string, kind = "packCard") => ({ kind, key: card, tape: position, char: "Ann-Realm", shiny, t: NOW });
    assert.equal((await check([event(old)], state({}))).failure, null, "the old pool before faction1");
    assert.equal((await check([event(added)], state({}))).failure?.reason, "pack", "a card added in spec 10 before faction1");
    // The same batch carrying the markers: faction1, side, then a card from the new pool.
    const marked = [event("faction1", "mode"), event("side:alliance", "mode"), event(added)].map((entry, index) => ({ ...entry, tape: index < 2 ? 0 : position }));
    assert.equal((await check(marked, state({}))).failure, null, "markers in the same upload move the pool");
    tested++;
  }
  assert.ok(tested >= 1, "found a pack the new cards change");
});

test("the server supports spec 10", () => {
  assert.ok(SUPPORTED_SPEC_VERSIONS.includes(10));
});

test("a season cannot name a card only one faction can win, and a random one never draws it", async () => {
  const rewards = { completion: { title: "", packs: [] }, first: { places: 0, title: "", packs: [] } };
  const season = (selection: Record<string, unknown>) => ({ id: "faction-season", title: "Test", startsAt: NOW + 100, endsAt: NOW + 5000, selection, rewards });
  const factionKey = cards.find(([, card]) => card.faction)![0];
  assert.match(String(await detail(seasonDefinition(season({ mode: "manual", cards: [factionKey] }), catalog, NOW))), /only one faction/);
  const card = catalog.cards[factionKey]!;
  const pool = cards.filter(([, other]) => other.set === card.set && other.rarity === card.rarity && !other.unobtainable && !other.faction).length;
  if (pool >= 1 && pool <= 64) {
    const all = await seasonDefinition(season({ mode: "random", seed: "f", count: pool, sets: [card.set], rarities: [card.rarity] }), catalog, NOW);
    for (const drawn of all.cards) assert.ok(!catalog.cards[drawn]?.faction, drawn);
  }
});
