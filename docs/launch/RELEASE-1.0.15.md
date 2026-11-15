# Guild binder release: addon 1.0.15 / companion 1.0.3

Prepared 15 November 2026, with server 1.0.2 and ledger spec 11. Builds on Harry's merged PR #66. Publish only after the matching installer and addon archive are checked and the signed feed is updated.

The top Guild tab replaces Wanted. It uses the existing parchment, fonts, buttons and card viewer. Browse the shared inventory, search by name or choose Donate cards. The list defaults to spare copies. Each donation requires confirmation, with a last-copy warning. Cancelling does not move a card, and a changed membership invalidates an open confirmation. Wanted lists remain accessible from Guild and `/acb wanted`.

The companion handles guild creation requests, membership applications and owner approval. The protected admin page reviews new guild requests. New summary data is validated, paired to the correct guild and binder, then written through the existing saved-file bridge. Guilds refresh on saved changes and manual actions, without idle polling.

Donations are permanent once credited. A refused donation is returned using the server's existing refund flow. Recovery must not discard or transplant pending donation state. Personal saves and Ranked progress are not reset.

Deployment requires additive migrations 0015_guilds.sql, 0016_guild_members.sql and 0017_guild_donations.sql on staging first, then production, with managed recovery references recorded. Enable GUILDS_ENABLED only with those tables present. Minimum supported app/addon versions remain unchanged for existing binders.

Validation before source publication: 258 Lua checks and 423 Node tests passed without skips, plus app/server typechecks and clean app compilation. The Windows release workflow and the downloaded installer are checked separately. In-game group verification of the Guild layout, membership and donation roundtrip remains a manual test.

The DX12 issue remains disclosed; this release does not claim to fix it. The CurseForge description includes the guild feature and keeps known issues near the bottom. No fake guild screenshots or community counts are used.
