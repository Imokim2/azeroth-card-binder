-- Additive: normal binder inventories, histories and tapes are unchanged.
CREATE TABLE seasons (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, starts_at INTEGER NOT NULL, ends_at INTEGER NOT NULL,
  cards_json TEXT NOT NULL, rewards_json TEXT NOT NULL, selection_json TEXT NOT NULL, created_at INTEGER NOT NULL
);
CREATE INDEX seasons_window ON seasons(starts_at, ends_at);
CREATE TABLE season_acquisitions (
  season_id TEXT NOT NULL REFERENCES seasons(id), player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  epoch INTEGER NOT NULL, seq INTEGER NOT NULL, card_key TEXT NOT NULL, zone TEXT NOT NULL, kind TEXT NOT NULL, received_at INTEGER NOT NULL,
  PRIMARY KEY(season_id, player_id, epoch, seq)
);
CREATE INDEX season_player_cards ON season_acquisitions(player_id, season_id, card_key);
CREATE TABLE season_completions (
  season_id TEXT NOT NULL REFERENCES seasons(id), player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  place INTEGER NOT NULL, completed_at INTEGER NOT NULL, titles_json TEXT NOT NULL, rewards_issued INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(season_id, player_id), UNIQUE(season_id, place)
);
CREATE TABLE season_grants (
  id TEXT PRIMARY KEY, season_id TEXT NOT NULL REFERENCES seasons(id),
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE, pack TEXT NOT NULL
);
CREATE INDEX season_player_grants ON season_grants(player_id);
CREATE TABLE season_redemptions (
  grant_id TEXT PRIMARY KEY REFERENCES season_grants(id) ON DELETE CASCADE,
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE, seq INTEGER NOT NULL
);
