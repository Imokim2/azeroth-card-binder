-- Guild binders, step two: members (docs/proposals/GUILD-BINDERS-DESIGN.md). Forward-only: this only adds.
-- A player applies to an active guild from a character they have played; the guild's owner approves or refuses; a member can leave and
-- the owner can remove one. The unique index gives one live row (pending or active) per player, so an account belongs to one guild, or has
-- one application open, at a time, whatever characters it has. The owner of a guild is its first member, added when the guild is approved
-- (and here, for any guild approved before this migration). Past donations, once there are any, do not depend on these rows.
CREATE TABLE guild_members (
  id           TEXT PRIMARY KEY,
  guild_id     TEXT NOT NULL REFERENCES guilds (id),
  player_id    TEXT NOT NULL REFERENCES players (id) ON DELETE CASCADE,
  character    TEXT NOT NULL,
  role         TEXT NOT NULL CHECK (role IN ('owner', 'member')),
  state        TEXT NOT NULL CHECK (state IN ('pending', 'active', 'refused', 'removed', 'left')),
  requested_at INTEGER NOT NULL,
  decided_at   INTEGER
);
CREATE UNIQUE INDEX guild_members_live ON guild_members (player_id) WHERE state IN ('pending', 'active');
CREATE INDEX guild_members_by_guild ON guild_members (guild_id, state);
CREATE INDEX guild_members_by_player ON guild_members (player_id, requested_at);

INSERT INTO guild_members (id, guild_id, player_id, character, role, state, requested_at, decided_at)
  SELECT 'owner-' || id, id, owner_player_id, owner_character, 'owner', 'active', COALESCE(decided_at, requested_at), decided_at
  FROM guilds WHERE status = 'active' AND owner_player_id IS NOT NULL;
