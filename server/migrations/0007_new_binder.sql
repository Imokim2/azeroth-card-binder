-- Starting a new binder (roadmap, "reset"). Forward-only: this only adds.
-- epoch: how many times the player has started over. It is part of how their roll tape is derived, so a new binder never
-- replays the old binder's roll values. reset_at: when they last did, to stop it being done again and again.
ALTER TABLE players ADD COLUMN epoch INTEGER NOT NULL DEFAULT 0;
ALTER TABLE players ADD COLUMN reset_at INTEGER;
