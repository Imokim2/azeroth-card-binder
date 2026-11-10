-- Trade matching (roadmap C5) and the firsts feed (C6). Forward-only: this only adds.
--
-- trades: one row per tradeIn or tradeOut event. A trade is matched when the other player's upload holds the opposite
-- half: the same trade id and card, naming each other. A row still open after seven days is marked unmatched.
-- char is the player's own character in the form partners use ("name-realmname"), so the two halves can be compared.
CREATE TABLE trades (
  player_id    TEXT NOT NULL REFERENCES players (id),
  seq          INTEGER NOT NULL,
  trade_id     TEXT NOT NULL,
  direction    TEXT NOT NULL CHECK (direction IN ('in', 'out')),
  card_key     TEXT NOT NULL,
  char         TEXT NOT NULL,
  partner      TEXT NOT NULL,
  t            INTEGER NOT NULL,
  received_at  INTEGER NOT NULL,
  state        TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'matched', 'unmatched')),
  PRIMARY KEY (player_id, seq)
);
CREATE INDEX trades_by_trade ON trades (trade_id);
CREATE INDEX trades_open ON trades (state, received_at);

-- set_completions: every `set` event, so the first eligible player for a set can be found even when the first to
-- finish is later held back or banned. Ordered by when the server received it, not by the player's own clock.
CREATE TABLE set_completions (
  set_code     TEXT NOT NULL,
  player_id    TEXT NOT NULL REFERENCES players (id),
  t            INTEGER NOT NULL,
  received_at  INTEGER NOT NULL,
  PRIMARY KEY (set_code, player_id)
);
CREATE INDEX set_completions_by_time ON set_completions (set_code, received_at);
