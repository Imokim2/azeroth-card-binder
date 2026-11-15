# Addon 1.0.14 and companion 1.0.2

Prepared 15 November 2026 for group testing, with server 1.0.1 and ledger spec 10. Harry's card work is merged from PR #63. This record is updated after publication; preparation alone does not change website downloads.

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
