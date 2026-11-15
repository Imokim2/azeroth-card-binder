# Addon 1.0.14 and companion 1.0.2

Published 15 November 2026 for group testing, with server 1.0.1 and ledger spec 10. Harry's card work is merged from PR #63; upgrade compatibility and matching versions are merged in PR #65.

## Included

- Faction bonus cards, expanded dungeon/raid lists and exclusions for known unkillable or one-off creatures. Faction cards are extras, tradable if owned, and excluded from set requirements and seasons.
- Companion 1.0.2 uploads the new card format. Install it before addon 1.0.14. The server continues accepting earlier formats for binders that have not activated the new rules.
- Historical compatibility for the published spec-9 active list, older pack results and completed pages. The frozen checkpoint is catalog `3d0b62359bee`; the release catalog is `4301ff859016`.
- No account reset, collection wipe, new database migration or scheduled season. Existing cards, packs, dust, titles and progress remain owned.

## Automated checks

The release includes fixed regression cases from the published catalog: 336 pack outcomes across 14 affected zones, 56 server tape checks and the old completion requirements for all 14 changed pages. These cover both earlier launch availability and activation of the new rules.

Run the complete addon/shared/app/server suite and typechecks before tagging. The release workflow must build the Windows installer and pass its actual packaged-executable startup check and native installer-process tests before the files are advertised. Download the published files and validate their hashes, addon contents and extracted installer again before signing the update feed.

## Deployment order

1. Record managed Cloudflare recovery references, without exporting player records. Verify no migration is waiting.
2. Deploy the backwards-compatible server to staging, leaving the previous signed downloads in place. Run the release walkthrough, then repeat on production.
3. Publish the checked addon ZIP and companion installer from the release tag. Verify both published files and the actual packaged Windows executable.
4. Sign the manifest locally with the existing trusted release key, then deploy the new feed to staging. Check the real addon updater on isolated fixture accounts, including unchanged save backups and sync data.
5. Deploy the same verified signed feed to production. Check the normal public download page, update feed and actual downloads after cached responses expire.

## Still needs the game

Test updating the companion first and the addon second over an existing collection, then save/sync/reload. Check faction eligibility, dungeon cards, set completion, packs, trading/gifting and model framing in Forever. Automated checks are not an in-game pass.

The DX12 loading-screen issue remains disclosed in [KNOWN-ISSUES.md](../../KNOWN-ISSUES.md). The model-pool limit is a mitigation, not a confirmed fix. This update does not change that mitigation. CurseForge submission remains separate and unsubmitted.

## Publication checks, 15 November 2026

- Tag `v1.0.14`, source `d550122`. Release workflow `43751785166` passed addon, Windows installer, actual packaged-app startup, native installer-process tests and publication.
- Local verification passed 248 Lua checks and 382 Node tests without skips, both typechecks and a clean companion build.
- Both Cloudflare databases had no pending migration. Managed recovery references were recorded; no player records were exported or reset.
- The exact published files were downloaded and checked against the published hashes. The addon has 103 entries, all TOC modules, the expected assets and the empty factory sync file, with no developer studio, installer or credentials.
- The companion extracted from the downloaded installer passed real ASAR imports and actual main/preload/renderer startup in isolated fresh data as version 1.0.2 with catalog `4301ff859016`.
- The trusted signed manifest and real addon updater passed an isolated installation over two accounts. Both save files, both backup saves and existing Ranked sync data remained byte-for-byte unchanged; the old addon was backed up.
- Staging passed all 18 deep checks. The same verified signed feed was deployed to production, where fresh requests showed the new versions and matching download links/checksums. Normal cached responses are checked separately before handoff.

Published addon SHA-256: `e7c119467f45e9de15001d6762f0e64f2250badaf6a7df7646a49c6b5a938e60`.

Published companion SHA-256: `ba8bfc21c78e60e9ce621d2af5b267de184d5dccd7738198b3d2ade17e60f88a`.
