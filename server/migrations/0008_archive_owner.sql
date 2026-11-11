-- Deleting a player's data (privacy). Forward-only: this only adds.
-- archived_from: for the private archive a reset leaves behind, the player it came from, so that deleting that player
-- deletes the archived records too.
ALTER TABLE players ADD COLUMN archived_from TEXT;
UPDATE players SET archived_from = NULL;
