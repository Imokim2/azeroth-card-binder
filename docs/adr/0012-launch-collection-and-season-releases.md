# 0012: A smaller launch collection, released by seasons

Proposed 13 November 2026, agreed by Harry and Ollie. See `docs/proposals/SMALLER-LAUNCH-COLLECTION.md` for the reasons and the numbers.

Launch with half the cards and hold the other half (1,712 ordinary-creature cards) back as season targets. Every elite, boss, critter and gathering card stays.

**Availability is a rule, not a deletion.** The catalog keeps every card and marks the held-back ones `seasonal`. A once-only marker `mode/launch1` (ledger specification 9, valid only after `chase2`) switches a binder to the new availability: from then on the server refuses to let it acquire (drop, miss on, find in a pack, craft) a held-back card that no season has released. Everything before the marker replays as it always did, and trades, recycling and owned copies are never affected.

**A card is released by scheduling a season that features it, and stays released.** Availability is "released at or before the event's time and the server's now". The shared rules take that as a function because the schedule lives in the server's database; the add-on learns the released list through the companion (`sync.seasonal.released`). This keeps later seasons a server-only change, as Ollie's seasons are.

**A page is finished by its launch cards alone.** Sets keep every card (pack pools and old histories depend on that) and name the cards that finish them in `required`; held-back cards are extras that still count as cards owned. Pages therefore stay completable on day one and never become incomplete.

Rejected: removing cards from the catalog (breaks old histories, packs and owned copies); making released cards expire after their season (a card would become uncollectable again, and "owned" binders would need special rules); counting released cards towards page completion (a completed page could become incomplete, and titles and first-finisher records would need a rule for that).

Consequences: add-on, companion and server ship together with minimum versions raised. A player who does not run the companion sees only launch cards until it syncs. The list is generated (`tools/launch-collection.js`) and a test keeps it equal to its rule.
