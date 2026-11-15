// Guild binders, step one (docs/proposals/GUILD-BINDERS-DESIGN.md): asking for a guild and a reviewer approving it. A guild takes its side from
// what the asking character's Ranked binder declared, holds its name on its realm while it is pending or active, and is off unless switched on.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { ApiError } from "../src/errors.ts";
import { guildSideOf, parseCharacter, parseGuildName } from "../src/guilds.ts";
import { NOW, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";
import { WEEK, admin, ask, code, decide, founder, mine, read, signed } from "./guildKit.ts";
import type { Env } from "./guildKit.ts";

test("guild routes do not exist until they are switched on", async () => {
  const env = setup(); // no guilds
  const ann = newPlayer("Ann");
  assert.equal(await code(await ask(env, ann, "ann-realmname", "Knights of Light")), "not_found");
  assert.equal(await code(await env.call("/v1/guilds/mine", { body: signed(ann, "guild-mine") })), "not_found");
  assert.equal(await code(await env.call("/v1/admin/guilds", { headers: admin })), "not_found");
  assert.equal(await code(await decide(env, "0".repeat(26), "approve")), "not_found");
});

test("a Ranked character with a declared side asks for a guild, and a reviewer approves it", async () => {
  const env = setup({ guilds: true });
  const ann = await founder(env, "Ann", { side: "horde" });
  const response = await ask(env, ann.player, "Ann-RealmName", "  Knights   of Light ");
  assert.equal(response.status, 201);
  const guild = (await read(response)).guild!;
  assert.match(guild["id"] as string, /^[0-9A-Z]{26}$/);
  assert.deepEqual({ ...guild, id: undefined }, {
    id: undefined, name: "Knights of Light", realm: "Realm Name", side: "horde", status: "pending", character: "ann-realmname", requestedAt: NOW, decidedAt: null, note: "",
  });
  assert.deepEqual(await mine(env, ann.player), [guild]);

  // A reviewer sees it with whose it is. Nobody else is told.
  assert.equal(await code(await env.call("/v1/admin/guilds")), "unauthorized");
  const waiting = (await read(await env.call("/v1/admin/guilds", { headers: admin }))).guilds!;
  assert.equal(waiting.length, 1);
  assert.equal(waiting[0]!["ownerId"], ann.id);
  env.clock.now = NOW + 60;
  const done = await decide(env, guild["id"] as string, "approve", " welcome ");
  assert.equal(done.status, 200);
  const approved = (await read(done)).guild!;
  assert.deepEqual([approved["status"], approved["decidedAt"], approved["decidedBy"], approved["note"]], ["active", NOW + 60, "token", "welcome"]);
  assert.equal((await mine(env, ann.player))[0]!["status"], "active");
  assert.deepEqual((await read(await env.call("/v1/admin/guilds", { headers: admin }))).guilds, []); // nothing left waiting
  assert.equal((await read(await env.call("/v1/admin/guilds?state=active", { headers: admin }))).guilds!.length, 1);
  const audit = (await read(await env.call("/v1/admin/audit", { headers: admin }))) as unknown as { entries: { action: string; target: string; detail: string }[] };
  assert.deepEqual(audit.entries.filter((entry) => entry.action.startsWith("guild-")).map((entry) => [entry.action, entry.target, entry.detail]),
    [["guild-approve", guild["id"], "Knights of Light (Realm Name, horde) - welcome"]]);
});

test("a binder that has declared its side through the real faction events can start a guild", async () => {
  const env = setup({ guilds: true });
  const ledger = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { GENESIS: string; makeEvent(partial: Record<string, unknown>, prev: string): Record<string, unknown> & { h: string } };
  const player = newPlayer("Real");
  const registered = await read(await env.call("/v1/register", { body: registration(player) }));
  let prev = ledger.GENESIS;
  const events = ["chase1", "chase2", "launch1", "faction1", "side:horde"].map((key, index) => {
    const made = ledger.makeEvent({ seq: index + 1, t: 1000 + index, char: "Hal-Realm", kind: "mode", key, count: 0, tape: 0, dust: 0, shiny: 0, partner: "", trade: "" }, prev);
    prev = made.h;
    return made;
  });
  const sent = await env.call("/v1/ledger", { body: signedUpload(player, events, { specVersion: 10, character: "Hal", realm: "Realm", snapshot: { counts: {}, dust: 0, sets: {}, attempts: {}, titles: {} } }) });
  assert.equal(sent.status, 200);
  const id = registered["playerId"] as string;
  // Not Ranked yet: this binder is Casual, so a guild is refused for that reason alone.
  const refused = await read(await ask(env, player, "hal-realm", "Horde Heroes"));
  assert.deepEqual([refused.error?.code, refused.error?.detail], ["guild_ineligible", { reason: "not-ranked" }]);
  env.raw.prepare("UPDATE ledger_state SET state_json = json_set(state_json, '$.mode', 'ranked2') WHERE player_id = ?").run(id);
  const guild = (await read(await ask(env, player, "hal-realm", "Horde Heroes"))).guild!;
  assert.deepEqual([guild["side"], guild["realm"]], ["horde", "Realm"]);
});

test("a binder that is not Ranked, has no faction rules or has declared no side cannot start a guild", async () => {
  const env = setup({ guilds: true });
  const reason = async (player: Player, peer: string) => (await read(await ask(env, player, peer, "Some Guild"))).error;
  const casual = await founder(env, "Cas", { mode: "casual" });
  assert.deepEqual(await reason(casual.player, casual.peer), { code: "guild_ineligible", message: "This binder cannot start a guild yet: it needs Ranked play and a declared faction.", detail: { reason: "not-ranked" } });
  const old = await founder(env, "Old", { faction: false });
  assert.deepEqual((await reason(old.player, old.peer))!.detail, { reason: "no-faction" });
  const none = await founder(env, "None", { side: null });
  assert.deepEqual((await reason(none.player, none.peer))!.detail, { reason: "no-side" });
  // A side declared by a different character is not this character's.
  const other = await founder(env, "Other");
  env.raw.prepare("UPDATE ledger_state SET state_json = json_set(state_json, '$.sides', json('{\"Someone-RealmName\":\"horde\"}')) WHERE player_id = ?").run(other.id);
  assert.deepEqual((await reason(other.player, other.peer))!.detail, { reason: "no-side" });
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM guilds").get()!["n"], 0);
});

test("only a character the player has played can ask, and the request has to be signed by them", async () => {
  const env = setup({ guilds: true });
  const ann = await founder(env, "Ann");
  const bob = await founder(env, "Bob");
  assert.equal(await code(await ask(env, ann.player, bob.peer, "Not Mine")), "bad_request"); // Bob's character
  assert.equal(await code(await ask(env, ann.player, "nobody-realmname", "Not Mine")), "bad_request");
  assert.equal(await code(await ask(env, newPlayer("Stranger"), ann.peer, "Not Mine")), "unknown_key");
  const body = signed(ann.player, "guild-request", { character: ann.peer, name: "Real Name" });
  assert.equal(await code(await env.call("/v1/guilds/request", { body: { ...body, name: "Other Name" } })), "bad_signature"); // the name is signed
  assert.equal(await code(await env.call("/v1/guilds/request", { body: { ...body, character: bob.peer } })), "bad_signature");
  assert.equal(await code(await env.call("/v1/guilds/request", { body: signed(ann.player, "guild-mine", { character: ann.peer, name: "Real Name" }) })), "bad_signature"); // a signature for another purpose
  assert.equal(await code(await env.call("/v1/guilds/request", { body: { ...body, sentAt: NOW - 90_000 } })), "bad_request");
  assert.equal(await code(await env.call("/v1/guilds/request", { body: { ...body, sig: undefined } })), "bad_request");
  assert.equal(await code(await env.call("/v1/guilds/request", { raw: "nope", headers: { "content-type": "application/json" } })), "bad_request");
  assert.equal(await code(await env.call("/v1/guilds/request", { raw: "{}", headers: { "content-type": "text/plain" } })), "unsupported_media");
  // A banned player cannot start a guild.
  await env.call(`/v1/admin/players/${bob.id}/ban`, { body: { banned: true }, headers: admin });
  assert.equal(await code(await ask(env, bob.player, bob.peer, "Banned Guild")), "banned");
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM guilds").get()!["n"], 0);
});

test("a name is held on its realm while it is pending or active, however it is spelled, and is free again once refused", async () => {
  const env = setup({ guilds: true });
  const ann = await founder(env, "Ann");
  const bob = await founder(env, "Bob");
  const first = (await read(await ask(env, ann.player, ann.peer, "Knights of Light"))).guild!;
  const same = await read(await ask(env, bob.player, bob.peer, "KNIGHTS  OF  LIGHT"));
  assert.deepEqual([same.error?.code, same.error?.detail], ["guild_taken", { reason: "name" }]);
  assert.equal(await code(await ask(env, bob.player, bob.peer, "Knight's of Light")), "guild_taken"); // apostrophes do not tell names apart
  const elsewhere = await founder(env, "Cyd", { realm: "Other Realm" });
  assert.equal((await ask(env, elsewhere.player, elsewhere.peer, "Knights of Light")).status, 201); // another realm, another guild
  assert.equal((await decide(env, first["id"] as string, "approve")).status, 200);
  assert.equal(await code(await ask(env, bob.player, bob.peer, "Knights of Light")), "guild_taken"); // still held once active
  assert.equal((await decide(env, (await mine(env, elsewhere.player))[0]!["id"] as string, "refuse", "name is taken in game")).status, 200);
  assert.equal((await ask(env, elsewhere.player, elsewhere.peer, "Knights of Light")).status, 201); // a refusal frees the name
  // Two accounts racing for one name: the unique index lets one through.
  const racers = await Promise.all([ask(env, bob.player, bob.peer, "Fast Guild"), ask(env, bob.player, bob.peer, "Fast Guild")]);
  assert.deepEqual(racers.map((response) => response.status).sort(), [201, 409]);
});

test("a player has one live guild at a time, and cannot keep asking after being refused", async () => {
  const env = setup({ guilds: true });
  const ann = await founder(env, "Ann");
  const first = (await read(await ask(env, ann.player, ann.peer, "First Try"))).guild!;
  const second = await read(await ask(env, ann.player, ann.peer, "Second Try"));
  assert.deepEqual([second.error?.code, second.error?.detail], ["guild_taken", { reason: "already-have-one" }]);
  for (const [index, name] of ["First Try", "Second Try", "Third Try"].entries()) {
    const id = index === 0 ? (first["id"] as string) : ((await read(await ask(env, ann.player, ann.peer, name))).guild!["id"] as string);
    assert.equal((await decide(env, id, "refuse", "no")).status, 200);
    env.clock.now += 60;
  }
  const refused = await ask(env, ann.player, ann.peer, "Fourth Try");
  assert.equal(refused.status, 429);
  assert.equal(refused.headers.get("retry-after"), "86400");
  env.clock.now = NOW + WEEK + 600; // the refusals are more than a week old
  assert.equal((await ask(env, ann.player, ann.peer, "Fourth Try")).status, 201);
  assert.equal((await mine(env, ann.player)).length, 4);
});

test("a reviewer's decision is checked, and a decided guild is not decided again", async () => {
  const env = setup({ guilds: true });
  const ann = await founder(env, "Ann");
  const id = (await read(await ask(env, ann.player, ann.peer, "Knights of Light"))).guild!["id"] as string;
  assert.equal(await code(await env.call(`/v1/admin/guilds/${id}`, { body: { decision: "approve" } })), "unauthorized");
  assert.equal(await code(await decide(env, id, "maybe")), "bad_request");
  assert.equal(await code(await decide(env, id, "approve", "x".repeat(201))), "bad_request");
  assert.equal(await code(await decide(env, id, "approve", "line\nbreak")), "bad_request");
  assert.equal(await code(await decide(env, "0".repeat(26), "approve")), "not_found");
  assert.equal(await code(await env.call("/v1/admin/guilds?state=bogus", { headers: admin })), "bad_request");
  assert.equal(env.raw.prepare("SELECT status FROM guilds").get()!["status"], "pending"); // none of that changed it
  assert.equal((await decide(env, id, "refuse", "not on this realm")).status, 200);
  const again = await read(await decide(env, id, "approve"));
  assert.deepEqual([again.error?.code, again.error?.detail], ["guild_decided", { status: "refused" }]);
  assert.equal((await mine(env, ann.player))[0]!["note"], "not on this realm"); // the player sees why
  assert.equal(env.raw.prepare("SELECT status FROM guilds").get()!["status"], "refused");
});

test("deleting an account removes its unapproved requests and leaves an approved guild without its owner", async () => {
  const env = setup({ guilds: true });
  const ann = await founder(env, "Ann");
  const bob = await founder(env, "Bob");
  const approved = (await read(await ask(env, ann.player, ann.peer, "Knights of Light"))).guild!["id"] as string;
  await decide(env, approved, "approve");
  await ask(env, bob.player, bob.peer, "Pending Guild");
  // The export holds what is held about the player.
  const data = (await read(await env.call("/v1/export", { body: signed(ann.player, "export") }))) as unknown as { guilds: { name: string; status: string }[] };
  assert.deepEqual(data.guilds.map((guild) => [guild.name, guild.status]), [["Knights of Light", "active"]]);
  await env.store.deletePlayer(ann.id);
  await env.store.deletePlayer(bob.id);
  const left = env.raw.prepare("SELECT id, name, status, owner_player_id AS owner, owner_character AS character FROM guilds").all() as Record<string, unknown>[];
  assert.deepEqual(left.map((row) => ({ ...row })), [{ id: approved, name: "Knights of Light", status: "active", owner: null, character: "" }]);
  // Its name stays held, and the owner can be replaced by a person who runs the service.
  const cyd = await founder(env, "Cyd");
  assert.equal(await code(await ask(env, cyd.player, cyd.peer, "Knights of Light")), "guild_taken");
});

test("a guild name is letters with single spaces, apostrophes and dashes, of the length the game allows", () => {
  const ok = (name: string) => parseGuildName(name);
  assert.equal(ok("Knights of Light"), "Knights of Light");
  assert.equal(ok("  Sons   of   Azeroth "), "Sons of Azeroth");
  assert.equal(ok("O'Brien-Smith Clan"), "O'Brien-Smith Clan");
  assert.equal(ok("Élite Wächter"), "Élite Wächter");
  assert.equal(ok("Ab"), "Ab");
  assert.equal(ok("a".repeat(24)), "a".repeat(24));
  for (const bad of ["", "A", " ", "a".repeat(25), "Guild1", "Guild 2", "<b>Guild</b>", "Gu|ild", "'Guild", "Guild'", "-Guild", "Guild -x", "Guild  - x", "Gui\nld", "Guild\u0000", "x'-y"]) {
    assert.throws(() => parseGuildName(bad), (error: unknown) => error instanceof ApiError && error.code === "bad_request" && error.detail?.["field"] === "name", JSON.stringify(bad));
  }
  for (const bad of [undefined, null, 5, ["Guild"], {}]) assert.throws(() => parseGuildName(bad), ApiError);
  assert.equal(parseCharacter("Ann-Realm Name".replace(" ", "")), "ann-realmname");
  for (const bad of ["ann", "ann-", "-realm", "an n-realm", "ann-re<alm", "a|b-c", `${"a".repeat(41)}-realm`, 5]) assert.throws(() => parseCharacter(bad), ApiError, String(bad));
});

test("the side comes from the binder's own record of the character", () => {
  const state = { mode: "ranked2", faction: 1, sides: { "Hal-Realm": "horde", "Ann-Other Realm": "alliance" } };
  assert.deepEqual(guildSideOf(state, "hal-realm"), { side: "horde" });
  assert.deepEqual(guildSideOf(state, "ann-otherrealm"), { side: "alliance" });
  assert.deepEqual(guildSideOf({ ...state, mode: "ranked" }, "hal-realm"), { side: "horde" });
  assert.deepEqual(guildSideOf(state, "bob-realm"), { reason: "no-side" });
  assert.deepEqual(guildSideOf({ ...state, sides: { "Hal-Realm": "neutral" } }, "hal-realm"), { reason: "no-side" });
  assert.deepEqual(guildSideOf({ ...state, mode: "casual" }, "hal-realm"), { reason: "not-ranked" });
  assert.deepEqual(guildSideOf({ mode: "ranked2", sides: state.sides }, "hal-realm"), { reason: "no-faction" });
  assert.deepEqual(guildSideOf(null, "hal-realm"), { reason: "no-binder" });
  assert.deepEqual(guildSideOf("junk", "hal-realm"), { reason: "no-binder" });
});
