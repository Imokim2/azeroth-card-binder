// Guild binders, step one: asking for a guild and a person who runs the service approving it (docs/proposals/GUILD-BINDERS-DESIGN.md).
// A guild is a name on a realm for one side, owned by the player who asked. Nobody can prove they lead a guild in the game, so the first
// approval is a human one; once a guild exists its id never changes, whoever owns it and whatever it is called.
// This step has no members and no donations, and it never reads or writes a ledger: the only thing it learns from a binder is whether the
// character asking is Ranked and which side it declared (mode/side), which becomes the guild's side.
import type { Db } from "./db.ts";
import { ApiError } from "./errors.ts";
import { newId } from "../../packages/shared/src/crypto.ts";
import { peerName } from "./names.ts";

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

export class SqlGuilds {
  readonly #db: Db;
  constructor(db: Db) {
    this.#db = db;
  }

  // Ask for a guild from one of the player's own characters. The guild is pending until someone approves it.
  async request(playerId: string, input: { character: string; name: string }, now: number): Promise<GuildView> {
    const characters = await this.#db.all<{ name: string; realm: string }>("SELECT name, realm FROM characters WHERE player_id = ?", [playerId]);
    const own = characters.find((row) => peerName(row.name, row.realm) === input.character);
    if (!own) throw new ApiError("bad_request", { field: "character" }); // only a character this player has played
    const stored = (await this.#db.all<{ state_json: string }>("SELECT state_json FROM ledger_state WHERE player_id = ?", [playerId]))[0];
    const decided = guildSideOf(stored ? (JSON.parse(stored.state_json) as unknown) : null, input.character);
    if ("reason" in decided) throw new ApiError("guild_ineligible", { reason: decided.reason });
    const refused = (await this.#db.all<{ n: number }>("SELECT COUNT(*) AS n FROM guilds WHERE owner_player_id = ? AND status = 'refused' AND requested_at > ?", [playerId, now - WEEK]))[0]?.n ?? 0;
    if (refused >= MAX_REFUSED_PER_WEEK) throw new ApiError("rate_limited", undefined, 86_400);
    const mine = await this.#db.all<{ n: number }>("SELECT COUNT(*) AS n FROM guilds WHERE owner_player_id = ? AND status IN ('pending', 'active')", [playerId]);
    if ((mine[0]?.n ?? 0) > 0) throw new ApiError("guild_taken", { reason: "already-have-one" });
    const nameKey = guildKey(input.name), realmKey = guildKey(own.realm);
    const held = await this.#db.all("SELECT 1 FROM guilds WHERE realm_key = ? AND name_key = ? AND status IN ('pending', 'active')", [realmKey, nameKey]);
    if (held.length) throw new ApiError("guild_taken", { reason: "name" });
    const id = newId(now * 1000);
    try {
      await this.#db.batch([{
        sql: `INSERT INTO guilds (${COLUMNS}) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NULL, '', '')`,
        params: [id, input.name, nameKey, own.realm, realmKey, decided.side, playerId, input.character, now],
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
      await this.#db.batch([{
        sql: "UPDATE guilds SET status = ?, decided_at = ?, decided_by = ?, note = ? WHERE id = ? AND status = 'pending'",
        params: [status, now, actor, note, id],
      }]);
    } catch {
      throw new ApiError("guild_taken", { reason: "name" }); // the index refused it: the owner or the name is held by another guild
    }
    const after = (await this.#row(id))!;
    if (after.status !== status || after.decided_by !== actor || after.decided_at !== now) throw new ApiError("guild_decided", { status: after.status });
    return review(after);
  }

  async #row(id: string): Promise<Row | null> {
    return (await this.#db.all<Row>(`SELECT ${COLUMNS} FROM guilds WHERE id = ?`, [id]))[0] ?? null;
  }
}
