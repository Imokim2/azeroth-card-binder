# World of Warcards 1.0.21

Harry's campfire fixes:

- The game's **Camp Benefits** buff now activates the campfire boost. Its duration determines whether it is the ordinary or violet camp buff.
- The buff's tooltip explains the boost where the client supports it. A separate icon remains available as a fallback.
- Drag the fallback icon to move it; its position is saved. Use `/acb campfire reset` to put it back, or `/acb campfire icon on`, `off` or `auto` to choose when it appears.

Keep companion **1.0.6**. If you already have it, only the addon needs updating, then `/reload` in game. Players upgrading from an older companion should update that first. Your cards, packs, guild donations and saved progress are preserved. No ledger or server rule changes are needed for these fixes.

The guild index, card selection, review, cancellation and donor-name improvements from 1.0.20 remain included.

Downloads: https://worldofwarcards.co.uk/download
Discord: https://discord.gg/266naSpg7

Known issue: some Forever clients can enter a fullscreen minimise/restore loop near loading screens. This release does not claim to fix it. If chat responds, type `/reload`; otherwise close the game with Alt+F4 and relaunch. Unsaved finds may be lost.

Harry's changes were merged in PR #74, 026c8c8. Its CI 43949949902 passed, and 288 Lua checks passed locally. Guild view/review/batch, Binder.lua and app/server guild code are unchanged from our 1.0.20 release. Companion 1.0.6, server 1.0.5, ledger spec 12 and catalog 39500d3ae8ca stay unchanged. Keep the canonical companion installer from v1.0.20, including its exact signed notes and checksum. In-game buff/tooltip testing remains for players.

Release preparation PR #75 merged as 8186848; CI 43962457817 and release 43963162298 passed. The published addon has 112 safe entries, every TOC module, exact reviewed campfire/guild code and empty factory Sync. Its published checksum and trusted signature verified. The actual updater preserved two fixture account saves, their backups and Ranked Sync, retaining an addon backup. The canonical companion block, URL, checksum and notes are byte-for-byte unchanged from v1.0.20.

Both staging and production passed exact signed-feed/download/catalog checks. Production passed all 18 deep smoke checks. No migration or player-save edit was needed. Website downloads, GitHub release notes, Discord updates/downloads and the CurseForge patch changelog are updated. CurseForge file 9655605 was submitted as Release, Forever 1.60.1, automatic publication after approval; it was processing at the final check. The previous 1.0.20 file is now Approved.

Addon SHA-256: `d759373e4d6d27f1744e28d67d5f919e80625ac3b6dbd07519253fdb53029e83`.
