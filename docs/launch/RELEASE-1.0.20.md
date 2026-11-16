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
