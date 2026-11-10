// Writes AzerothCardBinder/Data/Sync.lua: the one file the app writes for the add-on to read (roadmap 2.4).
// Everything written is checked first (whole numbers and lowercase hex only), so no value from the network or from
// a saved file can ever put code into a file the game will run.

export type Ack = { seq: number; hash: string };
export type SyncData = { syncedAt: number; acks: Ack[]; tape?: { start: number; entries: string[] } };

const isHash = (value: string) => /^[0-9a-f]{32}$/.test(value);

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
    "}",
    "",
  ].join("\n");
}
