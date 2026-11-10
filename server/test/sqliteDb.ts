// A Db (src/db.ts) on SQLite, for tests: D1 is SQLite underneath, and the real migrations are applied to it.
import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import type { SQLInputValue } from "node:sqlite";
import type { Db, Statement } from "../src/db.ts";

const migrations = new URL("../migrations/", import.meta.url);

export function openTestDb(): { db: Db; raw: DatabaseSync } {
  const raw = new DatabaseSync(":memory:");
  raw.exec("PRAGMA foreign_keys = ON");
  for (const name of readdirSync(migrations).filter((file) => file.endsWith(".sql")).sort()) {
    raw.exec(readFileSync(new URL(name, migrations), "utf8"));
  }
  const bind = (params: unknown[] = []) => params as SQLInputValue[];
  const db: Db = {
    async all<T>(sql: string, params?: unknown[]): Promise<T[]> {
      return raw.prepare(sql).all(...bind(params)) as T[];
    },
    async batch(statements: Statement[]): Promise<void> {
      raw.exec("BEGIN");
      try {
        for (const statement of statements) raw.prepare(statement.sql).run(...bind(statement.params));
        raw.exec("COMMIT");
      } catch (error) {
        raw.exec("ROLLBACK");
        throw error;
      }
    },
  };
  return { db, raw };
}
