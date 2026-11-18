# World of Warcards 1.1.0 publication

Published 18 November 2026: addon **1.1.0**, companion **1.0.8**, server **1.1.0**. Catalogue remains `39500d3ae8ca`.

- [GitHub release](https://github.com/Imokim2/azeroth-card-binder/releases/tag/1.1.0) contains the tested addon ZIP and companion installer. The tag deliberately has no `v` prefix so the separate legacy build workflow does not replace the verified binaries.
- The website and signed release feed advertise both versions. Existing release-signing identity is unchanged. Install companion first, then addon; sync and reload to load the reply. No binder reset is an update step.
- Production Worker deployment: `dfe41f7e-230a-41d0-bd16-d3bc00c3456a`. Bonus-events migration 0021 is applied. No bonus event was scheduled or activated.
- CurseForge file **9691595** was submitted as Release for Forever 1.60.1, with automatic publication after approval. Last observed state: **Processing**. The saved project description and file changelog include history, events and campfire sections; the existing loading-screen warning remains near the bottom.
- Discord **#updates** and **#downloads** received matching notes and companion-first update instructions. Existing announcements were retained.

## Validation

305 Lua checks and 462 companion/server checks passed, along with typechecks, packaged imports and isolated packaged executable startup. Both staging and production passed all 18 release smoke checks. The live canonical feed was separately checked for companion 1.0.8 and addon 1.1.0.

The actual compiled companion updater verified the signed feed and both downloaded artifacts. An isolated addon install preserved the fixture's `WTF` saved progress and `Data/Sync.lua` byte for byte, and backed up the previous addon. No user game installation or existing binder was modified for these checks.

Automated checks do not replace in-game testing of two-player trades, event timing and dungeon chat. The existing DirectX 12 loading-screen loop is not a confirmed fix in this release.
