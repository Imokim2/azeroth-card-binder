import assert from "node:assert/strict";
import test from "node:test";
import { windowActions } from "../electron/attention.ts";

test("background sync conflicts never reveal, restore or focus the companion", () => {
  for (const initial of ["hidden", "minimized", "visible"] as const) {
    const calls: string[] = [];
    const window = { isMinimized: () => initial === "minimized", restore: () => { calls.push("restore"); },
      show: () => { calls.push("show"); }, focus: () => { calls.push("focus"); } };
    const hints: string[] = [];
    const actions = windowActions(() => window, () => ({ setToolTip: text => hints.push(text) }), () => calls.push("check"));
    actions.syncIssue(); actions.syncIssue();
    assert.deepEqual(calls, [], `sync must leave a ${initial} window alone`);
    assert.ok(hints.every(hint => hint.includes("sync needs attention")));
    actions.open();
    assert.deepEqual(calls, initial === "minimized" ? ["restore", "show", "focus", "check"] : ["show", "focus", "check"],
      "opening the companion intentionally still works");
    assert.equal(hints.at(-1), "World of Warcards");
  }
});

test("an unavailable tray never makes a sync conflict fall back to opening a window", () => {
  const actions = windowActions(() => { throw new Error("background sync must not access the window"); }, () => null,
    () => { throw new Error("background sync must not open the companion"); });
  assert.doesNotThrow(() => actions.syncIssue());
});
