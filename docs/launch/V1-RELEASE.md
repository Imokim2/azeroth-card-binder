# Group test and 1.0 release

**Target: 1.0.0 after the group test passes.** This is the release plan, not a published release or a version bump. Keep the current development versions until the tested candidate is agreed.

## Before the group starts

- Give everyone the same candidate addon and companion builds, with the matching test server. Record their versions, catalog and commit in the test notes. The current candidate is addon 0.6.0 and companion/server 0.4.0. The sync savings require companion 0.4.0; older 0.3.0 installs retain their previous polling until updated.
- Test both a fresh install and an upgrade with an existing collection. Keep backups; moving to 1.0 must not reset players’ collections.
- Use two or more separate player accounts for trades, gifts, binder viewing and wanted lists.

## Group session

| Area | Pass criteria |
|---|---|
| Installation and updating | Correct addon folder detected, Discord sign-in works, errors are readable, and update checks accept genuine signed files. |
| Collecting | Cards, duplicates, variants and shiny cards appear with correct counts. Collection survives logout and restart. |
| Binder | Search, categories, achievements, titles, model poses and tab changes work without leftover text or unloaded models. |
| Packs and satchel | Common/Rare/Epic sizes are correct in the candidate build, faces preload, closing early loses nothing, and unopened packs remain available. |
| Trading and gifts | Both players see the same offer and accept it. Cancellation, rejected offers and disconnect/retry do not duplicate or lose items. Include pack trades and gifts. |
| Wanted lists | Mark cards in game; target checks, binder inspection and trade list sharing show the other player’s list without the website or companion wanted feed. |
| Chat links and announcements | Private links open the correct owned card; public announcements route correctly and can be switched off. |
| Sounds and settings | Pickup, pack, trade and window sound switches work independently and survive a reload. |
| Saved-progress syncing | Logout or /reload syncs new progress. The leaderboard stays cached while idle; a saved-file change refreshes it. Test offline recovery and another save during upload. |
| Website | Downloads, help, rules, support links and icons work on desktop and mobile. No public wanted board. Verify the PayPal.Me destination without an automated payment. |

Record any issue with the candidate version, player actions and screenshot/error text. Fix blockers and retest the affected flows before calling the build 1.0.

## Promote the tested build

1. Freeze the passing commit and coordinate addon, companion and server release versions as **1.0.0**. Keep saved-data/ledger compatibility and required minimum versions under deliberate control.
2. Build the exact final addon archive and Windows installer; run the full checks and the group-tested flows on those files.
3. Publish the GitHub 1.0 release files, checksums and accurate notes. Sign the updater manifest with the existing trusted release key; do not replace the key or point it at untested files.
4. Deploy the matching server after those downloads are available. Verify health, downloads, signature, syncing, support link and client compatibility. Keep the previous deployment and downloads available for recovery.
5. Replace screenshot placeholders with captures from the release build. Keep the installer’s unsigned-publisher wording accurate.
6. Submit to CurseForge only after its compatibility questions are resolved and the user asks to publish there. The [CurseForge plan](CURSEFORGE-PLAN.md) remains a draft.
