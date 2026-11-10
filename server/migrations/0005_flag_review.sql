-- Flag review (roadmap D4). Forward-only: this only adds. A reviewer clears a flag (the player was only lucky) or confirms
-- it (they were not); either way it records when and why.
ALTER TABLE flags ADD COLUMN reviewed_at INTEGER;
ALTER TABLE flags ADD COLUMN review_note TEXT NOT NULL DEFAULT '';
