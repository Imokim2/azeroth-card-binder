# Group test and 1.0 release

**Release preparation: addon, companion and server 1.0.0.** The merged 0.7.0 candidate has been promoted at the user's request. Publishing and verification are recorded in [RELEASE-1.0.0.md](RELEASE-1.0.0.md). The in-game checks below remain a checklist; automated checks alone do not mark them passed.

## Before the group starts

- Give everyone addon, companion and server **1.0.0**, with the matching test server. Record the catalog and commit in the test notes. The sync savings require companion 0.4.0 or newer; older 0.3.0 installs retain their previous polling until updated.
- Test both a fresh install and an upgrade with an existing collection. Keep backups; moving to 1.0 must not reset players’ collections.
- Use two or more separate player accounts for trades, gifts, binder viewing and wanted lists.

## Group session

| Area | Pass criteria |
|---|---|
| Installation and updating | Correct addon folder detected, Discord sign-in works, errors are readable, and update checks accept genuine signed files. |
| Collecting | Cards, duplicates, variants and shiny cards appear with correct counts. Collection survives logout and restart. |
| Binder | Search, categories, achievements, titles, model poses and tab changes work without leftover text or unloaded models. |
| Drop rates and the launch collection | Critters come far sooner than before; a held-back creature gives nothing until a season releases its card; a fresh binder shows launch cards only and an existing one keeps its owned copies; every page can be finished from its launch cards; packs never hold a held-back card. |
| Seasons | A scheduled season releases its cards for good; completion, titles and pack rewards work and cannot be claimed twice. |
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
