-- The admin panel can reset a player's binder (archive it, as the player's own restart does). The player's add-on still holds the old
-- history, so the reset also records when it happened: a history whose first event is not after that time is refused, and
-- restoring the binder clears it. Forward-only: this only adds.
ALTER TABLE players ADD COLUMN barred_before INTEGER;
