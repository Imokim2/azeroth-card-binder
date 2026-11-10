// The saved-data reader: the shapes the game writes, and the ways a hand-edited or hostile file must be refused.
import assert from "node:assert/strict";
import test from "node:test";
import { LuaSyntaxError, parseSavedVariables } from "../src/luaTable.ts";

const sample = `
AzerothCardBinderDB = {
\t["counts"] = {
\t\t["npc:639"] = 2,
\t\t["node:1731"] = 1,
\t},
\t["dust"] = 12,
\t["popups"] = false,
\t["title"] = "Defias Delver",
\t["ledger"] = {
\t\t{
\t\t\t["seq"] = 1,
\t\t\t["kind"] = "drop",
\t\t\t["dust"] = -10,
\t\t}, -- [1]
\t\t{
\t\t\t["seq"] = 2,
\t\t\t["kind"] = "craft",
\t\t}, -- [2]
\t},
\t["rolledGuids"] = {
\t\t"Creature-0-1-2-3-589-0001", -- [1]
\t\t"Creature-0-1-2-3-590-0002", -- [2]
\t},
\t["head"] = {
\t\t["seq"] = 2,
\t\t["hash"] = "0123456789abcdef0123456789abcdef",
\t},
}
`;

test("reads the layout the game writes: tabs, quoted keys, trailing commas, list comments", () => {
  const result = parseSavedVariables(sample);
  const db = result["AzerothCardBinderDB"] as Record<string, unknown>;
  assert.deepEqual(db["counts"], { "npc:639": 2, "node:1731": 1 });
  assert.equal(db["dust"], 12);
  assert.equal(db["popups"], false);
  assert.equal(db["title"], "Defias Delver");
  assert.deepEqual(db["ledger"], [{ seq: 1, kind: "drop", dust: -10 }, { seq: 2, kind: "craft" }]);
  assert.deepEqual(db["rolledGuids"], ["Creature-0-1-2-3-589-0001", "Creature-0-1-2-3-590-0002"]);
  assert.deepEqual(db["head"], { seq: 2, hash: "0123456789abcdef0123456789abcdef" });
});

test("reads every kind of value, key and escape", () => {
  const result = parseSavedVariables(String.raw`
    -- a comment, and a block one
    --[[ block
    comment ]]
    A = { 1, 2, 3 }
    B = { [1] = "a", [2] = "b", [4] = "d" }
    C = { name = "bare", ["with space"] = 1.5, [-3] = true, [0.5] = false }
    D = "quote \" backslash \\ newline \n tab \t nul \0 bell \7 ' end"
    E = 'single "double" inside'
    F = [[long
string]]
    G = [==[has ]] inside]==]
    H = { 0x10, 1e3, -2.5e-1, .5, 7. }
    I = { nil, true, false }
    J = { 1; 2; k = 3 }
    K = { {}, { {} } }
  `);
  assert.deepEqual(result["A"], [1, 2, 3]);
  assert.deepEqual(result["B"], { "1": "a", "2": "b", "4": "d" });
  assert.deepEqual(result["C"], { name: "bare", "with space": 1.5, "-3": true, "0.5": false });
  assert.equal(result["D"], "quote \" backslash \\ newline \n tab \t nul \u0000 bell \u0007 ' end");
  assert.equal(result["E"], 'single "double" inside');
  assert.equal(result["F"], "string".padStart(11, "long\n"));
  assert.equal(result["G"], "has ]] inside");
  assert.deepEqual(result["H"], [16, 1000, -0.25, 0.5, 7]);
  assert.deepEqual(result["I"], [null, true, false]);
  assert.deepEqual(result["J"], { "1": 1, "2": 2, k: 3 });
  assert.deepEqual(result["K"], [[], [[]]]);
});

test("accented and other non-ASCII text survives, written raw or as byte escapes", () => {
  const raw = parseSavedVariables('N = "Zul\'Gurub – Ünïcöde, 日本"');
  assert.equal(raw["N"], "Zul'Gurub – Ünïcöde, 日本");
  // The game may write the UTF-8 bytes of "é" (195 169) as decimal escapes.
  const escaped = parseSavedVariables(String.raw`N = "caf\195\169 \226\128\147 x"`);
  assert.equal(escaped["N"], "café – x");
  // Raw Latin-1-range characters are not mistaken for bytes.
  assert.equal(parseSavedVariables('N = "é"')["N"], "é");
  assert.equal(parseSavedVariables("﻿N = 1")["N"], 1);
});

test("an empty file, or one with other variables beside ours, is fine", () => {
  assert.deepEqual(parseSavedVariables(""), {});
  assert.deepEqual(parseSavedVariables("-- nothing here\n"), {});
  const two = parseSavedVariables("A = { 1 }\nB = { x = 2 }");
  assert.deepEqual(two, { A: [1], B: { x: 2 } });
});

test("anything that is not plain data is refused, and nothing is ever run", () => {
  const refuse = (source: string, pattern: RegExp) => assert.throws(() => parseSavedVariables(source), (error: unknown) => error instanceof LuaSyntaxError && pattern.test(error.message), source);
  refuse('A = os.execute("calc")', /unexpected "os"/);
  refuse("A = (function() return 1 end)()", /unexpected "\("/);
  refuse("A = function() end", /unexpected "function"/);
  refuse("A = { f = print }", /unexpected "print"/);
  refuse("A = { 1 + 2 }", /expected/);
  refuse("A = 1 B", /expected "="/);
  refuse('A = "unterminated', /never closed|past the end/);
  refuse('A = "line\nbreak"', /past the end of its line/);
  refuse(String.raw`A = "bad \q escape"`, /unknown escape/);
  refuse(String.raw`A = "\300"`, /out of range/);
  refuse("A = { 1 2 }", /expected "," or "}"/);
  refuse("A = { [{}] = 1 }", /key must be/);
  refuse("A = 1e999", /not finite/);
  refuse("--[[ never closed", /never closed/);
  refuse("A = {", /unexpected "end of file"/);
  refuse("A = { ... }", /unexpected/);
});

test("the line of a mistake is reported", () => {
  try {
    parseSavedVariables("A = {\n  1,\n  2,\n  bad stuff\n}");
    assert.fail("should have thrown");
  } catch (error) {
    assert.ok(error instanceof LuaSyntaxError);
    assert.equal(error.line, 4);
  }
});

test("deeply nested or enormous input is stopped, not crashed on", () => {
  assert.throws(() => parseSavedVariables("A = " + "{".repeat(200) + "}".repeat(200)), /nested too deeply/);
  assert.throws(() => parseSavedVariables("A = 1\n".repeat(1) + " ".repeat(50_000_001)), /too large/);
  const wide = "A = {" + "1,".repeat(200_000) + "}";
  assert.equal((parseSavedVariables(wide)["A"] as unknown[]).length, 200_000);
});
