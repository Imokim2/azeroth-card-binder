-- Guild binders, step one: asking for a guild and an admin approving it (docs/proposals/GUILD-BINDERS-DESIGN.md). Forward-only: this only adds.
-- A guild is a name on a realm for one side. A player asks for one from a character they have played, and a person who runs the
-- service approves or refuses it; the guild gets a permanent id, so a rename or a change of owner never creates another binder.
-- Nothing here touches a ledger or a player's binder, and there are no donations or members yet.
-- Names are compared by name_key and realm_key (lower case, without spaces, apostrophes or dashes, the way peerName does for characters),
-- and only a pending or active guild holds its name, so a refused request frees it. owner_player_id is emptied, not deleted, when the
-- owner deletes their account: a guild that has been approved stays, and an admin names a new owner.
CREATE TABLE guilds (
  id               TEXT PRIMARY KEY,
  name             TEXT NOT NULL,
  name_key         TEXT NOT NULL,
  realm            TEXT NOT NULL,
  realm_key        TEXT NOT NULL,
  side             TEXT NOT NULL CHECK (side IN ('alliance', 'horde')),
  owner_player_id  TEXT REFERENCES players (id) ON DELETE SET NULL,
  owner_character  TEXT NOT NULL,
  status           TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'refused')),
  requested_at     INTEGER NOT NULL,
  decided_at       INTEGER,
  decided_by       TEXT NOT NULL DEFAULT '',
  note             TEXT NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX guilds_live_name ON guilds (realm_key, name_key) WHERE status IN ('pending', 'active');
CREATE UNIQUE INDEX guilds_live_owner ON guilds (owner_player_id) WHERE status IN ('pending', 'active');
CREATE INDEX guilds_by_status ON guilds (status, requested_at);
CREATE INDEX guilds_by_owner ON guilds (owner_player_id, requested_at);
