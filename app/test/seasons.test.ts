import assert from "node:assert/strict";
import test from "node:test";
import { parseSeasonData } from "../src/seasons.ts";
import { syncFileText } from "../src/syncFile.ts";
import { parseSavedVariables } from "../src/luaTable.ts";
const data = () => ({ at: 100, seasons: [{ id: "first-hunt", title: "The First Hunt", startsAt: 100, endsAt: 200,
  cards: ["npc:589"], collected: [], place: 0, completedAt: 0, titles: [],
  rewards: { completion: { title: "Seeker", packs: [{ pack: "WF", count: 1 }] }, first: { places: 3, title: "Champion", packs: [] } },
}], grants: [{ id: "a".repeat(32), pack: "WF" }] });
test("seasonal data survives safe Lua serialization with its local binder pairing", () => {
  const value = data(); value.seasons[0]!.title = 'Hunter "One"\\\nreturn os.execute("bad")';
  const parsed = parseSeasonData(value, ["b".repeat(32)]);
  const lua = syncFileText({ syncedAt: 100, acks: [], seasonal: parsed });
  const tables = parseSavedVariables(lua.replace("local _, ACB = ...", "").replace("ACB.sync =", "SEASONS ="));
  const synced = tables["SEASONS"] as Record<string, unknown>;
  const season = (synced["seasonal"] as Record<string, unknown>)["seasons"] as Record<string, unknown>[];
  assert.equal(season[0]!["title"], value.seasons[0]!.title, "network text remains literal text");
  assert.ok(lua.includes('"' + "b".repeat(32) + '"'));
});
test("oversized and malformed seasonal data cannot enter Sync.lua", () => {
  const oversized = data(); oversized.seasons[0]!.cards = Array(65).fill("npc:589");
  assert.throws(() => parseSeasonData(oversized));
  const invalid = data(); invalid.grants[0]!.id = 'bad"; execute()';
  assert.throws(() => parseSeasonData(invalid));
  const unknown = data(); unknown.seasons[0]!.collected = ["npc:1"] as never[];
  assert.throws(() => parseSeasonData(unknown));
});
test("the cards a season has released reach the add-on in Sync.lua, are bounded, and an older server's silence means none", () => {
  const withReleased = { ...data(), released: ["npc:589", "npc:594", "edition:5891"] };
  const parsed = parseSeasonData(withReleased, ["b".repeat(32)]);
  assert.deepEqual(parsed.released, ["npc:589", "npc:594", "edition:5891"]);
  const lua = syncFileText({ syncedAt: 100, acks: [], seasonal: parsed });
  const tables = parseSavedVariables(lua.replace("local _, ACB = ...", "").replace("ACB.sync =", "RELEASED ="));
  const seasonal = (tables["RELEASED"] as Record<string, unknown>)["seasonal"] as Record<string, unknown>;
  assert.deepEqual(Object.values(seasonal["released"] as Record<string, string>), ["npc:589", "npc:594", "edition:5891"]);
  assert.deepEqual(parseSeasonData(data(), []).released, [], "no list from an older server");
  assert.throws(() => parseSeasonData({ ...data(), released: Array(2001).fill("npc:589") }));
  assert.throws(() => parseSeasonData({ ...data(), released: ['npc:1"; os.execute("bad")'] }));
});
