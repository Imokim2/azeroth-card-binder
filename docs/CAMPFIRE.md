# The campfire boost

Forever's camping system lets a camp give buffs to the players sitting at it. While you have the campfire buff, your chance of a card drop is **doubled**. The buff is the game's own, so the boost starts and ends with it: an hour for the welcoming campfire (spell 1229739), two hours when the camp has been dusted with violet (spell 1289723). These ids were read from the game with `/acb auras`.

## What it changes

- **Card drops** are twice as likely (capped at certain), in Casual and in Ranked, for **common and rare cards** only: ordinary creatures. Elites, rare spawns and bosses (epic and legendary cards) are not boosted. The "chance builds up after each miss" protection carries on as before and is doubled with the rest.
- **Not changed:** the chance of finding a pack, the shiny chance, and the cards a pack gives.
- The chance shown in the diagnostics log is the doubled one, marked "with the campfire".

## What the player sees

A small icon with the buff's own picture and the time left appears beside the buff bar while the buff lasts, with a tooltip. An add-on cannot add a real buff to the game's buff bar, so this is an icon of the add-on's own, placed next to it. It disappears when the buff ends.

- `/acb campfire` says whether you have the buff and how long is left.
- `/acb campfire icon` hides or shows the icon. The boost does not depend on the icon.
- `/acb auras` lists everything on your character with spell ids (used to find the two ids above).
- A new camp claim also earns a roll for the Fireside Friend card (docs/FELLOWSHIP.md), which a camp doubles like any common or rare card.

## Ranked and the server

Ranked rolls are checked by the server against a tape it issued, so the server has to know which attempts had the doubled chance. It cannot see a camp, so the binder says so in its ledger (ledger version 12, `docs/LEDGER-SPEC.md`):

1. `mode/camp1`, once, after the faction marker.
2. A `camp` event (`welcoming` or `violet`, with the seconds the buff has left) whenever the buff reaches further than the last claim.
3. Each boosted attempt is a `drop` or a run of misses with `partner = "camp"`. The server refuses that mark on an epic or legendary card (rule `camp`), so a boost cannot be claimed where the game gives none.

The server then rechecks each of those rolls at double the chance: a boosted drop must have rolled at or below it, and a boosted miss above it, so claiming the boost for attempts that were not made at a camp makes misses harder to explain, not easier. A boosted attempt counts double in the luck statistics, so a player who camps a lot is not flagged as lucky.

**The claim is the player's own word.** Like a character's faction, the server cannot prove someone was at a camp. What it bounds is what can be claimed: the buff cannot be longer than the game's, a boosted drop has to fall within the claimed window, and everything has to replay. A player who claims a camp they never had gets the doubled chance. The luck checks do not catch that, because boosted attempts are counted double on purpose. If this matters for the ladder, the answer is a limit on how much boosted play counts, which needs a decision about how much camping is normal.

## Things that depend on the game

- The buff is detected by its spell id in the player's auras. If a game patch changes the ids, the boost stops until `ACB.campAuras` in `AzerothCardBinder/Campfire.lua` is updated.
- Several camp features can give several buffs; only these two ids count. The icon and the boost use whichever has the longer time left.
- Nothing here has been tried in the real game yet: the aura calls, the icon's position beside the buff bar and the way the buff behaves when a camp ends all need a look in game.
