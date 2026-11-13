# World of Warcards 1.0.0

Addon, Windows companion and server use version **1.0.0**. The release includes Harry's latest merged work and the seasonal/trading implementation. This promotes the unpublished addon 0.7.0 / companion-server 0.5.0 candidate without changing gameplay rules again.

## Publishing order

1. Run both typechecks, a clean companion build, the full Lua/Node tests and the checkout walkthrough. Keep the results with the release record.
2. Record Cloudflare managed database recovery bookmarks. A full local database export was declined by automatic approval review because it would copy private player/account records; recovery bookmarks do not export those records.
3. Apply additive migration `0014_seasons.sql` on staging before the new server, then run the staging walkthrough. Keep the existing signed downloads during this step. No season is scheduled automatically.
4. Merge the reviewed source, tag `v1.0.0` and let the release workflow build the exact addon ZIP and Windows installer. The real packaged Windows startup gate must pass before publication.
5. Download the published files, check their SHA-256 values and addon folder layout, extract the published installer and launch its actual app using the isolated package checker.
6. Apply the production migration and deploy the backwards-compatible server before offering the new protocol-9 clients. Then sign the release descriptor with the existing release key, update both environments' latest versions, and deploy the matching signed feed.
7. Run the public walkthrough and deep download checks. Keep minimum versions at companion 0.4.0 / addon 0.6.0 during rollout. Do not force collection resets or remove saved files.

For existing Ranked players: update the companion first, then the addon. New players should install both before starting Ranked collecting. Updates preserve existing binder progress.

## What still needs people

Automated checks do not replace the in-game group checklist in [V1-RELEASE.md](V1-RELEASE.md). Record fresh and existing-account upgrades, trades/gifts, seasonal completion and rewards, and model/layout checks on the downloaded files. Do not mark those checks passed without the actual game session.

CurseForge submission is separate from the website/GitHub release. The description, branding and upload ZIP can be prepared now. Forever compatibility tags, wording for the external companion, and real in-game gallery images still need confirmation; see [CURSEFORGE-PLAN.md](CURSEFORGE-PLAN.md).
