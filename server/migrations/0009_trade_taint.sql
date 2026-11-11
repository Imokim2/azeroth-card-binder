-- Tracing cards that came from Casual play through several trades (roadmap D5). Forward-only: this only adds.
-- trade_taint: the received trade halves that are not trusted because of where the card came from, worked out hourly from
-- all the trades together (src/taint.ts). It is derived data: the hourly job replaces it whole.
CREATE TABLE trade_taint (
  player_id  TEXT NOT NULL REFERENCES players (id),
  seq        INTEGER NOT NULL,
  PRIMARY KEY (player_id, seq)
);
