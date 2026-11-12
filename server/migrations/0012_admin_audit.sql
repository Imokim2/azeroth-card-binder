-- A record of what the people who run the service did in the admin panel: who, what, to whom, and when. Forward-only: this only adds.
-- It holds no Discord ids, keys or names, only the acting reviewer (their Cloudflare Access email, or "token"), the kind of
-- action, the player id it was done to and a short note, so that it can stay when a player's own data is deleted.
CREATE TABLE admin_audit (
  id      TEXT PRIMARY KEY,
  at      INTEGER NOT NULL,
  actor   TEXT NOT NULL,
  action  TEXT NOT NULL,
  target  TEXT NOT NULL DEFAULT '',
  detail  TEXT NOT NULL DEFAULT ''
);
CREATE INDEX admin_audit_by_time ON admin_audit (at DESC);
