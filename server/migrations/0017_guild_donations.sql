-- Guild binders, step three: donations (docs/proposals/GUILD-BINDERS-DESIGN.md). Forward-only: this only adds.
-- A donation is a `donate` event in a player's ledger (spec 11). The server settles it in the same transaction that stores the upload: it is
-- credited to the guild, or refused and the copy is issued back (the player's ledger then writes a `donateReturn` for the same operation,
-- recorded here as returned_seq). operation_id is the player's own random id for the donation and is used once, so a repeat of an upload,
-- an old saved file or a retry can never donate twice. A donation outlives its donor: donor_player_id is emptied, not deleted, when the
-- account goes, because the guild still holds the card.
CREATE TABLE guild_donations (
  operation_id    TEXT PRIMARY KEY,
  guild_id        TEXT NOT NULL REFERENCES guilds (id),
  donor_player_id TEXT REFERENCES players (id) ON DELETE SET NULL,
  card_key        TEXT NOT NULL,
  seq             INTEGER NOT NULL,
  t               INTEGER NOT NULL,
  result          TEXT NOT NULL CHECK (result IN ('credited', 'refunded')),
  reason          TEXT NOT NULL DEFAULT '',
  decided_at      INTEGER NOT NULL,
  returned_seq    INTEGER
);
CREATE INDEX guild_donations_by_guild ON guild_donations (guild_id, result);
CREATE INDEX guild_donations_by_donor ON guild_donations (donor_player_id, decided_at);

-- What each guild holds: one row per card (or edition), the copies donated. Derived from the credited rows above, so it can be rebuilt.
CREATE TABLE guild_inventory (
  guild_id TEXT NOT NULL REFERENCES guilds (id),
  card_key TEXT NOT NULL,
  copies   INTEGER NOT NULL CHECK (copies > 0),
  PRIMARY KEY (guild_id, card_key)
);
