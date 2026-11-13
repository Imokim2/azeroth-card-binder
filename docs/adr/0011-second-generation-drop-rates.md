# 0011: A second generation of drop rates

Proposed 13 November 2026, agreed in principle by Harry and Ollie. See `docs/proposals/SMALLER-LAUNCH-COLLECTION.md` for why.

Raise drop rates after launch without invalidating any history: critters four times as likely, other ordinary cards 20% more likely, chase cards on limited sources (bosses, rare spawns, gathering, epics) unchanged.

The server replays every Ranked roll against the catalog's rates, so editing rates in place would make existing histories fail. Instead the catalog keeps both sets (`dropProfile.rate`, never changed, and `dropProfile.rate2`), and a new once-only marker `mode/chase2` (ledger specification 8) switches a binder to the second set, exactly as `mode/chase1` switched it to per-card profiles. Events before the marker are checked at the old rates; events after it at the new ones. The marker is valid only after `chase1` and only once. Miss counts carry over. The luck statistics restart at the marker, because the chances they compare against changed.

The add-on writes `chase2` before its first roll after upgrading, after flushing any run of misses so those stay at the old rates. The server refuses a binder on the new rates (or an upload carrying the marker) from a companion that does not say it speaks specification 8, so an old companion cannot upload a history it would mis-describe. Add-on, companion and server ship together, with the minimum versions raised; Casual play uses the same rates but is not checked.

Rejected: changing `rate` in place (breaks every existing Ranked history); a flag in the catalog version alone (a replay would have no way to tell which events were rolled at which rates).
