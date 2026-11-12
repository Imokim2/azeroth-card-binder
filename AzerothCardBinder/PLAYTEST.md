# World of Warcards · First playtest

Version 0.2.9 targets World of Warcraft: Forever, interface 16001. The add-on is standalone and stores one binder per WoW account installation using SavedVariables.

## Install

1. Extract the ZIP into `World of Warcraft/_forever_/Interface/AddOns/`. The final path should end in `AddOns/AzerothCardBinder/AzerothCardBinder.toc`.
2. Restart WoW, enable **World of Warcards** on the character screen, then click the book icon on the minimap or type `/acb`. Drag the minimap icon to move it around the rim.
3. Open **Index** or type `/acb index`. Search by set, category, or card name. Card matches show their set and whether you own them. Click one to open its exact binder page, or choose **Open card in binder** from a catalogued enemy's portrait menu. The addon starts requesting later portraits for the open set in the background.
4. Click a pocket to see the larger card, rarity, drop chance, and copy counts on the right. Deadmines tracks boss cards and full set progress separately.
5. For the portrait playtest, select **Edwin VanCleef** on Deadmines page 2 and **Foe Reaper 4000** in Westfall. The enlarged model turns gently from side to side while the pocket previews stay still. Left-drag the enlarged NPC portrait to rotate it by hand. The automatic turn pauses during the drag. Missing cards show a grey, hazy preview and return to full colour when collected. Try a Gathering card to check the model or fallback icon.

## Collection

Opening loot with a readable source from the catalog gives a personal roll per source. The base rates are 1% for normal enemies, 2% for elites, and 10% for rares and rare elites. The binder lists the catalog's expected rank. If the game gives the addon a readable rank for the same source, the random roll uses that rank. Gathering uses a rate of 1% per node, with a readable player gathering cast and matching node loot required.

Cards are keyed by NPC or object ID. A session remembers each rolled spawn token, including misses, across loot windows and zone transitions. Reloading the interface or relogging starts a fresh session. When Forever exposes a source at `LOOT_READY` and omits `LOOT_OPENED`, the addon uses the ready snapshot. Loot without a readable catalogued source cannot advance the meter. Use a clean logout or reload to check that Forever restores the binder.

## Deadmines and gathering checklist

1. Run `/acb diag` to start the trace. In Westfall, open loot on a Defias Pillager, close the window without taking everything, then reopen it. Expect one `loot` line and an `Already rolled` line. Try a second Pillager and repeat with auto-loot enabled.
2. Loot several Deadmines enemies, including a boss, during ordinary group play. The trace shows an attempted roll even when the card misses. If loot comes up empty or a source is unreadable, note the enemy, loot method and whether auto-loot was on.
3. For the optional personal roll, toggle `/acb boss` on before fighting Edwin VanCleef. Target him while he is alive and keep him targeted through the kill. Loot his corpse afterward if you can. If Forever sends matching readable start and success events and exposes the same boss as a readable corpse at completion, expect one `encounter` or `loot` roll and a deduplication line if the other route also runs. The trial starts disabled and currently matches the English encounter name. In a group it also requires you to be alive in the instance at completion.
4. Mine a Copper Vein or pick Peacebloom. Check for a `gather` roll. Try interrupting a gather before it completes and compare with looting a corpse. A corpse dropping ore or herbs follows its creature rule.
5. Use `/acb log` to copy the last 80 trace lines. The trace omits raw spawn identifiers. Copy it before reloading.

The encounter trial is deliberately narrow. If the required events, boss token or corpse are absent at completion, the regular loot route still applies. Loot attribution, gathering spell payloads, boss eligibility, and SavedVariables restoration need a live pass on the launch client.

## Pop-ups and shiny cards

When a card is added to the binder, a pop-up shows the card with a sound: **New card**, **Duplicate**, **Shiny card!** or **Received in trade**. Pop-ups queue, pause under the mouse, open the binder when left-clicked and close on right-click. `/acb popup` turns them on or off, and `/acb popup test` shows a sample so you can check the look and sound.

Owned cards get a subtle tint in their rarity colour. The first copy of each card you find has a 1 in 20 chance of being a shiny copy, shown with a cyan and violet foil sheen, a sweep of light and a cyan trim. Use `/acb popup test` to preview a shiny without owning one. You can own one shiny per card. Trades never move a shiny copy, so a shiny stays with the player who found it. The sound kit names are looked up when the pop-up plays and skipped if this client does not have them, so listen for a sound on the first test.

## The full catalog

The binder has 3,423 cards in 70 sets, including gathering nodes and creatures from Forever's dungeons, raids, battlegrounds and zones. The creature catalog keeps entries that are neutral or hostile to both factions. Rarity follows rank (bosses legendary, other rares and elites epic, normal creatures common). Zone art comes from the game's map and dungeon journal where available, with a colour wash for other zones. Use the mouse wheel over the left page to turn one page at a time. Hold Shift to turn ten. Check that a large set such as The Barrens scrolls smoothly and that the index search finds sets by name.

Gathering now has all 39 node types Forever lists (28 herbs, 11 ores), each recognised by every object id the game uses for it. 31 have a 3D model; Earthroot, Mageroyal, Briarthorn, Kingsblood, Ghost Mushroom, Silver Vein, Indurium and Dark Iron show an icon until a matching mesh is found. Mine and pick a few node types, including a high-level one, and check the card appears in the Gathering set with the right skill in its text.

## Lore

Every card has a description of at most 80 characters so it fits the card face. The original hand-made cards keep their lines. All raid and dungeon bosses and about a hundred well-known rares and elites have a line written for them. Most other creatures get a line built from their name: a named group ("the Scarlet Crusade"), a kind of creature (boar, murloc, ghoul), a title or job (guard, captain, miner) or, failing that, their rank. About a third of the creatures fall back to a rank line. The 39 nodes have their own lines. Read a few cards from a big set such as The Barrens for anything that sounds wrong.

## Variant artwork

Open `/acb studio`, cycle through all eight dungeon bosses and compare Signature, the still edition and the animated edition. The editions should be visibly different in crop, facing and action. Check the composition description under the previews. Pause and resume an animated edition; it should freeze on its own action, and restarting the loop must keep that action. Compare the same edition with another player using 0.4.0. Confirm that heads and weapons stay acceptably in frame, particularly Mr. Smite and Aku'mai. The studio grants no cards. Foe Reaper's alternates remain studio-only previews.

## Trading and gifts

Both players need addon **0.4.0 or newer**. Target the other player, open **Trade**, and click **Use target**. Click **Choose card**, search for a card you own and select it, then click **Start trade**. The other player's Trade window should open automatically. They choose their card; both players check **You give** and **You receive**, then click **Accept**. The picker shows how many you own, while the offer always represents one copy. Changing an offer clears the acceptance marks. A completed trade appears in **History**.

For a gift, select **Gift a card** before starting and click **Send gift**. The recipient should see the offered card, an empty **You give** side and an **Accept** button. No return card is required. Confirm that one acceptance moves nothing, both acceptances transfer one copy, cancellation beforehand moves nothing, and a last-copy gift removes that card from the giver's binder. Try an exact collectible edition and check that the shiny unlock remains with its original owner. Reload, sync both companions and reload again; both histories should be accepted and the gift should appear in History.

Move more than about 11 yards away before accepting: the addon should ask you to move closer. The recipient may need to target their partner before accepting. In **Settings**, "Trading distance" turns that check off. Trades remain outdoors and out of combat. Both players should keep the game open until completion; reloads and disconnected clients still need an in-game reliability pass.

Right-click a player and choose **View their binder**: below the sets it should list useful spares, and **Offer a trade** should open Trade with their name. Open a missing card and click **Ask target**, or type `/acb ask target CardName`: they should see your request only if they own it, with repeated requests limited politely.

## Card packs

Packs are rare (1 in 500 attempts), so to test without waiting, ask for a test build or temporarily lower `ACB.packOdds` in `Packs.lua` to 5 (Casual only; Ranked takes the odds from the server's check, so a Ranked test needs the real rate). (1) When one drops, chat says "Card pack found" and the **Packs** button on the binder window shows the count. (2) Click **Packs** (or `/acb packs`), then **Open** on a zone: the pack should shake, burst, and deal five face-down cards. Click one: it should turn over (the back narrows, the card face widens from the middle) and a caption says NEW CARD, SHINY! or Duplicate. **Flip all** turns the rest over. Check the cards belong to the pack's zone and that rarer ones really are rarer over several packs. (3) Close the window with cards still face down: chat should list them. (4) In Ranked with a fresh binder: the pack should open only with five tape entries; after `/reload`, a sync and another `/reload` the server should accept it (no error from the app), and the cards should show in the binder and on the website. The animation and the card flips are new and have only been tested with a stand-in for the game: please look at how they actually appear (sizes, overlap with the window, the flip) and tell us what to adjust.

## Cards from kills you can't loot

(1) Turn on diagnostics in Settings. Target a critter (a rabbit, rat or squirrel), kill it, and about three seconds after it dies chat should say whether you found its card; `/acb log` should show "Kill seen on target". A critter's card is in the catalog, so one should drop eventually; its page shows the stacking chance. (2) Kill a creature that drops loot while it is targeted and loot it straight away: the card should be rolled once, not twice. (3) Have someone else kill a creature while you only stand near it, or kill one that someone else tapped: nothing should happen (the log says it was skipped). (4) If a kill is missed that should have counted, copy the "Kill skipped" lines from `/acb log`; they say whether combat, tapping or targeting was the reason. (5) Switch the setting off: kills you can't loot should give nothing again.

## Reporting a player

(1) Right-click a player, **View their binder**, click **Report**: the button should change to "Click to confirm" and chat should say what it is about to do. Click again within a few seconds: chat should say the report is saved. Clicking it again for the same player should say you already reported them today. (2) `/acb report TheirName trading a short note` should save one with that reason; `/acb report` alone explains the command. (3) With the companion app running, `/reload`, wait for it to sync, `/reload` again: the saved reports should be gone from the game (the app handed back which ones the server took). Nothing should ever happen to the other player.

## Ranked checks every attempt

With the companion app signed in and a binder that is Ranked: (1) `/acb mode ranked` should say every card starts again from its base chance. (2) Kill a few creatures with a Ranked binder, `/reload`, wait for the app to sync, `/reload` again: nothing should be refused and no fair-play flag should appear. (3) Kill creatures until the tape runs out (about 1,000 attempts) and check the paused message tells you to `/reload`; after a reload and a sync, rolling should start again. (4) The Ladder tab and `/acb verify` should still say verified. A binder that was Ranked before this version should switch over on its own at load, and the chat should not show errors.

## Wanted tab

With a second player: (1) Open the **Wanted** tab, type a card you do not own into the box and press Enter or **Add a card**; it should appear on the left, and clicking it removes it. (2) Target the other player and click **Check my target**: within a few seconds their wanted cards should appear on the right (marked "just now") and in chat. Cards you have two or more of are marked "you have a spare", and those players come first. Click a name: the Trade tab should open with their name. (3) With the companion app signed in as a public player, wait for it to sync, `/reload`, and the board should list other public players' cards. (4) Right-click them and **View their binder**: it should now also say what they are looking for. A player who keeps their binder private must not answer either.

## Starting a new binder

To join the Ranked ladder from a binder that has Casual drops or old cards: (1) type `/acb newbinder`, read the message, then `/acb newbinder confirm`; the interface reloads into an empty binder. (2) Open the companion app; it should say **This looks like a new binder** with a button. Click **Start a new binder** and agree. (3) Wait until the app shows the account as synced. (4) In the game type `/acb mode ranked` **before your first drop**, then `/reload` so the app can bring the new roll tape, and `/reload` again once it has synced. Check that a kill then rolls without a pause message. The old collection is kept in the saved file as `lastBinder`.

## Only Ranked counts

The ladder only lists players whose every drop was rolled in Ranked mode. In Casual, or on a binder that already has Casual drops or cards from before the ledger, the Ladder tab says why it cannot join. `/acb mode casual` warns that one Casual drop keeps the binder off the ladder for good. Check those messages, and that a drop rolled in Ranked does not change them.

## Ladder tab

Open the binder and click **Ladder**. Without the companion app it says you are not on the ladder (or to switch to Ranked) and the list is empty, with "Nobody yet." under "First to finish a set". Check the tab opens without an error and the columns line up. With the app and a server running it should list up to 100 players, show your own place and mark your row in gold. The "(verified)" mark in the trade window and binder view only appears for characters on the ladder.

## Zone card bar

A green bar in the reputation bar's place, above the experience bar, shows the cards you own in the place you are in, such as "Westfall 12 / 87". Check it sits exactly over where the reputation bar was and that bar is gone while it shows. Walk between two zones and through a dungeon door and check it changes by itself, and that it moves when you find a card. In a city with no set it hides and the reputation bar returns. Switching it off (Settings or `/acb bar`) also brings the reputation bar back. If it does not take the right bar's place, `/acb bar debug` lists the bars it looked for; send me that. Shift-drag moves it (the position is kept); `/acb bar reset` clears that.

## Stacking drop chance

Every miss raises the card's chance for the next attempt by its listed base rate: a 1% normal card goes 1%, 2%, 3% and so on, an elite 2%, 4%, 6%, a rare 10%, 20%, 30%. At 100% the drop is certain: by attempt 100 for normal and gathering cards, 50 for elite and 10 for rare and rare elite cards. Any drop starts the card over at its base rate. The card page and the tooltip show the chance of the next attempt ("Next attempt: 3%"). Existing miss counts carry over and now count towards the stack, so some cards may be certain on their next attempt. Check the chance rises by one step each miss and falls back after a drop.

## Hints

Mob and node tooltips add a line saying whether the card is in your binder, its chance, and the stacked chance of the next attempt. In the binder, a missing card's page says where to find it. `/acb hints` turns the tooltip lines off. Check that the line appears on a Westfall Defias Pillager, a Foe Reaper 4000 and a Copper Vein.

## Achievements, sets and titles

- Open **Achievements** beside **Trade**, or type `/acb achievements`. Scroll the left page to see milestones for unique cards, completed sets, successful trades, shinies and the Deadmines. Duplicate cards and failed trades leave progress unchanged.
- Finishing a set still shows a **Set complete** pop-up and earns its set title. Existing cards and sets count towards milestones. Trade progress starts from the saved history of up to 20 earlier trades and then counts every completed trade.
- Select a title on the right page to equip it, or click **Hide title** to clear it. The chosen title appears in the binder header. `/acb title` lists your titles, `/acb title <number>` equips one, and `/acb title off` hides it.
- With both players on this build, equip a title and have the other player hover over your character outdoors and out of combat. Look for **Binder title** in their tooltip. After a title change, allow up to 45 seconds for the other player's cached title to expire, then hover again.
- Missing cards have an **Add to wanted list** button on their page.

## Sharing

- Right-click a player and choose **Offer a card trade** or **View their binder**. `/acb view <name>` also requests a read-only binder. Test with both players on this build, outdoors and out of combat. If Forever declines the addon whisper, the addon reports the reason it received. `/acb privacy` stops others viewing yours.
- **Share lists** in the trade window sends your spare cards and your wanted cards to your partner. The window then shows which of their spares you need and which of yours they want. **History** lists your last trades.
- Shift-click a collection pocket or the enlarged card in **Collection** or **Index**. This puts the card into your chat draft. **Link in chat** and `/acb link <name>` still work for owned cards.
- With both players on this build, send a card in a whisper and click it on the other client. The recipient's binder should open to the exact card and show their owned and spare counts. Players without this build see the card name with its reference as plain text.

## Trading

Both players need this version and at least one card each. Any card can be traded, including a last copy (the panel says "Your only copy"). Meet outdoors and out of combat, open `/acb trade`, then enter each other's character name. Use `Name-Realm` if needed.

1. One player clicks **Listen**. The other chooses a duplicate with **<** or **>** and clicks **Send offer**.
2. The listener chooses a different duplicate and clicks **Send reply**.
3. Review the two displayed cards and click **Accept trade** on both clients. Each side's panel turns green when it accepts. When both have accepted, each client gives away its spare copy and adds the card it received. If a message was missed, use **Resend last step**; a client that already finished answers it. If both players started as the sender or the trade expired, click **Cancel** on both clients and begin again.

This release exchanges offers and confirmations over addon whispers and applies the swap on each client. The two-player transport needs a live pass. Trading runs on trust: collection data is local and editable, so each client only checks its own spare copy, and a client that is modified can keep both cards.

## Binder Dust, settings and artwork

- **Loot attempts.** Open a card in Collection. The stats show the protection percentage and the number of identified loot or gathering attempts since its last drop. Loot the corpse of a catalogued enemy and check that the counter advances on a miss and resets on a drop.
- **Binder Dust.** On a card you own twice or more, **Recycle a spare** gives dust (common 1, rare 2, epic 5, legendary 10) and removes one copy; the last copy can never be recycled. On a card you do not own, **Craft** costs ten times the recycle value (10, 20, 50, 100) and adds a plain, non-shiny copy with a pop-up reading CRAFTED WITH DUST. The balance shows at the top of the card page and with `/acb dust`. Change the values in `ACB.dust` in `Catalog.lua`.
- **Settings tab.** Tick boxes for pop-ups, tooltip hints, letting others view your binder, diagnostics and the VanCleef trial, plus Previous title and Next title for the set title shown beside your name. `/acb settings` opens it, and the slash commands (`/acb hints`, `popup`, `privacy`) update the open tab.
- **Zone artwork.** Cards use a packaged painting when there is one (Deadmines, Westfall, Elwynn Forest). Otherwise they try the Dungeon Journal picture, then a loading screen named after the place, then the map of the zone a dungeon sits in, then a colour gradient. In game, open a few dungeons, raids and zones and note which ones end up on the plain gradient. `Art/Portrait-Backdrops-Needed.txt` has a painting prompt for each of the 65 other places.

## References

- Forever's exported [loot events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/LootDocumentation.lua), [unit and cast events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua), [encounter events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncounterInfoDocumentation.lua), and [addon messaging APIs](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua).
- The Forever beta [loot-source report](https://eu.forums.blizzard.com/en/wow/t/feature-request-area-aoe-looting-for-multiple-corpses/633131) and [GUID format notes](https://warcraft.wiki.gg/wiki/GUID) informed the loot-source and session deduplication assumptions.
- Catalog cross-checks used the [Forever Deadmines journal](https://www.wowhead.com/forever/dungeon-journal/the-deadmines), [Miner Johnson observation](https://wowforever.ninja/npcs/3586-miner-johnson/), [Foe Reaper 4000 records](https://www.wowhead.com/forever/npcs/min-level:19/max-level:20), [Copper Vein](https://www.wowhead.com/forever/object=1731/copper-vein), and [Peacebloom](https://www.wowhead.com/forever/object=1618/peacebloom).
