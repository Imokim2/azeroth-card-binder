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
