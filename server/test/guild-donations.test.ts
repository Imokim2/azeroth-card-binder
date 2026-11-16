// Guild binders, step three (docs/proposals/GUILD-BINDERS-DESIGN.md): donations (ledger spec 11). A donate event in an upload is settled in the same
// transaction that stores it: credited to the guild, or refused and the copy issued back, which the binder then writes as donateReturn.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";
import { catalog, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";
import { ask, code, founder, post, read } from "./guildKit.ts";
import type { Env } from "./guildKit.ts";

const require = createRequire(import.meta.url);
const ledger = require("../../packages/shared/src/ledger.js") as { GENESIS: string; makeEvent(partial: Record<string, unknown>, prev: string): Record<string, unknown> & { h: string } };
const rules = require("../../packages/shared/src/rules.js") as { replay(events: unknown[], catalog: unknown): { ok: boolean; state: { counts: Record<string, number> } } };

type Part = { kind: string; key: string; count?: number; partner?: string; trade?: string; dust?: number };
const MARKERS = ["chase1", "chase2", "launch1", "faction1"];
const card = "npc:589", other = "npc:590";
const op = (n: number) => String(n).padStart(32, "0").replace(/0/g, "a").slice(0, 32).padEnd(32, "b");

// A binder written by hand: Ranked, with the faction rules on and (when `guild` is true) mode/guild1, holding two copies of `card`.
class Binder {
  events: Record<string, unknown>[] = [];
  sent = 0;
  trades = 0;
  readonly env: Env;
  readonly player: Player;
  readonly name: string;
  readonly realm: string;
  readonly char: string;
  constructor(env: Env, player: Player, name: string, realm = "Realm Name") {
    this.env = env;
    this.player = player;
    this.name = name;
    this.realm = realm;
    this.char = `${name}-${realm.replace(/\s/g, "")}`;
  }
  add(...parts: Part[]) {
    for (const part of parts) {
      const prev = this.events.length ? (this.events[this.events.length - 1] as { h: string }).h : ledger.GENESIS;
      this.events.push(ledger.makeEvent({
        seq: this.events.length + 1, t: 1000 + this.events.length, char: this.char, kind: part.kind, key: part.key,
        count: part.count ?? (part.kind === "mode" ? 0 : 1), tape: 0, dust: part.dust ?? 0, shiny: 0, partner: part.partner ?? "", trade: part.trade ?? "",
      }, prev));
    }
    return this;
  }
  start(options: { guild?: boolean; side?: string } = {}) {
    this.add(...MARKERS.map((key) => ({ kind: "mode", key })), { kind: "mode", key: "side:" + (options.side ?? "alliance") });
    if (options.guild !== false) this.add({ kind: "mode", key: "guild1" });
    return this.add({ kind: "mode", key: "ranked2" }, this.gain(card, 1), this.gain(card, 2));
  }
  gain(key: string, count: number): Part { return { kind: "tradeIn", key, count, partner: "zed-realm", trade: `${this.name}-${++this.trades}` }; }
  donate(key: string, count: number, guild: string, operation: string): Part { return { kind: "donate", key, count, partner: guild, trade: operation }; }
  giveBack(key: string, count: number, guild: string, operation: string): Part { return { kind: "donateReturn", key, count, partner: guild, trade: operation }; }
  // Send what has not been sent yet.
  async upload(specVersion = 11) {
    const fresh = this.events.slice(this.sent);
    const played = rules.replay(this.events, catalog);
    const snapshot = { counts: played.ok ? played.state.counts : {}, // a history that breaks a rule is sent anyway: the server must refuse it
 dust: 0, sets: {}, attempts: {}, titles: {} };
    const response = await this.env.call("/v1/ledger", { body: signedUpload(this.player, fresh, { specVersion, character: this.name, realm: this.realm, snapshot, tapeIndex: 0, sentAt: this.env.clock.now }) });
    if (response.status === 200) this.sent = this.events.length;
    return response;
  }
}

async function binder(env: Env, name: string, options: { guild?: boolean; side?: string; realm?: string } = {}) {
  const player = newPlayer(name);
  const registered = await read(await env.call("/v1/register", { body: registration(player) }));
  const made = new Binder(env, player, name, options.realm).start(options);
  const response = await made.upload();
  assert.equal(response.status, 200, JSON.stringify(await response.clone().json()));
  return { binder: made, player, id: registered["playerId"] as string, peer: `${name.toLowerCase()}-${(options.realm ?? "Realm Name").replace(/[\s'-]/g, "").toLowerCase()}` };
}

// Ann owns an approved guild (her binder is set up directly: she does not donate). Returns the guild's id.
async function guildOf(env: Env, name = "Knights of Light", owner = "Ann") {
  const ann = await founder(env, owner);
  const id = (await read(await ask(env, ann.player, ann.peer, name))).guild!["id"] as string;
  return { ann, id };
}
async function enrol(env: Env, guildName: string, member: { player: Player; peer: string }, owner: { player: Player }) {
  assert.equal((await post(env, member.player, "join", "guild-join", { character: member.peer, name: guildName })).status, 201);
  const roster = (await read(await post(env, owner.player, "roster", "guild-roster"))) as unknown as { members: { id: string; state: string }[] };
  const pending = roster.members.find((entry) => entry.state === "pending")!.id;
  assert.equal((await post(env, owner.player, "decide", "guild-decide", { member: pending, decision: "approve" })).status, 200);
}
const donations = (env: Env) => env.raw.prepare("SELECT operation_id AS op, guild_id AS guild, card_key AS card, result, reason, returned_seq AS returned FROM guild_donations ORDER BY seq, operation_id").all().map((row) => ({ ...row })) as
  { op: string; guild: string; card: string; result: string; reason: string; returned: number | null }[];
const inventory = (env: Env, guild: string) => env.raw.prepare("SELECT card_key AS card, copies FROM guild_inventory WHERE guild_id = ? ORDER BY card_key").all(guild).map((row) => ({ ...row }));
const news = async (env: Env, player: Player, operations?: string[]) => (await read(await post(env, player, "mine", "guild-mine", operations === undefined ? {} : { operations })))["donations"] as { results: Record<string, string>; refunds: { operation: string; guild: string; card: string }[] };
const countOf = (env: Env, id: string, key: string) => (JSON.parse((env.raw.prepare("SELECT state_json FROM ledger_state WHERE player_id = ?").get(id) as { state_json: string }).state_json) as { counts: Record<string, number> }).counts[key];

test("a member's donation is credited to the guild in the same upload, and the copy leaves the binder", async () => {
  const env = setup({ guilds: true });
  const { ann, id: guild } = await guildOf(env);
  const bob = await binder(env, "Bob");
  await enrol(env, "Knights of Light", bob, ann);
  bob.binder.add(bob.binder.donate(card, 1, guild, op(1)));
  assert.equal((await bob.binder.upload()).status, 200);
  assert.deepEqual(donations(env).map((row) => [row.op, row.guild, row.card, row.result, row.reason]), [[op(1), guild, card, "credited", ""]]);
  assert.deepEqual(inventory(env, guild), [{ card, copies: 1 }]);
  assert.equal(countOf(env, bob.id, card), 1);
  assert.deepEqual(await news(env, bob.player, [op(1)]), { results: { [op(1)]: "credited" }, refunds: [] });

  // A second donation, of the last copy and of another card, adds to the inventory.
  bob.binder.add(bob.binder.donate(card, 0, guild, op(2)), bob.binder.gain(other, 1), bob.binder.donate(other, 0, guild, op(3)));
  assert.equal((await bob.binder.upload()).status, 200);
  assert.deepEqual(inventory(env, guild), [{ card, copies: 2 }, { card: other, copies: 1 }]);
  assert.equal(countOf(env, bob.id, card), 0);

  // The guild's summary and the public ladder show it: points count each distinct card once.
  const summary = await read(await post(env, bob.player, "summary", "guild-summary"));
  const points = (rarity: string) => ({ common: 1, rare: 2, epic: 5, legendary: 10 })[rarity]! * 10;
  assert.deepEqual([summary["points"], summary["cards"], summary["rank"]], [points(catalog.cards[card]!.rarity) + points(catalog.cards[other]!.rarity), 2, 1]);
  assert.deepEqual(summary["inventory"], [{ card, copies: 2, donor: bob.binder.char }, { card: other, copies: 1, donor: bob.binder.char }]);
  const ladder = await read(await env.call("/v1/guilds/leaderboard"));
  assert.deepEqual((ladder["entries"] as { rank: number; name: string; cards: number; members: number }[]).map((entry) => [entry.rank, entry.name, entry.cards, entry.members]), [[1, "Knights of Light", 2, 2]]);
});

test("sending the same upload again, or an old one, never donates twice", async () => {
  const env = setup({ guilds: true });
  const { ann, id: guild } = await guildOf(env);
  const bob = await binder(env, "Bob");
  await enrol(env, "Knights of Light", bob, ann);
  bob.binder.add(bob.binder.donate(card, 1, guild, op(1)));
  const body = signedUpload(bob.player, bob.binder.events.slice(bob.binder.sent), { specVersion: 11, character: "Bob", realm: "Realm Name",
    snapshot: { counts: { [card]: 1 }, dust: 0, sets: {}, attempts: {}, titles: {} }, tapeIndex: 0, sentAt: env.clock.now });
  assert.equal((await env.call("/v1/ledger", { body })).status, 200);
  const again = await env.call("/v1/ledger", { body });
  assert.equal(again.status, 200);
  assert.equal(((await again.json()) as { duplicate: boolean }).duplicate, true);
  assert.deepEqual(inventory(env, guild), [{ card, copies: 1 }]);
  // Another account cannot reuse the operation id.
  const cyd = await binder(env, "Cyd");
  await enrol(env, "Knights of Light", cyd, ann);
  cyd.binder.add(cyd.binder.donate(card, 1, guild, op(1)));
  const reused = await cyd.binder.upload();
  assert.equal(reused.status, 422);
  assert.deepEqual(((await reused.json()) as { error: { code: string; detail: { rule: string } } }).error.detail.rule, "donate");
  assert.deepEqual(inventory(env, guild), [{ card, copies: 1 }]);
  assert.equal(countOf(env, cyd.id, card), 2); // nothing of Cyd's was stored
});

test("a donation from someone who is not a member is refused, and the copy comes back once", async () => {
  const env = setup({ guilds: true });
  const { id: guild } = await guildOf(env);
  const cyd = await binder(env, "Cyd");
  cyd.binder.add(cyd.binder.donate(card, 1, guild, op(1)));
  assert.equal((await cyd.binder.upload()).status, 200); // stored: the copy has left the binder, and waits to come back
  assert.deepEqual(donations(env).map((row) => [row.result, row.reason]), [["refunded", "not-member"]]);
  assert.deepEqual(inventory(env, guild), []);
  assert.equal(countOf(env, cyd.id, card), 1);
  assert.deepEqual(await news(env, cyd.player, [op(1)]), { results: { [op(1)]: "refunded" }, refunds: [{ operation: op(1), guild, card }] });

  // The binder writes the copy back; the server accepts that once.
  cyd.binder.add(cyd.binder.giveBack(card, 2, guild, op(1)));
  assert.equal((await cyd.binder.upload()).status, 200);
  assert.equal(countOf(env, cyd.id, card), 2);
  assert.deepEqual(await news(env, cyd.player, [op(1)]), { results: { [op(1)]: "returned" }, refunds: [] });
  assert.equal(donations(env)[0]!.returned, cyd.binder.events.length);
  cyd.binder.add(cyd.binder.giveBack(card, 3, guild, op(1)));
  assert.equal((await cyd.binder.upload()).status, 422); // the binder's own rules refuse a second return, and so would the server
});

test("a copy cannot be written back for a donation that was credited, or one the server never saw", async () => {
  const env = setup({ guilds: true });
  const { ann, id: guild } = await guildOf(env);
  const bob = await binder(env, "Bob");
  await enrol(env, "Knights of Light", bob, ann);
  bob.binder.add(bob.binder.donate(card, 1, guild, op(1)));
  assert.equal((await bob.binder.upload()).status, 200);
  bob.binder.add(bob.binder.giveBack(card, 2, guild, op(1)));
  const refused = await bob.binder.upload();
  assert.equal(refused.status, 422);
  assert.equal(((await refused.json()) as { error: { detail: { rule: string } } }).error.detail.rule, "donate");
  assert.equal(countOf(env, bob.id, card), 1);
  assert.deepEqual(inventory(env, guild), [{ card, copies: 1 }]);
  // A donateReturn for an operation that was donated in the binder but never reached the server is refused as well.
  const dee = await binder(env, "Dee");
  dee.binder.add(dee.binder.donate(card, 1, guild, op(7)), dee.binder.giveBack(card, 2, guild, op(7)));
  assert.equal((await dee.binder.upload()).status, 422);
});

test("a donation to another guild, by a removed member, or with Casual finds or unconfirmed copies is refused", async () => {
  const env = setup({ guilds: true });
  const { ann, id: guild } = await guildOf(env);
  const { id: second } = await guildOf(env, "Second Guild", "Zoe");
  const bob = await binder(env, "Bob");
  await enrol(env, "Knights of Light", bob, ann);
  bob.binder.add(bob.binder.donate(card, 1, second, op(1))); // a guild Bob is not in
  assert.equal((await bob.binder.upload()).status, 200);
  assert.deepEqual(donations(env).map((row) => [row.guild, row.result, row.reason]), [[second, "refunded", "not-member"]]);

  // Removed from the guild: later donations are refused, earlier ones stay.
  bob.binder.add(bob.binder.donate(card, 0, guild, op(2)));
  assert.equal((await bob.binder.upload()).status, 200);
  const roster = (await read(await post(env, ann.player, "roster", "guild-roster"))) as unknown as { members: { id: string; character: string }[] };
  await post(env, ann.player, "remove", "guild-remove", { member: roster.members.find((entry) => entry.character === bob.peer)!.id });
  bob.binder.add(bob.binder.gain(other, 1), bob.binder.donate(other, 0, guild, op(3)));
  assert.equal((await bob.binder.upload()).status, 200);
  assert.deepEqual(donations(env).map((row) => [row.op, row.result, row.reason]), [[op(1), "refunded", "not-member"], [op(2), "credited", ""], [op(3), "refunded", "not-member"]]);
  assert.deepEqual(inventory(env, guild), [{ card, copies: 1 }]);

  // Casual finds keep a binder off the ladder, so its copies cannot be given to a guild either.
  const cas = await binder(env, "Cas");
  await enrol(env, "Knights of Light", cas, ann);
  env.raw.prepare("UPDATE ledger_state SET casual_drops = 1 WHERE player_id = ?").run(cas.id);
  cas.binder.add(cas.binder.donate(card, 1, guild, op(4)));
  assert.equal((await cas.binder.upload()).status, 200);
  assert.deepEqual(donations(env).filter((row) => row.op === op(4)).map((row) => [row.result, row.reason]), [["refunded", "casual"]]);

  // A copy that came from a trade nobody confirmed is not trusted.
  const dee = await binder(env, "Dee");
  await enrol(env, "Knights of Light", dee, ann);
  env.raw.prepare("UPDATE trades SET state = 'unmatched' WHERE player_id = ? AND direction = 'in' AND card_key = ?").run(dee.id, card);
  dee.binder.add(dee.binder.donate(card, 1, guild, op(5)));
  assert.equal((await dee.binder.upload()).status, 200);
  assert.deepEqual(donations(env).filter((row) => row.op === op(5)).map((row) => [row.result, row.reason]), [["refunded", "untrusted"]]);
  assert.deepEqual(inventory(env, guild), [{ card, copies: 1 }]);
});

test("the upload rules around donations: spec 11, guilds switched on, a Ranked binder", async () => {
  const env = setup({ guilds: true });
  const { ann, id: guild } = await guildOf(env);
  const bob = await binder(env, "Bob");
  await enrol(env, "Knights of Light", bob, ann);
  // A companion that does not say spec 11 cannot upload a binder that has recorded mode/guild1.
  bob.binder.add(bob.binder.donate(card, 1, guild, op(1)));
  const old = await bob.binder.upload(10);
  assert.equal(old.status, 426);
  assert.equal(((await old.json()) as { error: { code: string } }).error.code, "client_too_old");
  assert.deepEqual(inventory(env, guild), []);
  assert.equal((await bob.binder.upload()).status, 200);

  // With guilds switched off the marker is harmless but a donation is refused whole.
  const off = setup();
  const cyd = await binder(off, "Cyd");
  assert.equal(countOf(off, cyd.id, card), 2);
  cyd.binder.add(cyd.binder.donate(card, 1, "0".repeat(26), op(1)));
  const closed = await cyd.binder.upload();
  assert.equal(closed.status, 422);
  assert.equal(((await closed.json()) as { error: { detail: { rule: string } } }).error.detail.rule, "guilds-closed");
  // And a binder that never recorded guild1 cannot donate at all.
  const dee = await binder(env, "Dee", { guild: false });
  dee.binder.add(dee.binder.donate(card, 1, guild, op(2)));
  const unmarked = await dee.binder.upload();
  assert.equal(unmarked.status, 422);
  assert.equal(((await unmarked.json()) as { error: { detail: { rule: string } } }).error.detail.rule, "donate");
});

test("the guild ladder ranks guilds by points, then cards, and the answers about donations are checked", async () => {
  const env = setup({ guilds: true });
  const first = await guildOf(env, "Knights of Light", "Ann");
  const second = await guildOf(env, "Second Guild", "Zoe");
  assert.deepEqual((await read(await env.call("/v1/guilds/leaderboard")))["entries"], []); // nothing donated yet
  const bob = await binder(env, "Bob");
  await enrol(env, "Knights of Light", bob, first.ann);
  const cyd = await binder(env, "Cyd");
  await enrol(env, "Second Guild", cyd, second.ann);
  // Cyd gives two cards, Bob one: the second guild leads.
  cyd.binder.add(cyd.binder.gain(other, 1), cyd.binder.donate(card, 1, second.id, op(1)), cyd.binder.donate(other, 0, second.id, op(2)));
  bob.binder.add(bob.binder.donate(card, 1, first.id, op(3)));
  assert.equal((await cyd.binder.upload()).status, 200);
  assert.equal((await bob.binder.upload()).status, 200);
  const entries = (await read(await env.call("/v1/guilds/leaderboard")))["entries"] as { rank: number; name: string; cards: number }[];
  const names = entries.map((entry) => entry.name);
  const pointsFor = (...keys: string[]) => keys.reduce((sum, key) => sum + ({ common: 1, rare: 2, epic: 5, legendary: 10 })[catalog.cards[key]!.rarity]!, 0);
  assert.equal(names[0], pointsFor(card, other) > pointsFor(card) ? "Second Guild" : "Knights of Light");
  assert.deepEqual(entries.map((entry) => entry.rank), [1, 2]);
  assert.equal(await code(await env.call("/v1/guilds/leaderboard?limit=0")) , undefined);
  // The operations a player asks about are validated, signed and limited.
  assert.equal(await code(await post(env, bob.player, "mine", "guild-mine", { operations: ["nope"] })), "bad_request");
  assert.equal(await code(await post(env, bob.player, "mine", "guild-mine", { operations: [op(1), op(1)] })), "bad_request");
  assert.equal(await code(await post(env, bob.player, "mine", "guild-mine", { operations: "x" })), "bad_request");
  assert.equal(await code(await post(env, bob.player, "mine", "guild-mine", { operations: Array.from({ length: 101 }, (_, n) => op(n + 10)) })), "bad_request");
  // One player cannot learn about another's donation.
  assert.deepEqual((await news(env, bob.player, [op(1), op(3)])).results, { [op(3)]: "credited" });
  // Someone outside a guild has no summary, and with guilds off none of this exists.
  assert.equal(await code(await post(env, newPlayer("Nobody"), "summary", "guild-summary")), "unknown_key");
  const outsider = await founder(env, "Out");
  assert.equal(await code(await post(env, outsider.player, "summary", "guild-summary")), "not_found");
  const off = setup();
  assert.equal(await code(await off.call("/v1/guilds/leaderboard")), "not_found");
  assert.equal(await code(await off.call("/v1/guilds/summary", { body: {} })), "not_found");
});

test("deleting a donor's account keeps the guild's cards; deleting the owner leaves the guild and what it holds", async () => {
  const env = setup({ guilds: true });
  const { ann, id: guild } = await guildOf(env);
  const bob = await binder(env, "Bob");
  await enrol(env, "Knights of Light", bob, ann);
  bob.binder.add(bob.binder.donate(card, 1, guild, op(1)));
  assert.equal((await bob.binder.upload()).status, 200);
  const named = await read(await post(env, ann.player, "summary", "guild-summary"));
  assert.deepEqual(named["inventory"], [{ card, copies: 1, donor: bob.binder.char }]);
  await env.store.deletePlayer(bob.id);
  assert.deepEqual(inventory(env, guild), [{ card, copies: 1 }]);
  assert.deepEqual(env.raw.prepare("SELECT donor_player_id AS donor FROM guild_donations").all().map((row) => ({ ...row })), [{ donor: null }]);
  assert.equal(env.raw.prepare("SELECT donor_character AS donor FROM guild_donations").get()!["donor"], "");
  const anonymous = await read(await post(env, ann.player, "summary", "guild-summary"));
  assert.deepEqual(anonymous["inventory"], [{ card, copies: 1 }]);
  await env.store.deletePlayer(ann.id);
  assert.deepEqual(inventory(env, guild), [{ card, copies: 1 }]);
  assert.equal(env.raw.prepare("SELECT COUNT(*) AS n FROM guilds WHERE id = ?").get(guild)!["n"], 1);
});
