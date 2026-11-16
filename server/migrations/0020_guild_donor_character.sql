-- Preserve the exact signed donor character. Historical donations remain unnamed.
ALTER TABLE guild_donations ADD COLUMN donor_character TEXT NOT NULL DEFAULT '';
CREATE INDEX guild_donations_latest_card ON guild_donations
 (guild_id, card_key, result, decided_at DESC, seq DESC, operation_id DESC);
