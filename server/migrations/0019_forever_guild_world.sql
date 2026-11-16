-- Forever has surnames, not character realms. Keep IDs, memberships and donations intact.
-- Resolve conflicting legacy names before applying; the unique index refuses any unresolved collision.
CREATE UNIQUE INDEX guilds_forever_live_name ON guilds (name_key) WHERE status IN ('pending', 'active');
UPDATE guilds SET realm = 'Forever', realm_key = 'forever';
