# Policy and licence checks (roadmap B1)

Written 10 Nov 2026 from public pages found by web search. **This is research, not legal advice**, and several answers still need a human to confirm them with the people who run the game and the data sources. Each item says what is known, what is not, and what to do.

## D1. May an external app read and write the add-on's saved-data file?

**Known**
- Blizzard's UI Add-On Development Policy (first published 2009, the version still posted on its forums) has no section on companion apps and none on game data. Its rules are about add-ons themselves (below).
- Community guidance from long-standing add-on sites is that outside programs may read the saved-variables files on disk and write files an add-on reads, but must not read or talk to the running game (memory reading, packet inspection), which Blizzard treats as cheating. TradeSkillMaster's app is the best-known example of the permitted kind.
- Blizzard's 2025 and 2026 statements about third-party software are about programs that modify the client or draw overlays from live game data.
- The Midnight add-on restrictions (secret values, limits on combat data) are reported to apply to World of Warcraft: Forever as well. The add-on already ignores secret values (`ACB.read`).

**How the design stays on the safe side:** the app only reads one file the game wrote and writes one file the add-on reads (`Data/Sync.lua`). It never touches the game process, its memory, its network traffic or its window. It does not automate gameplay and gives no in-game advantage: the add-on collects cards, it does not make anything easier to kill or loot.

**Not known:** whether Forever has its own add-on or third-party-tool policy beyond Blizzard's, and the exact folder layout of a Forever install.

**To do (needs a person):** ask the Forever community and, if there is one, its official support channel, in writing, whether an app that only reads and writes saved-variables files is acceptable. Keep the answer in this folder. If the answer is no, Casual mode still works and nothing server-side is needed.

## What Blizzard's add-on policy requires of the add-on

Paraphrased from the posted policy. Each rule is checked against this project.

| Rule | This project |
|---|---|
| Free of charge, no paid versions, downloads or related services | Yes. No paid features. Keep it that way (see D3). |
| Code public and not hidden or obfuscated | Yes, if the repository is public. The Lua is plain and readable. Do not minify or obfuscate it. |
| No harm to realm performance or other players | Whispers are limited to trade and view messages, only on request. The add-on is quiet otherwise. Watch the trade messages in play-tests. |
| No advertising of goods or services | None. |
| No donation requests inside the game | None. Put any donation link on the website or download page, never in the add-on (not even in a tooltip). |
| Nothing offensive | Card text is short descriptions of creatures. Review any added text. |
| Follow the Terms of Use and EULA | See the app's behaviour above. |
| Blizzard may disable add-on functionality at its sole discretion | Accepted. The server can pause Ranked rolls through a kill switch if the game changes. |

## D3. Is this noncommercial?

The creature data comes from a fan site that says it allows noncommercial use, and the add-on policy forbids paid features. The roadmap therefore commits to: no paid features, no ads, prizes that are not money (titles, hall of fame, cosmetic card backs), donations only on the website and only if the data sources' terms allow them.

**To do (needs a person):** read wowforever.ninja's "Where the data comes from" page and its terms again before launch, and write to the site's owner if donations or any income are planned. Keep the reply here.

## D4. Licence for this repository

**Known:** `AzerothCardBinder/CatalogForever.lua` is generated from a fan database whose baseline is cMaNGOS classic-db, published under GPL-3.0, and `CatalogNodes.lua` uses ids from AzerothCore (also GPL). Data generated from GPL data may carry the GPL with it.

**Recommendation:** license the repository **GPL-3.0-or-later**, and say so in `CREDITS.md`. It matches the data's licence, it keeps the add-on source public as Blizzard's policy requires, and it still lets people use and learn from the code. The alternative (a permissive licence for the code and a separate licence for the generated data) is possible, but only worth the complexity if someone wants to reuse the code commercially.

**Decided (12 Nov 2026): GPL-3.0-or-later.** `LICENSE` holds the full text, and the README and `CREDITS.md` name it. The repository owner and the other contributors should each confirm they agree before the repository is made public. Ask a lawyer if the project grows beyond a hobby.

## Other points found

- **No Blizzard art on the website.** Card art comes from the game client only; the website must show card names and numbers, not game art (roadmap Section 4).
- **The "Forever" name.** The project says it is not affiliated with or endorsed by Blizzard. Keep that line on the README, the website and the app's About page.
- **Privacy.** The server stores a Discord id, a public key, character names and the ledger, and nothing else. A privacy page and a data-deletion route are launch requirements (roadmap E3).

## Sources

- Blizzard's UI Add-On Development Policy, as posted on its forums: https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534
- WoWInterface forum guidance on external programs and saved variables: https://www.wowinterface.com/forums/showthread.php?p=148818
- Reporting that Midnight add-on restrictions apply in Forever: https://kami-labs.fr/en/wow-classic/wow-forever-addons-restreints-comme-sur-midnight/ and https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/ (the second page could not be opened here; its headline was read from search results only)
