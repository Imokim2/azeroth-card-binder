-- Reports: one player telling us about another (a suspected cheat, a trade that went wrong). Forward-only: this only adds.
-- A report is a note for a person to read, not a verdict: it opens a review flag once several different players have
-- reported the same player, and changes nothing else. The target is kept by character name because that is all the
-- reporting player can see; target_id is filled in when that name belongs to a known player.
CREATE TABLE reports (
  id          TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL REFERENCES players (id),
  token       TEXT NOT NULL,
  target_name TEXT NOT NULL,
  target_id   TEXT REFERENCES players (id),
  reason      TEXT NOT NULL,
  note        TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE UNIQUE INDEX reports_token ON reports (reporter_id, token);
CREATE INDEX reports_by_target ON reports (target_id, created_at);
CREATE INDEX reports_by_reporter ON reports (reporter_id, created_at);
