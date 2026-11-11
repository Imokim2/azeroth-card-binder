// Turning the add-on's saved-data file into what the app needs: the ledger events not yet uploaded and the snapshot.
// The app does not repair or judge anything here: a damaged file is reported, and the server is the one that checks.
import { parseSavedVariables } from "./luaTable.ts";
import type { LuaValue } from "./luaTable.ts";

export const SAVED_VARIABLE = "AzerothCardBinderDB";

export type BinderEvent = {
  seq: number; t: number; kind: string; key: string; count: number; dust: number; shiny: number; tape: number;
  partner: string; trade: string; char: string; prev: string; h: string;
};

export type Binder = {
  schema: number;
  mode: string;
  head: { seq: number; hash: string };
  tapeNext: number; // the next roll-tape position the add-on will use
  events: BinderEvent[];
  snapshot: { counts: Record<string, number>; attempts: Record<string, number>; dust: number; sets: Record<string, boolean>; titles: Record<string, boolean> };
  character: { name: string; realm: string } | null;
  // The cards the player marked as wanted, as card keys, sorted, at most 60 (what the server's wanted board takes).
  wanted: string[];
};

export class BinderFileError extends Error {}

const isRecord = (value: LuaValue | undefined): value is { [key: string]: LuaValue } =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const asList = (value: LuaValue | undefined): LuaValue[] => (Array.isArray(value) ? value : isRecord(value) && Object.keys(value).length === 0 ? [] : []);
const whole = (value: LuaValue | undefined): value is number => typeof value === "number" && Number.isSafeInteger(value);

function numberMap(value: LuaValue | undefined, minimum: number): Record<string, number> {
  const out: Record<string, number> = {};
  if (!isRecord(value)) return out;
  for (const [key, count] of Object.entries(value)) if (whole(count) && count >= minimum) out[key] = count;
  return out;
}

function flagMap(value: LuaValue | undefined): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  if (!isRecord(value)) return out;
  for (const [key, flag] of Object.entries(value)) if (flag === true) out[key] = true;
  return out;
}

function toEvent(value: LuaValue, position: number): BinderEvent {
  if (!isRecord(value)) throw new BinderFileError(`ledger entry ${position} is not an event`);
  const text = (name: string): string => {
    const field = value[name];
    if (typeof field !== "string") throw new BinderFileError(`ledger entry ${position} has no "${name}"`);
    return field;
  };
  const number = (name: string): number => {
    const field = value[name];
    if (!whole(field)) throw new BinderFileError(`ledger entry ${position} has a bad "${name}"`);
    return field;
  };
  return {
    seq: number("seq"), t: number("t"), kind: text("kind"), key: text("key"), count: number("count"), dust: number("dust"),
    shiny: number("shiny"), tape: number("tape"), partner: text("partner"), trade: text("trade"), char: text("char"),
    prev: text("prev"), h: text("h"),
  };
}

const CARD_KEY = /^(?:npc|node):\d{1,9}$/;
function wantedKeys(value: LuaValue | undefined): string[] {
  if (!isRecord(value)) return [];
  return Object.entries(value).filter(([key, flag]) => flag === true && CARD_KEY.test(key)).map(([key]) => key).sort().slice(0, 60);
}

// "Name-Realm" as the add-on writes it. A character name never contains a hyphen; a realm may.
export function splitCharacter(char: string): { name: string; realm: string } | null {
  const at = char.indexOf("-");
  if (at < 1 || at === char.length - 1) return null;
  return { name: char.slice(0, at), realm: char.slice(at + 1) };
}

export function readBinder(fileText: string): Binder {
  const variables = parseSavedVariables(fileText);
  const db = variables[SAVED_VARIABLE];
  if (!isRecord(db)) throw new BinderFileError(`${SAVED_VARIABLE} is missing from the file`);
  const schema = db["schema"];
  if (!whole(schema)) throw new BinderFileError("the saved data predates the ledger (schema 2); log in once with the new add-on first");
  const events = asList(db["ledger"]).map((entry, index) => toEvent(entry, index + 1));
  const head = isRecord(db["head"]) ? db["head"] : {};
  const headSeq = head["seq"];
  const headHash = head["hash"];
  const last = events[events.length - 1];
  return {
    schema,
    mode: typeof db["mode"] === "string" ? db["mode"] : "casual",
    head: { seq: whole(headSeq) ? headSeq : 0, hash: typeof headHash === "string" ? headHash : "0".repeat(32) },
    tapeNext: isRecord(db["tape"]) && whole(db["tape"]["next"]) && db["tape"]["next"] >= 1 ? db["tape"]["next"] : 1,
    events,
    snapshot: {
      counts: numberMap(db["counts"], 1), attempts: numberMap(db["attempts"], 1),
      dust: whole(db["dust"]) ? db["dust"] : 0, sets: flagMap(db["sets"]), titles: flagMap(db["titles"]),
    },
    character: last ? splitCharacter(last.char) : null,
    wanted: wantedKeys(db["wanted"]),
  };
}
