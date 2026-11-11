// Writes AzerothCardBinder/Data/Sync.lua: the one file the app writes for the add-on to read (roadmap 2.4).
// Everything written is checked first (whole numbers and lowercase hex only), so no value from the network or from
// a saved file can ever put code into a file the game will run.

export type Ack = { seq: number; hash: string };
export type Standing = { rank: number; name: string; score: number; cards: number; sets: number };
export type SyncData = {
  syncedAt: number; acks: Ack[]; tape?: { start: number; entries: string[] };
  // Roadmap C3, C4 and C6: what the add-on's leaderboard tab shows. Scores are in tenths of a point.
  leaderboard?: Standing[]; you?: Omit<Standing, "name"> | null; verified?: string[];
  firsts?: { setCode: string; title: string; by: string; at: number }[];
  // The wanted board: what public players are looking for (roadmap: wanted tab).
  wanted?: { name: string; characters: string[]; cards: string[] }[];
  // Tokens of the reports the server has taken, so the add-on can forget them.
  reportsDone?: string[];
};

const isHash = (value: string) => /^[0-9a-f]{32}$/.test(value);

// A Lua string with nothing in it that can end the string or run: every byte except letters, digits and a few safe
// marks is written as a three-digit decimal escape, so a name from the network can only ever be text.
function luaString(value: string, field: string): string {
  if (typeof value !== "string" || value.length > 80) throw new Error(`${field} is not a short text`);
  let out = "";
  for (const byte of new TextEncoder().encode(value)) {
    const char = String.fromCharCode(byte);
    out += /[A-Za-z0-9 _.-]/.test(char) ? char : "\\" + String(byte).padStart(3, "0");
  }
  return '"' + out + '"';
}
const whole = (value: number, field: string): number => {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error(`${field} must be a whole number`);
  return value;
};

export function syncFileText(data: SyncData): string {
  if (!Number.isSafeInteger(data.syncedAt) || data.syncedAt < 0) throw new Error("syncedAt must be a whole number of seconds");
  const rows = data.acks.map((ack) => {
    if (!Number.isSafeInteger(ack.seq) || ack.seq < 1 || !isHash(ack.hash)) throw new Error("an acknowledgement is not valid");
    return `        { seq = ${ack.seq}, hash = "${ack.hash}" },`;
  });
  const tapeLines: string[] = [];
  if (data.tape) {
    if (!Number.isSafeInteger(data.tape.start) || data.tape.start < 1) throw new Error("the tape must start at 1 or later");
    for (const entry of data.tape.entries) if (!/^[0-9a-f]{16}$/.test(entry)) throw new Error("a tape entry is not 16 hex characters");
    tapeLines.push("    tape = {", `        start = ${data.tape.start},`, "        entries = {");
    for (let at = 0; at < data.tape.entries.length; at += 4) {
      tapeLines.push("            " + data.tape.entries.slice(at, at + 4).map((entry) => `"${entry}",`).join(" "));
    }
    tapeLines.push("        },", "    },");
  }
  const standing = (entry: Standing, index: number) =>
    `        { rank = ${whole(entry.rank, "rank")}, name = ${luaString(entry.name, "name")}, score = ${whole(entry.score, "score")}, cards = ${whole(entry.cards, "cards")}, sets = ${whole(entry.sets, "sets")} }, -- ${index + 1}`;
  const extra: string[] = [];
  if (data.leaderboard) {
    if (data.leaderboard.length > 100) throw new Error("the leaderboard has at most 100 places");
    extra.push("    leaderboard = {", ...data.leaderboard.map(standing), "    },");
  }
  if (data.you) extra.push(`    you = { rank = ${whole(data.you.rank, "rank")}, score = ${whole(data.you.score, "score")}, cards = ${whole(data.you.cards, "cards")}, sets = ${whole(data.you.sets, "sets")} },`);
  if (data.verified) {
    if (data.verified.length > 600) throw new Error("too many verified names");
    extra.push("    verified = {", ...data.verified.map((name) => `        [${luaString(name, "verified name")}] = true,`), "    },");
  }
  if (data.firsts) {
    if (data.firsts.length > 300) throw new Error("too many firsts");
    extra.push("    firsts = {", ...data.firsts.map((row) => `        { set = ${luaString(row.setCode, "set")}, title = ${luaString(row.title, "title")}, by = ${luaString(row.by, "name")}, at = ${whole(row.at, "at")} },`), "    },");
  }
  if (data.wanted) {
    if (data.wanted.length > 100) throw new Error("too many wanted lists");
    extra.push("    wanted = {");
    for (const entry of data.wanted) {
      if (entry.cards.length > 60 || entry.characters.length > 20) throw new Error("a wanted list is too long");
      for (const card of entry.cards) if (!/^(?:npc|node):\d{1,9}$/.test(card)) throw new Error("a wanted card is not a card key");
      extra.push(`        { name = ${luaString(entry.name, "name")}, characters = { ${entry.characters.map((name) => luaString(name, "character")).join(", ")} }, cards = { ${entry.cards.map((card) => `"${card}"`).join(", ")} } },`);
    }
    extra.push("    },");
  }
  if (data.reportsDone) {
    if (data.reportsDone.length > 200) throw new Error("too many report tokens");
    for (const token of data.reportsDone) if (!/^[0-9a-z]{6,40}$/.test(token)) throw new Error("a report token is not a token");
    extra.push("    reportsDone = {", ...data.reportsDone.map((token) => `        ["${token}"] = true,`), "    },");
  }
  return [
    "local _, ACB = ...",
    "",
    "-- Written by the World of Warcards companion app. Do not edit; the game only reads it.",
    "ACB.sync = {",
    "    syncVersion = 1,",
    `    syncedAt = ${data.syncedAt},`,
    "    acks = {",
    ...rows,
    "    },",
    ...tapeLines,
    ...extra,
    "}",
    "",
  ].join("\n");
}
