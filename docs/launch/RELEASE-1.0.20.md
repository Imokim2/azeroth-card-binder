# World of Warcards 1.0.20

Use companion **1.0.6** with addon **1.0.20**. Keep the companion open while playing Ranked. Updates preserve your collection and saved progress.

- The Guild tab opens the guild collection index. **Guild index** at the top takes you back from any section.
- **Add cards** opens your own binder. Choose cards, use **Review selected** to check the full selection and last-copy warnings, then accept the donation.
- **Keep choosing** returns to your selection. **Cancel donation** discards it and returns to the guild index. Cards only move after acceptance.
- Confirmed guild cards show their latest donating character. Older donations without a recorded character remain unnamed.
- Keep the companion open, use **Save & sync** after donating, then **Refresh after sync** once the companion finishes.
- Includes Harry's campfire boost and four Fellowship cards for camping, trading, gifting and guild donations, plus their collection achievement and title.

Help: https://worldofwarcards.co.uk/help
Discord: https://discord.gg/266naSpg7

Known issue: some Forever clients can enter a fullscreen minimise/restore loop near loading screens. This release does not claim to fix it. If chat responds, type `/reload`; otherwise close the game with Alt+F4 and relaunch. Unsaved finds may be lost.

Implementation: signed per-copy donation and settlement are unchanged. Migration 0020 stores the signed donating character for new donations, with an indexed latest-donor lookup available only to active guild members. Account deletion clears donor names while preserving guild cards. Companion 1.0.6 validates and carries the optional name through Sync.lua. Ledger spec 12 and catalog 39500d3ae8ca come from Harry’s merged campfire/Fellowship changes. No save reset or minimum-version increase. Actual in-game visual and group donation testing remains for the players.

Published from PR #73, source 07a9c33, tag v1.0.20. CI 43943653652 and release 43944263198 passed, including 282 Lua checks, the full Node suite, packaged Windows startup and native installer process checks. The exact published ZIP contains 111 safe entries, all TOC modules, matching reviewed guild/campfire/Fellowship source and empty factory Sync. Both published checksums and the trusted update signature verified. The real updater installed the published ZIP against two fixture accounts without changing either save, either backup or Ranked Sync; it retained an addon backup.

Migration 0020 was applied to staging and production after recording managed recovery points. Staging passed 29 walkthrough checks, both environments passed 18 deep smoke checks, and exact signed-feed tests confirmed the same app/addon URLs, hashes, versions and catalog on their download pages. Production server 1.0.5 deployment: 5f3f98ee-c74a-4f3b-8ea3-e7ba9032681d.

Addon SHA-256: `6df082351c8c07be9254442a3c571b7a91c02fd562c0727293d2d4f4a580e10f`.
Companion SHA-256: `22d03e39ccc5d5166760fe13faa5604bb19237b7267d9dbd30b528588cb48cce`.

Website downloads/help, GitHub README/release notes and Discord updates/downloads describe the same flow. CurseForge file 9653989 was submitted as Release for Forever 1.60.1 with automatic publication after approval; its guide now includes navigation, cancellation, donor names and Fellowship. Genuine earlier screenshots are retained, with a new in-game Guild capture still needed. The loading-screen warning remains near the bottom and is not claimed fixed.
