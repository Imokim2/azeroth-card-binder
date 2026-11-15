// Guild binders, step one: asking for a guild and a person who runs the service approving it (docs/proposals/GUILD-BINDERS-DESIGN.md).
// A guild is a name on a realm for one side, owned by the player who asked. Nobody can prove they lead a guild in the game, so the first
// approval is a human one; once a guild exists its id never changes, whoever owns it and whatever it is called.
// This step has no members and no donations, and it never reads or writes a ledger: the only thing it learns from a binder is whether the
// character asking is Ranked and which side it declared (mode/side), which becomes the guild's side.
import type { Db } from "./db.ts";
import { ApiError } from "./errors.ts";
import { newId } from "../../packages/shared/src/crypto.ts";
import { peerName } from "./names.ts";
import type { Catalog } from "./shared.ts";
import { baseCardKey } from "./shared.ts";
import type { LedgerEvent } from "./ledger.ts";
import { POINTS } from "./score.ts";

export type GuildSide = "alliance" | "horde";
export type GuildStatus = "pending" | "active" | "refused";
export const GUILD_STATES = ["pending", "active", "refused", "all"] as const;
export const GUILD_NAME_MIN = 2;
export const GUILD_NAME_MAX = 24; // what the game allows
export const MAX_REFUSED_PER_WEEK = 3; // by one player: asking again and again for names that get refused is not a request
const WEEK = 7 * 86_400;

type Row = {
  id: string; name: string; name_key: string; realm: string; realm_key: string; side: GuildSide; owner_player_id: string | null;
  owner_character: string; status: GuildStatus; requested_at: number; decided_at: number | null; decided_by: string; note: string;
};
const COLUMNS = "id, name, name_key, realm, realm_key, side, owner_player_id, owner_character, status, requested_at, decided_at, decided_by, note";

// What a player sees of their own request or guild.
export type GuildView = { id: string; name: string; realm: string; side: GuildSide; status: GuildStatus; character: string; requestedAt: number; decidedAt: number | null; note: string };
// What a reviewer sees: the same, and whose it is and who decided.
export type GuildReview = GuildView & { ownerId: string | null; decidedBy: string };

const view = (row: Row): GuildView => ({
  id: row.id, name: row.name, realm: row.realm, side: row.side, status: row.status, character: row.owner_character,
  requestedAt: row.requested_at, decidedAt: row.decided_at, note: row.note,
});
const review = (row: Row): GuildReview => ({ ...view(row), ownerId: row.owner_player_id, decidedBy: row.decided_by });

// Names and realms are compared without case, spaces, apostrophes or dashes (the way peerName compares a realm).
export const guildKey = (text: string): string => text.toLowerCase().replace(/[\s'’-]/g, "");

// A guild name as typed, checked and tidied: letters, with single spaces, apostrophes and dashes between them.
export function parseGuildName(value: unknown): string {
  if (typeof value !== "string" || /[\u0000-\u001f\u007f]/.test(value)) throw new ApiError("bad_request", { field: "name" }); // no control characters, not even a tab or line break
  const name = value.normalize("NFC").trim().replace(/\s+/g, " ");
  const ok = name.length >= GUILD_NAME_MIN && name.length <= GUILD_NAME_MAX && /^\p{L}[\p{L}\p{M}' -]*\p{L}$/u.test(name) && !/['’ -]{2,}/.test(name)
    && guildKey(name).length >= GUILD_NAME_MIN;
  if (!ok) throw new ApiError("bad_request", { field: "name" });
  return name;
}

// A character as the add-on names it to other players and the companion lists it: name-realmname, nothing that could be markup or a separator.
export function parseCharacter(value: unknown): string {
  if (typeof value !== "string" || value.length > 80 || !/^[^\s|,<>&"'`]{1,40}-[^\s|,<>&"'`]{1,40}$/.test(value)) throw new ApiError("bad_request", { field: "character" });
  return peerName(value);
}

// The side a character may start a guild for, from what its binder has recorded. The binder must be Ranked (so the character stands on
// a verified collection) and the character must have declared a side (ledger spec 10); otherwise there is nothing to take the side from.
export function guildSideOf(state: unknown, peer: string): { side: GuildSide } | { reason: "no-binder" | "not-ranked" | "no-faction" | "no-side" } {
  if (!state || typeof state !== "object") return { reason: "no-binder" };
  const saved = state as { mode?: unknown; faction?: unknown; sides?: unknown };
  if (saved.mode !== "ranked" && saved.mode !== "ranked2") return { reason: "not-ranked" };
  if (saved.faction !== 1) return { reason: "no-faction" };
  const sides = saved.sides && typeof saved.sides === "object" ? Object.entries(saved.sides as Record<string, unknown>) : [];
  const found = sides.find(([character]) => peerName(character) === peer)?.[1];
  return found === "alliance" || found === "horde" ? { side: found } : { reason: "no-side" };
}

type MemberRow = { id: string; character: string; role: "owner" | "member"; state: string; requested_at: number; decided_at: number | null };
type MemberJoin = MemberRow & { guild_id: string; guild_name: string; guild_realm: string; guild_side: GuildSide };
const MEMBER_ROW = "SELECT id, character, role, state, requested_at, decided_at FROM guild_members";
const MEMBER_SELECT = `SELECT m.id, m.character, m.role, m.state, m.requested_at, m.decided_at, g.id AS guild_id, g.name AS guild_name, g.realm AS guild_realm, g.side AS guild_side
  FROM guild_members m JOIN guilds g ON g.id = m.guild_id`;
export type RosterEntry = { id: string; character: string; role: "owner" | "member"; state: string; requestedAt: number; decidedAt: number | null };
const entry = (row: MemberRow): RosterEntry => ({ id: row.id, character: row.character, role: row.role, state: row.state, requestedAt: row.requested_at, decidedAt: row.decided_at });
// A player's own place in a guild. `state` is pending (waiting for the owner), active, refused, removed or left.
export type MembershipView = {
  id: string; role: "owner" | "member"; state: string; character: string; requestedAt: number; decidedAt: number | null;
  guild: { id: string; name: string; realm: string; side: GuildSide; members: number };
};

// How a donation was settled when its upload was stored, and why when it was refused.
export type DonationDecision = { operation: string; guildId: string; key: string; seq: number; t: number; result: "credited" | "refunded"; reason: string };
export type DonationReason = "" | "not-member" | "casual" | "untrusted";

// A guild's points, in tenths like a personal score: each distinct card it holds is worth its rarity's points (the copies and the editions of a
// card count once), and nothing else adds to it. Guilds earn nothing from finished pages, shinies, seasons or rewards.
export function guildPoints(catalog: Catalog, held: { card_key: string }[]): { tenths: number; cards: number } {
  const seen = new Set<string>();
  let tenths = 0;
  for (const { card_key } of held) {
    const card = catalog.cards[card_key];
    const base = card ? baseCardKey(catalog, card_key) : card_key;
    if (!card || seen.has(base)) continue;
    seen.add(base);
    tenths += (POINTS[catalog.cards[base]?.rarity ?? card.rarity] ?? 0) * 10;
  }
  return { tenths, cards: seen.size };
}

export type GuildStanding = { guildId: string; name: string; realm: string; side: GuildSide; tenths: number; cards: number; members: number };

export class SqlGuilds {
  readonly #db: Db;
  readonly #catalog: Catalog;
  constructor(db: Db, catalog: Catalog) {
    this.#db = db;
    this.#catalog = catalog;
  }

  // ---- Donations ----

  // Settle the donations in an upload, before it is stored. A donation is credited when the donor is an active member of the guild it names, has no
  // Casual finds (which the server cannot check, and which keep a player off the ladder) and holds no copy of that card that came from a trade nobody
  // confirmed. Otherwise it is refused, and the copy is issued back. `excluded` is those unconfirmed copies, by card; `casualDrops` the donor's Casual finds
  // so far including this upload. An operation id that is already recorded can only be a collision, since the ledger uses each once: the upload is refused.
  async decideDonations(playerId: string, events: LedgerEvent[], context: { excluded: Record<string, number>; casualDrops: number }, now: number): Promise<DonationDecision[]> {
    const donations = events.filter((event) => event.kind === "donate");
    if (!donations.length) return [];
    const member = (await this.#db.all<{ guild_id: string }>(
      `SELECT m.guild_id FROM guild_members m JOIN guilds g ON g.id = m.guild_id WHERE m.player_id = ? AND m.state = 'active' AND g.status = 'active'`, [playerId]))[0]?.guild_id ?? null;
    const decisions: DonationDecision[] = [];
    for (const event of donations) {
      if ((await this.#db.all("SELECT 1 FROM guild_donations WHERE operation_id = ?", [event.trade])).length) throw new ApiError("rule_broken", { rule: "donate", index: event.seq });
      const base = baseCardKey(this.#catalog, event.key);
      let reason: DonationReason = "";
      if (member === null || member !== event.partner) reason = "not-member";
      else if (context.casualDrops > 0) reason = "casual";
      else if ((context.excluded[event.key] ?? 0) > 0 || (context.excluded[base] ?? 0) > 0) reason = "untrusted";
      decisions.push({ operation: event.trade, guildId: event.partner, key: event.key, seq: event.seq, t: event.t, result: reason === "" ? "credited" : "refunded", reason });
    }
    return decisions;
  }

  // Whether every donateReturn in an upload is for a donation of this player that the server refused and has not yet given back.
  async checkReturns(playerId: string, events: LedgerEvent[]): Promise<boolean> {
    for (const event of events) if (event.kind === "donateReturn") {
      const rows = await this.#db.all(
        "SELECT 1 FROM guild_donations WHERE operation_id = ? AND donor_player_id = ? AND guild_id = ? AND card_key = ? AND result = 'refunded' AND returned_seq IS NULL",
        [event.trade, playerId, event.partner, event.key]);
      if (!rows.length) return false;
    }
    return true;
  }

  // What became of the donations a player's add-on is waiting to hear about (their operation ids), and every refused donation still to be
  // written back as a donateReturn. An operation not listed is not known to the server yet: its upload has not arrived.
  async donationNews(playerId: string, operations: string[]): Promise<{ results: Record<string, "credited" | "refunded" | "returned">; refunds: { operation: string; guild: string; card: string }[] }> {
    const results: Record<string, "credited" | "refunded" | "returned"> = {};
    if (operations.length) {
      const marks = operations.map(() => "?").join(", ");
      const rows = await this.#db.all<{ operation_id: string; result: "credited" | "refunded"; returned_seq: number | null }>(
        `SELECT operation_id, result, returned_seq FROM guild_donations WHERE donor_player_id = ? AND operation_id IN (${marks})`, [playerId, ...operations]);
      for (const row of rows) results[row.operation_id] = row.returned_seq !== null ? "returned" : row.result;
    }
    const refunds = await this.#db.all<{ operation_id: string; guild_id: string; card_key: string }>(
      "SELECT operation_id, guild_id, card_key FROM guild_donations WHERE donor_player_id = ? AND result = 'refunded' AND returned_seq IS NULL ORDER BY decided_at, operation_id LIMIT 100", [playerId]);
    return { results, refunds: refunds.map((row) => ({ operation: row.operation_id, guild: row.guild_id, card: row.card_key })) };
  }

  // What the guild a player belongs to holds, with its points and place. Any active member may ask.
  async summary(playerId: string): Promise<{ guild: MembershipView["guild"]; points: number; cards: number; rank: number | null; inventory: { card: string; copies: number }[] }> {
    const membership = await this.membership(playerId);
    if (!membership || membership.state !== "active") throw new ApiError("not_found");
    const inventory = await this.#db.all<{ card_key: string; copies: number }>("SELECT card_key, copies FROM guild_inventory WHERE guild_id = ? ORDER BY card_key", [membership.guild.id]);
    const { tenths, cards } = guildPoints(this.#catalog, inventory);
    const standings = await this.standings(500);
    const place = standings.findIndex((standing) => standing.guildId === membership.guild.id);
    return { guild: membership.guild, points: tenths, cards, rank: place < 0 ? null : place + 1, inventory: inventory.map((row) => ({ card: row.card_key, copies: row.copies })) };
  }

  // The guild ladder: guilds that hold at least one card, by points, then cards, then name.
  async standings(limit: number): Promise<GuildStanding[]> {
    const held = await this.#db.all<{ guild_id: string; card_key: string }>("SELECT guild_id, card_key FROM guild_inventory");
    const byGuild = new Map<string, { card_key: string }[]>();
    for (const row of held) byGuild.set(row.guild_id, [...(byGuild.get(row.guild_id) ?? []), row]);
    if (!byGuild.size) return [];
    const guilds = await this.#db.all<Row & { members: number }>(
      `SELECT ${COLUMNS.split(", ").map((column) => "g." + column).join(", ")}, (SELECT COUNT(*) FROM guild_members m WHERE m.guild_id = g.id AND m.state = 'active') AS members FROM guilds g WHERE g.status = 'active'`);
    return guilds.filter((guild) => byGuild.has(guild.id)).map((guild) => {
      const { tenths, cards } = guildPoints(this.#catalog, byGuild.get(guild.id)!);
      return { guildId: guild.id, name: guild.name, realm: guild.realm, side: guild.side, tenths, cards, members: guild.members };
    }).sort((a, b) => b.tenths - a.tenths || b.cards - a.cards || a.name.localeCompare(b.name) || a.guildId.localeCompare(b.guildId)).slice(0, limit);
  }

  // Ask for a guild from one of the player's own characters. The guild is pending until someone approves it.
  async request(playerId: string, input: { character: string; name: string }, now: number): Promise<GuildView> {
    const { own, side } = await this.#eligible(playerId, input.character);
    const refused = (await this.#db.all<{ n: number }>("SELECT COUNT(*) AS n FROM guilds WHERE owner_player_id = ? AND status = 'refused' AND requested_at > ?", [playerId, now - WEEK]))[0]?.n ?? 0;
    if (refused >= MAX_REFUSED_PER_WEEK) throw new ApiError("rate_limited", undefined, 86_400);
    if (await this.#hasLiveGuild(playerId)) throw new ApiError("guild_taken", { reason: "already-have-one" });
    const nameKey = guildKey(input.name), realmKey = guildKey(own.realm);
    const held = await this.#db.all("SELECT 1 FROM guilds WHERE realm_key = ? AND name_key = ? AND status IN ('pending', 'active')", [realmKey, nameKey]);
    if (held.length) throw new ApiError("guild_taken", { reason: "name" });
    const id = newId(now * 1000);
    try {
      await this.#db.batch([{
        sql: `INSERT INTO guilds (${COLUMNS}) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NULL, '', '')`,
        params: [id, input.name, nameKey, own.realm, realmKey, side, playerId, input.character, now],
      }]);
    } catch {
      // Two requests for the same name, or two from one player, at once: the unique indexes let one through.
      throw new ApiError("guild_taken", { reason: "name" });
    }
    return view((await this.#row(id))!);
  }

  // The player's own requests and guilds, newest first.
  async mine(playerId: string): Promise<GuildView[]> {
    const rows = await this.#db.all<Row>(`SELECT ${COLUMNS} FROM guilds WHERE owner_player_id = ? ORDER BY requested_at DESC, id DESC LIMIT 10`, [playerId]);
    return rows.map(view);
  }

  // For the people who review: guilds in a state, oldest request first.
  async list(state: (typeof GUILD_STATES)[number], limit: number): Promise<GuildReview[]> {
    const rows = await this.#db.all<Row>(
      `SELECT ${COLUMNS} FROM guilds ${state === "all" ? "" : "WHERE status = ?"} ORDER BY requested_at, id LIMIT ?`, state === "all" ? [limit] : [state, limit]);
    return rows.map(review);
  }

  // Approve or refuse a pending guild. Returns the decided guild, or null when there is no such guild. A guild that has already been
  // decided is not decided again (guild_decided), so two reviewers cannot overturn each other without noticing.
  async decide(id: string, decision: "approve" | "refuse", note: string, actor: string, now: number): Promise<GuildReview | null> {
    const row = await this.#row(id);
    if (!row) return null;
    if (row.status !== "pending") throw new ApiError("guild_decided", { status: row.status });
    const status: GuildStatus = decision === "approve" ? "active" : "refused";
    try {
      await this.#db.batch([
        { sql: "UPDATE guilds SET status = ?, decided_at = ?, decided_by = ?, note = ? WHERE id = ? AND status = 'pending'", params: [status, now, actor, note, id] },
        // The owner is the guild's first member. If they have joined another guild since asking, the unique index refuses this and nothing is approved.
        ...(decision === "approve" && row.owner_player_id
          ? [{ sql: "INSERT INTO guild_members (id, guild_id, player_id, character, role, state, requested_at, decided_at) VALUES (?, ?, ?, ?, 'owner', 'active', ?, ?)",
              params: [newId(now * 1000), id, row.owner_player_id, row.owner_character, row.requested_at, now] }]
          : []),
      ]);
    } catch {
      throw new ApiError("guild_taken", { reason: "name" }); // the index refused it: the owner or the name is held by another guild
    }
    const after = (await this.#row(id))!;
    if (after.status !== status || after.decided_by !== actor || after.decided_at !== now) throw new ApiError("guild_decided", { status: after.status });
    return review(after);
  }

  // ---- Members ----

  // The player's own place in a guild: the live row if they have one, otherwise the newest (so a refusal or a removal can be shown).
  async membership(playerId: string): Promise<MembershipView | null> {
    const rows = await this.#db.all<MemberJoin>(
      `${MEMBER_SELECT} WHERE m.player_id = ? ORDER BY (m.state IN ('pending', 'active')) DESC, m.requested_at DESC, m.id DESC LIMIT 1`, [playerId]);
    return rows[0] ? await this.#membershipView(rows[0]) : null;
  }

  // Apply to an active guild, by name, from one of the player's own characters on the guild's realm that declared the guild's side.
  async join(playerId: string, input: { character: string; name: string }, now: number): Promise<MembershipView> {
    const { own, side } = await this.#eligible(playerId, input.character);
    const guild = (await this.#db.all<Row>(`SELECT ${COLUMNS} FROM guilds WHERE realm_key = ? AND name_key = ? AND status = 'active'`, [guildKey(own.realm), guildKey(input.name)]))[0];
    if (!guild) throw new ApiError("not_found", { reason: "no-such-guild" });
    if (guild.side !== side) throw new ApiError("guild_ineligible", { reason: "other-side" });
    const refused = (await this.#db.all<{ n: number }>("SELECT COUNT(*) AS n FROM guild_members WHERE player_id = ? AND state = 'refused' AND requested_at > ?", [playerId, now - WEEK]))[0]?.n ?? 0;
    if (refused >= MAX_REFUSED_PER_WEEK) throw new ApiError("rate_limited", undefined, 86_400);
    if (await this.#hasLiveGuild(playerId)) throw new ApiError("guild_taken", { reason: "already-have-one" });
    const id = newId(now * 1000);
    try {
      await this.#db.batch([{
        sql: "INSERT INTO guild_members (id, guild_id, player_id, character, role, state, requested_at, decided_at) VALUES (?, ?, ?, ?, 'member', 'pending', ?, NULL)",
        params: [id, guild.id, playerId, input.character, now],
      }]);
    } catch {
      throw new ApiError("guild_taken", { reason: "already-have-one" }); // two applications at once: the unique index lets one through
    }
    return (await this.membership(playerId))!;
  }

  // The members and waiting applications of the guild this player owns. Only its owner may ask.
  async roster(playerId: string): Promise<{ guild: GuildView; members: RosterEntry[] }> {
    const guild = await this.#owned(playerId);
    const rows = await this.#db.all<MemberRow>(
      "SELECT id, character, role, state, requested_at, decided_at FROM guild_members WHERE guild_id = ? AND state IN ('pending', 'active') ORDER BY (state = 'active') DESC, requested_at, id", [guild.id]);
    return { guild: view(guild), members: rows.map(entry) };
  }

  // The owner approves or refuses a waiting application.
  async decideMember(ownerId: string, memberId: string, decision: "approve" | "refuse", now: number): Promise<RosterEntry> {
    const guild = await this.#owned(ownerId);
    const row = (await this.#db.all<MemberRow>(`${MEMBER_ROW} WHERE id = ? AND guild_id = ?`, [memberId, guild.id]))[0];
    if (!row) throw new ApiError("not_found");
    if (row.state !== "pending") throw new ApiError("guild_decided", { status: row.state });
    const state = decision === "approve" ? "active" : "refused";
    try {
      await this.#db.batch([{ sql: "UPDATE guild_members SET state = ?, decided_at = ? WHERE id = ? AND state = 'pending'", params: [state, now, memberId] }]);
    } catch {
      throw new ApiError("guild_taken", { reason: "already-have-one" }); // the applicant joined another guild first
    }
    const after = (await this.#db.all<MemberRow>(`${MEMBER_ROW} WHERE id = ?`, [memberId]))[0]!;
    if (after.state !== state) throw new ApiError("guild_decided", { status: after.state });
    return entry(after);
  }

  // A member leaves, or withdraws a waiting application. The owner cannot leave: an owner is replaced by a person who runs the service.
  async leave(playerId: string, now: number): Promise<void> {
    const row = (await this.#db.all<{ id: string; role: string }>("SELECT id, role FROM guild_members WHERE player_id = ? AND state IN ('pending', 'active')", [playerId]))[0];
    if (!row) throw new ApiError("not_found");
    if (row.role === "owner") throw new ApiError("bad_request", { field: "role", reason: "owner" });
    await this.#db.batch([{ sql: "UPDATE guild_members SET state = 'left', decided_at = ? WHERE id = ? AND state IN ('pending', 'active')", params: [now, row.id] }]);
  }

  // The owner removes an active member. Past donations stay in the guild.
  async remove(ownerId: string, memberId: string, now: number): Promise<void> {
    const guild = await this.#owned(ownerId);
    const row = (await this.#db.all<MemberRow>(`${MEMBER_ROW} WHERE id = ? AND guild_id = ?`, [memberId, guild.id]))[0];
    if (!row || row.state !== "active") throw new ApiError("not_found");
    if (row.role === "owner") throw new ApiError("bad_request", { field: "member", reason: "owner" });
    await this.#db.batch([{ sql: "UPDATE guild_members SET state = 'removed', decided_at = ? WHERE id = ? AND state = 'active'", params: [now, memberId] }]);
  }

  // The player's character, as the server knows it, and the side its Ranked binder declared; or the reason it cannot act for a guild.
  async #eligible(playerId: string, character: string): Promise<{ own: { name: string; realm: string }; side: GuildSide }> {
    const characters = await this.#db.all<{ name: string; realm: string }>("SELECT name, realm FROM characters WHERE player_id = ?", [playerId]);
    const own = characters.find((row) => peerName(row.name, row.realm) === character);
    if (!own) throw new ApiError("bad_request", { field: "character" }); // only a character this player has played
    const stored = (await this.#db.all<{ state_json: string }>("SELECT state_json FROM ledger_state WHERE player_id = ?", [playerId]))[0];
    const decided = guildSideOf(stored ? (JSON.parse(stored.state_json) as unknown) : null, character);
    if ("reason" in decided) throw new ApiError("guild_ineligible", { reason: decided.reason });
    return { own, side: decided.side };
  }

  // Whether the player already has a guild: one they asked for and have not been refused, or a membership or application.
  async #hasLiveGuild(playerId: string): Promise<boolean> {
    const owned = await this.#db.all("SELECT 1 FROM guilds WHERE owner_player_id = ? AND status IN ('pending', 'active')", [playerId]);
    const member = await this.#db.all("SELECT 1 FROM guild_members WHERE player_id = ? AND state IN ('pending', 'active')", [playerId]);
    return owned.length > 0 || member.length > 0;
  }

  async #owned(playerId: string): Promise<Row> {
    const guild = (await this.#db.all<Row>(`SELECT ${COLUMNS.split(", ").map((column) => "g." + column).join(", ")} FROM guilds g JOIN guild_members m ON m.guild_id = g.id
      WHERE m.player_id = ? AND m.role = 'owner' AND m.state = 'active' AND g.status = 'active'`, [playerId]))[0];
    if (!guild) throw new ApiError("not_found"); // not the owner of a guild: there is nothing here for them
    return guild;
  }

  async #membershipView(row: MemberJoin): Promise<MembershipView> {
    const members = (await this.#db.all<{ n: number }>("SELECT COUNT(*) AS n FROM guild_members WHERE guild_id = ? AND state = 'active'", [row.guild_id]))[0]?.n ?? 0;
    return {
      id: row.id, role: row.role, state: row.state, character: row.character, requestedAt: row.requested_at, decidedAt: row.decided_at,
      guild: { id: row.guild_id, name: row.guild_name, realm: row.guild_realm, side: row.guild_side, members },
    };
  }

  async #row(id: string): Promise<Row | null> {
    return (await this.#db.all<Row>(`SELECT ${COLUMNS} FROM guilds WHERE id = ?`, [id]))[0] ?? null;
  }
}
