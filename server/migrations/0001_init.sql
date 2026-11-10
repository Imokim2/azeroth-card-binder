-- World of Warcards database, version 1. Forward-only (see docs/runbooks and the roadmap, B13).
-- Every table is keyed by player_id and every id is a random ULID, so players can be split across databases later.
-- Only batches (the source of truth) and players/keys hold facts. ledger_state, drops and scores are derived from
-- the batches and can be rebuilt from them.

CREATE TABLE players (
  id          TEXT PRIMARY KEY,
  discord_id  TEXT UNIQUE,
  created_at  INTEGER NOT NULL,
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'banned')),
  visibility  TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'public'))
);

CREATE TABLE keys (
  public_key  TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL REFERENCES players (id),
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at  INTEGER NOT NULL
);
CREATE INDEX keys_by_player ON keys (player_id);

CREATE TABLE characters (
  player_id   TEXT NOT NULL REFERENCES players (id),
  name        TEXT NOT NULL,
  realm       TEXT NOT NULL,
  first_seen  INTEGER NOT NULL,
  last_seen   INTEGER NOT NULL,
  PRIMARY KEY (player_id, name, realm)
);

-- One row per accepted upload: the events, compressed. The primary key makes two racing uploads for the same
-- position impossible: the second one fails and is told to retry.
CREATE TABLE batches (
  player_id    TEXT NOT NULL REFERENCES players (id),
  first_seq    INTEGER NOT NULL,
  last_seq     INTEGER NOT NULL,
  last_hash    TEXT NOT NULL,
  events_gzip  BLOB NOT NULL,
  received_at  INTEGER NOT NULL,
  PRIMARY KEY (player_id, first_seq)
);

CREATE TABLE drops (
  player_id  TEXT NOT NULL REFERENCES players (id),
  seq        INTEGER NOT NULL,
  card_key   TEXT NOT NULL,
  t          INTEGER NOT NULL,
  shiny      INTEGER NOT NULL,
  tape_idx   INTEGER NOT NULL,
  PRIMARY KEY (player_id, seq)
);

-- Where each player's chain stands, and what the rules need to carry on from there.
CREATE TABLE ledger_state (
  player_id   TEXT PRIMARY KEY REFERENCES players (id),
  head_seq    INTEGER NOT NULL,
  head_hash   TEXT NOT NULL,
  state_json  TEXT NOT NULL,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE scores (
  player_id      TEXT PRIMARY KEY REFERENCES players (id),
  display_name   TEXT NOT NULL,
  score          INTEGER NOT NULL,
  unique_cards   INTEGER NOT NULL,
  sets_done      INTEGER NOT NULL,
  attempts       INTEGER NOT NULL,
  rules_version  INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX scores_by_score ON scores (score DESC, updated_at ASC);

CREATE TABLE flags (
  id          TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL REFERENCES players (id),
  kind        TEXT NOT NULL,
  state       TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'cleared', 'confirmed')),
  notes       TEXT NOT NULL DEFAULT '',
  created_at  INTEGER NOT NULL
);
CREATE INDEX flags_by_player ON flags (player_id);
