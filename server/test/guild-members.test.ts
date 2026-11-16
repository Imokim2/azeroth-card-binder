// Guild binders, step two (docs/proposals/GUILD-BINDERS-DESIGN.md): applying to a guild, the owner deciding, leaving and removal. One guild per
// account; a character joins only a guild on its own realm and side; the owner is the first member.
import assert from "node:assert/strict";
import test from "node:test";
import { NOW, newPlayer, setup } from "./harness.ts";
import type { Player } from "./harness.ts";
import { WEEK, askPending as ask, code, decide, founder, post, read } from "./guildKit.ts";
import type { Env } from "./guildKit.ts";

type Member = { id: string; character: string; role: string; state: string };
const joinAs = (env: Env, player: Player, character: string, name: string) => post(env, player, "join", "guild-join", { character, name });
const roster = async (env: Env, player: Player) => (await read(await post(env, player, "roster", "guild-roster"))) as unknown as { guild: { name: string }; members: Member[]; error?: { code: string } };
const membership = async (env: Env, player: Player) => (await read(await post(env, player, "mine", "guild-mine")))["membership"] as { id: string; state: string; role: string; guild: { name: string; members: number } } | null;
const decideMember = (env: Env, owner: Player, member: string, decision: string) => post(env, owner, "decide", "guild-decide", { member, decision });
const pendingOf = async (env: Env, owner: Player) => (await roster(env, owner)).members.find((member) => member.state === "pending")!.id;

// An approved guild owned by Ann on the Alliance side of "Realm Name".
async function guildWithOwner(env: Env, name = "Knights of Light") {
  const ann = await founder(env, "Ann");
  const id = (await read(await ask(env, ann.player, ann.peer, name))).guild!["id"] as string;
  await decide(env, id, "approve");
  return { ann, id };
}

test("approving a guild makes its owner its first member", async () => {
  const env = setup({ guilds: true });
  const { ann, id } = await guildWithOwner(env);
  const seen = await membership(env, ann.player);
  assert.deepEqual([seen!.role, seen!.state, seen!.guild.name, seen!.guild.members], ["owner", "active", "Knights of Light", 1]);
  assert.deepEqual((await roster(env, ann.player)).members.map((member) => [member.character, member.role, member.state]), [[ann.peer, "owner", "active"]]);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM guild_members WHERE guild_id = ?").get(id)!["n"], 1);
  // A guild that was refused has no members.
  const bob = await founder(env, "Bob");
  const refusedId = (await read(await ask(env, bob.player, bob.peer, "Refused Guild"))).guild!["id"] as string;
  await decide(env, refusedId, "refuse");
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM guild_members WHERE guild_id = ?").get(refusedId)!["n"], 0);
});

test("a player applies, the owner approves, and the member can leave or be removed", async () => {
  const env = setup({ guilds: true });
  const { ann } = await guildWithOwner(env);
  const bob = await founder(env, "Bob");
  const applied = await joinAs(env, bob.player, bob.peer, "knights   of LIGHT");
  assert.equal(applied.status, 201);
  const made = (await read(applied))["membership"] as { state: string; role: string };
  assert.deepEqual([made.state, made.role], ["pending", "member"]);
  assert.equal((await membership(env, bob.player))!.state, "pending");

  // Only the owner sees the application, and only the owner decides it.
  assert.equal((await roster(env, bob.player)).error?.code, "not_found");
  const waiting = (await roster(env, ann.player)).members;
  assert.deepEqual(waiting.map((member) => [member.character, member.state]), [[ann.peer, "active"], [bob.peer, "pending"]]);
  const bobRow = waiting[1]!.id;
  assert.equal(await code(await decideMember(env, bob.player, bobRow, "approve")), "not_found");
  assert.equal((await membership(env, bob.player))!.state, "pending");
  assert.equal((await decideMember(env, ann.player, bobRow, "approve")).status, 200);
  const joined = await membership(env, bob.player);
  assert.deepEqual([joined!.state, joined!.guild.members], ["active", 2]);
  const again = await read(await decideMember(env, ann.player, bobRow, "refuse"));
  assert.deepEqual([again.error?.code, again.error?.detail], ["guild_decided", { status: "active" }]);

  // A member leaves, and can come back by applying again.
  assert.equal((await post(env, bob.player, "leave", "guild-leave")).status, 200);
  assert.equal((await membership(env, bob.player))!.state, "left");
  assert.equal((await post(env, bob.player, "leave", "guild-leave")).status, 404);
  env.clock.now += 60; // the newest row is the one shown, so the second application is a minute later
  assert.equal((await joinAs(env, bob.player, bob.peer, "Knights of Light")).status, 201);
  const second = await pendingOf(env, ann.player);
  assert.equal((await decideMember(env, ann.player, second, "approve")).status, 200);

  // The owner removes a member; the owner can neither leave nor be removed.
  assert.equal(await code(await post(env, bob.player, "remove", "guild-remove", { member: second })), "not_found"); // not the owner
  const ownerRow = (await roster(env, ann.player)).members.find((member) => member.role === "owner")!.id;
  assert.equal((await read(await post(env, ann.player, "remove", "guild-remove", { member: ownerRow }))).error?.detail?.["reason"], "owner");
  assert.equal((await read(await post(env, ann.player, "leave", "guild-leave"))).error?.detail?.["reason"], "owner");
  assert.equal((await post(env, ann.player, "remove", "guild-remove", { member: second })).status, 200);
  assert.equal((await membership(env, bob.player))!.state, "removed");
  assert.equal(await code(await post(env, ann.player, "remove", "guild-remove", { member: second })), "not_found"); // already gone
  assert.equal((await roster(env, ann.player)).members.length, 1);
});

test("an application can be refused or withdrawn, and a refused player cannot keep asking", async () => {
  const env = setup({ guilds: true });
  const { ann } = await guildWithOwner(env);
  const bob = await founder(env, "Bob");
  assert.equal((await joinAs(env, bob.player, bob.peer, "Knights of Light")).status, 201);
  assert.equal((await post(env, bob.player, "leave", "guild-leave")).status, 200); // withdrawn
  assert.deepEqual((await roster(env, ann.player)).members.map((member) => member.state), ["active"]);
  for (let round = 0; round < 3; round++) {
    assert.equal((await joinAs(env, bob.player, bob.peer, "Knights of Light")).status, 201);
    assert.equal((await decideMember(env, ann.player, await pendingOf(env, ann.player), "refuse")).status, 200);
    env.clock.now += 60;
  }
  assert.equal((await membership(env, bob.player))!.state, "refused");
  assert.equal((await joinAs(env, bob.player, bob.peer, "Knights of Light")).status, 429);
  env.clock.now = NOW + WEEK + 600;
  assert.equal((await joinAs(env, bob.player, bob.peer, "Knights of Light")).status, 201);
});

test("only the right characters can join: different surnames, same side, Ranked, and one guild at a time", async () => {
  const env = setup({ guilds: true });
  const { ann } = await guildWithOwner(env);
  const join = async (player: Player, peer: string, name = "Knights of Light") => read(await joinAs(env, player, peer, name));
  const horde = await founder(env, "Hal", { side: "horde" });
  const refused = await join(horde.player, horde.peer);
  assert.deepEqual([refused.error?.code, refused.error?.detail], ["guild_ineligible", { reason: "other-side" }]);
  const away = await founder(env, "Cyd", { realm: "Other Realm" });
  assert.equal((await joinAs(env, away.player, away.peer, "Knights of Light")).status, 201); // surnames do not split the world
  const casual = await founder(env, "Cas", { mode: "casual" });
  assert.equal((await join(casual.player, casual.peer)).error?.detail?.["reason"], "not-ranked");
  const bob = await founder(env, "Bob");
  assert.equal((await join(bob.player, bob.peer, "No Such Guild")).error?.code, "not_found");
  assert.equal((await join(bob.player, ann.peer)).error?.code, "bad_request"); // not Bob's character
  // A guild still waiting for approval cannot be joined, only an approved one.
  const dee = await founder(env, "Dee");
  await ask(env, dee.player, dee.peer, "Still Waiting");
  const eve = await founder(env, "Eve");
  assert.equal((await join(eve.player, eve.peer, "Still Waiting")).error?.code, "not_found");
  // One guild per account: a member cannot start or join another; the owner of a waiting guild cannot join one; the owner is already in theirs.
  assert.equal((await joinAs(env, bob.player, bob.peer, "Knights of Light")).status, 201);
  assert.equal((await join(bob.player, bob.peer)).error?.code, "guild_taken");
  assert.equal((await read(await ask(env, bob.player, bob.peer, "My Own"))).error?.code, "guild_taken");
  assert.equal((await join(dee.player, dee.peer)).error?.code, "guild_taken");
  assert.equal((await join(ann.player, ann.peer)).error?.code, "guild_taken");
});

test("two applications at once from one player let only one through", async () => {
  const env = setup({ guilds: true });
  await guildWithOwner(env);
  const bob = await founder(env, "Bob");
  const results = await Promise.all([joinAs(env, bob.player, bob.peer, "Knights of Light"), joinAs(env, bob.player, bob.peer, "Knights of Light")]);
  assert.deepEqual(results.map((response) => response.status).sort(), [201, 409]);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM guild_members WHERE player_id = ?").get(bob.id)!["n"], 1);
});

test("member routes need the right signature and a well-formed member id", async () => {
  const env = setup({ guilds: true });
  const { ann } = await guildWithOwner(env);
  const bob = await founder(env, "Bob");
  await joinAs(env, bob.player, bob.peer, "Knights of Light");
  const row = await pendingOf(env, ann.player);
  assert.equal(await code(await decideMember(env, ann.player, "nonsense", "approve")), "bad_request");
  assert.equal(await code(await decideMember(env, ann.player, row, "maybe")), "bad_request");
  assert.equal(await code(await decideMember(env, ann.player, "0".repeat(26), "approve")), "not_found");
  const send = (path: string, body: Record<string, unknown>) => env.call("/v1/guilds/" + path, { body });
  const good = (await import("./guildKit.ts")).signed(ann.player, "guild-decide", { member: row, decision: "approve" }, { sentAt: env.clock.now });
  assert.equal(await code(await send("decide", { ...good, decision: "refuse" })), "bad_signature"); // the decision is signed
  assert.equal(await code(await send("remove", good)), "bad_signature"); // and so is the purpose
  const stranger = (await import("./guildKit.ts")).signed(newPlayer("Stranger"), "guild-roster", {}, { sentAt: env.clock.now });
  assert.equal(await code(await send("roster", stranger)), "unknown_key");
  assert.equal((await roster(env, ann.player)).members.find((member) => member.id === row)!.state, "pending"); // none of that decided it
  // With guilds off none of the member routes exist.
  const off = setup();
  for (const path of ["join", "roster", "decide", "leave", "remove"]) assert.equal(await code(await off.call("/v1/guilds/" + path, { body: {} })), "not_found", path);
});

test("deleting an account removes its membership but not the guild", async () => {
  const env = setup({ guilds: true });
  const { ann, id } = await guildWithOwner(env);
  const bob = await founder(env, "Bob");
  await joinAs(env, bob.player, bob.peer, "Knights of Light");
  await decideMember(env, ann.player, await pendingOf(env, ann.player), "approve");
  await env.store.deletePlayer(bob.id);
  assert.deepEqual((env.raw.prepare("SELECT player_id AS p FROM guild_members WHERE guild_id = ?").all(id) as { p: string }[]).map((row) => row.p), [ann.id]);
  await env.store.deletePlayer(ann.id);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM guild_members").get()!["n"], 0);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM guilds WHERE id = ? AND status = 'active'").get(id)!["n"], 1);
});
