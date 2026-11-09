# Azeroth Card Binder · First playtest

Version 0.2.3 targets World of Warcraft: Forever, interface 16001. The add-on is standalone and stores one binder per WoW account installation using SavedVariables.

## Install

1. Extract the ZIP into `World of Warcraft/_forever_/Interface/AddOns/`. The final path should end in `AddOns/AzerothCardBinder/AzerothCardBinder.toc`.
2. Restart WoW, enable **Azeroth Card Binder** on the character screen, then click the book icon on the minimap or type `/acb`. Drag the minimap icon to move it around the rim.
3. Open **Index** or type `/acb index`. Search for a set by name or category, then click it to open its **Collection**. The index shows how many cards you own in each set.
4. Click a pocket to see the larger card, rarity, drop chance, and copy counts on the right. Deadmines has three pages of four cards and tracks the eight boss cards and full twelve-card set separately.
5. For the portrait playtest, select **Edwin VanCleef** on Deadmines page 2 and **Foe Reaper 4000** in Westfall. The enlarged card previews the scene even when the pocket is still marked Missing. Check the framing, whether the pose holds still, and how the character reads against the backdrop. Try a Gathering card to check that its resource model and backdrop display together. These checks require the live client.

## Collection

Opening loot with a readable source from the catalog gives a personal roll per source. There are 18 cards. Normal enemies roll at 0.5%, elites at 1%, and rares and rare elites at 5%. The binder lists the catalog's expected rank. If the game gives the add-on a readable rank for the same source, the roll uses that rank. Copper Vein and Peacebloom use a prototype rate of 0.5% per node, with a readable player gathering cast and matching node loot required.

Cards are keyed by NPC or object ID. A session remembers each rolled spawn token, including misses, across loot windows and zone transitions. Reloading the interface or relogging starts a fresh session. Sources with no readable identity, empty loot windows, and sources outside the catalog are skipped. Group loot that never exposes the corpse to you may produce no roll. Use a clean logout or reload to check that Forever restores the binder.

## Deadmines and gathering checklist

1. Run `/acb diag` to start the trace. In Westfall, open loot on a Defias Pillager, close the window without taking everything, then reopen it. Expect one `loot` line and an `Already rolled` line. Try a second Pillager and repeat with auto-loot enabled.
2. Loot several Deadmines enemies, including a boss, during ordinary group play. The trace shows an attempted roll even when the card misses. If loot comes up empty or a source is unreadable, note the enemy, loot method and whether auto-loot was on.
3. For the optional personal roll, toggle `/acb boss` on before fighting Edwin VanCleef. Target him while he is alive and keep him targeted through the kill. Loot his corpse afterward if you can. If Forever sends matching readable start and success events and exposes the same boss as a readable corpse at completion, expect one `encounter` or `loot` roll and a deduplication line if the other route also runs. The trial starts disabled and currently matches the English encounter name. In a group it also requires you to be alive in the instance at completion.
4. Mine a Copper Vein or pick Peacebloom. Check for a `gather` roll. Try interrupting a gather before it completes and compare with looting a corpse. A corpse dropping ore or herbs follows its creature rule.
5. Use `/acb log` to copy the last 80 trace lines. The trace omits raw spawn identifiers. Copy it before reloading.

The encounter trial is deliberately narrow. If the required events, boss token or corpse are absent at completion, the regular loot route still applies. Loot attribution, gathering spell payloads, boss eligibility, and SavedVariables restoration need a live pass on the launch client.

## Pop-ups and shiny cards

When a card is added to the binder, a pop-up shows the card with a sound: **New card**, **Duplicate**, **Shiny card!** or **Received in trade**. Pop-ups queue, pause under the mouse, open the binder when left-clicked and close on right-click. `/acb popup` turns them on or off, and `/acb popup test` shows a sample so you can check the look and sound.

The first copy of each card you find has a 1 in 20 chance of being a shiny copy, shown with a foil sheen, a sweep of light and a cyan trim. You can own one shiny per card. Trades never move a shiny copy, so a shiny stays with the player who found it. The sound kit names are looked up when the pop-up plays and skipped if this client does not have them, so listen for a sound on the first test.

## Bad-luck safety net

Every card has a miss counter for its source. When a source has missed 2.5 times its expected number of attempts, the next attempt is guaranteed: the 500th for a 0.5% card, the 250th for 1% and the 50th for 5%. The counter resets on a drop. The tooltip hint and the log show progress. Change or switch off `ACB.pityFactor` in `Catalog.lua` (0 turns it off).

## Hints

Mob and node tooltips add a line saying whether the card is in your binder, its chance, and the safety-net progress. In the binder, a missing card's page says where to find it. `/acb hints` turns the tooltip lines off. Check that the line appears on a Westfall Defias Pillager, a Foe Reaper 4000 and a Copper Vein.

## Sets, titles and the wanted list

Each set has a progress bar in the folio and the index. Finishing a set shows a **Set complete** pop-up and earns a title (Defias Delver, Westfall Warden, Fieldhand). The chosen title shows in the binder header; `/acb title` lists them and `/acb title <number>` picks one. Missing cards have an **Add to wanted list** button on their page.

## Sharing

- Right-click a player: **Offer a card trade** opens the Trade tab with their name filled in, and **View their binder** asks for a read-only copy of their collection. `/acb view <name>` does the same. `/acb privacy` stops others viewing yours.
- **Share lists** in the trade window sends your spare cards and your wanted cards to your partner. The window then shows which of their spares you need and which of yours they want. **History** lists your last trades.
- **Link in chat** on a card you own (or `/acb link <name>`) puts a clickable card link in chat. Clicking a link opens the card at a readable size.
- If a right-click entry or a link click does nothing, report which; both use client menu and hyperlink hooks that need a live check.

## Trading

Both players need this version and at least one duplicate each. Meet outdoors and out of combat, open `/acb trade`, then enter each other's character name. Use `Name-Realm` if needed.

1. One player clicks **Listen**. The other chooses a duplicate with **<** or **>** and clicks **Send offer**.
2. The listener chooses a different duplicate and clicks **Send reply**.
3. Review the two displayed cards and click **Accept trade** on both clients. Each side's panel turns green when it accepts. When both have accepted, each client gives away its spare copy and adds the card it received. If a message was missed, use **Resend last step**; a client that already finished answers it. If both players started as the sender or the trade expired, click **Cancel** on both clients and begin again.

This release exchanges offers and confirmations over addon whispers and applies the swap on each client. The two-player transport needs a live pass. Trading runs on trust: collection data is local and editable, so each client only checks its own spare copy, and a client that is modified can keep both cards.

## References

- Forever's exported [loot events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/LootDocumentation.lua), [unit and cast events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua), [encounter events](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncounterInfoDocumentation.lua), and [addon messaging APIs](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua).
- The Forever beta [loot-source report](https://eu.forums.blizzard.com/en/wow/t/feature-request-area-aoe-looting-for-multiple-corpses/633131) and [GUID format notes](https://warcraft.wiki.gg/wiki/GUID) informed the loot-source and session deduplication assumptions.
- Catalog cross-checks used the [Forever Deadmines journal](https://www.wowhead.com/forever/dungeon-journal/the-deadmines), [Miner Johnson observation](https://wowforever.ninja/npcs/3586-miner-johnson/), [Foe Reaper 4000 records](https://www.wowhead.com/forever/npcs/min-level:19/max-level:20), [Copper Vein](https://www.wowhead.com/forever/object=1731/copper-vein), and [Peacebloom](https://www.wowhead.com/forever/object=1618/peacebloom).
