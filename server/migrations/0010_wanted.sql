-- The wanted board: the cards public players are looking for, so others can see what they want. Forward-only: this only adds.
-- Replaced whole each time a player uploads their list; only public players' rows are ever shown, and a player who
-- goes private has theirs removed. Not part of the ledger and not checked by it: it is only a list of wishes.
CREATE TABLE wanted (
  player_id  TEXT NOT NULL REFERENCES players (id),
  card_key   TEXT NOT NULL,
  added_at   INTEGER NOT NULL,
  PRIMARY KEY (player_id, card_key)
);
CREATE INDEX wanted_by_card ON wanted (card_key);
