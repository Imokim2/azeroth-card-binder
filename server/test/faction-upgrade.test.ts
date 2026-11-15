import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { checkTape, shinyValue, tapeEntry, tapeKey } from "../src/tape.ts";
import { newState } from "../src/shared.ts";
import { catalog } from "./harness.ts";

const fixture = JSON.parse(readFileSync(new URL("../../tests/fixtures/spec9-packs.json", import.meta.url), "utf8")) as {
  sourceCatalogVersion: string;
  testTape: { secret: string; playerId: string };
  serverCases: { zone: string; position: number; entry: string; expected: string }[];
};

test("the server accepts published spec-9 pack outcomes after the catalog changes", async () => {
  assert.equal(fixture.sourceCatalogVersion, "3d0b62359bee");
  assert.equal(fixture.serverCases.length, 56);
  const key = await tapeKey(fixture.testTape.secret);
  for (const row of fixture.serverCases) {
    const entry = await tapeEntry(key, fixture.testTape.playerId, row.position);
    assert.equal(entry, row.entry);
    const event = { seq: 1, prev: "0".repeat(32), h: "0".repeat(32), kind: "packCard", key: row.expected,
      char: "Upgrade-Realm", t: 1000, count: 1, tape: row.position, dust: 0, shiny: shinyValue(entry, catalog.shinyOdds) === 1 ? 1 : 0,
      partner: "", trade: "" };
    const result = await checkTape({ key, playerId: fixture.testTape.playerId, catalog, events: [event],
      stateBefore: { ...newState(), mode: "ranked2", balance: 2, launch: 1, packZone: row.zone, packLeft: 1 },
      issuedEnd: row.position, stack: {}, tapeNext: row.position + 1, available: () => false });
    assert.equal(result.failure, null, `${row.zone} / tape ${row.position}`);
  }
});
