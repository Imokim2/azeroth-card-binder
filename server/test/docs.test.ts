// docs/API.md must list exactly the errors the server can return (docs and code cannot drift apart).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { ERRORS } from "../src/errors.ts";

const doc = readFileSync(new URL("../../docs/API.md", import.meta.url), "utf8").replace(/\r\n/g, "\n");

test("the error table in docs/API.md equals src/errors.ts", () => {
  const table = doc.split("<!-- errors:start -->")[1]?.split("<!-- errors:end -->")[0] ?? "";
  const documented = [...table.matchAll(/^\| `(\w+)` \| (\d+) \| (.+) \|$/gm)].map((row) => [row[1], Number(row[2]), row[3]]);
  const actual = Object.entries(ERRORS).map(([code, error]) => [code, error.status, error.message]);
  assert.deepEqual(documented, actual);
});
