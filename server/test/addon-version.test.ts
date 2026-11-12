// An add-on older than the oldest the server accepts gets no tape: it can finish what it already has, and then Ranked waits
// for an update. A player whose add-on version is not known is treated as current, so no request is ever stranded.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { canonicalJson } from "../../packages/shared/src/crypto.ts";
import { releasesFrom } from "../src/releases.ts";
import { NOW, newPlayer, registration, setup } from "./harness.ts";
import type { Player } from "./harness.ts";

type Body = Record<string, unknown> & { error?: { code: string; detail?: Record<string, unknown> } };
const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };

const tapeRequest = (player: Player, extra: Record<string, unknown> = {}) => {
  const body = { key: player.publicKeyHex, sentAt: NOW, ...extra };
  return { ...body, sig: reference.signBatch({ ...body, purpose: "tape" }, player.privateKey) };
};

async function playerWith(minAddon: string) {
  const env = setup();
  env.deps.releases = { latestApp: "0.2.0", latestAddon: "0.5.0", minAddon };
  const player = newPlayer("alice");
  await env.call("/v1/register", { body: registration(player) });
  return { env, player };
}

test("tape goes to an add-on at or above the oldest accepted version, and to one that did not say its version", async () => {
  const { env, player } = await playerWith("0.4.0");
  for (const extra of [{ addon: "0.4.0" }, { addon: "0.5.2" }, {}]) {
    const response = await env.call("/v1/tape", { body: tapeRequest(player, extra) });
    assert.equal(response.status, 200, JSON.stringify(extra) + " " + JSON.stringify(await read(response)));
  }
});

test("an add-on below the oldest accepted version is told to update, and nothing is issued to it", async () => {
  const { env, player } = await playerWith("0.4.0");
  const before = env.raw.prepare("SELECT COUNT(*) AS n FROM tapes").get()?.["n"];
  const response = await env.call("/v1/tape", { body: tapeRequest(player, { addon: "0.3.9" }) });
  const body = await read(response);
  assert.equal(response.status, 426);
  assert.equal(body.error?.code, "addon_too_old");
  assert.deepEqual(body.error?.detail, { minAddon: "0.4.0", latestAddon: "0.5.0" });
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM tapes").get()?.["n"], before, "no tape was issued");
});

test("the version a request names is signed with it, so it cannot be changed on the way", async () => {
  const { env, player } = await playerWith("0.4.0");
  const request = tapeRequest(player, { addon: "0.3.9" });
  const changed = await env.call("/v1/tape", { body: { ...request, addon: "0.5.0" } });
  assert.equal((await read(changed)).error?.code, "bad_signature");
});

test("a version that is not x.y.z is refused", async () => {
  const { env, player } = await playerWith("0.4.0");
  for (const addon of ["latest", "0.4", 4, "0.4.0; drop"]) {
    const response = await env.call("/v1/tape", { body: tapeRequest(player, { addon }) });
    assert.equal(response.status, 400, String(addon));
  }
});

test("with no minimum announced every add-on gets tape", async () => {
  const env = setup();
  const player = newPlayer("alice");
  await env.call("/v1/register", { body: registration(player) });
  const response = await env.call("/v1/tape", { body: tapeRequest(player, { addon: "0.0.1" }) });
  assert.equal(response.status, 200);
});

test("the signed manifest is passed on, and ignored when it cannot be read or is not signed", () => {
  const vars = { MIN_CLIENT: "0.1.0", LATEST_APP: "0.2.0", LATEST_ADDON: "0.4.0", MIN_ADDON: "0.3.0" };
  const manifest = canonicalJson({ format: 1, app: { version: "0.3.0" }, addon: { version: "0.5.0" } });
  const signature = "ab".repeat(64);
  assert.deepEqual(releasesFrom(vars, { manifest, signature }), {
    latestApp: "0.3.0", latestAddon: "0.5.0", minAddon: "0.3.0", signed: { manifest, signature },
  });
  assert.deepEqual(releasesFrom(vars, { manifest: null, signature: null }), { latestApp: "0.2.0", latestAddon: "0.4.0", minAddon: "0.3.0" });
  assert.equal(releasesFrom(vars, { manifest: "{not json", signature }).latestAddon, "0.4.0");
  assert.equal(releasesFrom(vars, { manifest, signature: "short" }).latestAddon, "0.4.0");
  assert.equal(releasesFrom(vars, { manifest: canonicalJson({ app: { version: "x" }, addon: { version: "0.5.0" } }), signature }).latestAddon, "0.4.0");
});
