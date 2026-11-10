-- Ranked random numbers (the tape). Forward-only: this only adds. The entries themselves are not stored: each one is
-- derived from a server secret, the player and its position, so a tape of any length costs one row here. The row
-- records what range was issued and its commitment (the SHA-256 of the entries joined by line feeds), for audits.

CREATE TABLE tapes (
  player_id   TEXT NOT NULL REFERENCES players (id),
  start_idx   INTEGER NOT NULL,
  end_idx     INTEGER NOT NULL,
  commitment  TEXT NOT NULL,
  issued_at   INTEGER NOT NULL,
  PRIMARY KEY (player_id, start_idx)
);

-- The next tape entry the add-on said it will use (from the last upload), and how many "bad luck guarantee" drops
-- each card has had so far (a JSON object, derived data that a rebuild recomputes).
ALTER TABLE ledger_state ADD COLUMN tape_next INTEGER NOT NULL DEFAULT 1;
ALTER TABLE ledger_state ADD COLUMN pity_json TEXT NOT NULL DEFAULT '{}';
