// Guild binder data, kept bounded and declarative before it reaches executable Sync.lua (docs/proposals/GUILD-BINDERS-DESIGN.md). The server's answers are
// checked field by field: nothing the network sends is passed on unless it has exactly the expected shape, and every string is length-limited.
export type GuildSide = "alliance" | "horde";
export type GuildInfo = { id: string; name: string; realm: string; side: GuildSide; members: number };
export type MembershipState = "pending" | "active" | "refused" | "removed" | "left";
export type GuildMembership = { id: string; role: "owner" | "member"; state: MembershipState; character: string; requestedAt: number; decidedAt: number; guild: GuildInfo };
// A guild the player asked to start: waiting for a reviewer, active, or refused (with the reviewer's note).
export type GuildRequest = { id: string; name: string; realm: string; side: GuildSide; status: "pending" | "active" | "refused"; character: string; requestedAt: number; decidedAt: number; note: string };
export type Donations = { results: Record<string, "credited" | "refunded" | "returned">; refunds: { operation: string; guild: string; card: string }[] };
export type GuildSummary = { guildId: string; points: number; cards: number; rank?: number; inventory: { card: string; copies: number }[] };
export type GuildData = { at: number; binders: string[]; membership: GuildMembership | null; requests: GuildRequest[]; donations: Donations; summary?: GuildSummary };
export type RosterEntry = { id: string; character: string; role: "owner" | "member"; state: "pending" | "active"; requestedAt: number };

const row = (v: unknown): Record<string, unknown> => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
const whole = (v: unknown): number => { if (!Number.isSafeInteger(v) || Number(v) < 0) throw new Error("invalid guild number"); return Number(v); };
const orZero = (v: unknown): number => (v === null || v === undefined ? 0 : whole(v));
const text = (v: unknown, max = 80): string => { if (typeof v !== "string" || v.length > max || /[\u0000-\u001f]/.test(v)) throw new Error("invalid guild text"); return v; };
const side = (v: unknown): GuildSide => { if (v !== "alliance" && v !== "horde") throw new Error("invalid guild side"); return v; };
const ulid = (v: unknown): string => { const s = text(v, 26); if (!/^[0-9A-Z]{26}$/.test(s)) throw new Error("invalid guild id"); return s; };
const operation = (v: unknown): string => { const s = text(v, 32); if (!/^[0-9a-f]{32}$/.test(s)) throw new Error("invalid operation id"); return s; };
const card = (v: unknown): string => { const s = text(v); if (!/^(npc|node|edition):\d{1,9}$/.test(s)) throw new Error("invalid guild card"); return s; };
const list = (v: unknown, max: number): unknown[] => { if (!Array.isArray(v) || v.length > max) throw new Error("invalid guild list"); return v; };
const token = (v: unknown): string => { const s = text(v, 32); if (!/^[0-9a-f]{32}$/.test(s)) throw new Error("invalid binder id"); return s; };
const memberId = (v: unknown): string => { const s = text(v, 32); if (!/^(owner-)?[0-9A-Z]{26}$/.test(s)) throw new Error("invalid member id"); return s; };

const guildInfo = (v: unknown): GuildInfo => {
  const g = row(v);
  return { id: ulid(g["id"]), name: text(g["name"], 24), realm: text(g["realm"], 40), side: side(g["side"]), members: g["members"] === undefined ? 1 : whole(g["members"]) };
};

export function parseMembership(v: unknown): GuildMembership | null {
  if (v === null || v === undefined) return null;
  const m = row(v);
  const state = m["state"];
  if (!["pending", "active", "refused", "removed", "left"].includes(state as string)) throw new Error("invalid membership state");
  if (m["role"] !== "owner" && m["role"] !== "member") throw new Error("invalid membership role");
  return { id: memberId(m["id"]), role: m["role"], state: state as MembershipState, character: text(m["character"], 80), requestedAt: whole(m["requestedAt"]), decidedAt: orZero(m["decidedAt"]), guild: guildInfo(m["guild"]) };
}

export function parseRequests(v: unknown): GuildRequest[] {
  return list(v ?? [], 10).map((item) => {
    const r = row(item);
    if (!["pending", "active", "refused"].includes(r["status"] as string)) throw new Error("invalid guild status");
    return { id: ulid(r["id"]), name: text(r["name"], 24), realm: text(r["realm"], 40), side: side(r["side"]), status: r["status"] as GuildRequest["status"],
      character: text(r["character"], 80), requestedAt: whole(r["requestedAt"]), decidedAt: orZero(r["decidedAt"]), note: text(r["note"] ?? "", 200) };
  });
}

export function parseDonations(v: unknown): Donations {
  const d = row(v);
  const results: Donations["results"] = {};
  for (const [id, result] of Object.entries(row(d["results"]))) {
    if (result !== "credited" && result !== "refunded" && result !== "returned") throw new Error("invalid donation result");
    results[operation(id)] = result;
  }
  if (Object.keys(results).length > 100) throw new Error("too many donation results");
  return { results, refunds: list(d["refunds"] ?? [], 100).map((item) => { const r = row(item); return { operation: operation(r["operation"]), guild: ulid(r["guild"]), card: card(r["card"]) }; }) };
}

// What the server said about the player's guild, ready for the sync file. `binders` are the binders this answer is paired with.
export function parseGuildData(input: unknown, binders: string[], at: number): GuildData {
  const data = row(input);
  const membership = parseMembership(data["membership"]);
  let summary: GuildSummary | undefined;
  if (data["summary"] !== undefined) {
    const saved = row(data["summary"]);
    if (membership?.state !== "active" || ulid(saved["guildId"]) !== membership.guild.id) throw new Error("guild summary does not match membership");
    summary = parseGuildSummary({ ...saved, guild: membership.guild }, membership.guild.id);
  }
  return { at: whole(at), binders: list(binders, 100).map(token), membership, requests: parseRequests(data["guilds"]), donations: parseDonations(data["donations"]), ...(summary ? { summary } : {}) };
}

export function parseRoster(input: unknown): { guild: { id: string; name: string; realm: string; side: GuildSide }; members: RosterEntry[] } {
  const data = row(input);
  const g = guildInfo({ ...row(data["guild"]), members: 1 });
  return {
    guild: { id: g.id, name: g.name, realm: g.realm, side: g.side },
    members: list(data["members"], 500).map((item) => {
      const m = row(item);
      if (m["role"] !== "owner" && m["role"] !== "member") throw new Error("invalid roster role");
      if (m["state"] !== "pending" && m["state"] !== "active") throw new Error("invalid roster state");
      return { id: memberId(m["id"]), character: text(m["character"], 80), role: m["role"], state: m["state"], requestedAt: whole(m["requestedAt"]) };
    }),
  };
}

// Lua for a value that has already been checked: strings are written byte by byte so they can only ever be text, numbers must be whole.
export function luaLiteral(v: unknown, luaString: (value: string, field: string) => string): string {
  if (typeof v === "string") return luaString(v, "guild text");
  if (typeof v === "number") { if (!Number.isSafeInteger(v) || v < 0) throw new Error("invalid guild number"); return String(v); }
  if (Array.isArray(v)) return "{ " + v.map((item) => luaLiteral(item, luaString)).join(", ") + " }";
  if (v && typeof v === "object") return "{ " + Object.entries(v).map(([k, value]) => "[" + luaString(k, "guild field") + "] = " + luaLiteral(value, luaString)).join(", ") + " }";
  throw new Error("invalid guild value");
}

// The part of the guild data the add-on reads: who the player is in which guild, and what became of their donations.
export const forAddon = (data: GuildData): { at: number; binders: string[]; membership?: GuildMembership; donations: Donations; summary?: GuildSummary } => ({
  at: data.at, binders: data.binders, ...(data.membership ? { membership: data.membership } : {}), donations: data.donations,
  ...(data.summary ? { summary: data.summary } : {}),
});

export function parseGuildSummary(input: unknown, expectedGuild: string): GuildSummary {
  const data = row(input), guild = guildInfo(data["guild"]);
  if (guild.id !== expectedGuild) throw new Error("guild summary does not match membership");
  const seen = new Set<string>();
  const inventory = list(data["inventory"], 10000).map(item => {
    const entry = row(item), key = card(entry["card"]), copies = whole(entry["copies"]);
    if (copies < 1 || seen.has(key)) throw new Error("invalid guild inventory");
    seen.add(key);
    return { card: key, copies };
  });
  return { guildId: guild.id, points: whole(data["points"]), cards: whole(data["cards"]), inventory,
    ...(data["rank"] == null ? {} : { rank: whole(data["rank"]) }) };
}
