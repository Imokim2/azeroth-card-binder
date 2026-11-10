// Reads the saved-data file the game writes for an add-on (WTF/Account/<name>/SavedVariables/<AddOn>.lua) WITHOUT
// running it. The file is Lua source made only of assignments to tables, strings, numbers and booleans:
//
//   AzerothCardBinderDB = {
//       ["counts"] = { ["npc:639"] = 1, },
//       ["ledger"] = { { ["seq"] = 1, }, -- [1]
//       },
//   }
//
// A player can edit that file, so it is treated as untrusted text: this is a small parser for exactly that
// subset, with limits on size and depth, and anything else is an error. Nothing is evaluated.

export type LuaValue = null | boolean | number | string | LuaValue[] | { [key: string]: LuaValue };

export class LuaSyntaxError extends Error {
  readonly line: number;
  constructor(message: string, line: number) {
    super(`${message} (line ${line})`);
    this.line = line;
  }
}

export const MAX_FILE_CHARACTERS = 50_000_000;
const MAX_DEPTH = 64;

const ESCAPES: Record<string, string> = { a: "\x07", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t", v: "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n" };

class Reader {
  readonly #text: string;
  #at = 0;
  #line = 1;
  constructor(text: string) {
    this.#text = text;
  }

  fail(message: string): never {
    throw new LuaSyntaxError(message, this.#line);
  }

  get done(): boolean {
    this.skip();
    return this.#at >= this.#text.length;
  }

  peek(offset = 0): string {
    return this.#text.charAt(this.#at + offset);
  }

  #advance(count = 1): void {
    for (let index = 0; index < count; index++) if (this.#text.charAt(this.#at + index) === "\n") this.#line++;
    this.#at += count;
  }

  // Skip spaces and comments (`-- to end of line` and `--[[ block ]]`).
  skip(): void {
    for (;;) {
      const c = this.peek();
      if (c === " " || c === "\t" || c === "\r" || c === "\n") {
        this.#advance();
      } else if (c === "-" && this.peek(1) === "-") {
        const block = /^--\[(=*)\[/.exec(this.#text.slice(this.#at, this.#at + 40));
        if (block) {
          const close = "]" + (block[1] ?? "") + "]";
          const end = this.#text.indexOf(close, this.#at + block[0].length);
          if (end < 0) this.fail("a comment is never closed");
          this.#advance(end + close.length - this.#at);
        } else {
          while (this.#at < this.#text.length && this.peek() !== "\n") this.#advance();
        }
      } else {
        return;
      }
    }
  }

  expect(character: string): void {
    this.skip();
    if (this.peek() !== character) this.fail(`expected "${character}"`);
    this.#advance();
  }

  accept(character: string): boolean {
    this.skip();
    if (this.peek() !== character) return false;
    this.#advance();
    return true;
  }

  name(): string | null {
    this.skip();
    const match = /^[A-Za-z_][A-Za-z0-9_]*/.exec(this.#text.slice(this.#at, this.#at + 200));
    if (!match) return null;
    this.#advance(match[0].length);
    return match[0];
  }

  // After a name: is the next thing `=` (and not `==`)? Used to tell `key = value` from a plain value.
  nextIsAssignment(): boolean {
    this.skip();
    return this.peek() === "=" && this.peek(1) !== "=";
  }

  number(): number | null {
    this.skip();
    const match = /^-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)/.exec(this.#text.slice(this.#at, this.#at + 400));
    if (!match) return null;
    const value = Number(match[0]);
    if (!Number.isFinite(value)) this.fail("a number is not finite");
    this.#advance(match[0].length);
    return value;
  }

  string(): string | null {
    this.skip();
    const quote = this.peek();
    if (quote === '"' || quote === "'") {
      this.#advance();
      let out = "";
      // A decimal escape above 127 is one byte of UTF-8 text: gather a run of them, then decode the run together.
      const bytes: number[] = [];
      const flush = () => {
        if (bytes.length > 0) out += new TextDecoder("utf-8").decode(Uint8Array.from(bytes));
        bytes.length = 0;
      };
      for (;;) {
        if (this.#at >= this.#text.length) this.fail("a string is never closed");
        const c = this.peek();
        if (c === quote) {
          this.#advance();
          flush();
          return out;
        }
        if (c === "\n") this.fail("a string runs past the end of its line");
        if (c !== "\\") {
          flush();
          out += c;
          this.#advance();
          continue;
        }
        const next = this.peek(1);
        const digits = /^\d{1,3}/.exec(this.#text.slice(this.#at + 1, this.#at + 4));
        if (digits) {
          const code = Number(digits[0]);
          if (code > 255) this.fail("a character code is out of range");
          if (code >= 128) {
            bytes.push(code);
          } else {
            flush();
            out += String.fromCharCode(code);
          }
          this.#advance(1 + digits[0].length);
        } else if (next in ESCAPES) {
          flush();
          out += ESCAPES[next];
          this.#advance(2);
        } else {
          this.fail(`unknown escape \\${next}`);
        }
      }
    }
    const long = /^\[(=*)\[/.exec(this.#text.slice(this.#at, this.#at + 40));
    if (long) {
      const close = "]" + (long[1] ?? "") + "]";
      const start = this.#at + long[0].length;
      const end = this.#text.indexOf(close, start);
      if (end < 0) this.fail("a string is never closed");
      const body = this.#text.slice(start, end);
      this.#advance(end + close.length - this.#at);
      return body.startsWith("\n") ? body.slice(1) : body;
    }
    return null;
  }
}

function readValue(reader: Reader, depth: number): LuaValue {
  if (depth > MAX_DEPTH) reader.fail("tables are nested too deeply");
  reader.skip();
  const c = reader.peek();
  if (c === "{") return readTable(reader, depth);
  const text = reader.string();
  if (text !== null) return text;
  const number = reader.number();
  if (number !== null) return number;
  const word = reader.name();
  if (word === "true") return true;
  if (word === "false") return false;
  if (word === "nil") return null;
  return reader.fail(word ? `unexpected "${word}"` : `unexpected "${c || "end of file"}"`);
}

function readTable(reader: Reader, depth: number): LuaValue {
  reader.expect("{");
  const named: Record<string, LuaValue> = {};
  const listed: LuaValue[] = [];
  let hasNamed = false;
  while (!reader.accept("}")) {
    reader.skip();
    if (reader.peek() === "[" && reader.peek(1) !== "[" && reader.peek(1) !== "=") {
      reader.expect("[");
      const key = readValue(reader, depth + 1);
      reader.expect("]");
      reader.expect("=");
      const value = readValue(reader, depth + 1);
      if (typeof key !== "string" && typeof key !== "number") reader.fail("a table key must be a string or a number");
      if (typeof key === "number" && Number.isInteger(key) && key === listed.length + 1 && !hasNamed) listed.push(value);
      else {
        hasNamed = true;
        named[String(key)] = value;
      }
    } else {
      const start = reader.name();
      if (start !== null && reader.nextIsAssignment()) {
        reader.expect("=");
        hasNamed = true;
        named[start] = readValue(reader, depth + 1);
      } else if (start !== null) {
        // A bare word is true, false or nil as a plain list item.
        const word = start === "true" ? true : start === "false" ? false : start === "nil" ? null : reader.fail(`unexpected "${start}"`);
        listed.push(word);
      } else {
        listed.push(readValue(reader, depth + 1));
      }
    }
    reader.skip();
    if (!reader.accept(",") && !reader.accept(";")) {
      reader.skip();
      if (reader.peek() !== "}") reader.fail('expected "," or "}"');
    }
  }
  if (!hasNamed) return listed;
  // A mix of list items and keys: keep the list items under their positions.
  listed.forEach((value, index) => { named[String(index + 1)] = value; });
  return named;
}

// Read every top-level `Name = value` assignment in the file.
export function parseSavedVariables(text: string): Record<string, LuaValue> {
  if (text.length > MAX_FILE_CHARACTERS) throw new LuaSyntaxError("the file is too large", 1);
  const reader = new Reader(text.replace(/^﻿/, ""));
  const result: Record<string, LuaValue> = {};
  while (!reader.done) {
    const name = reader.name();
    if (name === null) reader.fail("expected a variable name");
    reader.expect("=");
    result[name as string] = readValue(reader, 0);
  }
  return result;
}
