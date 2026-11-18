import assert from "node:assert/strict";
import test from "node:test";
import { parseBonusData } from "../src/bonusEvents.ts";
import { syncFileText } from "../src/syncFile.ts";
import { parseSavedVariables } from "../src/luaTable.ts";
const event = { id: "collectors-hour", title: "Collector's Hour", startsAt: 1800000000, endsAt: 1800003600, effect: "card-drops", percent: 200, sets: ["WF"] };
test("bonus schedules become escaped Lua data with the exact binder pairing", () => {
  const nonce = "b".repeat(32);
  const data = parseBonusData({ at: 1799999990, events: [event] }, [nonce]);
  const lua = syncFileText({ syncedAt: 1799999990, companionReady: true, acks: [], bonuses: data });
  assert.match(lua, /bonuses = /); assert.match(lua, /collectors-hour/);
  const parsed = parseSavedVariables(lua.replace("local _, ACB = ...", "").replace("ACB.sync =", "Example ="));
  const saved = parsed["Example"] as Record<string, unknown>;
  const bonuses = saved["bonuses"] as Record<string, unknown>;
  const events = bonuses["events"] as Record<string, unknown>[];
  assert.deepEqual(events[0], event);
  assert.match(lua, new RegExp(nonce));
});
test("invalid event effects, scopes, windows, multipliers and markup never enter Sync.lua", () => {
  for (const changed of [{ percent: 0 }, { percent: 501 }, { percent: 200.5 }, { effect: "give-cards" }, { endsAt: event.startsAt }, { sets: ["WF", "WF"] }, { title: "bad|Hlink" }, { id: "bad|code" }]) {
    assert.throws(() => parseBonusData({ at: 1, events: [{ ...event, ...changed }] }));
  }
  assert.throws(() => parseBonusData({ at: 1, events: [event, event] }));
  assert.throws(() => parseBonusData({ at: 1, events: [event] }, ["wrong"]));
});
