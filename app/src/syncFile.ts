// Writes AzerothCardBinder/Data/Sync.lua: the one file the app writes for the add-on to read (roadmap 2.4).
// Everything written is checked first (whole numbers and lowercase hex only), so no value from the network or from
// a saved file can ever put code into a file the game will run.

export type Ack = { seq: number; hash: string };
export type SyncData = { syncedAt: number; acks: Ack[] };

const isHash = (value: string) => /^[0-9a-f]{32}$/.test(value);

export function syncFileText(data: SyncData): string {
  if (!Number.isSafeInteger(data.syncedAt) || data.syncedAt < 0) throw new Error("syncedAt must be a whole number of seconds");
  const rows = data.acks.map((ack) => {
    if (!Number.isSafeInteger(ack.seq) || ack.seq < 1 || !isHash(ack.hash)) throw new Error("an acknowledgement is not valid");
    return `        { seq = ${ack.seq}, hash = "${ack.hash}" },`;
  });
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
    "}",
    "",
  ].join("\n");
}
