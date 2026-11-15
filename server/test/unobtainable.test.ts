// A season cannot feature a card whose creature cannot be killed: not by name, and not by chance in a random pick.
import assert from "node:assert/strict";
import test from "node:test";
import { seasonDefinition } from "../src/seasons.ts";
import { NOW, catalog } from "./harness.ts";

const unobtainable = Object.entries(catalog.cards).filter(([, card]) => card.unobtainable).map(([key]) => key);
const rewards = { completion: { title: "", packs: [] }, first: { places: 0, title: "", packs: [] } };
const season = (selection: Record<string, unknown>) => ({ id: "test-season", title: "Test", startsAt: NOW + 100, endsAt: NOW + 5000, selection, rewards });
const detail = async (work: Promise<unknown>) => { try { await work; return null; } catch (error) { return (error as { detail?: { field?: string } }).detail?.field ?? "?"; } };

test("a season that names a card that cannot be won is refused, and one that names others is fine", async () => {
  assert.ok(unobtainable.length >= 10);
  const other = Object.entries(catalog.cards).find(([key, card]) => !card.baseKey && !card.unobtainable && key.startsWith("npc:"))![0];
  assert.match(String(await detail(seasonDefinition(season({ mode: "manual", cards: [other, unobtainable[0]] }), catalog, NOW))), /cannot be won/);
  const ok = await seasonDefinition(season({ mode: "manual", cards: [other] }), catalog, NOW);
  assert.deepEqual(ok.cards, [other]);
});

test("a random season never draws one, even when it asks for every card its filters leave", async () => {
  let checked = 0;
  for (const key of unobtainable) {
    const card = catalog.cards[key]!;
    const filters = { sets: [card.set], rarities: [card.rarity], bossesOnly: card.boss === true };
    const pool = Object.entries(catalog.cards).filter(([, other]) => other.set === card.set && !other.baseKey && other.rarity === card.rarity && (!filters.bossesOnly || other.boss) && !other.unobtainable && !other.faction).length;
    if (pool < 1 || pool > 64) continue; // too many to ask for all of them at once
    const everything = await seasonDefinition(season({ mode: "random", seed: "all", count: pool, ...filters }), catalog, NOW);
    assert.equal(everything.cards.length, pool, key);
    for (const drawn of everything.cards) assert.ok(!catalog.cards[drawn]?.unobtainable, key + " came up as " + drawn);
    assert.equal(await detail(seasonDefinition(season({ mode: "random", seed: "all", count: pool + 1, ...filters }), catalog, NOW)), "count", "one more than the filters leave is more than there is");
    checked++;
  }
  assert.ok(checked >= 3, "enough of them could be asked for in full (" + checked + ")");
});
