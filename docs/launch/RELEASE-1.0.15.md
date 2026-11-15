# Guild binder release: addon 1.0.15 / companion 1.0.3

Published 15 November 2026, with server 1.0.2 and ledger spec 11. Builds on Harry's merged PR #66. Publish only after the matching installer and addon archive are checked and the signed feed is updated.

The top Guild tab replaces Wanted. It uses the existing parchment, fonts, buttons and card viewer. Browse the shared inventory, search by name or choose Donate cards. The list defaults to spare copies. Each donation requires confirmation, with a last-copy warning. Cancelling does not move a card, and a changed membership invalidates an open confirmation. Wanted lists remain accessible from Guild and `/acb wanted`.

The companion handles guild creation requests, membership applications and owner approval. The protected admin page reviews new guild requests. New summary data is validated, paired to the correct guild and binder, then written through the existing saved-file bridge. Guilds refresh on saved changes and manual actions, without idle polling.

Donations are permanent once credited. A refused donation is returned using the server's existing refund flow. Recovery must not discard or transplant pending donation state. Personal saves and Ranked progress are not reset.

Deployment requires additive migrations 0015_guilds.sql, 0016_guild_members.sql and 0017_guild_donations.sql on staging first, then production, with managed recovery references recorded. Enable GUILDS_ENABLED only with those tables present. Minimum supported app/addon versions remain unchanged for existing binders.

Validation before source publication: 258 Lua checks and 423 Node tests passed without skips, plus app/server typechecks and clean app compilation. The Windows release workflow and the downloaded installer are checked separately. In-game group verification of the Guild layout, membership and donation roundtrip remains a manual test.

The DX12 issue remains disclosed; this release does not claim to fix it. The CurseForge description includes the guild feature and keeps known issues near the bottom. No fake guild screenshots or community counts are used.

## Publication record

- Source `a5e2697`, tag `v1.0.15`. Release workflow `43764982164` passed addon, Windows installer and publication, including real packaged-app startup and native installer-process tests.
- Migrations 0015–0017 were applied on staging and production after managed recovery references were recorded. Guild routes are enabled. No player collection was reset or exported.
- Staging passed all 29 walkthrough checks and 18 deep download checks. Guild HTML and public standings routes answered successfully on both environments.
- The actual published files matched their hashes. The addon contains 105 entries with Guild.lua, GuildView.lua and the empty factory sync file. The companion extracted from the published installer passed imports, preload, renderer and actual executable startup as 1.0.3.
- The signed update feed and actual addon install preserved both fixture accounts, both save backups and existing Ranked sync data byte-for-byte, with an addon backup kept.
- The same verified feed is deployed to production. The normal public updater and download page passed exact-version and signature checks; production passed all 18 deep checks, including real download hashes. Discord updates and downloads channels were updated with the matching versions and Guild setup instructions. CurseForge project 1808775 and addon file 9638154 are submitted for processing/moderation, with automatic publication after approval.
- The CurseForge gallery has all five supplied in-game/companion captures with individual titles and descriptions. Its description preview renders all images, links to Discord and help, and keeps the loading-screen warning near the bottom. At the final check the project was awaiting moderator approval and the file status was Uploading; it is not yet a public CurseForge release.

Addon SHA-256: `0fd9337592d43cc94db7dc51f1a3144d773c9af56128bf3899ca09b045ed01e7`.

Companion SHA-256: `00a7cb2af979da1e3b79ab9752f5e9c4c6cb443fcecfd7c8313b43884a3f1914`.
