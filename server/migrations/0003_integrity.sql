-- Integrity checks (luck score, attempt rate). Forward-only: this only adds. Drop counts per card are derived data
-- (a rebuild recomputes them from the stored batches).
ALTER TABLE ledger_state ADD COLUMN drops_json TEXT NOT NULL DEFAULT '{}';
