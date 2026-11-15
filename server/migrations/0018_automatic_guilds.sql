-- Finish requests made before automatic guild creation. Preserve guild IDs, names and all collection data.
-- A player who joined another guild in the meantime must not gain a second active membership.
INSERT INTO guild_members (id, guild_id, player_id, character, role, state, requested_at, decided_at)
SELECT 'owner-' || g.id, g.id, g.owner_player_id, g.owner_character, 'owner', 'active', g.requested_at, unixepoch()
FROM guilds g
WHERE g.status = 'pending' AND g.owner_player_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM guild_members m WHERE m.player_id = g.owner_player_id AND m.state IN ('pending', 'active'));

UPDATE guilds SET status = 'active', decided_at = unixepoch(), decided_by = 'automatic'
WHERE status = 'pending' AND EXISTS (
  SELECT 1 FROM guild_members m WHERE m.guild_id = guilds.id AND m.player_id = guilds.owner_player_id AND m.role = 'owner' AND m.state = 'active'
);
