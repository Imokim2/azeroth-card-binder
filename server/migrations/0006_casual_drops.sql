-- Only Ranked counts (roadmap decision D5). Forward-only: this only adds.
-- casual_drops: how many of a player's drop events were rolled in Casual mode (tape position 0), which the server cannot
-- recheck. A player with any is not listed on the ladder. It is derived from the stored events, so a rebuild recomputes it.
ALTER TABLE ledger_state ADD COLUMN casual_drops INTEGER NOT NULL DEFAULT 0;
-- Players who already have drops stored get their count from the drops table.
UPDATE ledger_state SET casual_drops = (SELECT COUNT(*) FROM drops d WHERE d.player_id = ledger_state.player_id AND d.tape_idx = 0);
