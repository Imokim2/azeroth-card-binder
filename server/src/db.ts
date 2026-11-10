// The smallest database interface the SQL store needs, and an adapter for Cloudflare D1. Tests use an adapter for
// SQLite (test/sqliteDb.ts). Nothing else in the server knows which database is behind it.

export type Statement = { sql: string; params?: unknown[] };

export interface Db {
  all<T>(sql: string, params?: unknown[]): Promise<T[]>;
  // Run all statements as one transaction: every one is applied or none is. Throws if any of them fails.
  batch(statements: Statement[]): Promise<void>;
}

// The parts of Cloudflare's D1 binding that are used, declared here so the server needs no Cloudflare types.
export interface D1Statement {
  bind(...values: unknown[]): D1Statement;
  all(): Promise<{ results?: unknown[] }>;
}
export interface D1Like {
  prepare(sql: string): D1Statement;
  batch(statements: D1Statement[]): Promise<unknown[]>;
}

export function fromD1(d1: D1Like): Db {
  const prepared = (statement: Statement) => d1.prepare(statement.sql).bind(...(statement.params ?? []));
  return {
    async all<T>(sql: string, params: unknown[] = []): Promise<T[]> {
      const result = await prepared({ sql, params }).all();
      return (result.results ?? []) as T[];
    },
    async batch(statements: Statement[]): Promise<void> {
      if (statements.length === 0) return;
      await d1.batch(statements.map(prepared));
    },
  };
}
