-- Keep every published definition: old offline uploads and rebuilds must replay at their original rules.
CREATE TABLE IF NOT EXISTS bonus_events (
  id TEXT PRIMARY KEY,
  starts_at INTEGER NOT NULL,
  ends_at INTEGER NOT NULL,
  definition_json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS bonus_events_window ON bonus_events(ends_at, starts_at);
